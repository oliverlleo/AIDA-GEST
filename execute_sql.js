
const fs = require('fs');
const https = require('https');

const REF = 'cpydazjwlmssbzzsurxu';
const TOKEN = process.env.SUPABASE_SERVICE_KEY;
const SQL_FILE = process.argv[2];

if (!TOKEN) {
    console.error("Error: SUPABASE_SERVICE_KEY environment variable is not set.");
    process.exit(1);
}

if (!SQL_FILE) {
    console.error("Usage: node execute_sql.js <file.sql>");
    process.exit(1);
}

const sql = fs.readFileSync(SQL_FILE, 'utf8');

const options = {
    hostname: 'api.supabase.com',
    path: `/v1/projects/${REF}/database/query`,
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${TOKEN}`
    }
};

const req = https.request(options, (res) => {
    let data = '';
    res.on('data', (chunk) => data += chunk);
    res.on('end', () => {
        console.log(`Status: ${res.statusCode}`);
        console.log('Response:', data);
    });
});

req.on('error', (e) => {
    console.error(`Problem with request: ${e.message}`);
});

req.write(JSON.stringify({ query: sql }));
req.end();
