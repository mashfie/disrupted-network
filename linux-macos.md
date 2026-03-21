# Linux & macOS — Platform Notes

Supplement to `SKILL.md`. Platform-specific commands for proxy detection, verification, and system-wide proxy configuration.

## Checking if a proxy port is listening

### Linux
```bash
ss -tlnp | grep :10808
# or
netstat -tlnp | grep :10808
# or (used by scripts)
nc -z -w 2 127.0.0.1 10808 && echo "UP" || echo "DOWN"
```

### macOS
```bash
lsof -i :10808 -sTCP:LISTEN
# or
nc -z -w 2 127.0.0.1 10808 && echo "UP" || echo "DOWN"
```

## Setting proxy environment variables

These apply to the current terminal session. Add to `~/.bashrc` / `~/.zshrc` for persistence.

```bash
# Use socks5h:// — the 'h' makes the proxy resolve DNS, not the client.
# This is critical in Iran where DNS is poisoned.
export https_proxy="socks5h://127.0.0.1:10808"
export http_proxy="socks5h://127.0.0.1:10808"
export all_proxy="socks5h://127.0.0.1:10808"
export no_proxy="localhost,127.0.0.1"
```

To unset:
```bash
unset https_proxy http_proxy all_proxy
```

## Tool-specific notes

### V2Ray / Xray

Most common in Iran. Runs a local SOCKS5 proxy (default 10808) and HTTP proxy (default 10809).

```bash
# Config locations
~/.config/v2ray/config.json
/usr/local/etc/v2ray/config.json     # Linux package install
/usr/local/etc/xray/config.json      # Xray

# Start (Linux systemd)
systemctl start v2ray
systemctl status v2ray

# Start manually
v2ray run -config ~/.config/v2ray/config.json

# macOS (homebrew)
brew services start v2ray
```

### Psiphon

```bash
# Linux: download AppImage from psiphon3.com
chmod +x Psiphon3.AppImage
./Psiphon3.AppImage
# SOCKS5 on 1080, HTTP on 8080 by default

# macOS: .dmg installer available
```

### Cloudflare WARP

```bash
# Linux
warp-cli connect
warp-cli status
# Creates warp0 or CloudflareWARP network interface, or SOCKS5 on 40000

# macOS
/Applications/Cloudflare\ WARP.app/Contents/Resources/warp-cli connect
# Or use the system tray app
```

Verify interface (Linux):
```bash
ip link show warp0
ip addr show warp0
```

Verify interface (macOS):
```bash
ifconfig | grep -A4 CloudflareWARP
networksetup -listallnetworkservices
```

### WireGuard

WireGuard creates a network interface — there is no SOCKS5 port to probe.

```bash
# Linux
wg show                     # shows active tunnels
ip link show wg0
sudo wg-quick up wg0        # bring up tunnel

# macOS
wg show
# Or use the WireGuard app from the App Store
```

All traffic is routed through the interface. No proxy env vars needed — but `netprobe.sh` cannot detect WireGuard this way. Run the probe without a port argument and check if GitHub/PyPI respond with 200.

### Sing-box

```bash
# Typically SOCKS5 on 2080, HTTP on 2081 (configurable)
sing-box run -c config.json

# Check config for actual ports:
grep -i "socks\|http\|listen" config.json
```

### Hysteria2 / TUIC

```bash
# Typically SOCKS5 on 1080 (configurable)
hysteria2 client -c config.yaml

# Check config:
grep -i "socks\|listen\|port" config.yaml
```

Hysteria2 uses QUIC (UDP), which performs well under packet loss — useful during partial outages.

### Shadowsocks

```bash
# SOCKS5 on 1080 (configurable)
ss-local -c config.json
# or via shadowsocks-libev:
ss-local -s SERVER -p PORT -l 1080 -k PASSWORD -m METHOD
```

## macOS system-wide proxy (alternative to env vars)

```bash
# Set SOCKS5 proxy for Wi-Fi
networksetup -setsocksfirewallproxy Wi-Fi 127.0.0.1 10808
networksetup -setsocksfirewallproxystate Wi-Fi on

# Verify
networksetup -getsocksfirewallproxy Wi-Fi

# Disable
networksetup -setsocksfirewallproxystate Wi-Fi off
```

Note: system-wide proxy settings affect GUI apps and browsers but not all terminal tools — `curl` and `pip` respect env vars more reliably.

## Dependencies for the scripts

| Tool | Linux | macOS |
|------|-------|-------|
| `nc` (netcat) | `apt install netcat-openbsd` | Built-in (BSD netcat) |
| `curl` | `apt install curl` | Built-in or `brew install curl` |
| `bash 4+` | Default on most distros | `brew install bash` (macOS ships bash 3.x) |

The scripts use `nc -z -w N` (BSD-compatible syntax) and `curl -m N` (no GNU `timeout` needed).

## Diagnosing PROXY_DEGRADED

When the proxy is up but traffic is blocked:

1. **Check if it's DPI blocking your protocol.** V2Ray/Xray uses traffic obfuscation — make sure your config uses a working transport (VLESS+Reality or VMess+WebSocket+TLS tends to survive DPI better than plain VMess).

2. **Check if the proxy server itself is unreachable** (foreign server blocked by IP). Try switching servers/subscriptions.

3. **Check if it's a temporary outage** (elections, protests). Iran's national outages are complete and sudden. If GitHub returns TIMEOUT through proxy, it's likely the server, not DPI.

4. **Hysteria2 over QUIC may work when TCP-based proxies don't.** UDP is harder to DPI.
