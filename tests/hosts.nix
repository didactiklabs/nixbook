/*
  Evaluation checks for one colmena node, without building the system.

  Run through tests/run.sh (`tests/run.sh host <name>`), which calls:
    colmena eval -E '(import ./tests/hosts.nix { host = "<name>"; })'

  It evaluates the node exactly as `colmena build` does (hive.nix -> base.nix ->
  profile), so any module/option/assertion error fails here in about a minute
  instead of after a full build. On top of that it asserts invariants every
  machine is meant to keep (security hardening, deployment contract, state
  version, ...): a change that silently drops one fails the check.

  `allModules = true` evaluates the node with every optional
  customNixOSModules.* toggle switched on (see `optionalModules`), so modules no
  profile enables still get evaluated and can't rot unnoticed.

  The result (JSON) lists the toplevel .drv, NixOS warnings and a few small
  generated files (`cheapBuilds`) that tests/run.sh realises: they are built
  from the evaluated config by tiny runCommands, so building them is cheap and
  exercises code that otherwise only runs during the full system build.
*/
{
  host,
  allModules ? false,
}:
{ nodes, lib, ... }:
let
  # customNixOSModules toggles that few or no profiles turn on; forced on
  # together on top of a real host by `allModules`.
  optionalModules = {
    customNixOSModules =
      lib.genAttrs
        [
          "bluetoothAutoConnect"
          "firewall"
          "gamingConfig"
          "lanzaboote"
          "netbird-tools"
          "ollama"
          "printTools"
          "simracing"
          "sunshine"
          "sway"
          "tailscale"
          "vmSupport"
          "wolf"
        ]
        (_: {
          enable = lib.mkForce true;
        });
  };

  node =
    if !(nodes ? ${host}) then
      throw "tests/hosts.nix: unknown host '${host}' (hive.nix nodes: ${lib.concatStringsSep ", " (lib.attrNames nodes)})"
    else if allModules then
      nodes.${host}.extendModules { modules = [ optionalModules ]; }
    else
      nodes.${host};
  inherit (node) config;
  custom = config.customNixOSModules;

  # Hardening sysctls from nixosModules/core.nix that must reach every machine.
  hardenedSysctls = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.perf_event_paranoid" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.kexec_load_disabled" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "fs.suid_dumpable" = 0;
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    "dev.tty.ldisc_autoload" = 0;
  };
  hardenedKernelParams = [
    "slab_nomerge"
    "page_alloc.shuffle=1"
  ];

  weakSysctls = lib.filter (k: (config.boot.kernel.sysctl.${k} or null) != hardenedSysctls.${k}) (
    lib.attrNames hardenedSysctls
  );
  missingKernelParams = lib.filter (p: !lib.elem p config.boot.kernelParams) hardenedKernelParams;

  normalUsers = lib.attrNames (lib.filterAttrs (_: u: u.isNormalUser) config.users.users);
  hmUsers = config.home-manager.users;

  # name -> bool. Keep each check about a documented, intended behaviour.
  checks = {
    "networking.hostName matches the hive node name" = config.networking.hostName == host;
    "system.stateVersion is still 24.05 (changing it migrates state)" =
      config.system.stateVersion == "24.05";
    "colmena apply-local works (allowLocalDeployment)" = config.deployment.allowLocalDeployment;
    "colmena builds on the target (buildOnTarget)" = config.deployment.buildOnTarget;

    "core module is enabled" = custom.core.enable;
    "getRevision writes /etc/nixos/version (used by osupdate)" =
      config.environment.etc ? "nixos/version";

    "kernel hardening sysctls are applied (weakened: ${toString weakSysctls})" = weakSysctls == [ ];
    "kernel hardening boot params are applied (missing: ${toString missingKernelParams})" =
      missingKernelParams == [ ];
    "systemd-boot command-line editor is disabled" = !config.boot.loader.systemd-boot.editor;
    "sudo is executable by wheel only" = config.security.sudo.execWheelOnly;
    "Wayland only: X server is disabled" = !config.services.xserver.enable;

    "lanzaboote replaces systemd-boot when enabled" =
      custom.lanzaboote.enable
      -> (config.boot.lanzaboote.enable && !config.boot.loader.systemd-boot.enable);
    "greetd login keeps U2F, fingerprint and keyring unlock (whatever the greeter)" =
      custom.greetd.enable
      -> (
        let
          pam = config.security.pam.services.greetd;
        in
        pam.u2fAuth && pam.fprintAuth && pam.enableGnomeKeyring
      );
    "firewall module turns on the nftables firewall" =
      custom.firewall.enable -> (config.networking.firewall.enable && config.networking.nftables.enable);

    "the didactiklabs binary cache is configured" =
      lib.elem "https://s3.didactiklabs.io/nix-cache" config.nix.settings.substituters
      && lib.elem "didactiklabs-nixcache:PxLKN0+ZkP07M8g8/B6xbP6A4MYpqQg6LH7V3muiy/0=" config.nix.settings.trusted-public-keys;

    "the machine has at least one normal user" = normalUsers != [ ];
    "every normal user is in wheel" = lib.all (
      u: lib.elem "wheel" config.users.users.${u}.extraGroups
    ) normalUsers;
    "every normal user has a Home Manager config" = lib.all (u: hmUsers ? ${u}) normalUsers;
  };
  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);

  # Small files generated from the evaluated config (see header).
  drvOf = x: if lib.isDerivation x then x.drvPath else null;
  # system-facts.json's inputs (the rendered niri config, package names) carry
  # the string context of the whole desktop: building it as-is would first
  # fetch or build every package the keybinds mention. Same text, no context.
  withoutInputContext =
    drv:
    drv.overrideAttrs (
      old:
      lib.mapAttrs (_: builtins.unsafeDiscardStringContext) (
        lib.getAttrs (lib.filter (a: old ? ${a}) [
          "info"
          "niriKdl"
        ]) old
      )
    );
  userFiles =
    u:
    let
      files = hmUsers.${u}.xdg.configFile;
      source = name: files.${name}.source or null;
    in
    lib.optionals (files ? "nixbook-shell/system-facts.json") [
      (drvOf (withoutInputContext (source "nixbook-shell/system-facts.json")))
      (drvOf (source "nixbook-shell/nix-pinned-values.json"))
      (drvOf (source "nixbook-shell/nix-managed.json"))
    ];
  cheapBuilds = lib.filter (d: d != null) (
    [ (drvOf config.environment.etc."nixos/version".source) ] ++ lib.concatMap userFiles normalUsers
  );
in
if failed != [ ] then
  throw ''
    ${host}${lib.optionalString allModules " (all optional modules on)"}: ${toString (lib.length failed)} invariant(s) broken:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}''
else
  {
    inherit host allModules cheapBuilds;
    inherit (config) warnings;
    toplevel = config.system.build.toplevel.drvPath;
  }
