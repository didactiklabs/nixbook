{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  imports = [
    ./swayConfig.nix
  ];
  config = lib.mkIf cfg.sway.enable {
    wayland.windowManager.sway.config.startup = [
      {
        command = "${pkgs.systemd}/bin/systemctl --user restart swayidle";
        always = true;
      }
      {
        command = "${pkgs.copyq}/bin/copyq";
        always = false;
      }
    ];
  };
  ## https://arewewaylandyet.com/
  ## https://shibumi.dev/posts/my-way-to-wayland/
  ## https://github.com/swaywm/sway/wiki/Useful-add-ons-for-sway
  options.customHomeManagerModules.sway = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable sway config globally or not
      '';
    };
  };
}
