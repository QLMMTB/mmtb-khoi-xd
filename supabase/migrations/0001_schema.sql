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
