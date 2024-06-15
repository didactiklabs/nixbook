{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf (cfg.sway.enable || cfg.hyprland.enable) {
    programs.waybar.style = ''
      * {
        border: none;
        font-family: Hack Nerd Font;
        font-size: 12px;
        font-weight: bold;
      }

      #custom-separator {
        color: #abb2bf;
        margin: 0 1px;
      }

      #workspaces {
        background-color: #1e222a;
        margin: 1px 2px 2px 2px;
        border-radius: 10px;
        background-clip: padding-box;
      }

      #workspaces button {
        color: #abb2bf;
      }

      #workspaces button:first-child {
        padding-left: 10px;
      }

      #workspaces button:last-child {
        padding-right: 10px;
      }

      #workspaces button:hover {
        background-color: rgba(0, 0, 0, 0.2)
      }

      #workspaces button.focused {
        color: #1DB954;
        background-color: #12151d;
      }

      #workspaces button.urgent {
        color: #e06c75;
      }

      window#waybar {
        background-color: #12151d;
        border-bottom: 3px solid #12151d;
        color: #abb2bf;
        transition-property: background-color;
        transition-duration: .5s;
      }

      window#waybar.hidden {
        opacity: 0.2;
      }

      #mode {
        color: #12151d;
        background-color: #e06c75;
        padding: 0 10px;
        margin: 1px 2px 2px 2px;
        border-radius: 10px;
        background-clip: padding-box;
      }

      #custom-spotify {
        padding: 0 10px;
        margin: 1px 2px 2px 2px;
        border-radius: 10px;
        background-color: #1e222a;
      }

      #custom-spotify.Playing {
          color: #1DB954;
      }

      #custom-spotify.Paused {
          color: #e06c75;
      }

      #window,
      #temperature,
      #cpu,
      #memory,
      #disk,
      #network,
      #battery {
        background-color: #12151d;
        padding: 0 3px;
        margin: 1px;
        border: 1px solid #12151d;
      }

      #clock {
        padding: 0 10px;
        margin: 1px 2px 2px 2px;
        border-radius: 10px;
        background-color: #1e222a;
        color: #c678dd;
      }

      #window {
        background-color: #12151d;
      }

      #temperature {
        color: #61afef;
      }
      #temperature.critical {
        background-color: #e06c75;
        color: #1e222a;
      }

      #cpu {
        color: #d19a66;
      }

      #memory {
        color: #d19a66;
      }

      #disk {
        color: #d19a66;
      }

      #battery {
        color: #1DB954;
      }
      #battery.charging {
        background-color: #1e222a;
        color: #61afef
      }
      #battery.plugged {
        background-color: #1e222a;
        color: #1DB954;
      }
      #battery.critical:not(.charging) {
        background-color: #e06c75;
        color: #1e222a;
        animation-name: blink;
        animation-duration: 0.5s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
      }

      #network {
        color: #1DB954
      }
      #network.disconnected {
        background-color: #e06c75;
        color: #1e222a;
      }

      #pulseaudio,
      #idle_inhibitor,
      #custom-print,
      #tray {
        margin: 1px 0;
        padding: 0 5px;
        background-color: #1e222a;
      }

      #pulseaudio {
        margin-left: 1px;
        border-top-left-radius: 10px;
        border-bottom-left-radius: 10px;
      }
      #pulseaudio.muted {
        background-color: #1e222a;
        color: #e06c75;
      }

      #idle_inhibitor,
      #custom-print {
        padding-left: 9px;
        padding-right: 9px;
      }

      #idle_inhibitor.activated {
        background-color: #1e222a;
        color: #abb2bf;
      }
      #idle_inhibitor.deactivated {
        background-color: #1e222a;
        color: #e06c75;
      }

      #tray {
        margin-right: 1px;
        border-top-right-radius: 10px;
        border-bottom-right-radius: 10px;
      }
      #tray > .needs-attention {
        background-color: #e06c75;
      }
    '';
  };
}
