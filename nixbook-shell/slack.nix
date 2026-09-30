{
  pkgs,
  slack ? pkgs.slack,
}:
# Slack coloured like the shell: slack-theme.js appended to its main-process
# bundle loads the CSS apply-app-colors.sh renders from the shell's palette
# (Settings > Appearance > Color generation > Apps > Slack), live. Without
# that file (the switch off, or no nixbook-shell) it is stock Slack.
#
# app.asar is repacked with the same files left outside it
# (app.asar.unpacked: the native modules and what Slack runs out of process).
slack.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.asar ];
  postInstall = (old.postInstall or "") + ''
    resources=$out/lib/slack/resources
    work=$(mktemp -d)
    asar extract "$resources/app.asar" "$work/src"
    # On its own line (the bundle ends with a sourceMappingURL comment).
    { printf '\n;\n'; cat ${./slack-theme.js}; } >>"$work/src/dist/boot.bundle.cjs"
    unpack=$(cd "$resources/app.asar.unpacked" && find . -type f -printf '**/src/%P,')
    rm -rf "$resources/app.asar" "$resources/app.asar.unpacked"
    asar pack "$work/src" "$resources/app.asar" --unpack "{''${unpack%,}}"
    rm -rf "$work"
  '';
})
