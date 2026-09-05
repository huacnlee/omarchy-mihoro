import base64
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

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
    # The subscription server in the user-agent test is on loopback, and
    # urllib honours http_proxy without bypassing 127.0.0.1 — only no_proxy
    # does. On any machine that exports one (this repo's own developers, whose
    # whole subject is a local proxy) the fetch would go to the proxy and the
    # test would fail for a reason that has nothing to do with the code.
    environment = {**os.environ, "no_proxy": "*", "NO_PROXY": "*"}
    result = subprocess.run(command, text=True, capture_output=True, env=environment)
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

    # A non-string value is a mis-edit, not a URL: it is refused with the
    # missing-URL message rather than stringified onto the wire.
    (root / "mihoro.toml").write_text("remote_config_url = true\n")
    result = run_enhancer(root, "update", "--mihoro-config", str(root / "mihoro.toml"),
                          "--no-restart", expect=1)
    assert "The active subscription URL is unavailable." in result.stderr

    # Bytes the file cannot be decoded from report the file, not a codec.
    (root / "mihoro.toml").write_bytes(b'remote_config_url = "http://x/y"\n\xff\xfe\n')
    result = run_enhancer(root, "update", "--mihoro-config", str(root / "mihoro.toml"),
                          "--no-restart", expect=1)
    assert "Could not read mihoro.toml" in result.stderr

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

# Subscription downloads identify with `mihoro_user_agent` from mihoro.toml —
# the same value `mihoro update --config` sends — so a provider that answers
# particular clients sees one client whichever path fetched. Only a real HTTP
# fetch exposes the header, so the remote is served from a local server.
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    remote_config = yaml.safe_dump({
        "port": 9999,
        "mode": "rule",
        "rules": ["MATCH,PROXY"],
        "proxies": [{"name": "Node", "type": "http", "server": "example.com", "port": 443}],
    }, sort_keys=False)
    seen = {}

    class AgentHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            seen["agent"] = self.headers.get("User-Agent", "")
            body = remote_config.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/yaml")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), AgentHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        url = "http://127.0.0.1:%d/remote.yaml" % server.server_port
        write_executable(root / "mihomo", "#!/bin/sh\nexit 0\n")
        write_executable(root / "systemctl", "#!/bin/sh\nexit 0\n")
        (root / "config.yaml").write_text(remote_config)
        (root / "rules.json").write_text(json.dumps({
            "version": 1, "subscriptions": {"sub-a": {"rules": [], "applied": []}},
        }))

        def mihoro_toml(user_agent_line):
            return f'remote_config_url = "{url}"\n' + user_agent_line

        (root / "mihoro.toml").write_text(
            mihoro_toml('mihoro_user_agent = "clash-verge/1.2"\n'))
        run_enhancer(root, "update", "--mihoro-config", str(root / "mihoro.toml"),
                     "--no-restart")
        assert seen["agent"] == "clash-verge/1.2"

        # No key, no empty gap: the downloader falls back to mihoro's own
        # default, so the provider sees the same client either way.
        (root / "mihoro.toml").write_text(mihoro_toml(""))
        run_enhancer(root, "update", "--mihoro-config", str(root / "mihoro.toml"),
                     "--no-restart")
        assert seen["agent"] == "mihoro"

        # The value becomes a request header: a line break must be collapsed
        # rather than smuggle a second one in.
        (root / "mihoro.toml").write_text(
            mihoro_toml('mihoro_user_agent = "clash/1.0\\nx-inject: yes"\n'))
        run_enhancer(root, "update", "--mihoro-config", str(root / "mihoro.toml"),
                     "--no-restart")
        assert seen["agent"] == "clash/1.0 x-inject: yes"

        # Header values are encoded latin-1, so a name written in Chinese would
        # raise UnicodeEncodeError from inside urlopen and fail the whole
        # update with a codec message. mihoro's own fetch refuses the same
        # value, so the default is what keeps the two paths identifying alike.
        (root / "mihoro.toml").write_text(
            mihoro_toml('mihoro_user_agent = "小猫咪/1.0"\n'))
        run_enhancer(root, "update", "--mihoro-config", str(root / "mihoro.toml"),
                     "--no-restart")
        assert seen["agent"] == "mihoro"

        # A value that is not a string is a mis-edit, not a client name.
        (root / "mihoro.toml").write_text(mihoro_toml("mihoro_user_agent = true\n"))
        run_enhancer(root, "update", "--mihoro-config", str(root / "mihoro.toml"),
                     "--no-restart")
        assert seen["agent"] == "mihoro"
    finally:
        server.shutdown()

print("config enhancer tests passed")
