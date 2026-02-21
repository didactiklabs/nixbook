{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.thunderbirdConfig;
in
{
  options.customHomeManagerModules.thunderbirdConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable thunderbirdConfig globally or not
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      package = pkgs.thunderbird;
    };
  };
}
