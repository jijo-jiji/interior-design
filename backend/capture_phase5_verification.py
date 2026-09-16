import os
import shutil
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE_DIR = Path(__file__).resolve().parent.parent

def capture():
    os.makedirs("plan/screenshots", exist_ok=True)
    out_path = BASE_DIR / "plan" / "screenshots" / "phase5_factory_dxf_cutlist.png"
    brain_dir = Path(r"C:\Users\User\.gemini\antigravity\brain\3479f5a9-6103-4821-b60a-cb5ccf5febc6")
    brain_path = brain_dir / "phase5_factory_dxf_cutlist.png"

    print("[INFO] Launching Playwright (Edge) for Phase 5 Factory DXF & Cutlist...")
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge", headless=True)
        context = browser.new_context(viewport={"width": 1500, "height": 920})
        page = context.new_page()

        print("[INFO] Navigating to Factory CNC Dispatch & Cutlist viewer...")
        page.goto("http://127.0.0.1:8000/studio/factory.html?id=QT-992AC14B", wait_until="domcontentloaded")
        page.wait_for_selector("#cutlist-body tr:nth-child(5)", timeout=10000)
        time.sleep(1.5)

        # Capture screenshot
        page.screenshot(path=str(out_path))
        print(f"[SUCCESS] Saved Phase 5 screenshot to {out_path}")

        # Copy to brain
        if brain_dir.exists():
            shutil.copyfile(str(out_path), str(brain_path))
            print(f"[SUCCESS] Copied screenshot to brain: {brain_path}")

        browser.close()

if __name__ == "__main__":
    capture()
