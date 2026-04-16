{ pkgs, ... }:
let
  jira-worklog = pkgs.writeShellScriptBin "jira-worklog" ''
    set -euo pipefail

    # List issues assigned to me, pick one with fzf
    ISSUE=$(${pkgs.jira-cli-go}/bin/jira issue list \
      -a"$(${pkgs.jira-cli-go}/bin/jira me)" \
      -q"project IS NOT EMPTY" \
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
    read -rp "Time spent (e.g. 1h, 30m, 1h30m): " TIME

    if [ -z "$TIME" ]; then
      echo "No time entered."
      exit 1
    fi

    ${pkgs.jira-cli-go}/bin/jira issue worklog add "$KEY" "$TIME"
    echo "Logged $TIME on $KEY"
  '';
in
{
  home.packages = [ jira-worklog ];
}
