{ lib, ... }: {
  imports = [ ./swayConfig.nix ];
  ## https://arewewaylandyet.com/
  ## https://shibumi.dev/posts/my-way-to-wayland/
  ## https://github.com/swaywm/sway/wiki/Useful-add-ons-for-sway
  options.customHomeManagerModules.swayConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable sway config globally or not
      '';
    };
  };
}
