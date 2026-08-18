# Mihoro for Omarchy

An Omarchy bar panel for [mihoro](https://github.com/spencerwooo/mihoro), the
Mihomo CLI client for Linux.

<img width="400" alt="Mihoro panel" src="https://github.com/user-attachments/assets/828033d7-930b-4e66-8a7a-8d968240b8c3" />

Use it to monitor your proxy, switch between Rule, Global, and Direct modes,
and manage your subscription.

## Requirements

- Omarchy
- The [mihoro CLI](https://github.com/spencerwooo/mihoro#installation)

## Getting Started

Open the panel and choose **Install Mihoro**. The panel shows whether the CLI
is installed, reports its detected version, and opens Mihoro's official
installer in an Omarchy terminal. The same installer remains available from
the panel menu after installation.

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
