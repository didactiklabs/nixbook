{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.vscode;
  # nixpkgs-unstable's VSCode (>= 1.131) can't fetch its Oniguruma WASM in this
  # environment, breaking ALL TextMate syntax highlighting. Pin VSCode to 1.130.0
  # (the last version where it works, Copilot-compatible), built by this nixpkgs'
  # own VSCode expression: only the version, the archive and the Remote SSH server
  # commit change (values from nixpkgs 148bab9c), so no second nixpkgs is
  # evaluated and the runtime libraries are shared with the rest of the system.
  # Hardcoded so `npins update` can't bump it. Revert to pkgs.vscode once
  # upstream fixes it.
  vscodePinned =
    let
      version = "1.130.0";
      rev = "1b6a188127eeaf9194f945eb6eb89a657e93c54c";
      plat =
        {
          x86_64-linux = "linux-x64";
          aarch64-linux = "linux-arm64";
        }
        .${pkgs.stdenv.hostPlatform.system};
      hash =
        {
          x86_64-linux = "sha256-fWrT06eKxFUcFGMfeNfgPIUoKrUFw86LG8BOAfr+iOo=";
          aarch64-linux = "sha256-CzQScd1qm4YzqXMkeWqPWCKKWtwmKQ5AsokPy/lmowA=";
        }
        .${pkgs.stdenv.hostPlatform.system};
    in
    pkgs.vscode.override {
      buildVscode =
        args:
        pkgs.buildVscode (
          args
          // {
            inherit version rev;
            src = pkgs.fetchurl {
              name = "VSCode_${version}_${plat}.tar.gz";
              url = "https://update.code.visualstudio.com/${version}/${plat}/stable";
              inherit hash;
            };
            vscodeServer = pkgs.srcOnly {
              name = "vscode-server-${rev}.tar.gz";
              src = pkgs.fetchurl {
                name = "vscode-server-${rev}.tar.gz";
                url = "https://update.code.visualstudio.com/commit:${rev}/server-linux-x64/stable";
                hash = "sha256-ogtXQGE9/8xQYvN/juDglu6wkHJzYyL8wetF8sWnqd8=";
              };
              stdenv = pkgs.stdenvNoCC;
            };
          }
        );
    };
in
{
  options.customHomeManagerModules.vscode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Visual Studio Code with a declarative extension set.

        Manages VSCode entirely through Home Manager (mutableExtensionsDir = false),
        ensuring the extension list is reproducible and version-pinned.

        Extensions (200+, defined in extensionsList.nix):
          Languages:     Go, Rust, Python (Pylance + pylint + black), TypeScript,
                         Nix, Ansible, Terraform/OpenTofu, YAML, TOML, Markdown,
                         Docker, Kubernetes, Helm, SQL, Java, C/C++, HTML/CSS
          AI assistants: GitHub Copilot (inline + chat), Continue
          Git:           GitLens, Git Graph, GitHub Pull Requests
          Formatting:    Prettier, EditorConfig, run-on-save (golines for Go,
                         nixfmt for Nix files)
          UI/UX:         Material Theme, Material Icons, indent-rainbow,
                         Error Lens, Project Manager, Todo Tree

        User settings (profiles.default.userSettings):
          - Go: golines formatter (max line length 140) on save
          - Nix: nixfmt on save via emeraldwalk.runonsave
          - Python: Pylance language server, pylint linter, black formatter
          - Ansible: full OIDC collection names, lint enabled
          - GitHub Copilot: inline suggestions (3), completions (10)
          - kitty integration: sets kitty as external terminal

        Extra packages installed alongside VSCode:
          - exercism   — coding challenge CLI
          - golines    — Go line-length formatter
          - nixfmt     — Nix code formatter

        Used on: nishinoya.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.exercism
      pkgs.golines
      pkgs.nixfmt
    ];
    programs.vscode = {
      enable = true;
      package = vscodePinned;
      profiles.default.extensions = import ./mkAllExtensions.nix { inherit pkgs; };
      mutableExtensionsDir = false;
      # Write settings.json as a writable file so VSCode can persist runtime
      # changes (avoids "EROFS: read-only file system" on the store symlink).
      profiles.default.mutableUserSettings = true;
      profiles.default.userSettings = {
        "emeraldwalk.runonsave" = {
          "commands" = [
            {
              "match" = "\\.go$";
              "cmd" = "golines \${file} -w --max-len=140";
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
          lib.mkOverride 3000 "'Roboto Mono', 'Font Awesome 5 Brands', 'Font Awesome 5 Free', 'Font Awesome 5 Free Solid'";
        "editor.fontLigatures" = true;
        "editor.fontWeight" = "bold";
        "editor.formatOnSave" = false;
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
        "terminal.integrated.fontFamily" =
          lib.mkOverride 3000 "'Roboto Mono', 'Font Awesome 5 Brands', 'Font Awesome 5 Free', 'Font Awesome 5 Free Solid'";
        "terminal.integrated.fontWeight" = "bold";
        "terminal.integrated.copyOnSelection" = true;
        "window.menuBarVisibility" = "toggle";
        "window.zoomLevel" = 1;
        "keyboard.dispatch" = "keyCode";
        "explorer.confirmDelete" = false;
        "explorer.confirmDragAndDrop" = false;
        "explorer.openEditors.visible" = 1;
        "editor.occurrencesHighlight" = "singleFile";
        "workbench.iconTheme" = "material-icon-theme";
        "workbench.colorTheme" = lib.mkForce "Dark Modern";
        # Custom theme
        #"workbench.colorTheme" = lib.mkOverride 3000 "Ayu Dark";

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
        "[go]" = {
          "editor.insertSpaces" = false;
          "editor.formatOnSave" = true;
          "editor.codeActionsOnSave" = {
            "source.organizeImports" = "explicit";
          };
        };
        "go.useLanguageServer" = true;
        "go.toolsManagement.autoUpdate" = true;
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
