{
  pkgs,
  lib,
  ...
}: let
  volume = pkgs.writeShellScriptBin "volume" ''
      #!/bin/bash

    # ░█▀▀▄░█▀▀░▄▀▀▄░█▀▄▀█░░▀░░█░▄░█▀▀▄░█▀▀█░█▀▀▄░░   volume changer!
    # ░█░▒█░█▀▀░█░░█░█░▀░█░░█▀░█▀▄░█▄▄▀░█▄▀█░█░▒█░░   v0.9 TODO: consolidate notifications,
    # ░▀░░▀░▀▀▀░░▀▀░░▀░░▒▀░▀▀▀░▀░▀░▀░▀▀░█▄▄█░▀░░▀░░   what about a single notify function.
    # original found on Reddit by: JaKooLit
    # https://github.com/JaKooLit/Ja_HyprLanD-dots/blob/main/config/hypr/scripts/volume

    iDIR="$HOME/.config/assets/images/volume-icons"
    play="${pkgs.libcanberra-gtk3}/bin/canberra-gtk-play -i audio-volume-change"
    # any of those will work:
    # "canberra-gtk-play -i audio-volume-change"
    # "play --volume 0.15 $HOME/.config/hypr/sounds/volume_notif.wav"

    # Get Volume
    get_volume() {
      volume=$(${pkgs.pamixer}/bin/pamixer --get-volume)
      echo "$volume"
    }

    # Get icons
    get_icon() {
      current=$(get_volume)
      if [[ "$current" -eq "0" ]]; then
        echo "$iDIR/volume-mute.png"
      elif [[ ("$current" -ge "0") && ("$current" -le "30") ]]; then
        echo "$iDIR/volume-low.png"
      elif [[ ("$current" -ge "30") && ("$current" -le "60") ]]; then
        echo "$iDIR/volume-mid.png"
      elif [[ ("$current" -ge "60") && ("$current" -le "100") ]]; then
        echo "$iDIR/volume-high.png"
      elif [[ ("$current" -ge "100") && ("$current" -le "130") ]]; then
        echo "$iDIR/volume-veryhigh.png"
      elif [[ ("$current" -ge "130") && ("$current" -le "200") ]]; then
        echo "$iDIR/volume-danger.png"
      fi
    }

    # Get urgency
    get_urgency() {
      current=$(get_volume)
      if [[ "$current" -eq "0" ]]; then
        echo "low"
      elif [[ ("$current" -ge "0") && ("$current" -le "100") ]]; then
        echo "low"
      elif [[ ("$current" -ge "100") && ("$current" -le "130") ]]; then
        echo "normal"
        elif [[ ("$current" -ge "130") && ("$current" -le "200") ]]; then
        echo "critical"
      fi
    }

    # Notify
    notify_user() {
      ${pkgs.libnotify}/bin/notify-send -e -h string:x-canonical-private-synchronous:sys-notify -u "$(get_urgency)" -i "$(get_icon)" -t 555 -h  int:value:"$(get_volume)" "    Volume : $(get_volume)%"
    }

    # Increase Volume
    inc_volume() {
      ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 3%+ && notify_user && $play
    # pamixer -i 5 && notify_user && $play    # an alternative to pactl, doesn't go beyond 100% tho
    }

    # Decrease Volume
    dec_volume() {
      ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 3%- && notify_user && $play
      # pamixer -d 5 && notify_user && $play  # an alternative to pactl, doesn't go beyond 100% tho
    }

    # Toggle AUDIO Mute
    toggle_mute() {
      if [ "$(${pkgs.pamixer}/bin/pamixer --get-mute)" == "false" ]; then
        ${pkgs.pamixer}/bin/pamixer -m && notify-send -h string:x-canonical-private-synchronous:sys-notify-audio -u low -i "$iDIR/volume-mute.png" "Volume Switched OFF"
      elif [ "$(${pkgs.pamixer}/bin/pamixer --get-mute)" == "true" ]; then
        ${pkgs.pamixer}/bin/pamixer -u && notify-send -h string:x-canonical-private-synchronous:sys-notify-audio -u low -i "$(get_icon)" "Volume Switched ON" && $play
      fi
    }

    # Toggle MIC Mute
    toggle_mic() {
      if ${pkgs.wireplumber}/bin/wpctl list sources | grep -q "Mute: yes"; then
        # If microphone is muted, unmute it and send a notification
        ${pkgs.wireplumber}/bin/wpctl set-source-mute @DEFAULT_SOURCE@ toggle
        ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:sys-notify-mic -u low -i "$iDIR/microphone.png" "Microphone Switched ON" && $play
      else
        # If microphone is not muted, mute it and send a notification
        ${pkgs.wireplumber}/bin/wpctl set-source-mute @DEFAULT_SOURCE@ toggle
        ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:sys-notify-mic -u low -i "$iDIR/microphone-mute.png" "Microphone Switched OFF"
      fi
      # PAMIXER ALTERNATIVE:
      # if [ "$(pamixer --source 66 --get-mute)" == "false" ]; then
      #   pamixer -m --source 66 && notify-send -h string:x-canonical-private-synchronous:sys-notify -u low -i "$iDIR/microphone-mute.png" "Microphone Switched OFF"
      # elif [ "$(pamixer --source 66 --get-mute)" == "true" ]; then
      #   pamixer -u --source 66 && notify-send -h string:x-canonical-private-synchronous:sys-notify -u low -i "$iDIR/microphone.png" "Microphone Switched ON"
      # fi
    }

    # Execute accordingly
    if [[ "$1" == "--get" ]]; then
      get_volume
    elif [[ "$1" == "--inc" ]]; then
      inc_volume
    elif [[ "$1" == "--dec" ]]; then
      dec_volume
    elif [[ "$1" == "--toggle" ]]; then
      toggle_mute
    elif [[ "$1" == "--toggle-mic" ]]; then
      toggle_mic
    elif [[ "$1" == "--get-icon" ]]; then
      get_icon
    elif [[ "$1" == "--notify" ]]; then
      notify_user
    else
      get_volume & notify_user
    fi
  '';
in {
  home.packages = [
    volume
  ];
  home.file.".config/assets/images/volume-icons".source = ../../assets/images/volume-icons;
  wayland.windowManager.hyprland.settings = {
    bindle = [
      ",XF86AudioRaiseVolume, exec, ${volume}/bin/volume --inc"
      ",XF86AudioLowerVolume, exec, ${volume}/bin/volume --dec"
    ];
    bindl = [
      ",XF86AudioMute, exec, ${volume}/bin/volume --toggle"
    ];
  };
  wayland.windowManager.sway.config.keybindings = lib.filterAttrsRecursive (name: value: value != null) {
    # Volume
    "--locked XF86AudioRaiseVolume" = "exec ${volume}/bin/volume --inc";
    "--locked XF86AudioLowerVolume" = "exec ${volume}/bin/volume --dec";
    "--locked XF86AudioMute" = "exec ${volume}/bin/volume --toggle";
  };
}