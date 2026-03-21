{ lib, ... }:
{
  imports = [ ./swayConfig.nix ];
  ## https://arewewaylandyet.com/
  ## https://shibumi.dev/posts/my-way-to-wayland/
  ## https://github.com/swaywm/sway/wiki/Useful-add-ons-for-sway
  options.customHomeManagerModules.swayConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable per-user Sway compositor configuration.

        Manages the full Sway i3-compatible tiling environment via Home Manager:
          - swayConfig.nix: wayland.windowManager.sway.config — keybindings,
            workspace layout, bar configuration, input device settings,
            output configuration, exec-on-startup commands, gaps, borders,
            and Sway-specific SwayFX visual effects (blur, corner radius)

        References:
          https://arewewaylandyet.com/
          https://github.com/swaywm/sway/wiki/Useful-add-ons-for-sway

        Requires the system-level nixosModules/sway.nix to be enabled
        (customNixOSModules.sway.enable = true).

        Used on: anya (primary).
      '';
    };
  };
}
