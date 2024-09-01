{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.desktopApps.enable {
    home.packages = [
      pkgs.exercism
      pkgs.golines
      pkgs.nixfmt-rfc-style
    ];
    programs.vscode = {
      enable = true;
      extensions = import ./mkAllExtensions.nix { inherit pkgs; };
      mutableExtensionsDir = false;
      userSettings = {
        "emeraldwalk.runonsave" = {
          "commands" = [
            {
              "match" = "\\.go$";
              "cmd" = "golines \${file} -w";
            }
            {
              "match" = "\\.nix$";
              "cmd" = "nixfmt \${file}";
            }
          ];
        };
        "ansible.ansible.useFullyQualifiedCollectionNames" = true;
        "ansible.ansibleLint.enabled" = true;
        "ansible.python.interpreterPath" = "${pkgs.python3}/bin/python3";
        "python.analysis.completeFunctionParens" = true;
        "python.autoComplete.addBrackets" = true;
        "python.formatting.provider" = "black";
        "python.formatting.blackPath" = "${pkgs.python3Packages.black}/bin/black";
        "python.linting.pylintEnabled" = true;
        "python.linting.pylintPath" = "${pkgs.python3Packages.pylint}/bin/pylint";
        "python.linting.enabled" = true;
        "python.languageServer" = "Pylance";

        "github.copilot.inlineSuggest.count" = 3;
        "github.copilot.list.count" = 10;
        "github.copilot.autocomplete.count" = 3;
        "github.copilot.autocomplete.enable" = true;
        "github.copilot.inlineSuggest.enable" = true;
        "github.copilot.enable" = {
          "python" = true;
          "ansible" = true;
        };

        "extensions.autoUpdate" = false;
        "extensions.autoCheckUpdates" = false;
        "editor.fontFamily" =
          lib.mkOverride 3000
            "'Hack Nerd Font', 'Ubuntu Mono', 'Cascadia Mono', 'DejaVu Sans Mono', 'Font Awesome 5 Brands', 'Font Awesome 5 Free', 'Font Awesome 5 Free Solid'";
        "editor.fontLigatures" = true;
        "editor.fontSize" = 11;
        "editor.fontWeight" = "bold";
        "editor.formatOnSave" = true;
        "editor.renderWhitespace" = "all";
        "editor.minimap.enabled" = false;
        "files.insertFinalNewline" = true;
        "files.trimFinalNewlines" = true;
        "files.trimTrailingWhitespace" = true;
        "files.autoSave" = "afterDelay";
        "trailing-spaces.trimOnSave" = true;
        "highlightLine.borderColor" = "#abb2bf";
        "highlightLine.borderStyle" = "solid";
        "highlightLine.borderWidth" = "1px";
        "terminal.integrated.profiles.linux" = {
          "bash" = {
            "path" = "${pkgs.zsh}/bin/zsh";
            "icon" = "terminal-bash";
          };
          "tmux" = {
            "path" = "${pkgs.tmux}/bin/tmux";
            "icon" = "terminal-tmux";
          };
        };
        "terminal.integrated.defaultProfile.linux" = "zsh";
        "terminal.external.linuxExec" = "kitty";
        "terminal.integrated.fontFamily" =
          lib.mkOverride 3000
            "'Hack Nerd Font', 'Ubuntu Mono', 'Cascadia Mono', 'DejaVu Sans Mono', 'Font Awesome 5 Brands', 'Font Awesome 5 Free', 'Font Awesome 5 Free Solid'";
        "terminal.integrated.fontSize" = 12;
        "terminal.integrated.fontWeight" = "bold";
        "terminal.integrated.copyOnSelection" = true;
        "window.menuBarVisibility" = "toggle";
        "window.zoomLevel" = 1;
        "explorer.confirmDelete" = false;
        "explorer.confirmDragAndDrop" = false;
        "explorer.openEditors.visible" = 1;
        "editor.occurrencesHighlight" = "singleFile";
        "workbench.iconTheme" = "material-icon-theme";
        "workbench.colorTheme" = lib.mkOverride 3000 "Ayu Dark";

        ## bracket color stuff
        "editor.bracketPairColorization.enabled" = true;
        "editor.guides.bracketPairs" = false;
        "editor.guides.bracketPairsHorizontal" = true;
        "editor.guides.highlightActiveBracketPair" = true;

        "files.associations" = {
          "config" = "properties";
          "i3_config" = "properties";
          "dunstrc" = "properties";
          "Dockerfile*" = "dockerfile";
          "*.dockerfile" = "dockerfile";
          "docker-compose.yml" = "dockercompose";
          "*.docker-compose.yml" = "dockercompose";
          "alerts.rules" = "jinja-yaml";
          "Pipfile" = "pip-requirements";
          "*.rasi" = "css";
          "jenkinsfile" = "groovy";
          "Jenkinsfile" = "groovy";
          "*.groovy" = "groovy";
          "*.groovy.j2" = "jinja-groovy";
          "*.j2" = "jinja";
          "*.yml" = "ansible";
          "*.xml.j2" = "jinja-xml";
          "*.yml.j2" = "jinja-yaml";
          "*.yaml.j2" = "jinja-yaml";
          "*.conf.j2" = "jinja-properties";
          "*.tf" = "terraform";
          "flake.lock" = "json";
          "*.boot" = "clojure";
          "*.boot.j2" = "clojure";
          "*.clj" = "clojure";
          "*.clj.j2" = "clojure";
          "*.properties.j2" = "jinja-properties";
          "inventory*" = "jinja-properties";
          "*.env*" = "dotenv";
          "*Dockerfile.j2" = "jinja-dockerfile";
          "*.yuck" = "yuck";
          "*.sh" = "shellscript";
        };
        "security.workspace.trust.untrustedFiles" = "open";
        "files.exclude" = {
          "**/.git" = false;
        };
        "settingsSync.keybindingsPerPlatform" = false;
        "nix.enableLanguageServer" = false;
        "shellformat.path" = "${pkgs.shfmt}/bin/shfmt";

        "[html]" = {
          "editor.defaultFormatter" = "vscode.html-language-features";
        };
        "[json]" = {
          "editor.defaultFormatter" = "vscode.json-language-features";
          "editor.tabSize" = 2;
          "editor.insertSpaces" = true;
          "editor.autoIndent" = "full";
          "editor.formatOnSave" = true;
        };
        "[jsonc]" = {
          "editor.defaultFormatter" = "vscode.json-language-features";
          "editor.tabSize" = 2;
          "editor.insertSpaces" = true;
          "editor.autoIndent" = "full";
          "editor.formatOnSave" = true;
        };
        "[markdown]" = {
          "editor.formatOnSave" = false;
        };
        "markdown.marp.toggleMarpFeature" = true;
        "[nix]" = {
          "editor.insertSpaces" = true;
          "editor.tabSize" = 2;
          "editor.autoIndent" = "full";
          "editor.quickSuggestions" = {
            "other" = true;
            "comments" = false;
            "strings" = true;
          };
          "editor.formatOnSave" = true;
          "editor.formatOnPaste" = false;
          "editor.formatOnType" = false;
        };
        "alejandra.program" = "${pkgs.alejandra}/bin/alejandra";
        "[terraform]" = {
          "editor.insertSpaces" = true;
          "editor.tabSize" = 2;
          "editor.autoIndent" = "full";
          "editor.quickSuggestions" = {
            "other" = true;
            "comments" = false;
            "strings" = true;
          };
          "editor.formatOnSave" = true;
        };
        "[shellscript]" = {
          "editor.defaultFormatter" = "foxundermoon.shell-format";
        };
        "[yaml]" = {
          "editor.insertSpaces" = true;
          "editor.tabSize" = 2;
          "editor.autoIndent" = "full";
          "editor.quickSuggestions" = {
            "other" = true;
            "comments" = false;
            "strings" = true;
          };
          "editor.formatOnSave" = true;
          "editor.formatOnPaste" = false;
        };
        "search.useGlobalIgnoreFiles" = true;
        "git.confirmSync" = false;
        "update.mode" = "none";
        "vsicons.dontShowNewVersionMessage" = true;
      };
    };
  };
}
