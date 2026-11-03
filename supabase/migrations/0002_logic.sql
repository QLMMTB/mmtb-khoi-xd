-- =====================================================================
-- Nghiệp vụ: cập nhật trạng thái, xác nhận ngày, báo hỏng, điều chuyển
-- Mọi hàm chạy với quyền definer và tự kiểm tra vai trò/ban của người gọi.
-- =====================================================================

create or replace function _ghi_log(p_ma text, p_truong text, p_cu text, p_moi text, p_ly_do text)
returns void language sql security definer set search_path = public as $$
  insert into nhat_ky_may(ma_may, nguoi, truong, gia_tri_cu, gia_tri_moi, ly_do)
  values (p_ma, auth.uid(), p_truong, p_cu, p_moi, p_ly_do) $$;

-- Cán bộ BQL / trưởng ban đổi trạng thái máy của ban mình (không đổi máy đang vận chuyển)
create or replace function cap_nhat_trang_thai(p_ma text, p_tt trang_thai_may, p_ly_do text default null)
returns void language plpgsql security definer set search_path = public as $$
declare m may%rowtype;
begin
  select * into m from may where ma = p_ma for update;
  if not found then raise exception 'Không có máy %', p_ma; end if;
  if not (la_qltb() or (toi_vai_tro() in ('bql','truong_ban') and m.ban_id = toi_ban())) then
    raise exception 'Bạn không có quyền cập nhật máy % (đang ở ban %)', p_ma, m.ban_id; end if;
  if m.trang_thai = 'van_chuyen' or p_tt = 'van_chuyen' then
    raise exception 'Trạng thái vận chuyển chỉ đổi qua phiếu điều chuyển'; end if;
  if m.trang_thai = p_tt then return; end if;
  update may set trang_thai = p_tt, cap_nhat_luc = now() where ma = p_ma;
  perform _ghi_log(p_ma, 'trang_thai', m.trang_thai::text, p_tt::text, p_ly_do);
end $$;

-- Ban xác nhận số liệu trong ngày (kèm số lái máy có mặt)
create or replace function xac_nhan_ngay_ban(p_so_lai_may int default null)
returns void language plpgsql security definer set search_path = public as $$
declare b text := toi_ban();
begin
  if toi_vai_tro() not in ('bql','truong_ban') or b is null then raise exception 'Chỉ cán bộ BQLXD xác nhận được'; end if;
  insert into xac_nhan_ngay(ban_id, ngay, nguoi, so_lai_may) values (b, current_date, auth.uid(), p_so_lai_may)
  on conflict (ban_id, ngay) do update set nguoi = excluded.nguoi, luc = now(), so_lai_may = coalesce(excluded.so_lai_may, xac_nhan_ngay.so_lai_may);
  if p_so_lai_may is not null then
    insert into lai_may_hien_co(ban_id, so_nguoi) values (b, p_so_lai_may)
    on conflict (ban_id) do update set so_nguoi = excluded.so_nguoi, cap_nhat_luc = now();
  end if;
end $$;

-- Báo hỏng: lập phiếu → máy sang 'hong'
create or replace function bao_hong(p_ma text, p_mo_ta text, p_du_kien date, p_chi_phi numeric, p_muc_do text default 'dung_may')
returns bigint language plpgsql security definer set search_path = public as $$
declare m may%rowtype; v_id bigint;
begin
  select * into m from may where ma = p_ma for update;
  if not found then raise exception 'Không có máy %', p_ma; end if;
  if not (la_qltb() or m.ban_id = toi_ban()) then raise exception 'Máy % không thuộc ban của bạn', p_ma; end if;
  if coalesce(btrim(p_mo_ta),'') = '' then raise exception 'Cần mô tả hư hỏng'; end if;
  insert into phieu_hong(ma_may, ban_id, mo_ta, muc_do, du_kien_xong, chi_phi_du_toan)
  values (p_ma, m.ban_id, p_mo_ta, p_muc_do, p_du_kien, p_chi_phi) returning id into v_id;
  if m.trang_thai <> 'hong' then
    update may set trang_thai = 'hong', cap_nhat_luc = now() where ma = p_ma;
    perform _ghi_log(p_ma, 'trang_thai', m.trang_thai::text, 'hong', 'Phiếu báo hỏng #' || v_id);
  end if;
  return v_id;
end $$;

create or replace function dong_phieu_hong(p_id bigint, p_chi_phi numeric, p_trang_thai_sau trang_thai_may default 'ton')
returns void language plpgsql security definer set search_path = public as $$
declare p phieu_hong%rowtype; m may%rowtype;
begin
  select * into p from phieu_hong where id = p_id for update;
  if not found or p.dong_luc is not null then raise exception 'Phiếu không tồn tại hoặc đã đóng'; end if;
  if not (la_qltb() or p.ban_id = toi_ban()) then raise exception 'Không có quyền'; end if;
  if p_trang_thai_sau not in ('lam_viec','ton','cho_tra') then raise exception 'Trạng thái sau sửa không hợp lệ'; end if;
  update phieu_hong set dong_luc = now(), chi_phi_thuc_te = p_chi_phi where id = p_id;
  select * into m from may where ma = p.ma_may for update;
  update may set trang_thai = p_trang_thai_sau, cap_nhat_luc = now() where ma = p.ma_may;
  perform _ghi_log(p.ma_may, 'trang_thai', m.trang_thai::text, p_trang_thai_sau::text, 'Đóng phiếu báo hỏng #' || p_id);
end $$;

-- Lập đề nghị điều chuyển (ban cần máy, hoặc P.QLTB)
create or replace function de_nghi_dieu_chuyen(p_ma text, p_den_ban text, p_ngay_can date, p_ly_do text, p_chi_phi numeric default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare m may%rowtype; v_id bigint; v_nguong numeric; v_khoi_di text; v_khoi_den text;
begin
  select * into m from may where ma = p_ma;
  if not found then raise exception 'Không có máy %', p_ma; end if;
  if not (la_qltb() or toi_ban() = p_den_ban) then raise exception 'Chỉ ban nhận hoặc P.QLTB lập đề nghị'; end if;
  if m.trang_thai in ('hong','sua_chua','van_chuyen','cho_tra','da_tra') then
    raise exception 'Máy % đang ở trạng thái %, không điều chuyển được', p_ma, m.trang_thai; end if;
  select gia_tri into v_nguong from cau_hinh where khoa = 'nguong_chi_phi_dieu_chuyen';
  select khoi_id into v_khoi_di from ban where id = m.ban_id;
  select khoi_id into v_khoi_den from ban where id = p_den_ban;
  insert into phieu_dieu_chuyen(ma_may, tu_ban, den_ban, ngay_can, ly_do, chi_phi_van_chuyen, vuot_nguong)
  values (p_ma, m.ban_id, p_den_ban, p_ngay_can, p_ly_do, p_chi_phi,
          coalesce(p_chi_phi,0) > v_nguong or v_khoi_di is distinct from v_khoi_den)
  returning id into v_id;
  return v_id;
end $$;

-- Duyệt / từ chối một bước. Ai được duyệt bước nào:
--  1 trưởng ban đi · 2 P.QLTB · 3 lãnh đạo Khối · 4 cán bộ/trưởng ban đi hoặc đến (giao nhận) · 5 ban nhận
create or replace function duyet_buoc(p_id bigint, p_dong_y boolean, p_ghi_chu text default null)
returns smallint language plpgsql security definer set search_path = public as $$
declare p phieu_dieu_chuyen%rowtype; r vai_tro := toi_vai_tro(); b text := toi_ban(); ok boolean; m may%rowtype;
begin
  select * into p from phieu_dieu_chuyen where id = p_id for update;
  if not found then raise exception 'Không có phiếu %', p_id; end if;
  if p.tu_choi or p.buoc >= 6 then raise exception 'Phiếu % đã kết thúc', p_id; end if;
  ok := case p.buoc
    when 1 then r = 'truong_ban' and b = p.tu_ban
    when 2 then r in ('qltb','admin')
    when 3 then r in ('lanh_dao','admin')
    when 4 then r in ('bql','truong_ban') and b in (p.tu_ban, p.den_ban)
    when 5 then r in ('bql','truong_ban') and b = p.den_ban
  end;
  if not ok then raise exception 'Bạn không có quyền duyệt bước % của phiếu %', p.buoc, p_id; end if;
  insert into duyet_dieu_chuyen(phieu_id, buoc, dong_y, nguoi, ghi_chu) values (p_id, p.buoc, p_dong_y, auth.uid(), p_ghi_chu);
  if not p_dong_y then
    update phieu_dieu_chuyen set tu_choi = true where id = p_id; return p.buoc; end if;
  p.buoc := p.buoc + 1;
  if p.buoc = 3 and not p.vuot_nguong then p.buoc := 4; end if;
  select * into m from may where ma = p.ma_may for update;
  if p.buoc = 4 then             -- đã duyệt xong: máy lên đường
    update may set trang_thai = 'van_chuyen', cap_nhat_luc = now() where ma = p.ma_may;
    perform _ghi_log(p.ma_may, 'trang_thai', m.trang_thai::text, 'van_chuyen', 'Phiếu điều chuyển #' || p_id);
  elsif p.buoc = 6 then          -- ban nhận xác nhận: đổi ban
    update may set ban_id = p.den_ban, trang_thai = 'lam_viec', cap_nhat_luc = now() where ma = p.ma_may;
    perform _ghi_log(p.ma_may, 'ban_id', p.tu_ban, p.den_ban, 'Phiếu điều chuyển #' || p_id);
  end if;
  update phieu_dieu_chuyen set buoc = p.buoc where id = p_id;
  return p.buoc;
end $$;

-- =====================================================================
-- Tính nhu cầu theo tiến độ – khối lượng – định mức
-- số máy/tháng = ceil( khối lượng tháng / (năng suất/ca × ca/tháng × hệ số ca) )
-- lái máy/tháng = ceil( số máy × lái máy/ca × hệ số ca )
-- =====================================================================
create or replace view v_nhu_cau_dinh_muc with (security_invoker = true) as
with ca as (select gia_tri as ca_thang from cau_hinh where khoa = 'ca_thang'),
thang as (
  select cv.id cv_id, cv.ban_id, cv.hang_muc_id, gs::date as thang,
         cv.khoi_luong / ((extract(year from age(cv.den_thang, cv.tu_thang))*12 + extract(month from age(cv.den_thang, cv.tu_thang)) + 1)) as kl_thang
  from cong_viec cv, generate_series(cv.tu_thang, cv.den_thang, interval '1 month') gs)
select t.ban_id, dm.loai_id, t.thang,
       sum(ceil(t.kl_thang / (dm.nang_suat_ca * ca.ca_thang * b.he_so_ca)))::int as so_may,
       sum(ceil(ceil(t.kl_thang / (dm.nang_suat_ca * ca.ca_thang * b.he_so_ca)) * dm.lai_may_ca * b.he_so_ca))::int as so_lai_may
from thang t join dinh_muc dm on dm.hang_muc_id = t.hang_muc_id
join ban b on b.id = t.ban_id cross join ca
group by t.ban_id, dm.loai_id, t.thang;

-- Nhu cầu tổng = theo định mức + nhập tay
create or replace view v_nhu_cau with (security_invoker = true) as
select ban_id, loai_id, thang, sum(so_may)::numeric as so_may, sum(so_lai_may)::numeric as so_lai_may
from (
  select ban_id, loai_id, thang, so_may, so_lai_may from v_nhu_cau_dinh_muc
  union all
  select ban_id, loai_id, thang, so_may, 0 from nhu_cau_nhap_tay) x
group by ban_id, loai_id, thang;

-- Nguồn cung hiện tại theo ban × loại (máy hỏng / sửa / chờ trả / đã trả không tính)
create or replace view v_nguon_cung with (security_invoker = true) as
select ban_id, loai_id,
  count(*) filter (where so_huu = 'CSH' and trang_thai in ('lam_viec','ton','van_chuyen'))  as csh,
  count(*) filter (where so_huu = 'Thue' and trang_thai in ('lam_viec','ton','van_chuyen')) as thue,
  count(*) filter (where trang_thai = 'ton')                     as ton,
  count(*) filter (where trang_thai in ('hong','sua_chua'))       as hong
from may group by ban_id, loai_id;

-- Cung cầu toàn Khối theo tháng (giữ máy thuê / trả hết máy thuê)
create or replace view v_cung_cau_khoi with (security_invoker = true) as
with hs as (select gia_tri h from cau_hinh where khoa = 'he_so_nhu_cau'),
cau as (select thang, sum(so_may) so_may from v_nhu_cau group by thang),
cung as (select sum(csh) csh, sum(thue) thue from v_nguon_cung),
ve as (select thang, sum(sum(so_luong)) over (order by thang) luy_ke from may_dang_ve group by thang)
select c.thang, round(c.so_may * hs.h, 1) as nhu_cau,
       cung.csh, cung.thue,
       coalesce((select luy_ke from ve where ve.thang <= c.thang order by ve.thang desc limit 1), 0) as sap_ve_luy_ke,
       cung.csh + cung.thue + coalesce((select luy_ke from ve where ve.thang <= c.thang order by ve.thang desc limit 1), 0) - round(c.so_may * hs.h, 1) as thua_thieu_giu_thue,
       cung.csh + coalesce((select luy_ke from ve where ve.thang <= c.thang order by ve.thang desc limit 1), 0) - round(c.so_may * hs.h, 1) as thua_thieu_tra_thue
from cau c cross join cung cross join hs order by c.thang;

-- Ban chưa xác nhận số liệu hôm nay
create or replace view v_ban_chua_cap_nhat with (security_invoker = true) as
select b.id, b.ten, (select max(ngay) from xac_nhan_ngay x where x.ban_id = b.id) as lan_cuoi
from ban b where b.dang_thi_cong
  and not exists (select 1 from xac_nhan_ngay x where x.ban_id = b.id and x.ngay = current_date);
