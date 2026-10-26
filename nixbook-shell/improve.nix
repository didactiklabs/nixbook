{ pkgs, modelProvider }:
# nixbook-improve (improve/): the desktop agent's fixes to nixbook, fixes and
# polish only (services/SelfImprove.qml, Settings > Desktop agents). Its
# inbox, the confined Claude Code session, the checks (tests/shell-loads.sh:
# the shell on a headless sway), the PR, CI and the user's answer.
pkgs.buildGoModule {
  pname = "nixbook-improve";
  version = "0.1.0";
  src = ./improve;
  vendorHash = null;
  env.CGO_ENABLED = 0;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postInstall = ''
    mv $out/bin/improve $out/bin/nixbook-improve
    # Claude Code, nix and devenv are the user's, from their PATH; these
    # come after it (the user's own gh and git first).
    wrapProgram $out/bin/nixbook-improve --suffix PATH : ${
      pkgs.lib.makeBinPath (
        with pkgs;
        [
          gitMinimal
          openssh
          gh # the PRs, with its own token only
          libsecret # secret-tool: the token in the keyring
          modelProvider # nixbook-model-provider run: the provider Claude Code talks to
          libnotify # notify-send: Merge, Look, Drop
          xdg-utils # xdg-open: Look
          systemd # journalctl, systemctl: the shell's log
          sway # tests/shell-loads.sh: the shell started headless
          grim
          util-linux # setsid
          bash
          coreutils
          findutils
          gnused
        ]
      )
    }
  '';
  meta.mainProgram = "nixbook-improve";
}
