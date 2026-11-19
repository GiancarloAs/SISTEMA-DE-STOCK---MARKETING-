-- =====================================================================
--  05_campanas.sql · Validación por campaña
--  Una campaña agrupa piezas del catálogo + tiendas participantes + fechas.
--  La tienda valida cada pieza: llegó / aún no llegó / llegó dañado (+ foto opcional).
-- =====================================================================

create table if not exists public.campaigns (
  id          bigint generated always as identity primary key,
  name        text not null check (length(trim(name)) > 0),
  description text,
  start_date  date not null,
  end_date    date not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint campaign_dates check (end_date >= start_date)
);

create table if not exists public.campaign_items (
  campaign_id bigint not null references public.campaigns(id) on delete cascade,
  item_id     bigint not null references public.items(id) on delete cascade,
  primary key (campaign_id, item_id)
);
create index if not exists campaign_items_item_idx on public.campaign_items(item_id);

create table if not exists public.campaign_stores (
  campaign_id bigint not null references public.campaigns(id) on delete cascade,
  store_id    bigint not null references public.stores(id) on delete cascade,
  primary key (campaign_id, store_id)
);
create index if not exists campaign_stores_store_idx on public.campaign_stores(store_id);

create table if not exists public.campaign_submissions (
  id           bigint generated always as identity primary key,
  campaign_id  bigint not null references public.campaigns(id) on delete cascade,
  store_id     bigint not null references public.stores(id) on delete cascade,
  submitted_by uuid,
  submitted_at timestamptz not null default now(),
  notes        text
);
create index if not exists campaign_submissions_idx on public.campaign_submissions(campaign_id, store_id, submitted_at desc);
create index if not exists campaign_submissions_store_idx on public.campaign_submissions(store_id);

create table if not exists public.campaign_submission_items (
  submission_id bigint not null references public.campaign_submissions(id) on delete cascade,
  item_id       bigint not null references public.items(id) on delete cascade,
  status        text   not null check (status in ('llego','no_llego','llego_danado')),
  photo_path    text,
  primary key (submission_id, item_id)
);
create index if not exists campaign_submission_items_item_idx on public.campaign_submission_items(item_id);

-- ¿La campaña está vigente hoy (hora Lima) y la tienda participa?
create or replace function public.campaign_open_for_me(p_campaign bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.campaigns c
    join public.campaign_stores cs on cs.campaign_id = c.id and cs.store_id = public.my_store_id()
    where c.id = p_campaign and c.active
      and (now() at time zone 'America/Lima')::date between c.start_date and c.end_date);
$$;

-- La tienda envía su validación de campaña (todo o nada)
-- p_answers = {"<item_id>": {"status": "llego|no_llego|llego_danado", "photo": "ruta opcional"}, ...}
create or replace function public.submit_campaign(p_campaign bigint, p_answers jsonb, p_notes text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_store   bigint := public.my_store_id();
  v_sub     bigint;
  v_at      timestamptz;
  v_missing int;
begin
  if v_store is null then raise exception 'Usuario sin tienda activa asignada'; end if;
  if not public.campaign_open_for_me(p_campaign) then
    raise exception 'La campaña no está vigente o tu tienda no participa';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'Respuestas inválidas'; end if;

  select count(*) into v_missing from public.campaign_items ci
  where ci.campaign_id = p_campaign
    and coalesce(p_answers -> ci.item_id::text ->> 'status', '') not in ('llego','no_llego','llego_danado');
  if v_missing > 0 then raise exception 'Faltan % pieza(s) por responder', v_missing; end if;

  insert into public.campaign_submissions (campaign_id, store_id, submitted_by, notes)
  values (p_campaign, v_store, auth.uid(), nullif(trim(p_notes), ''))
  returning id, submitted_at into v_sub, v_at;

  insert into public.campaign_submission_items (submission_id, item_id, status, photo_path)
  select v_sub, ci.item_id,
         p_answers -> ci.item_id::text ->> 'status',
         -- solo se aceptan fotos de la carpeta de esta tienda
         case when (p_answers -> ci.item_id::text ->> 'photo') like v_store::text || '/%'
              then p_answers -> ci.item_id::text ->> 'photo' end
  from public.campaign_items ci where ci.campaign_id = p_campaign;

  -- Lo que estaba "en camino" y ahora llegó bien → recibido
  update public.shipments sh set status = 'recibido', received_at = v_at
   where sh.store_id = v_store and sh.status = 'en_camino'
     and (p_answers -> sh.item_id::text ->> 'status') = 'llego';

  return jsonb_build_object('id', v_sub, 'submitted_at', v_at);
end $$;

revoke all on function public.campaign_open_for_me(bigint)              from public, anon;
revoke all on function public.submit_campaign(bigint, jsonb, text)      from public, anon;
grant execute on function public.campaign_open_for_me(bigint)           to authenticated;
grant execute on function public.submit_campaign(bigint, jsonb, text)   to authenticated;

-- ---------- RLS ----------
alter table public.campaigns                 enable row level security;
alter table public.campaign_items            enable row level security;
alter table public.campaign_stores           enable row level security;
alter table public.campaign_submissions      enable row level security;
alter table public.campaign_submission_items enable row level security;

create policy campaigns_admin on public.campaigns for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy campaigns_store_read on public.campaigns for select to authenticated
  using (exists (select 1 from public.campaign_stores cs where cs.campaign_id = campaigns.id and cs.store_id = (select public.my_store_id())));

create policy campaign_items_admin on public.campaign_items for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy campaign_items_store_read on public.campaign_items for select to authenticated
  using (exists (select 1 from public.campaign_stores cs where cs.campaign_id = campaign_items.campaign_id and cs.store_id = (select public.my_store_id())));

create policy campaign_stores_admin on public.campaign_stores for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy campaign_stores_store_read on public.campaign_stores for select to authenticated
  using (store_id = (select public.my_store_id()));

create policy campaign_subs_read on public.campaign_submissions for select to authenticated
  using ((select public.is_admin()) or store_id = (select public.my_store_id()));
create policy campaign_subs_admin_delete on public.campaign_submissions for delete to authenticated
  using ((select public.is_admin()));

create policy campaign_subitems_read on public.campaign_submission_items for select to authenticated
  using ((select public.is_admin()) or exists (select 1 from public.campaign_submissions s
         where s.id = submission_id and s.store_id = (select public.my_store_id())));

-- ---------- STORAGE: fotos de evidencia (privado) ----------
-- Ruta: <store_id>/<campaign_id>/<archivo>.webp → cada tienda solo escribe y lee su carpeta
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidencias', 'evidencias', false, 5242880, array['image/webp','image/jpeg','image/png'])
on conflict (id) do nothing;

create policy evidencias_store_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'evidencias' and (storage.foldername(name))[1] = (select public.my_store_id())::text);
create policy evidencias_read on storage.objects for select to authenticated
  using (bucket_id = 'evidencias' and ((select public.is_admin())
         or (storage.foldername(name))[1] = (select public.my_store_id())::text));
create policy evidencias_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'evidencias' and (select public.is_admin()));
