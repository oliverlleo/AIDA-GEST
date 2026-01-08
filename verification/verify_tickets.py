
from playwright.sync_api import sync_playwright
import json

def verify_tickets(page):
    # Load the page initially to have the context
    page.goto("file:///app/index.html")

    # Inject fake session into localStorage
    fake_session = {
        "id": "123",
        "name": "Test User",
        "username": "tester",
        "workspace_id": "ws-123",
        "workspace_name": "Test Workspace",
        "company_code": "9999",
        "roles": ["admin"]
    }

    page.evaluate(f"localStorage.setItem('techassist_employee', '{json.dumps(fake_session)}');")

    # Reload to pick up the session
    page.reload()

    # Wait for the dashboard to load (checking for "Visão Geral")
    page.wait_for_selector("text=Visão Geral")

    # Take screenshot of Dashboard
    page.screenshot(path="verification/dashboard.png")

    # Click on "Chamados" in Sidebar
    # Using a more robust selector if needed, or just text
    page.click("text=Chamados")

    # Wait for Kanban
    page.wait_for_selector("text=Quadro de Chamados")
    page.screenshot(path="verification/kanban.png")

    # Click "Novo" button to open modal (ensure we click the one in Kanban header)
    page.click("button:has-text(\"Novo\")")
    page.wait_for_selector("text=Novo Chamado")
    page.screenshot(path="verification/new_ticket_modal.png")

if __name__ == "__main__":
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        try:
            verify_tickets(page)
            print("Verification successful.")
        except Exception as e:
            print(f"Error: {e}")
        finally:
            browser.close()
