
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

        start_time = (datetime.datetime.utcnow() - datetime.timedelta(hours=1, seconds=30)).isoformat() + "Z"

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
        page.locator("div[x-show=\"view === 'tech_orders'\"]").get_by_role("button", name="Abrir Painel").click()
        time.sleep(1)

        page.screenshot(path='verification/timer_modal.png')

        browser.close()

if __name__ == '__main__':
    run()
