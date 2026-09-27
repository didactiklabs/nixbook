{ pkgs }:
let
  sources = import ../npins;
  opencodeManagerSrc = sources.opencode-manager;
  # Release pins carry `version`; the fork's branch pin does not. Keep the
  # upstream release it is based on so ocm's update check (which ignores the
  # `-…` suffix) doesn't report an update for the base it already includes.
  version =
    opencodeManagerSrc.version or "v2.7.0-fork.${builtins.substring 0 7 opencodeManagerSrc.revision}";
in
pkgs.buildGoModule {
  pname = "opencode-manager";
  version = "${version}";

  src = opencodeManagerSrc;

  vendorHash = "sha256-XL22WQ0C6JyGxLIQ2jKKohhlLU8Oj++jMMtmWs969Oc=";

  # The test suite expects a container runtime and interactive environment.
  doCheck = false;

  subPackages = [ "cmd/opencode-manager" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/mickael-menu/opencode-manager/internal/cli.version=${version}"
    "-X github.com/mickael-menu/opencode-manager/internal/tui.appVersion=${version}"
  ];

  postInstall = ''
    # Short alias shipped by the npm package (bin/ocm).
    ln -s opencode-manager $out/bin/ocm

    # Built-in module catalogue: the npm postinstall copies this tree into
    # ~/.config/opencode-manager/modules; the devTools Home Manager activation
    # does the same from $out/share/opencode-manager/modules.
    mkdir -p $out/share/opencode-manager
    cp -r modules $out/share/opencode-manager/modules
  '';

  meta = {
    homepage = "https://github.com/Banh-Canh/opencode-manager";
    description = "k9s for OpenCode — TUI to create, attach, edit and tear down isolated coding-agent workspaces";
    license = pkgs.lib.licenses.mit;
    mainProgram = "opencode-manager";
    platforms = pkgs.lib.platforms.linux ++ pkgs.lib.platforms.darwin;
  };
}
