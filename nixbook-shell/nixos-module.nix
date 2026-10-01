{
  config,
  options,
  lib,
  ...
}:
# The NixOS side of nixbook-shell's config assistant: the system's toggles
# (toggles.nix) discovered from the NixOS options tree, read by the Home
# Manager module through osConfig (`assistant.os.toggles`). Home Manager
# modules only get the NixOS configuration, not its options, hence this
# module. Optional: without it, only the Home Manager toggles are known.
#
# Also the login screen in the shell's style (greeter.nix,
# `nixbook-shell.greeter`, off unless enabled), and the firewall of the app
# debugging ports desktop-mcp uses (agent-ports.nix).
{
  imports = [
    ./greeter.nix
    ./agent-ports.nix
  ];

  options.nixbook-shell.toggles = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
    readOnly = true;
    internal = true;
    default = (import ./toggles.nix { inherit lib; }) {
      inherit options config;
      scope = "nixos";
    };
    description = "Every NixOS option set with an `enable` option, and whether it is on.";
  };
}
