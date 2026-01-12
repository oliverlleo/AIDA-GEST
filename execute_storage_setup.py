
import urllib.request
import json
import os

SERVICE_KEY = 'sbp_bb8d8691fccd83e6a48791b2c8a0f0347316d960'
sql_file = 'setup_storage.sql'

if not os.path.exists(sql_file):
    print(f"Error: {sql_file} not found.")
    exit(1)

with open(sql_file, 'r') as f:
    sql = f.read()

api_url = "https://api.supabase.com/v1/projects/cpydazjwlmssbzzsurxu/database/query"
headers = {
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json"
}

data = json.dumps({"query": sql}).encode('utf-8')

try:
    req = urllib.request.Request(api_url, data=data, headers=headers, method='POST')
    with urllib.request.urlopen(req) as response:
        print("SQL executed successfully.")
        print(response.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print(f"HTTP Error {e.code}: {e.read().decode('utf-8')}")
except Exception as e:
    print(f"Error: {e}")
