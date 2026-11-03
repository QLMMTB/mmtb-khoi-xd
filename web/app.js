/* Quản lý MMTB Khối XD – ứng dụng web (HTML/JS thuần + Supabase) */
"use strict";
const cfg = window.MMTB_CONFIG || {};
const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
const $ = s => document.querySelector(s);
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const fmt = n => (n == null || n === "" ? "–" : Number(n).toLocaleString("vi-VN"));
const STATUS = {
  lam_viec: ["Đang làm việc", "s-lam"], ton: ["Tồn (chờ việc)", "s-ton"], hong: ["Hỏng", "s-hong"], sua_chua: ["Đang sửa chữa", "s-sua"],
  van_chuyen: ["Đang vận chuyển", "s-vc"], cho_tra: ["Chờ trả NCC", "s-tra"], da_tra: ["Đã trả / thanh lý", "s-tra"]
};
const ROLE = { bql: "Cán bộ thiết bị BQLXD", truong_ban: "Trưởng BQLXD", qltb: "P.QLTB", lanh_dao: "Lãnh đạo Khối XD", admin: "Quản trị" };
const STEPS = ["Lập đề nghị", "Ban đi đồng ý", "P.QLTB kiểm tra", "LĐ Khối duyệt", "Giao nhận", "Ban nhận xác nhận"];
const pill = t => `<span class="pill ${STATUS[t]?.[1] || ""}">${STATUS[t]?.[0] || esc(t)}</span>`;
const today = () => new Date().toISOString().slice(0, 10);
const vnDate = d => (d ? d.slice(0, 10).split("-").reverse().join("/") : "–");
function months(n = 8) {
  const d = new Date(); d.setDate(1); const out = [];
  for (let i = 0; i < n; i++) { const x = new Date(d.getFullYear(), d.getMonth() + i, 1);
    out.push({ iso: `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, "0")}-01`, lab: `T${x.getMonth() + 1}/${String(x.getFullYear()).slice(2)}` }); }
  return out;
}
function toast(t, bad) { const el = $("#toast"); el.textContent = t; el.style.background = bad ? "var(--bad)" : ""; el.hidden = false; clearTimeout(toast.h); toast.h = setTimeout(() => el.hidden = true, bad ? 5000 : 2500); }
function fail(e) { console.error(e); toast(e?.message || String(e), true); }
async function q(p) { const { data, error } = await p; if (error) throw error; return data; }
async function all(table, select, build = x => x) {           // đọc hết (vượt giới hạn 1000 dòng/lần)
  let out = [], from = 0; const step = 1000;
  for (;;) { const rows = await q(build(sb.from(table).select(select)).range(from, from + step - 1)); out = out.concat(rows); if (rows.length < step) return out; from += step; }
}
async function rpc(fn, args) { const { data, error } = await sb.rpc(fn, args); if (error) throw error; return data; }

/* ---------- trạng thái phiên ---------- */
const S = { me: null, bans: [], banMap: {}, loai: [], loaiMap: {}, viewBan: null };
const canEditBan = () => ["bql", "truong_ban"].includes(S.me.vai_tro) && S.viewBan === S.me.ban_id;
const isQltb = () => ["qltb", "admin"].includes(S.me.vai_tro);
const banTen = id => S.banMap[id]?.ten || id;
const loaiTen = id => S.loaiMap[id]?.ten_chuan || id;

const TABS = [["tongquan", "Tổng quan"], ["capnhat", "Cập nhật hằng ngày"], ["tiendo", "Nhu cầu theo tiến độ"], ["laimay", "Lái máy (LXLM)"],
  ["ton", "Máy tồn toàn Khối"], ["hong", "Báo hỏng"], ["dieuchuyen", "Điều chuyển & phê duyệt"], ["danhmuc", "Danh mục chuẩn hóa"]];
let tab = (location.hash.slice(1) && TABS.some(t => t[0] === location.hash.slice(1))) ? location.hash.slice(1) : "tongquan";

async function boot() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { $("#hdr").hidden = true; $("#view").innerHTML = ""; $("#login").hidden = false; return; }
  $("#login").hidden = true;
  try {
    S.me = await q(sb.from("nguoi_dung").select("*").eq("id", session.user.id).maybeSingle());
    if (!S.me) { $("#view").innerHTML = `<p class="sub">Tài khoản ${esc(session.user.email)} chưa được phân vai trò. Liên hệ quản trị hệ thống.</p><button id="lo2">Đăng xuất</button>`; $("#lo2").onclick = logout; return; }
    S.bans = await q(sb.from("ban").select("*").order("ten")); S.banMap = Object.fromEntries(S.bans.map(b => [b.id, b]));
    S.loai = await all("loai_may", "*", x => x.order("ten_chuan")); S.loaiMap = Object.fromEntries(S.loai.map(l => [l.id, l]));
    S.viewBan = S.me.ban_id || S.bans[0]?.id;
    $("#me").textContent = `${S.me.ho_ten || S.me.email} · ${ROLE[S.me.vai_tro]}${S.me.ban_id ? " · " + banTen(S.me.ban_id) : ""}`;
    $("#ban").innerHTML = S.bans.map(b => `<option value="${esc(b.id)}" ${b.id === S.viewBan ? "selected" : ""}>${esc(b.ten)}</option>`).join("");
    $("#hdr").hidden = false; render();
  } catch (e) { fail(e); }
}
async function logout() { await sb.auth.signOut(); location.hash = ""; boot(); }
$("#login").onsubmit = async e => {
  e.preventDefault(); $("#loginErr").textContent = "";
  const { error } = await sb.auth.signInWithPassword({ email: $("#email").value.trim(), password: $("#pw").value });
  if (error) $("#loginErr").textContent = "Sai email hoặc mật khẩu."; else boot();
};
$("#logout").onclick = logout;
$("#ban").onchange = () => { S.viewBan = $("#ban").value; render(); };
window.addEventListener("hashchange", () => { const h = location.hash.slice(1); if (TABS.some(t => t[0] === h)) { tab = h; render(); } });

function renderTabs() {
  $("#tabs").innerHTML = TABS.map(([k, t]) => `<button class="tab" role="tab" aria-selected="${k === tab}" data-k="${k}">${t}</button>`).join("");
  $("#tabs").querySelectorAll(".tab").forEach(b => b.onclick = () => { tab = b.dataset.k; location.hash = tab; render(); });
}
async function render() {
  renderTabs(); $("#view").innerHTML = `<div class="loading">Đang tải…</div>`;
  try { await ({ tongquan: vTongQuan, capnhat: vCapNhat, tiendo: vTienDo, laimay: vLaiMay, ton: vTon, hong: vHong, dieuchuyen: vDC, danhmuc: vDM })[tab](); }
  catch (e) { fail(e); $("#view").innerHTML = `<p class="err">Không tải được dữ liệu: ${esc(e.message || e)}</p>`; }
}

/* ---------- biểu đồ cột đơn giản (SVG) ---------- */
function svgBars(title, labels, need, have, haveLabel) {
  const W = 720, H = 230, L = 52, R = 16, T = 34, B = 36, mx = Math.max(1, ...need, ...(Array.isArray(have) ? have : [have])) * 1.1, bw = (W - L - R) / labels.length;
  const y = v => T + (H - T - B) * (1 - v / mx); const ticks = [0, .25, .5, .75, 1].map(f => Math.round(mx * f));
  const hv = i => (Array.isArray(have) ? have[i] : have);
  return `<div class="scroll"><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(title)}" style="width:100%;min-width:520px;height:auto;font-family:var(--font)">
  <text x="${L}" y="18" font-size="13" font-weight="600" fill="var(--ink)">${esc(title)}</text>
  ${ticks.map(t => `<line x1="${L}" x2="${W - R}" y1="${y(t)}" y2="${y(t)}" stroke="var(--line)"/><text x="${L - 6}" y="${y(t) + 4}" font-size="11" text-anchor="end" fill="var(--muted)">${fmt(t)}</text>`).join("")}
  ${need.map((v, i) => { const x = L + i * bw + bw * .18, w = bw * .64, over = v > hv(i); return `<rect x="${x}" y="${y(v)}" width="${w}" height="${Math.max(0, y(0) - y(v))}" rx="2" fill="${over ? "var(--warn)" : "var(--accent)"}" opacity=".85"><title>${labels[i]}: ${fmt(v)}</title></rect><text x="${x + w / 2}" y="${y(v) - 5}" font-size="11" text-anchor="middle" fill="var(--ink)">${fmt(Math.round(v))}</text><text x="${x + w / 2}" y="${H - 14}" font-size="11" text-anchor="middle" fill="var(--muted)">${labels[i]}</text>`; }).join("")}
  ${Array.isArray(have) ? `<polyline fill="none" stroke="var(--bad)" stroke-width="2" stroke-dasharray="6 4" points="${have.map((v, i) => `${L + i * bw + bw / 2},${y(v)}`).join(" ")}"/>` : `<line x1="${L}" x2="${W - R}" y1="${y(have)}" y2="${y(have)}" stroke="var(--bad)" stroke-width="2" stroke-dasharray="6 4"/>`}
  <text x="${W - R}" y="${y(Array.isArray(have) ? have.at(-1) : have) - 6}" font-size="11.5" text-anchor="end" font-weight="600" fill="var(--bad)">${esc(haveLabel)}</text>
  </svg></div><p class="sub" style="margin-top:4px">Cột cam = tháng nhu cầu vượt nguồn cung (đường đỏ).</p>`;
}

/* ---------- Tổng quan ---------- */
async function vTongQuan() {
  const [cc, chua, hong, ncung, dc, xn] = await Promise.all([
    q(sb.from("v_cung_cau_khoi").select("*")), q(sb.from("v_ban_chua_cap_nhat").select("*")),
    q(sb.from("phieu_hong").select("id,du_kien_xong").is("dong_luc", null)), all("v_nguon_cung", "*"),
    q(sb.from("phieu_dieu_chuyen").select("id").lt("buoc", 6).eq("tu_choi", false)),
    q(sb.from("xac_nhan_ngay").select("ban_id,ngay").gte("ngay", new Date(Date.now() - 14 * 864e5).toISOString().slice(0, 10)))]);
  const tot = ncung.reduce((a, r) => ({ csh: a.csh + r.csh, thue: a.thue + r.thue, ton: a.ton + r.ton, hong: a.hong + r.hong }), { csh: 0, thue: 0, ton: 0, hong: 0 });
  const quaHan = hong.filter(h => h.du_kien_xong && h.du_kien_xong < today()).length;
  const lastXn = {}; xn.forEach(x => { if (!lastXn[x.ban_id] || x.ngay > lastXn[x.ban_id]) lastXn[x.ban_id] = x.ngay; });
  const perBan = {}; ncung.forEach(r => { const p = perBan[r.ban_id] ||= { may: 0, ton: 0, hong: 0 }; p.may += r.csh + r.thue; p.ton += r.ton; p.hong += r.hong; });
  const c0 = cc[0];
  $("#view").innerHTML = `
  <h2>Cung cầu MMTB toàn Khối</h2>
  <p class="sub">Nhu cầu = tổng nhu cầu các ban (theo định mức + nhập tay) × hệ số; nguồn cung = máy Tập đoàn + máy thuê đang dùng được + máy mua sắp về (cộng dồn).</p>
  <div class="grid">
    <div class="tile"><div class="k">Máy Tập đoàn / máy thuê dùng được</div><div class="v">${fmt(tot.csh)} / ${fmt(tot.thue)}</div><div class="d">không gồm máy hỏng, sửa chữa, chờ trả</div></div>
    <div class="tile"><div class="k">Nhu cầu ${c0 ? vnDate(c0.thang).slice(3) : ""}</div><div class="v">${c0 ? fmt(Math.round(c0.nhu_cau)) : "–"}</div><div class="d">${c0 ? "máy, đã nhân hệ số" : "chưa có ban nào nhập kế hoạch"}</div></div>
    <div class="tile ${c0 && c0.thua_thieu_giu_thue < 0 ? "bad" : ""}"><div class="k">Thừa / (thiếu) – giữ máy thuê</div><div class="v">${c0 ? fmt(Math.round(c0.thua_thieu_giu_thue)) : "–"}</div><div class="d">tháng đầu</div></div>
    <div class="tile ${c0 && c0.thua_thieu_tra_thue < 0 ? "warn" : ""}"><div class="k">Thừa / (thiếu) – trả hết máy thuê</div><div class="v">${c0 ? fmt(Math.round(c0.thua_thieu_tra_thue)) : "–"}</div><div class="d">tháng đầu</div></div>
  </div>
  ${cc.length ? `<div class="panel">${svgBars("Nhu cầu MMTB và nguồn cung theo tháng (máy)", cc.map(r => "T" + Number(r.thang.slice(5, 7)) + "/" + r.thang.slice(2, 4)), cc.map(r => +r.nhu_cau), cc.map(r => +r.csh + +r.thue + +r.sap_ve_luy_ke), "Nguồn cung (giữ máy thuê)")}</div>` : ""}
  <h2>Việc cần xử lý hôm nay</h2>
  <div class="grid">
    <div class="tile ${chua.length ? "warn" : ""}"><div class="k">Ban chưa xác nhận số liệu hôm nay</div><div class="v">${chua.length}/${S.bans.filter(b => b.dang_thi_cong).length}</div><div class="d">xem bảng dưới</div></div>
    <div class="tile ${quaHan ? "bad" : ""}"><div class="k">Máy hỏng quá hạn sửa</div><div class="v">${quaHan}</div><div class="d">trong ${hong.length} phiếu báo hỏng đang mở</div></div>
    <div class="tile"><div class="k">Máy tồn có thể điều chuyển</div><div class="v">${fmt(tot.ton)}</div><div class="d">xem tab Máy tồn toàn Khối</div></div>
    <div class="tile"><div class="k">Đề nghị điều chuyển đang xử lý</div><div class="v">${dc.length}</div><div class="d">xem tab Điều chuyển</div></div>
  </div>
  <div class="panel scroll"><table><thead><tr><th>Ban</th><th class="num">Số máy dùng được</th><th class="num">Tồn</th><th class="num">Hỏng/sửa</th><th>Xác nhận gần nhất</th></tr></thead><tbody>
  ${S.bans.filter(b => b.dang_thi_cong).map(b => { const p = perBan[b.id] || { may: 0, ton: 0, hong: 0 }; const l = lastXn[b.id];
    return `<tr><td>${esc(b.ten)}</td><td class="num">${fmt(p.may)}</td><td class="num">${fmt(p.ton)}</td><td class="num">${fmt(p.hong)}</td><td>${l === today() ? `<span class="pill s-lam">Hôm nay</span>` : `<span class="pill s-sua">${l ? vnDate(l) : "Chưa từng"} – chưa cập nhật</span>`}</td></tr>`; }).join("")}
  </tbody></table></div>`;
}

/* ---------- Cập nhật hằng ngày ---------- */
async function vCapNhat() {
  const b = S.viewBan, edit = canEditBan() || isQltb();
  const [ms, xn, lm] = await Promise.all([
    all("may", "ma,loai_id,so_huu,bien_so,trang_thai", x => x.eq("ban_id", b).order("loai_id").order("ma")),
    q(sb.from("xac_nhan_ngay").select("ngay").eq("ban_id", b).order("ngay", { ascending: false }).limit(1)),
    q(sb.from("lai_may_hien_co").select("so_nguoi").eq("ban_id", b).maybeSingle())]);
  $("#view").innerHTML = `
  <h2>Cập nhật trạng thái máy – ${esc(banTen(b))}</h2>
  <p class="sub">Trạng thái giữ nguyên từ hôm trước; chỉ đổi máy thay đổi, mỗi lần đổi được lưu ngay và ghi nhật ký. Cuối cùng bấm Xác nhận số liệu hôm nay. Máy đang vận chuyển chỉ đổi qua phiếu điều chuyển.</p>
  <div class="panel"><div class="row">
    <span>Xác nhận gần nhất: <b>${xn[0] ? vnDate(xn[0].ngay) : "chưa có"}</b> · ${ms.length} máy</span>
    <input id="q" placeholder="Tìm mã máy, loại máy, biển số" style="flex:1 1 220px">
    ${canEditBan() ? `<label class="sm" for="lm">Lái máy có mặt</label><input id="lm" type="number" min="0" value="${lm?.so_nguoi ?? ""}" style="width:90px"><button class="primary" id="xn">Xác nhận số liệu hôm nay</button>` : `<span class="muted right">${edit ? "P.QLTB sửa được trạng thái" : "Chỉ xem"}</span>`}
  </div></div>
  <div class="panel scroll"><table><thead><tr><th>Mã máy</th><th>Loại máy (chuẩn hóa)</th><th>Sở hữu</th><th>Biển số</th><th>Trạng thái</th></tr></thead><tbody id="tb"></tbody></table></div>`;
  const draw = () => {
    const s = ($("#q").value || "").toLowerCase();
    const rows = ms.filter(m => !s || m.ma.toLowerCase().includes(s) || loaiTen(m.loai_id).toLowerCase().includes(s) || (m.bien_so || "").toLowerCase().includes(s)).slice(0, 500);
    $("#tb").innerHTML = rows.map(m => `<tr><td class="code">${esc(m.ma)}</td><td>${esc(loaiTen(m.loai_id))}</td><td>${m.so_huu === "CSH" ? "Tập đoàn" : "Thuê"}</td><td class="code">${esc(m.bien_so || "–")}</td>
      <td>${edit && m.trang_thai !== "van_chuyen" ? `<select data-ma="${esc(m.ma)}" aria-label="Trạng thái ${esc(m.ma)}">${Object.keys(STATUS).filter(k => k !== "van_chuyen").map(k => `<option value="${k}" ${k === m.trang_thai ? "selected" : ""}>${STATUS[k][0]}</option>`).join("")}</select>` : pill(m.trang_thai)}</td></tr>`).join("")
      + (rows.length === 500 ? `<tr><td colspan="5" class="muted">Hiện 500 máy đầu – gõ tìm để lọc.</td></tr>` : "");
    $("#tb").querySelectorAll("select").forEach(sel => sel.onchange = async () => {
      const m = ms.find(x => x.ma === sel.dataset.ma); const old = m.trang_thai;
      try { await rpc("cap_nhat_trang_thai", { p_ma: m.ma, p_tt: sel.value, p_ly_do: "Cập nhật hằng ngày" }); m.trang_thai = sel.value; sel.closest("tr").classList.add("changed");
        if (sel.value === "hong") toast("Đã đổi sang Hỏng – nhớ lập phiếu ở tab Báo hỏng"); }
      catch (e) { sel.value = old; fail(e); }
    });
  };
  $("#q").oninput = draw; draw();
  if ($("#xn")) $("#xn").onclick = async () => {
    try { const v = $("#lm").value; await rpc("xac_nhan_ngay_ban", { p_so_lai_may: v === "" ? null : +v }); toast(`Đã xác nhận số liệu ${banTen(b)} hôm nay`); vCapNhat(); } catch (e) { fail(e); }
  };
}

/* ---------- Nhu cầu theo tiến độ ---------- */
async function vTienDo() {
  const b = S.viewBan, edit = canEditBan() || isQltb(), M = months(8);
  const [cv, hm, dm, nc, cung, ntay] = await Promise.all([
    q(sb.from("cong_viec").select("*").eq("ban_id", b).order("id")), q(sb.from("hang_muc").select("*").order("ten")),
    q(sb.from("dinh_muc").select("*")), q(sb.from("v_nhu_cau").select("*").eq("ban_id", b).gte("thang", M[0].iso).lte("thang", M.at(-1).iso)),
    q(sb.from("v_nguon_cung").select("*").eq("ban_id", b)), q(sb.from("nhu_cau_nhap_tay").select("*").eq("ban_id", b))]);
  const hmMap = Object.fromEntries(hm.map(h => [h.id, h]));
  const byLoai = {}; nc.forEach(r => { (byLoai[r.loai_id] ||= Array(M.length).fill(0))[M.findIndex(m => m.iso === r.thang)] += +r.so_may; });
  const co = Object.fromEntries(cung.map(r => [r.loai_id, r.csh + r.thue]));
  const opt = (sel) => M.map((m, i) => `<option value="${m.iso}" ${m.iso === sel ? "selected" : ""}>${m.lab}</option>`).join("");
  const banRow = S.banMap[b];
  $("#view").innerHTML = `
  <h2>Nhu cầu MMTB theo tiến độ – ${esc(banTen(b))}</h2>
  <p class="sub">Số máy/tháng = khối lượng tháng ÷ (năng suất máy/ca × số ca/tháng × hệ số ca), làm tròn lên. Máy đặc thù không tính được theo định mức thì nhập tay ở cuối trang.</p>
  <div class="panel">
    <div class="row" style="margin-bottom:8px"><b>Hạng mục và khối lượng</b><label class="sm right" for="hsca">Hệ số ca</label>
      <select id="hsca" ${canEditBan() ? "" : "disabled"}>${[1, 1.5, 2].map(v => `<option ${v === +banRow.he_so_ca ? "selected" : ""}>${v}</option>`).join("")}</select></div>
    <div class="scroll"><table><thead><tr><th>Hạng mục</th><th class="num">Khối lượng</th><th>Đơn vị</th><th>Từ tháng</th><th>Đến tháng</th><th></th></tr></thead><tbody>
    ${cv.map(c => `<tr><td>${esc(hmMap[c.hang_muc_id]?.ten)}</td><td class="num">${edit ? `<input id="kl-${c.id}" class="kl" data-id="${c.id}" type="number" min="0" value="${c.khoi_luong}" style="width:130px;text-align:right">` : fmt(c.khoi_luong)}</td><td>${esc(hmMap[c.hang_muc_id]?.don_vi)}</td>
      <td>${edit ? `<select class="tu" id="tu-${c.id}" data-id="${c.id}">${opt(c.tu_thang)}</select>` : vnDate(c.tu_thang).slice(3)}</td><td>${edit ? `<select class="den" id="den-${c.id}" data-id="${c.id}">${opt(c.den_thang)}</select>` : vnDate(c.den_thang).slice(3)}</td>
      <td>${edit ? `<button class="ghost" data-del="${c.id}">Xóa</button>` : ""}</td></tr>`).join("") || `<tr><td colspan="6" class="muted">Chưa có hạng mục.</td></tr>`}
    </tbody></table></div>
    ${edit ? `<div class="row" style="margin-top:10px"><select id="newhm" aria-label="Hạng mục">${hm.map(h => `<option value="${h.id}">${esc(h.ten)}</option>`).join("")}</select><input id="newkl" type="number" min="0" placeholder="Khối lượng" style="width:140px">
      <select id="newtu" aria-label="Từ tháng">${opt(M[0].iso)}</select><select id="newden" aria-label="Đến tháng">${opt(M[3].iso)}</select><button id="add">Thêm hạng mục</button></div>` : ""}
  </div>
  <div class="panel scroll"><table><thead><tr><th>Loại máy</th>${M.map(m => `<th class="num">${m.lab}</th>`).join("")}<th class="num">Đang có ở ban</th><th class="num">Thiếu lúc cao điểm</th></tr></thead><tbody>
    ${Object.entries(byLoai).map(([l, arr]) => { const c = co[l] || 0, pk = Math.max(...arr), th = pk - c;
      return `<tr><td>${esc(loaiTen(+l))}</td>${arr.map(v => `<td class="num ${v > c ? "" : "muted"}">${v ? fmt(v) : "–"}</td>`).join("")}<td class="num">${c}</td><td class="num">${th > 0 ? `<span class="pill s-hong">${th}</span>` : `<span class="pill s-lam">đủ</span>`}</td></tr>`; }).join("") || `<tr><td colspan="${M.length + 3}" class="muted">Chưa có nhu cầu.</td></tr>`}
  </tbody></table></div>
  <h2>Nhu cầu nhập tay (máy đặc thù)</h2>
  <div class="panel scroll"><table><thead><tr><th>Loại máy</th><th>Tháng</th><th class="num">Số máy</th><th></th></tr></thead><tbody>
    ${ntay.map(r => `<tr><td>${esc(loaiTen(r.loai_id))}</td><td>${vnDate(r.thang).slice(3)}</td><td class="num">${fmt(r.so_may)}</td><td>${edit ? `<button class="ghost" data-ntdel="${r.loai_id}|${r.thang}">Xóa</button>` : ""}</td></tr>`).join("") || `<tr><td colspan="4" class="muted">Không có.</td></tr>`}
  </tbody></table>
  ${edit ? `<div class="row" style="margin-top:10px"><select id="ntloai" aria-label="Loại máy">${S.loai.map(l => `<option value="${l.id}">${esc(l.ten_chuan)}</option>`).join("")}</select><select id="ntthang" aria-label="Tháng">${opt(M[0].iso)}</select><input id="ntso" type="number" min="0" step="1" placeholder="Số máy" style="width:100px"><button id="ntadd">Thêm</button></div>` : ""}</div>
  <h2>Định mức năng suất và lái máy</h2>
  <p class="sub">${isQltb() ? "Bạn là P.QLTB: sửa năng suất/lái máy rồi bấm ra ngoài ô để lưu; mọi ban tính lại ngay." : "Chỉ P.QLTB sửa được định mức."}</p>
  <div class="panel scroll"><table><thead><tr><th>Hạng mục</th><th>Loại máy</th><th class="num">Năng suất/máy/ca</th><th>Đơn vị</th><th class="num">Lái máy/máy/ca</th></tr></thead><tbody>
  ${dm.map(d => `<tr><td>${esc(hmMap[d.hang_muc_id]?.ten)}</td><td>${esc(loaiTen(d.loai_id))}</td>
    <td class="num">${isQltb() ? `<input class="dm" id="ns-${d.hang_muc_id}-${d.loai_id}" data-h="${d.hang_muc_id}" data-l="${d.loai_id}" data-f="nang_suat_ca" type="number" min="0.01" step="any" value="${d.nang_suat_ca}" style="width:100px;text-align:right">` : fmt(d.nang_suat_ca)}</td>
    <td>${esc(hmMap[d.hang_muc_id]?.don_vi)}</td><td class="num">${isQltb() ? `<input class="dm" id="lai-${d.hang_muc_id}-${d.loai_id}" data-h="${d.hang_muc_id}" data-l="${d.loai_id}" data-f="lai_may_ca" type="number" min="0" step="0.5" value="${d.lai_may_ca}" style="width:70px;text-align:right">` : d.lai_may_ca}</td></tr>`).join("")}
  </tbody></table></div>`;
  const reload = () => vTienDo().catch(fail);
  const upd = async (id, patch) => { try { await q(sb.from("cong_viec").update(patch).eq("id", id)); reload(); } catch (e) { fail(e); } };
  document.querySelectorAll(".kl").forEach(x => x.onchange = () => upd(+x.dataset.id, { khoi_luong: Math.max(0, +x.value || 0) }));
  document.querySelectorAll(".tu").forEach(x => x.onchange = () => { const c = cv.find(y => y.id === +x.dataset.id); upd(c.id, { tu_thang: x.value, den_thang: c.den_thang < x.value ? x.value : c.den_thang }); });
  document.querySelectorAll(".den").forEach(x => x.onchange = () => { const c = cv.find(y => y.id === +x.dataset.id); upd(c.id, { den_thang: x.value, tu_thang: c.tu_thang > x.value ? x.value : c.tu_thang }); });
  document.querySelectorAll("[data-del]").forEach(x => x.onclick = async () => { try { await q(sb.from("cong_viec").delete().eq("id", +x.dataset.del)); reload(); } catch (e) { fail(e); } });
  if ($("#add")) $("#add").onclick = async () => { const kl = +$("#newkl").value; if (!kl) return toast("Nhập khối lượng", true);
    let tu = $("#newtu").value, den = $("#newden").value; if (den < tu) [tu, den] = [den, tu];
    try { await q(sb.from("cong_viec").insert({ ban_id: b, hang_muc_id: +$("#newhm").value, khoi_luong: kl, tu_thang: tu, den_thang: den })); toast("Đã thêm hạng mục"); reload(); } catch (e) { fail(e); } };
  if ($("#hsca") && canEditBan()) $("#hsca").onchange = async () => { try { await rpc("dat_he_so_ca", { p_he_so: +$("#hsca").value }); S.banMap[b].he_so_ca = +$("#hsca").value; reload(); } catch (e) { fail(e); } };
  if ($("#ntadd")) $("#ntadd").onclick = async () => { const so = +$("#ntso").value; if (!(so >= 0) || $("#ntso").value === "") return toast("Nhập số máy", true);
    try { await q(sb.from("nhu_cau_nhap_tay").upsert({ ban_id: b, loai_id: +$("#ntloai").value, thang: $("#ntthang").value, so_may: so })); reload(); } catch (e) { fail(e); } };
  document.querySelectorAll("[data-ntdel]").forEach(x => x.onclick = async () => { const [l, t] = x.dataset.ntdel.split("|");
    try { await q(sb.from("nhu_cau_nhap_tay").delete().eq("ban_id", b).eq("loai_id", +l).eq("thang", t)); reload(); } catch (e) { fail(e); } });
  document.querySelectorAll(".dm").forEach(x => x.onchange = async () => {
    try { await q(sb.from("dinh_muc").update({ [x.dataset.f]: +x.value }).eq("hang_muc_id", +x.dataset.h).eq("loai_id", +x.dataset.l)); toast("Đã lưu định mức"); reload(); } catch (e) { fail(e); } });
}

/* ---------- Lái máy ---------- */
async function vLaiMay() {
  const b = S.viewBan, M = months(8);
  const [nc, lm] = await Promise.all([all("v_nhu_cau", "ban_id,loai_id,thang,so_lai_may", x => x.gte("thang", M[0].iso).lte("thang", M.at(-1).iso)), q(sb.from("lai_may_hien_co").select("*"))]);
  const idx = t => M.findIndex(m => m.iso === t);
  const need = Array(M.length).fill(0), tot = Array(M.length).fill(0), byLoai = {}, byBan = {};
  nc.forEach(r => { const i = idx(r.thang); if (i < 0) return; tot[i] += +r.so_lai_may; (byBan[r.ban_id] ||= Array(M.length).fill(0))[i] += +r.so_lai_may;
    if (r.ban_id === b) { need[i] += +r.so_lai_may; (byLoai[r.loai_id] ||= Array(M.length).fill(0))[i] += +r.so_lai_may; } });
  const lmMap = Object.fromEntries(lm.map(x => [x.ban_id, x.so_nguoi])); const have = lmMap[b] || 0; const haveTot = lm.reduce((a, x) => a + x.so_nguoi, 0);
  const pk = Math.max(0, ...need);
  $("#view").innerHTML = `
  <h2>Công nhân lái máy (LXLM) – ${esc(banTen(b))}</h2>
  <p class="sub">Nhu cầu = số máy cần × định mức lái máy/máy/ca × hệ số ca (từ tab Nhu cầu theo tiến độ). Số hiện có do ban cập nhật.</p>
  <div class="grid">
    <div class="tile"><div class="k">Lái máy hiện có</div><div class="v">${fmt(have)}</div><div class="d">${canEditBan() || isQltb() ? `<span class="row" style="gap:6px"><input id="lmv" type="number" min="0" value="${have}" style="width:90px"><button id="lmok">Cập nhật</button></span>` : "người"}</div></div>
    <div class="tile ${pk > have ? "warn" : ""}"><div class="k">Cần lúc cao điểm</div><div class="v">${fmt(pk)}</div><div class="d">người${pk ? ", tháng " + M[need.indexOf(pk)].lab : ""}</div></div>
    <div class="tile ${pk > have ? "bad" : ""}"><div class="k">Thiếu lúc cao điểm</div><div class="v">${fmt(Math.max(0, pk - have))}</div><div class="d">người cần tuyển hoặc điều động</div></div>
  </div>
  <div class="panel">${svgBars(`Nhu cầu lái máy theo tháng – ${banTen(b)} (người)`, M.map(m => m.lab), need, have, "Hiện có: " + fmt(have))}</div>
  <div class="panel scroll"><table><thead><tr><th>Loại máy</th>${M.map(m => `<th class="num">${m.lab}</th>`).join("")}</tr></thead><tbody>
    ${Object.entries(byLoai).map(([l, a]) => `<tr><td>${esc(loaiTen(+l))}</td>${a.map(v => `<td class="num">${v || "–"}</td>`).join("")}</tr>`).join("")}
    <tr><td><b>Tổng lái máy</b></td>${need.map(v => `<td class="num"><b>${fmt(v)}</b></td>`).join("")}</tr></tbody></table></div>
  <h2>Toàn Khối</h2>
  <div class="panel">${svgBars("Nhu cầu lái máy toàn Khối theo tháng (người)", M.map(m => m.lab), tot, haveTot, "Hiện có toàn Khối: " + fmt(haveTot))}</div>
  <div class="panel scroll"><table><thead><tr><th>Ban</th><th class="num">Hiện có</th>${M.map(m => `<th class="num">${m.lab}</th>`).join("")}</tr></thead><tbody>
    ${Object.entries(byBan).map(([id, a]) => { const h = lmMap[id] || 0; return `<tr><td>${esc(banTen(id))}</td><td class="num">${fmt(h)}</td>${a.map(v => `<td class="num">${v > h ? `<span class="pill s-sua">${fmt(v)}</span>` : fmt(v)}</td>`).join("")}</tr>`; }).join("")}
    <tr><td><b>Tổng</b></td><td class="num"><b>${fmt(haveTot)}</b></td>${tot.map(v => `<td class="num"><b>${fmt(v)}</b></td>`).join("")}</tr></tbody></table></div>`;
  if ($("#lmok")) $("#lmok").onclick = async () => { try { await q(sb.from("lai_may_hien_co").upsert({ ban_id: b, so_nguoi: Math.max(0, +$("#lmv").value || 0), cap_nhat_luc: new Date().toISOString() })); toast("Đã cập nhật số lái máy"); vLaiMay(); } catch (e) { fail(e); } };
}

/* ---------- Máy tồn ---------- */
async function vTon() {
  const ton = await all("may", "ma,loai_id,so_huu,ban_id", x => x.eq("trang_thai", "ton").order("loai_id"));
  const loai = [...new Set(ton.map(m => m.loai_id))].sort((a, b) => loaiTen(a).localeCompare(loaiTen(b), "vi"));
  const canAsk = canEditBan() || isQltb();
  $("#view").innerHTML = `
  <h2>Máy tồn toàn Khối</h2>
  <p class="sub">Máy tốt đang chờ việc ở các ban. Ban thiếu máy xin điều chuyển từ đây trước khi đề xuất thuê hoặc mua.</p>
  <div class="panel row"><label class="sm" for="fl">Loại máy</label><select id="fl"><option value="">Tất cả (${ton.length} máy)</option>${loai.map(l => `<option value="${l}">${esc(loaiTen(l))} (${ton.filter(m => m.loai_id === l).length})</option>`).join("")}</select></div>
  <form class="panel" id="xin" hidden>
    <b id="xinTitle"></b>
    <div class="form" style="margin-top:8px"><label>Ngày cần máy<input id="xinNgay" type="date" required></label><label>Chi phí vận chuyển dự kiến (đồng)<input id="xinCp" type="number" min="0" step="1000000"></label></div>
    <label class="sm" style="display:block;margin-top:8px">Lý do / hạng mục sử dụng<textarea id="xinLy" required></textarea></label>
    <div class="row" style="margin-top:8px"><button class="primary">Gửi đề nghị</button><button type="button" class="ghost" id="xinHuy">Hủy</button></div>
  </form>
  <div class="panel scroll"><table><thead><tr><th>Mã máy</th><th>Loại máy</th><th>Đang ở ban</th><th>Sở hữu</th><th></th></tr></thead><tbody id="tb"></tbody></table></div>`;
  let pick = null;
  const draw = () => { const f = +$("#fl").value || 0;
    $("#tb").innerHTML = ton.filter(m => !f || m.loai_id === f).slice(0, 500).map(m => `<tr><td class="code">${esc(m.ma)}</td><td>${esc(loaiTen(m.loai_id))}</td><td>${esc(banTen(m.ban_id))}</td><td>${m.so_huu === "CSH" ? "Tập đoàn" : "Thuê"}</td>
      <td>${m.ban_id === S.viewBan ? `<span class="muted">Máy của ban đang xem</span>` : canAsk ? `<button data-ma="${esc(m.ma)}">Xin về ${esc(banTen(S.viewBan))}</button>` : ""}</td></tr>`).join("") || `<tr><td colspan="5" class="muted">Không có máy tồn.</td></tr>`;
    $("#tb").querySelectorAll("button").forEach(x => x.onclick = () => { pick = ton.find(m => m.ma === x.dataset.ma); $("#xin").hidden = false;
      $("#xinTitle").textContent = `Đề nghị điều chuyển ${pick.ma} (${loaiTen(pick.loai_id)}) từ ${banTen(pick.ban_id)} về ${banTen(S.viewBan)}`; $("#xin").scrollIntoView({ behavior: "smooth" }); });
  };
  $("#fl").onchange = draw; draw();
  $("#xinHuy").onclick = () => { $("#xin").hidden = true; };
  $("#xin").onsubmit = async e => { e.preventDefault();
    try { const id = await rpc("de_nghi_dieu_chuyen", { p_ma: pick.ma, p_den_ban: S.viewBan, p_ngay_can: $("#xinNgay").value, p_ly_do: $("#xinLy").value.trim(), p_chi_phi: $("#xinCp").value === "" ? null : +$("#xinCp").value });
      toast(`Đã lập phiếu điều chuyển #${id}`); tab = "dieuchuyen"; location.hash = tab; render(); } catch (err) { fail(err); } };
}

/* ---------- Báo hỏng ---------- */
async function vHong() {
  const b = S.viewBan, edit = canEditBan() || isQltb();
  const [ms, ph] = await Promise.all([all("may", "ma,loai_id,trang_thai", x => x.eq("ban_id", b).neq("trang_thai", "van_chuyen").order("ma")),
    q(sb.from("phieu_hong").select("*").is("dong_luc", null).order("ngay_hong", { ascending: false }))]);
  $("#view").innerHTML = `
  <h2>Báo hỏng</h2>
  <p class="sub">Lập phiếu thì máy tự chuyển sang Hỏng và không tính vào nguồn cung cho đến khi đóng phiếu.</p>
  ${edit ? `<form class="panel" id="f"><div class="form">
    <label>Máy (${esc(banTen(b))})<select id="fm" required>${ms.map(m => `<option value="${esc(m.ma)}">${esc(m.ma)} – ${esc(loaiTen(m.loai_id))}</option>`).join("")}</select></label>
    <label>Mức độ<select id="fmd"><option value="dung_may">Dừng máy</option><option value="van_chay">Vẫn chạy được</option></select></label>
    <label>Dự kiến sửa xong<input id="fk" type="date"></label>
    <label>Chi phí dự toán (đồng)<input id="fc" type="number" min="0" step="500000"></label></div>
    <label class="sm" style="display:block;margin-top:10px">Mô tả hư hỏng<textarea id="ft" required placeholder="Ví dụ: hỏng bơm thủy lực, máy dừng hoàn toàn"></textarea></label>
    <div class="row" style="margin-top:10px"><button class="primary">Gửi phiếu báo hỏng</button></div></form>` : ""}
  <div class="panel scroll"><table><thead><tr><th>Phiếu</th><th>Máy</th><th>Ban</th><th>Ngày hỏng</th><th>Mô tả</th><th>Dự kiến xong</th><th class="num">Dự toán (đ)</th><th></th></tr></thead><tbody>
  ${ph.map(h => { const qh = h.du_kien_xong && h.du_kien_xong < today(); const mine = isQltb() || (canEditBan() && h.ban_id === S.me.ban_id);
    return `<tr><td class="code">#${h.id}</td><td class="code">${esc(h.ma_may)}</td><td>${esc(banTen(h.ban_id))}</td><td>${vnDate(h.ngay_hong)}</td><td>${esc(h.mo_ta)}</td>
    <td>${qh ? `<span class="pill s-hong">${vnDate(h.du_kien_xong)} – quá hạn</span>` : vnDate(h.du_kien_xong)}</td><td class="num">${fmt(h.chi_phi_du_toan)}</td>
    <td>${mine ? `<button data-id="${h.id}">Đã sửa xong</button>` : ""}</td></tr>`; }).join("") || `<tr><td colspan="8" class="muted">Không có phiếu đang mở.</td></tr>`}
  </tbody></table></div>`;
  if ($("#f")) $("#f").onsubmit = async e => { e.preventDefault();
    try { const id = await rpc("bao_hong", { p_ma: $("#fm").value, p_mo_ta: $("#ft").value.trim(), p_du_kien: $("#fk").value || null, p_chi_phi: $("#fc").value === "" ? null : +$("#fc").value, p_muc_do: $("#fmd").value });
      toast(`Đã gửi phiếu #${id}; máy chuyển sang Hỏng`); vHong(); } catch (err) { fail(err); } };
  document.querySelectorAll("button[data-id]").forEach(x => x.onclick = async () => {
    try { await rpc("dong_phieu_hong", { p_id: +x.dataset.id, p_chi_phi: null, p_trang_thai_sau: "ton" }); toast(`Phiếu #${x.dataset.id} đã đóng; máy về Tồn (chờ việc)`); vHong(); } catch (e) { fail(e); } });
}

/* ---------- Điều chuyển ---------- */
async function vDC() {
  const r = S.me.vai_tro, b = S.me.ban_id;
  const ds = await q(sb.from("phieu_dieu_chuyen").select("*, may(loai_id)").order("tao_luc", { ascending: false }).limit(200));
  const can = d => !d.tu_choi && d.buoc < 6 && ((d.buoc === 1 && r === "truong_ban" && b === d.tu_ban) || (d.buoc === 2 && isQltb()) || (d.buoc === 3 && ["lanh_dao", "admin"].includes(r))
    || (d.buoc === 4 && ["bql", "truong_ban"].includes(r) && [d.tu_ban, d.den_ban].includes(b)) || (d.buoc === 5 && ["bql", "truong_ban"].includes(r) && b === d.den_ban));
  const ten = ["", "Đồng ý cho đi", "Xác nhận kiểm tra", "Phê duyệt", "Ký biên bản giao nhận", "Xác nhận đã nhận máy"];
  const mine = ds.filter(can), rest = ds.filter(d => !can(d));
  const card = d => {
    const steps = STEPS.map((s, i) => { if (i === 3 && !d.vuot_nguong) return `<span class="step">${s}: không cần</span>`;
      const cls = d.tu_choi && i === d.buoc ? "no" : i < d.buoc ? "done" : i === d.buoc && d.buoc < 6 ? "now" : ""; return `<span class="step ${cls}">${s}</span>`; }).join("");
    return `<div class="panel"><div class="row"><b class="code">#${d.id}</b><span>${esc(loaiTen(d.may?.loai_id))} · <span class="code">${esc(d.ma_may)}</span></span>
      <span class="right">${d.tu_choi ? `<span class="pill s-hong">Bị từ chối</span>` : d.buoc >= 6 ? `<span class="pill s-lam">Hoàn thành</span>` : `<span class="pill s-sua">Đang xử lý</span>`}</span></div>
      <div class="muted" style="font-size:13px;margin:4px 0 8px">${esc(banTen(d.tu_ban))} → <b style="color:var(--ink)">${esc(banTen(d.den_ban))}</b> · cần ngày ${vnDate(d.ngay_can)} · ${esc(d.ly_do)}${d.chi_phi_van_chuyen ? " · v/c " + fmt(d.chi_phi_van_chuyen) + " đ" : ""}${d.vuot_nguong ? " · cần LĐ Khối duyệt" : ""}</div>
      <div class="steps">${steps}</div>
      ${can(d) ? `<div class="row" style="margin-top:10px"><input id="gc-${d.id}" placeholder="Ghi chú (không bắt buộc)" style="flex:1 1 200px"><button class="primary" data-ok="${d.id}">${ten[d.buoc]}</button><button class="danger" data-no="${d.id}">Từ chối</button></div>` : ""}</div>`;
  };
  $("#view").innerHTML = `
  <h2>Điều chuyển & xin phê duyệt</h2>
  <p class="sub">Máy chỉ chuyển sang ban mới khi ban nhận xác nhận đã nhận máy. Đề nghị khác khối hoặc chi phí vận chuyển vượt ngưỡng cần Lãnh đạo Khối duyệt.</p>
  <h2 style="font-size:15px">Chờ bạn xử lý (${mine.length})</h2>${mine.map(card).join("") || `<p class="sub">Không có phiếu nào chờ bạn.</p>`}
  <h2 style="font-size:15px">Các phiếu khác</h2>${rest.map(card).join("") || `<p class="sub">Chưa có phiếu.</p>`}`;
  const act = (id, ok) => async () => { try { const buoc = await rpc("duyet_buoc", { p_id: id, p_dong_y: ok, p_ghi_chu: $("#gc-" + id)?.value || null });
    toast(!ok ? `Phiếu #${id} đã bị từ chối` : buoc >= 6 ? `Phiếu #${id} hoàn thành: máy đã chuyển ban` : `Phiếu #${id}: sang bước "${STEPS[buoc]}"`); vDC(); } catch (e) { fail(e); } };
  document.querySelectorAll("[data-ok]").forEach(x => x.onclick = act(+x.dataset.ok, true));
  document.querySelectorAll("[data-no]").forEach(x => x.onclick = act(+x.dataset.no, false));
}

/* ---------- Danh mục ---------- */
async function vDM() {
  const [gh, cnt] = await Promise.all([all("ten_ghep", "ten_cu,loai_id"), all("v_nguon_cung", "loai_id,csh,thue")]);
  const ali = {}; gh.forEach(g => (ali[g.loai_id] ||= []).push(g.ten_cu));
  const n = {}; cnt.forEach(r => n[r.loai_id] = (n[r.loai_id] || 0) + r.csh + r.thue);
  $("#view").innerHTML = `
  <h2>Danh mục chuẩn hóa</h2>
  <p class="sub">BQLXD chỉ chọn loại máy từ danh mục. Tên cũ được ghép về tên chuẩn, không phân biệt chữ hoa/thường và khoảng trắng thừa. ${isQltb() ? "Bạn là P.QLTB nên thêm được loại mới và tên ghép." : "Chỉ P.QLTB thêm/sửa danh mục."}</p>
  <div class="panel row"><input id="q" placeholder="Gõ tên máy bất kỳ, ví dụ: 20-25kva" style="flex:1 1 260px"><span id="kq" class="muted"></span></div>
  ${isQltb() ? `<div class="panel row"><input id="newLoai" placeholder="Tên loại chuẩn mới" style="flex:1 1 220px"><button id="addLoai">Thêm loại</button>
    <input id="tenCu" placeholder="Tên cũ" style="flex:1 1 180px"><select id="veLoai" aria-label="Ghép về loại">${S.loai.map(l => `<option value="${l.id}">${esc(l.ten_chuan)}</option>`).join("")}</select><button id="addGhep">Ghép tên</button></div>` : ""}
  <div class="panel scroll"><table><thead><tr><th>Tên chuẩn hóa</th><th>Tên cũ được ghép về</th><th class="num">Máy dùng được</th></tr></thead><tbody id="tb"></tbody></table></div>`;
  const norm = t => t.toLowerCase().replace(/\s+/g, " ").trim();
  const draw = () => { const s = norm($("#q").value || "");
    const rows = S.loai.filter(l => !s || norm(l.ten_chuan).includes(s) || (ali[l.id] || []).some(a => norm(a).includes(s)));
    const exact = S.loai.find(l => norm(l.ten_chuan) === s) || S.loai.find(l => (ali[l.id] || []).some(a => norm(a) === s));
    $("#kq").textContent = s ? (exact ? `→ quy về: ${exact.ten_chuan}` : rows.length ? `${rows.length} loại gần giống` : "Chưa có trong danh mục – gửi P.QLTB") : "";
    $("#tb").innerHTML = rows.map(l => `<tr><td><b>${esc(l.ten_chuan)}</b></td><td class="muted">${esc((ali[l.id] || []).join("; ") || "–")}</td><td class="num">${fmt(n[l.id] || 0)}</td></tr>`).join(""); };
  $("#q").oninput = draw; draw();
  if ($("#addLoai")) $("#addLoai").onclick = async () => { const t = $("#newLoai").value.trim(); if (!t) return;
    try { await q(sb.from("loai_may").insert({ ten_chuan: t })); S.loai = await all("loai_may", "*", x => x.order("ten_chuan")); S.loaiMap = Object.fromEntries(S.loai.map(l => [l.id, l])); toast("Đã thêm loại"); vDM(); } catch (e) { fail(e); } };
  if ($("#addGhep")) $("#addGhep").onclick = async () => { const t = $("#tenCu").value.trim(); if (!t) return;
    try { await q(sb.from("ten_ghep").insert({ ten_cu_norm: norm(t), ten_cu: t, loai_id: +$("#veLoai").value, nguon: "P.QLTB" })); toast("Đã ghép tên"); vDM(); } catch (e) { fail(e); } };
}

sb.auth.onAuthStateChange((ev) => { if (ev === "SIGNED_OUT") boot(); });
boot();
