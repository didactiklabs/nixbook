{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules.sway;
  cfgcust = config.profileCustomization;
in {
  imports = [
    ./makoConfig.nix
    ./rofiConfig.nix
    ./swayConfig.nix
    ./thunar.nix
    ./waybarConfig.nix
    ./waybarStyle.nix
    ./wofiConfig.nix
  ];

  config = {
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
