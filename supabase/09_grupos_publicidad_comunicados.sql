-- =====================================================================
--  09_grupos_publicidad_comunicados.sql
--  El grupo ARTES se divide en PUBLICIDAD (afiches) y COMUNICADOS.
-- =====================================================================
alter table public.categories drop constraint if exists categories_grupo_check;
update public.categories set grupo = case when name ilike 'comunicado%' then 'COMUNICADOS' else 'PUBLICIDAD' end
 where grupo = 'ARTES';
alter table public.categories add constraint categories_grupo_check
  check (grupo in ('PUBLICIDAD','COMUNICADOS','MATERIALES'));
