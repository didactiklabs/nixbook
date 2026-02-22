{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  goji = import ../customPkgs/goji.nix { inherit pkgs; };
  goji-ai = pkgs.writeShellScriptBin "goji-ai" ''
    # Check if opencode is installed
    if ! command -v opencode &> /dev/null; then
        echo "❌ Error: opencode is not installed."
        exit 1
    fi

    # Check for staged changes
    DIFF=$( ${pkgs.git}/bin/git diff --cached)

    if [ -z "$DIFF" ]; then
        echo "❌ No staged changes found. Please stage your changes first (git add)."
        exit 1
    fi

    echo "🤖 Generating commit message with OpenCode AI..."

    # Build the prompt
    # We request a conventional commit format (type: description)
    PROMPT="Analyze the following git diff and generate a concise conventional commit message.
    Follow the conventional commits specification (e.g., feat: add login functionality).
    Do not include emojis.
    Output ONLY the commit message text, nothing else.

    Diff:
    $DIFF"

    # Call opencode run to get the message
    # Use --format json for reliable parsing
    COMMIT_MSG=$(opencode run "$PROMPT" --format json | ${pkgs.jq}/bin/jq -r 'select(.type=="text") | .part.text' | tr -d '\r' | xargs)

    if [ -z "$COMMIT_MSG" ]; then
        echo "❌ Error: Failed to generate a commit message."
        exit 1
    fi

    echo "✨ Generated message: $COMMIT_MSG"

    # Run goji with the generated message
    # Any additional arguments passed to this script will be forwarded to goji
    ${goji}/bin/goji -m "$COMMIT_MSG" "$@"
  '';
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
    home.packages = [
      goji
      goji-ai
    ];
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
