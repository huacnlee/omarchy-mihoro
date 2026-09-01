import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import yaml

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "config_enhancer.py"


def write_executable(path, body):
    path.write_text(body)
    path.chmod(0o755)


def run_enhancer(root, *extra, expect=0):
    command = [
        sys.executable,
        str(SCRIPT),
        "--config", str(root / "config.yaml"),
        "--rules", str(root / "rules.json"),
        "--subscription-id", "sub-a",
        "--mihomo-bin", str(root / "mihomo"),
        "--config-dir", str(root),
        "--systemctl", str(root / "systemctl"),
        *extra,
    ]
    result = subprocess.run(command, text=True, capture_output=True)
    assert result.returncode == expect, result.stderr
    return result


with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    (root / "config.yaml").write_text(yaml.safe_dump({
        "port": 7891,
        "mode": "rule",
        "rules": ["GEOSITE,OLD,DIRECT", "MATCH,PROXY"],
        "proxies": [{"name": "Node", "type": "http", "server": "example.com", "port": 443}],
    }, sort_keys=False))
    (root / "rules.json").write_text(json.dumps({
        "version": 1,
        "subscriptions": {
            "sub-a": {
                "rules": [
                    {"id": "new", "type": "GEOSITE", "match": "CN", "route": "DIRECT"}
                ],
                "applied": [
                    {"id": "old", "type": "GEOSITE", "match": "OLD", "route": "DIRECT"}
                ],
            }
        },
    }))
    write_executable(root / "mihomo", "#!/bin/sh\nexit 0\n")
    write_executable(root / "systemctl", "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$0.log\"\n")

    run_enhancer(root, "apply")
    config = yaml.safe_load((root / "config.yaml").read_text())
    assert config["rules"] == ["GEOSITE,CN,DIRECT", "MATCH,PROXY"]
    saved = json.loads((root / "rules.json").read_text())
    assert saved["subscriptions"]["sub-a"]["applied"][0]["match"] == "CN"
    assert "--user restart mihomo.service" in (root / "systemctl.log").read_text()

    # Re-applying is idempotent and never duplicates the managed prefix.
    run_enhancer(root, "apply")
    config = yaml.safe_load((root / "config.yaml").read_text())
    assert config["rules"].count("GEOSITE,CN,DIRECT") == 1

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    original = {"port": 7891, "mode": "global", "rules": ["MATCH,PROXY"]}
    (root / "config.yaml").write_text(yaml.safe_dump(original, sort_keys=False))
    (root / "rules.json").write_text(json.dumps({
        "version": 1,
        "subscriptions": {"sub-a": {"rules": [
            {"id": "cn", "type": "GEOSITE", "match": "CN", "route": "DIRECT"}
        ], "applied": []}},
    }))
    remote = root / "remote.yaml"
    remote.write_text(yaml.safe_dump({
        "port": 9999,
        "mode": "rule",
        "rules": ["DOMAIN-SUFFIX,google.com,PROXY", "MATCH,DIRECT"],
    }, sort_keys=False))
    write_executable(root / "mihomo", "#!/bin/sh\nexit 0\n")
    write_executable(root / "systemctl", "#!/bin/sh\nexit 0\n")

    run_enhancer(root, "update", "--source", str(remote), "--no-restart")
    config = yaml.safe_load((root / "config.yaml").read_text())
    assert config["port"] == 7891
    assert config["mode"] == "global"
    assert config["rules"] == [
        "GEOSITE,CN,DIRECT", "DOMAIN-SUFFIX,google.com,PROXY", "MATCH,DIRECT"
    ]

    # The just-written mihoro.toml is the URL truth during a subscription
    # switch; subscriptions.json may still be finishing its independent write.
    (root / "mihoro.toml").write_text(f'remote_config_url = "{remote.as_uri()}"\n')
    run_enhancer(root, "update", "--mihoro-config", str(root / "mihoro.toml"),
                 "--no-restart")

    # Base64 subscriptions are decoded before merging.
    encoded = root / "encoded.txt"
    encoded.write_bytes(base64.b64encode(remote.read_bytes()))
    run_enhancer(root, "update", "--source", str(encoded), "--no-restart")

    # A failed mihomo validation leaves the previous working config untouched.
    before = (root / "config.yaml").read_text()
    write_executable(root / "mihomo", "#!/bin/sh\necho invalid >&2\nexit 1\n")
    result = run_enhancer(root, "apply", "--no-restart", expect=1)
    assert "invalid" in result.stderr
    assert (root / "config.yaml").read_text() == before

print("config enhancer tests passed")
