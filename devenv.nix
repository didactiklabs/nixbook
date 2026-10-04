{ pkgs, ... }:
{
  imports = [ ./devenvModules/devenv.nix ];

  # https://devenv.sh/basics/
  env.GREET = "Welcome to the Nixbook NixOS configuration environment!";

  packages = with pkgs; [
    git
    colmena
    npins
    ragenix
    # tests/run.sh
    jq
    yq-go
    python3
    # documentation website (docs/, VitePress)
    nodejs_24
    pnpm_10
  ];

  treefmt.config.programs.prettier.excludes = [
    "assets/dms/plugins/**/translations.js"
    # documentation website: dependencies, build output, generated lockfile
    "docs/node_modules/**"
    "docs/.vitepress/cache/**"
    "docs/.vitepress/dist/**"
    "docs/pnpm-lock.yaml"
  ];

  # nixbook-shell/src is a vendored upstream tree (nixbook-shell, merged by
  # hand): upstream's shell/Python scripts and QML-flavoured JS (`.pragma
  # library`, which prettier can't parse) are left as upstream wrote them, so
  # resyncing stays a plain diff. Our own scripts (nixbook-shell/scripts)
  # are still checked.
  treefmt.config.settings.global.excludes = [ "nixbook-shell/src/**" ];
  git-hooks.hooks.shellcheck.excludes = [ "^nixbook-shell/src/" ];

  scripts = {
    # https://devenv.sh/scripts/
    hello.exec = ''
      echo $GREET
    '';
    build-iso.exec = ''
      nix-build default.nix -A buildIso "$@"
    '';
    test-iso.exec = ''
      nix-build default.nix -A testVm "$@" && ./result/bin/test-iso-vm
    '';
    generate-docs.exec = ''
      nix-build docs/generate-docs.nix "$@" && cp result/MODULES.md docs/MODULES.md && treefmt docs/MODULES.md && echo "Documentation written to docs/MODULES.md"
    '';
    run-tests.exec = ''
      "$DEVENV_ROOT/tests/run.sh" "$@"
    '';
    doc-dev.exec = ''
      cd "$DEVENV_ROOT/docs" && pnpm install --frozen-lockfile && pnpm run docs:dev "$@"
    '';
    doc-build.exec = ''
      cd "$DEVENV_ROOT/docs" && pnpm install --frozen-lockfile && pnpm run docs:build "$@"
    '';
    doc-preview.exec = ''
      cd "$DEVENV_ROOT/docs" && pnpm run docs:preview "$@"
    '';
  };

  enterShell = ''
    mkdir -p .tmp/
    hello
    echo ""
    echo "Available custom scripts:"
    echo "  hello     - Prints the greeting message"
    echo "  build-iso - Builds the installation ISO"
    echo "  test-iso       - Builds and tests the installation ISO in a VM"
    echo "  generate-docs  - Auto-generates module documentation to docs/MODULES.md"
    echo "  run-tests      - Cheap regression checks (tests/run.sh; run-tests for usage)"
    echo "  doc-dev        - Run the documentation website locally (VitePress, port 5173)"
    echo "  doc-build      - Build the documentation website (docs/.vitepress/dist)"
    echo "  doc-preview    - Preview the built documentation website"
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    hello | grep "Welcome"
  '';
}
