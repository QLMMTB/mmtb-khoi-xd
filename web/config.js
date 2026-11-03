// Điền 2 giá trị của project Supabase (Project Settings → API).
// Khóa "anon public" được phép nằm trong trang web; quyền truy cập do RLS trong cơ sở dữ liệu kiểm soát.
// TUYỆT ĐỐI không đặt khóa service_role ở đây.
window.MMTB_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
  SUPABASE_ANON_KEY: "YOUR-ANON-KEY"
};
