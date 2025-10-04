{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.zshConfig;
  common = import ./commonShellConfig.nix { inherit pkgs; };
in
{
  options.customHomeManagerModules.zshConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable zsh configuration and shell integrations.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = common.commonPackages;
    programs = common.commonPrograms // {
      atuin = {
        enableZshIntegration = true;
        flags = [ "--disable-up-arrow" ];
      };
      yazi = common.commonPrograms.yazi // {
        enableZshIntegration = true;
      };
      zoxide = common.commonPrograms.zoxide // {
        enableZshIntegration = true;
      };
      fzf = common.commonPrograms.fzf // {
        enableZshIntegration = true;
      };
      eza = common.commonPrograms.eza // {
        enableZshIntegration = true;
      };
      zsh = {
        autosuggestion.enable = true;
        plugins = [
          {
            # will source zsh-autosuggestions.plugin.zsh
            name = "zsh-syntax-highlighting";
            src = pkgs.fetchFromGitHub {
              owner = "zsh-users";
              repo = "zsh-syntax-highlighting";
              rev = "refs/tags/0.8.0";
              sha256 = "sha256-iJdWopZwHpSyYl5/FQXEW7gl/SrKaYDEtTH9cGP7iPo=";
            };
          }
          {
            # will source zsh-autosuggestions.plugin.zsh
            name = "zsh-bat";
            src = pkgs.fetchFromGitHub {
              owner = "fdellwing";
              repo = "zsh-bat";
              rev = "master";
              sha256 = "sha256-TTuYZpev0xJPLgbhK5gWUeGut0h7Gi3b+e00SzFvSGo=";
            };
          }
        ];
        enable = true;
        shellAliases = common.commonShellAliases;
        initContent = ''
          ${common.anyNixShellInit "zsh"}
          # source <(okada completion zsh)
        '';
        oh-my-zsh = {
          enable = true;
        };
      };
    };
  };
}
