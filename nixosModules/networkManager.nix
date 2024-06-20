{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customNixOSModules.networkManager;
in {
  options.customNixOSModules.networkManager = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable networkManager globally or not
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # The global useDHCP flag is deprecated, therefore explicitly set to false here.
    # Per-interface useDHCP will be mandatory in the future, so this generated config
    # replicates the default behaviour.
    networking.useDHCP = false;
    networking.networkmanager.enable = true;
    networking.networkmanager.dhcp = "internal";
    networking.dhcpcd.enable = false;
    programs.nm-applet.enable = true;
    ## cf https://github.com/NixOS/nixpkgs/issues/180175#issuecomment-1658731959
    systemd.services.NetworkManager-wait-online = {
      serviceConfig = {
        ExecStart = ["" "${pkgs.networkmanager}/bin/nm-online -q"];
      };
    };
  };
}
