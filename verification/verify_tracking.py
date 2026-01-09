
from playwright.sync_api import sync_playwright

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        import os
        cwd = os.getcwd()

        # 1. Verify "Acompanhar" Page exists (Error State)
        page.goto(f"file://{cwd}/acompanhar.html")
        page.get_by_text("Chamado não encontrado").wait_for()
        page.screenshot(path="verification/acompanhar_error.png")
        print("Verified Error State")

        # 2. Verify "Configurações" in Dashboard
        page.goto(f"file://{cwd}/index.html")

        # Mock Admin Session
        page.evaluate("""
            localStorage.setItem("techassist_employee", JSON.stringify({
                id: "test-admin",
                name: "Admin User",
                username: "admin",
                roles: ["admin"],
                workspace_id: "test-ws"
            }));
        """)
        page.reload()

        # Click "Configurações" (Sidebar) - Use role link
        page.get_by_role("link", name="Configurações").click()

        # Verify Settings Input exists
        page.get_by_text("WhatsApp da Empresa").wait_for()
        page.screenshot(path="verification/settings_page.png")
        print("Verified Settings Page")

        # 3. Verify Share Modal Logic
        # Manually trigger viewTicketDetails via Alpine
        page.evaluate("""
            // Alpine stores data on the element
            document.querySelector("[x-data]")._x_dataStack[0].viewTicketDetails({
                id: "test-uuid-123",
                status: "Aberto",
                client_name: "Test Client",
                os_number: "1234"
            });
        """)

        # Verify Share Button exists in modal
        share_btn = page.get_by_role("button", name="Compartilhar")
        share_btn.wait_for()
        share_btn.click()

        # Verify Share Modal appears
        page.get_by_text("Compartilhar Acompanhamento").wait_for()

        # Verify Link format
        # Use more specific locator for the link span inside the modal
        # Modal is likely last in DOM or z-indexed.
        # Use text content matching URL pattern if possible, or relative to button
        # The modal has text "Compartilhar Acompanhamento"

        modal = page.locator("div", has_text="Compartilhar Acompanhamento").last
        link_text = modal.locator("span.font-mono").text_content()

        if "acompanhar.html?id=test-uuid-123" in link_text:
            print("Link format correct")
        else:
            print(f"Link format incorrect: {link_text}")

        page.screenshot(path="verification/share_modal.png")
        print("Verified Share Modal")

        browser.close()

if __name__ == "__main__":
    run()
