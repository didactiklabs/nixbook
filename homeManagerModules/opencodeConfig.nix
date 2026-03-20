{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.opencodeConfig;
in
{
  options.customHomeManagerModules.opencodeConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "whether to enable opencodeConfig or not";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      settings = {
        plugin = [
          "opencode-gemini-auth"
          "opencode-anthropic-oauth"
        ];
      };
    };
  };
}
