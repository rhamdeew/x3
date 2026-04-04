#!/usr/bin/env python3
"""
First-run initialization for 3x-ui panel.
Runs inside the container via: docker exec overseer python3 /scripts/init-panel.py

Reads from environment:
  PANEL_PORT  — panel port (default: 2083)
  PANEL_USER  — login username (default: admin)
  PANEL_PASS  — login password (default: admin)
  PANEL_PATH  — URL base path (default: /get)
"""
import sqlite3
import json
import os
import subprocess
import sys

PORT = os.environ.get("PANEL_PORT", "2083")
USER = os.environ.get("PANEL_USER", "admin")
PASS = os.environ.get("PANEL_PASS", "admin")
PATH = os.environ.get("PANEL_PATH", "/get")
DB   = "/etc/x-ui/x-ui.db"

# Xray config template — controls ONLY routing/outbounds/log.
# Do NOT include api/inbounds/policy/stats — 3x-ui generates those itself.
# Note: blackhole tag must be "blocked" (3x-ui default), not "block".
XRAY_TEMPLATE = {
    "log": {"loglevel": "warning"},
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            # 3x-ui management API — must be first
            {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
            # Block access to private/LAN IPs (SSRF protection)
            {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},
            # Block ads
            {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"},
            # YouTube — direct before any other matching
            {"type": "field", "domain": [
                "youtube.com", "youtubei.googleapis.com", "googlevideo.com",
                "ytimg.com", "youtu.be", "ggpht.com", "gstatic.com"
            ], "outboundTag": "direct"},
            # Russia — direct (gov-ru + all .ru domains)
            {"type": "field", "domain": ["geosite:category-gov-ru", "ru"], "outboundTag": "direct"},
            {"type": "field", "ip": ["geoip:ru"], "outboundTag": "direct"},
            # BitTorrent — direct (not blocked, just bypasses proxy chain)
            {"type": "field", "protocol": ["bittorrent"], "outboundTag": "direct"},
        ]
    },
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {"domainStrategy": "AsIs", "redirect": "", "noises": []}
        },
        {
            "tag": "blocked",
            "protocol": "blackhole",
            "settings": {}
        }
    ]
}

def set_setting(cur, key, value):
    cur.execute("SELECT value FROM settings WHERE key=?", (key,))
    if cur.fetchone():
        cur.execute("UPDATE settings SET value=? WHERE key=?", (value, key))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?,?)", (key, value))

# ── 1. Port / username / password / basepath via x-ui CLI ─────────────────────
print("Applying panel settings via x-ui CLI...")
result = subprocess.run(
    ["/app/x-ui", "setting",
     "-port",        PORT,
     "-username",    USER,
     "-password",    PASS,
     "-webBasePath", PATH],
    capture_output=True, text=True
)
output = (result.stdout + result.stderr).strip()
if output:
    print(" ", output)
if result.returncode != 0:
    print("ERROR: x-ui setting failed", file=sys.stderr)
    sys.exit(1)

# ── 2. Cert + sub + xray template via DB ──────────────────────────────────────
print("Applying DB settings...")
con = sqlite3.connect(DB)
cur = con.cursor()

set_setting(cur, "webCertFile", "/root/cert/cert.pem")
set_setting(cur, "webKeyFile",  "/root/cert/key.pem")
print("  SSL cert configured")

set_setting(cur, "subEnable", "false")
print("  subscription service disabled")

set_setting(cur, "xrayTemplateConfig", json.dumps(XRAY_TEMPLATE))
print("  xray template set (routing: .ru → direct)")

con.commit()
con.close()

print(f"\nDone. Panel will be at https://<host>:{PORT}{PATH}")
