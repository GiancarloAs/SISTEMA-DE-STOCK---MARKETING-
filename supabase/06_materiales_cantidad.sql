-- =====================================================================
--  06_materiales_cantidad.sql · Pedido por cantidad en materiales
--  items.max_qty = tope de unidades que la tienda puede pedir cuando marca
--  "No lo tenemos" o "Deteriorado" (1 = por unidad, sin elegir cantidad).
--  submission_items.qty = cantidad pedida por la tienda.
-- =====================================================================

alter table public.items add column if not exists max_qty int not null default 1 check (max_qty between 1 and 50);
alter table public.submission_items add column if not exists qty int check (qty >= 0);
alter table public.submission_items add column if not exists qty_bad int check (qty_bad >= 0);

-- p_answers = {"<item_id>": "tiene" | "no_tiene" | "deteriorado"
--                          | {"status": "no_tiene"|"deteriorado"|"tiene", "qty": n}}
create or replace function public.submit_checklist(p_answers jsonb, p_notes text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_store   bigint := public.my_store_id();
  v_sub     bigint;
  v_at      timestamptz;
  v_missing int;
begin
  if v_store is null then raise exception 'Usuario sin tienda activa asignada'; end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'Respuestas inválidas'; end if;

  select count(*) into v_missing
  from public.items i join public.categories c on c.id = i.category_id
  cross join lateral (select p_answers -> i.id::text as a) x
  cross join lateral (select case when jsonb_typeof(x.a) = 'object' then x.a ->> 'status' else x.a #>> '{}' end as st,
                             case when jsonb_typeof(x.a) = 'object' then x.a ->> 'qty' end as q) y
  where i.active and c.active and not (
    coalesce(y.st, '') in ('tiene','no_tiene','deteriorado')
    and (y.q is null or (y.q ~ '^\d{1,3}$' and y.q::int between 1 and i.max_qty)));
  if v_missing > 0 then raise exception 'Faltan % artículo(s) por responder', v_missing; end if;

  insert into public.submissions (store_id, submitted_by, period, notes)
  values (v_store, auth.uid(), public.current_period(), nullif(trim(p_notes), ''))
  returning id, submitted_at into v_sub, v_at;

  insert into public.submission_items (submission_id, item_id, status, qty)
  select v_sub, i.id, y.st,
         case when y.st in ('no_tiene','deteriorado') then coalesce(y.q::int, 1) end
  from public.items i join public.categories c on c.id = i.category_id
  cross join lateral (select p_answers -> i.id::text as a) x
  cross join lateral (select case when jsonb_typeof(x.a) = 'object' then x.a ->> 'status' else x.a #>> '{}' end as st,
                             case when jsonb_typeof(x.a) = 'object' then x.a ->> 'qty' end as q) y
  where i.active and c.active;

  update public.shipments sh set status = 'recibido', received_at = v_at
   where sh.store_id = v_store and sh.status = 'en_camino'
     and exists (select 1 from public.submission_items si
                 where si.submission_id = v_sub and si.item_id = sh.item_id and si.status = 'tiene');

  return jsonb_build_object('id', v_sub, 'submitted_at', v_at, 'period', public.current_period());
end $$;

-- ---------- Materiales (fotos en fotos/ del repo) ----------
update public.categories set name = 'Acrílicos porta afiche' where grupo = 'MATERIALES' and name = 'Acrílicos porta afiche A4';
update public.categories set name = 'Jalavistas', sort = 6 where grupo = 'MATERIALES' and name = 'Módulos';
insert into public.categories (name, grupo, sort) values ('Jalavistas', 'MATERIALES', 6) on conflict (grupo, name) do nothing;

with v (cat, name, slug, w, h, sort, max_qty, expected, size) as (values
  ('Acrílicos porta afiche', 'Acrílico porta afiche 50 x 70 cm', 'mat-acrilico-50x70', 1200, 1600, 101, 3, 3, '50 x 70 cm'),
  ('Acrílicos porta afiche', 'Acrílico porta afiche A4',          'mat-acrilico-a4',    1200, 1600, 102, 5, 4, 'A4 (21 x 29.7 cm)'),
  ('Preciadores', 'Preciador',                                     'mat-preciador',      1200, 1600, 103, 5, 5, 'POR DEFINIR'),
  ('Preciadores', 'Juego de nombres para preciadores',             'mat-juego-nombres-preciadores', 1200, 1600, 104, 2, 1, 'POR DEFINIR'),
  ('Jalavistas', 'Jalavista de afiche 50 x 70',                    'mat-jalavista-afiche-50x70', 1200, 1600, 105, 1, 1, 'POR DEFINIR'),
  ('Jalavistas', 'Juego de números para jalavista de afiche (grande)', 'mat-juego-numeros-jalavista-afiche', 1200, 1600, 106, 1, 1, 'POR DEFINIR'),
  ('Jalavistas', 'Jalavista de huevos',                            'mat-jalavista-huevos', 1200, 1600, 107, 1, 1, 'POR DEFINIR'),
  ('Jalavistas', 'Juego de números para jalavista de huevos (pequeño)', 'mat-juego-numeros-jalavista-huevos', 1200, 1600, 108, 1, 1, 'POR DEFINIR')
), ins as (
  insert into public.items (category_id, name, photo_path, thumb_path, photo_w, photo_h, sort, max_qty)
  select c.id, v.name, 'seed/'||v.slug||'.webp', 'seed/'||v.slug||'_t.webp', v.w, v.h, v.sort, v.max_qty
  from v join public.categories c on c.name = v.cat and c.grupo = 'MATERIALES'
  where not exists (select 1 from public.items i where i.photo_path = 'seed/'||v.slug||'.webp')
  returning id, sort
)
insert into public.item_admin (item_id, supplier, material, size, stock, qty_per_store)
select ins.id, 'POR DEFINIR', 'POR DEFINIR', v.size, 0, 1 from ins join v on v.sort = ins.sort;
