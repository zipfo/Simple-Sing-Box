<div align="center">
    <img src="https://github.com/user-attachments/assets/1b2ec02b-6bf6-4c62-b8e3-bfba4aaafd93" alt="SSB Logo" width="325" height="auto">
    <h1>SIMPLE SING-BOX</h1>
    <a href="README.md">Русский</a> | English<br><br>
</div>

Simple Sing-Box deploys a hardened proxy server powered by [Sing-Box](https://sing-box.sagernet.org) behind an [NGINX](https://nginx.org/en/) or [HAProxy](https://www.haproxy.org) TLS front-end. Traffic is carried over **Trojan** and **VLESS** protocols, while the reverse proxy serves a decoy website on port 443 — making the proxy completely invisible to external probes. Installation, user management, WARP integration, and proxy chaining are handled through a single interactive menu.

---

## ✨ Key Features

<table>
<tr><td><b>Core</b></td>
<td>

- Sing-Box server config for **v1.12.0+**; client configs for **v1.11.0 – 1.13.X**
- Choice of **NGINX** (WebSocket / HTTPUpgrade path-based) or **HAProxy** (Lua password-based, FPPweb3)
- TLS certificates with automatic renewal
- Multiplexing — solves TLS-in-TLS; BBR congestion control enabled

</td></tr>
<tr><td><b>WARP</b></td>
<td>

- WARP via [usque](https://github.com/Diniboy1123/usque) — MASQUE HTTP/2 over TCP
- Automatic endpoint selection by [warpscout](https://github.com/vernette/warpscout)
- Dedicated management submenu: status, re-scan, test, legacy cleanup

</td></tr>
<tr><td><b>Routing</b></td>
<td>

- Russian routing rule sets (GeoIP-RU, gov-RU, ads, ru-blocked)
- Per-user routing modes: Full WARP / Direct / Chain / split by domain group
- Custom Cloudflare IP for client connections

</td></tr>
<tr><td><b>Networking</b></td>
<td>

- Proxy chains of two or more servers (endpoint + intermediate roles)
- Outbound nodes via proxy link, local tunnel interface, or manual SOCKS5 / HTTP
- Per-user outbound assignment

</td></tr>
<tr><td><b>Management</b></td>
<td>

- Interactive user list with profile actions (rename, TUN stack, routing, delete)
- Subscription distribution page ([example](https://zipfo.github.io/Simple-Sing-Box/sub.html#en))
- Optional security hardening: SSH, UFW, unattended-upgrades
- Full uninstall with optional config retention

</td></tr>
</table>

---

## 🏗️ Architecture

Two deployment options — choose during installation:

<details open>
<summary><b>NGINX — path-based routing</b></summary>
<br>

All requests arrive at NGINX on port 443. Only requests carrying the correct WebSocket or HTTPUpgrade path are forwarded to Sing-Box; everything else is served the decoy website.

![nginx-en](https://github.com/user-attachments/assets/8b832294-f14f-4c8b-876e-30b1d160fd1e)

</details>

<details>
<summary><b>HAProxy — Lua password-based routing (FPPweb3 method)</b></summary>
<br>

All requests arrive at HAProxy on port 443. A Lua script reads the Trojan password from the first 56 bytes; only correct passwords are forwarded to Sing-Box over TCP transport.

![haproxy-en](https://github.com/user-attachments/assets/a9753846-4f40-414d-b4eb-4c37b4e9de14)

</details>

Both methods make it **impossible to detect Sing-Box from the outside**, significantly improving security.

---

## 📋 System Requirements

> [!IMPORTANT]
> **OS:** Debian 11 / 12 / 13 or Ubuntu 22.04 / 24.04
> **Hardware:** 1 CPU core · 512 MB RAM · 5 GB disk
> **Network:** Public IPv4 · Own domain or subdomain ([How to set it up?](cf-settings-en.md))
> **Ports:** 443 and SSH must be open
>
> Run as **root** on a freshly installed system. Update packages and reboot before running the installer.

> [!NOTE]
> Includes routing rules for Russia. This project is created for educational and demonstration purposes. Please ensure your actions comply with applicable laws before using it.

---

## 🚀 Quick Start — Server Installation

```bash
bash <(curl -Ls https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Scripts/install-server.sh); source /etc/bash.bashrc
```

Follow the interactive prompts:

![pic-1-en](https://github.com/user-attachments/assets/b2f3dc29-bf49-48e9-ab82-170a6b8ffa09)

> [!CAUTION]
> Passwords, UUIDs, paths and other data in the screenshot above are **examples only**. Do not reuse them on your server.

When finished the installer displays your client config links and subscription page URL — **save them**.

---

## ⚙️ Settings Menu — `ssb`

After installation, open the management menu at any time:

```bash
ssb
```

![pic-2-en](https://github.com/user-attachments/assets/58ea4e4c-342a-4a8b-a18b-e4b5b987c50b)

<details>
<summary><b>Full menu reference (options 0 – 20)</b></summary>

| # | Action |
|--:|--------|
| 0 | Exit |
| 1 | User Management (interactive user list & profile) |
| 2 | Add user |
| 3 | Outbound Management |
| 4 | Sync client configs |
| 5 | Custom Cloudflare IP |
| 6 | WARP domains management |
| 7 | Server connection chain |
| 8 | Auto-update rule sets |
| 9 | WARP Management (status / re-scan / test / purge) |
| 10 | Routing rule sets (Antizapret / Ru-blocked) |
| 11 | Domain & path configuration |
| 12 | Firewall settings |
| 13 | Change domain |
| 14 | Change paths |
| 15 | Disable IPv6 |
| 16 | Enable IPv6 |
| 17 | Show current paths |
| 18 | Update SSB |
| 19 | Blacklist management |
| 20 | Uninstall |

</details>

---

## 👥 User Management

Option **1** opens an interactive user list showing every registered user with their:

- Numbered index
- Active TUN stack (`system` / `gvisor` / `mixed`)
- Assigned outbound node
- Current routing mode

Selecting a user opens the **profile submenu**:

| # | Action | Description |
|--:|--------|-------------|
| 1 | Connection details | Display config links and QR codes |
| 2 | Select outbound node | Assign exit via `direct`, an external node, or a tunnel interface |
| 3 | Select routing mode | Per-user routing template (see [Routing Modes](#-routing-modes)) |
| 4 | Rename user | Change the display name |
| 5 | Change TUN stack | Switch between `system`, `gvisor`, or `mixed` |
| 6 | Delete user | Remove credentials, routing rules, and client files (with confirmation) |

> [!TIP]
> If Sing-Box on a device does not work with `system` TUN stack, switch the user to `gvisor` here.

---

## 🔀 Outbound Management

Option **3** opens the outbound nodes submenu:

- **View** all configured outbound nodes with their type, endpoint, and count of connected users
- **Add** a node by:
  - Proxy link — `vless://`, `vmess://`, `trojan://`, `ss://`, `socks5://`, `http://`
  - Local network interface / tunnel — e.g. WireGuard `wg0`, `tun0`, Tailscale
  - Manual entry — SOCKS5 or HTTP proxy
- **Delete** a custom outbound — users assigned to it are safely reverted to `direct`

---

## 🌐 WARP Backend

WARP traffic is carried by [usque](https://github.com/Diniboy1123/usque) over **MASQUE HTTP/2 (TCP)**, with the optimal endpoint selected automatically by [warpscout](https://github.com/vernette/warpscout). The Sing-Box `warp` outbound continues to use `SOCKS5 127.0.0.1:40000`, so all routing modes, WARP domain lists, and proxy chains remain fully compatible.

| Scenario | Behaviour |
|----------|-----------|
| **New install** | usque is deployed automatically |
| **Existing server update** | Migrated to usque; if the connection test fails, the updater rolls back to warp-cli |
| **WARP Management** (`ssb` → 9) | Status · endpoint re-scan · connection test · legacy warp-cli removal |

> [!WARNING]
> **WARP+ license keys** are supported only by the legacy warp-cli backend. If your server fell back to warp-cli, activate a key with:
> ```
> warp-cli registration license CMD5m479-Y5hS6y79-U06c5mq9
> ```

---

## 🗺️ Routing Modes

Routing behaviour depends on the **server role** and whether WARP is available.

<details open>
<summary><b>🇷🇺 Russia-based server (5 modes)</b></summary>

| # | Mode | RU / Blocked traffic | Other traffic |
|--:|------|----------------------|---------------|
| 1 | Full WARP | → WARP | → WARP |
| 2 | Partial WARP + Server Direct (Ru-blocked) | Blocked in Russia → WARP | → Server direct |
| 3 | Partial WARP + Client Direct (Ru-blocked) | Blocked in Russia → WARP | → Client direct |
| 4 | Partial WARP + Server Direct (RU/SU/RF) | All RU/SU/RF → WARP | → Server direct |
| 5 | Partial WARP + Client Direct (RU/SU/RF) | RU/SU/RF → Client direct | → WARP |

</details>

<details>
<summary><b>🌍 Foreign server (4 modes)</b></summary>

| # | Mode | RU-related traffic | Other traffic |
|--:|------|--------------------|---------------|
| 1 | Full WARP | → WARP | → WARP |
| 2 | Partial WARP (RU/SU/RF) + Server Direct | RU/SU/RF → WARP | → Server direct |
| 3 | Partial WARP (all except RU/SU/RF) + Client Direct | All except RU/SU/RF → WARP | RU/SU/RF → Client direct |
| 4 | Partial WARP (Ru-blocked) + Server Direct + Client Direct | Ru-blocked → WARP, all except RU/SU/RF → Server | RU/SU/RF → Client direct |

</details>

<details>
<summary><b>🚫 No-WARP server (2 modes)</b></summary>

| # | Mode | Description |
|--:|------|-------------|
| 1 | Full routing | All traffic through server |
| 2 | Ru-blocked + Client Direct | Blocked sites through server; everything else through client direct |

</details>

---

## 🔗 Server Roles

| Role | Description |
|------|-------------|
| **Endpoint** | Last server in a chain (or standalone). Releases traffic to the internet. |
| **Intermediate** | Forwards traffic to the next server. Modes: all traffic · RU/SU/RF via WARP · RU/SU/RF via client direct. |

---

## 📦 Rule Sets

Four SRS rule-set files are used for traffic classification:

| File | Purpose |
|------|---------|
| `geoip-ru.srs` | Russian IP ranges |
| `geosite-category-gov-ru.srs` | Russian government domains |
| `geosite-ru-blocked.srs` | Domains blocked in Russia |
| `geosite-category-ads-all.srs` | Advertising & tracker domains |

Rule sets can be updated automatically via option **8** in the `ssb` menu.

---

## 📱 Client Setup

> [!IMPORTANT]
> The recommended client is the **Sing-Box** app for the most complete routing support. You can also import config links into [Hiddify](https://github.com/hiddify/hiddify-app/releases/latest) or any client based on Sing-Box / Clash / Mihomo cores.
>
> In Hiddify, set **DNS → Outbound domain strategy → IPv4 only**. If some apps are not proxied: **Settings → Inbound → Service mode → VPN**.

| Platform | Guide |
|----------|-------|
| Android, iOS, macOS | [Sing-Box setup guide](Sing-Box-Android-iOS-en.md) |
| Windows | [Sing-Box core setup (no GUI)](Sing-Box-Windows-en.md) |
| Linux (Debian-based) | Run the command below ↓ |

```bash
bash <(curl -Ls https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Scripts/sb-pc-linux.sh)
```

---

## 🗑️ Uninstall

Option **20** in the `ssb` menu provides a full removal wizard:

- **Complete uninstall** — removes all packages, configuration files, and settings
- **Uninstall with config retention** — keeps SSL certificates and web files for potential re-installation
- Optional: reset SSH configuration · reset UFW rules

---

## ⭐ Stargazers

[![Stargazers over time](https://starchart.cc/zipfo/Simple-Sing-Box.svg?variant=adaptive)](https://starchart.cc/zipfo/Simple-Sing-Box)

---

<div align="center">
    Based on the original work by <a href="https://github.com/A-Zuro/Secret-Sing-Box">A-Zuro</a>
</div>
