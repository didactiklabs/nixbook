{
  config,
  pkgs,
  lib,
  sources,
  ...
}:
let
  cfg = config.customNixOSModules;
  ds4drv = pkgs.python313Packages.ds4drv.overrideAttrs (oldAttrs: {
    src = sources.ds4drv;
  });
  inherit (pkgs.customPkgs) ginx;
  osupdate = pkgs.writeShellScriptBin "osupdate" ''
    set -euo pipefail
    # colmena evaluates the hive with nix (not on a systemd unit's PATH: its
    # absence made `colmena apply-local` panic with "No such file or directory").
    export PATH=${
      lib.makeBinPath [
        config.nix.package
        pkgs.git
        pkgs.gawk
        pkgs.coreutils
        pkgs.hostname
      ]
    }:$PATH

    # --force (or OSUPDATE_FORCE=1): skip the network preflight.
    # --boot (or OSUPDATE_BOOT=1): install the new system for the next boot
    # only (colmena's `boot` goal): nothing running changes until a restart.
    force=''${OSUPDATE_FORCE:-0}
    boot=''${OSUPDATE_BOOT:-0}
    for arg in "$@"; do
      case "$arg" in
        --force) force=1 ;;
        --boot) boot=1 ;;
        *) echo "usage: osupdate [--force] [--boot]" >&2; exit 2 ;;
      esac
    done

    ${lib.optionalString config.networking.networkmanager.enable ''
      if [ "$force" != 1 ] && ! ${pkgs.networkmanager}/bin/nm-online -q -t 30; then
        echo "error: no network connection (use osupdate --force to try anyway)" >&2
        exit 1
      fi
    ''}

    target="$(git ls-remote https://github.com/didactiklabs/nixbook refs/heads/main | awk '{print $1}')"
    echo "last applied revision: $(${pkgs.jq}/bin/jq -r .rev /etc/nixos/version)"
    echo applying revision: "$target"...

    goal=switch
    # The new system's own copy: /etc only changes once it is running.
    version=/etc/nixos/version
    if [ "$boot" = 1 ]; then
      goal=boot
      version=/nix/var/nix/profiles/system/etc/nixos/version
      echo "installing it for the next boot (the running system is left as it is)"
    fi

    echo Running ginx...
    ${ginx}/bin/ginx --source https://github.com/didactiklabs/nixbook -b main --now -- /run/wrappers/bin/sudo ${pkgs.colmena}/bin/colmena apply-local "$goal"
    # ginx exits 0 even when its command fails: check the result.
    applied="$(${pkgs.jq}/bin/jq -r .rev "$version")"
    if [ "$applied" != "$target" ]; then
      echo "error: the update did not apply (deployed revision: $applied, expected: $target)" >&2
      exit 1
    fi
    if [ "$boot" = 1 ]; then
      echo "installed $applied: it applies at the next boot"
    else
      echo "updated to $applied"
    fi
  '';
  # The update units the desktop shell starts (passwordless, core.nix's
  # polkit rule). Both write /run/nixos-upgrade/status.json, so the shell
  # watches one file whichever ran; never both at once.
  upgradeService =
    { description, boot }:
    let
      other = if boot then "nixos-upgrade-manual.service" else "nixos-upgrade-boot.service";
      mode = if boot then "boot" else "switch";
      # What the run installed: the new system's copy when it is for the
      # next boot (/etc only changes once it is running).
      version = if boot then "/nix/var/nix/profiles/system/etc/nixos/version" else "/etc/nixos/version";
    in
    {
      inherit description;
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        # What the desktop shell's updates widget watches (it no longer
        # follows the journal itself): /run/nixos-upgrade/status.json,
        # {state: running|success|failed, started, finished, step (the
        # latest log line, every 2 s), rev, tail (the log's last lines),
        # mode: switch | boot}.
        RuntimeDirectory = "nixos-upgrade";
        RuntimeDirectoryMode = "0755";
        RuntimeDirectoryPreserve = "yes";
        # Never while the other one runs (both use the same files).
        ExecCondition = "${pkgs.writeShellScript "nixos-upgrade-alone" ''
          ! ${pkgs.systemd}/bin/systemctl is-active --quiet ${other}
        ''}";
        ExecStart = "${pkgs.writeShellScript "nixos-upgrade-wrapper" ''
          set -o pipefail
          export NIXPKGS_ALLOW_UNFREE=1
          export PATH=$PATH:${
            lib.makeBinPath [
              pkgs.git
              pkgs.jq
              pkgs.colmena
              ginx
              osupdate
            ]
          }
          dir=/run/nixos-upgrade
          : >"$dir/log"
          # Which unit the status is about (ExecStopPost runs for a skipped one too).
          echo ${mode} >"$dir/owner"
          started=$(date +%s)
          running() {
            jq -nc --argjson s "$started" --arg step "$(tail -n 1 "$dir/log" | cut -c1-200)" \
              '{state: "running", started: $s, step: $step, mode: "${mode}"}' >"$dir/status.json.tmp" &&
              mv -f "$dir/status.json.tmp" "$dir/status.json"
          }
          running
          (while sleep 2; do running; done) &
          ticker=$!
          trap 'kill $ticker 2>/dev/null' EXIT
          osupdate ${lib.optionalString boot "--boot"} 2>&1 | tee -a "$dir/log"
        ''}";
        ExecStopPost = "${pkgs.writeShellScript "nixos-upgrade-status" ''
          dir=/run/nixos-upgrade
          [ "$(cat "$dir/owner" 2>/dev/null)" = ${mode} ] || exit 0
          state=failed
          [ "''${SERVICE_RESULT:-}" = success ] && [ "''${EXIT_STATUS:-0}" = 0 ] && state=success
          started=$(${pkgs.jq}/bin/jq '.started // null' "$dir/status.json" 2>/dev/null) || started=null
          tail -n 60 "$dir/log" 2>/dev/null |
            ${pkgs.jq}/bin/jq -Rsc --arg st "$state" --argjson s "''${started:-null}" --argjson f "$(date +%s)" \
              --arg rev "$(${pkgs.jq}/bin/jq -r '.rev // ""' ${version} 2>/dev/null)" \
              '{state: $st, started: $s, finished: $f, rev: $rev, mode: "${mode}", tail: (. | rtrimstr("\n"))}' >"$dir/status.json.tmp" &&
            mv -f "$dir/status.json.tmp" "$dir/status.json"
        ''}";
        StandardOutput = "journal";
        StandardError = "journal";
        # Stay out of the way of the desktop while it evaluates and
        # switches, and don't hang forever on a stuck download.
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "2h";
      };
    };

in
{
  options.customNixOSModules.tools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the tools NixOS module.

        Provides system-level tooling and services:
        - Container runtime: Podman with Docker compatibility alias, DNS-enabled default
          network, weekly auto-prune, and OCI container backend
        - Kernel modules: netfilter (conntrack, ipvs) for container
          networking
        - System packages: openvpn, gnupg, yubikey tools (yubico-piv-tool, yubioath-flutter,
          yubikey-personalization), podman/podman-compose, wlsunset, cups-pk-helper, ginx,
          osupdate, ds4drv, efibootmgr, colmena, update-systemd-resolved, pinentry-qt, lsof
        - YubiKey: udev rules, yubikey-touch-detector, GnuPG agent with SSH support
        - FIDO2: libfido2 package and udev rules for SSH security keys (ed25519-sk/ecdsa-sk)
        - DS4 controller: user systemd service running ds4drv in HID-raw + xpad emulation
          mode for DualShock 4 controllers
        - osupdate: shell script that applies the latest nixbook main branch via ginx +
          colmena apply-local (`--boot`: installed for the next boot only); the
          nixos-upgrade-manual and nixos-upgrade-boot units run it for the desktop shell
        - udev: game-devices rules, and uinput for the users (the uinput group, which
          every nixbook user is in, and the active seat), not every local account

        Note: User-level packages belong in homeManagerModules (devTools, cliTools, etc.).
      '';
    };
  };

  config = lib.mkIf cfg.tools.enable {
    virtualisation = {
      oci-containers.backend = "podman";
      podman = {
        enable = true;
        # Create a `docker` alias for podman, to use it as a drop-in replacement
        dockerCompat = true;
        # Required for containers under podman-compose to be able to talk to each other.
        defaultNetwork.settings.dns_enabled = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
      };
    };
    # Weekly and Persistent like nh-clean: idle priority when it catches up
    # at boot or resume.
    systemd.services.podman-prune.serviceConfig = {
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    boot = {
      # No legacy ip_tables/iptable_nat/ip6_tables/ip6table_nat: the kernel no
      # longer builds them (CONFIG_IP_NF_IPTABLES_LEGACY off) and podman uses
      # nftables. nf_conntrack_ipv4 was merged into nf_conntrack in Linux 4.19.
      kernelModules = [
        "nf_conntrack"
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
      ];
    };

    # System packages - Core utilities only
    # User-level packages should be in homeManagerModules (devTools, securityTools, systemTools, cliTools)
    environment.systemPackages = with pkgs; [
      libsecret
      openvpn
      podman
      podman-compose
      # GPG and SSH
      gnupg
      # FIDO2 support for SSH security keys (ed25519-sk / ecdsa-sk)
      libfido2
      # Yubikey tools
      yubico-piv-tool
      yubico-pam
      yubioath-flutter
      yubikey-personalization
      accountsservice
      wlsunset
      cups-pk-helper
      ginx
      osupdate
      ds4drv
      efibootmgr
      colmena
      update-systemd-resolved
      pinentry-qt
      lsof
      sshuttle
    ];

    services.udev = {
      packages = with pkgs; [
        game-devices-udev-rules
        yubikey-personalization
        libfido2 # FIDO2 device access rules for SSH security keys
      ];
      extraRules = ''
        # Virtual input (Steam, Sunshine, controller drivers) for the users,
        # not world-writable: with 0666 any account (a service user, a
        # container) could type into the desktop session, i.e. run commands as
        # its user. Users are in the uinput group (lib/userConfig.nix); uaccess
        # also covers a session started before that group was added.
        KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="uinput", TAG+="uaccess"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0666"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:054C:05C4.*", MODE="0666"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0666"
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:054C:09CC.*", MODE="0666"
      '';
    };
    systemd = {
      # user.services.ds4drv = {
      #   enable = true;
      #   description = "Controller Support.";
      #   wantedBy = [ "default.target" ];
      #   serviceConfig = {
      #     ExecStart = "${ds4drv}/bin/ds4drv --hidraw";
      #     Restart = "always";
      #   };
      # };
      services = {
        "nixos-upgrade-manual" = upgradeService {
          description = "Manual NixOS System Upgrade";
          boot = false;
        };
        # The same, installed for the next boot only (osupdate --boot): the
        # shell's "Next restart" and updates.auto.nextBoot.
        "nixos-upgrade-boot" = upgradeService {
          description = "NixOS System Upgrade for the next boot";
          boot = true;
        };
      };
    };

    programs = {
      kdeconnect.enable = lib.mkDefault true;
      # yubikey-touch-detector.enable = true;
      gnupg.agent = {
        enable = true;
        enableSSHSupport = true; # yubikey ssh
        pinentryPackage = pkgs.pinentry-qt;
      };
    };
  };
}
