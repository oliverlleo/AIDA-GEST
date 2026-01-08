
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://cpydazjwlmssbzzsurxu.supabase.co';
const SUPABASE_KEY = 'sbp_bb8d8691fccd83e6a48791b2c8a0f0347316d960';

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

async function testAdmin() {
    console.log("Testing key...");
    const { data, error } = await supabase.auth.admin.listUsers();
    if (error) {
        console.error("Error:", error.message);
    } else {
        console.log("Success! Users found:", data.users.length);
    }
}

testAdmin();
