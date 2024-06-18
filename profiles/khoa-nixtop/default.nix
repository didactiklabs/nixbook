{
  config,
  pkgs,
  lib,
  username,
  hostname,
  ...
}: let
  mainIf = "enp34s0";
in {
  customNixOSModules = {
    laptopProfile.enable = false;
    networkManager.enable = true;
    sunshine.enable = true;
  };
  ## wake with sunshine
  networking.interfaces."${mainIf}".wakeOnLan = {
    enable = true;
    policy = ["magic"];
  };
  systemd.services.wol-custom = {
    description = "Wake-on-lan Hack (module doesn't work).";
    partOf = ["default.target"];
    requires = ["default.target"];
    after = ["default.target"];
    wantedBy = ["default.target"];
    serviceConfig = {
      User = "root";
      Group = "root";
      ExecStart = "${pkgs.ethtool}/bin/ethtool -s ${mainIf} wol g";
      Restart = "always";
    };
  };
  services.openssh.enable = true;
  home-manager = {
    users."${username}" = {
      home.packages = [
      ];
      profileCustomization = {
        mainWallpaper = let
          image = pkgs.fetchurl {
            url = "https://w.wallhaven.cc/full/6k/wallhaven-6k2ogx.jpg";
            sha256 = "sha256-9CwiVA30Er2lX+MJMKp7fOtmnpZzVAYSLVjKK2X9G0A=";
          };
        in "${image}";
        lockWallpaper = let
          image = pkgs.fetchurl {
            url = "https://w.wallhaven.cc/full/6o/wallhaven-6okd5l.png";
            sha256 = "sha256-uofSasQgDYmvuS7ZQJxY1oLht0X4o/Sq0ZrHACh01AQ=";
          };
        in "${image}";
      };
      customHomeManagerModules = {
        bluetooth.enable = false;
        fontConfig.enable = true;
        gitConfig.enable = true;
        gtkConfig.enable = true;
        sshConfig.enable = true;
        starship.enable = true;
        sway.enable = true;
        vim.enable = true;
        stylixConfig.enable = true;
        # https://github.com/adi1090x/rofi
        rofiConfig = {
          enable = true;
          launcher = {
            type = "type-3";
            style = "style-10";
          };
          powermenu = {
            style = "style-1"; #(1 - 5) # type-1 only
          };
          color = "cyberpunk";
        };
        copyqConfig.enable = false;
        fastfetchConfig.enable = true;
        desktopApps.enable = false;
        kubeTools.enable = false;
        waybar.enable = true;
      };
      imports = [
        ./gitConfig.nix
        ./swayConfig.nix
        ./sunshine.nix
        ./fastfetchConfig.nix
      ];
    };
  };
}
