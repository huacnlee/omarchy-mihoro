#!/usr/bin/env python3
"""Install the plugin-owned config updater without disturbing unrelated cron jobs."""

import argparse
from pathlib import Path
import re
import shlex
import subprocess
import sys


def interval_from(path):
    try:
        text = path.read_text()
    except OSError:
        return 0
    match = re.search(r"(?m)^\s*auto_update_interval\s*=\s*(\d+)\s*(?:#.*)?$", text)
    return min(24, max(0, int(match.group(1)))) if match else 0


def write_if_changed(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == content:
        return
    temporary = path.with_name("." + path.name + ".tmp")
    temporary.write_text(content)
    temporary.chmod(0o644)
    temporary.replace(path)


def remove_mihoro_update_cron(crontab):
    try:
        listed = subprocess.run([crontab, "-l"], text=True, capture_output=True)
    except FileNotFoundError:
        return
    if listed.returncode != 0:
        return
    kept = []
    pattern = re.compile(r"(?:^|\s)\S*mihoro\s+update(?:\s|$)")
    for line in listed.stdout.splitlines():
        if not pattern.search(line) or line.lstrip().startswith("#"):
            kept.append(line)
    payload = "\n".join(kept) + ("\n" if kept else "")
    updated = subprocess.run([crontab, "-"], input=payload, text=True)
    if updated.returncode != 0:
        raise ValueError("Could not replace mihoro's config update cron entry.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install",))
    parser.add_argument("--mihoro-config", required=True, type=Path)
    parser.add_argument("--config-home", required=True, type=Path)
    parser.add_argument("--python", required=True)
    parser.add_argument("--enhancer", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--rules", required=True)
    parser.add_argument("--subscriptions", required=True)
    parser.add_argument("--mihomo-bin", required=True)
    parser.add_argument("--config-dir", required=True)
    parser.add_argument("--systemctl", default="systemctl")
    parser.add_argument("--crontab", default="crontab")
    args = parser.parse_args()

    interval = interval_from(args.mihoro_config)
    if interval == 0:
        print("disabled")
        return

    command = [args.python, args.enhancer, "update", "--config", args.config,
               "--rules", args.rules, "--subscriptions", args.subscriptions,
               "--mihoro-config", str(args.mihoro_config),
               "--mihomo-bin", args.mihomo_bin, "--config-dir", args.config_dir]
    exec_start = " ".join(shlex.quote(str(part)) for part in command)
    unit_dir = args.config_home / "systemd" / "user"
    service_path = unit_dir / "omarchy-mihoro-update.service"
    timer_path = unit_dir / "omarchy-mihoro-update.timer"
    write_if_changed(service_path, """[Unit]
Description=Update Mihoro subscription with Omarchy local rules
After=network-online.target

[Service]
Type=oneshot
ExecStart=%s
""" % exec_start)
    write_if_changed(timer_path, """[Unit]
Description=Schedule Mihoro subscription updates with Omarchy local rules

[Timer]
OnBootSec=5m
OnUnitActiveSec=%dh
Persistent=true

[Install]
WantedBy=timers.target
""" % interval)

    remove_mihoro_update_cron(args.crontab)
    if subprocess.run([args.systemctl, "--user", "daemon-reload"]).returncode != 0:
        raise ValueError("Could not reload user systemd units.")
    if subprocess.run([args.systemctl, "--user", "enable", "--now",
                       "omarchy-mihoro-update.timer"]).returncode != 0:
        raise ValueError("Could not enable the local-rule update timer.")
    print("installed")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.stderr.write(str(error).strip() + "\n")
        raise SystemExit(1)
