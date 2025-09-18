{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  goji = import ../customPkgs/goji.nix { inherit pkgs; };
  gojiJson = ''
    {
      "noemoji": false,
      "signoff": true,
      "skipquestions": null,
      "subjectmaxlength": 100,
      "types": [
        {
          "emoji": "✨",
          "code": ":sparkles:",
          "description": "Introduce new features.",
          "name": "feat"
        },
        {
          "emoji": "🐛",
          "code": ":bug:",
          "description": "Fix a bug.",
          "name": "fix"
        },
        {
          "emoji": "📚",
          "code": ":books:",
          "description": "Documentation change.",
          "name": "docs"
        },
        {
          "emoji": "🎨",
          "code": ":art:",
          "description": "Improve structure/format of the code.",
          "name": "refactor"
        },
        {
          "emoji": "🧹",
          "code": ":broom:",
          "description": "A chore change.",
          "name": "chore"
        },
        {
          "emoji": "🧪",
          "code": ":test_tube:",
          "description": "Add a test.",
          "name": "test"
        },
        {
          "emoji": "🚑️",
          "code": ":ambulance:",
          "description": "Critical hotfix.",
          "name": "hotfix"
        },
        {
          "emoji": "⚰️",
          "code": ":coffin:",
          "description": "Remove dead code.",
          "name": "deprecate"
        },
        {
          "emoji": "⚡️",
          "code": ":zap:",
          "description": "Improve performance.",
          "name": "perf"
        },
        {
          "emoji": "🚧",
          "code": ":construction:",
          "description": "Work in progress.",
          "name": "wip"
        },
        {
          "emoji": "📦",
          "code": ":package:",
          "description": "Add or update compiled files or packages.",
          "name": "package"
        }
      ]
    }
  '';
in
{
  config = lib.mkIf cfg.gojiConfig.enable {
    home.packages = [ goji ];
    home.file.".goji.json" = {
      text = gojiJson;
    };
    programs.zsh = {
      initContent = ''
        source <(goji completion zsh)
      '';
    };
    programs.fish = lib.mkIf (config.customHomeManagerModules.fishConfig.enable or false) {
      shellInit = ''
        goji completion fish | source
      '';
    };
  };

  options.customHomeManagerModules.gojiConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable gojiConfig config globally or not.
      '';
    };
  };
}
