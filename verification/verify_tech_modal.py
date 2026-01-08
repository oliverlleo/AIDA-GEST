
from playwright.sync_api import sync_playwright
import time

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Load the local index.html directly
        page.goto('file:///home/jules/src/index.html')

        # Wait for app initialization (mocking localStorage for Tech view)
        page.evaluate('''() => {
            const mockEmp = {
                id: 'mock-emp-id',
                name: 'Tecnico Teste',
                username: 'tech',
                roles: ['tecnico'],
                workspace_id: 'ws-123',
                company_code: '1234'
            };
            localStorage.setItem('techassist_employee', JSON.stringify(mockEmp));

            // Mock Supabase client to avoid errors blocking UI
            window.supabase = {
                createClient: () => ({
                    auth: {
                        getSession: () => Promise.resolve({ data: { session: null } }),
                        onAuthStateChange: () => {}
                    },
                    from: () => ({
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
                                         os_number: '1001'
                                     }
                                 ], error: null })
                             })
                        })
                    }),
                    channel: () => ({ on: () => ({ subscribe: () => {} }) }),
                    rpc: (name) => {
                        if (name === 'get_employees_for_workspace') return Promise.resolve({ data: [] });
                        return Promise.resolve({ data: [] });
                    }
                })
            };
        }''')

        page.reload()
        time.sleep(2) # Wait for Alpine init

        # Click 'Minha Bancada' in sidebar
        page.get_by_text('Minha Bancada').click()
        time.sleep(1)

        # Click 'Abrir Painel' on the card
        page.get_by_role('button', name='Abrir Painel').click()
        time.sleep(1)

        # Verify 'Conclusão da Análise' section is visible
        # This confirms that 'modalSource' was set to 'tech' correctly
        page.screenshot(path='/home/jules/verification/tech_view_modal.png')

        # Check if the text 'Conclusão da Análise' is visible
        is_visible = page.get_by_text('Conclusão da Análise').is_visible()
        print(f'Conclusion Section Visible: {is_visible}')

        browser.close()

if __name__ == '__main__':
    run()
