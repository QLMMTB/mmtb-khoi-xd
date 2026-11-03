-- =====================================================================
-- MMTB Khối XD – cơ sở dữ liệu (Supabase / PostgreSQL 15+)
-- Quy tắc gốc: mỗi máy luôn có đúng 1 ban giữ và 1 trạng thái; mọi thay đổi
-- trạng thái / vị trí đi qua hàm (RPC) có kiểm tra quyền và ghi nhật ký.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Danh mục ----------
create table khoi (
  id   text primary key,
  ten  text not null
);

create table ban (
  id          text primary key,                 -- mã ban, ví dụ 'HLX'
  ten         text not null unique,              -- tên hiển thị, ví dụ 'DA HLX'
  khoi_id     text references khoi(id),
  dang_thi_cong boolean not null default true,
  he_so_ca    numeric(3,2) not null default 1 check (he_so_ca between 0.5 and 3)
);

create table loai_may (
  id        serial primary key,
  ten_chuan text not null,
  nhom      text,
  ghi_chu   text
);
create unique index loai_may_ten_ci on loai_may (lower(ten_chuan));

-- Tên cũ (trong file Excel, Danh sách máy, sheet dự án) ghép về loại chuẩn hóa.
-- So khớp không phân biệt hoa/thường, khoảng trắng thừa (tránh lỗi '20-25kva' / '20-25KVA').
create table ten_ghep (
  ten_cu_norm text primary key,                  -- lower + gộp khoảng trắng
  ten_cu      text not null,
  loai_id     int not null references loai_may(id),
  nguon       text
);

create or replace function norm_ten(t text) returns text
language sql immutable as $$ select lower(regexp_replace(btrim(coalesce(t,'')), '\s+', ' ', 'g')) $$;

create or replace function tim_loai(t text) returns int
language sql stable as $$
  select coalesce(
    (select loai_id from ten_ghep where ten_cu_norm = norm_ten(t)),
    (select id from loai_may where lower(ten_chuan) = norm_ten(t)))
$$;

-- ---------- Người dùng & vai trò ----------
create type vai_tro as enum ('bql', 'truong_ban', 'qltb', 'lanh_dao', 'admin');

create table nguoi_dung (
  id      uuid primary key references auth.users(id) on delete cascade,
  email   text not null unique,
  ho_ten  text,
  vai_tro vai_tro not null default 'bql',
  ban_id  text references ban(id),               -- bắt buộc với bql / truong_ban
  check (vai_tro not in ('bql','truong_ban') or ban_id is not null)
);

create or replace function toi_vai_tro() returns vai_tro
language sql stable security definer set search_path = public as $$
  select vai_tro from nguoi_dung where id = auth.uid() $$;
create or replace function toi_ban() returns text
language sql stable security definer set search_path = public as $$
  select ban_id from nguoi_dung where id = auth.uid() $$;
create or replace function la_qltb() returns boolean
language sql stable as $$ select coalesce(toi_vai_tro() in ('qltb','admin'), false) $$;

-- ---------- Máy ----------
create type trang_thai_may as enum ('lam_viec', 'ton', 'hong', 'sua_chua', 'van_chuyen', 'cho_tra', 'da_tra');

create table may (
  ma             text primary key,               -- 'Mã máy móc' trong Danh sách máy
  loai_id        int not null references loai_may(id),
  ten_loai_goc   text,                           -- tên loại như file gốc (để đối chiếu)
  so_huu         text not null check (so_huu in ('CSH','Thue')),
  chu_tai_san    text,
  don_vi_su_dung text,                           -- VHM / Vinalpha / Vinalpha WDS / Vincons
  so_khung text, so_may text, bien_so text, ma_sap text,
  ban_id         text not null references ban(id),
  trang_thai     trang_thai_may not null default 'lam_viec',
  cap_nhat_luc   timestamptz not null default now()
);
create index may_ban on may(ban_id);
create index may_loai on may(loai_id);

create table nhat_ky_may (
  id        bigserial primary key,
  ma_may    text not null references may(ma),
  luc       timestamptz not null default now(),
  nguoi     uuid,
  truong    text not null,                        -- 'trang_thai' | 'ban_id'
  gia_tri_cu text, gia_tri_moi text, ly_do text
);
create index nkm_may on nhat_ky_may(ma_may, luc desc);

create table xac_nhan_ngay (
  ban_id text references ban(id),
  ngay   date not null,
  nguoi  uuid,
  luc    timestamptz not null default now(),
  so_lai_may int check (so_lai_may >= 0),         -- lái máy có mặt (tùy chọn)
  primary key (ban_id, ngay)
);

-- ---------- Báo hỏng ----------
create table phieu_hong (
  id          bigserial primary key,
  ma_may      text not null references may(ma),
  ban_id      text not null references ban(id),
  ngay_hong   date not null default current_date,
  mo_ta       text not null,
  muc_do      text not null default 'dung_may' check (muc_do in ('dung_may','van_chay')),
  du_kien_xong date,
  don_vi_sua  text,
  chi_phi_du_toan numeric(14,2),
  chi_phi_thuc_te numeric(14,2),
  anh         text[],                              -- đường dẫn ảnh trong Storage
  dong_luc    timestamptz,
  nguoi_lap   uuid default auth.uid(),
  tao_luc     timestamptz not null default now()
);

-- ---------- Điều chuyển ----------
-- Bước: 1 Ban đi đồng ý · 2 P.QLTB kiểm tra · 3 LĐ Khối duyệt (chỉ khi vượt ngưỡng)
--       4 Giao nhận · 5 Ban nhận xác nhận · 6 Hoàn thành
create table phieu_dieu_chuyen (
  id          bigserial primary key,
  ma_may      text not null references may(ma),
  tu_ban      text not null references ban(id),
  den_ban     text not null references ban(id),
  ngay_can    date,
  ly_do       text not null,
  chi_phi_van_chuyen numeric(14,2),
  vuot_nguong boolean not null default false,
  buoc        smallint not null default 1 check (buoc between 1 and 6),
  tu_choi     boolean not null default false,
  nguoi_lap   uuid default auth.uid(),
  tao_luc     timestamptz not null default now(),
  check (tu_ban <> den_ban)
);
create unique index pdc_mot_phieu_mo on phieu_dieu_chuyen(ma_may) where (buoc < 6 and not tu_choi);

create table duyet_dieu_chuyen (
  id       bigserial primary key,
  phieu_id bigint not null references phieu_dieu_chuyen(id),
  buoc     smallint not null,
  dong_y   boolean not null,
  nguoi    uuid,
  ghi_chu  text,
  luc      timestamptz not null default now()
);

create table cau_hinh (
  khoa text primary key,
  gia_tri numeric not null,
  mo_ta text
);
insert into cau_hinh values
  ('nguong_chi_phi_dieu_chuyen', 50000000, 'Chi phí vận chuyển (đồng) trên mức này cần LĐ Khối duyệt'),
  ('ca_thang', 26, 'Số ca làm việc mỗi tháng dùng để tính nhu cầu theo định mức'),
  ('he_so_nhu_cau', 1.05, 'Hệ số nhân nhu cầu khi lập báo cáo cung cầu');

-- ---------- Nhu cầu theo tiến độ – khối lượng – định mức ----------
create table hang_muc (
  id     serial primary key,
  ten    text not null unique,
  don_vi text not null
);
create table dinh_muc (
  hang_muc_id int references hang_muc(id) on delete cascade,
  loai_id     int references loai_may(id),
  nang_suat_ca numeric(12,2) not null check (nang_suat_ca > 0),   -- khối lượng / máy / ca
  lai_may_ca   numeric(4,2) not null default 1 check (lai_may_ca >= 0),
  primary key (hang_muc_id, loai_id)
);
create table cong_viec (
  id          bigserial primary key,
  ban_id      text not null references ban(id),
  hang_muc_id int not null references hang_muc(id),
  khoi_luong  numeric(14,2) not null check (khoi_luong >= 0),
  tu_thang    date not null,                       -- ngày 1 của tháng
  den_thang   date not null,
  ghi_chu     text,
  check (den_thang >= tu_thang),
  check (extract(day from tu_thang) = 1 and extract(day from den_thang) = 1)
);
-- Nhu cầu nhập tay (máy đặc thù không tính được theo định mức), cộng thêm vào nhu cầu theo định mức
create table nhu_cau_nhap_tay (
  ban_id  text references ban(id),
  loai_id int references loai_may(id),
  thang   date not null check (extract(day from thang) = 1),
  so_may  numeric(8,2) not null check (so_may >= 0),
  primary key (ban_id, loai_id, thang)
);
create table lai_may_hien_co (
  ban_id  text primary key references ban(id),
  so_nguoi int not null default 0 check (so_nguoi >= 0),
  cap_nhat_luc timestamptz not null default now()
);

-- ---------- Máy mua đang về ----------
create table may_dang_ve (
  id       bigserial primary key,
  loai_id  int not null references loai_may(id),
  ten_goc  text,
  don_vi   text,
  thang    date not null check (extract(day from thang) = 1),
  so_luong int not null check (so_luong >= 0),
  ban_phan_bo text references ban(id)
);
-- =====================================================================
-- Nghiệp vụ: cập nhật trạng thái, xác nhận ngày, báo hỏng, điều chuyển
-- Mọi hàm chạy với quyền definer và tự kiểm tra vai trò/ban của người gọi.
-- =====================================================================

create or replace function _ghi_log(p_ma text, p_truong text, p_cu text, p_moi text, p_ly_do text)
returns void language sql security definer set search_path = public as $$
  insert into nhat_ky_may(ma_may, nguoi, truong, gia_tri_cu, gia_tri_moi, ly_do)
  values (p_ma, auth.uid(), p_truong, p_cu, p_moi, p_ly_do) $$;

-- Cán bộ BQL / trưởng ban đổi trạng thái máy của ban mình (không đổi máy đang vận chuyển)
create or replace function cap_nhat_trang_thai(p_ma text, p_tt trang_thai_may, p_ly_do text default null)
returns void language plpgsql security definer set search_path = public as $$
declare m may%rowtype;
begin
  select * into m from may where ma = p_ma for update;
  if not found then raise exception 'Không có máy %', p_ma; end if;
  if not (la_qltb() or (toi_vai_tro() in ('bql','truong_ban') and m.ban_id = toi_ban())) then
    raise exception 'Bạn không có quyền cập nhật máy % (đang ở ban %)', p_ma, m.ban_id; end if;
  if m.trang_thai = 'van_chuyen' or p_tt = 'van_chuyen' then
    raise exception 'Trạng thái vận chuyển chỉ đổi qua phiếu điều chuyển'; end if;
  if m.trang_thai = p_tt then return; end if;
  update may set trang_thai = p_tt, cap_nhat_luc = now() where ma = p_ma;
  perform _ghi_log(p_ma, 'trang_thai', m.trang_thai::text, p_tt::text, p_ly_do);
end $$;

-- Ban xác nhận số liệu trong ngày (kèm số lái máy có mặt)
create or replace function xac_nhan_ngay_ban(p_so_lai_may int default null)
returns void language plpgsql security definer set search_path = public as $$
declare b text := toi_ban();
begin
  if toi_vai_tro() not in ('bql','truong_ban') or b is null then raise exception 'Chỉ cán bộ BQLXD xác nhận được'; end if;
  insert into xac_nhan_ngay(ban_id, ngay, nguoi, so_lai_may) values (b, current_date, auth.uid(), p_so_lai_may)
  on conflict (ban_id, ngay) do update set nguoi = excluded.nguoi, luc = now(), so_lai_may = coalesce(excluded.so_lai_may, xac_nhan_ngay.so_lai_may);
  if p_so_lai_may is not null then
    insert into lai_may_hien_co(ban_id, so_nguoi) values (b, p_so_lai_may)
    on conflict (ban_id) do update set so_nguoi = excluded.so_nguoi, cap_nhat_luc = now();
  end if;
end $$;

-- Báo hỏng: lập phiếu → máy sang 'hong'
create or replace function bao_hong(p_ma text, p_mo_ta text, p_du_kien date, p_chi_phi numeric, p_muc_do text default 'dung_may')
returns bigint language plpgsql security definer set search_path = public as $$
declare m may%rowtype; v_id bigint;
begin
  select * into m from may where ma = p_ma for update;
  if not found then raise exception 'Không có máy %', p_ma; end if;
  if not (la_qltb() or m.ban_id = toi_ban()) then raise exception 'Máy % không thuộc ban của bạn', p_ma; end if;
  if coalesce(btrim(p_mo_ta),'') = '' then raise exception 'Cần mô tả hư hỏng'; end if;
  insert into phieu_hong(ma_may, ban_id, mo_ta, muc_do, du_kien_xong, chi_phi_du_toan)
  values (p_ma, m.ban_id, p_mo_ta, p_muc_do, p_du_kien, p_chi_phi) returning id into v_id;
  if m.trang_thai <> 'hong' then
    update may set trang_thai = 'hong', cap_nhat_luc = now() where ma = p_ma;
    perform _ghi_log(p_ma, 'trang_thai', m.trang_thai::text, 'hong', 'Phiếu báo hỏng #' || v_id);
  end if;
  return v_id;
end $$;

create or replace function dong_phieu_hong(p_id bigint, p_chi_phi numeric, p_trang_thai_sau trang_thai_may default 'ton')
returns void language plpgsql security definer set search_path = public as $$
declare p phieu_hong%rowtype; m may%rowtype;
begin
  select * into p from phieu_hong where id = p_id for update;
  if not found or p.dong_luc is not null then raise exception 'Phiếu không tồn tại hoặc đã đóng'; end if;
  if not (la_qltb() or p.ban_id = toi_ban()) then raise exception 'Không có quyền'; end if;
  if p_trang_thai_sau not in ('lam_viec','ton','cho_tra') then raise exception 'Trạng thái sau sửa không hợp lệ'; end if;
  update phieu_hong set dong_luc = now(), chi_phi_thuc_te = p_chi_phi where id = p_id;
  select * into m from may where ma = p.ma_may for update;
  update may set trang_thai = p_trang_thai_sau, cap_nhat_luc = now() where ma = p.ma_may;
  perform _ghi_log(p.ma_may, 'trang_thai', m.trang_thai::text, p_trang_thai_sau::text, 'Đóng phiếu báo hỏng #' || p_id);
end $$;

-- Lập đề nghị điều chuyển (ban cần máy, hoặc P.QLTB)
create or replace function de_nghi_dieu_chuyen(p_ma text, p_den_ban text, p_ngay_can date, p_ly_do text, p_chi_phi numeric default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare m may%rowtype; v_id bigint; v_nguong numeric; v_khoi_di text; v_khoi_den text;
begin
  select * into m from may where ma = p_ma;
  if not found then raise exception 'Không có máy %', p_ma; end if;
  if not (la_qltb() or toi_ban() = p_den_ban) then raise exception 'Chỉ ban nhận hoặc P.QLTB lập đề nghị'; end if;
  if m.trang_thai in ('hong','sua_chua','van_chuyen','cho_tra','da_tra') then
    raise exception 'Máy % đang ở trạng thái %, không điều chuyển được', p_ma, m.trang_thai; end if;
  select gia_tri into v_nguong from cau_hinh where khoa = 'nguong_chi_phi_dieu_chuyen';
  select khoi_id into v_khoi_di from ban where id = m.ban_id;
  select khoi_id into v_khoi_den from ban where id = p_den_ban;
  insert into phieu_dieu_chuyen(ma_may, tu_ban, den_ban, ngay_can, ly_do, chi_phi_van_chuyen, vuot_nguong)
  values (p_ma, m.ban_id, p_den_ban, p_ngay_can, p_ly_do, p_chi_phi,
          coalesce(p_chi_phi,0) > v_nguong or v_khoi_di is distinct from v_khoi_den)
  returning id into v_id;
  return v_id;
end $$;

-- Duyệt / từ chối một bước. Ai được duyệt bước nào:
--  1 trưởng ban đi · 2 P.QLTB · 3 lãnh đạo Khối · 4 cán bộ/trưởng ban đi hoặc đến (giao nhận) · 5 ban nhận
create or replace function duyet_buoc(p_id bigint, p_dong_y boolean, p_ghi_chu text default null)
returns smallint language plpgsql security definer set search_path = public as $$
declare p phieu_dieu_chuyen%rowtype; r vai_tro := toi_vai_tro(); b text := toi_ban(); ok boolean; m may%rowtype;
begin
  select * into p from phieu_dieu_chuyen where id = p_id for update;
  if not found then raise exception 'Không có phiếu %', p_id; end if;
  if p.tu_choi or p.buoc >= 6 then raise exception 'Phiếu % đã kết thúc', p_id; end if;
  ok := case p.buoc
    when 1 then r = 'truong_ban' and b = p.tu_ban
    when 2 then r in ('qltb','admin')
    when 3 then r in ('lanh_dao','admin')
    when 4 then r in ('bql','truong_ban') and b in (p.tu_ban, p.den_ban)
    when 5 then r in ('bql','truong_ban') and b = p.den_ban
  end;
  if not ok then raise exception 'Bạn không có quyền duyệt bước % của phiếu %', p.buoc, p_id; end if;
  insert into duyet_dieu_chuyen(phieu_id, buoc, dong_y, nguoi, ghi_chu) values (p_id, p.buoc, p_dong_y, auth.uid(), p_ghi_chu);
  if not p_dong_y then
    update phieu_dieu_chuyen set tu_choi = true where id = p_id; return p.buoc; end if;
  p.buoc := p.buoc + 1;
  if p.buoc = 3 and not p.vuot_nguong then p.buoc := 4; end if;
  select * into m from may where ma = p.ma_may for update;
  if p.buoc = 4 then             -- đã duyệt xong: máy lên đường
    update may set trang_thai = 'van_chuyen', cap_nhat_luc = now() where ma = p.ma_may;
    perform _ghi_log(p.ma_may, 'trang_thai', m.trang_thai::text, 'van_chuyen', 'Phiếu điều chuyển #' || p_id);
  elsif p.buoc = 6 then          -- ban nhận xác nhận: đổi ban
    update may set ban_id = p.den_ban, trang_thai = 'lam_viec', cap_nhat_luc = now() where ma = p.ma_may;
    perform _ghi_log(p.ma_may, 'ban_id', p.tu_ban, p.den_ban, 'Phiếu điều chuyển #' || p_id);
  end if;
  update phieu_dieu_chuyen set buoc = p.buoc where id = p_id;
  return p.buoc;
end $$;

-- =====================================================================
-- Tính nhu cầu theo tiến độ – khối lượng – định mức
-- số máy/tháng = ceil( khối lượng tháng / (năng suất/ca × ca/tháng × hệ số ca) )
-- lái máy/tháng = ceil( số máy × lái máy/ca × hệ số ca )
-- =====================================================================
create or replace view v_nhu_cau_dinh_muc with (security_invoker = true) as
with ca as (select gia_tri as ca_thang from cau_hinh where khoa = 'ca_thang'),
thang as (
  select cv.id cv_id, cv.ban_id, cv.hang_muc_id, gs::date as thang,
         cv.khoi_luong / ((extract(year from age(cv.den_thang, cv.tu_thang))*12 + extract(month from age(cv.den_thang, cv.tu_thang)) + 1)) as kl_thang
  from cong_viec cv, generate_series(cv.tu_thang, cv.den_thang, interval '1 month') gs)
select t.ban_id, dm.loai_id, t.thang,
       sum(ceil(t.kl_thang / (dm.nang_suat_ca * ca.ca_thang * b.he_so_ca)))::int as so_may,
       sum(ceil(ceil(t.kl_thang / (dm.nang_suat_ca * ca.ca_thang * b.he_so_ca)) * dm.lai_may_ca * b.he_so_ca))::int as so_lai_may
from thang t join dinh_muc dm on dm.hang_muc_id = t.hang_muc_id
join ban b on b.id = t.ban_id cross join ca
group by t.ban_id, dm.loai_id, t.thang;

-- Nhu cầu tổng = theo định mức + nhập tay
create or replace view v_nhu_cau with (security_invoker = true) as
select ban_id, loai_id, thang, sum(so_may)::numeric as so_may, sum(so_lai_may)::numeric as so_lai_may
from (
  select ban_id, loai_id, thang, so_may, so_lai_may from v_nhu_cau_dinh_muc
  union all
  select ban_id, loai_id, thang, so_may, 0 from nhu_cau_nhap_tay) x
group by ban_id, loai_id, thang;

-- Nguồn cung hiện tại theo ban × loại (máy hỏng / sửa / chờ trả / đã trả không tính)
create or replace view v_nguon_cung with (security_invoker = true) as
select ban_id, loai_id,
  count(*) filter (where so_huu = 'CSH' and trang_thai in ('lam_viec','ton','van_chuyen'))  as csh,
  count(*) filter (where so_huu = 'Thue' and trang_thai in ('lam_viec','ton','van_chuyen')) as thue,
  count(*) filter (where trang_thai = 'ton')                     as ton,
  count(*) filter (where trang_thai in ('hong','sua_chua'))       as hong
from may group by ban_id, loai_id;

-- Cung cầu toàn Khối theo tháng (giữ máy thuê / trả hết máy thuê)
create or replace view v_cung_cau_khoi with (security_invoker = true) as
with hs as (select gia_tri h from cau_hinh where khoa = 'he_so_nhu_cau'),
cau as (select thang, sum(so_may) so_may from v_nhu_cau group by thang),
cung as (select sum(csh) csh, sum(thue) thue from v_nguon_cung),
ve as (select thang, sum(sum(so_luong)) over (order by thang) luy_ke from may_dang_ve group by thang)
select c.thang, round(c.so_may * hs.h, 1) as nhu_cau,
       cung.csh, cung.thue,
       coalesce((select luy_ke from ve where ve.thang <= c.thang order by ve.thang desc limit 1), 0) as sap_ve_luy_ke,
       cung.csh + cung.thue + coalesce((select luy_ke from ve where ve.thang <= c.thang order by ve.thang desc limit 1), 0) - round(c.so_may * hs.h, 1) as thua_thieu_giu_thue,
       cung.csh + coalesce((select luy_ke from ve where ve.thang <= c.thang order by ve.thang desc limit 1), 0) - round(c.so_may * hs.h, 1) as thua_thieu_tra_thue
from cau c cross join cung cross join hs order by c.thang;

-- Ban chưa xác nhận số liệu hôm nay
create or replace view v_ban_chua_cap_nhat with (security_invoker = true) as
select b.id, b.ten, (select max(ngay) from xac_nhan_ngay x where x.ban_id = b.id) as lan_cuoi
from ban b where b.dang_thi_cong
  and not exists (select 1 from xac_nhan_ngay x where x.ban_id = b.id and x.ngay = current_date);
-- =====================================================================
-- Phân quyền theo dòng (RLS)
-- Đọc: mọi người đã đăng nhập (cần thấy máy tồn toàn Khối, phiếu liên quan).
-- Ghi trực tiếp: chỉ danh mục / kế hoạch đúng vai trò; trạng thái máy, phiếu
-- điều chuyển, báo hỏng chỉ đổi qua hàm ở 0002 (không có policy update/insert).
-- =====================================================================
do $$ declare t text; begin
  foreach t in array array['khoi','ban','loai_may','ten_ghep','nguoi_dung','may','nhat_ky_may','xac_nhan_ngay',
    'phieu_hong','phieu_dieu_chuyen','duyet_dieu_chuyen','cau_hinh','hang_muc','dinh_muc','cong_viec',
    'nhu_cau_nhap_tay','lai_may_hien_co','may_dang_ve'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy doc_%s on %I for select to authenticated using (true)', t, t);
  end loop;
end $$;

-- Danh mục, định mức, cấu hình, máy đang về, hồ sơ máy: P.QLTB / admin
do $$ declare t text; begin
  foreach t in array array['khoi','ban','loai_may','ten_ghep','hang_muc','dinh_muc','cau_hinh','may_dang_ve','may'] loop
    execute format('create policy ghi_qltb_%s on %I for all to authenticated using (la_qltb()) with check (la_qltb())', t, t);
  end loop;
end $$;

-- Người dùng: chỉ admin quản lý
create policy ghi_admin_nguoi_dung on nguoi_dung for all to authenticated
  using (toi_vai_tro() = 'admin') with check (toi_vai_tro() = 'admin');

-- Kế hoạch công việc và nhu cầu nhập tay: ban mình (bql, trưởng ban) hoặc P.QLTB
create policy ghi_ban_cong_viec on cong_viec for all to authenticated
  using (la_qltb() or (toi_vai_tro() in ('bql','truong_ban') and ban_id = toi_ban()))
  with check (la_qltb() or (toi_vai_tro() in ('bql','truong_ban') and ban_id = toi_ban()));
create policy ghi_ban_nhap_tay on nhu_cau_nhap_tay for all to authenticated
  using (la_qltb() or (toi_vai_tro() in ('bql','truong_ban') and ban_id = toi_ban()))
  with check (la_qltb() or (toi_vai_tro() in ('bql','truong_ban') and ban_id = toi_ban()));
create policy ghi_ban_lai_may on lai_may_hien_co for all to authenticated
  using (la_qltb() or ban_id = toi_ban()) with check (la_qltb() or ban_id = toi_ban());

-- Hệ số ca của ban: ban được sửa hệ số ca của mình qua hàm riêng
create or replace function dat_he_so_ca(p_he_so numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if toi_vai_tro() not in ('bql','truong_ban') then raise exception 'Chỉ cán bộ BQLXD'; end if;
  update ban set he_so_ca = p_he_so where id = toi_ban();
end $$;

-- Hàm nghiệp vụ: chỉ người đã đăng nhập gọi được
revoke execute on all functions in schema public from anon, public;
grant execute on all functions in schema public to authenticated;
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
