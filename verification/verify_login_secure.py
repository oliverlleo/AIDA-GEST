from playwright.sync_api import sync_playwright, expect
import os

def test_login(page):
    print("Navigating...")
    page.goto("http://localhost:8080")

    # Wait for init
    page.wait_for_timeout(2000)

    # Fill Form
    print("Filling form...")
    page.locator("input[x-model='loginForm.company_code']").fill("6752")
    page.locator("input[x-model='loginForm.username']").fill("testbot_session")
    page.locator("input[x-model='loginForm.password']").fill("123456")

    # Click Login
    print("Clicking Login...")
    page.locator("button").filter(has_text="Entrar").locator("visible=true").click()

    # Wait for Dashboard
    print("Waiting for dashboard...")
    try:
        page.wait_for_selector("text=Visão Geral", timeout=15000)
    except:
        print("Dashboard not found")
        page.screenshot(path="verification/login_fail_secure.png")
        raise

    # Take screenshot of dashboard
    print("Taking screenshot...")
    page.wait_for_timeout(3000)

    page.screenshot(path="verification/dashboard_secure.png")
    print("Screenshot saved.")

if __name__ == "__main__":
    os.makedirs("verification", exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        try:
            test_login(page)
        except Exception as e:
            print(f"Error: {e}")
        finally:
            browser.close()
