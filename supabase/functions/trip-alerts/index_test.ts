// deno test -A --node-modules-dir=none supabase/functions/trip-alerts/
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { alertText, durationText, pktTime, signedAssertion, type TripRow } from "./index.ts";

const trip: TripRow = {
  id: 7,
  driver_id: "d",
  status: "completed",
  start_time: "2026-10-14T05:10:00Z", // 10:10 AM PKT
  end_time: "2026-10-14T08:15:00Z",
  start_mileage: 45210,
  end_mileage: 45298,
  distance_km: 88,
  purpose: "AWS maintenance",
  destination: "Nowshera",
  fuel_litres: "20.00",
  fuel_cost: "5600.00",
  vehicles: { reg_no: "LEB-1234" },
  profiles: { full_name: "Ali Khan" },
};

Deno.test("times are shown in Pakistan time", () => {
  assertEquals(pktTime("2026-10-14T05:10:00Z"), "10:10 AM");
});

Deno.test("duration text", () => {
  assertEquals(durationText(trip.start_time, trip.end_time!), "3h 05m");
  assertEquals(durationText("2026-10-14T05:00:00Z", "2026-10-14T05:45:00Z"), "45m");
});

Deno.test("start alert", () => {
  const { title, body } = alertText("start", trip);
  assertEquals(title, "🚗 Ali Khan left with LEB-1234");
  assertEquals(body, "→ Nowshera · AWS maintenance · 10:10 AM · 45,210 km");
});

Deno.test("end alert with fuel", () => {
  const { title, body } = alertText("end", trip);
  assertEquals(title, "✅ Ali Khan is back – LEB-1234");
  assertEquals(body, "Nowshera · 88 km · 3h 05m · fuel 20 L / PKR 5,600");
});

Deno.test("end alert without fuel", () => {
  const { body } = alertText("end", { ...trip, fuel_litres: null, fuel_cost: null });
  assertEquals(body, "Nowshera · 88 km · 3h 05m");
});

Deno.test("service-account JWT is correctly RS256-signed", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keys.privateKey));
  const pem = "-----BEGIN PRIVATE KEY-----\n" + btoa(String.fromCharCode(...pkcs8)) + "\n-----END PRIVATE KEY-----\n";
  const jwt = await signedAssertion(
    { project_id: "p", client_email: "svc@p.iam.gserviceaccount.com", private_key: pem }, 1000,
  );
  const [h, c, s] = jwt.split(".");
  const dec = (x: string) => Uint8Array.from(atob(x.replace(/-/g, "+").replace(/_/g, "/")), (ch) => ch.charCodeAt(0));
  const claims = JSON.parse(new TextDecoder().decode(dec(c)));
  assertEquals(claims.iss, "svc@p.iam.gserviceaccount.com");
  assertEquals(claims.exp - claims.iat, 3600);
  assertStringIncludes(claims.scope, "firebase.messaging");
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5", keys.publicKey, dec(s), new TextEncoder().encode(`${h}.${c}`),
  );
  assert(ok, "signature must verify with the matching public key");
});
