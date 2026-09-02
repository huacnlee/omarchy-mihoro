#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_id="mihoro.omarchy"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
plugin_home="$config_home/omarchy/plugins"
install_path="$plugin_home/$plugin_id"
# Backups must live outside the plugins directory. Omarchy scans every
# subdirectory of it for a manifest, so a backup left alongside the install is a
# second plugin with the same id — and the shell then loads the stale copy.
backup_home="$config_home/omarchy/plugin-backups"
restart_shell=true

usage() {
  printf 'Usage: %s [--no-restart]\n' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-restart)
      restart_shell=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

command -v omarchy >/dev/null 2>&1 || {
  printf '%s\n' 'omarchy is required to install this plugin.' >&2
  exit 1
}

# mihoro is not a hard requirement for installing the panel: the panel opens
# without it and links to the official instructions. Installing the CLI is the
# user's call, and this script never does it for them.
if ! command -v mihoro >/dev/null 2>&1; then
  printf '%s\n' 'Note: mihoro is not on PATH. The panel will link to the install guide.' >&2
  printf '%s\n' '      https://github.com/spencerwooo/mihoro#installation' >&2
fi

printf '%s\n' 'Validating plugin…'
omarchy plugin validate "$project_dir"

mkdir -p "$plugin_home"
if [[ -L "$install_path" && "$(readlink -f "$install_path")" == "$project_dir" ]]; then
  :
elif [[ -e "$install_path" || -L "$install_path" ]]; then
  mkdir -p "$backup_home"
  backup_path="$backup_home/$plugin_id.bak.$(date +%Y%m%d%H%M%S)"
  mv "$install_path" "$backup_path"
  printf 'Backed up the previous install to %s\n' "$backup_path"
  ln -s "$project_dir" "$install_path"
else
  ln -s "$project_dir" "$install_path"
fi

if $restart_shell; then
  printf '%s\n' 'Restarting Omarchy shell…'
  omarchy restart shell
fi

printf '%s\n' 'Registering Mihoro in the bar…'
omarchy-shell shell rescanPlugins
omarchy plugin enable "$plugin_id"

printf 'Mihoro installed for development at %s\n' "$install_path"
printf '%s\n' 'Open the panel from the bar. QML edits are read through the symlink.'
