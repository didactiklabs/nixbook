{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.foxblatConfig;

  mkPreset = name: data: pkgs.writeText "${name}.yml" (builtins.toJSON data);

  # ---------------------------------------------------------------------------
  # Wire format reference (values in YAML are raw wire values sent to hardware)
  # ---------------------------------------------------------------------------
  # base-ffb-strength    : UI% = wire / 10       → 75% UI = 750 wire
  # base-damper          : UI% = wire / 10       → 40% UI = 400 wire
  # base-friction        : UI% = wire / 10       → 25% UI = 250 wire
  # base-inertia         : UI  = wire / 10       → 250 UI = 2500 wire (range 100–500 UI)
  # base-speed           : UI% = wire / 10       → 100% UI = 1000 wire
  # base-spring          : UI% = wire / 10       → 0% UI = 0 wire
  # base-natural-inertia : 1:1 wire = UI         → default 1100 (KS/GS mark), range 100–4000
  # base-speed-damping   : 1:1 wire = UI%        → 0% = 0, set to 0 for always-on
  # base-speed-damping-point : 1:1 wire = kph    → 0 = always active
  # base-road-sensitivity: 1:1 (raw 50 ≈ UI 10) → keep 50
  # base-torque          : 1:1                   → 100 = 100%
  # base-protection      : 0 or 1 switch         → 0 = off
  # base-protection-mode : 0-indexed             → 0 = mode 1
  # base-soft-limit-stiffness : complex          → UI 5 (mid) ≈ wire 278
  # base-soft-limit-strength  : complex toggle   → wire 78 = "Middle"
  # base-soft-limit-retain    : switch           → 0 = off
  # base-equalizer1–6    : 1:1, range 100–400    → 100 = neutral (flat)
  # base-ffb-curve-y1–5  : 1:1 %                → linear = [20,40,60,80,100]
  # base-ffb-curve-x1    : inverted mapping      → 0 = no deadzone
  # main-set-*-gain      : UI% = wire / 2.55     → 100% UI = 255 wire, 50% UI = 128 wire

  # ---------------------------------------------------------------------------
  # Shared pedal sections (sim vs arcade)
  # ---------------------------------------------------------------------------
  # Pedal values are all 1:1 (0–100 range, no wire conversion needed).
  # brake-angle-ratio: 0 = angle-only, 100 = load-cell-only.
  # Curves: y1–y5 are the response curve at the 5 equidistant input points.
  #   Linear:      [20, 40, 60, 80, 100]
  #   Progressive: [ 8, 20, 42, 70, 100]  (soft initial, firm end — sim brake feel)
  #   Exponential: [ 6, 14, 28, 54, 100]  (very late response)

  simPedals = {
    # Throttle: linear — precision is critical in sim racing
    throttle-dir = 0;
    throttle-min = 0;
    throttle-max = 100;
    throttle-y1 = 20;
    throttle-y2 = 40;
    throttle-y3 = 60;
    throttle-y4 = 80;
    throttle-y5 = 100;
    # Brake: progressive/parabolic — simulates load-cell pedal feel where
    # initial travel is light and final quarter is firm. Heavy load-cell bias.
    brake-dir = 0;
    brake-angle-ratio = 80;
    brake-min = 0;
    brake-max = 100;
    brake-y1 = 8;
    brake-y2 = 20;
    brake-y3 = 42;
    brake-y4 = 70;
    brake-y5 = 100;
    # Clutch: linear
    clutch-dir = 0;
    clutch-min = 0;
    clutch-max = 100;
    clutch-y1 = 20;
    clutch-y2 = 40;
    clutch-y3 = 60;
    clutch-y4 = 80;
    clutch-y5 = 100;
  };

  # ---------------------------------------------------------------------------
  # Assetto Corsa Competizione  (Pit House R9-ACC-Official2 preset)
  # ---------------------------------------------------------------------------
  # Imported from a Pit House preset export (id e483b0fc-421a-42f0-b9f1-589227d2b4db,
  # lastModified 2025-12-08). Conversion performed manually using foxblat's
  # PithouseConverter logic (foxblat/pithouse_converter.py) so the values match
  # what foxblat itself would produce if you imported the JSON via its UI.
  #
  # Converter rules used (Pit House field → foxblat YAML key):
  #   maximumSteeringAngle        → max-angle, limit    (raw — foxblat slider /2; 450 = 900°)
  #   gameForceFeedbackStrength   → ffb-strength * 10
  #   gameForceFeedbackReversal   → ffb-reverse (bool → 0/1)
  #   mechanicalDamper            → damper    * 10
  #   mechanicalFriction          → friction  * 10
  #   mechanicalSpringStrength    → spring    * 10
  #   maximumSteeringSpeed        → speed     * 10
  #   maximumTorque               → torque    (1:1)
  #   naturalInertiaV2            → inertia   * 10
  #   safeDrivingEnabled          → protection (bool → 0/1)
  #   safeDrivingMode             → protection-mode (0-indexed: 2 = Mode 3)
  #   speedDependentDamping       → speed-damping
  #   initialSpeedDependentDamping→ speed-damping-point
  #   softLimitStiffness          → soft-limit-stiffness
  #   softLimitStrength           → soft-limit-strength
  #   softLimitGameForceStrength  → soft-limit-retain
  #   equalizerGain1–6            → equalizer1–6 (1:1; 100 = neutral, <100 attenuates)
  #   setGame*Value               → set-*-gain (× 2.55, clamped to 255)
  #   constForceExtraMode         → set-interpolation
  #   forceFeedbackMaping (12-byte string) → ffb-curve-{x1,y1..y5} (bytes 2,3,5,7,9,11)
  #
  # Pit House JSON has no equivalent for `natural-inertia` (UI 100–4000 slider) or
  # `road-sensitivity` — converter writes 0 for both.
  # `linked-process` and `pedals` aren't part of Pit House exports — kept as before.
  accPreset = {
    FoxblatPresetVersion = "1";
    linked-process = "acc.exe";
    main = {
      set-interpolation = 100; # constForceExtraMode
      set-spring-gain = 0; # 0% — wheel goes fully limp on ACC pause/menu
      set-damper-gain = 255; # setGameDampingValue 100 × 2.55
      set-inertia-gain = 255; # setGameInertiaValue 100 × 2.55
      set-friction-gain = 255; # setGameFrictionValue 100 × 2.55
    };
    base = {
      limit = 450; # maximumSteeringAngle (= 900° on wheel; slider divides by 2)
      max-angle = 450;
      ffb-strength = 650; # 65% — reduced from 85% for gentler overall FFB
      road-sensitivity = 0; # not in Pit House export
      speed = 1600; # maximumSteeringSpeed 160 × 10
      spring = 0; # mechanicalSpringStrength
      damper = 400; # mechanicalDamper 40 × 10
      torque = 80; # 80% — hard cap to limit peak torque on R9
      inertia = 1500; # naturalInertiaV2 150 × 10
      friction = 300; # mechanicalFriction 30 × 10 — above R9 200 anti-oscillation floor
      protection = 1; # safeDrivingEnabled
      protection-mode = 2; # safeDrivingMode (0-indexed = Mode 3)
      natural-inertia = 0; # not in Pit House export
      speed-damping = 50; # speedDependentDamping
      speed-damping-point = 75; # initialSpeedDependentDamping
      soft-limit-stiffness = 100; # softLimitStiffness
      soft-limit-strength = 78; # softLimitStrength
      soft-limit-retain = 20; # softLimitGameForceStrength
      equalizer1 = 100; # equalizerGain1
      equalizer2 = 100; # equalizerGain2
      equalizer3 = 100; # equalizerGain3
      equalizer4 = 70; # equalizerGain4 (attenuates)
      equalizer5 = 50; # equalizerGain5 (attenuates)
      equalizer6 = 40; # equalizerGain6 (attenuates)
      # forceFeedbackMaping "  \b\f (4<JP d" decoded by char index
      ffb-curve-x1 = 8; # byte 2 = \b
      ffb-curve-y1 = 12; # byte 3 = \f
      ffb-curve-y2 = 40; # byte 5 = '('
      ffb-curve-y3 = 60; # byte 7 = '<'
      ffb-curve-y4 = 80; # byte 9 = 'P'
      ffb-curve-y5 = 100; # byte 11 = 'd'
      ffb-reverse = 0; # gameForceFeedbackReversal
    };
    pedals = simPedals;
  };

  # ---------------------------------------------------------------------------
  # Assetto Corsa (AC1)  — derived from the new ACC preset
  # ---------------------------------------------------------------------------
  # Mostly mirrors the Pit House-imported ACC preset above. AC1 differences:
  #   - AC1 sends damper/friction effects itself, so set-damper-gain is reduced
  #     (50%) and set-friction-gain is reduced (25%); set-inertia-gain = 0
  #     because AC1 models inertia internally.
  #   - set-interpolation = 0 (off) — AC1's signal is detailed and clean, so
  #     keep it raw (vs. ACC's 100).
  #   - ffb-strength = 90% (typical AC1 guidance) vs ACC's 85%.
  #   - EQ kept flat — ACC's high-frequency rolloff is for that title's whine
  #     profile, not generally applicable.
  acPreset = {
    FoxblatPresetVersion = "1";
    linked-process = "acs.exe";
    main = {
      set-interpolation = 0; # AC1 detail worth preserving
      set-spring-gain = 0; # 0% — wheel goes fully limp on pause/menu
      set-damper-gain = 128; # 50% — AC1 sends own damper effects
      set-inertia-gain = 0; # AC1 models inertia internally
      set-friction-gain = 64; # 25% — small friction amplification
    };
    base = {
      limit = 450; # = 900° (slider /2)
      max-angle = 450;
      ffb-strength = 700; # 70% — reduced from 90% for gentler overall FFB
      road-sensitivity = 0;
      speed = 1600; # 160% (carry from ACC)
      spring = 0;
      damper = 400; # 40% (carry from ACC)
      torque = 80; # 80% — hard cap to limit peak torque on R9
      inertia = 1500; # 150% (carry from ACC)
      friction = 300; # 30% — above R9 200 anti-oscillation floor
      protection = 1;
      protection-mode = 2; # Mode 3 (Pit House preference)
      natural-inertia = 0; # not in Pit House export
      speed-damping = 50; # (carry from ACC)
      speed-damping-point = 75;
      soft-limit-stiffness = 100;
      soft-limit-strength = 78;
      soft-limit-retain = 20;
      equalizer1 = 100; # AC1's spectrum is cleaner than ACC — flat EQ
      equalizer2 = 100;
      equalizer3 = 100;
      equalizer4 = 100;
      equalizer5 = 100;
      equalizer6 = 100;
      ffb-curve-x1 = 8; # carry ACC FFB curve (small-input smoothing)
      ffb-curve-y1 = 12;
      ffb-curve-y2 = 40;
      ffb-curve-y3 = 60;
      ffb-curve-y4 = 80;
      ffb-curve-y5 = 100;
      ffb-reverse = 0;
    };
    pedals = simPedals;
  };

  # ---------------------------------------------------------------------------
  # Cyberpunk 2077 + cp2077-wheel-mod-moza (natpoh/cp2077-wheel-mod-moza)
  # ---------------------------------------------------------------------------
  # FFB is entirely mod-generated — the game itself sends no wheel effects.
  # The mod (a RED4ext plugin running at 250 Hz) computes and dispatches:
  #
  #   Spring   — physics-derived centering torque, scales with speed.
  #              Cornering feedback stiffens the spring during turns.
  #   Damper   — road-texture resistance ("friction force" slider in mod),
  #              scales with speed.
  #   ConstantForce — active torque / slip-angle countersteer push-back.
  #   Sine     — 25 Hz road-surface buzz from suspension activity.
  #   Jolt     — transient constant-force pulse on collision.
  #
  # Because the mod owns all FFB at 250 Hz, wheelbase mechanical effects
  # that would fight or duplicate it are zeroed:
  #   base spring = 0   — mod's centering spring is the sole spring source.
  #   set-inertia-gain = 0   — mod sends no DirectInput inertia effect.
  #   set-friction-gain = 0  — mod sends no DirectInput friction effect.
  #   set-interpolation = 0  — mod signal is 250 Hz; no smoothing needed.
  #
  # The mod recommends 720° wheel operating range in Pit House.
  # foxblat slider is degrees / 2, so limit = max-angle = 360.
  #
  # `set-spring-gain` and `set-damper-gain` are passed through at full
  # resolution (255) so the mod's computed torques reach the hardware
  # without attenuation. Tune the mod's in-game sliders instead:
  #   FFB strength, Cornering feedback, Friction force, Road vibration,
  #   Collision jolt — all adjustable in Main Menu → Mod Settings.
  #
  # Base `damper` = 200 (20%) provides the R9 anti-oscillation floor on
  # top of the mod's own damper channel; base `friction` = 300 (30%) is
  # the standard R9 floor to prevent free-wheeling.
  # `torque` = 80 is the standard R9 hard torque cap.
  # EQ is flat — the mod's 250 Hz signal has no title-specific whine.
  cp2077Preset = {
    FoxblatPresetVersion = "1";
    linked-process = "Cyberpunk2077.exe";
    main = {
      set-interpolation = 0; # mod pumps at 250 Hz — signal is clean, no smoothing needed
      set-spring-gain = 255; # 100% — mod's centering/cornering spring; pass through fully
      set-damper-gain = 255; # 100% — mod's road friction channel; pass through fully
      set-inertia-gain = 0; # mod sends no DirectInput inertia effect
      set-friction-gain = 0; # mod sends no DirectInput friction effect
    };
    base = {
      limit = 360; # = 720° (slider /2) — mod-recommended operating range
      max-angle = 360;
      ffb-strength = 650; # 65% — tune mod's in-game sliders for per-effect strength
      road-sensitivity = 0;
      speed = 1600; # 160% — carry from ACC; adequate for open-world driving speeds
      spring = 0; # mod owns centering spring; zero hardware spring to avoid fighting
      damper = 200; # 20% — R9 anti-oscillation floor on top of mod's damper
      torque = 80; # 80% — standard R9 hard torque cap
      inertia = 1500; # 150% — carry from ACC for baseline wheel mass feel
      friction = 300; # 30% — standard R9 anti-oscillation friction floor
      protection = 1;
      protection-mode = 2; # Mode 3
      natural-inertia = 0;
      speed-damping = 50;
      speed-damping-point = 75;
      soft-limit-stiffness = 100;
      soft-limit-strength = 78;
      soft-limit-retain = 20;
      equalizer1 = 100; # flat EQ — mod's 250 Hz signal has no title-specific whine
      equalizer2 = 100;
      equalizer3 = 100;
      equalizer4 = 100;
      equalizer5 = 100;
      equalizer6 = 100;
      ffb-curve-x1 = 8; # small-input smoothing (carry from ACC)
      ffb-curve-y1 = 12;
      ffb-curve-y2 = 40;
      ffb-curve-y3 = 60;
      ffb-curve-y4 = 80;
      ffb-curve-y5 = 100;
      ffb-reverse = 0;
    };
    pedals = {
      # Throttle: deadzone + steep start to prevent idle creep
      throttle-dir = 0;
      throttle-min = 0;
      throttle-max = 100;
      throttle-y1 = 4;
      throttle-y2 = 14;
      throttle-y3 = 36;
      throttle-y4 = 68;
      throttle-y5 = 100;
      # Brake: deadzone + steep start to prevent phantom braking
      brake-dir = 0;
      brake-angle-ratio = 40;
      brake-min = 0;
      brake-max = 100;
      brake-y1 = 4;
      brake-y2 = 14;
      brake-y3 = 36;
      brake-y4 = 68;
      brake-y5 = 100;
      # Clutch: linear
      clutch-dir = 0;
      clutch-min = 0;
      clutch-max = 100;
      clutch-y1 = 20;
      clutch-y2 = 40;
      clutch-y3 = 60;
      clutch-y4 = 80;
      clutch-y5 = 100;
    };
  };
in
{
  options.customHomeManagerModules.foxblatConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Foxblat presets for Moza Racing wheelbases.

        Foxblat is a fork of Boxflat — the Linux configuration tool for Moza
        Racing hardware (alternative to Pit House). This module places
        game-specific FFB presets into ~/.config/foxblat/presets/ tuned for
        the Moza R9 (9 Nm):

          - r9-acc.yml — Assetto Corsa Competizione (transparent FFB, 15% damper,
                         25% friction for anti-oscillation on direct-drive)
          - r9-ac.yml  — Assetto Corsa 1 (25% damper, 25% friction)
          - r9-cyberpunk2077.yml — Cyberpunk 2077 with cp2077-wheel-mod-moza (720°, mod-generated
                         FFB at 250 Hz; spring/damper pass-through at 100%)

        All presets include pedal sections with game-appropriate response curves.

        All values are stored in raw wire format (what is sent to the hardware),
        not UI percentages. Key conversions:
          - ffb-strength, damper, friction, inertia, speed: wire = UI% * 10
          - natural-inertia: 1:1 (factory default KS/GS = 1100)
          - set-*-gain: wire = UI% * 2.55
          - equalizers: 1:1, neutral = 100

        Requires customNixOSModules.simracing.enable = true on the machine.
        Used on: anya.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = {
      ".config/foxblat/presets/r9-ac.yml".source = mkPreset "r9-ac" acPreset;
      ".config/foxblat/presets/r9-acc.yml".source = mkPreset "r9-acc" accPreset;
      ".config/foxblat/presets/r9-cyberpunk2077.yml".source = mkPreset "r9-cyberpunk2077" cp2077Preset;

      # XDG autostart: launch foxblat hidden in background on login so the
      # ProcessObserver can auto-load presets when a linked game starts.
      ".config/autostart/foxblat.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Foxblat
        Exec=foxblat --autostart
        X-GNOME-Autostart-enabled=true
      '';
    };

    # Stamp settings.yml so foxblat:
    #   - stops showing the "update udev rules" dialog (rules-version >= 2)
    #   - starts hidden and stays alive after window close (background + autostart-hidden)
    home.activation.foxblatSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings_file="''${XDG_CONFIG_HOME:-$HOME/.config}/foxblat/settings.yml"
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
