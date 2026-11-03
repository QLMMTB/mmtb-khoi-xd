-- =====================================================================
-- Định mức 4 kiểu (theo file 'Định mức' của Khối XD, sheet 'Danh mục DM NX')
--  nang_suat   : khối lượng / máy / ca (M3/ca, md/ca, m2/ca, m/ngày)
--                số máy = ceil( KL tháng / (định mức × ca/tháng × hệ số ca) )
--  ca_tren_dv  : ca máy / 1 đơn vị (Ca/căn)
--                số máy = ceil( KL tháng × định mức / (ca/tháng × hệ số ca) )
--  dv_tren_bo  : đơn vị / 1 bộ máy (Căn/1 cần, Căn/2 cẩu tháp + 2 cẩu thùng, m2/máy, Máy/10 căn)
--                số máy = ceil( KL đang thi công / định mức × số máy trong bộ )  (mỗi tháng hạng mục đang chạy)
--  theo_may    : máy đi kèm máy khác (1 Kato/4 máy ép cọc, 2 xe ben/1 máy xúc)
--                số máy = ceil( tổng số máy nguồn của ban trong tháng × tỷ lệ )
-- =====================================================================
create type kieu_dinh_muc as enum ('nang_suat', 'ca_tren_dv', 'dv_tren_bo', 'theo_may');

alter table hang_muc add column nhom text;            -- Hạ tầng / Nhà thấp tầng / Nhà xưởng ...

alter table dinh_muc
  add column kieu kieu_dinh_muc not null default 'nang_suat',
  add column so_may_trong_bo numeric(6,2) not null default 1 check (so_may_trong_bo > 0),
  add column don_vi_goc text,                          -- đơn vị như file định mức, ví dụ 'Căn/ 2 cẩu tháp + 2 cẩu thùng'
  add column da_phe_duyet boolean not null default false,
  add column nhom_thay_the text,                      -- các loại máy thay thế nhau trong cùng hạng mục (cột 'Loại máy' của file)
  add column mac_dinh boolean not null default true;  -- loại được chọn khi BQLXD chưa chọn (1 dòng / nhóm)
alter table dinh_muc rename column nang_suat_ca to gia_tri;

-- BQLXD chọn loại máy cho từng nhóm thay thế của một công việc
create table cong_viec_chon (
  cong_viec_id  bigint not null references cong_viec(id) on delete cascade,
  nhom_thay_the text not null,
  loai_id       int not null references loai_may(id),
  primary key (cong_viec_id, nhom_thay_the)
);
alter table cong_viec_chon enable row level security;
create policy doc_cong_viec_chon on cong_viec_chon for select to authenticated using (true);
create policy ghi_cong_viec_chon on cong_viec_chon for all to authenticated
  using (exists (select 1 from cong_viec c where c.id = cong_viec_id and (la_qltb() or (toi_vai_tro() in ('bql','truong_ban') and c.ban_id = toi_ban()))))
  with check (exists (select 1 from cong_viec c where c.id = cong_viec_id and (la_qltb() or (toi_vai_tro() in ('bql','truong_ban') and c.ban_id = toi_ban()))));
grant select, insert, update, delete on cong_viec_chon to authenticated;

-- Máy đi kèm (kiểu theo_may): áp dụng trên tổng số máy nguồn của ban trong tháng
create table dinh_muc_theo_may (
  loai_id        int not null references loai_may(id),  -- máy đi kèm (Kato, xe ben)
  loai_nguon_id  int not null references loai_may(id),  -- máy nguồn (máy ép cọc, máy xúc)
  ty_le          numeric(8,4) not null check (ty_le > 0),
  lai_may_ca     numeric(4,2) not null default 1,
  don_vi_goc     text,
  da_phe_duyet   boolean not null default false,
  primary key (loai_id, loai_nguon_id)
);
alter table dinh_muc_theo_may enable row level security;
create policy doc_dinh_muc_theo_may on dinh_muc_theo_may for select to authenticated using (true);
create policy ghi_qltb_dinh_muc_theo_may on dinh_muc_theo_may for all to authenticated using (la_qltb()) with check (la_qltb());

drop view if exists v_cung_cau_khoi;
drop view if exists v_nhu_cau;
drop view if exists v_nhu_cau_dinh_muc;

create view v_nhu_cau_dinh_muc with (security_invoker = true) as
with ca as (select gia_tri as ca_thang from cau_hinh where khoa = 'ca_thang'),
thang as (
  select cv.id cv_id, cv.ban_id, cv.hang_muc_id, gs::date as thang, cv.khoi_luong as kl_tong,
         cv.khoi_luong / ((extract(year from age(cv.den_thang, cv.tu_thang))*12 + extract(month from age(cv.den_thang, cv.tu_thang)) + 1)) as kl_thang
  from cong_viec cv, generate_series(cv.tu_thang, cv.den_thang, interval '1 month') gs),
truc_tiep as (
  select t.ban_id, dm.loai_id, t.thang, dm.lai_may_ca, b.he_so_ca,
    ceil(case dm.kieu
      when 'nang_suat'  then t.kl_thang / (dm.gia_tri * ca.ca_thang * b.he_so_ca)
      when 'ca_tren_dv' then t.kl_thang * dm.gia_tri / (ca.ca_thang * b.he_so_ca)
      when 'dv_tren_bo' then t.kl_tong / dm.gia_tri * dm.so_may_trong_bo
    end)::int as so_may
  from thang t join dinh_muc dm on dm.hang_muc_id = t.hang_muc_id and dm.kieu <> 'theo_may'
  left join cong_viec_chon ch on ch.cong_viec_id = t.cv_id and ch.nhom_thay_the = dm.nhom_thay_the
  join ban b on b.id = t.ban_id cross join ca
  where dm.nhom_thay_the is null or (ch.loai_id is not null and ch.loai_id = dm.loai_id) or (ch.loai_id is null and dm.mac_dinh)),
tong_truc_tiep as (
  select ban_id, loai_id, thang, sum(so_may) so_may, sum(ceil(so_may * lai_may_ca * he_so_ca)) so_lai_may
  from truc_tiep group by ban_id, loai_id, thang),
di_kem as (
  select t.ban_id, tm.loai_id, t.thang, ceil(sum(t.so_may) * max(tm.ty_le))::int as so_may, max(tm.lai_may_ca) lai, max(b.he_so_ca) hs
  from tong_truc_tiep t join dinh_muc_theo_may tm on tm.loai_nguon_id = t.loai_id join ban b on b.id = t.ban_id
  group by t.ban_id, tm.loai_id, t.thang)
select ban_id, loai_id, thang, sum(so_may)::int as so_may, sum(so_lai_may)::int as so_lai_may from (
  select ban_id, loai_id, thang, so_may, so_lai_may from tong_truc_tiep
  union all
  select ban_id, loai_id, thang, so_may, ceil(so_may * lai * hs) from di_kem) x
group by ban_id, loai_id, thang;

create view v_nhu_cau with (security_invoker = true) as
select ban_id, loai_id, thang, sum(so_may)::numeric as so_may, sum(so_lai_may)::numeric as so_lai_may
from (
  select ban_id, loai_id, thang, so_may, so_lai_may from v_nhu_cau_dinh_muc
  union all
  select ban_id, loai_id, thang, so_may, 0 from nhu_cau_nhap_tay) x
group by ban_id, loai_id, thang;

create view v_cung_cau_khoi with (security_invoker = true) as
with hs as (select gia_tri h from cau_hinh where khoa = 'he_so_nhu_cau'),
cau as (select thang, sum(so_may) so_may from v_nhu_cau group by thang),
cung as (select sum(csh) csh, sum(thue) thue from v_nguon_cung),
ve as (select thang, sum(sum(so_luong)) over (order by thang) luy_ke from may_dang_ve group by thang),
x as (select c.thang, round(c.so_may * hs.h, 1) nhu_cau, cung.csh, cung.thue,
        coalesce((select luy_ke from ve where ve.thang <= c.thang order by ve.thang desc limit 1), 0) sap_ve_luy_ke
      from cau c cross join cung cross join hs)
select thang, nhu_cau, csh, thue, sap_ve_luy_ke,
       csh + thue + sap_ve_luy_ke - nhu_cau as thua_thieu_giu_thue,
       csh + sap_ve_luy_ke - nhu_cau as thua_thieu_tra_thue
from x order by thang;

grant select on v_nhu_cau_dinh_muc, v_nhu_cau, v_cung_cau_khoi to authenticated;
grant select, insert, update, delete on dinh_muc_theo_may to authenticated;
