{ pkgs, ... }:
let
  jw = pkgs.writeShellScriptBin "jw" ''
    set -euo pipefail

    usage() {
      echo "Usage: jw <command>"
      echo ""
      echo "Commands:"
      echo "  list      List issues and open selected one"
      echo "  worklog   Log time spent on an issue"
      echo "  comment   Add a comment to an issue"
      exit 1
    }

    select_issue() {
      ME=$(${pkgs.jira-cli-go}/bin/jira me)
      ISSUE=$(${pkgs.jira-cli-go}/bin/jira issue list \
        -q"(assignee = '$ME' OR engineers = '$ME') AND project IS NOT EMPTY" \
        --plain \
        --no-headers \
        --columns KEY,SUMMARY 2>/dev/null \
        | ${pkgs.fzf}/bin/fzf --prompt="Select issue: " --height=40%)

      if [ -z "$ISSUE" ]; then
        echo "No issue selected."
        exit 1
      fi

      KEY=$(echo "$ISSUE" | ${pkgs.gawk}/bin/awk '{print $1}')
      echo "Selected: $ISSUE"
    }

    if [ $# -lt 1 ]; then
      usage
    fi

    COMMAND="$1"
    shift

    case "$COMMAND" in
      list)
        select_issue
        ${pkgs.jira-cli-go}/bin/jira open "$KEY"
        ;;
      worklog)
        select_issue
        read -rp "Time spent (e.g. 1h, 30m, 1h30m): " TIME
        if [ -z "$TIME" ]; then
          echo "No time entered."
          exit 1
        fi
        read -rp "Comment (optional, press Enter to skip): " WCOMMENT
        if [ -n "$WCOMMENT" ]; then
          ${pkgs.jira-cli-go}/bin/jira issue worklog add "$KEY" "$TIME" --comment "$WCOMMENT"
          echo "Logged $TIME on $KEY with comment"
        else
          ${pkgs.jira-cli-go}/bin/jira issue worklog add "$KEY" "$TIME"
          echo "Logged $TIME on $KEY"
        fi
        ;;
      comment)
        select_issue
        read -rp "Comment: " COMMENT
        if [ -z "$COMMENT" ]; then
          echo "No comment entered."
          exit 1
        fi
        ${pkgs.jira-cli-go}/bin/jira issue comment add "$KEY" "$COMMENT"
        echo "Comment added to $KEY"
        ;;
      *)
        echo "Unknown command: $COMMAND"
        usage
        ;;
    esac
  '';
in
{
  home.packages = [ jw ];
}
