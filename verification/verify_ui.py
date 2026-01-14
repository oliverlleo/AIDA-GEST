from playwright.sync_api import sync_playwright
import os
import time

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Load local file
        cwd = os.getcwd()
        page.goto(f"file://{cwd}/index.html")

        # Wait for Alpine to initialize
        # Wait for the body to have the x-data attribute (it has it initially)
        # But we need Alpine to process it.
        page.wait_for_timeout(2000)

        # Inject Data via JS
        page.evaluate("""
            const el = document.querySelector('[x-data]');
            // Alpine v3 uses _x_dataStack
            const app = el._x_dataStack && el._x_dataStack[0];

            if (!app) throw new Error("Alpine data not found");

            // Mock User & View
            app.user = { id: 'test', name: 'Tester', roles: ['admin'], workspace_id: 'ws1' };
            app.view = 'dashboard';
            app.session = { user: { id: 'test' } };

            // Mock Tickets
            app.tickets = [
                {
                    id: '1', client_name: 'Maria Silva', os_number: '1001', device_model: 'iPhone 13 Pro',
                    priority_requested: true, status: 'Analise Tecnica', created_at: new Date().toISOString()
                },
                {
                    id: '2', client_name: 'João Souza', os_number: '1002', device_model: 'Samsung S21',
                    priority_requested: false, status: 'Andamento Reparo', deadline: '2023-01-01T00:00:00Z', created_at: new Date().toISOString()
                },
                {
                    id: '3', client_name: 'Empresa XYZ', os_number: '1003', device_model: 'MacBook Air',
                    priority_requested: true, status: 'Aberto', created_at: new Date().toISOString()
                }
            ];

            // Mock Logs
            app.dashboardLogs = [
                {
                    id: 1, action: 'Iniciou Reparo', user_name: 'Pedro Tech', created_at: new Date().toISOString(),
                    tickets: { os_number: '1001', client_name: 'Maria Silva', device_model: 'iPhone 13 Pro' }
                },
                {
                    id: 2, action: 'Aprovou Orçamento', user_name: 'Ana Atend', created_at: new Date(Date.now() - 3600000).toISOString(),
                    tickets: { os_number: '1002', client_name: 'João Souza', device_model: 'Samsung S21' }
                }
            ];
        """)

        # Allow UI to react
        page.wait_for_timeout(2000)

        # Screenshot
        page.screenshot(path="verification/dashboard_ops.png", full_page=True)
        print("Screenshot taken.")
        browser.close()

if __name__ == "__main__":
    run()
