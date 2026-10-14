// =====================================================================
//  trip-alerts – push notification to admins when a trip starts or ends.
//
//  Called by the database trigger trips_notify_admins (supabase/schema.sql)
//  with { trip_id, event: "start" | "end" }. It re-reads the trip itself and
//  records each alert in trip_alerts, so every alert is sent at most once –
//  that's why the caller doesn't need to be signed in.
//
//  Needs the secret FCM_SERVICE_ACCOUNT = the Firebase service-account JSON
//  (Supabase → Edge Functions → Secrets). Deploy with "Verify JWT" OFF.
// =====================================================================
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export type TripRow = {
  id: number;
  driver_id: string;
  status: string;
  start_time: string;
  end_time: string | null;
  start_mileage: number;
  end_mileage: number | null;
  distance_km: number | null;
  purpose: string;
  destination: string;
  fuel_litres: number | string | null;
  fuel_cost: number | string | null;
  vehicles: { reg_no: string } | null;
  profiles: { full_name: string } | null;
};

export type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

const PKT = "Asia/Karachi";
const num = new Intl.NumberFormat("en-US");

export function pktTime(iso: string): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: PKT,
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(iso));
}

export function durationText(fromIso: string, toIso: string): string {
  const mins = Math.max(0, Math.round((Date.parse(toIso) - Date.parse(fromIso)) / 60000));
  const d = Math.floor(mins / 1440), h = Math.floor(mins / 60) % 24, m = mins % 60;
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${String(m).padStart(2, "0")}m`;
  return `${m}m`;
}

/** Title and text of the notification. */
export function alertText(event: "start" | "end", t: TripRow): { title: string; body: string } {
  const driver = t.profiles?.full_name || "A driver";
  const reg = t.vehicles?.reg_no || "a vehicle";
  if (event === "start") {
    return {
      title: `🚗 ${driver} left with ${reg}`,
      body: `→ ${t.destination} · ${t.purpose} · ${pktTime(t.start_time)} · ${num.format(t.start_mileage)} km`,
    };
  }
  const parts = [`${t.destination}`, `${num.format(t.distance_km ?? 0)} km`];
  if (t.end_time) parts.push(durationText(t.start_time, t.end_time));
  const litres = t.fuel_litres == null ? null : Number(t.fuel_litres);
  const cost = t.fuel_cost == null ? null : Number(t.fuel_cost);
  if (litres || cost) {
    parts.push(
      "fuel " + [litres ? `${litres} L` : "", cost ? `PKR ${num.format(cost)}` : ""]
        .filter(Boolean).join(" / "),
    );
  }
  return { title: `✅ ${driver} is back – ${reg}`, body: parts.join(" · ") };
}

// ---------------- Google OAuth (service account → access token) -----------
const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/** Signed JWT that Google exchanges for an access token. */
export async function signedAssertion(sa: ServiceAccount, nowSec = Math.floor(Date.now() / 1000)) {
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = enc({ alg: "RS256", typ: "JWT" }) + "." + enc({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: nowSec,
    exp: nowSec + 3600,
  });
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${b64url(new Uint8Array(sig))}`;
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const res = await fetch(sa.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await signedAssertion(sa),
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`Google auth failed: ${JSON.stringify(json)}`);
  return json.access_token;
}

// ---------------- Handler -------------------------------------------------
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  let tripId: number, event: "start" | "end";
  try {
    const b = await req.json();
    tripId = Number(b.trip_id);
    event = b.event;
    if (!Number.isInteger(tripId) || (event !== "start" && event !== "end")) throw 0;
  } catch {
    return json({ error: "Expected { trip_id, event: start|end }." }, 400);
  }

  const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saJson) return json({ error: "FCM_SERVICE_ACCOUNT secret is not set." }, 500);
  const sa: ServiceAccount = JSON.parse(saJson);

  const db: SupabaseClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: trip, error: tripErr } = await db
    .from("trips").select("*, vehicles(reg_no), profiles(full_name)")
    .eq("id", tripId).maybeSingle<TripRow>();
  if (tripErr) throw tripErr;
  if (!trip) return json({ error: "No such trip." }, 404);
  if (event === "end" && trip.status !== "completed") {
    return json({ error: "Trip has not ended." }, 409);
  }

  // Claim this alert – a second call for the same trip/event does nothing.
  const { error: dupErr } = await db.from("trip_alerts").insert({ trip_id: tripId, event });
  if (dupErr) {
    if (dupErr.code === "23505") return json({ skipped: "already sent" });
    throw dupErr;
  }

  // Every admin's phone, except the person who made the trip.
  const { data: admins, error: aErr } = await db
    .from("profiles").select("id").eq("role", "admin").neq("id", trip.driver_id);
  if (aErr) throw aErr;
  const ids = (admins ?? []).map((a: { id: string }) => a.id);
  if (!ids.length) return json({ sent: 0, note: "no other admins" });
  const { data: tokens, error: tErr } = await db
    .from("device_tokens").select("token").in("user_id", ids);
  if (tErr) throw tErr;
  if (!tokens?.length) return json({ sent: 0, note: "no admin phones registered" });

  const { title, body } = alertText(event, trip);
  const bearer = await accessToken(sa);
  let sent = 0;
  const failed: string[] = [];
  for (const { token } of tokens as { token: string }[]) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: { trip_id: String(tripId), event },
            android: {
              priority: "high",
              notification: { channel_id: "trip_alerts", color: "#0952DF", icon: "ic_stat_reminder" },
            },
          },
        }),
      },
    );
    if (res.ok) {
      sent++;
    } else {
      const err = await res.text();
      failed.push(err.slice(0, 200));
      // Phone uninstalled the app or the token expired: forget it.
      if (res.status === 404 || err.includes("UNREGISTERED")) {
        await db.from("device_tokens").delete().eq("token", token);
      }
    }
  }
  return json({ sent, failed: failed.length, errors: failed });
}

// Serve when running on Supabase (SUPABASE_URL is always set there); stay
// quiet when the tests import this file.
if (Deno.env.get("SUPABASE_URL")) {
  Deno.serve(async (req) => {
    try {
      return await handle(req);
    } catch (e) {
      console.error(e);
      return json({ error: e instanceof Error ? e.message : String(e) }, 500);
    }
  });
}
