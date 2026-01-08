
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

        # 1. Check KANBAN View (Default)
        print("Checking Kanban View...")
        # Kanban is default view. Find the card in the Analise Tecnica column.
        # It's in the second column (Analise Tecnica).
        # We need to find the card with UniqueDevice123 and click it.
        # Since UniqueDevice123 appears in Tech View too, we must ensure we click the Kanban one.
        # Kanban container: x-show="view === 'kanban'"

        kanban_view = page.locator("div[x-show=\"view === 'kanban'\"]")
        if kanban_view.is_visible():
             # Find card inside kanban
             card = kanban_view.get_by_text("UniqueDevice123")
             if card.count() > 0:
                 card.first.click()
                 time.sleep(1)

                 # Check Modal
                 if page.get_by_text("Conclusão da Análise").is_visible():
                     print("FAILURE: Tech Controls Visible in Kanban (Should be hidden)")
                 else:
                     print("SUCCESS: Tech Controls Hidden in Kanban")

                 # Close Modal
                 page.get_by_role("button", name="Fechar").click()
                 time.sleep(1)
             else:
                 print("Kanban Card not found")

        # 2. Check TECH View
        print("Checking Tech View...")
        page.get_by_role("link", name="Minha Bancada").click()
        time.sleep(1)

        tech_view = page.locator("div[x-show=\"view === 'tech_orders'\"]")
        tech_view.get_by_role("button", name="Abrir Painel").click()
        time.sleep(1)

        if page.get_by_text("Conclusão da Análise").is_visible():
             print("SUCCESS: Tech Controls Visible in Tech View")
        else:
             print("FAILURE: Tech Controls NOT Visible in Tech View")

        browser.close()

if __name__ == '__main__':
    run()
