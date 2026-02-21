{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.atuinConfig.didactiklabs.enable {
    programs = {
      atuin = {
        enable = true;
        settings = {
          sync_address = "https://atuin.didactik.labs";
          enter_accept = true;
          sync = {
            records = true;
          };
        };
      };
    };
  };

  options.customHomeManagerModules.atuinConfig = {
    didactiklabs.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable atuinConfig config globally or not.
      '';
    };
  };
}
