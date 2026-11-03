\set ON_ERROR_STOP on
-- HLX hệ số ca 1.5 (bảng ban đặt sẵn = 1; đặt lại để kiểm tra)
update ban set he_so_ca = 1.5 where ten = 'Dự án Hạ Long Xanh';
insert into cong_viec(ban_id,hang_muc_id,khoi_luong,tu_thang,den_thang)
select b.id, h.id, v.kl, v.tu::date, v.den::date from ban b, hang_muc h,
 (values ('Đào xúc cát, xỉ bằng máy',600000,'2026-11-01','2027-04-01'),('Nhà thấp tầng – phần thô',500,'2026-11-01','2027-04-01'),
         ('Ép cọc',60000,'2026-11-01','2027-01-01'),('Nhà thấp tầng – phần hoàn thiện',300,'2027-01-01','2027-06-01')) v(hm,kl,tu,den)
where b.ten='Dự án Hạ Long Xanh' and h.ten=v.hm;
select l.ten_chuan, n.so_may, n.so_lai_may from v_nhu_cau n join loai_may l on l.id=n.loai_id join ban b on b.id=n.ban_id
where b.ten='Dự án Hạ Long Xanh' and n.thang='2026-11-01' order by 1;
-- BQL chọn máy ép cọc 680 thay cho 460
insert into cong_viec_chon select c.id, 'Máy ép cọc', tim_loai('Máy ép cọc 680') from cong_viec c join hang_muc h on h.id=c.hang_muc_id where h.ten='Ép cọc';
select 'sau khi chọn 680' x, l.ten_chuan, n.so_may from v_nhu_cau n join loai_may l on l.id=n.loai_id where n.thang='2026-11-01' and (l.ten_chuan ilike 'Máy ép cọc%' or l.ten_chuan ilike '%Kato 50-60%') order by 2;
select thang, so_may from (select thang, sum(so_may) so_may from v_nhu_cau group by thang) x order by thang;
select * from v_cung_cau_khoi;
