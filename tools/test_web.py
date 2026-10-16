"""Run the exported Godot solo smoke path under a project-site URL prefix."""

import argparse
import functools
import http.server
import json
from pathlib import Path
import re
import threading
import time

from playwright.sync_api import sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--browser", help="Optional installed Chromium executable")
    args = parser.parse_args()
    directory = args.directory.resolve()
    html = (directory / "index.html").read_text(encoding="utf-8")
    pattern = r"const GODOT_CONFIG = (\{[^\n]+\});"
    match = re.search(pattern, html)
    if match is None:
        raise RuntimeError("Official Godot HTML configuration not found")
    config = json.loads(match[1])
    config["args"] = ["--", "--smoke"]
    smoke_html = directory / "smoke.html"
    smoke_html.write_text(
        html[:match.start(1)] + json.dumps(config) + html[match.end(1):],
        encoding="utf-8",
    )
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(directory.parent))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    messages = []
    errors = []
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path=args.browser, args=[
                "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader",
                "--autoplay-policy=no-user-gesture-required",
            ])
            page = browser.new_page(viewport={"width": 1440, "height": 900})
            page.on("console", lambda message: messages.append(message.text))
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("response", lambda response: errors.append(f"HTTP {response.status}: {response.url}") if response.status >= 400 else None)
            # A nested path catches absolute asset URLs that break repository Pages sites.
            page.goto(f"http://127.0.0.1:{server.server_port}/{directory.name}/smoke.html")
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                if errors or any("SCRIPT ERROR:" in message or message.startswith("ERROR:") for message in messages):
                    raise RuntimeError("Web runtime failed")
                if any("SMOKE_PASS" in message for message in messages):
                    print("WEB_SMOKE_PASS")
                    break
                page.wait_for_timeout(200)
            else:
                raise TimeoutError("Web game did not complete solo smoke test")
            browser.close()
    finally:
        logs = directory.parent / "logs"
        logs.mkdir(exist_ok=True)
        (logs / "web-smoke.log").write_text("\n".join(messages + errors), encoding="utf-8")
        server.shutdown()
        server.server_close()
        smoke_html.unlink()


if __name__ == "__main__":
    main()
