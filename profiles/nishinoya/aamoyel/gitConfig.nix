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
    programs.git = {
      userName = "Alan Amoyel";
      userEmail = "alanamoyel06@gmail.com";
      signing = {
        signByDefault = lib.mkForce true;
      };
      includes = [
        {
          condition = "gitdir:~/go/src/github.com/the-marshmallow-project/";
          path = "~/go/src/github.com/the-marshmallow-project/.gitconfig";
        }
      ];
    };
  };
}
