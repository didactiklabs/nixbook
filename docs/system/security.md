# Security

Security is built into every layer of Nixbook.

| Layer           | Feature                                          | Module / where                            |
| --------------- | ------------------------------------------------ | ----------------------------------------- |
| Firmware & boot | UEFI Secure Boot, automatic key enrolment        | [`lanzaboote`](/installation/secure-boot) |
| Boot            | Kernel command-line editor disabled, silent boot | `core`                                    |
| Disk            | LUKS full-disk encryption on LVM                 | [installer](/installation/iso)            |
| Kernel          | Hardening sysctls and boot parameters            | [`core`](./core#kernel-hardening)         |
| Authentication  | U2F security keys, fingerprint, GNOME Keyring    | `core`, [`greetd`](/desktop/login)        |
| Secrets         | Age-encrypted secrets                            | agenix                                    |
| Network         | Deny-by-default nftables firewall                | `firewall`                                |
| Trust           | Organisation CA certificates                     | `caCertificates`                          |
| Malware         | ClamAV daemon and signature updates              | per profile (tanjiro)                     |

## Secure Boot

See the dedicated page: [Secure Boot](/installation/secure-boot).

## Disk encryption

The installer optionally sets up **LUKS** under LVM. The installer adds the LUKS device into the generated hardware configuration, since `nixos-generate-config` cannot see a LUKS container below LVM. LUKS is strongly recommended together with Secure Boot, whose signing keys are stored on disk.

## Security keys and fingerprints

- **U2F / FIDO2** (YubiKey…) works for login, sudo, greetd and the lock screens. pam_u2f sends a _"Touch your security key"_ cue, which tuigreet, sudo and the nixbook-shell lock and login screens display.
- **Fingerprint** login through fprintd.
- **SSH with a YubiKey**: either GPG authentication subkeys on the smart card (GnuPG agent with SSH support), or FIDO2 `ed25519-sk` / `ecdsa-sk` keys.
- Some profiles lock the session when the security key is removed.

## Secrets with agenix

[agenix](https://github.com/ryantm/agenix) is imported both system-wide and into Home Manager. Secrets are age-encrypted files committed to the repository and decrypted at activation with the machine's or user's key. The devenv shell provides `ragenix` to create and re-key them.

## Firewall

`customNixOSModules.firewall` (off by default) enables the NixOS stateful firewall with a **deny-by-default** inbound policy:

```nix
customNixOSModules.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 ];
  allowedUDPPorts = [ 51820 ]; # WireGuard
};
```

Incoming connections are **dropped** (not rejected, to avoid leaking topology) unless listed, refused attempts are logged to the journal, and outbound traffic is unrestricted. Tailscale's interface is trusted by the [Tailscale module](./networking#tailscale).

## CA certificates

`customNixOSModules.caCertificates.<org>.enable` adds an organisation's internal CA to the system trust store (and to `/etc/ssl/certs/<org>-ca.crt`), so curl, Git, browsers and container tools trust internal HTTPS endpoints:

| Option         | Certificate                        |
| -------------- | ---------------------------------- |
| `didactiklabs` | `assets/certs/didactiklabs-ca.crt` |
| `bealv`        | `assets/certs/bealv-ca.crt`        |
| `rpcu`         | `assets/certs/rpcu-ca.crt`         |
| `logicmg`      | `assets/certs/logicmg-ca.crt`      |

## ClamAV

Profiles can enable the ClamAV daemon and its signature updater (`services.clamav.daemon` / `updater`), as tanjiro does.

## Sandboxing AI agents

nixbook-shell's [agent desktop](/nixbook-shell/agent-desktop) runs AI agents' apps in a bubblewrap sandbox with their own home, network namespace and a restricted Wayland connection, and the [desktop control server](/nixbook-shell/desktop-agents#guardrails) refuses typing into terminals and password prompts.
