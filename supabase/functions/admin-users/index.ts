// =====================================================================
//  admin-users – lets an admin manage logins from the app.
//
//  Runs on Supabase's servers, where the secret (service_role) key is
//  available. The app never sees that key. Every request is checked:
//  the caller must be signed in AND have role = 'admin' in profiles.
//
//  Deploy: Supabase Dashboard > Edge Functions > Deploy a new function
//          > Via Editor > name it exactly "admin-users" > paste this file.
//
//  Actions (POST JSON body):
//    { action: "list" }
//    { action: "create", email, password, full_name, role? }
//    { action: "update", id, full_name?, role?, password?, banned? }
//    { action: "delete", id }            only users with no trips
// =====================================================================
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

/** Error the app shows to the admin as-is. */
const fail = (message: string, status = 400) => json({ error: message }, status);

const ROLES = ["driver", "admin"];
const BAN_FOREVER = "876000h"; // ~100 years

type ProfileRow = { id: string; full_name: string; role: string };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail("Use POST.", 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  // ---- Who is calling? Must be a signed-in admin. --------------------
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who, error: whoErr } = await admin.auth.getUser(token);
  if (whoErr || !who?.user) return fail("Please sign in again.", 401);
  const callerId = who.user.id;

  const { data: callerProfile } = await admin
    .from("profiles").select("role").eq("id", callerId).maybeSingle();
  if (callerProfile?.role !== "admin") {
    return fail("Only an admin can manage users.", 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("Invalid request.");
  }

  try {
    switch (body.action) {
      case "list":
        return json(await listUsers(admin));
      case "create":
        return await createUser(admin, body);
      case "update":
        return await updateUser(admin, body, callerId);
      case "delete":
        return await deleteUser(admin, body, callerId);
      default:
        return fail("Unknown action.");
    }
  } catch (e) {
    console.error(e);
    return fail(e instanceof Error ? e.message : "Something went wrong.", 500);
  }
});

type Admin = SupabaseClient;

async function listUsers(admin: Admin) {
  const users = [];
  for (let page = 1; ; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) break;
  }
  const { data: profiles, error } = await admin
    .from("profiles").select("id, full_name, role");
  if (error) throw error;
  const byId = new Map(
    (profiles as ProfileRow[]).map((p): [string, ProfileRow] => [p.id, p]),
  );
  const now = Date.now();

  return users.map((u) => ({
    id: u.id,
    email: u.email ?? "",
    full_name: byId.get(u.id)?.full_name ?? "",
    role: byId.get(u.id)?.role ?? "driver",
    banned: !!u.banned_until && new Date(u.banned_until).getTime() > now,
    last_sign_in_at: u.last_sign_in_at ?? null,
    created_at: u.created_at,
  }));
}

function checkPassword(p: unknown): string | null {
  if (typeof p !== "string" || p.length < 6) {
    return "Password must be at least 6 characters.";
  }
  return null;
}

async function createUser(admin: Admin, b: Record<string, unknown>) {
  const email = String(b.email ?? "").trim().toLowerCase();
  const fullName = String(b.full_name ?? "").trim();
  const role = String(b.role ?? "driver");
  if (!email.includes("@")) return fail("Enter a valid email.");
  if (!fullName) return fail("Enter the person's name.");
  if (!ROLES.includes(role)) return fail("Invalid role.");
  const pwErr = checkPassword(b.password);
  if (pwErr) return fail(pwErr);

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: b.password as string,
    email_confirm: true, // no confirmation email needed
    user_metadata: { full_name: fullName },
  });
  if (error) {
    if (/already/i.test(error.message)) {
      return fail("A user with this email already exists.");
    }
    return fail(error.message);
  }

  // The database trigger creates the profile; make sure name + role are right.
  const { error: pErr } = await admin.from("profiles").upsert({
    id: data.user.id,
    full_name: fullName,
    role,
  });
  if (pErr) throw pErr;
  return json({ id: data.user.id });
}

async function updateUser(admin: Admin, b: Record<string, unknown>, callerId: string) {
  const id = String(b.id ?? "");
  if (!id) return fail("Missing user.");
  const self = id === callerId;

  // Never let an admin lock themselves out.
  if (self && b.role !== undefined && b.role !== "admin") {
    return fail("You can't remove your own admin rights.");
  }
  if (self && b.banned === true) return fail("You can't block yourself.");

  const profile: Record<string, string> = {};
  if (b.full_name !== undefined) {
    const n = String(b.full_name).trim();
    if (!n) return fail("Name can't be empty.");
    profile.full_name = n;
  }
  if (b.role !== undefined) {
    if (!ROLES.includes(String(b.role))) return fail("Invalid role.");
    profile.role = String(b.role);
  }
  if (Object.keys(profile).length) {
    const { error } = await admin.from("profiles").update(profile).eq("id", id);
    if (error) throw error;
  }

  const auth: Record<string, unknown> = {};
  if (b.password !== undefined) {
    const pwErr = checkPassword(b.password);
    if (pwErr) return fail(pwErr);
    auth.password = b.password;
  }
  if (b.banned !== undefined) auth.ban_duration = b.banned ? BAN_FOREVER : "none";
  if (Object.keys(auth).length) {
    const { error } = await admin.auth.admin.updateUserById(id, auth);
    if (error) return fail(error.message);
  }
  return json({ ok: true });
}

async function deleteUser(admin: Admin, b: Record<string, unknown>, callerId: string) {
  const id = String(b.id ?? "");
  if (!id) return fail("Missing user.");
  if (id === callerId) return fail("You can't delete yourself.");

  // Keep history: anyone with trips can only be blocked, not deleted.
  const { count, error } = await admin
    .from("trips").select("id", { count: "exact", head: true }).eq("driver_id", id);
  if (error) throw error;
  if ((count ?? 0) > 0) {
    return fail(`This person has ${count} trip(s). Block them instead, so their history is kept.`);
  }

  const { error: dErr } = await admin.auth.admin.deleteUser(id);
  if (dErr) return fail(dErr.message);
  return json({ ok: true });
}
