#!/usr/bin/env python3
"""
Pre-configure Russia bypass routing in 3x-ui database.
Run after first 'make panel' start (so that x-ui.db is created).

Rules applied:
  - All *.ru domains and geosite:ru → direct
  - All Russian IP ranges (geoip:ru) → direct
  - Everything else → proxy (default)
"""
import sqlite3
import json
import sys
import os

DB_PATH = "/etc/x-ui/x-ui.db"

RU_DOMAIN_RULE = {
    "type": "field",
    "domain": ["ru"],
    "outboundTag": "direct"
}

RU_IP_RULE = {
    "type": "field",
    "ip": ["geoip:ru"],
    "outboundTag": "direct"
}

def main():
    db_path = DB_PATH
    if not os.path.exists(db_path):
        print(f"ERROR: DB not found at {db_path}")
        sys.exit(1)

    con = sqlite3.connect(db_path)
    cur = con.cursor()

    # Fetch current xray template config
    cur.execute("SELECT value FROM settings WHERE key='xrayTemplateConfig'")
    row = cur.fetchone()

    if row and row[0]:
        try:
            config = json.loads(row[0])
        except json.JSONDecodeError:
            config = {}
    else:
        config = {}

    # Build routing section
    routing = config.get("routing", {"domainStrategy": "IPIfNonMatch", "rules": []})
    rules = routing.get("rules", [])

    modified = False

    # Add IP rule if not present
    if not any("geoip:ru" in str(r.get("ip", [])) for r in rules):
        rules.insert(0, RU_IP_RULE)
        modified = True
        print("Added geoip:ru → direct rule")

    # Add domain rule if not present
    if not any("geosite:ru" in str(r.get("domain", [])) for r in rules):
        rules.insert(0, RU_DOMAIN_RULE)
        modified = True
        print("Added geosite:ru → direct rule")

    if not modified:
        print("Routing rules already configured. Nothing to do.")
        con.close()
        return

    routing["rules"] = rules
    if "domainStrategy" not in routing:
        routing["domainStrategy"] = "IPIfNonMatch"
    config["routing"] = routing

    config_json = json.dumps(config)

    if row:
        cur.execute("UPDATE settings SET value=? WHERE key='xrayTemplateConfig'", (config_json,))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (config_json,))

    con.commit()
    con.close()

    print("Done.")

if __name__ == "__main__":
    main()
