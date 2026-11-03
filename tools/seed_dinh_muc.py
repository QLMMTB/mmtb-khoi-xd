"""Sinh SQL định mức từ file 'Định mức' (sheet 'Danh mục DM NX').
python tools/seed_dinh_muc.py --file "Định mức.xlsx" --out supabase/seed_dinh_muc.sql [--sheet "Danh mục DM NX"]

Quy tắc đọc (ghi rõ để P.QLTB kiểm tra):
- Kiểu định mức theo cột 'Đơn vị': '/ca' hoặc 'm/ngày' → năng suất theo ca; 'Ca/căn' → ca máy trên 1 căn;
  'Căn/…', 'm2/máy', 'Máy/10 căn' → số đơn vị cho 1 bộ máy; '1 Kato/4 máy ép cọc', '2 xe ben/1 máy xúc' → máy đi kèm.
- Hạng mục: cột 'Hạng mục/Công việc'; dòng trống: đơn vị căn kiểu bộ máy → 'Nhà thấp tầng – phần thô',
  Ca/căn → 'Nhà thấp tầng – chung', m/ngày → 'Ép cọc', m2/máy → 'Nhà xưởng', m2/ca → 'Lắp đặt kết cấu thép'.
- Số máy trong bộ: 'Căn/2 cẩu tháp + 2 cẩu thùng' → 2; 'Căn/2 xúc lốp + 1 xúc xích' → xúc lốp 2, xúc xích 1; còn lại 1.
- Nhóm thay thế = cột 'Loại máy' trong cùng hạng mục; mặc định = dòng 'Đã PD' đầu tiên, nếu không có thì dòng đầu tiên.
- Lái máy/máy/ca: file không có → mặc định 1 (P.QLTB sửa trên phần mềm).
"""
import argparse, re
import openpyxl
ap = argparse.ArgumentParser(); ap.add_argument('--file', required=True); ap.add_argument('--out', required=True); ap.add_argument('--sheet', default='Danh mục DM NX')
a = ap.parse_args()
cl = lambda x: re.sub(r'\s+', ' ', str(x or '').replace('\xa0', ' ')).strip()
q = lambda v: 'null' if v is None or v == '' else "'" + str(v).replace("'", "''") + "'"
ws = openpyxl.load_workbook(a.file, read_only=True, data_only=True)[a.sheet]
rows = [r for r in ws.iter_rows(min_row=4, max_col=10, values_only=True) if r[0] and r[6] is not None]
items, theo_may = [], []
for r in rows:
    loai_nhom, ten_ct, ten_ch, gt, dv, hm, pd = cl(r[2]), cl(r[3]), cl(r[4]), float(r[6]), cl(r[7]), cl(r[8]), cl(r[9])
    ten = re.sub(r'\s*-\s*Nhà xưởng$', '', ten_ch or ten_ct).strip()
    ten = re.sub(r'\s+l$', '', ten)            # 'Kato 50-60 tấn l' (lỗi gõ trong file)
    d = dv.lower()
    if 'máy ép cọc' in d:
        theo_may.append((ten, ['Máy ép cọc 460', 'Máy ép cọc 680'], gt, dv, pd)); continue
    if 'xe ben' in d and 'máy xúc' in d:
        theo_may.append((ten, ['Máy xúc bánh xích 200', 'Máy xúc bánh xích 300'], gt, dv, pd)); continue
    bo = 1
    if '/ca' in d or 'm/ngày' in d:
        kieu, dvhm = 'nang_suat', ('m3' if 'm3' in d else 'md' if 'md' in d else 'm2' if 'm2' in d else 'm cọc')
        hmn = hm or ('Ép cọc' if 'm/ngày' in d else 'Lắp đặt kết cấu thép')
        nhom = 'Hạ tầng' if dvhm in ('m3', 'md') else 'Nhà xưởng' if dvhm == 'm2' else 'Móng'
    elif d.startswith('ca/căn'):
        kieu, dvhm, nhom = 'ca_tren_dv', 'căn', 'Nhà thấp tầng'
        hmn = 'Nhà thấp tầng – ' + (hm.lower() if hm else 'chung')
    elif 'm2/máy' in d:
        kieu, dvhm, nhom, hmn = 'dv_tren_bo', 'm2', 'Nhà xưởng', 'Nhà xưởng'
    elif d.startswith('máy/'):
        kieu, dvhm, nhom, hmn = 'dv_tren_bo', 'căn', 'Nhà thấp tầng', 'Nhà thấp tầng – ' + (hm.lower() if hm else 'chung')
        gt = float(re.search(r'(\d+)', d).group(1)) / gt         # 1 máy/10 căn → 10 căn/máy
    elif d.startswith('căn'):
        kieu, dvhm, nhom, hmn = 'dv_tren_bo', 'căn', 'Nhà thấp tầng', 'Nhà thấp tầng – ' + (hm.lower() if hm else 'phần thô')
        if 'cẩu tháp' in d: bo = 2
        if 'xúc lốp' in d: bo = 2 if 'bánh lốp' in ten.lower() else 1
    else:
        raise SystemExit(f'Không nhận ra đơn vị định mức: {dv!r} ({ten})')
    items.append(dict(ten=ten, gt=gt, dv=dv, hm=hmn, dvhm=dvhm, nhom=nhom, kieu=kieu, bo=bo, pd=pd == 'Đã PD', grp=loai_nhom))
# nhóm thay thế + mặc định
from collections import defaultdict
g = defaultdict(list)
for it in items: g[(it['hm'], it['grp'])].append(it)
for (hm, grp), lst in g.items():
    if len({x['ten'] for x in lst}) > 1:
        dflt = next((x for x in lst if x['pd']), lst[0])
        for x in lst: x['nhom_tt'], x['mac_dinh'] = grp, x is dflt
    else:
        for x in lst: x['nhom_tt'], x['mac_dinh'] = None, True
L = ['-- Sinh tự động bởi tools/seed_dinh_muc.py từ file định mức – không sửa tay', 'begin;',
     'delete from dinh_muc; delete from dinh_muc_theo_may;']
for t in sorted({it['ten'] for it in items} | {x[0] for x in theo_may} | {s for x in theo_may for s in x[1]}):
    L.append(f"insert into loai_may(ten_chuan) select {q(t)} where tim_loai({q(t)}) is null;")
for hm, dvhm, nhom in sorted({(it['hm'], it['dvhm'], it['nhom']) for it in items}):
    L.append(f"insert into hang_muc(ten, don_vi, nhom) values ({q(hm)}, {q(dvhm)}, {q(nhom)}) on conflict (ten) do update set don_vi = excluded.don_vi, nhom = excluded.nhom;")
seen = set()
for it in items:
    k = (it['hm'], it['ten'])
    if k in seen: continue
    seen.add(k)
    L.append("insert into dinh_muc(hang_muc_id, loai_id, gia_tri, lai_may_ca, kieu, so_may_trong_bo, don_vi_goc, da_phe_duyet, nhom_thay_the, mac_dinh) "
             f"select h.id, tim_loai({q(it['ten'])}), {it['gt']}, 1, '{it['kieu']}', {it['bo']}, {q(it['dv'])}, {str(it['pd']).lower()}, {q(it['nhom_tt'])}, {str(it['mac_dinh']).lower()} "
             f"from hang_muc h where h.ten = {q(it["hm"])} on conflict do nothing;")
for ten, nguon, gt, dv, pd in theo_may:
    for s in nguon:
        L.append(f"insert into dinh_muc_theo_may(loai_id, loai_nguon_id, ty_le, don_vi_goc, da_phe_duyet) values (tim_loai({q(ten)}), tim_loai({q(s)}), {gt}, {q(dv)}, {str(pd == 'Đã PD').lower()}) on conflict do nothing;")
L.append('commit;')
open(a.out, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print(f"{len(items)} dòng định mức trực tiếp, {len(theo_may)} dòng máy đi kèm, {len({it['hm'] for it in items})} hạng mục, "
      f"{len({(it['hm'], it['nhom_tt']) for it in items if it['nhom_tt']})} nhóm thay thế")
for (hm, grp), lst in sorted(g.items()):
    if lst[0].get('nhom_tt'): print('  thay thế:', hm, '|', grp, '→ mặc định', next(x['ten'] for x in lst if x['mac_dinh']), f"({len(lst)} lựa chọn)")
