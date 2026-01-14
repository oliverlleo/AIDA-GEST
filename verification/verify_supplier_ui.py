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
        page.wait_for_timeout(2000)

        # Inject Data via JS to test the "Pending Supplier" lists
        page.evaluate("""
            const el = document.querySelector('[x-data]');
            const app = el._x_dataStack && el._x_dataStack[0];

            if (!app) throw new Error("Alpine data not found");

            // Mock User & View
            app.user = { id: 'test', name: 'Tester', roles: ['admin'], workspace_id: 'ws1' };
            app.view = 'dashboard';
            app.session = { user: { id: 'test' } };

            // Mock Tickets for Supplier Flow
            app.tickets = [
                // 1. Pending Purchase (Status: Compra Peca, parts_status: null/empty)
                {
                    id: 'sup1', device_model: 'iPhone 11', parts_needed: 'Tela Original',
                    status: 'Compra Peca', parts_status: null, created_at: new Date().toISOString()
                },
                // 2. Pending Receipt (Status: Compra Peca, parts_status: 'Comprado')
                {
                    id: 'sup2', device_model: 'MacBook Pro', parts_needed: 'Bateria',
                    status: 'Compra Peca', parts_status: 'Comprado', created_at: new Date().toISOString()
                }
            ];
        """)

        # Allow UI to react
        page.wait_for_timeout(2000)

        # Screenshot
        page.screenshot(path="verification/dashboard_supplier.png", full_page=True)
        print("Screenshot taken.")
        browser.close()

if __name__ == "__main__":
    run()
