from playwright.sync_api import sync_playwright
import json
import time

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        page = context.new_page()

        # Mock User Data
        mock_user = {
            "id": "00000000-0000-0000-0000-000000000000",
            "workspace_id": "00000000-0000-0000-0000-000000000000",
            "name": "Test User",
            "roles": ["admin"],
            "tracker_config": {
                "enable_outsourced": True,
                "visible_stages": ["Aberto", "Terceirizado", "Finalizado"],
                "colors": {}
            }
        }

        # Navigate to set localStorage
        page.goto("http://localhost:8080/index.html")

        # Inject localStorage
        page.evaluate(f"localStorage.setItem('techassist_employee', '{json.dumps(mock_user)}');")

        # Reload to apply
        page.reload()

        # Wait for app to load (dismiss loading overlay if present)
        # Assuming the 'Novo Chamado' button is visible when loaded
        try:
            page.wait_for_selector("text=Novo Chamado", timeout=10000)
        except:
            print("Timeout waiting for dashboard.")
            page.screenshot(path="verification/debug_load.png")

        # Click "Novo Chamado"
        page.click("text=Novo Chamado")

        # Wait for modal
        page.wait_for_selector("text=Detalhes do Chamado")

        # Wait a bit for transitions
        time.sleep(1)

        # Take screenshot of the modal area
        page.screenshot(path="verification/ticket_modal.png")
        print("Screenshot taken at verification/ticket_modal.png")

        browser.close()

if __name__ == "__main__":
    run()
