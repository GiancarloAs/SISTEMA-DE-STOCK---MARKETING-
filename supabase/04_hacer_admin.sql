-- 04_hacer_admin.sql
-- Convierte un usuario ya creado en Supabase › Authentication en ADMINISTRADOR.
-- 1) Authentication › Users › Add user › Create new user (tu correo + tu contraseña, marca "Auto Confirm User").
-- 2) Cambia el correo de abajo y ejecuta esto en SQL Editor.

insert into public.profiles (user_id, role, full_name)
select id, 'admin', email from auth.users where email = 'carloz.asian@gmail.com'
on conflict (user_id) do update set role = 'admin', store_id = null;
