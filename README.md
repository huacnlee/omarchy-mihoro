# Mihoro for Omarchy

An Omarchy bar panel for [mihoro](https://github.com/spencerwooo/mihoro), the
Mihomo CLI client for Linux.

<img width="320" alt="Mihoro for Omarchy" src="https://github.com/user-attachments/assets/f58b161e-389e-43bc-880a-8216c67eb863" />

Use it to monitor your proxy, switch between Rule, Global, and Direct modes,
and keep several subscriptions to switch between.

## Requirements

- Omarchy
- The [mihoro CLI](https://github.com/spencerwooo/mihoro#installation)

## Getting Started

Open the panel and choose **Install Mihoro...**. The panel shows whether the CLI
is installed, reports its detected version, and links to Mihoro's official
installation guide. The guide remains available from the panel menu after
installation.

You can also follow the [upstream installation instructions](https://github.com/spencerwooo/mihoro#installation)
from the panel menu or install it manually.

Initialize it and enter your subscription URL when prompted:

```bash
mihoro init
```

For TUN mode, grant mihomo the required capabilities and restart it:

```bash
sudo setcap cap_net_admin,cap_net_raw,cap_net_bind_service=+ep ~/.local/bin/mihomo
getcap ~/.local/bin/mihomo
systemctl --user restart mihomo.service
```

Install the Omarchy plugin:

```bash
omarchy plugin add https://github.com/huacnlee/omarchy-mihoro.git --enable
```

Remove the Omarchy plugin:

```bash
omarchy plugin remove mihoro.omarchy
```

The panel looks for the mihomo binary where `mihomo_binary_path` in
`~/.config/mihoro.toml` says it is, and falls back to your `PATH`. If you
installed mihomo somewhere else, point that key at it.

## Subscriptions

mihoro holds one subscription at a time — `remote_config_url` in
`~/.config/mihoro.toml` — so the panel keeps the list and hands the selected one
down. Open **Subscriptions...** from the panel menu (or press `s`) to add, name,
edit, and remove them; clicking a row switches to it, which writes its URL into
`mihoro.toml` and runs `mihoro update --config` to fetch it.

Whatever `mihoro.toml` already points at becomes the first entry the first time
the panel runs, so nothing is lost on upgrade, and a URL you later set with
`mihoro init` or by hand is picked up as an entry rather than overwritten.
Removing the last subscription clears `remote_config_url`, returning the panel to
its not-set-up state.

The list lives in `~/.config/omarchy/mihoro-subscriptions.json`, written
`0600` — subscription URLs are bearer credentials, so they are kept out of
`shell.json` and never rendered outside the editor.

From a script:

```bash
omarchy-shell mihoro.omarchy subscriptions     # names and ids, no URLs
omarchy-shell mihoro.omarchy select Backup     # switch by name or id
```

If mihomo does not start, inspect its recent logs:

```bash
journalctl --user -u mihomo.service -n 30 --no-pager
```

## Development

```bash
./install.sh --no-restart
make test
make validate
```

## License

MIT. mihoro and mihomo are distributed separately under their own licenses.
