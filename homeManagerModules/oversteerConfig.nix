{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.oversteerConfig;

  # Oversteer profiles are Python configparser INI files with a single
  # implicit [DEFAULT] section. Profiles are name-based and device-agnostic
  # (no USB id is stored inside the file); they are applied by name via
  # `oversteer -p <name> --apply`.
  #
  # Key reference (oversteer/model.py):
  #   range          : wheel rotation in degrees (40–1080)
  #   ff_gain        : overall FFB gain, 0–100 (%) — sysfs gain
  #   autocenter     : autocenter strength, 0–100 (%) — MUST be 0 for direct drive
  #   spring_level   : 0–100 (%)
  #   damper_level   : 0–100 (%)
  #   friction_level : 0–100 (%)
  #   combine_pedals : 0 = none, 1 = brakes, 2 = clutch
  #   ffb_leds       : 0/1 — FFBmeter RPM/clip LEDs on the wheel
  #   mode           : wheel emulation/compat mode id
  # Booleans are serialized as 0/1.
  mkProfile =
    data:
    lib.generators.toINI { } {
      DEFAULT = builtins.mapAttrs (_: v: if builtins.isBool v then (if v then 1 else 0) else v) data;
    };

  # ---------------------------------------------------------------------------
  # Assetto Corsa Competizione — Fanatec CSL DD / GT DD Pro
  # ---------------------------------------------------------------------------
  # NOTE: oversteer can only set the wheel range, overall FFB gain, autocenter,
  # combine-pedals and the spring/damper/friction *levels* exposed by the
  # kernel hid-fanatec/PIDFF driver. The detailed Fanatec base tune
  # (FFB strength, NDP, NFR, NIN, FEI, FOR, SPR, DPR) lives in the wheelbase
  # firmware and is set on the base/wheel OLED tuning menu — there is no Linux
  # tool (and no foxblat equivalent) that writes those over a config file.
  #
  # ACC settings to set in-game (Options → Controls):
  #   Gain 100, Min Force 0–4%, Dynamic Damping ~100, Road Effects to taste.
  #   CSL Pedals have a potentiometer brake (no load cell) — calibrate the
  #   brake in ACC (Calibration) and adjust brake gamma to taste; there is no
  #   load-cell pressure curve to set.
  # Recommended OLED tuning menu starting point for a CSL DD on ACC:
  #   SEN 900 (or AUT), FFB 100, NDP 30, NFR 0, NIN OFF, INT 1–3, FEI 100.
  accProfile = {
    # ACC applies per-car steering lock internally, so run the base at its
    # full 900° range and let the game scale it per car.
    range = 900;
    # Leave overall gain at 100 here; do final strength on the OLED FFB / FOR
    # setting and ACC's in-game Gain to avoid double-attenuation.
    ff_gain = 100;
    # Direct drive: autocenter MUST be off — the game/physics provides the
    # centering force. Any hardware autocenter fights the FFB signal.
    autocenter = 0;
    # Mechanical effect levels — kept neutral; CSL DD prefers minimal added
    # spring/friction so the road signal stays clean.
    spring_level = 100;
    damper_level = 100;
    friction_level = 0;
    # CSL Pedals: potentiometer brake (no load cell), presented as their own
    # axes — keep combine_pedals = 0 (combining is only a workaround for
    # single-axis wheels). Brake feel/calibration on CSL Pedals is done in ACC
    # (brake calibration + gamma), not via oversteer.
    combine_pedals = 0;
    # RPM/clip LED strip on the wheel.
    ffb_leds = 1;
  };
in
{
  options.customHomeManagerModules.oversteerConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to deploy Oversteer wheel profiles for Fanatec hardware.

        Oversteer is the Linux steering-wheel manager (rotation range, overall
        FFB gain, autocenter, combine-pedals, spring/damper/friction levels)
        that talks to the kernel hid-fanatec / universal-pidff driver. This
        module ships a game profile into ~/.config/oversteer/profiles/ tuned
        for the Fanatec CSL DD / GT DD Pro:

          - acc.ini — Assetto Corsa Competizione (900° base range, autocenter
            off for direct drive, neutral mechanical effects)

        IMPORTANT: Oversteer (and Linux in general) cannot set the detailed
        Fanatec base tune — FFB strength, NDP/NFR/NIN/FEI, etc. Those live in
        the wheelbase firmware and must be set on the base/wheel OLED tuning
        menu. This is the key difference from Moza, where foxblat can push the
        full base tune declaratively. So there is no full ACC FFB preset here,
        only the oversteer-level settings.

        An XDG autostart entry applies the ACC profile on login. Profiles can
        also be applied manually at any time with:
          oversteer -p acc --apply

        Requires customNixOSModules.simracing.enable = true on the machine
        (which installs oversteer and the Fanatec udev rules).
        Used on: hanamichi.
        Reference: https://github.com/berarma/oversteer
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = {
      ".config/oversteer/profiles/acc.ini".text = mkProfile accProfile;

      # XDG autostart: apply the ACC profile on login so the wheel is set up
      # without opening the oversteer GUI. --apply applies the named profile to
      # the connected wheel and exits.
      ".config/autostart/oversteer-acc.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Oversteer (apply ACC profile)
        Exec=${lib.getExe pkgs.oversteer} -p acc --apply
        X-GNOME-Autostart-enabled=true
      '';
    };
  };
}
