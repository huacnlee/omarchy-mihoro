#!/usr/bin/env python3
"""Apply per-subscription local rules without exposing subscription URLs in argv."""

import argparse
import base64
import binascii
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib
import urllib.request

try:
    import yaml
except ImportError:
    sys.stderr.write("Python PyYAML is required to manage local Mihoro rules.\n")
    raise SystemExit(2)


MANAGED_KEYS = (
    "port", "socks-port", "mixed-port", "redir-port", "allow-lan",
    "bind-address", "mode", "log-level", "ipv6", "external-controller",
    "external-ui", "secret", "geodata-mode", "geo-auto-update",
    "geo-update-interval", "geox-url",
)


def load_yaml_bytes(raw):
    try:
        value = yaml.safe_load(raw.decode("utf-8"))
    except (UnicodeDecodeError, yaml.YAMLError):
        value = None
    if isinstance(value, dict):
        return value
    try:
        decoded = base64.b64decode(b"".join(raw.split()), validate=True)
        value = yaml.safe_load(decoded.decode("utf-8"))
    except (binascii.Error, UnicodeDecodeError, yaml.YAMLError):
        value = None
    if not isinstance(value, dict):
        raise ValueError("The subscription did not contain a mihomo YAML configuration.")
    return value


def load_json(path, fallback):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else fallback
    except (OSError, json.JSONDecodeError):
        return fallback


def compile_rule(rule):
    return ",".join((str(rule.get("type", "")), str(rule.get("match", "")),
                     str(rule.get("route", ""))))


def rule_entry(store, subscription_id):
    subscriptions = store.setdefault("subscriptions", {})
    entry = subscriptions.setdefault(subscription_id, {"rules": [], "applied": []})
    if isinstance(entry, list):
        entry = {"rules": entry, "applied": []}
        subscriptions[subscription_id] = entry
    entry.setdefault("rules", [])
    entry.setdefault("applied", [])
    return entry


def strip_applied(rules, applied):
    compiled = [compile_rule(rule) for rule in applied]
    if compiled and rules[:len(compiled)] == compiled:
        return rules[len(compiled):]
    return rules


def read_subscription_url(path, subscription_id):
    store = load_json(path, {})
    for entry in store.get("items", []):
        if str(entry.get("id", "")) == subscription_id:
            url = str(entry.get("url", "")).strip()
            if url:
                return url
    raise ValueError("The active subscription URL is unavailable.")


def load_mihoro_config(path):
    # The file itself is load-bearing — it is where the update's URL lives —
    # so a broken one fails the update. Individual keys are settled leniently
    # by their readers below.
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        raise ValueError("Could not read mihoro.toml: %s" % error) from error


def read_mihoro_url(mihoro_config):
    # A non-string value is a mis-edit, not a URL: like the user agent below,
    # it is refused rather than stringified onto the wire.
    value = mihoro_config.get("remote_config_url", "")
    if not isinstance(value, str) or not value.strip():
        raise ValueError("The active subscription URL is unavailable.")
    return value.strip()


# The same client name `mihoro update --config` sends, so the two update paths
# identify identically to the provider. Falls back to mihoro's own default when
# the key is absent, empty, or otherwise unusable — the user agent is cosmetic
# and never worth failing an update over.
DEFAULT_USER_AGENT = "mihoro"


def read_user_agent(mihoro_config):
    value = mihoro_config.get("mihoro_user_agent", "")
    # A non-string value is a mis-edit, not a client name: mihoro's own
    # deserializer refuses it outright rather than stringifying it, and
    # `str(True)` would put the Python spelling of a bool on the wire.
    if not isinstance(value, str):
        return DEFAULT_USER_AGENT
    # The value becomes a request header: a hand-edited file must not smuggle
    # extra ones in on a line break.
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", value).strip()
    if not text:
        return DEFAULT_USER_AGENT
    # http.client encodes header values as latin-1, so anything outside it —
    # a name written in Chinese, say — raises UnicodeEncodeError from inside
    # urlopen and fails the whole update with a codec message. mihoro's own
    # fetch would refuse the same value, so falling back keeps the two paths
    # identifying alike instead of one of them breaking.
    try:
        text.encode("latin-1")
    except UnicodeEncodeError:
        return DEFAULT_USER_AGENT
    return text


def download(url, user_agent):
    request = urllib.request.Request(url, headers={"User-Agent": user_agent})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def atomic_write(path, payload, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".omarchy-mihoro-", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as output:
            output.write(payload)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("apply", "update"))
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--rules", required=True, type=Path)
    parser.add_argument("--subscriptions", type=Path)
    parser.add_argument("--mihoro-config", type=Path)
    parser.add_argument("--subscription-id")
    parser.add_argument("--mihomo-bin", required=True)
    parser.add_argument("--config-dir", required=True, type=Path)
    parser.add_argument("--systemctl", default="systemctl")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--no-restart", action="store_true")
    args = parser.parse_args()

    if not args.subscription_id:
        if not args.subscriptions:
            raise ValueError("The subscription store path is required.")
        subscription_store = load_json(args.subscriptions, {})
        args.subscription_id = str(subscription_store.get("activeId", ""))
        if not args.subscription_id:
            raise ValueError("There is no active subscription.")

    current_raw = args.config.read_bytes()
    current = load_yaml_bytes(current_raw)
    store = load_json(args.rules, {"version": 1, "subscriptions": {}})
    entry = rule_entry(store, args.subscription_id)

    if args.action == "update":
        if args.source:
            incoming_raw = args.source.read_bytes()
        else:
            if args.mihoro_config:
                mihoro_config = load_mihoro_config(args.mihoro_config)
                url = read_mihoro_url(mihoro_config)
                user_agent = read_user_agent(mihoro_config)
            elif args.subscriptions:
                url = read_subscription_url(args.subscriptions, args.subscription_id)
                user_agent = DEFAULT_USER_AGENT
            else:
                raise ValueError("mihoro.toml is required for an update.")
            incoming_raw = download(url, user_agent)
        candidate = load_yaml_bytes(incoming_raw)
        for key in MANAGED_KEYS:
            if key in current:
                candidate[key] = current[key]
            else:
                candidate.pop(key, None)
    else:
        candidate = current

    original_rules = candidate.get("rules")
    if original_rules is None:
        original_rules = []
    if not isinstance(original_rules, list) or not all(isinstance(rule, str) for rule in original_rules):
        raise ValueError("The subscription's rules must be a list of strings.")
    remaining = strip_applied(original_rules, entry.get("applied", []))
    desired = entry.get("rules", [])
    candidate["rules"] = [compile_rule(rule) for rule in desired] + remaining
    rendered = yaml.safe_dump(candidate, sort_keys=False, allow_unicode=True).encode("utf-8")

    args.config.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=".omarchy-mihoro-candidate-",
                                           suffix=".yaml", dir=args.config.parent)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        temporary.write_bytes(rendered)
        validation = subprocess.run(
            [args.mihomo_bin, "-t", "-d", str(args.config_dir), "-f", str(temporary)],
            text=True, capture_output=True,
        )
        if validation.returncode != 0:
            message = (validation.stderr or validation.stdout or "mihomo rejected the configuration.").strip()
            raise ValueError(message)
    finally:
        temporary.unlink(missing_ok=True)

    entry["applied"] = json.loads(json.dumps(desired))
    store_payload = (json.dumps(store, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    config_mode = args.config.stat().st_mode & 0o777
    changed = rendered != current_raw
    if changed:
        atomic_write(args.config, rendered, config_mode)
    atomic_write(args.rules, store_payload, 0o600)

    if changed and not args.no_restart:
        restart = subprocess.run([args.systemctl, "--user", "restart", "mihomo.service"])
        if restart.returncode != 0:
            raise ValueError("The configuration was applied, but mihomo.service could not restart.")
    print("updated" if changed else "unchanged")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        sys.stderr.write(str(error).strip() + "\n")
        raise SystemExit(1)
