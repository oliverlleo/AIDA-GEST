
from playwright.sync_api import sync_playwright
import time
import os

def run():
    cwd = os.getcwd()
    file_path = f'file://{cwd}/index.html'

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Block the real Supabase script
        page.route("**/*supabase-js*", lambda route: route.abort())

        # Inject Mock Supabase and User Data
        page.add_init_script("""
            // Mock Data
            const mockEmp = {
                id: 'mock-emp-id',
                name: 'Tecnico Teste',
                username: 'tech',
                roles: ['tecnico'],
                workspace_id: 'ws-123',
                company_code: '1234'
            };
            localStorage.setItem('techassist_employee', JSON.stringify(mockEmp));

            // Mock Supabase Factory
            window.supabase = {
                createClient: () => ({
                    auth: {
                        getSession: () => Promise.resolve({ data: { session: null } }),
                        onAuthStateChange: () => {}
                    },
                    from: (table) => {
                        console.log('Mock DB Call:', table);
                        return {
                            select: () => ({
                                eq: () => ({
                                    order: () => Promise.resolve({
                                        data: [
                                            {
                                                id: 1,
                                                status: 'Analise Tecnica', // TARGET STATUS
                                                device_model: 'iPhone 13 Pro',
                                                client_name: 'Maria Teste',
                                                priority: 'Alta',
                                                parts_needed: false,
                                                os_number: '1001',
                                                deadline: new Date(Date.now() + 86400000).toISOString(),
                                                checklist_data: []
                                            }
                                        ],
                                        error: null
                                    })
                                })
                            })
                        };
                    },
                    channel: () => ({ on: () => ({ subscribe: () => {} }) }),
                    rpc: (name) => {
                         console.log('Mock RPC:', name);
                         return Promise.resolve({ data: [] });
                    }
                })
            };
        """)

        page.on("console", lambda msg: print(f"CONSOLE: {msg.text}"))

        page.goto(file_path)
        time.sleep(2)

        # Navigate to Tech View
        if page.get_by_role("link", name="Minha Bancada").is_visible():
            page.get_by_role("link", name="Minha Bancada").click()
            time.sleep(1)

            # Check if card appeared
            if page.get_by_text("iPhone 13 Pro").is_visible():
                print("Card Found!")

                # Click Open Panel
                page.get_by_role("button", name="Abrir Painel").click()
                time.sleep(1)

                page.screenshot(path='verification/tech_view_modal.png')

                # VERIFICATION POINT
                if page.get_by_text("Conclusão da Análise").is_visible():
                     print("SUCCESS: Tech Controls Visible")
                     # Also check if hidden in normal view? (Optional, but good sanity check)
                else:
                     print("FAILURE: Tech Controls NOT Visible")
            else:
                print("Card NOT Found - List Empty?")
                page.screenshot(path='verification/debug_empty.png')
        else:
            print("Sidebar link not found")
            page.screenshot(path='verification/debug_home.png')

        browser.close()

if __name__ == '__main__':
    run()
