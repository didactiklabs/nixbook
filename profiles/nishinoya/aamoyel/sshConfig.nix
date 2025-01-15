{
  config,
  lib,
  ...
}:
{
  config = {
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
