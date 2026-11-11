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

    force=''${OSUPDATE_FORCE:-0} wait_cache=1
    for arg in "$@"; do
      case "$arg" in
      --force) force=1 ;;
      --no-wait) wait_cache=0 ;;
      *)
        echo "usage: osupdate [--force] [--no-wait]" >&2
        exit 2
        ;;
      esac
    done
    [ "''${OSUPDATE_NO_WAIT:-0}" = 1 ] && wait_cache=0

    ${lib.optionalString config.networking.networkmanager.enable ''
      # Network preflight, skipped with `osupdate --force` (or OSUPDATE_FORCE=1).
      if [ "$force" != 1 ] && ! ${pkgs.networkmanager}/bin/nm-online -q -t 30; then
        echo "error: no network connection (use osupdate --force to try anyway)" >&2
        exit 1
      fi
    ''}

    main_rev() {
      git ls-remote https://github.com/didactiklabs/nixbook refs/heads/main | awk '{print $1}'
    }
    target="$(main_rev)"

    # Wait until CI has pushed this revision's systems to the binary cache
    # (build.yaml's cache-ready job writes nixbook/revs/<rev> once the push
    # is over): applying right after a merge, as the update widget invites,
    # built everything here — the push lands ~30 min after the merge, so not
    # one path came from the cache in two weeks of updates on totoro. main
    # is read again each time, so a newer merge (whose run replaces this
    # one's) is waited for instead. After OSUPDATE_CACHE_WAIT minutes
    # (default 45), or with --no-wait / OSUPDATE_NO_WAIT=1, it goes ahead
    # and builds what isn't cached.
    if [ "$wait_cache" = 1 ]; then
      cache=https://s3.didactiklabs.io/nix-cache/nixbook/revs
      limit=$((''${OSUPDATE_CACHE_WAIT:-45} * 60)) waited=0
      while true; do
        if mark=$(${pkgs.curl}/bin/curl -sfL --max-time 10 "$cache/$target" 2>/dev/null); then
          echo "CI has cached revision ''${target:0:8} ($(${pkgs.jq}/bin/jq -r '.result // "?"' <<<"$mark" 2>/dev/null))"
          break
        fi
        if [ "$waited" -ge "$limit" ]; then
          echo "warning: CI hasn't cached revision ''${target:0:8} after $((waited / 60)) min, building what isn't cached" >&2
          break
        fi
        echo "waiting for CI to cache revision ''${target:0:8} ($((waited / 60))/$((limit / 60)) min, osupdate --no-wait skips this)"
        sleep 30
        waited=$((waited + 30))
        if newer="$(main_rev)" && [ -n "$newer" ]; then target=$newer; fi
      done
    fi

    echo last applied revision: $(${pkgs.jq}/bin/jq -r .rev /etc/nixos/version)
    echo applying revision: "$target"...

    echo Running ginx...
    ${ginx}/bin/ginx --source https://github.com/didactiklabs/nixbook -b main --now -- /run/wrappers/bin/sudo ${pkgs.colmena}/bin/colmena apply-local
    # ginx exits 0 even when its command fails: check the result.
    applied="$(${pkgs.jq}/bin/jq -r .rev /etc/nixos/version)"
    if [ "$applied" != "$target" ]; then
      echo "error: the update did not apply (deployed revision: $applied, expected: $target)" >&2
      exit 1
    fi
    echo "updated to $applied"
  '';
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
          colmena apply-local, once CI has pushed that revision to the binary cache
          (up to 45 min; `--no-wait` skips the wait)
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
        "nixos-upgrade-manual" = {
          description = "Manual NixOS System Upgrade";
          restartIfChanged = false;
          stopIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            # What the desktop shell's updates widget watches (it no longer
            # follows the journal itself): /run/nixos-upgrade/status.json,
            # {state: running|success|failed, started, finished, step (the
            # latest log line, every 2 s), rev, tail (the log's last lines)}.
            RuntimeDirectory = "nixos-upgrade";
            RuntimeDirectoryMode = "0755";
            RuntimeDirectoryPreserve = "yes";
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
              started=$(date +%s)
              running() {
                jq -nc --argjson s "$started" --arg step "$(tail -n 1 "$dir/log" | cut -c1-200)" \
                  '{state: "running", started: $s, step: $step}' >"$dir/status.json.tmp" &&
                  mv -f "$dir/status.json.tmp" "$dir/status.json"
              }
              running
              (while sleep 2; do running; done) &
              ticker=$!
              trap 'kill $ticker 2>/dev/null' EXIT
              osupdate 2>&1 | tee -a "$dir/log"
            ''}";
            ExecStopPost = "${pkgs.writeShellScript "nixos-upgrade-status" ''
              dir=/run/nixos-upgrade
              state=failed
              [ "''${SERVICE_RESULT:-}" = success ] && [ "''${EXIT_STATUS:-0}" = 0 ] && state=success
              started=$(${pkgs.jq}/bin/jq '.started // null' "$dir/status.json" 2>/dev/null) || started=null
              tail -n 60 "$dir/log" 2>/dev/null |
                ${pkgs.jq}/bin/jq -Rsc --arg st "$state" --argjson s "''${started:-null}" --argjson f "$(date +%s)" \
                  --arg rev "$(${pkgs.jq}/bin/jq -r '.rev // ""' /etc/nixos/version 2>/dev/null)" \
                  '{state: $st, started: $s, finished: $f, rev: $rev, tail: (. | rtrimstr("\n"))}' >"$dir/status.json.tmp" &&
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
