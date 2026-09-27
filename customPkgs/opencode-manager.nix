{ pkgs }:
let
  sources = import ../npins;
  opencodeManagerSrc = sources.opencode-manager;
  inherit (opencodeManagerSrc) version;
in
pkgs.buildGoModule {
  pname = "opencode-manager";
  version = "${version}";

  src = opencodeManagerSrc;

  vendorHash = "sha256-XL22WQ0C6JyGxLIQ2jKKohhlLU8Oj++jMMtmWs969Oc=";

  # The test suite expects a container runtime and interactive environment.
  doCheck = false;

  subPackages = [ "cmd/opencode-manager" ];

  # baseImage.commands are joined with " && " into the EXTRA_COMMANDS build arg,
  # but the embedded Dockerfiles run it as `RUN ${EXTRA_COMMANDS}`: the shell
  # word-splits the expansion without re-parsing it, so `&&`, pipes, redirects
  # and quotes become plain arguments of the first command (every command ends
  # up as arguments to the first `mkdir`). Hand the string to `sh -c` so it is
  # parsed as a shell command line.
  postPatch = ''
    substituteInPlace \
      internal/runtime/buildcontext/Dockerfile \
      internal/runtime/buildcontext/Dockerfile.overlay \
      --replace-fail 'RUN ''${EXTRA_COMMANDS}' 'RUN sh -c "''${EXTRA_COMMANDS}"'
  '';

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
    homepage = "https://github.com/Mickael-Roger/opencode-manager";
    description = "k9s for OpenCode — TUI to create, attach, edit and tear down isolated coding-agent workspaces";
    license = pkgs.lib.licenses.mit;
    mainProgram = "opencode-manager";
    platforms = pkgs.lib.platforms.linux ++ pkgs.lib.platforms.darwin;
  };
}
