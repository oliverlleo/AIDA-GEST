from playwright.sync_api import Page, expect, sync_playwright
import os

def verify_feature(page: Page):
  # In this environment static html files should be loaded via file:// protocol
  file_path = f"file://{os.path.abspath('index.html')}"
  print(f"Loading {file_path}")
  page.goto(file_path)

  # Wait for alpine to initialize
  page.wait_for_timeout(1000)

  # Find the specific label we changed
  # Let's locate the span/label inside the Scheduling UI div
  locator = page.locator('label.text-gray-500', has_text="Agendamento").first

  # Ensure "(Opcional)" is NOT in this specific label
  text_content = locator.text_content()
  assert "(Opcional)" not in text_content, f"Text content still has (Opcional): {text_content}"
  print(f"Found label: {text_content.strip()}")

  # Force the modal open to take a screenshot
  page.evaluate("document.querySelector('[x-data]')._x_dataStack[0].modals.ticket = true")
  page.evaluate("document.querySelector('[x-data]')._x_dataStack[0].ticketForm.is_outsourced = false")
  page.wait_for_timeout(1000)

  page.screenshot(path="/home/jules/verification/verification.png")
  page.wait_for_timeout(1000)

if __name__ == "__main__":
  os.makedirs("/home/jules/verification/video", exist_ok=True)
  with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    context = browser.new_context(record_video_dir="/home/jules/verification/video")
    page = context.new_page()
    try:
      verify_feature(page)
    finally:
      context.close()
      browser.close()
