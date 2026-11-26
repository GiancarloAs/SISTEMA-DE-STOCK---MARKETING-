-- =====================================================================
--  10_recepcion_envios.sql · La tienda confirma primero lo que se le envió
--  shipments.receipt: llego | no_llego | llego_danado (lo responde la tienda)
--  · llego        → envío recibido; ese artículo ya no se le pide en el control del mes (cuenta como "tiene")
--  · llego_danado → envío recibido; sigue en el control del mes (marcará deteriorado)
--  · no_llego     → sigue en camino; podrá confirmarlo cuando llegue
-- =====================================================================
alter table public.shipments add column if not exists receipt text check (receipt in ('llego','no_llego','llego_danado'));
alter table public.shipments add column if not exists receipt_at timestamptz;

create or replace function public.confirm_receipt(p_answers jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_store bigint := public.my_store_id();
  v_n     int := 0;
  k text; v text;
begin
  if v_store is null then raise exception 'Usuario sin tienda activa asignada'; end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'Respuestas inválidas'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(p_answers) loop
    if v not in ('llego','no_llego','llego_danado') or k !~ '^\d+$' then raise exception 'Respuesta inválida'; end if;
    update public.shipments
       set receipt = v, receipt_at = now(),
           status = case when v = 'no_llego' then 'en_camino' else 'recibido' end,
           received_at = case when v = 'no_llego' then null else now() end
     where id = k::bigint and store_id = v_store and status = 'en_camino';
    if found then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
revoke all on function public.confirm_receipt(jsonb) from public, anon;
grant execute on function public.confirm_receipt(jsonb) to authenticated;

create or replace function public.submit_checklist(p_answers jsonb, p_notes text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_store   bigint := public.my_store_id();
  v_sub     bigint;
  v_at      timestamptz;
  v_missing int;
  v_from    timestamptz := (public.current_period()::timestamp at time zone 'America/Lima');
begin
  if v_store is null then raise exception 'Usuario sin tienda activa asignada'; end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'Respuestas inválidas'; end if;

  select count(*) into v_missing
  from public.items i join public.categories c on c.id = i.category_id
  cross join lateral (select p_answers -> i.id::text as a) x
  cross join lateral (select case when jsonb_typeof(x.a) = 'object' then x.a ->> 'status' else x.a #>> '{}' end as st,
                             case when jsonb_typeof(x.a) = 'object' then x.a ->> 'qty' end as q) y
  where i.active and c.active
    and (i.all_stores or exists (select 1 from public.item_stores x2 where x2.item_id = i.id and x2.store_id = v_store))
    and not exists (select 1 from public.shipments r where r.store_id = v_store and r.item_id = i.id and r.receipt = 'llego' and r.receipt_at >= v_from) and not (
    coalesce(y.st, '') in ('tiene','no_tiene','deteriorado')
    and (y.q is null or (y.q ~ '^\d{1,3}$' and y.q::int between 1 and i.max_qty)));
  if v_missing > 0 then raise exception 'Faltan % artículo(s) por responder', v_missing; end if;

  insert into public.submissions (store_id, submitted_by, period, notes)
  values (v_store, auth.uid(), public.current_period(), nullif(trim(p_notes), ''))
  returning id, submitted_at into v_sub, v_at;

  insert into public.submission_items (submission_id, item_id, status, qty)
  select v_sub, i.id, coalesce(y.st, 'tiene'),
         case when y.st in ('no_tiene','deteriorado') then coalesce(y.q::int, 1) end
  from public.items i join public.categories c on c.id = i.category_id
  cross join lateral (select p_answers -> i.id::text as a) x
  cross join lateral (select case when jsonb_typeof(x.a) = 'object' then x.a ->> 'status' else x.a #>> '{}' end as st,
                             case when jsonb_typeof(x.a) = 'object' then x.a ->> 'qty' end as q) y
  where i.active and c.active
    and (i.all_stores or exists (select 1 from public.item_stores x2 where x2.item_id = i.id and x2.store_id = v_store))
    and (y.st in ('tiene','no_tiene','deteriorado') or exists (select 1 from public.shipments r where r.store_id = v_store and r.item_id = i.id and r.receipt = 'llego' and r.receipt_at >= v_from));

  -- El nuevo control de la tienda cierra los envíos anteriores: lo que aún falte, lo vuelve a pedir
  update public.shipments sh set status = 'recibido', received_at = v_at
   where sh.store_id = v_store and sh.status = 'en_camino' and sh.sent_at < v_at
     and coalesce(sh.receipt, '') <> 'no_llego';   -- lo que la tienda dijo que aún no llega sigue en camino

  return jsonb_build_object('id', v_sub, 'submitted_at', v_at, 'period', public.current_period());
end $$;


