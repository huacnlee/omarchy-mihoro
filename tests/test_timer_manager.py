from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "timer_manager.py"


with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    config_home = root / "config"
    bin_dir = root / "bin"
    bin_dir.mkdir()
    cron_state = root / "crontab"
    cron_state.write_text("15 2 * * * backup\n0 */12 * * * /home/u/.local/bin/mihoro update\n")
    systemctl_log = root / "systemctl.log"

    systemctl = bin_dir / "systemctl"
    systemctl.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> {systemctl_log}\n")
    systemctl.chmod(0o755)
    crontab = bin_dir / "crontab"
    crontab.write_text(f'''#!/bin/sh
if [ "$1" = "-l" ]; then cat {cron_state}; exit 0; fi
if [ "$1" = "-" ]; then cat > {cron_state}; exit 0; fi
exit 1
''')
    crontab.chmod(0o755)

    mihoro_toml = root / "mihoro.toml"
    mihoro_toml.write_text("auto_update_interval = 6\n")
    command = [
        sys.executable, str(SCRIPT), "install",
        "--mihoro-config", str(mihoro_toml),
        "--config-home", str(config_home),
        "--python", sys.executable,
        "--enhancer", str(ROOT / "scripts" / "config_enhancer.py"),
        "--config", str(root / "config.yaml"),
        "--rules", str(root / "rules.json"),
        "--subscriptions", str(root / "subscriptions.json"),
        "--mihomo-bin", str(root / "mihomo"),
        "--config-dir", str(root),
        "--systemctl", str(systemctl),
        "--crontab", str(crontab),
    ]
    result = subprocess.run(command, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr

    timer = config_home / "systemd/user/omarchy-mihoro-update.timer"
    service = config_home / "systemd/user/omarchy-mihoro-update.service"
    assert "OnUnitActiveSec=6h" in timer.read_text()
    assert "config_enhancer.py update" in service.read_text()
    assert "--subscription-id" not in service.read_text()
    assert cron_state.read_text() == "15 2 * * * backup\n"
    log = systemctl_log.read_text()
    assert "--user daemon-reload" in log
    assert "--user enable --now omarchy-mihoro-update.timer" in log

    missing_crontab = command[:-1] + [str(bin_dir / "missing-crontab")]
    result = subprocess.run(missing_crontab, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr

print("timer manager tests passed")
