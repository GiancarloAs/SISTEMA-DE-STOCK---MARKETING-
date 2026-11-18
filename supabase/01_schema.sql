-- =====================================================================
--  NORAVES · Control de Artes y Materiales en Tiendas
--  01_schema.sql  → Ejecutar UNA vez en Supabase › SQL Editor
-- =====================================================================

-- ---------- TABLAS ---------------------------------------------------

create table if not exists public.cities (
  id    bigint generated always as identity primary key,
  name  text not null unique,
  sort  int  not null default 0
);

create table if not exists public.stores (
  id         bigint generated always as identity primary key,
  code       text not null unique,                 -- código de tienda (ej. TRU01) = usuario de login
  name       text not null,
  city_id    bigint not null references public.cities(id),
  active     boolean not null default true,
  user_id    uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  role      text not null check (role in ('admin','store')),
  store_id  bigint references public.stores(id) on delete cascade,
  full_name text,
  constraint store_role_needs_store check (role = 'admin' or store_id is not null)
);

-- Grupo = ARTES (afiches, comunicados…) o MATERIALES (preciadores, acrílicos, módulos…)
create table if not exists public.categories (
  id      bigint generated always as identity primary key,
  name    text not null,
  grupo   text not null check (grupo in ('ARTES','MATERIALES')),
  sort    int  not null default 0,
  active  boolean not null default true,
  unique (grupo, name)
);

-- Lo que ve la tienda
create table if not exists public.items (
  id          bigint generated always as identity primary key,
  category_id bigint not null references public.categories(id),
  name        text not null,
  description text,
  photo_path  text,          -- WebP grande (máx 1600 px) en el bucket "articulos"
  thumb_path  text,          -- WebP miniatura (máx 480 px) para celulares
  photo_w     int,           -- proporción real de la pieza → tarjeta adaptable
  photo_h     int,
  sort        int  not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Solo admin: proveedor, material, medida (obligatorios), precio sugerido (opcional), stock en almacén
create table if not exists public.item_admin (
  item_id         bigint primary key references public.items(id) on delete cascade,
  supplier        text not null check (length(trim(supplier)) > 0),
  material        text not null check (length(trim(material)) > 0),
  size            text not null check (length(trim(size)) > 0),
  suggested_price numeric(10,2),
  stock           int  not null default 0 check (stock >= 0),
  qty_per_store   int  not null default 1 check (qty_per_store >= 1)
);

-- Cada vez que una tienda envía su control queda un registro (historial completo)
create table if not exists public.submissions (
  id           bigint generated always as identity primary key,
  store_id     bigint not null references public.stores(id) on delete cascade,
  submitted_by uuid,
  submitted_at timestamptz not null default now(),
  period       date not null,          -- primer día del mes (hora Lima)
  notes        text,
  source       text not null default 'tienda'   -- 'tienda' | 'importado'
);
create index if not exists submissions_period_idx on public.submissions(period, store_id, submitted_at desc);
create index if not exists submissions_store_idx on public.submissions(store_id);

create table if not exists public.submission_items (
  submission_id bigint not null references public.submissions(id) on delete cascade,
  item_id       bigint not null references public.items(id) on delete cascade,
  status        text   not null check (status in ('tiene','no_tiene','deteriorado')),
  primary key (submission_id, item_id)
);

-- Envíos de marketing a tiendas (el "1" del Excel)
create table if not exists public.shipments (
  id          bigint generated always as identity primary key,
  store_id    bigint not null references public.stores(id) on delete cascade,
  item_id     bigint not null references public.items(id) on delete cascade,
  qty         int    not null default 1 check (qty >= 1),
  status      text   not null default 'en_camino' check (status in ('en_camino','recibido','anulado')),
  sent_at     timestamptz not null default now(),
  received_at timestamptz,
  sent_by     uuid,
  note        text
);
create index if not exists shipments_open_idx on public.shipments(store_id, item_id) where status = 'en_camino';
create index if not exists shipments_item_idx on public.shipments(item_id);
create index if not exists stores_city_idx on public.stores(city_id);
create index if not exists items_category_idx on public.items(category_id);
create index if not exists profiles_store_idx on public.profiles(store_id);
create index if not exists submission_items_item_idx on public.submission_items(item_id);

-- ---------- FUNCIONES AUXILIARES ------------------------------------

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'admin');
$$;

create or replace function public.my_store_id() returns bigint
language sql stable security definer set search_path = public as $$
  select p.store_id from public.profiles p
  join public.stores s on s.id = p.store_id and s.active
  where p.user_id = auth.uid() and p.role = 'store';
$$;

create or replace function public.current_period() returns date
language sql stable set search_path = public as $$
  select date_trunc('month', now() at time zone 'America/Lima')::date;
$$;

-- ---------- RPC: la tienda envía su control (todo o nada) -----------
-- p_answers = {"<item_id>": "tiene" | "no_tiene" | "deteriorado", ...}
create or replace function public.submit_checklist(p_answers jsonb, p_notes text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_store   bigint := public.my_store_id();
  v_sub     bigint;
  v_at      timestamptz;
  v_missing int;
begin
  if v_store is null then
    raise exception 'Usuario sin tienda activa asignada';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Respuestas inválidas';
  end if;

  select count(*) into v_missing
  from public.items i join public.categories c on c.id = i.category_id
  where i.active and c.active
    and coalesce(p_answers ->> i.id::text, '') not in ('tiene','no_tiene','deteriorado');
  if v_missing > 0 then
    raise exception 'Faltan % artículo(s) por responder', v_missing;
  end if;

  insert into public.submissions (store_id, submitted_by, period, notes)
  values (v_store, auth.uid(), public.current_period(), nullif(trim(p_notes), ''))
  returning id, submitted_at into v_sub, v_at;

  insert into public.submission_items (submission_id, item_id, status)
  select v_sub, i.id, p_answers ->> i.id::text
  from public.items i join public.categories c on c.id = i.category_id
  where i.active and c.active;

  -- Lo que estaba "en camino" y ahora la tienda dice que lo tiene → recibido
  update public.shipments sh
     set status = 'recibido', received_at = v_at
   where sh.store_id = v_store and sh.status = 'en_camino'
     and (p_answers ->> sh.item_id::text) = 'tiene';

  return jsonb_build_object('id', v_sub, 'submitted_at', v_at, 'period', public.current_period());
end $$;

-- ---------- RPC admin: marcar envíos (descuenta stock de almacén) ----
-- p_rows = [{"store_id":1,"item_id":5,"qty":1}, ...]
create or replace function public.mark_shipped(p_rows jsonb, p_note text default null)
returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;

  with r as (
    select (x->>'store_id')::bigint store_id, (x->>'item_id')::bigint item_id,
           greatest(coalesce((x->>'qty')::int, 1), 1) qty
    from jsonb_array_elements(p_rows) x
  ), ins as (
    insert into public.shipments (store_id, item_id, qty, sent_by, note)
    select store_id, item_id, qty, auth.uid(), nullif(trim(p_note), '') from r
    returning item_id, qty
  ), agg as (
    select item_id, sum(qty) q from ins group by item_id
  ), upd as (
    update public.item_admin ia set stock = greatest(ia.stock - agg.q, 0)
    from agg where ia.item_id = agg.item_id returning 1
  )
  select count(*) into v_n from ins;
  return v_n;
end $$;

create or replace function public.cancel_shipment(p_id bigint)
returns void
language plpgsql security definer set search_path = public as $$
declare v_item bigint; v_qty int;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  update public.shipments set status = 'anulado'
   where id = p_id and status = 'en_camino'
  returning item_id, qty into v_item, v_qty;
  if v_item is not null then
    update public.item_admin set stock = stock + v_qty where item_id = v_item;
  end if;
end $$;

revoke all on function public.submit_checklist(jsonb, text) from public, anon;
revoke all on function public.mark_shipped(jsonb, text)     from public, anon;
revoke all on function public.cancel_shipment(bigint)       from public, anon;
revoke all on function public.is_admin()                    from public, anon;
revoke all on function public.my_store_id()                 from public, anon;
grant execute on function public.is_admin()                    to authenticated;
grant execute on function public.my_store_id()                 to authenticated;
grant execute on function public.submit_checklist(jsonb, text) to authenticated;
grant execute on function public.mark_shipped(jsonb, text)     to authenticated;
grant execute on function public.cancel_shipment(bigint)       to authenticated;

-- ---------- SEGURIDAD (RLS) -----------------------------------------

alter table public.cities           enable row level security;
alter table public.stores           enable row level security;
alter table public.profiles         enable row level security;
alter table public.categories       enable row level security;
alter table public.items            enable row level security;
alter table public.item_admin       enable row level security;
alter table public.submissions      enable row level security;
alter table public.submission_items enable row level security;
alter table public.shipments        enable row level security;

-- Catálogo visible para cualquier usuario logueado; solo admin edita
create policy cities_read      on public.cities     for select to authenticated using (true);
create policy cities_admin     on public.cities     for all    to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy categories_read  on public.categories for select to authenticated using (true);
create policy categories_admin on public.categories for all    to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy items_read       on public.items      for select to authenticated using (true);
create policy items_admin      on public.items      for all    to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Proveedor / material / medida / precio / stock: SOLO admin
create policy item_admin_only  on public.item_admin for all    to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Tiendas y perfiles: cada tienda ve solo lo suyo
create policy stores_read      on public.stores     for select to authenticated using ((select public.is_admin()) or id = (select public.my_store_id()));
create policy stores_admin     on public.stores     for all    to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy profiles_read    on public.profiles   for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy profiles_admin   on public.profiles   for all    to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Registros: la tienda solo inserta vía submit_checklist(); lee solo los suyos
create policy submissions_read  on public.submissions for select to authenticated using ((select public.is_admin()) or store_id = (select public.my_store_id()));
create policy submissions_admin on public.submissions for delete to authenticated using ((select public.is_admin()));
create policy subitems_read     on public.submission_items for select to authenticated using (
  (select public.is_admin()) or exists (select 1 from public.submissions s where s.id = submission_id and s.store_id = (select public.my_store_id())));
create policy subitems_admin    on public.submission_items for delete to authenticated using ((select public.is_admin()));

-- Envíos: la tienda ve lo que le mandaron ("En camino")
create policy shipments_read   on public.shipments for select to authenticated using ((select public.is_admin()) or store_id = (select public.my_store_id()));
create policy shipments_admin  on public.shipments for all    to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- ---------- STORAGE: fotos de artículos ------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('articulos', 'articulos', true, 5242880, array['image/webp','image/jpeg','image/png'])
on conflict (id) do nothing;

create policy articulos_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'articulos' and (select public.is_admin()));
create policy articulos_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'articulos' and (select public.is_admin()));
create policy articulos_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'articulos' and (select public.is_admin()));
