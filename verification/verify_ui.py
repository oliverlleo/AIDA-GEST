
from playwright.sync_api import sync_playwright
import time

def verify_ui():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto("http://localhost:8080/index.html")

        # Give it a moment to load Alpine
        time.sleep(3)

        # Helper to set alpine data
        def set_alpine_data(key, value):
            js = f"document.querySelector('[x-data]')._x_dataStack[0].{key} = {value}"
            page.evaluate(js)

        # 1. Verify Force Change Password Modal
        print("Verifying Force Change Password Modal...")
        set_alpine_data("modals.forceChangePassword", "true")
        time.sleep(1)
        page.screenshot(path="verification/force_change_modal.png")
        set_alpine_data("modals.forceChangePassword", "false")

        # 2. Verify Reset Password Modal
        print("Verifying Reset Password Modal...")
        set_alpine_data("modals.resetPassword", "true")
        time.sleep(1)
        page.screenshot(path="verification/reset_password_modal.png")
        set_alpine_data("modals.resetPassword", "false")

        # 3. Verify Edit Employee Modal (Reset Button)
        print("Verifying Edit Employee Modal...")
        # Mock an employee object so the form doesn't crash if it tries to read props
        # We need to set individual properties because assigning a full object to employeeForm via dot notation might break reactivity or need pure JS obj
        page.evaluate("document.querySelector('[x-data]')._x_dataStack[0].employeeForm.id = '123'")
        page.evaluate("document.querySelector('[x-data]')._x_dataStack[0].employeeForm.name = 'Test User'")

        set_alpine_data("modals.editEmployee", "true")
        time.sleep(1)
        page.screenshot(path="verification/edit_employee_modal.png")

        browser.close()

if __name__ == "__main__":
    try:
        verify_ui()
        print("Verification scripts ran successfully.")
    except Exception as e:
        print(f"Error: {e}")
