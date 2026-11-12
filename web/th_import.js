/* Nạp nhu cầu MMTB theo tháng từ file "TH MMTB 2026_2027 theo tiến độ" (chỉ P.QLTB / quản trị).
   - Đọc từng sheet dự án (sheet có cột "Tên nhóm máy chi tiết" và các cột "Tháng m/yyyy"); bỏ sheet "TH của Khối"
     vì sheet này cộng tay từng ô, có thể lệch với sheet dự án.
   - Mỗi dòng có STT là số nguyên = 1 loại máy; số máy từng tháng lấy ở dòng đó (đã là tổng các dòng P&L con).
     Cột tháng lặp lại (phần Lái xe lái máy) bị bỏ, chỉ lấy lần xuất hiện đầu.
   - Sheet → ban: tự đoán theo tên, P.QLTB chọn lại nếu sai; sheet chưa chọn ban thì bỏ qua. Nhiều sheet cùng 1 ban thì cộng.
   - Loại máy: ghép theo bảng tên ghép trong hệ thống và chuan_hoa.js; tên chưa có thì thêm vào danh mục (nhóm = cột "Loại máy").
   - Ghi vào nhu_cau_nhap_tay với nguon = 'TH MMTB'; lần nạp sau xóa phần 'TH MMTB' cũ của các ban được nạp rồi ghi lại. */
"use strict";
(function () {
  const SRC = "TH MMTB";
  const norm = t => String(t ?? "").replace(/ /g, " ").replace(/\s+/g, " ").trim();
  const low = t => norm(t).toLowerCase();
  const key = t => norm(t).replace(/Đ/g, "D").replace(/đ/g, "d").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/^(du an|da|bqlxd|bql)\s+/, "").replace(/[^a-z0-9]+/g, "");
  const BO_QUA = ["th của khối"];

  /* sheets: { tên sheet: mảng dòng (mảng ô) } → [{ sheet, tieuDe, thang:[iso], loai:[{nhom, ten, so:{iso: số}}] }] */
  function parse(sheets) {
    const out = [];
    for (const [name, rows] of Object.entries(sheets)) {
      if (BO_QUA.includes(low(name))) continue;
      const hi = rows.slice(0, 8).findIndex(r => (r || []).some(v => typeof v === "string" && v.includes("Tên nhóm máy chi tiết")));
      if (hi < 0) continue;
      const h = rows[hi], iT = h.findIndex(v => typeof v === "string" && v.includes("Tên nhóm máy chi tiết"));
      const iN = h.findIndex(v => low(v) === "loại máy");
      const cot = {};
      h.forEach((v, j) => { const m = /^\s*Tháng\s*(\d{1,2})\s*\/\s*(\d{4})/.exec(String(v ?? ""));
        if (m) { const iso = `${m[2]}-${String(+m[1]).padStart(2, "0")}-01`; if (!(iso in cot)) cot[iso] = j; } });
      const thang = Object.keys(cot).sort();
      if (!thang.length) continue;
      const loai = {};
      for (const r of rows.slice(hi + 1)) {
        if (!r || typeof r[0] !== "number" || !Number.isInteger(r[0]) || !norm(r[iT])) continue;
        const ten = norm(r[iT]); const x = (loai[low(ten)] ||= { ten, nhom: iN >= 0 ? norm(r[iN]) || null : null, so: {} });
        for (const t of thang) { const v = r[cot[t]]; if (typeof v === "number" && v > 0) x.so[t] = (x.so[t] || 0) + v; }
      }
      const ds = Object.values(loai).filter(l => Object.keys(l.so).length);
      out.push({ sheet: name, tieuDe: norm(rows[0]?.[0]) || norm(name), thang, loai: ds });
    }
    return out;
  }

  /* MAP_DA: tên dự án → tên gốc (thêm gợi ý khi đoán ban) */
  function mapDA(rows) {
    const m = {}; (rows || []).slice(1).forEach(r => { if (r && norm(r[0]) && norm(r[1])) m[key(r[0])] = norm(r[1]); }); return m;
  }

  /* Đoán ban cho 1 sheet: so khóa không dấu của tên sheet / tiêu đề / tên gốc với tên ban và mã ban */
  function doanBan(sh, bans, goc) {
    const ks = [...new Set([key(sh.sheet), key(sh.tieuDe), key(goc[key(sh.sheet)] || "")].filter(k => k.length >= 3))];
    let best = null, bestSc = 0;
    for (const b of bans) {
      for (const bk of [key(b.ten), key(b.id)].filter(k => k.length >= 3)) {
        for (const k of ks) {
          const sc = k === bk ? 1000 : (bk.includes(k) || k.includes(bk)) ? Math.min(k.length, bk.length) : 0;
          if (sc > bestSc) { bestSc = sc; best = b.id; }
        }
      }
    }
    return bestSc >= 3 ? best : "";
  }

  window.MMTB_TH = { parse, mapDA, doanBan, key, SRC };
  if (typeof document === "undefined") return;

  const loadXlsx = () => window.XLSX ? Promise.resolve() : new Promise((ok, no) => { const s = document.createElement("script");
    s.src = "https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"; s.onload = ok; s.onerror = () => no(new Error("Không tải được thư viện đọc Excel")); document.head.appendChild(s); });
  const LS = "mmtb_th_ban";
  const nhoMap = () => { try { return JSON.parse(localStorage.getItem(LS) || "{}"); } catch (e) { return {}; } };
  const luuMap = m => { try { localStorage.setItem(LS, JSON.stringify(m)); } catch (e) { /* bỏ qua */ } };
  const thLab = iso => `T${+iso.slice(5, 7)}/${iso.slice(2, 4)}`;

  window.MMTB_TH.mount = function (el) {
    el.innerHTML = `
    <h2>Nạp nhu cầu từ file TH MMTB theo tiến độ</h2>
    <p class="sub">Chọn file "TH MMTB 2026_2027 theo tiến độ". Phần mềm đọc từng sheet dự án (bỏ sheet "TH của Khối"), lấy số máy từng tháng của mỗi loại máy, ghi vào nhu cầu của ban tương ứng. Nhu cầu đã nạp từ file trước của các ban này được thay bằng số mới; nhu cầu BQLXD tự nhập tay giữ nguyên (trùng loại máy và tháng thì lấy số trong file).</p>
    <div class="panel row"><input type="file" id="thfile" accept=".xlsx,.xlsm,.xls"><span id="thst" class="muted"></span></div>
    <div id="thpv"></div>`;
    const CH = window.MMTB_CHUAN_HOA || { map: {}, ghep: {} };
    const chuan = t => { const x = CH.ghep[low(t)] || norm(t); return CH.map[low(x)] || x; };
    $("#thfile").onchange = async () => {
      const f = $("#thfile").files[0]; if (!f) return;
      try {
        $("#thst").textContent = "Đang đọc file…"; await loadXlsx();
        const wb = XLSX.read(await f.arrayBuffer(), { type: "array" });
        const sheets = {}; wb.SheetNames.forEach(n => sheets[n] = XLSX.utils.sheet_to_json(wb.Sheets[n], { header: 1, defval: null, raw: true }));
        const ds = parse(sheets).filter(s => s.loai.length);
        if (!ds.length) throw new Error('Không thấy sheet dự án nào có cột "Tên nhóm máy chi tiết" và cột "Tháng m/yyyy"');
        const goc = mapDA(sheets["MAP_DA"]); const nho = nhoMap();
        ds.forEach(s => { s.ban = nho[s.sheet] !== undefined && (nho[s.sheet] === "" || S.banMap[nho[s.sheet]]) ? nho[s.sheet] : doanBan(s, S.bans, goc); });
        const ghepDB = Object.fromEntries((await all("ten_ghep", "ten_cu_norm,loai_id")).map(g => [g.ten_cu_norm, g.loai_id]));
        const idOf = () => Object.fromEntries(S.loai.map(l => [low(l.ten_chuan), l.id]));
        const tim = (ten, ids) => ghepDB[low(ten)] || ids[low(ten)] || ids[low(chuan(ten))];
        const tenSet = {}; ds.forEach(s => s.loai.forEach(l => tenSet[low(l.ten)] ||= l));
        const ids0 = idOf(); const moi = {}; Object.values(tenSet).forEach(l => { if (!tim(l.ten, ids0)) moi[low(chuan(l.ten))] ||= { ten_chuan: chuan(l.ten), nhom: l.nhom }; });
        const thang = [...new Set(ds.flatMap(s => s.thang))].sort();
        const tong = s => s.loai.reduce((a, l) => a + Object.values(l.so).reduce((x, y) => x + y, 0), 0);
        const banOpt = sel => `<option value="">— bỏ qua —</option>` + S.bans.map(b => `<option value="${esc(b.id)}" ${b.id === sel ? "selected" : ""}>${esc(b.ten)}</option>`).join("");
        $("#thst").textContent = "";
        const draw = () => {
          const chon = ds.filter(s => s.ban);
          $("#thpv").innerHTML = `<div class="grid">
            <div class="tile"><div class="k">Sheet dự án có nhu cầu</div><div class="v">${ds.length}</div><div class="d">${chon.length} sheet đã chọn ban</div></div>
            <div class="tile"><div class="k">Tháng</div><div class="v">${thang.length}</div><div class="d">${thLab(thang[0])} – ${thLab(thang.at(-1))}</div></div>
            <div class="tile"><div class="k">Loại máy trong file</div><div class="v">${Object.keys(tenSet).length}</div><div class="d">${Object.keys(tenSet).length - Object.values(tenSet).filter(l => !tim(l.ten, ids0)).length} loại đã có trong danh mục</div></div>
            <div class="tile ${Object.keys(moi).length ? "warn" : ""}"><div class="k">Loại máy sẽ thêm vào danh mục</div><div class="v">${Object.keys(moi).length}</div><div class="d">P.QLTB rà lại ở tab Danh mục chuẩn hóa</div></div></div>
            <div class="panel scroll"><table><thead><tr><th>Sheet</th><th>Tên dự án trong file</th><th class="num">Số loại máy</th><th class="num">Tổng máy·tháng</th><th>Nạp vào ban</th></tr></thead><tbody>
            ${ds.map((s, i) => `<tr><td>${esc(s.sheet)}</td><td class="muted">${esc(s.tieuDe)}</td><td class="num">${s.loai.length}</td><td class="num">${fmt(Math.round(tong(s)))}</td>
              <td><select class="thban" data-i="${i}" aria-label="Ban cho ${esc(s.sheet)}">${banOpt(s.ban)}</select></td></tr>`).join("")}
            </tbody></table></div>
            ${Object.keys(moi).length ? `<details class="panel"><summary>${Object.keys(moi).length} loại máy chưa có trong danh mục</summary><p class="sm">${Object.values(moi).map(m => esc(m.ten_chuan)).join("; ")}</p></details>` : ""}
            <div class="panel row"><button class="primary" id="thgo" ${chon.length ? "" : "disabled"}>Nạp nhu cầu của ${chon.length} sheet</button><span id="thpg" class="muted"></span></div>`;
          document.querySelectorAll(".thban").forEach(x => x.onchange = () => { ds[+x.dataset.i].ban = x.value; const m = nhoMap(); m[ds[+x.dataset.i].sheet] = x.value; luuMap(m); draw(); });
          $("#thgo").onclick = () => nap(chon);
        };
        const nap = async chon => {
          $("#thgo").disabled = true; window.onbeforeunload = () => "Đang nạp dữ liệu"; const pg = t => $("#thpg").textContent = t;
          try {
            const m = nhoMap(); ds.forEach(s => m[s.sheet] = s.ban); luuMap(m);
            const can = Object.values(moi);
            if (can.length) { pg("Đang thêm loại máy mới vào danh mục…");
              await q(sb.from("loai_may").insert(can.map(x => ({ ...x, ghi_chu: "Thêm khi nạp file TH MMTB" }))));
              S.loai = await all("loai_may", "*", x => x.order("ten_chuan")); S.loaiMap = Object.fromEntries(S.loai.map(l => [l.id, l])); }
            const ids = idOf(); const gom = {}; let khongRo = 0;
            for (const s of chon) for (const l of s.loai) { const id = tim(l.ten, ids); if (!id) { khongRo++; continue; }
              for (const [t, v] of Object.entries(l.so)) { const k = `${s.ban}|${id}|${t}`; gom[k] = (gom[k] || 0) + v; } }
            const recs = Object.entries(gom).map(([k, v]) => { const [ban_id, loai_id, thang] = k.split("|"); return { ban_id, loai_id: +loai_id, thang, so_may: Math.round(v * 100) / 100, nguon: SRC }; });
            const bans = [...new Set(chon.map(s => s.ban))];
            pg("Đang xóa nhu cầu đã nạp từ file lần trước…");
            await q(sb.from("nhu_cau_nhap_tay").delete().eq("nguon", SRC).in("ban_id", bans));
            for (let i = 0; i < recs.length; i += 500) { pg(`Đang ghi nhu cầu ${fmt(i)}/${fmt(recs.length)}…`);
              await q(sb.from("nhu_cau_nhap_tay").upsert(recs.slice(i, i + 500), { onConflict: "ban_id,loai_id,thang" })); }
            pg(`Xong: ${fmt(recs.length)} dòng nhu cầu (ban × loại máy × tháng) cho ${bans.length} ban, ${can.length} loại máy mới${khongRo ? `, ${khongRo} dòng không xác định được loại máy` : ""}.`);
            toast("Đã nạp nhu cầu"); window.onbeforeunload = null; $("#thgo").disabled = false;
          } catch (e) { window.onbeforeunload = null; fail(e); $("#thgo").disabled = false; pg("Lỗi – xem thông báo, sửa rồi bấm lại (nạp lại sẽ thay toàn bộ phần đã nạp từ file của các ban này)."); }
        };
        draw();
      } catch (e) { $("#thst").textContent = ""; fail(e); }
    };
  };
})();
