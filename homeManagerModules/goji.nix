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
        echo "❌ Error: 'opencode' is not installed."
        echo "Please install it first or add it to your environment."
        exit 1
    fi

    # Check if opencode is configured
    if ! opencode auth list 2>/dev/null | grep -q "[1-9] credentials"; then
        echo "❌ Error: 'opencode' is not configured."
        echo "Please run 'opencode auth login' to set up a provider (e.g., Google, OpenRouter, etc.)."
        exit 1
    fi

    echo "🤖 Generating commit message with OpenCode AI..."

    # Get valid types from config
    TYPES=$(echo '${gojiJson}' | ${pkgs.jq}/bin/jq -r '.types[].name' | xargs | sed 's/ /, /g')

    # Extract hints and filter arguments
    TYPE_HINT=""
    SCOPE_HINT=""
    IS_AMEND=false
    IS_ADD=false
    OTHER_ARGS=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t|--type) TYPE_HINT="$2"; shift 2 ;;
        -s|--scope) SCOPE_HINT="$2"; shift 2 ;;
        --amend) IS_AMEND=true; OTHER_ARGS+=("$1"); shift ;;
        -a|--add) IS_ADD=true; OTHER_ARGS+=("$1"); shift ;;
        *) OTHER_ARGS+=("$1"); shift ;;
      esac
    done

    if [ "$IS_ADD" = true ]; then
        echo "➕ Staging all changes..."
        ${pkgs.git}/bin/git add -A
    fi

    HINTS=""
    if [ -n "$TYPE_HINT" ]; then HINTS+="The user explicitly wants type: $TYPE_HINT. "; fi
    if [ -n "$SCOPE_HINT" ]; then HINTS+="The user explicitly wants scope: $SCOPE_HINT. "; fi

    if [ "$IS_AMEND" = true ]; then
        # For amend, we want to see changes relative to the parent of the commit being amended
        REF="HEAD~1"
        DIFF=$( ${pkgs.git}/bin/git diff --cached $REF 2>/dev/null || ${pkgs.git}/bin/git diff --cached )
        OLD_MSG=$( ${pkgs.git}/bin/git log -1 --format=%B 2>/dev/null)
        HINTS+="This is an amendment to a previous commit. The provided diff shows the changes that will be introduced by the new commit compared to its parent. The previous commit message was: $OLD_MSG. "
        echo "🔄 Amending last commit..."
    else
        # Only staged changes for a new commit
        DIFF=$( ${pkgs.git}/bin/git diff --cached )
        HINTS+="The provided diff shows the changes that will be introduced by this new commit. "
    fi

    if [ -z "$DIFF" ]; then
        echo "❌ No changes found to commit."
        exit 1
    fi

    # Summarize the diff: list changed files and stats to give the AI quick context
    DIFF_STAT=$( ${pkgs.git}/bin/git diff --cached --stat $( [ "$IS_AMEND" = true ] && echo "$REF" || true ) 2>/dev/null )

    # Build the prompt
    PROMPT="You are a commit message generator. Read the diff below and produce a single JSON object.

    RULES:
    1. In a unified diff, lines starting with '-' (not '---') are OLD/REMOVED lines. Lines starting with '+' (not '+++') are NEW/ADDED lines. Context lines have no prefix.
    2. To determine what the commit does, compare old vs new: if a line moved from '-' to '+' with changes, it was MODIFIED. If only '-' lines exist, content was REMOVED. If only '+' lines exist, content was ADDED.
    3. The subject must describe the net effect (what the codebase looks like after this commit), not list individual line changes.
    4. Use one of these types: $TYPES
    5. $HINTS

    Changed files summary:
    $DIFF_STAT

    OUTPUT FORMAT (raw JSON only, no markdown, no backticks):
    {\"type\": \"...\", \"scope\": \"...or null\", \"subject\": \"...\"}

    Diff:
    $DIFF"

    # Call opencode run and extract the AI response
    OPENCODE_OUTPUT=$(opencode run "$PROMPT" --format json --model "opencode/big-pickle" 2>/dev/null)
    AI_TEXT=$(echo "$OPENCODE_OUTPUT" | ${pkgs.jq}/bin/jq -r 'select(.type=="text") | .part.text // empty' 2>/dev/null | tr -d '\r')

    # Extract JSON from the response - handle markdown code blocks
    RESPONSE=$(echo "$AI_TEXT" | sed -n '/```json/,/```/p' | sed '1d;$d')

    # If no code block found, use the whole response
    if [ -z "$RESPONSE" ]; then
        RESPONSE="$AI_TEXT"
    fi

    # Extract values with fallbacks
    TYPE=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.type // "feat"')
    SCOPE=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.scope // ""')
    SUBJECT=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.subject // "update"')

    # If SUBJECT is still empty or "null", extract from plain text
    if [ -z "$SUBJECT" ] || [ "$SUBJECT" == "null" ]; then
        # Try to extract commit message from plain text
        SUBJECT=$(echo "$AI_TEXT" | grep -i "subject:" | sed 's/.*subject:[[:space:]]*//i' | tr -d '\n' | head -c 100)
        [ -z "$SUBJECT" ] && SUBJECT="update changes"
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
        Whether to enable Goji conventional-commit tooling with AI assistance.

        Goji is a TUI/CLI tool for writing Conventional Commits with emoji.
        This module installs two tools:

          goji — interactive commit helper that prompts for type, scope, and
            subject, then formats the message as:
              <emoji> <type>(<scope>): <subject>
            Supported types: feat, fix, docs, refactor, chore, test, hotfix,
            deprecate, perf, wip, package (configured via ~/.goji.json)

          goji-ai — AI-powered wrapper that:
            1. Runs `git diff --cached` to collect staged changes
            2. Sends the diff to opencode (must be installed + authenticated)
            3. Parses the JSON response to extract type/scope/subject
            4. Invokes goji with the generated values
            Supports -t/--type, -s/--scope, -a/--add, --amend flags
            Requires opencode to be configured (opencodeConfig.enable = true)

        Also installs Zsh completion for goji (`source <(goji completion zsh)`)
        and Fish completion when fishConfig is enabled.

        Shell aliases (from commonShellConfig): gfix, gfeat, gchore.
        Used on: totoro, nishinoya.
      '';
    };
  };
}
