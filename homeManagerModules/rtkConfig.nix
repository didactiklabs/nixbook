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

    enableGlobalHook = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to automatically install the global command rewrite hook.
        This transparently rewrites commands like `git status` to `rtk git status`
        before execution, providing automatic token savings without manual intervention.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ rtk ];

    # Initialize RTK with optional auto-rewrite hook
    home.activation.rtkInit = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      if cfg.enableGlobalHook then
        ''
          ${rtk}/bin/rtk init --global --auto-patch || true
        ''
      else
        ''
          # RTK is installed but hook not auto-initialized
          # Users can manually run: rtk init --global
        ''
    );
  };
}
