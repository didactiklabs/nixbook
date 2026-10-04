# Networking & VPN

Every machine uses **NetworkManager**. On top of it, Nixbook ships two mesh VPNs (enabled by default) and support for traditional VPN clients.

## Tailscale

`customNixOSModules.tailscale` (on by default):

- `services.tailscale` with full routing features — use the machine as an **exit node** or **subnet router**, or route through one;
- the **native nftables** backend (no iptables-compat translation issues), IP forwarding and loose reverse-path filtering for exit-node traffic;
- the `tailscale0` interface trusted and Tailscale's UDP port open in the firewall;
- workarounds for route conflicts with other VPNs;
- **`tswitch`** — an fzf TUI listing your tailnets (`tailscale switch --list`) to switch between them.

## NetBird

`customNixOSModules.netbird-tools` (on by default):

- the [NetBird](https://netbird.io) WireGuard overlay daemon (no tray UI);
- **`nswitch`** — an fzf TUI listing NetBird networks and switching to the selected one (`netbird network select` + `netbird up`).

Disable either per machine:

```nix
customNixOSModules = {
  tailscale.enable = false;
  netbird-tools.enable = false;
};
```

## In the desktop shell

nixbook-shell's **VPN bar widget** shows Tailscale and NetBird status, IPs and the exit node on hover; its panel toggles each VPN, switches tailnet or NetBird profile, and sets or clears the exit node. DankMaterialShell has an equivalent VPN status plugin. The shell only puts the CLIs of the VPNs the system enables on its PATH.

## Other VPN clients

- **OpenVPN** — installed system-wide by the `tools` module (an `.ovpn` profile lives in `assets/openvpn/`).
- **OpenVPN 3** (`programs.openvpn3`, the `openvpn3` CLI) — per profile (tanjiro).
- **GlobalProtect** — `gpclient` / `gpauth` built from source from the pinned upstream flake (tanjiro).
- **WPA Enterprise / 802.1X** — `nm-applet` and `nm-connection-editor` are installed with Niri for credential prompts and advanced settings.

## SSH client

`customHomeManagerModules.sshConfig` sets keep-alives for every host (every 10 s, disconnect after 2 misses) and disables compression. Keys come from YubiKeys (GPG or FIDO2) or agenix secrets.

## Remote access

- **Sunshine** / **Moonlight** for remote desktop and game streaming — see [Streaming](./gaming-and-streaming#sunshine).
- **KDE Connect** is enabled globally: phone notifications, file sharing, clipboard, media control — and a [bar widget](/nixbook-shell/media#phone-connect) in nixbook-shell.
