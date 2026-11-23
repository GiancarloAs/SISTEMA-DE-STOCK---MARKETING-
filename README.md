# Noraves · Sistema de Stock – Marketing

Control de **artes y materiales** en las tiendas Noraves. Reemplaza el Excel `Inventario_Control_Afiches_Noraves_v2.xlsx`.

- **Panel de tienda** (celular o PC): cada tienda entra con su código (ej. `TRU01`) y marca cada pieza como **Lo tenemos / No lo tenemos / Deteriorado**. Al enviar queda registrada la tienda, la fecha y la hora.
- **Panel admin** (Marketing): entra con su correo. Gestiona categorías, artículos y tiendas. Ve los informes del mes, marca envíos y descarga todo en Excel.

Stack: un solo `index.html` (HTML/JS) + Supabase (Auth, Postgres con RLS, Storage, Edge Function). Se publica gratis con GitHub Pages.

---

## Puesta en marcha (una sola vez)

La base de datos ya está creada en el proyecto Supabase **Noraves Control Tiendas** (`elnvvoxgfnyicsrutvxs`, São Paulo) con las 20 tiendas, los 23 artes, el stock y el estado del Excel v2. Faltan 2 pasos que te tocan a ti:

1. **Crear tu usuario admin**
   Supabase › *Authentication* › *Users* › *Add user* › *Create new user*: tu correo y una contraseña, con **Auto Confirm User** marcado.
   Luego, en *SQL Editor*, ejecuta [`supabase/04_hacer_admin.sql`](supabase/04_hacer_admin.sql) (ya trae `carloz.asian@gmail.com`).
2. **Crear los usuarios de las tiendas**
   Entra al sistema como admin › pestaña **Tiendas** › **Crear usuario** en cada tienda y ponle su contraseña. La tienda entra con su código y esa contraseña.

Recomendado: Supabase › *Authentication* › *Sign In / Providers* › desactiva **Allow new users to sign up**, para que nadie se registre por su cuenta.

## Cómo funciona

| Estado | Significado |
|---|---|
| ✔ Tiene | La tienda lo tiene en buen estado |
| ✘ No tiene | Falta → hay que enviarlo |
| ⚠ Deteriorado | Hay que reponerlo |
| ➜ En camino | Marketing ya lo envió (el antiguo "1" del Excel) |
| — Sin dato | La tienda aún no envía su control del mes |

- El informe es **mensual** y se actualiza solo: cuenta el **último envío de cada tienda** en el mes elegido.
- En **Pedido y envío** marcas lo despachado (uno por uno, por tienda o por selección). Pasa a *En camino*, se descuenta del stock de almacén y la tienda lo ve. Cuando la tienda marca *Lo tenemos*, queda **recibido** automáticamente. Un envío marcado por error se puede **anular**.
- **A pedir al proveedor** = (faltantes + deteriorados) × cantidad por tienda − stock en almacén.
- Proveedor, material y medida son **obligatorios** y el precio sugerido es opcional. Solo los ve el admin; la base de datos los guarda en una tabla aparte que las tiendas no pueden leer.
- **Pedido por cantidad (materiales):** cada artículo tiene un *Pedido máximo*. Si es 1, se controla por unidad. Si es mayor, cuando la tienda marca *No lo tenemos* o *Deteriorado*, elige cuántos necesita (de 1 hasta el máximo), y esa cantidad pasa directa a *Pedido y envío* y al cálculo de *A pedir*.
- "Quitar" una categoría o artículo lo oculta sin borrar el historial.
- Las fotos se optimizan en el navegador a WebP: grande (máx. 1600 px) para PC y miniatura (480 px) para celular. La tarjeta se adapta a la proporción real de cada pieza.

### Campañas
- Pestaña **Campañas** (admin): crea una campaña con nombre, descripción, fechas, piezas (del Catálogo) y tiendas participantes.
- Mientras esté vigente, cada tienda participante ve una tarjeta **📣 Campaña** en su inicio y valida cada pieza: **Llegó · Aún no llegó · Llegó dañado**, con **foto opcional** (se guarda privada: solo la ve esa tienda y el admin).
- El informe muestra quién validó, cuándo, el estado por pieza con sus fotos, y la lista **Por resolver**, donde marcas reenvíos. Esos reenvíos pasan a *En camino* y descuentan stock, igual que en Pedido y envío. Se descarga en Excel con las hojas Resumen, Detalle e Historial.
- Las piezas de campaña siguen apareciendo en el control mensual.

### Informes y Excel
- **Faltantes**: *Matriz* (igual a tu Excel, con las fotos), *Por tienda*, *Por ciudad*, *Total*. Se pueden filtrar por ciudad y por categoría o grupo, y activar **"Solo lo que hay que pedir y enviar"**.
- Cada vista tiene su botón **⬇ Excel**. **⬇ Excel completo** descarga un libro con: Registros, Pendientes, Matriz general, Por tienda, Por ciudad, Total, Enviar a tiendas, Pedir al proveedor, En camino, una hoja por categoría y Catálogo.

## Archivos

```
index.html                      App completa (panel tienda + panel admin)
fotos/                          23 artes iniciales en WebP (sacados del Excel v2)
supabase/01_schema.sql          Tablas, seguridad (RLS), funciones y bucket de fotos
supabase/02_seed.sql            Ciudades, tiendas, categorías y artículos iniciales
supabase/03_importar_estado_excel.sql   Estado del Excel v2 (✔ / vacío / 1)
supabase/04_hacer_admin.sql     Dar rol admin a un usuario
supabase/05_campanas.sql        Campañas: tablas, permisos, validación y fotos de evidencia
supabase/06_materiales_cantidad.sql  Pedido por cantidad + 8 materiales iniciales
supabase/functions/gestionar-tienda/   Crea usuarios de tienda y cambia contraseñas (Edge Function)
```

Las fotos iniciales venían en baja resolución dentro del Excel. Para cambiarlas por los originales: **Catálogo › Editar › Elegir imagen**.
