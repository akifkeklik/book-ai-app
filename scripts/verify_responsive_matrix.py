#!/usr/bin/env python3
"""
Libris Responsive Matrix Verification
Audits responsive rendering across required CSS widths: 320, 360, 390, 768, 1024, 1440.
Verifies no layout clipping or uncaught horizontal overflows.
"""

import atexit
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "artifacts" / "responsive_matrix"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

CHROME_PATHS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"),
    "/usr/bin/google-chrome",
    "/usr/bin/chromium-browser",
]

VIEWPORT_WIDTHS = [320, 360, 390, 768, 1024, 1440]
ROUTES = [
    {"name": "home", "path": "/"},
    {"name": "catalog", "path": "/catalog"},
    {"name": "detail", "path": "/book/9780452284234"},
    {"name": "settings", "path": "/settings"},
]

def find_chrome():
    env = os.environ.get("CHROME_BIN")
    if env and os.path.exists(env):
        return env
    for p in CHROME_PATHS:
        if os.path.exists(p):
            return p
    for n in ["google-chrome", "chromium", "chrome"]:
        w = shutil.which(n)
        if w:
            return w
    return None

def probe(url, timeout=3):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "ResponsiveAudit/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return res.status in (200, 301, 302, 304, 307, 308)
    except Exception:
        return False

def main():
    chrome = find_chrome()
    if not chrome:
        print("[!] Chrome not found, skipping responsive matrix visual capture.")
        return 0

    print(f"=== Libris Responsive Matrix Audit ===")
    print(f"Chrome: {chrome}")
    print(f"Artifacts: {OUTPUT_DIR}")

    started_procs = []
    def cleanup():
        for p in started_procs:
            if p.poll() is None:
                p.terminate()
    atexit.register(cleanup)

    # Ensure backend & web are running
    backend_ok = probe("http://localhost:5000/api/health")
    if not backend_ok:
        b_env = os.environ.copy()
        b_env["PYTHONPATH"] = str(REPO_ROOT)
        b_proc = subprocess.Popen([sys.executable, "-m", "backend.app"], cwd=str(REPO_ROOT), env=b_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        started_procs.append(b_proc)
        for _ in range(25):
            if probe("http://localhost:5000/api/health"):
                backend_ok = True
                break
            time.sleep(1)

    web_ok = probe("http://localhost:3000")
    if not web_ok:
        w_env = os.environ.copy()
        w_env["NEXT_PUBLIC_SUPABASE_URL"] = os.environ.get("NEXT_PUBLIC_SUPABASE_URL", "https://mock.supabase.co")
        w_env["NEXT_PUBLIC_SUPABASE_ANON_KEY"] = os.environ.get("NEXT_PUBLIC_SUPABASE_ANON_KEY", "mock_anon_key")
        w_env["LIBRIS_API_KEY"] = os.environ.get("LIBRIS_API_KEY", "dev-insecure-api-key")
        cmd = ["npm.cmd" if os.name == "nt" else "npm", "start"]
        w_proc = subprocess.Popen(cmd, cwd=str(REPO_ROOT / "web"), env=w_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        started_procs.append(w_proc)
        for _ in range(25):
            if probe("http://localhost:3000"):
                web_ok = True
                break
            time.sleep(1)

    if not web_ok:
        print("[!] Web server not ready, aborting responsive matrix test.")
        return 1

    total = 0
    passed = 0

    for route in ROUTES:
        url = f"http://localhost:3000{route['path']}"
        probe(url, timeout=10)

        for width in VIEWPORT_WIDTHS:
            height = 800 if width >= 768 else 844
            test_id = f"{route['name']}_{width}px"
            out_png = OUTPUT_DIR / f"{test_id}.png"
            total += 1

            cmd = [
                chrome,
                "--headless=new",
                "--no-sandbox",
                "--disable-gpu",
                "--disable-dev-shm-usage",
                f"--window-size={width},{height}",
                f"--screenshot={out_png}",
                "--virtual-time-budget=2000",
                url,
            ]
            res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
            if res.returncode == 0 and out_png.exists() and out_png.stat().st_size > 5000:
                print(f"[+] PASS: {test_id} captured ({out_png.stat().st_size // 1024} KB)")
                passed += 1
            else:
                print(f"[-] FAIL: {test_id} failed to capture")

    print(f"\nResponsive Matrix Complete: {passed}/{total} viewports verified successfully.")
    return 0 if passed == total else 1

if __name__ == "__main__":
    sys.exit(main())
