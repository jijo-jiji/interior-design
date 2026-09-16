import os
import shutil
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE_DIR = Path(__file__).resolve().parent.parent

def capture():
    os.makedirs("plan/screenshots", exist_ok=True)
    out_path = BASE_DIR / "plan" / "screenshots" / "phase3_interactive_studio.png"
    brain_dir = Path(r"C:\Users\User\.gemini\antigravity\brain\3479f5a9-6103-4821-b60a-cb5ccf5febc6")
    brain_path = brain_dir / "phase3_interactive_studio.png"

    print("[INFO] Launching Playwright (Edge) for Phase 3 Interactive Studio...")
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge", headless=True)
        context = browser.new_context(viewport={"width": 1600, "height": 950})
        page = context.new_page()

        print("[INFO] Navigating to Studio Workbench with Marcus Aurelius project...")
        page.goto("http://127.0.0.1:8000/studio/?id=QT-992AC14B", wait_until="domcontentloaded")
        page.wait_for_selector("#card-QT-992AC14B", timeout=10000)
        page.wait_for_timeout(1500)

        # Select Marcus Aurelius
        card = page.locator("#card-QT-992AC14B")
        card.click()
        page.wait_for_timeout(1000)

        # Click + Base 600 button to add a module
        print("[INFO] Adding + Base 600 module...")
        add_btn = page.locator("button:has-text('+ Base 600')")
        add_btn.click()
        page.wait_for_timeout(1000)

        # Move selected cabinet along rail
        print("[INFO] Moving selected cabinet...")
        move_btn = page.locator("button:has-text('→ 100mm')")
        if move_btn.is_visible():
            move_btn.click()
            page.wait_for_timeout(500)

        # Click Save Studio Revisions & Lock BOQ
        print("[INFO] Saving studio revisions...")
        save_btn = page.locator("#btn-save-revisions")
        save_btn.click()
        page.wait_for_timeout(1200)

        # Take screenshot of the interactive workbench
        page.screenshot(path=str(out_path))
        print(f"[SUCCESS] Saved screenshot to {out_path}")

        # Copy to brain
        if brain_dir.exists():
            shutil.copyfile(str(out_path), str(brain_path))
            print(f"[SUCCESS] Copied screenshot to brain: {brain_path}")

        browser.close()

if __name__ == "__main__":
    capture()
