-- Gán vai trò cho người dùng (chạy trong Supabase → SQL Editor, sau khi đã tạo tài khoản ở Authentication → Users → Add user)
-- vai_tro: 'bql' (cán bộ thiết bị BQLXD) | 'truong_ban' | 'qltb' | 'lanh_dao' | 'admin'
-- ban_id: mã ban (xem: select id, ten from ban order by ten;) – bắt buộc với bql và truong_ban

insert into nguoi_dung (id, email, ho_ten, vai_tro, ban_id)
select id, email, 'Họ tên', 'admin', null from auth.users where email = 'email.cua.ban@congty.vn'
on conflict (id) do update set vai_tro = excluded.vai_tro, ban_id = excluded.ban_id, ho_ten = excluded.ho_ten;

-- Ví dụ cán bộ thiết bị ban Hạ Long Xanh:
-- insert into nguoi_dung (id, email, ho_ten, vai_tro, ban_id)
-- select id, email, 'Nguyễn Văn A', 'bql', (select id from ban where ten = 'Dự án Hạ Long Xanh')
-- from auth.users where email = 'a.nguyen@congty.vn';
