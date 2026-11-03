-- =====================================================================
-- Bảo mật: chỉ người đã được quản trị gán vai trò (có dòng trong nguoi_dung) mới đọc được dữ liệu.
-- Lý do: Supabase mặc định cho phép tự đăng ký tài khoản; một tài khoản tự đăng ký
-- không được thấy gì cho đến khi admin gán vai trò.
-- =====================================================================
create or replace function da_cap_quyen() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from nguoi_dung where id = auth.uid()) $$;
grant execute on function da_cap_quyen() to authenticated;

do $$ declare t text; begin
  foreach t in array array['khoi','ban','loai_may','ten_ghep','may','nhat_ky_may','xac_nhan_ngay',
    'phieu_hong','phieu_dieu_chuyen','duyet_dieu_chuyen','cau_hinh','hang_muc','dinh_muc','cong_viec',
    'nhu_cau_nhap_tay','lai_may_hien_co','may_dang_ve','dinh_muc_theo_may','cong_viec_chon'] loop
    execute format('drop policy if exists doc_%s on %I', t, t);
    execute format('create policy doc_%s on %I for select to authenticated using (da_cap_quyen())', t, t);
  end loop;
end $$;

-- Bảng người dùng: mỗi người đọc được dòng của mình; người đã cấp quyền đọc được danh sách (để hiện tên)
drop policy if exists doc_nguoi_dung on nguoi_dung;
create policy doc_nguoi_dung on nguoi_dung for select to authenticated using (id = auth.uid() or da_cap_quyen());

-- Các hàm nghiệp vụ đã tự kiểm tra vai trò; bổ sung chặn tài khoản chưa cấp quyền ở hàm xác nhận ngày (đã có kiểm tra vai trò).
