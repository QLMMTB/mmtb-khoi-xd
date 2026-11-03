/* Nhập dữ liệu từ file Excel 'Danh sách máy' (chỉ P.QLTB / quản trị).
   - Lọc đơn vị sử dụng VHM, Vinalpha, Vinalpha WDS, Vincons (bỏ SGC, VFM, Vinfast).
   - Ban = cột 'Dự án', khối = cột 'Khối'. Loại máy chuẩn hóa theo bảng ghép (REV2 + bảng ten_ghep trong hệ thống).
   - Máy mới được thêm; máy đã có chỉ cập nhật thông tin hồ sơ (chủ tài sản, biển số, số khung…),
     KHÔNG đổi ban đang giữ và trạng thái (những thứ do quy trình trên phần mềm quản lý). */
"use strict";
window.vNhapDuLieu = async function () {
  const KEEP = ["VHM", "Vinalpha", "Vinalpha WDS", "Vincons"];
  const TT = { "Đang sử dụng": "lam_viec", "Sửa chữa": "sua_chua", "Lưu kho": "ton" };
  const norm = t => String(t ?? "").replace(/ /g, " ").replace(/\s+/g, " ").trim();
  const low = t => norm(t).toLowerCase();
  const slug = t => { let s = norm(t).replace(/Đ/g, "D").replace(/đ/g, "d").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    s = s.replace(/^(du an|bql|bqlxd)\s+/, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40).toUpperCase(); return s || "BAN"; };
  const CH = window.MMTB_CHUAN_HOA || { map: {}, ghep: {} };
  const chuan = t => { const x = CH.ghep[low(t)] || norm(t); return CH.map[low(x)] || x; };
  const isAdmin = ["qltb", "admin"].includes(S.me.vai_tro);
  $("#view").innerHTML = `
  <h2>Nhập dữ liệu từ file Danh sách máy</h2>
  <p class="sub">Chọn file Excel báo cáo MMTB (có sheet "Danh sách máy"). Phần mềm chỉ lấy máy của VHM, Vinalpha, Vinalpha WDS, Vincons; ban = cột "Dự án". Máy mới được thêm; máy đã có chỉ cập nhật hồ sơ (biển số, số khung, chủ tài sản…), không đổi ban đang giữ và trạng thái.</p>
  ${isAdmin ? `<div class="panel row"><input type="file" id="file" accept=".xlsx,.xlsm,.xls"><span id="st" class="muted"></span></div>
  <div id="pv"></div>` : `<p class="err">Chỉ P.QLTB hoặc quản trị được nhập dữ liệu.</p>`}`;
  if (!isAdmin) return;
  const loadXlsx = () => window.XLSX ? Promise.resolve() : new Promise((ok, no) => { const s = document.createElement("script");
    s.src = "https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"; s.onload = ok; s.onerror = () => no(new Error("Không tải được thư viện đọc Excel")); document.head.appendChild(s); });
  $("#file").onchange = async () => {
    const f = $("#file").files[0]; if (!f) return;
    try {
      $("#st").textContent = "Đang đọc file…"; await loadXlsx();
      const wb = XLSX.read(await f.arrayBuffer(), { type: "array" });
      const ws = wb.Sheets["Danh sách máy"]; if (!ws) throw new Error('File không có sheet "Danh sách máy"');
      const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: null });
      const h = rows[0].map(norm); const c = n => { const i = h.indexOf(n); if (i < 0) throw new Error(`Thiếu cột "${n}"`); return i; };
      const iK = c("Khối"), iDV = c("Đơn vị sử dụng"), iMa = c("Mã máy móc"), iLoai = c("Tên loại máy móc"), iCts = c("Chủ tài sản"), iDA = c("Dự án"), iCSH = c("CSH");
      const opt = n => h.indexOf(n); const iSK = opt("Số Khung"), iSM = opt("Số máy"), iBS = opt("Biển số"), iSAP = opt("Mã TS SAP");
      const iTT = rows.slice(1, 200).some(r => r[21] && TT[norm(r[21])]) ? 21 : -1;
      const data = rows.slice(1).filter(r => r[iMa] && KEEP.includes(norm(r[iDV])));
      const bo = rows.slice(1).filter(r => r[iMa] && !KEEP.includes(norm(r[iDV]))).length;
      const banTenSet = [...new Set(data.map(r => norm(r[iDA])).filter(Boolean))].sort((a, b) => a.localeCompare(b, "vi"));
      const loaiSet = [...new Set(data.map(r => chuan(r[iLoai])))];
      const daCo = new Set(S.loai.map(l => low(l.ten_chuan)));
      const loaiMoi = loaiSet.filter(t => !daCo.has(low(t)));
      const csh = data.filter(r => norm(r[iCSH]) === "Máy CSH hiện có").length;
      $("#st").textContent = "";
      $("#pv").innerHTML = `<div class="grid">
        <div class="tile"><div class="k">Máy sẽ nạp</div><div class="v">${fmt(data.length)}</div><div class="d">${fmt(csh)} máy Tập đoàn · ${fmt(data.length - csh)} máy thuê</div></div>
        <div class="tile"><div class="k">Máy bỏ qua (SGC, VFM, Vinfast…)</div><div class="v">${fmt(bo)}</div><div class="d">không thuộc phạm vi</div></div>
        <div class="tile"><div class="k">Ban (cột Dự án)</div><div class="v">${banTenSet.length}</div><div class="d">${banTenSet.filter(t => !S.bans.some(b => b.ten === t)).length} ban mới</div></div>
        <div class="tile ${loaiMoi.length ? "warn" : ""}"><div class="k">Loại máy chưa có trong danh mục</div><div class="v">${loaiMoi.length}</div><div class="d">sẽ thêm mới, P.QLTB rà lại sau</div></div></div>
        <div class="panel row"><button class="primary" id="go">Nạp ${fmt(data.length)} máy vào hệ thống</button><span id="pg" class="muted"></span></div>`;
      $("#go").onclick = async () => {
        $("#go").disabled = true; window.onbeforeunload = () => "Đang nạp dữ liệu"; const pg = t => $("#pg").textContent = t;
        try {
          pg("Đang nạp khối và ban…");
          const khoi = [...new Set(data.map(r => norm(r[iK])).filter(Boolean))];
          await q(sb.from("khoi").upsert(khoi.map(k => ({ id: slug(k), ten: k })), { onConflict: "id", ignoreDuplicates: true }));
          const banKhoi = {}; data.forEach(r => { const d = norm(r[iDA]); const k = norm(r[iK]); (banKhoi[d] ||= {})[k] = ((banKhoi[d] || {})[k] || 0) + 1; });
          const used = new Set(S.bans.map(b => b.id)); const banId = Object.fromEntries(S.bans.map(b => [b.ten, b.id]));
          const banNew = banTenSet.filter(t => !banId[t]).map(t => { let id = slug(t); while (used.has(id)) id += "X"; used.add(id); banId[t] = id;
            const k = Object.entries(banKhoi[t]).sort((a, b) => b[1] - a[1])[0][0]; return { id, ten: t, khoi_id: slug(k) }; });
          if (banNew.length) await q(sb.from("ban").insert(banNew));
          pg("Đang nạp danh mục loại máy…");
          if (loaiMoi.length) await q(sb.from("loai_may").insert(loaiMoi.map(t => ({ ten_chuan: t, ghi_chu: "Thêm khi nhập Danh sách máy" }))));
          S.loai = await all("loai_may", "*", x => x.order("ten_chuan")); S.loaiMap = Object.fromEntries(S.loai.map(l => [l.id, l]));
          const idOf = Object.fromEntries(S.loai.map(l => [low(l.ten_chuan), l.id]));
          const ghep = [...Object.entries(CH.ghep), ...Object.entries(CH.map)].filter(([k, v]) => idOf[low(v)] && k !== low(v))
            .map(([k, v]) => ({ ten_cu_norm: k, ten_cu: k, loai_id: idOf[low(v)], nguon: "REV2" }));
          for (const r of data) { const k = low(r[iLoai]); const v = chuan(r[iLoai]); if (k !== low(v) && idOf[low(v)]) ghep.push({ ten_cu_norm: k, ten_cu: norm(r[iLoai]), loai_id: idOf[low(v)], nguon: "Danh sách máy" }); }
          const ghepU = Object.values(Object.fromEntries(ghep.map(g => [g.ten_cu_norm, g])));
          if (ghepU.length) await q(sb.from("ten_ghep").upsert(ghepU, { onConflict: "ten_cu_norm", ignoreDuplicates: true }));
          const val = v => { const s = norm(v); return s && s !== "0" ? s : null; };
          const ex = new Set((await all("may", "ma")).map(m => m.ma));
          const recs = data.map(r => ({ ma: norm(r[iMa]), loai_id: idOf[low(chuan(r[iLoai]))], ten_loai_goc: norm(r[iLoai]), so_huu: norm(r[iCSH]) === "Máy CSH hiện có" ? "CSH" : "Thue",
            chu_tai_san: val(r[iCts]), don_vi_su_dung: norm(r[iDV]), so_khung: iSK >= 0 ? val(r[iSK]) : null, so_may: iSM >= 0 ? val(r[iSM]) : null,
            bien_so: iBS >= 0 ? val(r[iBS]) : null, ma_sap: iSAP >= 0 ? val(r[iSAP]) : null, ban_id: banId[norm(r[iDA])], trang_thai: iTT >= 0 ? (TT[norm(r[iTT])] || "lam_viec") : "lam_viec" }));
          const moi = recs.filter(x => !ex.has(x.ma)), cu = recs.filter(x => ex.has(x.ma));
          for (let i = 0; i < moi.length; i += 500) { pg(`Đang thêm máy mới ${fmt(i)}/${fmt(moi.length)}…`); await q(sb.from("may").insert(moi.slice(i, i + 500))); }
          for (let i = 0; i < cu.length; i += 500) { pg(`Đang cập nhật hồ sơ máy đã có ${fmt(i)}/${fmt(cu.length)}…`);
            await q(sb.from("may").upsert(cu.slice(i, i + 500).map(({ ban_id, trang_thai, ...rest }) => rest), { onConflict: "ma" })); }
          S.bans = await q(sb.from("ban").select("*").order("ten")); S.banMap = Object.fromEntries(S.bans.map(b => [b.id, b]));
          $("#ban").innerHTML = S.bans.map(b => `<option value="${esc(b.id)}" ${b.id === S.viewBan ? "selected" : ""}>${esc(b.ten)}</option>`).join("");
          pg(`Xong: thêm ${fmt(moi.length)} máy mới, cập nhật hồ sơ ${fmt(cu.length)} máy, ${banNew.length} ban mới, ${loaiMoi.length} loại máy mới.`);
          toast("Đã nạp dữ liệu"); window.onbeforeunload = null;
        } catch (e) { window.onbeforeunload = null; fail(e); $("#go").disabled = false; pg("Lỗi – xem thông báo, sửa rồi bấm lại (máy đã nạp không bị nạp trùng)."); }
      };
    } catch (e) { $("#st").textContent = ""; fail(e); }
  };
};
