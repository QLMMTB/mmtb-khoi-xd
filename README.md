# Quản lý MMTB Khối XD – bản test

Ứng dụng web cho 60–100 BQLXD cập nhật máy hằng ngày, lập nhu cầu MMTB theo tiến độ – khối lượng – định mức,
tính lái máy (LXLM), quản lý máy tồn, báo hỏng, điều chuyển nhiều cấp duyệt.

**Trang chạy thử:** https://qlmmtb.github.io/mmtb-khoi-xd/ (GitHub Pages của tổ chức QLMMTB, tự triển khai khi thư mục `web/` thay đổi).

- `web/` – trang web tĩnh (HTML/JS thuần, thư viện Supabase tải từ CDN). Đưa lên Cloudflare Pages, thư mục xuất bản = `web`.
- `supabase/migrations/` – cơ sở dữ liệu: bảng, hàm nghiệp vụ, phân quyền (RLS). Chạy theo thứ tự 0001 → 0003.
- `supabase/tao_nguoi_dung.sql` – gán vai trò cho tài khoản.
- `tools/seed_from_excel.py` – sinh dữ liệu ban đầu từ file `Danh sách máy` và file REV2.
- `test/` – chạy thử cơ sở dữ liệu trên PostgreSQL thường (giả lập Supabase).

## Triển khai lần đầu
1. Supabase → SQL Editor: chạy lần lượt `0001_schema.sql`, `0002_logic.sql`, `0003_rls.sql`, rồi file `seed.sql`.
2. Supabase → Authentication → Users → Add user (email + mật khẩu, tick Auto Confirm). Gán vai trò bằng `tao_nguoi_dung.sql`.
3. Sửa `web/config.js`: Project URL + khóa anon public (KHÔNG dùng khóa service_role).
4. Cloudflare → Workers & Pages → Create → Pages → Connect to Git → chọn repo; Build command để trống; Build output directory = `web`.

## Quy tắc nghiệp vụ chính
- Mỗi máy có đúng 1 ban giữ và 1 trạng thái; đổi trạng thái/vị trí chỉ qua hàm có kiểm tra quyền, mọi thay đổi ghi `nhat_ky_may`.
- Điều chuyển: ban đi đồng ý → P.QLTB kiểm tra → LĐ Khối duyệt (khi khác khối hoặc chi phí vượt ngưỡng `cau_hinh`) → giao nhận → ban nhận xác nhận (lúc này máy mới đổi ban).
- Nhu cầu theo định mức: số máy/tháng = ceil(khối lượng tháng / (năng suất/ca × ca/tháng × hệ số ca)); lái máy = ceil(số máy × lái máy/ca × hệ số ca).
- Nguồn cung chỉ tính máy làm việc, tồn, đang vận chuyển; bỏ máy SGC, VFM, Vinfast khi nhập dữ liệu.
- Định mức trong seed là SỐ MẪU – P.QLTB thay bằng định mức chính thức.
