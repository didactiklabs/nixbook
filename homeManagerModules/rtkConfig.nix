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
        Whether to enable RTK (Rust Token Killer) - a CLI proxy that reduces LLM token
        consumption by 60-90% on common development commands.
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
