
from playwright.sync_api import sync_playwright
import time
import os

def run():
    cwd = os.getcwd()
    file_path = f'file://{cwd}/index.html'

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.route("**/*supabase-js*", lambda route: route.abort())

        page.add_init_script("""
            const mockEmp = { id: 'mock', name: 'Tech', roles: ['tecnico'], workspace_id: 'ws', company_code: '1' };
            localStorage.setItem('techassist_employee', JSON.stringify(mockEmp));
            window.supabase = {
                createClient: () => ({
                    auth: { getSession: () => Promise.resolve({ data: { session: null } }), onAuthStateChange: () => {} },
                    from: () => ({ select: () => ({ eq: () => ({ order: () => Promise.resolve({ data: [{
                        id: 1, status: 'Analise Tecnica', device_model: 'UniqueDevice123', client_name: 'Client',
                        priority: 'Alta', parts_needed: false, os_number: '1001',
                        deadline: new Date().toISOString(), checklist_data: []
                    }], error: null }) }) }) }),
                    channel: () => ({ on: () => ({ subscribe: () => {} }) }),
                    rpc: () => Promise.resolve({ data: [] })
                })
            };
        """)

        page.goto(file_path)
        time.sleep(2)

        page.get_by_role("link", name="Minha Bancada").click()
        time.sleep(1)

        # Scope to Tech View
        tech_view = page.locator("div[x-show=\"view === 'tech_orders'\"]")

        if tech_view.get_by_text("UniqueDevice123").is_visible():
            print("Card Found in Tech View")
            tech_view.get_by_role("button", name="Abrir Painel").click()
            time.sleep(1)

            page.screenshot(path='verification/tech_view_modal.png')

            if page.get_by_text("Conclusão da Análise").is_visible():
                print("SUCCESS: Tech Controls Visible")
            else:
                print("FAILURE: Tech Controls NOT Visible")
        else:
            print("Card NOT Found")

        browser.close()

if __name__ == '__main__':
    run()
