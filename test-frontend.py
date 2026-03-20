from playwright.sync_api import sync_playwright
import os

def test_index_page():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        # We don't have a dev server running, so we open the local index.html directly
        filepath = "file://" + os.path.abspath("index.html")
        page = browser.new_page()
        page.goto(filepath)

        # Wait a bit for AlpineJS to initialize
        page.wait_for_timeout(2000)

        # Let's take a screenshot of the main page
        page.screenshot(path="screenshot.png")

        browser.close()

if __name__ == "__main__":
    test_index_page()
