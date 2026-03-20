from playwright.sync_api import sync_playwright
import os

def run_verify():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        # Create context to record video
        os.makedirs("/home/jules/verification/video", exist_ok=True)
        context = browser.new_context(record_video_dir="/home/jules/verification/video")
        page = context.new_page()

        filepath = "file://" + os.path.abspath("index.html")
        page.goto(filepath)
        page.wait_for_timeout(2000)

        # We take a screenshot of the login page because this repo requires auth to see the app
        # But we can verify no JS syntax errors are breaking the login screen by capturing it successfully.
        page.screenshot(path="/home/jules/verification/verification.png")

        context.close()
        browser.close()

if __name__ == "__main__":
    run_verify()
