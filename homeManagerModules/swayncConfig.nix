{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  soundNotification = pkgs.writeShellScriptBin "soundNotification" ''
    if [ $(${pkgs.swaynotificationcenter}/bin/swaync-client -D) == 'false' ]; then
      ${pkgs.mpg123}/bin/mpg123 ${../assets/sounds/notifications.mp3};
    fi
  '';
in
{
  config = lib.mkIf cfg.desktopApps.enable {
    services.swaync = {
      enable = true;
      settings = {
        scripts = {
          sound = {
            exec = "${soundNotification}/bin/soundNotification";
            app-name = ".*";
          };
        };
        positionX = "right";
        positionY = "top";
        control-center-margin-top = 10;
        control-center-margin-bottom = 10;
        control-center-margin-right = 10;
        control-center-margin-left = 10;
        notification-icon-size = 48;
        notification-body-image-height = 70;
        notification-body-image-width = 150;
        timeout = 10;
        timeout-low = 5;
        timeout-critical = 0;
        fit-to-screen = true;
        control-center-width = 500;
        control-center-height = 800;
        notification-window-width = 500;
        keyboard-shortcuts = true;
        image-visibility = "when-available";
        transition-time = 200;
        hide-on-clear = false;
        hide-on-action = true;
        script-fail-notify = true;
        widgets = [
          "title"
          "mpris"
          "volume"
          "backlight"
          "dnd"
          "notifications"
        ];
        widget-config = {
          title = {
            text = "Notification Center";
            clear-all-button = true;
            button-text = "󰆴 Clear All";
          };
          dnd = {
            text = "Do Not Disturb";
          };
          label = {
            max-lines = 1;
            text = "Notification Center";
          };
          mpris = {
            image-size = 96;
            image-radius = 7;
          };
          volume = {
            label = "󰕾";
          };
          backlight = {
            label = "󰃟";
          };
        };
      };
    };
  };
}
