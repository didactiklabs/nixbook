{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customNixOSModules.bluetoothAutoConnect;

  runtime = [
    pkgs.bluez
    pkgs.glib # gdbus
    pkgs.coreutils
    pkgs.gnugrep
  ];

  # Records the most recently connected Bluetooth *audio* device (speaker /
  # headset). Keyboards and mice reconnect by themselves, so they must not
  # replace the speaker as "the last device" when they wake up.
  remember = pkgs.writeShellApplication {
    name = "bt-autoconnect-remember";
    runtimeInputs = runtime;
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/bluetooth-autoconnect"
      mkdir -p "$state"

      record() {
        local mac="$1"
        [[ "$mac" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || return 0
        if bluetoothctl info "$mac" 2>/dev/null | grep -qE 'UUID: (Audio Sink|Headset|Handsfree)'; then
          printf '%s\n' "$mac" > "$state/last-audio-device.tmp"
          mv "$state/last-audio-device.tmp" "$state/last-audio-device"
          echo "remembered $mac"
        fi
      }

      # Already connected when we start (e.g. connected before login).
      while read -r _ mac _; do
        record "$mac"
      done < <(bluetoothctl devices Connected 2>/dev/null)

      gdbus monitor --system --dest org.bluez | while IFS= read -r line; do
        case "$line" in
        *"org.bluez.Device1"*"'Connected': <true>"*) ;;
        *) continue ;;
        esac
        path=''${line%%:*}
        mac=''${path##*/dev_}
        record "''${mac//_/:}"
      done
    '';
  };

  # Reconnects the remembered device at login. Retries for a while: the
  # speaker may be switched on after the laptop.
  reconnect = pkgs.writeShellApplication {
    name = "bt-autoconnect-reconnect";
    runtimeInputs = runtime;
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/bluetooth-autoconnect"
      [ -s "$state/last-audio-device" ] || { echo "no remembered device"; exit 0; }
      mac=$(head -n 1 "$state/last-audio-device")

      for _ in $(seq 1 ${toString cfg.attempts}); do
        if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
          info=$(bluetoothctl info "$mac" 2>/dev/null || true)
          if ! grep -q 'Paired: yes' <<<"$info"; then
            echo "$mac is no longer paired; giving up"
            exit 0
          fi
          if grep -q 'Connected: yes' <<<"$info"; then
            echo "$mac connected"
            exit 0
          fi
          bluetoothctl --timeout 10 connect "$mac" >/dev/null 2>&1 || true
        fi
        sleep ${toString cfg.interval}
      done
      echo "could not reach $mac"
    '';
  };
in
{
  options.customNixOSModules.bluetoothAutoConnect = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hardware.bluetooth.enable;
      defaultText = lib.literalExpression "config.hardware.bluetooth.enable";
      description = ''
        Remember the last connected Bluetooth audio device (speaker, headset)
        per user and reconnect to it automatically at login. A user service
        watches BlueZ on the system bus and records the most recently
        connected device exposing an Audio Sink / Headset profile
        (`~/.local/state/bluetooth-autoconnect/last-audio-device`); another
        one reconnects it after PipeWire is up, retrying for
        `attempts * interval` seconds (it needs the adapter powered —
        `hardware.bluetooth.powerOnBoot`, set per profile). BlueZ is also told
        to retry after a lost link.
      '';
    };
    attempts = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Reconnection attempts at login.";
    };
    interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Seconds between reconnection attempts.";
    };
  };

  config = lib.mkIf cfg.enable {
    # powerOnBoot is left to each profile (tanjiro/nishinoya keep the adapter
    # off at boot): the reconnect service simply waits for a powered adapter.
    hardware.bluetooth = {
      settings.Policy = {
        # Retry after a link loss (speaker briefly out of range).
        ReconnectAttempts = 7;
        ReconnectIntervals = "1,2,4,8,16,32,64";
      };
    };

    systemd.user.services = {
      bt-autoconnect-remember = {
        description = "Remember the last connected Bluetooth audio device";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          ExecStart = lib.getExe remember;
          Restart = "on-failure";
          RestartSec = 5;
          Slice = "background.slice";
        };
      };
      bt-autoconnect-reconnect = {
        description = "Reconnect the last Bluetooth audio device";
        wantedBy = [ "default.target" ];
        after = [
          "pipewire.service"
          "wireplumber.service"
        ];
        wants = [ "pipewire.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe reconnect;
          Slice = "background.slice";
        };
      };
    };
  };
}
