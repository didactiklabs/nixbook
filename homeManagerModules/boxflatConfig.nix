{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.boxflatConfig;

  mkPreset = name: data: pkgs.writeText "${name}.yml" (builtins.toJSON data);

  # --- Assetto Corsa Competizione ---
  # Moza R9 (9 Nm). ACC provides high-fidelity physics FFB, so the base
  # stays transparent: zero spring/damper/friction/inertia on the wheelbase
  # side, let the sim drive everything through PIDFF.
  #
  # Recommended in-game ACC FFB settings to pair with this preset:
  #   Gain:            70-80%
  #   Min force:       5%
  #   Dynamic damping: 60%
  #   Road effects:    25%
  accPreset = {
    BoxflatPresetVersion = "1";
    linked-process = "acc.exe";
    main = {
      set-interpolation = 1;
      set-spring-gain = 100;
      set-damper-gain = 100;
      set-inertia-gain = 100;
      set-friction-gain = 100;
    };
    base = {
      limit = 1;
      max-angle = 900;
      ffb-strength = 75;
      road-sensitivity = 50;
      speed = 100;
      spring = 0;
      damper = 0;
      torque = 100;
      inertia = 0;
      friction = 0;
      protection = 50;
      protection-mode = 0;
      natural-inertia = 15;
      speed-damping = 0;
      speed-damping-point = 0;
      soft-limit-stiffness = 50;
      soft-limit-strength = 100;
      soft-limit-retain = 5;
      equalizer1 = 50;
      equalizer2 = 50;
      equalizer3 = 50;
      equalizer4 = 50;
      equalizer5 = 50;
      equalizer6 = 50;
      ffb-curve-y1 = 20;
      ffb-curve-y2 = 40;
      ffb-curve-y3 = 60;
      ffb-curve-y4 = 80;
      ffb-curve-y5 = 100;
      ffb-reverse = 0;
      ffb-curve-x1 = 0;
    };
  };

  # --- Assetto Corsa (AC1) ---
  # Moza R9 (9 Nm). AC1 has strong, detailed FFB but its default signal can
  # clip on a 9 Nm base. Slightly lower FFB strength than ACC to avoid
  # saturation with heavy cars/mods. AC1 benefits from a touch of filtering
  # since its FFB can be spiky with certain cars and track mods.
  #
  # Recommended in-game AC FFB settings to pair with this preset:
  #   Gain:              70%
  #   Filter:            0%
  #   Min force:         8%
  #   Kerb effect:       15%
  #   Road effect:       20%
  #   Slip effect:       0%
  #   Enhanced understeer: on
  acPreset = {
    BoxflatPresetVersion = "1";
    linked-process = "acs.exe";
    main = {
      set-interpolation = 1;
      set-spring-gain = 100;
      set-damper-gain = 100;
      set-inertia-gain = 100;
      set-friction-gain = 100;
    };
    base = {
      limit = 1;
      max-angle = 900;
      ffb-strength = 70;
      road-sensitivity = 40;
      speed = 100;
      spring = 0;
      damper = 3;
      torque = 100;
      inertia = 0;
      friction = 3;
      protection = 50;
      protection-mode = 0;
      natural-inertia = 10;
      speed-damping = 0;
      speed-damping-point = 0;
      soft-limit-stiffness = 50;
      soft-limit-strength = 100;
      soft-limit-retain = 5;
      equalizer1 = 50;
      equalizer2 = 50;
      equalizer3 = 50;
      equalizer4 = 50;
      equalizer5 = 50;
      equalizer6 = 50;
      ffb-curve-y1 = 20;
      ffb-curve-y2 = 40;
      ffb-curve-y3 = 60;
      ffb-curve-y4 = 80;
      ffb-curve-y5 = 100;
      ffb-reverse = 0;
      ffb-curve-x1 = 0;
    };
  };

  # --- Forza Horizon 6 ---
  # Moza R9 (9 Nm). Forza Horizon is arcade/simcade with aggressive, noisy
  # FFB. The base adds filtering and centering to smooth the experience,
  # with a slightly compressed FFB curve so subtle effects aren't lost.
  #
  # Recommended in-game Forza Horizon FFB settings to pair with this preset:
  #   Vibration scale:      50%
  #   FFB scale:            70%
  #   Steering sensitivity: 50 (centre deadzone 0, outer deadzone 100)
  #   Wheel damper scale:   0%  (handled by wheelbase)
  fhPreset = {
    BoxflatPresetVersion = "1";
    linked-process = "ForzaHorizon6.exe";
    main = {
      set-interpolation = 1;
      set-spring-gain = 100;
      set-damper-gain = 80;
      set-inertia-gain = 100;
      set-friction-gain = 80;
    };
    base = {
      limit = 1;
      max-angle = 540;
      ffb-strength = 60;
      road-sensitivity = 30;
      speed = 100;
      spring = 10;
      damper = 10;
      torque = 100;
      inertia = 5;
      friction = 5;
      protection = 50;
      protection-mode = 0;
      natural-inertia = 5;
      speed-damping = 10;
      speed-damping-point = 50;
      soft-limit-stiffness = 50;
      soft-limit-strength = 100;
      soft-limit-retain = 5;
      equalizer1 = 50;
      equalizer2 = 55;
      equalizer3 = 60;
      equalizer4 = 55;
      equalizer5 = 50;
      equalizer6 = 50;
      ffb-curve-y1 = 25;
      ffb-curve-y2 = 48;
      ffb-curve-y3 = 68;
      ffb-curve-y4 = 85;
      ffb-curve-y5 = 100;
      ffb-reverse = 0;
      ffb-curve-x1 = 0;
    };
  };
in
{
  options.customHomeManagerModules.boxflatConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Boxflat presets for Moza Racing wheelbases.

        Boxflat is the Linux configuration tool for Moza Racing hardware
        (alternative to Pit House). This module places game-specific FFB
        presets into ~/.config/boxflat/presets/ tuned for the Moza R9 (9 Nm):

          - r9-ac.yml — Assetto Corsa (realistic, slight filtering for spiky FFB)
          - r9-acc.yml — Assetto Corsa Competizione (realistic, transparent FFB)
          - r9-forza-horizon.yml — Forza Horizon 6 (arcade, filtered/smoothed)

        Presets auto-load when the linked game process is detected.
        They are read-only Nix store symlinks; edit this module to change them.
        Presets created through Boxflat's UI live alongside these unaffected.

        Requires customNixOSModules.simracing.enable = true on the machine.
        Used on: anya.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = {
      ".config/boxflat/presets/r9-ac.yml".source = mkPreset "r9-ac" acPreset;
      ".config/boxflat/presets/r9-acc.yml".source = mkPreset "r9-acc" accPreset;
      ".config/boxflat/presets/r9-forza-horizon.yml".source = mkPreset "r9-forza-horizon" fhPreset;

      # XDG autostart: launch boxflat hidden in background on login so the
      # ProcessObserver can auto-load presets when a linked game starts.
      ".config/autostart/boxflat.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Boxflat
        Exec=boxflat --autostart
        X-GNOME-Autostart-enabled=true
      '';
    };

    # Stamp settings.yml so boxflat:
    #   - stops showing the "update udev rules" dialog (rules-version >= 2)
    #   - starts hidden and stays alive after window close (background + autostart-hidden)
    home.activation.boxflatSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings_file="''${XDG_CONFIG_HOME:-$HOME/.config}/boxflat/settings.yml"
      mkdir -p "$(dirname "$settings_file")"
      touch "$settings_file"

      stamp_setting() {
        if ${lib.getExe pkgs.gnugrep} -q "^$1:" "$settings_file" 2>/dev/null; then
          ${lib.getExe pkgs.gnused} -i "s/^$1:.*/$1: $2/" "$settings_file"
        else
          echo "$1: $2" >> "$settings_file"
        fi
      }

      stamp_setting "rules-version" "2"
      stamp_setting "background" "1"
      stamp_setting "autostart-hidden" "1"
    '';
  };
}
