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

All traffic is routed through the interface. No proxy env vars needed — but `netprobe.sh` cannot test foreign reachability for WireGuard. Without a SOCKS5 port, the script skips Layer 3 (GitHub/PyPI) entirely. Test directly instead:

```bash
curl -s -o /dev/null -w "%{http_code}" https://github.com
```

A `200` or `301` means WireGuard is routing correctly. The gateway ping (Layer 2a) in `netprobe.sh` still works and will tell you if the interface is alive.

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

Local network up, proxy running, but foreign endpoints unreachable through it.

1. **Check if it's DPI blocking your protocol.** Make sure your config uses a resistant transport — VLESS+REALITY or VMess+WebSocket+TLS survives DPI far better than plain VMess.

2. **Check if the remote server itself is blocked** (IP blocked, not protocol). Try switching servers or subscription endpoints.

3. **Check if it's a blanket outage.** If GitHub, PyPI, and npm all return TIMEOUT through proxy simultaneously, it's likely a national-level block event, not a local config issue.

4. **Hysteria2 over QUIC may work when TCP-based proxies are throttled.** UDP traffic is harder to rate-limit precisely.

## DPI — making `claude` CLI more reliable

DPI (Deep Packet Inspection) can identify and throttle or block specific TLS connections even when a proxy is running. When `claude` connects to `api.anthropic.com`, the TLS ClientHello contains the SNI (Server Name Indication) in plaintext — DPI can read this even on encrypted connections.

### Protocol choices (strongest to weakest against DPI)

| Protocol | DPI resistance | Notes |
|----------|---------------|-------|
| VLESS + REALITY | Excellent | Mimics real TLS to a legit domain (e.g. microsoft.com). Gold standard. |
| VLESS + Vision + TLS | Very good | XTLS splice mode, minimal overhead |
| Trojan + TLS | Good | Looks like HTTPS traffic |
| VMess + WebSocket + TLS | Good | Works through CDN fronting |
| Hysteria2 (QUIC/UDP) | Good | UDP-based; DPI tools often can't deep-inspect QUIC |
| Plain VMess / Shadowsocks | Poor | Fingerprinted and blocked more easily |

### TCP fragmentation (v2rayN built-in)

v2rayN has a **Fragment** feature that splits the TLS ClientHello into small TCP segments. DPI engines that reassemble packets partially often miss the SNI in a fragmented ClientHello.

Enable in v2rayN: **Settings → Core: Xray → (edit config JSON)** and add to outbound:
```json
"sockopt": {
  "dialerProxy": "fragment",
  "fragment": {
    "packets": "tlshello",
    "length": "100-200",
    "interval": "10-20"
  }
}
```
Or use v2rayN's GUI option under **Settings → Fragment** if your version exposes it.

### Using the HTTP proxy port for `claude`

When `HTTPS_PROXY` is set to an HTTP proxy, `claude` sends a `CONNECT api.anthropic.com:443` request to the local proxy, which then tunnels the TLS through the VPN — so the DPI at the ISP level only sees your VPN protocol, never `api.anthropic.com`. This is the standard behavior and is already correct if you've set `HTTP_PROXY`/`HTTPS_PROXY`.

```bash
# Use the HTTP inbound (v2rayN default: 10809) — equivalent in effect to SOCKS5
export HTTPS_PROXY="http://127.0.0.1:10809"
export HTTP_PROXY="http://127.0.0.1:10809"
claude
```

### Cloudflare WARP as a fallback

WARP uses WireGuard and routes all traffic through Cloudflare's network. It's not a silver bullet against DPI (the WireGuard handshake is identifiable), but Cloudflare's infrastructure often has more routes around blockages than individual proxy servers.

```bash
warp-cli connect
warp-cli status
# No proxy env vars needed — all traffic goes through the WARP interface
claude
```

### ECH (Encrypted Client Hello)

Some recent clients support ECH, which encrypts the SNI. Support requires both the client and the target server. As of 2025, `api.anthropic.com` may not support ECH, but this is worth watching as it evolves.

### Checking service status before debugging proxies

Before spending time on proxy config, verify the issue isn't on Anthropic's side:

```
https://status.claude.ai
```

If there's an ongoing incident, no proxy configuration will help.
