-- 02_seed.sql · Datos iniciales tomados de Inventario_Control_Afiches_Noraves_v2.xlsx

insert into public.cities (name, sort) values
  ('Trujillo', 1),
  ('Chimbote', 2),
  ('Chiclayo', 3),
  ('Piura', 4),
  ('Tarapoto', 5)
on conflict (name) do nothing;

insert into public.stores (code, name, city_id) values
  ('TRU01', 'Tienda Larco', (select id from public.cities where name='Trujillo')),
  ('TRU02', 'Tienda Ingeniería', (select id from public.cities where name='Trujillo')),
  ('TRU03', 'Tienda Húsares', (select id from public.cities where name='Trujillo')),
  ('TRU04', 'Tienda Liverpool', (select id from public.cities where name='Trujillo')),
  ('TRU05', 'Tienda 28 de Julio', (select id from public.cities where name='Trujillo')),
  ('TRU06', 'Tienda Ricardo Palma', (select id from public.cities where name='Trujillo')),
  ('TRU07', 'Tienda Seoane', (select id from public.cities where name='Trujillo')),
  ('TRU08', 'Tienda Blas Pascal', (select id from public.cities where name='Trujillo')),
  ('TRU09', 'Tienda Huanchaco', (select id from public.cities where name='Trujillo')),
  ('TRU10', 'Tienda Primavera', (select id from public.cities where name='Trujillo')),
  ('CHB01', 'Tienda Buenos Aires', (select id from public.cities where name='Chimbote')),
  ('CHB02', 'Tienda Country', (select id from public.cities where name='Chimbote')),
  ('CIX01', 'Tienda Sáenz Peña', (select id from public.cities where name='Chiclayo')),
  ('CIX02', 'Tienda Santa Victoria', (select id from public.cities where name='Chiclayo')),
  ('PIU01', 'Tienda Santa Isabel', (select id from public.cities where name='Piura')),
  ('PIU02', 'Tienda Guardia Civil', (select id from public.cities where name='Piura')),
  ('PIU03', 'Tienda Loreto', (select id from public.cities where name='Piura')),
  ('PIU04', 'Tienda Grau', (select id from public.cities where name='Piura')),
  ('TPP01', 'Tienda Tahuantinsuyo Cuadra 3', (select id from public.cities where name='Tarapoto')),
  ('TPP02', 'Tienda Huallaga', (select id from public.cities where name='Tarapoto'))
on conflict (code) do nothing;

insert into public.categories (name, grupo, sort) values
  ('Afiches A4', 'ARTES', 1),
  ('Afiches 50 x 70 cm', 'ARTES', 2),
  ('Comunicados', 'ARTES', 3),
  ('Preciadores', 'MATERIALES', 4),
  ('Acrílicos porta afiche A4', 'MATERIALES', 5),
  ('Módulos', 'MATERIALES', 6)
on conflict (grupo, name) do nothing;

with v (cat, name, slug, w, h, sort, size, stock) as (values
  ('Afiches A4', 'Milanesa de Pollo', 'a4-milanesa-de-pollo', 178, 252, 1, 'A4 (21 x 29.7 cm)', 8),
  ('Afiches A4', 'Suprema de Pollo', 'a4-suprema-de-pollo', 178, 252, 2, 'A4 (21 x 29.7 cm)', 5),
  ('Afiches A4', 'Nuggets de Pollo', 'a4-nuggets-de-pollo', 176, 250, 3, 'A4 (21 x 29.7 cm)', 0),
  ('Afiches A4', 'Hamburguesa Premium de Pollo', 'a4-hamburguesa-premium-de-pollo', 178, 252, 4, 'A4 (21 x 29.7 cm)', 6),
  ('Afiches A4', 'Alitas Korean BBQ Picante', 'a4-alitas-korean-bbq-picante', 178, 252, 5, 'A4 (21 x 29.7 cm)', 5),
  ('Afiches A4', 'Chicharrón de Pollo', 'a4-chicharron-de-pollo', 176, 250, 6, 'A4 (21 x 29.7 cm)', 0),
  ('Afiches A4', 'Pollo Sabor a la Brasa', 'a4-pollo-sabor-a-la-brasa', 176, 250, 7, 'A4 (21 x 29.7 cm)', 0),
  ('Afiches A4', 'Lomito de Pollo', 'a4-lomito-de-pollo', 176, 250, 8, 'A4 (21 x 29.7 cm)', 0),
  ('Afiches A4', 'Pollada Criolla', 'a4-pollada-criolla', 176, 250, 9, 'A4 (21 x 29.7 cm)', 3),
  ('Afiches A4', 'Alitas Bouchet', 'a4-alitas-bouchet', 176, 250, 10, 'A4 (21 x 29.7 cm)', 1),
  ('Afiches A4', 'Celda Huevos Pardos x 30', 'a4-celda-huevos-pardos-x-30', 178, 250, 11, 'A4 (21 x 29.7 cm)', 0),
  ('Afiches A4', 'Pollo Superior (Jugoso)', 'a4-pollo-superior-jugoso', 176, 250, 12, 'A4 (21 x 29.7 cm)', 0),
  ('Afiches A4', 'Filetillo de Pollo', 'a4-filetillo-de-pollo', 176, 250, 13, 'A4 (21 x 29.7 cm)', 0),
  ('Afiches A4', 'Celda Huevos Pardos x 15', 'a4-celda-huevos-pardos-x-15', 176, 250, 14, 'A4 (21 x 29.7 cm)', 0),
  ('Afiches 50 x 70 cm', 'Pollo Entero c/ menudencia', '5070-pollo-entero-c-menudencia', 190, 264, 15, '50 x 70 cm', 0),
  ('Afiches 50 x 70 cm', 'Pollo Sabor a la Brasa', '5070-pollo-sabor-a-la-brasa', 190, 264, 16, '50 x 70 cm', 0),
  ('Afiches 50 x 70 cm', 'Listos p/ Preparar (Alitas/Suprema)', '5070-listos-p-preparar-alitas-suprema', 190, 264, 17, '50 x 70 cm', 0),
  ('Afiches 50 x 70 cm', 'Chicharrón de Pollo', '5070-chicharron-de-pollo', 170, 238, 18, '50 x 70 cm', 0),
  ('Afiches 50 x 70 cm', 'Pollo Superior c/ menudencia', '5070-pollo-superior-c-menudencia', 170, 238, 19, '50 x 70 cm', 0),
  ('Comunicados', 'Comunicado bolsas (Ley 30884)', 'com-comunicado-bolsas-ley-30884', 176, 250, 20, 'A4 (21 x 29.7 cm)', 0),
  ('Comunicados', 'Señalética atención preferencial', 'com-senaletica-atencion-preferencial', 842, 1192, 21, 'A4 (21 x 29.7 cm)', 2),
  ('Comunicados', 'Horario de atención', 'com-horario-de-atencion', 842, 1186, 22, 'A4 (21 x 29.7 cm)', 6),
  ('Comunicados', 'Protocolo en caso de robos', 'com-protocolo-en-caso-de-robos', 1584, 2236, 23, 'A4 (21 x 29.7 cm)', 0)
), ins as (
  insert into public.items (category_id, name, photo_path, thumb_path, photo_w, photo_h, sort)
  select c.id, v.name, 'seed/'||v.slug||'.webp', 'seed/'||v.slug||'_t.webp', v.w, v.h, v.sort
  from v join public.categories c on c.name = v.cat and c.grupo = 'ARTES'
  returning id, sort
)
insert into public.item_admin (item_id, supplier, material, size, stock)
select ins.id, 'POR DEFINIR', 'POR DEFINIR', v.size, v.stock from ins join v on v.sort = ins.sort;
