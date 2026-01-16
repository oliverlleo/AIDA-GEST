
from playwright.sync_api import sync_playwright
import os
import time

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Navigate to the local server
        page.goto("http://localhost:8080/index.html")

        # Wait a bit for JS to execute
        time.sleep(2)

        # Take a screenshot of the initial load
        os.makedirs("/home/jules/verification", exist_ok=True)
        path = "/home/jules/verification/initial_load.png"
        page.screenshot(path=path)

        print(f"Screenshot saved to {path}")

        # Check title
        print("Page Title:", page.title())

        browser.close()

if __name__ == "__main__":
    run()
