
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
        page.goto(file_path)

        # Mocking
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
            window.supabase = {
                createClient: () => ({
                    auth: { getSession: () => Promise.resolve({ data: { session: null } }), onAuthStateChange: () => {} },
                    from: () => ({
                        select: () => ({
                             eq: () => ({
                                 order: () => Promise.resolve({ data: [{
                                     id: 1, status: 'Analise Tecnica', device_model: 'iPhone 13',
                                     client_name: 'Cliente', priority: 'Alta', parts_needed: false,
                                     os_number: '1001', deadline: new Date().toISOString()
                                 }], error: null })
                             })
                        })
                    }),
                    channel: () => ({ on: () => ({ subscribe: () => {} }) }),
                    rpc: () => Promise.resolve({ data: [] })
                })
            };
        """)

        page.reload()
        time.sleep(2)

        # Click Sidebar Link
        page.get_by_role("link", name="Minha Bancada").click()
        time.sleep(1)

        # Click Open Panel
        page.get_by_role("button", name="Abrir Painel").click()
        time.sleep(1)

        page.screenshot(path='verification/tech_view_modal.png')

        # Check for Tech Controls
        if page.get_by_text('Conclusão da Análise').is_visible():
            print('SUCCESS: Tech Controls Visible')
        else:
            print('FAILURE: Tech Controls NOT Visible')

        browser.close()

if __name__ == '__main__':
    run()
