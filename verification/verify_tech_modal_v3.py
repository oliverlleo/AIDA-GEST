
from playwright.sync_api import sync_playwright
import time
import os

def run():
    cwd = os.getcwd()
    file_path = f'file://{cwd}/index.html'
    print(f'Navigating to: {file_path}')

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Load the local index.html directly
        page.goto(file_path)

        # Mock localStorage and Supabase via init script
        page.add_init_script("""
            const mockEmp = {
                id: 'mock-emp-id',
                name: 'Tecnico Teste',
                username: 'tech',
                roles: ['tecnico'],
                workspace_id: 'ws-123',
                company_code: '1234'
            };
            localStorage.setItem('techassist_employee', JSON.stringify(mockEmp));

            // Mock Supabase
            window.supabase = {
                createClient: () => ({
                    auth: {
                        getSession: () => Promise.resolve({ data: { session: null } }),
                        onAuthStateChange: () => {}
                    },
                    from: (table) => {
                        return {
                        select: () => ({
                             eq: () => ({
                                 order: () => Promise.resolve({ data: [
                                     {
                                         id: 1,
                                         status: 'Analise Tecnica',
                                         device_model: 'iPhone 13',
                                         client_name: 'Cliente Teste',
                                         priority: 'Alta',
                                         parts_needed: false,
                                         os_number: '1001',
                                         deadline: new Date(Date.now() + 86400000).toISOString()
                                     }
                                 ], error: null })
                             })
                        })
                    }},
                    channel: () => ({ on: () => ({ subscribe: () => {} }) }),
                    rpc: (name) => Promise.resolve({ data: [] })
                })
            };
        """)

        page.reload()
        # Wait for Alpine to process the mocked data
        time.sleep(3)

        # Check if 'Minha Bancada' is visible
        if page.get_by_text('Minha Bancada').is_visible():
            print('Found Minha Bancada')
            page.get_by_text('Minha Bancada').click()
            time.sleep(1)

            # Click 'Abrir Painel'
            print('Clicking Abrir Painel')
            page.get_by_role('button', name='Abrir Painel').click()
            time.sleep(1)

            page.screenshot(path='verification/tech_view_modal.png')

            # Check for specific text that only appears in Tech View
            # 'Conclusão da Análise' is inside the x-if block
            if page.get_by_text('Conclusão da Análise').is_visible():
                print('SUCCESS: Tech Controls Visible')
            else:
                print('FAILURE: Tech Controls NOT Visible')
        else:
            print('Minha Bancada link not found')
            page.screenshot(path='verification/debug_home.png')

        browser.close()

if __name__ == '__main__':
    run()
