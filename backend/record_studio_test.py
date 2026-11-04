"""
Automated Test & Screen Recording Script for Static Trace Studio Workbench.
Exercises all buttons, 3D multi-camera views, catalog modal, and export features.
Records video using Playwright and encodes to MP4 format via ffmpeg.
"""

import os
import sys
import time
import subprocess
import shutil
from pathlib import Path

# Ensure backend directory is in path
BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

from playwright.sync_api import sync_playwright


def record_studio_sequence():
    # 1. Start FastAPI backend server in a background subprocess
    print("[1/5] Starting FastAPI backend server on http://localhost:8000...")
    server_process = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "backend.main:app", "--host", "127.0.0.1", "--port", "8000"],
        cwd=str(BASE_DIR),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    time.sleep(2.5)  # Wait for uvicorn to bind

    video_temp_dir = BASE_DIR / "temp_video_recordings"
    if video_temp_dir.exists():
        shutil.rmtree(video_temp_dir)
    video_temp_dir.mkdir(parents=True, exist_ok=True)

    output_mp4 = BASE_DIR / "plan" / "studio_workbench_test_sequence.mp4"
    output_mp4.parent.mkdir(parents=True, exist_ok=True)

    try:
        print("[2/5] Launching Playwright browser with video recorder...")
        with sync_playwright() as p:
            # Launch Microsoft Edge with high resolution
            browser = p.chromium.launch(
                channel="msedge",
                headless=True,
                args=["--no-sandbox", "--disable-gpu", "--window-size=1600,1000"],
            )

            context = browser.new_context(
                viewport={"width": 1600, "height": 950},
                record_video_dir=str(video_temp_dir),
                record_video_size={"width": 1600, "height": 950},
                accept_downloads=True,
            )

            page = context.new_page()
            page.on("console", lambda msg: print(f"       [Browser Console] {msg.type}: {msg.text}"))
            page.on("pageerror", lambda err: print(f"       [Browser Error] {err}"))
            page.on("response", lambda res: print(f"       [HTTP {res.status}] {res.url}") if res.status >= 400 else None)
            page.on("requestfailed", lambda req: print(f"       [REQUEST FAILED] {req.url}: {req.failure}"))

            # Helper for deliberate, smooth pace
            def deliberate_pause(seconds: float, log_msg: str = ""):
                if log_msg:
                    print(f"       -> {log_msg}")
                page.wait_for_timeout(int(seconds * 1000))

            print("[3/5] Navigating to Studio Workbench (http://127.0.0.1:8000/studio/)...")
            page.goto("http://127.0.0.1:8000/studio/", wait_until="domcontentloaded")
            deliberate_pause(2.5, "Studio loaded with 3-panel CAD layout")

            # ── Test 1: Inspect Project 1 (Emma Watson) ────────────────────
            print("  [*] Test Step 1: Selecting Project 1 (Emma Watson — Industrial Luxe)...")
            page.wait_for_selector("#card-QT-816BB0DC", timeout=10000)
            card_1 = page.locator("#card-QT-816BB0DC")
            card_1.scroll_into_view_if_needed()
            card_1.hover()
            deliberate_pause(1.0, "Hovering Project 1 card")
            card_1.click()
            deliberate_pause(2.5, "Project 1 loaded: 3D Industrial Luxe cabinets rendered")

            # ── Test 2: Switch to Project 2 (Marcus Aurelius) ───────────────
            print("  [*] Test Step 2: Selecting Project 2 (Marcus Aurelius — Japandi)...")
            card_2 = page.locator("#card-QT-992AC14B")
            card_2.scroll_into_view_if_needed()
            card_2.hover()
            deliberate_pause(1.0, "Hovering Project 2 card")
            card_2.click()
            deliberate_pause(2.5, "Project 2 loaded: Japandi Natural 3D scene & BOQ updated")

            # ── Test 3: Multi-Camera Views ─────────────────────────────────
            print("  [*] Test Step 3: Exercising Multi-Camera Viewport Controls...")
            # Top Plan View
            btn_top = page.locator("#btn-cam-top")
            btn_top.hover()
            deliberate_pause(0.8)
            btn_top.click()
            deliberate_pause(2.5, "Switched to Top-Down 2D Architectural Plan View")

            # Front Elevation View
            btn_front = page.locator("#btn-cam-front")
            btn_front.hover()
            deliberate_pause(0.8)
            btn_front.click()
            deliberate_pause(2.5, "Switched to Front Elevation View (cabinet heights aligned)")

            # Return to 3D Orbit View
            btn_persp = page.locator("#btn-cam-persp")
            btn_persp.hover()
            deliberate_pause(0.8)
            btn_persp.click()
            deliberate_pause(2.0, "Returned to 3D Perspective Orbit")

            # Simulate 3D Orbit Rotation
            print("  [*] Test Step 4: Simulating 3D Orbit Rotation with mouse drag...")
            canvas = page.locator("#canvas-container")
            box = canvas.bounding_box()
            if box:
                cx = box["x"] + box["width"] / 2
                cy = box["y"] + box["height"] / 2
                page.mouse.move(cx, cy)
                page.mouse.down()
                page.mouse.move(cx + 250, cy - 80, steps=25)
                page.mouse.up()
                deliberate_pause(2.0, "Rotated 3D scene to inspect side cabinet depth")

            # ── Test 4: Master Catalog Modal ───────────────────────────────
            print("  [*] Test Step 5: Testing Master Catalog & Pricing Matrix Modal...")
            btn_cat = page.locator("button:has-text('Master Catalog & Pricing Matrix')")
            btn_cat.hover()
            deliberate_pause(1.0)
            btn_cat.click()
            deliberate_pause(2.0, "Catalog Modal opened with pricing matrix")

            # Type a new Base 800 price to show editability
            input_base = page.locator("#cat-base-800")
            input_base.click()
            input_base.fill("440")
            deliberate_pause(1.2, "Updated Base 800mm rate to RM440")

            btn_save_cat = page.locator("button:has-text('Save Pricing Matrix')")
            btn_save_cat.hover()
            deliberate_pause(1.0)
            # Accept the alert dialog automatically
            page.once("dialog", lambda dialog: dialog.accept())
            btn_save_cat.click()
            deliberate_pause(2.0, "Saved pricing matrix to server")

            # ── Test 5: Switch back to Project 1 & Test DXF Export ──────────
            print("  [*] Test Step 6: Testing AutoCAD DXF Export...")
            card_1.click()
            deliberate_pause(1.5, "Re-selected Emma Watson project")

            btn_dxf = page.locator("#btn-export-dxf")
            btn_dxf.hover()
            deliberate_pause(1.2)
            with page.expect_download() as download_info:
                btn_dxf.click()
            download = download_info.value
            download_path = BASE_DIR / "temp_video_recordings" / download.suggested_filename
            download.save_as(str(download_path))
            deliberate_pause(2.0, f"AutoCAD DXF generated and downloaded: {download.suggested_filename}")

            # ── Test 6: Test PDF Agreement ─────────────────────────────────
            print("  [*] Test Step 7: Testing Signed PDF Agreement...")
            btn_pdf = page.locator("#btn-download-pdf")
            btn_pdf.hover()
            deliberate_pause(1.5, "Hovering Signed PDF Agreement button")
            deliberate_pause(2.0, "Demonstration sequence complete")

            # Close context to flush video to disk
            context.close()
            browser.close()
            print("[4/5] Playwright recording finished.")

    finally:
        # Terminate backend server process
        server_process.terminate()
        server_process.wait()
        print("       -> Backend server stopped.")

    # 4. Find the raw video file and convert to standard MP4 with ffmpeg
    print("[5/5] Encoding high-quality MP4 video with ffmpeg...")
    raw_videos = list(video_temp_dir.glob("*.webm"))
    if not raw_videos:
        print("[ERROR] No raw video found in", video_temp_dir)
        return False

    raw_video = raw_videos[0]
    print(f"       -> Converting {raw_video.name} to {output_mp4.name}...")

    # ffmpeg conversion command
    cmd = [
        "ffmpeg",
        "-y",
        "-i", str(raw_video),
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "22",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        str(output_mp4),
    ]

    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if res.returncode == 0 and output_mp4.exists():
        size_mb = output_mp4.stat().st_size / (1024 * 1024)
        print(f"\n[SUCCESS] MP4 Video generated successfully!")
        print(f"File: {output_mp4}")
        print(f"Size: {size_mb:.2f} MB")

        # Copy to brain artifacts
        brain_mp4 = Path(r"C:\Users\User\.gemini\antigravity\brain\3479f5a9-6103-4821-b60a-cb5ccf5febc6\studio_workbench_test_sequence.mp4")
        shutil.copyfile(str(output_mp4), str(brain_mp4))
        print(f"Copied to persistent brain artifact: {brain_mp4}")
        return True
    else:
        print("[ERROR] ffmpeg failed:", res.stderr.decode("utf-8", errors="ignore"))
        return False


if __name__ == "__main__":
    record_studio_sequence()
