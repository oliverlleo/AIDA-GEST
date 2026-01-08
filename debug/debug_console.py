from playwright.sync_api import sync_playwright
import os

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Listen for console logs
        page.on("console", lambda msg: print(f"CONSOLE: {msg.type}: {msg.text}"))
        page.on("pageerror", lambda exc: print(f"PAGE ERROR: {exc}"))

        # Load file
        cwd = os.getcwd()
        page.goto(f"file://{cwd}/index.html")

        # Wait a bit
        try:
            page.wait_for_timeout(3000)
        except:
            pass

        browser.close()

if __name__ == "__main__":
    run()
