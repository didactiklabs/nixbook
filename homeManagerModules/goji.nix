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

    # Get valid types from config
    TYPES=$(echo '${gojiJson}' | ${pkgs.jq}/bin/jq -r '.types[].name' | xargs | sed 's/ /, /g')

    # Extract hints and filter arguments
    TYPE_HINT=""
    SCOPE_HINT=""
    OTHER_ARGS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t|--type) TYPE_HINT="$2"; shift 2 ;;
        -s|--scope) SCOPE_HINT="$2"; shift 2 ;;
        *) OTHER_ARGS+=("$1"); shift ;;
      esac
    done

    HINTS=""
    if [ -n "$TYPE_HINT" ]; then HINTS+="The user explicitly wants type: $TYPE_HINT. "; fi
    if [ -n "$SCOPE_HINT" ]; then HINTS+="The user explicitly wants scope: $SCOPE_HINT. "; fi

    # Build the prompt
    PROMPT="Analyze the following git diff and generate a conventional commit.
    Available types: $TYPES
    $HINTS

    If type or scope are provided in 'HINTS', use them. Otherwise, determine the most appropriate ones from the diff.

    Output a JSON object with exactly these fields:
    - type: The commit type (must be one of the available types)
    - scope: A short scope (optional, use null if no clear scope exists)
    - subject: A concise description of the change

    Output ONLY the JSON object, no markdown, no backticks.

    Diff:
    $DIFF"

    # Call opencode run
    RESPONSE=$(opencode run "$PROMPT" --format json | ${pkgs.jq}/bin/jq -r 'select(.type=="text") | .part.text' | tr -d '\r')

    # Extract values
    TYPE=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.type // empty')
    SCOPE=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.scope // empty')
    SUBJECT=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.subject // empty')

    if [ -z "$SUBJECT" ] || [ "$SUBJECT" == "null" ]; then
        echo "❌ Error: Failed to generate a valid commit message."
        echo "AI Response: $RESPONSE"
        exit 1
    fi

    # Build goji command
    GOJI_ARGS=("-m" "$SUBJECT" "-t" "$TYPE")
    if [ -n "$SCOPE" ] && [ "$SCOPE" != "null" ]; then
        GOJI_ARGS+=("-s" "$SCOPE")
    fi

    FULL_MSG="$TYPE"
    [ -n "$SCOPE" ] && [ "$SCOPE" != "null" ] && FULL_MSG+="($SCOPE)"
    FULL_MSG+=": $SUBJECT"

    echo "✨ Generated: $FULL_MSG"

    # Run goji
    ${goji}/bin/goji "''${GOJI_ARGS[@]}" "''${OTHER_ARGS[@]}"
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
