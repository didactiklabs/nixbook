{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  imports = [
    ./niriConfig.nix
  ];
  config = lib.mkIf cfg.niriConfig.enable {
    systemd.user.services.polkit-gnome = {
      Unit = {
        Description = "PolicyKit Authentication Agent";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      };
      Install = {
        WantedBy = [
          "graphical-session.target"
          "niri.service"
        ];
      };
    };
  };
  options.customHomeManagerModules.niriConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Niri config globally or not.
        Niri is a scrollable-tiling Wayland compositor.
      '';
    };
  };
}
