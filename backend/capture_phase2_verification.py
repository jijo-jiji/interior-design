"""
Verification script for Phase 2:
Captures visual evidence of the L-Shape Multi-Wall Rail and 3D architectural realism
(return wall, contemporary bar handles, recessed toe-kick baseboards).
"""

import os
import sys
import time
import subprocess
import shutil
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

def capture_phase2():
    print("[1/3] Starting backend server...")
    server = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "backend.main:app", "--host", "127.0.0.1", "--port", "8000"],
        cwd=str(BASE_DIR),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(2.0)

    try:
        print("[2/3] Launching Playwright to capture Studio Hub with Phase 2 L-Shape room...")
        with sync_playwright() as p:
            browser = p.chromium.launch(channel="msedge", headless=True)
            context = browser.new_context(viewport={"width": 1600, "height": 950})
            page = context.new_page()

            page.goto("http://127.0.0.1:8000/studio/", wait_until="domcontentloaded")
            page.wait_for_selector("#card-QT-992AC14B", timeout=10000)
            page.wait_for_timeout(1000)

            # Click Marcus Aurelius (L-Shape project)
            card = page.locator("#card-QT-992AC14B")
            card.click()
            page.wait_for_timeout(2000)

            screenshot_path = BASE_DIR / "plan" / "screenshots" / "phase2_lshape_room_realism.png"
            page.screenshot(path=str(screenshot_path), full_page=False)
            print(f"[SUCCESS] Screenshot saved: {screenshot_path}")

            # Copy to brain artifacts
            brain_dest = Path(r"C:\Users\User\.gemini\antigravity\brain\3479f5a9-6103-4821-b60a-cb5ccf5febc6\phase2_lshape_room_realism.png")
            shutil.copyfile(str(screenshot_path), str(brain_dest))
            print(f"[COPIED] Brain artifact: {brain_dest}")

            browser.close()
    finally:
        server.terminate()
        server.wait()

if __name__ == "__main__":
    capture_phase2()
