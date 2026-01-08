
from playwright.sync_api import sync_playwright
import time
import os
import datetime

def run():
    cwd = os.getcwd()
    file_path = f'file://{cwd}/index.html'

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.route("**/*supabase-js*", lambda route: route.abort())

        # Start time 1 hour ago
        start_time = (datetime.datetime.utcnow() - datetime.timedelta(hours=1, seconds=5)).isoformat() + "Z"

        page.add_init_script(f"""
            const mockEmp = {{ id: 'mock', name: 'Tech', roles: ['tecnico'], workspace_id: 'ws', company_code: '1' }};
            localStorage.setItem('techassist_employee', JSON.stringify(mockEmp));
            window.supabase = {{
                createClient: () => ({{
                    auth: {{ getSession: () => Promise.resolve({{ data: {{ session: null }} }}), onAuthStateChange: () => {{}} }},
                    from: () => ({{ select: () => ({{ eq: () => ({{ order: () => Promise.resolve({{ data: [{{
                        id: 1, status: 'Andamento Reparo', device_model: 'DeviceTimer', client_name: 'Client',
                        priority: 'Normal', parts_needed: false, os_number: '1001',
                        deadline: new Date().toISOString(), checklist_data: [],
                        repair_start_at: '{start_time}'
                    }}], error: null }}) }}) }}) }}),
                    channel: () => ({{ on: () => ({{ subscribe: () => {{}} }}) }}),
                    rpc: () => Promise.resolve({{ data: [] }})
                }})
            }};
        """)

        page.goto(file_path)
        time.sleep(2)

        page.get_by_role("link", name="Minha Bancada").click()
        time.sleep(1)

        # 1. Check Card Timer (approx 01:00:05)
        # We need to find the text starting with "Tempo: "
        card_text = page.locator("div[x-show=\"view === 'tech_orders'\"]").get_by_text("Tempo:").first
        if card_text.is_visible():
            initial_text = card_text.inner_text()
            print(f"Initial Card Timer: {initial_text}")
            if "01:00" in initial_text:
                print("SUCCESS: Timer showing correct initial time")
            else:
                print(f"FAILURE: Timer showing wrong time: {initial_text}")
        else:
            print("FAILURE: Card Timer not found")

        # 2. Check Ticking (Wait 3 seconds)
        time.sleep(3)
        updated_text = card_text.inner_text()
        print(f"Updated Card Timer: {updated_text}")
        if updated_text != initial_text:
             print("SUCCESS: Timer is ticking")
        else:
             print("FAILURE: Timer is STUCK")

        # 3. Check Modal Timer
        page.locator("div[x-show=\"view === 'tech_orders'\"]").get_by_role("button", name="Abrir Painel").click()
        time.sleep(1)

        # Modal timer is in a div with text-xl
        modal_timer = page.locator(".text-xl.font-mono").first
        modal_text = modal_timer.inner_text()
        print(f"Modal Timer: {modal_text}")

        time.sleep(2)
        modal_text_2 = modal_timer.inner_text()
        print(f"Modal Timer +2s: {modal_text_2}")

        if modal_text != modal_text_2:
            print("SUCCESS: Modal Timer is ticking")
        else:
            print("FAILURE: Modal Timer is STUCK")

        browser.close()

if __name__ == '__main__':
    run()
