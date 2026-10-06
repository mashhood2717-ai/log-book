// Runs supabase/schema.sql on a real PostgreSQL (PGlite, in-memory) with
// stand-ins for Supabase's auth schema, then checks the security rules.
//
// Run from the project folder:
//   deno run -A --node-modules-dir=none supabase/tests/schema_test.ts
import { PGlite } from "npm:@electric-sql/pglite@0.3";

const db = new PGlite();
const schema = await Deno.readTextFile(new URL("../schema.sql", import.meta.url));

// --- Minimal Supabase stand-ins -------------------------------------------
await db.exec(`
  create schema auth;
  create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create role authenticated;
`);
await db.exec(schema);
await db.exec(`
  grant usage on schema public, auth to authenticated;
  grant all on all tables in schema public to authenticated;
  grant execute on all functions in schema public, auth to authenticated;
`);

const ADMIN = "00000000-0000-0000-0000-00000000000a";
const DRIVER = "00000000-0000-0000-0000-00000000000d";
await db.exec(`
  insert into auth.users values
    ('${ADMIN}', 'boss@x.com', '{"full_name":"Boss"}'),
    ('${DRIVER}', 'ali@x.com', '{"full_name":"Ali"}');
  update public.profiles set role = 'admin' where id = '${ADMIN}';
  insert into public.vehicles (reg_no, last_odometer) values ('LEB-1', 1000);
`);

let failures = 0;
function check(name: string, ok: boolean, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok ? "" : "  -> " + detail}`);
  if (!ok) failures++;
}

/** Run SQL as a signed-in user (RLS applies). Returns rows. */
async function as(user: string, sql: string) {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${user}', false);`);
  try {
    return (await db.query(sql)).rows as Record<string, unknown>[];
  } finally {
    await db.exec(`reset role;`);
  }
}
const one = async (sql: string) => (await db.query(sql)).rows[0] as Record<string, unknown>;
const odo = async () => (await one(`select last_odometer from vehicles where reg_no='LEB-1'`)).last_odometer;

// --- 1. Driver starts and ends a trip; can't fake the end time ------------
const [t1] = await as(DRIVER, `insert into trips (vehicle_id, start_mileage, purpose, destination)
  values (1, 1000, 'Visit', 'Nowshera') returning id`);
await as(DRIVER, `update trips set status='completed', end_mileage=1100,
  end_time='2000-01-01' where id=${t1.id}`);
let t = await one(`select * from trips where id=${t1.id}`);
check("end time comes from server clock", new Date(t.end_time as string).getFullYear() > 2000);
check("odometer updated on end", (await odo()) === 1100, String(await odo()));
check("fresh trip not marked edited", t.edited_at === null);

// --- 2. Driver corrects within 24h; locked fields stay locked ------------
const endBefore = String(t.end_time);
const upd = await as(DRIVER, `update trips set end_mileage=1090, notes='typo fixed',
  status='ongoing', end_time='2000-01-01', end_lat=1, start_time='2000-01-01'
  where id=${t1.id} returning id`);
t = await one(`select * from trips where id=${t1.id}`);
check("driver can edit finished trip within 24h", upd.length === 1);
check("edit keeps trip finished", t.status === "completed", String(t.status));
check("edit can't change end time", String(t.end_time) === endBefore);
check("edit can't change start time", new Date(t.start_time as string).getFullYear() > 2000);
check("edit can't change end GPS", t.end_lat === null, String(t.end_lat));
check("edit marks trip as edited", t.edited_at !== null);
check("notes saved", t.notes === "typo fixed");
check("odometer follows corrected (lower) reading", (await odo()) === 1090, String(await odo()));

// --- 3. After 24h the driver can't edit any more ---------------------------
await db.exec(`alter table trips disable trigger trips_guard;
  update trips set end_time = now() - interval '25 hours',
                   start_time = now() - interval '26 hours' where id=${t1.id};
  alter table trips enable trigger trips_guard;`);
const late = await as(DRIVER, `update trips set notes='too late' where id=${t1.id} returning id`);
check("driver blocked after 24h", late.length === 0);
const adminLate = await as(ADMIN, `update trips set notes='admin fix' where id=${t1.id} returning id`);
check("admin can still correct after 24h (database level)", adminLate.length === 1);

// --- 4. Only admins delete; odometer falls back ----------------------------
const dDel = await as(DRIVER, `delete from trips where id=${t1.id} returning id`);
check("driver cannot delete", dDel.length === 0);
const aDel = await as(ADMIN, `delete from trips where id=${t1.id} returning id`);
check("admin can delete", aDel.length === 1);
check("odometer falls back to deleted trip's start", (await odo()) === 1000, String(await odo()));

// --- 5. Deleting an older trip doesn't lower a newer reading ---------------
const [a] = await as(DRIVER, `insert into trips (vehicle_id, start_mileage, purpose, destination)
  values (1, 1000, 'A', 'X') returning id`);
await as(DRIVER, `update trips set status='completed', end_mileage=1100 where id=${a.id}`);
const [b] = await as(DRIVER, `insert into trips (vehicle_id, start_mileage, purpose, destination)
  values (1, 1100, 'B', 'Y') returning id`);
await as(DRIVER, `update trips set status='completed', end_mileage=1200 where id=${b.id}`);
await as(ADMIN, `delete from trips where id=${a.id}`);
check("deleting older trip keeps newer reading", (await odo()) === 1200, String(await odo()));
await as(DRIVER, `update trips set end_mileage=1150 where id=${b.id}`);
check("correcting latest trip lowers odometer", (await odo()) === 1150, String(await odo()));
await as(ADMIN, `delete from trips where id=${b.id}`);
check("deleting only trip falls back to its start", (await odo()) === 1100, String(await odo()));

// --- 6. Driver can't touch someone else's trip -----------------------------
const [c] = await as(ADMIN, `insert into trips (driver_id, vehicle_id, start_mileage, purpose, destination)
  values ('${ADMIN}', 1, 1100, 'C', 'Z') returning id`);
const other = await as(DRIVER, `update trips set notes='hack' where id=${c.id} returning id`);
check("driver can't edit another person's trip", other.length === 0);
const bad = await as(DRIVER, `update trips set end_mileage = 5 where id=${c.id} returning id`);
check("…nor via end mileage", bad.length === 0);

console.log(failures ? `\n${failures} FAILED` : "\nALL PASSED");
Deno.exit(failures ? 1 : 0);
