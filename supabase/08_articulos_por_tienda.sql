-- =====================================================================
--  08_articulos_por_tienda.sql · Qué tiendas validan cada artículo
--  items.all_stores = true  → lo validan todas las tiendas (por defecto)
--  items.all_stores = false → solo las tiendas listadas en item_stores
-- =====================================================================
alter table public.items add column if not exists all_stores boolean not null default true;

create table if not exists public.item_stores (
  item_id  bigint not null references public.items(id) on delete cascade,
  store_id bigint not null references public.stores(id) on delete cascade,
  primary key (item_id, store_id)
);
create index if not exists item_stores_store_idx on public.item_stores(store_id);
alter table public.item_stores enable row level security;
create policy item_stores_admin on public.item_stores for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy item_stores_store_read on public.item_stores for select to authenticated
  using (store_id = (select public.my_store_id()));

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
  where i.active and c.active
    and (i.all_stores or exists (select 1 from public.item_stores x2 where x2.item_id = i.id and x2.store_id = v_store)) and not (
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
  where i.active and c.active
    and (i.all_stores or exists (select 1 from public.item_stores x2 where x2.item_id = i.id and x2.store_id = v_store));

  -- El nuevo control de la tienda cierra los envíos anteriores: lo que aún falte, lo vuelve a pedir
  update public.shipments sh set status = 'recibido', received_at = v_at
   where sh.store_id = v_store and sh.status = 'en_camino' and sh.sent_at < v_at;

  return jsonb_build_object('id', v_sub, 'submitted_at', v_at, 'period', public.current_period());
end $$;

