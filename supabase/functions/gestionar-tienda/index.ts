// Edge Function: gestionar-tienda
// Crea usuarios de tienda, cambia contraseñas y activa/desactiva tiendas.
// Solo la puede usar un usuario con rol admin. La service_role key nunca sale del servidor.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const STORE_DOMAIN = "tiendas.noraves.app"; // debe coincidir con STORE_EMAIL_DOMAIN en index.html

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // ¿Quién llama? Debe ser admin.
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: { user } } = await admin.auth.getUser(token);
    if (!user) return json({ error: "No autenticado" }, 401);
    const { data: prof } = await admin.from("profiles").select("role").eq("user_id", user.id).maybeSingle();
    if (prof?.role !== "admin") return json({ error: "Solo administradores" }, 403);

    const body = await req.json();
    const { action } = body;

    if (action === "create") {
      const code = String(body.code ?? "").trim().toUpperCase();
      const name = String(body.name ?? "").trim();
      const city_id = Number(body.city_id);
      const password = String(body.password ?? "");
      if (!/^[A-Z0-9-]{3,20}$/.test(code)) return json({ error: "Código inválido (3-20 letras/números)" }, 400);
      if (!name || !city_id) return json({ error: "Falta nombre o ciudad" }, 400);
      if (password.length < 6) return json({ error: "La contraseña debe tener al menos 6 caracteres" }, 400);

      // La tienda puede existir ya (cargada por SQL) sin usuario
      let { data: store } = await admin.from("stores").select("*").eq("code", code).maybeSingle();
      if (store?.user_id) return json({ error: "Esa tienda ya tiene usuario" }, 409);
      if (!store) {
        const { data, error } = await admin.from("stores").insert({ code, name, city_id }).select().single();
        if (error) return json({ error: error.message }, 400);
        store = data;
      }
      const { data: created, error: e1 } = await admin.auth.admin.createUser({
        email: `${code.toLowerCase()}@${STORE_DOMAIN}`, password, email_confirm: true,
        user_metadata: { store_code: code },
      });
      if (e1) return json({ error: e1.message }, 400);
      await admin.from("stores").update({ user_id: created.user.id, name, city_id }).eq("id", store.id);
      await admin.from("profiles").insert({ user_id: created.user.id, role: "store", store_id: store.id });
      return json({ ok: true });
    }

    if (action === "password") {
      const { data: store } = await admin.from("stores").select("user_id").eq("id", body.store_id).single();
      if (!store?.user_id) return json({ error: "La tienda no tiene usuario" }, 400);
      if (String(body.password ?? "").length < 6) return json({ error: "Mínimo 6 caracteres" }, 400);
      const { error } = await admin.auth.admin.updateUserById(store.user_id, { password: body.password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (action === "active") {
      const { data: store } = await admin.from("stores").update({ active: !!body.active })
        .eq("id", body.store_id).select("user_id").single();
      if (store?.user_id) {
        await admin.auth.admin.updateUserById(store.user_id, { ban_duration: body.active ? "none" : "876000h" });
      }
      return json({ ok: true });
    }

    return json({ error: "Acción desconocida" }, 400);
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});
