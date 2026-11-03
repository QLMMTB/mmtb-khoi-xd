\set ON_ERROR_STOP on
-- dữ liệu thử
insert into khoi values ('KTC1','Khối thi công 1'),('KTC2','Khối thi công 2');
insert into ban(id,ten,khoi_id,he_so_ca) values ('HLX','DA HLX','KTC2',1.5),('OLP','OLP','KTC1',1),('CG','DA Cần Giờ','KTC2',1);
insert into loai_may(ten_chuan) values ('Máy xúc bánh xích 200'),('Xe ben 16 tấn VC04'),('Máy phát điện 3 pha 25KVA');
insert into ten_ghep values (norm_ten('Máy phát điện 3 pha 20-25KVA'),'Máy phát điện 3 pha 20-25KVA',3,'test');
select tim_loai('máy phát điện 3 pha  20-25kva ') = 3 as ghep_khong_phan_biet_hoa_thuong;
insert into auth.users values ('00000000-0000-0000-0000-000000000001','bql.hlx@x'),('00000000-0000-0000-0000-000000000002','tb.olp@x'),
 ('00000000-0000-0000-0000-000000000003','qltb@x'),('00000000-0000-0000-0000-000000000004','ld@x'),('00000000-0000-0000-0000-000000000005','bql.olp@x');
insert into nguoi_dung values ('00000000-0000-0000-0000-000000000001','bql.hlx@x','BQL HLX','bql','HLX'),
 ('00000000-0000-0000-0000-000000000002','tb.olp@x','TB OLP','truong_ban','OLP'),('00000000-0000-0000-0000-000000000003','qltb@x','QLTB','qltb',null),
 ('00000000-0000-0000-0000-000000000004','ld@x','LĐ','lanh_dao',null),('00000000-0000-0000-0000-000000000005','bql.olp@x','BQL OLP','bql','OLP');
insert into may(ma,loai_id,so_huu,ban_id,trang_thai) values ('V-1',1,'CSH','OLP','ton'),('V-2',1,'CSH','HLX','lam_viec'),('T-3',2,'Thue','HLX','lam_viec');
insert into hang_muc(ten,don_vi) values ('Đào đất','m3');
insert into dinh_muc values (1,1,400,1),(1,2,100,1);
insert into cong_viec(ban_id,hang_muc_id,khoi_luong,tu_thang,den_thang) values ('HLX',1,600000,'2026-11-01','2027-04-01');
insert into may_dang_ve(loai_id,thang,so_luong) values (1,'2026-11-01',5),(2,'2026-12-01',10);

set role authenticated;
-- BQL HLX
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select cap_nhat_trang_thai('V-2','ton','test');
do $$ begin perform cap_nhat_trang_thai('V-1','hong'); raise exception 'LỖI: sửa được máy ban khác'; exception when others then
  if sqlerrm like 'LỖI%' then raise; end if; raise notice 'OK chặn sửa máy ban khác: %', sqlerrm; end $$;
do $$ begin update may set trang_thai='hong' where ma='V-2'; if found then raise exception 'LỖI: update trực tiếp được'; end if; raise notice 'OK RLS chặn update trực tiếp'; end $$;
select xac_nhan_ngay_ban(40);
select de_nghi_dieu_chuyen('V-1','HLX','2026-11-10','Đào đất khu B',10000000) as phieu;  -- khác khối => vượt ngưỡng
select id,buoc,vuot_nguong from phieu_dieu_chuyen;
do $$ begin perform duyet_buoc(1,true); raise exception 'LỖI: BQL HLX duyệt bước 1'; exception when others then
  if sqlerrm like 'LỖI%' then raise; end if; raise notice 'OK chặn sai người duyệt: %', sqlerrm; end $$;
-- Trưởng ban OLP đồng ý cho đi
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002'; select duyet_buoc(1,true,'Đồng ý');
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003'; select duyet_buoc(1,true,'Máy tốt');
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004'; select duyet_buoc(1,true,'Duyệt');
select ma,ban_id,trang_thai from may where ma='V-1';
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005'; select duyet_buoc(1,true,'Đã giao');
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001'; select duyet_buoc(1,true,'Đã nhận');
select ma,ban_id,trang_thai from may where ma='V-1';
select ma_may,truong,gia_tri_cu,gia_tri_moi from nhat_ky_may order by id;
-- báo hỏng + đóng phiếu
select bao_hong('T-3','Hỏng bơm thủy lực','2026-11-08',18000000) as phieu_hong;
select trang_thai from may where ma='T-3';
select dong_phieu_hong(1,17500000,'lam_viec'); select trang_thai from may where ma='T-3';
-- nhu cầu theo định mức (HLX: 100.000 m3/tháng, ca 1.5 => máy xúc ceil(100000/(400*26*1.5))=7, xe ben ceil(100000/(100*39))=26)
select l.ten_chuan, n.thang, n.so_may, n.so_lai_may from v_nhu_cau n join loai_may l on l.id=n.loai_id where n.thang='2026-11-01' order by 1;
select * from v_cung_cau_khoi limit 3;
select * from v_nguon_cung order by 1,2;
-- cong_viec: BQL HLX không sửa được kế hoạch OLP
do $$ begin insert into cong_viec(ban_id,hang_muc_id,khoi_luong,tu_thang,den_thang) values ('OLP',1,1,'2026-11-01','2026-11-01');
 raise exception 'LỖI: chèn kế hoạch ban khác'; exception when insufficient_privilege then raise notice 'OK RLS chặn kế hoạch ban khác'; end $$;
reset role;
