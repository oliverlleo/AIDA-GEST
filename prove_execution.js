const { Client } = require('pg');

const client = new Client({
  user: 'postgres.cpydazjwlmssbzzsurxu',
  password: 'SpyDD@246819',
  host: 'aws-1-sa-east-1.pooler.supabase.com',
  port: 6543,
  database: 'postgres',
  ssl: { rejectUnauthorized: false }
});

async function run() {
  try {
    await client.connect();
    console.log("🔌 CONNECTED TO DATABASE: aws-1-sa-east-1.pooler.supabase.com");

    const res = await client.query(`
      select pg_get_functiondef(p.oid) as def
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='employee_login'
    `);

    const def = res.rows[0]?.def || "";

    if (def.includes('v_lock_minutes := LEAST(10 * power(2, v_auth_state.lock_count - 1)::int, 1440)')) {
        console.log("\n✅ STATUS: HARDENING IS ACTIVE ON DATABASE.");
        console.log("--------------------------------------------------");
        console.log("Proof (Line from DB): v_lock_minutes := LEAST(10 * power(2, v_auth_state.lock_count - 1)::int, 1440);");
        console.log("--------------------------------------------------");
    } else {
        console.log("\n❌ STATUS: HARDENING IS NOT ACTIVE.");
        console.log(def);
    }

  } catch (err) {
    console.error("Connection Error:", err);
  } finally {
    await client.end();
  }
}

run();
