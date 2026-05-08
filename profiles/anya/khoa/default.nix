{
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./gitConfig.nix
    ./swayConfig.nix
    ./sunshine.nix
    ./zshConfig.nix
  ];
  profileCustomization = {
    mainWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://w.wallhaven.cc/full/5g/wallhaven-5gp535.png";
          sha256 = "sha256-Ip4Kox49zJxYIGxtisI0qcWcc/MSzeeEdsxJIiHUcvg=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://w.wallhaven.cc/full/5g/wallhaven-5gp535.png";
          sha256 = "sha256-Ip4Kox49zJxYIGxtisI0qcWcc/MSzeeEdsxJIiHUcvg=";
        };
      in
      "${image}";
  };
  home.packages = [
    pkgs.wineWow64Packages.waylandFull
    pkgs.firefox
  ];
  systemd.user.services.opencode-web = {
    Unit = {
      Description = "OpenCode Web Server";
      After = [ "network-online.target" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      WorkingDirectory = "/tmp";
      ExecStart = "${lib.getExe config.programs.opencode.package} web";
      Restart = "always";
      RestartSec = 5;
    };
  };
  programs.opencode.settings = {
    mcp = {
      trek = {
        type = "remote";
        url = "https://trek.bealv.io/mcp";
      };
    };
    server = {
      hostname = "0.0.0.0";
      port = 4096;
    };
    permission = {
      # bash = "deny";
      edit = "deny";
      read = "deny";
      grep = "deny";
      glob = "deny";
    };
  };
  customHomeManagerModules = {
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = true;
    nixvimConfig.enable = true;
    fastfetchConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    dmsConfig.enable = true;
    opencodeConfig = {
      enable = true;
      ollama.enable = true;
    };
  };
}
