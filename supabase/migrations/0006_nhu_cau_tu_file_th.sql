-- =====================================================================
-- Nhu cầu nạp từ file "TH MMTB 2026_2027 theo tiến độ" (sheet từng dự án).
-- Ghi vào nhu_cau_nhap_tay, đánh dấu nguồn để lần nạp sau thay đúng phần đã nạp từ file,
-- không xóa nhu cầu BQLXD tự nhập tay.
-- =====================================================================
alter table nhu_cau_nhap_tay add column if not exists nguon text not null default 'nhap_tay';
comment on column nhu_cau_nhap_tay.nguon is 'nhap_tay = BQLXD/P.QLTB nhập trên phần mềm; TH MMTB = nạp từ file TH MMTB theo tiến độ';
