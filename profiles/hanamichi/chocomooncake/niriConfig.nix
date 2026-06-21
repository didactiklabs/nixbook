{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  # Per-user niri output layout. The shared niri module already provides a
  # sane default ("*" at scale 1.0), which works for a single-monitor desktop.
  # Add explicit monitor entries here once the connector names are known
  # (run `niri msg outputs` to list them), e.g.:
  #
  #   programs.niri.settings.outputs = lib.mkForce {
  #     "DP-1" = {
  #       mode = { width = 2560; height = 1440; refresh = 144.0; };
  #       position = { x = 0; y = 0; };
  #     };
  #   };
  config = lib.mkIf cfg.niriConfig.enable {
    # Override the shared niri default (French) with a US keyboard layout.
    programs.niri.settings.input.keyboard.xkb.layout = lib.mkForce "us";
  };
}
