{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.rbwConfig;
in
{
  options.customHomeManagerModules.rbwConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable rbw (Bitwarden CLI) with a selfhosted base url.
      '';
    };

    email = lib.mkOption {
      type = lib.types.str;
      description = "The email address for the Bitwarden account.";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://pass.bealv.io";
      description = "The base URL for the Bitwarden server.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.rbw = {
      enable = true;
      settings = {
        inherit (cfg) email;
        base_url = cfg.baseUrl;
        pinentry = pkgs.pinentry-qt;
        lock_timeout = 2629746;
      };
    };
  };
}
