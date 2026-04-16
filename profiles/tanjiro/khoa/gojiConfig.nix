{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.gojiConfig.enable {
    home.file.".goji.json" = lib.mkForce {
      text = builtins.toJSON {
        noemoji = true;
        signoff = true;
        skipquestions = null;
        subjectmaxlength = 100;
        types = [
          {
            emoji = "";
            code = "";
            description = "Introduce new features.";
            name = "feat";
          }
          {
            emoji = "";
            code = "";
            description = "Fix a bug.";
            name = "fix";
          }
          {
            emoji = "";
            code = "";
            description = "Documentation change.";
            name = "docs";
          }
          {
            emoji = "";
            code = "";
            description = "Improve structure/format of the code.";
            name = "refactor";
          }
          {
            emoji = "";
            code = "";
            description = "A chore change.";
            name = "chore";
          }
          {
            emoji = "";
            code = "";
            description = "Add a test.";
            name = "test";
          }
          {
            emoji = "";
            code = "";
            description = "Critical hotfix.";
            name = "hotfix";
          }
          {
            emoji = "";
            code = "";
            description = "Remove dead code.";
            name = "deprecate";
          }
          {
            emoji = "";
            code = "";
            description = "Improve performance.";
            name = "perf";
          }
          {
            emoji = "";
            code = "";
            description = "Work in progress.";
            name = "wip";
          }
          {
            emoji = "";
            code = "";
            description = "Add or update compiled files or packages.";
            name = "package";
          }
        ];
      };
    };
  };
}
