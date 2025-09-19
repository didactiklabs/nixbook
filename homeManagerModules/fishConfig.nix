{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.fishConfig;
  common = import ./commonShellConfig.nix { inherit pkgs; };
in
{
  options.customHomeManagerModules.fishConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable fish shell configuration globally or not
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = common.commonPackages;
    programs = common.commonPrograms // {
      atuin = common.commonPrograms.atuin // {
        enableFishIntegration = true;
        settings = {
          up_arrow = false;
        };
      };
      yazi = common.commonPrograms.yazi // {
        enableFishIntegration = true;
      };
      zoxide = common.commonPrograms.zoxide // {
        enableFishIntegration = true;
      };
      fzf = common.commonPrograms.fzf // {
        enableFishIntegration = true;
      };
      eza = common.commonPrograms.eza // {
        enableFishIntegration = true;
      };
      fish = {
        enable = true;
        plugins = [
          {
            name = "autopair";
            inherit (pkgs.fishPlugins.autopair) src;
          }
          {
            name = "sponge";
            inherit (pkgs.fishPlugins.sponge) src;
          }
          {
            name = "sudope";
            inherit (pkgs.fishPlugins.plugin-sudope) src;
          }
          {
            name = "fish-you-should-use";
            inherit (pkgs.fishPlugins.fish-you-should-use) src;
          }
        ];
        shellAliases = common.commonShellAliases;
        shellInit = ''
          ${common.anyNixShellInit "fish"}
          # source (okada completion fish | psub)
        '';
        functions = {
          fish_greeting = {
            description = "Greeting to show when starting a fish shell";
            body = "";
          };
          mkdircd = {
            description = "Create a directory and cd into it";
            body = "mkdir -p $argv[1]; and cd $argv[1]";
          };
        };
      };
    };
  };
}
