"""Tạo file SQL nạp dữ liệu ban đầu cho hệ thống MMTB từ các file Excel hiện có.

python tools/seed_from_excel.py --registry "01.11.2026_MMTB_BaoCao_Vinalpha -VHM-Vincons.xlsx" \
    --rev2 "261022_TH MMTB 2026, 2027 - REV2.xlsx" --out supabase/seed.sql [--du-an "Dự án Hạ Long Xanh" "Dự án Olympic" ...]

- Ban (BQLXD) = cột 'Dự án' của sheet 'Danh sách máy'; khối = cột 'Khối'.
- Máy: chỉ đơn vị sử dụng VHM, Vinalpha, Vinalpha WDS, Vincons (bỏ SGC, VFM, Vinfast) – quy tắc đã chốt.
- Loại máy: tên chuẩn hóa theo 'Map MMTB chuẩn hóa' + bảng ghép của REV2; tên chưa ghép giữ nguyên làm 1 loại
  (P.QLTB rà lại trong màn hình Danh mục). Gộp không phân biệt hoa/thường, khoảng trắng.
- Trạng thái ban đầu: 'Đang sử dụng' → làm việc; 'Sửa chữa' → sửa chữa; 'Lưu kho' → tồn; còn lại → làm việc (ghi chú).
- Định mức: bộ định mức MẪU (cần P.QLTB thay bằng định mức chính thức).
- --du-an: chỉ nạp máy của các dự án thí điểm (khuyến nghị cho bản test trên đám mây miễn phí).
"""
import argparse, re, unicodedata, sys
import pandas as pd, openpyxl

ap = argparse.ArgumentParser()
ap.add_argument('--registry', required=True); ap.add_argument('--rev2', required=True)
ap.add_argument('--out', required=True); ap.add_argument('--du-an', nargs='*', default=None)
a = ap.parse_args()
KEEP = ['VHM', 'Vinalpha', 'Vinalpha WDS', 'Vincons']


def norm(t):
    return re.sub(r'\s+', ' ', str(t or '').replace('\xa0', ' ')).strip().lower()


def q(v):
    if v is None or (isinstance(v, float) and pd.isna(v)) or str(v).strip() in ('', 'nan', '0'):
        return 'null'
    return "'" + str(v).strip().replace("'", "''") + "'"


def slug(t):
    t = unicodedata.normalize('NFD', t.replace('Đ', 'D').replace('đ', 'd'))
    t = ''.join(c for c in t if unicodedata.category(c) != 'Mn')
    t = re.sub(r'^(du an|bql|bqlxd)\s+', '', t.lower())
    return re.sub(r'[^a-z0-9]+', '-', t).strip('-')[:40].upper()


d = pd.read_excel(a.registry, sheet_name='Danh sách máy')
d = d[d['Đơn vị sử dụng'].isin(KEEP)].copy()
if a.du_an:
    miss = [x for x in a.du_an if x not in set(d['Dự án'])]
    if miss:
        sys.exit(f'Không thấy dự án: {miss}')
    d = d[d['Dự án'].isin(a.du_an)]

wb = openpyxl.load_workbook(a.rev2, read_only=True, data_only=True)
mp = {}
for r in wb['Map MMTB chuẩn hóa'].iter_rows(min_row=6, max_row=79, values_only=True):
    if r[1] and r[2]:
        mp[norm(r[1])] = re.sub(r'\s+', ' ', str(r[2])).strip()
gh = {}
for r in wb['Thiếu T11 theo loại máy'].iter_rows(min_row=7, max_row=40, values_only=True):
    if r[17] and r[18]:
        gh[norm(r[17])] = re.sub(r'\s+', ' ', str(r[18])).strip()
gh[norm('Máy phát điện 3 pha 275-295KVA')] = 'Máy phát điện 3 pha 300-395 KVA'


def chuan(t):
    n = norm(t)
    x = gh.get(n, None) or re.sub(r'\s+', ' ', str(t)).strip()
    return mp.get(norm(x), x)


loai, alias = {}, {}
for t in d['Tên loại máy móc'].dropna().astype(str):
    c = chuan(t)
    loai.setdefault(norm(c), c)
    if norm(t) != norm(c):
        alias[norm(t)] = (t.strip(), norm(c))
for k, v in list(mp.items()) + list(gh.items()):
    loai.setdefault(norm(v), v)
    if k != norm(v):
        alias.setdefault(k, (k, norm(v)))

khoi = sorted(set(d['Khối'].dropna()))
ban = d.groupby('Dự án')['Khối'].agg(lambda s: s.mode().iat[0]).to_dict()
ban_id = {}
for b in sorted(ban):
    s = slug(b) or 'BAN'
    while s in ban_id.values():
        s += 'X'
    ban_id[b] = s
TT = {'Đang sử dụng': 'lam_viec', 'Sửa chữa': 'sua_chua', 'Lưu kho': 'ton'}
stcol = d.columns[21] if len(d.columns) > 21 else None

L = ['-- Sinh tự động bởi tools/seed_from_excel.py – không sửa tay', 'begin;']
L += [f"insert into khoi(id, ten) values ({q(slug(k))}, {q(k)}) on conflict do nothing;" for k in khoi]
L += [f"insert into ban(id, ten, khoi_id) values ({q(ban_id[b])}, {q(b)}, {q(slug(k))}) on conflict do nothing;" for b, k in ban.items()]
L += [f"insert into loai_may(ten_chuan) values ({q(v)}) on conflict do nothing;" for v in sorted(loai.values())]
for k, (raw, cn) in alias.items():
    L.append(f"insert into ten_ghep(ten_cu_norm, ten_cu, loai_id, nguon) select {q(k)}, {q(raw)}, id, 'REV2/Danh sách máy' "
             f"from loai_may where lower(ten_chuan) = {q(cn)} on conflict do nothing;")
n_tt = {}
vals = []
for _, r in d.iterrows():
    st = TT.get(str(r[stcol]).strip(), 'lam_viec') if stcol is not None else 'lam_viec'
    n_tt[st] = n_tt.get(st, 0) + 1
    vals.append(f"({q(r['Mã máy móc'])}, tim_loai({q(chuan(r['Tên loại máy móc']))}), {q(r['Tên loại máy móc'])}, "
             f"{q('CSH' if r['CSH'] == 'Máy CSH hiện có' else 'Thue')}, {q(r['Chủ tài sản'])}, {q(r['Đơn vị sử dụng'])}, "
             f"{q(r.get('Số Khung'))}, {q(r.get('Số máy'))}, {q(r.get('Biển số'))}, {q(r.get('Mã TS SAP'))}, {q(ban_id[r['Dự án']])}, '{st}')")
for i in range(0, len(vals), 500):
    L.append("insert into may(ma, loai_id, ten_loai_goc, so_huu, chu_tai_san, don_vi_su_dung, so_khung, so_may, bien_so, ma_sap, ban_id, trang_thai) values\n"
             + ",\n".join(vals[i:i + 500]) + "\non conflict (ma) do nothing;")
# Định mức MẪU (giống bản mẫu) – thay bằng định mức chính thức
DM = {'Đào đất': ('m3', [('Máy xúc bánh xích 200', 400, 1), ('Xe ben 16 tấn VC04', 100, 1)]),
      'Đắp và lu lèn nền': ('m3', [('Máy ủi D5', 800, 1), ('Máy lu rung bánh lốp 12-14 tấn', 700, 1), ('Xe nước 9m3', 1400, 1)]),
      'Bê tông bơm': ('m3', [('Xe bơm bê tông Cần bơm 62m', 250, 2)]),
      'Cẩu lắp cấu kiện': ('cấu kiện', [('Máy cẩu bánh lốp chuyên dụng Kato 50-60 tấn', 8, 2), ('Xe cẩu thùng 15 tấn', 12, 1)]),
      'Đào hố móng nhỏ': ('m3', [('Máy xúc bánh xích 55', 120, 1)])}
for h, (dv, ms) in DM.items():
    L.append(f"insert into hang_muc(ten, don_vi) values ({q(h)}, {q(dv)}) on conflict do nothing;")
    for l, ns, lai in ms:
        L.append(f"insert into loai_may(ten_chuan) select {q(l)} where not exists (select 1 from loai_may where lower(ten_chuan) = lower({q(l)}));")
        L.append(f"insert into dinh_muc select h.id, tim_loai({q(l)}), {ns}, {lai} from hang_muc h where h.ten = {q(h)} on conflict do nothing;")
L.append('commit;')
open(a.out, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print(f'{a.out}: {len(ban)} ban, {len(khoi)} khối, {len(loai)} loại máy, {len(alias)} tên ghép, {len(d)} máy; trạng thái: {n_tt}')
