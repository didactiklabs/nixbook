/*
  A macOS machine (darwin.nix) evaluates, on Linux too, and keeps its
  invariants. Nothing is built: CI's `darwin` job runs it on ubuntu-latest,
  build.yaml's `build (<host>)` builds and activates it on a macOS runner.

    tests/run.sh darwin [NAME]
    nix-instantiate --eval --strict --json tests/darwin.nix --argstr host talia

  Returns { toplevel; warnings; checks }; each check is "ok" or throws with the
  reason. The caller also instantiates `toplevel` with
  allow-import-from-derivation off (a Linux machine can't build darwin
  derivations while evaluating) and looks for Linux desktop packages in its
  closure (tests/run.sh cmd_darwin).
*/
{
  host ? "talia",
}:
let
  machine = (import ../darwin.nix).${host};
  inherit (machine) config;
  inherit (machine.pkgs) lib;
  users = config.home-manager.users;
  check = what: ok: if ok then "ok" else throw "tests/darwin.nix (${host}): ${what}";
  # The Linux-only Home Manager modules: none may be on.
  linuxOnly = [
    "niriConfig"
    "swayConfig"
    "nixbookShellConfig"
    "dmsConfig"
    "gtkConfig"
    "fcitx5Config"
    "desktopEntriesConfig"
    "dolphinConfig"
    "moonlightCompanion"
    "foxblatConfig"
    "oversteerConfig"
  ];
  enabledLinuxOnly = lib.concatLists (
    lib.mapAttrsToList (
      name: hm:
      map (m: "${name}: ${m}") (
        lib.filter (m: hm.customHomeManagerModules.${m}.enable or false) linuxOnly
      )
    ) users
  );
in
{
  toplevel = config.system.build.toplevel.drvPath;
  inherit (config) warnings;
  checks = {
    platform = check "not an aarch64-darwin system (${machine.pkgs.stdenv.hostPlatform.system})" (
      machine.pkgs.stdenv.hostPlatform.system == "aarch64-darwin"
    );
    primaryUser = check "system.primaryUser has no Home Manager configuration" (
      users ? ${config.system.primaryUser}
    );
    linuxDesktop = check "Linux desktop modules are on: ${toString enabledLinuxOnly}" (
      enabledLinuxOnly == [ ]
    );
    # OmniWM is talia's window manager: installed, started at login, and the
    # Nix settings merged into its file.
    omniwm = check "OmniWM isn't set up (package, launchd agents)" (
      lib.all (
        hm:
        !(hm.customHomeManagerModules.omniwmConfig.enable or false)
        || (
          hm.programs.omniwm.enable
          && hm.launchd.agents.omniwm.enable
          && hm.launchd.agents.omniwm-nix-settings.enable
          && hm.home.activation ? omniwmSettings
        )
      ) (lib.attrValues users)
    );
    # Required by OmniWM: "Displays have separate Spaces".
    spaces = check "system.defaults.spaces.spans-displays isn't false" (
      config.system.defaults.spaces.spans-displays == false
    );
    darwinSwitch = check "darwin-switch isn't installed" (
      lib.any (p: (p.name or "") == "darwin-switch") config.environment.systemPackages
    );
  };
}
