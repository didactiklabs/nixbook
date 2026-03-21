{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.rtk;
  rtk = import ../customPkgs/rtk.nix { inherit pkgs; };
in
{
  options.customHomeManagerModules.rtk = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable RTK (Rust Token Killer).

        RTK is a CLI proxy that transparently intercepts common development
        commands (git, kubectl, terraform, etc.) and compresses / summarises
        their output before passing it to an LLM, reducing token consumption
        by 60–90% on typical dev workflows.

        This module:
          - Installs the rtk binary (custom package from customPkgs/rtk.nix)
          - Runs `rtk init --global` on Home Manager activation to register
            rtk's shell hooks globally (~/.config/rtk/)
          - When opencodeConfig is enabled, runs `rtk init -g --opencode`
            instead, which also wires up the opencode auto-rewrite hook so
            that rtk automatically rewrites commands piped through opencode

        Used on: totoro.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ rtk ];

    # Initialize RTK with optional auto-rewrite hook
    home.activation.rtkInit = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      if config.customHomeManagerModules.opencodeConfig.enable then
        ''
          ${rtk}/bin/rtk init -g --opencode
        ''
      else
        ''
          ${rtk}/bin/rtk init --global
        ''
    );
  };
}
