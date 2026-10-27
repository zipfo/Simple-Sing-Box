# Changelog & Architecture Guide

All notable changes to Simple-Sing-Box are documented in this file.

---

## [1.6.0] - 2026-10-27

### Added
- **usque MASQUE-H2 WARP Backend**:
  - Replaced UDP-based `warp-cli` (WireGuard) with `usque` running MASQUE protocol over TCP/HTTP2 on port 443. This bypasses ISP and hoster throttling on UDP traffic (e.g., 15 Mbps caps) and delivers full wire speeds (up to 100+ Mbps).
  - Integrated `warpscout` for automatic Cloudflare WARP account registration (`/etc/warpscout/account.json`) and scanning for the lowest-latency MASQUE endpoint.
  - Drop-in compatibility: sing-box configuration remains untouched; `usque` binds to `127.0.0.1:40000` via SOCKS5, perfectly preserving the existing `warp` outbound contract (`{"type":"socks","tag":"warp","server":"127.0.0.1","server_port":40000}`).
  - Systemd service `usque-warp.service` manages the usque daemon with automatic restart on boot.
- **WARP Management Submenu (Option 9)**:
  - Option 1: Status display (active backend, service state, endpoint IP:port, SNI, port).
  - Option 2: Re-scan best endpoint via `warpscout` with automatic configuration reload and health verification (with rollback to previous endpoint on failure).
  - Option 3: End-to-end SOCKS connectivity test through WARP.
  - Option 4: Removal of legacy `cloudflare-warp` package (only permitted when `usque` is active and healthy).
- **Automated Migration & Upgrade in `update-server.sh`**:
  - Automatically migrates existing servers with `warp_option=1` from `warp-cli` to `usque` during server updates.
  - Fully automated rollback to `warp-cli` if `usque` registration, endpoint scan, or health test fails.
  - Automatically updates `usque` and `warpscout` binaries when new GitHub releases are detected.

### Changed
- **Modern Subscription Interface Redesign**:
  - Rebuilt `sub.html` with a standalone dark theme featuring sharp borders, CSS grid background, and responsive layout without external assets.
  - Eliminated dependency on `background.jpg` and updated `install-server.sh` and `update-server.sh` accordingly.
  - Added streamlined profile actions: one-click Sing-Box import, profile URL clipboard copying, and direct JSON file download.
- **Uninstaller Upgrades**:
  - Uninstaller thoroughly purges `usque`, `warpscout`, `usque-warp.service`, `/etc/usque`, and `/etc/warpscout`.

---

## [1.5.5] - 2026-10-22

### Added
- **Outbounds Management Menu (Option 3 in Main Menu)**:
  - Interactive table displaying all active outbounds (built-in `direct`, `warp` and custom nodes) with node type, server address/interface, and connected user counts.
  - **Add outbound by proxy link**: Embedded parser for `vless://`, `vmess://`, `trojan://`, `ss://`, `socks5://`, and `http://`. Automatically extracts server, port, credentials, TLS settings, transport (WS/gRPC/HTTPUpgrade), SNI, and generates valid sing-box outbound configurations.
  - **Add outbound via network interface / tunnel**: Supports WireGuard interfaces (`wg0`), TUN devices, Tailscale/ZeroTier tunnels via sing-box `bind_interface`.
  - **Add outbound manually**: Interactive setup for custom SOCKS5 and HTTP proxy servers with optional authentication.
  - **Safe Outbound Deletion**: Safely removes custom outbounds and automatically falls back all assigned users to server `direct`.
- **Per-User Independent Outbound Nodes & Routing Modes**:
  - Users can be assigned any custom outbound node independently of their routing mode.
  - Upgraded routing modes dynamic dispatch:
    - `default`: Server default routing (Russian domains -> WARP, rest -> assigned user node).
    - `full-node` / `full-direct`: 100% user traffic routed through their selected outbound node.
    - `full-warp`: 100% user traffic routed through local WARP.
    - `full-chain`: 100% user traffic routed through proxy chain.
    - `warp-ru`: Russian domains (.ru, .su, etc.) -> WARP, remaining traffic -> user outbound node.
    - `direct-ru` / `node-ru`: Russian domains -> user outbound node, remaining traffic -> WARP.
    - `chain-ru`: Russian domains -> proxy chain, remaining traffic -> user outbound node.
  - State persisted cleanly in `/etc/secret-sing-box/user-routes` with format `username:node:mode`.
- **Zero-Downtime Sing-Box Hot-Reload**:
  - Implemented `reload_sing_box` to eliminate service restart downtime.
  - Configures systemd drop-in override: `/etc/systemd/system/sing-box.service.d/override.conf` with `ExecReload=/bin/kill -HUP $MAINPID`.
  - Graceful fallback sequence: `systemctl reload` -> direct `kill -HUP $pid` -> `systemctl restart` (only if stopped).
  - All routing mode and outbound changes take effect immediately on the fly without dropping active user connections.
- **Interactive User Management Submenu (Option 1 in Main Menu)**:
  - Interactive User List showing user profiles with their active TUN stack, assigned outbound node, and routing mode.
  - Selecting a user opens their dedicated action profile:
    - `1`: Connection details (links & QR codes)
    - `2`: Select outbound node
    - `3`: Select routing mode
    - `4`: Rename user
    - `5`: Change TUN stack (system / gvisor / mixed)
    - `6`: Delete user (with confirmation)

### Changed
- **Server Update Hardening (`update-server.sh`)**:
  - Preserves custom outbounds and user routing rules across server updates.
  - Auto-initializes `/etc/secret-sing-box/user-routes` for existing users during upgrades from v1.5.4.
  - Adds configuration validation (`sing-box check`) before restarting services, with automatic rollback to `config.json.0` on failure.
  - Ensures accurate placeholder substitution for `RULESETPATH`.

---

## [1.5.4] - 2026-04-13

### Baseline Architecture
- Sing-Box core server with Trojan-WS and VLESS-WS inbounds multiplexed behind NGINX / HAProxy.
- Automated ACME certificate issuance via Certbot (HTTP-01 or Cloudflare DNS-01 challenge).
- Local WARP integration for Russian domain routing (.ru, .su, .рф, geoip-ru, category-gov-ru).
- Dynamic client configuration generation with encrypted subscription distribution page (`sub.html`).
- Automated ruleset updater (`rsupdate`) and blacklist management (`blacklist-update`).

---

## Key Configuration Files & Architecture Reference

| Path | Purpose |
| :--- | :--- |
| `/etc/sing-box/config.json` | Sing-box core configuration (inbounds, outbounds, routing rules, rule-sets). |
| `/etc/secret-sing-box/config` | Global SSB settings (`warp_option`, `warp_backend`, `usque_endpoint`, `usque_port`, `usque_sni`, `server_location`). |
| `/etc/secret-sing-box/user-routes` | Per-user routing registry in format `username:outbound_node:routing_mode`. |
| `/etc/usque/config.json` | usque MASQUE daemon configuration (private key, endpoint IP, port). |
| `/etc/warpscout/account.json` | Cloudflare WARP MASQUE account registration data. |
| `/etc/systemd/system/sing-box.service.d/override.conf` | Systemd drop-in defining `ExecReload=/bin/kill -HUP $MAINPID` for hot-reload. |
| `/var/www/${subspath}/` | Subscription web page and user client JSON profiles. |
| `/var/www/${rulesetpath}/` | Local binary rule sets (SRS format). |
