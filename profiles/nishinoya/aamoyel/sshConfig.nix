{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.gitConfig;
in
{
  config = lib.mkIf cfg.enable {
    programs.ssh = {
      matchBlocks = {
        "gitlab.com" = {
          user = "git";
          identityFile = "/home/aamoyel/.ssh/kubolabs";
        };
      };
    };
  };
}
