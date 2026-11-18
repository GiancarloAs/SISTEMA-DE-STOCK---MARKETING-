-- 03_importar_estado_excel.sql (OPCIONAL)
-- Carga el estado del Excel v2 como control del mes actual.
-- Cada letra = un artículo en el orden del Excel (columna C → Y):
--   T = ✔ tiene · N = vacío, no tiene · E = "1", enviado por marketing (queda En camino)
-- Las tiendas con la fila vacía en el Excel no se importan (quedan pendientes).
with _xl (code, s) as (values
  ('TRU02','TTTTTNTTTNTTTTNTTNTNNNT'),
  ('TRU03','TTNTTTNNNNNTNTNNNNNNNTN'),
  ('TRU04','TTTTTTTTTTTTTTTNNNNTTTT'),
  ('TRU05','NNTTNTTTTNTTTTNNNTNTTTN'),
  ('TRU07','TTTTTTNTTTTNTTNNNNNNTTT'),
  ('TRU08','TTTTTTTTTTTTTTTNNNNNTTT'),
  ('TRU09','TTTTTTTTTTTNTTTNNTNTTTT'),
  ('TRU10','TTTTTTTTTTTTTTTTTTTTTTT'),
  ('CIX01','EEETEEETEEETTEEEEENTTTT'),
  ('CIX02','TTEEETEETTETEEEEEENTTTT'),
  ('PIU01','TTETTTTETEENTTTTTTNTTTT'),
  ('PIU02','TTEETTETTETNTTTETTNETTT'),
  ('PIU03','TTTTTTTTTTTTTTEEETNTTTT'),
  ('PIU04','EEETETEETTENTEEEEENNTTT'),
  ('TPP02','TTTTTNNNNNNTNNNNNNTTNNN')
), subs as (
  insert into public.submissions (store_id, period, notes, source)
  select st.id, public.current_period(), 'Importado del Excel v2', 'importado'
  from _xl join public.stores st on st.code = _xl.code
  returning id, store_id
), cells as (
  select st.id store_id, i.id item_id, substr(_xl.s, i.sort, 1) ch
  from _xl join public.stores st on st.code = _xl.code
  join public.items i on i.sort between 1 and length(_xl.s) and i.photo_path like 'seed/%'
), si as (
  insert into public.submission_items (submission_id, item_id, status)
  select subs.id, cells.item_id, case cells.ch when 'T' then 'tiene' else 'no_tiene' end
  from subs join cells using (store_id)
  returning 1
)
insert into public.shipments (store_id, item_id, qty, note)
select store_id, item_id, 1, 'Enviado según Excel v2' from cells where ch = 'E';
