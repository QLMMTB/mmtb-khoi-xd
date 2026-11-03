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
