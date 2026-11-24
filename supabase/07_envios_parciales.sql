-- =====================================================================
--  07_envios_parciales.sql · Saldos pendientes de envíos incompletos
--  shipments.requested = lo que pidió la tienda; si qty < requested queda saldo.
--  Un nuevo control de la tienda cierra los envíos anteriores: su respuesta manda.
-- =====================================================================
alter table public.shipments add column if not exists requested int check (requested >= 1);

create or replace function public.mark_shipped(p_rows jsonb, p_note text default null)
returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  with r as (
    select (x->>'store_id')::bigint store_id, (x->>'item_id')::bigint item_id,
           greatest(coalesce((x->>'qty')::int, 1), 1) qty,
           nullif(x->>'requested', '')::int requested
    from jsonb_array_elements(p_rows) x
  ), ins as (
    insert into public.shipments (store_id, item_id, qty, requested, sent_by, note)
    select store_id, item_id, qty, case when requested > qty then requested end, auth.uid(), nullif(trim(p_note), '') from r
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

-- Cierra el recordatorio de saldo (enviado o descartado)
create or replace function public.close_balance(p_id bigint)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  update public.shipments set requested = null where id = p_id;
end $$;
revoke all on function public.close_balance(bigint) from public, anon;
grant execute on function public.close_balance(bigint) to authenticated;

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

  -- El nuevo control de la tienda cierra los envíos anteriores: lo que aún falte, lo vuelve a pedir
  update public.shipments sh set status = 'recibido', received_at = v_at
   where sh.store_id = v_store and sh.status = 'en_camino' and sh.sent_at < v_at;

  return jsonb_build_object('id', v_sub, 'submitted_at', v_at, 'period', public.current_period());
end $$;
