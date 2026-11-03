-- =====================================================================
-- TẠO TÀI KHOẢN CHẠY THỬ (người dùng tự chạy trong Supabase SQL Editor)
-- Bước duy nhất phải sửa: thay chữ  NHAP_MAT_KHAU  ở dòng dưới bằng mật khẩu thử.
-- Chạy lại nhiều lần không sao: tài khoản đã có thì bỏ qua, chỉ cập nhật vai trò.
-- =====================================================================
do $$
declare
  mk text := 'NHAP_MAT_KHAU';
  r record; uid uuid;
begin
  if mk = 'NHAP_MAT_KHAU' then raise exception 'Chưa thay NHAP_MAT_KHAU bằng mật khẩu'; end if;

  -- 1) Đổi email tài khoản Lãnh đạo Khối cũ
  update auth.users set email = 'mmtbldk@mmtb.com', updated_at = now() where lower(email) = 'mmtbdamcld@mmtb.com';
  update auth.identities set identity_data = identity_data || jsonb_build_object('email','mmtbldk@mmtb.com'), updated_at = now()
   where provider = 'email' and user_id = (select id from auth.users where lower(email) = 'mmtbldk@mmtb.com');

  -- 2) Danh sách tài khoản: email, họ tên, vai trò, ban (tìm theo tên ban)
  create temp table ds(email text, ho_ten text, vai_tro text, ban_like text) on commit drop;
  insert into ds values
   ('mmtb_ttt@mmtb.com','Quản trị hệ thống (TTT)','admin',null),
   ('mmtbldk@mmtb.com','Lãnh đạo Khối','lanh_dao',null),
   ('qltb_01@mmtb.com','P.QLTB – cán bộ 1','qltb',null),
   ('qltb_02@mmtb.com','P.QLTB – cán bộ 2','qltb',null),
   ('hlx_bql@mmtb.com','DA Hạ Long Xanh – BQL','bql','%Hạ Long Xanh%'),
   ('hlx_tb@mmtb.com','DA Hạ Long Xanh – Trưởng ban','truong_ban','%Hạ Long Xanh%'),
   ('olp_bql@mmtb.com','DA Olympic – BQL','bql','Dự án Olympic'),
   ('olp_tb@mmtb.com','DA Olympic – Trưởng ban','truong_ban','Dự án Olympic'),
   ('cg_bql@mmtb.com','DA Green Paradise Cần Giờ – BQL','bql','%Green Paradise%'),
   ('cg_tb@mmtb.com','DA Green Paradise Cần Giờ – Trưởng ban','truong_ban','%Green Paradise%'),
   ('va_bql@mmtb.com','DA Vinmetal Vũng Áng – BQL','bql','%Vinmetal%'),
   ('va_tb@mmtb.com','DA Vinmetal Vũng Áng – Trưởng ban','truong_ban','%Vinmetal%'),
   ('hm_bql@mmtb.com','DA Berjaya Hóc Môn – BQL','bql','%Berjaya%'),
   ('hm_tb@mmtb.com','DA Berjaya Hóc Môn – Trưởng ban','truong_ban','%Berjaya%'),
   ('ml_bql@mmtb.com','DA Mỹ Lâm – BQL','bql','%Mỹ Lâm%'),
   ('ml_tb@mmtb.com','DA Mỹ Lâm – Trưởng ban','truong_ban','%Mỹ Lâm%'),
   ('damc_bql@mmtb.com','DA Chùa Minh Châu – BQL','bql','%MINH CHÂU%'),
   ('damc_tb@mmtb.com','DA Chùa Minh Châu – Trưởng ban','truong_ban','%MINH CHÂU%'),
   ('cl_bql@mmtb.com','DA VH Cổ Loa – BQL','bql','%Cổ Loa%'),
   ('cl_tb@mmtb.com','DA VH Cổ Loa – Trưởng ban','truong_ban','%Cổ Loa%'),
   ('ocp2_bql@mmtb.com','DA Ocean Park 2 – BQL','bql','%Ocean Park 2%'),
   ('ocp2_tb@mmtb.com','DA Ocean Park 2 – Trưởng ban','truong_ban','%Ocean Park 2%');

  for r in select * from ds loop
    select id into uid from auth.users where lower(email) = r.email;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change, email_change_token_current,
        phone_change, phone_change_token, reauthentication_token)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', r.email,
        extensions.crypt(mk, extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}', jsonb_build_object('ho_ten', r.ho_ten), now(), now(),
        '', '', '', '', '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), uid, uid::text, 'email',
        jsonb_build_object('sub', uid::text, 'email', r.email, 'email_verified', true), now(), now(), now());
    end if;
    insert into public.nguoi_dung (id, email, ho_ten, vai_tro, ban_id)
    values (uid, r.email, r.ho_ten, r.vai_tro::vai_tro,
      case when r.ban_like is null then null else (select id from public.ban where ten ilike r.ban_like order by id limit 1) end)
    on conflict (id) do update set email = excluded.email, ho_ten = excluded.ho_ten, vai_tro = excluded.vai_tro, ban_id = excluded.ban_id;
    if r.ban_like is not null and not exists (select 1 from public.ban where ten ilike r.ban_like) then
      raise exception 'Không tìm thấy ban cho %', r.email; end if;
  end loop;
end $$;

-- Kết quả
select n.email, n.ho_ten, n.vai_tro, b.ten as ban
from public.nguoi_dung n left join public.ban b on b.id = n.ban_id
order by n.vai_tro, n.email;
