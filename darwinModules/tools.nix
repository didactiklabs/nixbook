# `darwin-switch`: nixbook's `colmena apply-local switch` for the macOS
# machines. darwin-rebuild finds its configuration through <darwin-config>;
# nixbook's is darwin.nix, with the same pins as the NixOS machines, so this
# builds that machine and activates it the way darwin-rebuild does.
{
  config,
  pkgs,
  lib,
  hostname,
  ...
}:
let
  # The checkout this system was built from (a path, not copied to the
  # store: toString). NIXBOOK_REPO or --repo points it elsewhere.
  repo = toString ../.;
  darwin-switch = pkgs.writeShellApplication {
    name = "darwin-switch";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      usage() {
        echo "usage: darwin-switch [--build] [--repo DIR] [--host NAME] [--user NAME] [nix-build options…]" >&2
        echo "  builds darwin.nix's machine (default ${hostname}, for ${config.system.primaryUser}) and activates it" >&2
        echo "  --build: build only" >&2
      }
      repo=''${NIXBOOK_REPO:-${lib.escapeShellArg repo}}
      host=${lib.escapeShellArg hostname}
      # The account this system was built for (darwin.nix's withUser: the same
      # machine on a CI runner, a VM or a rented Mac).
      user=${lib.escapeShellArg config.system.primaryUser}
      build_only=0
      extra=()
      while [ $# -gt 0 ]; do
        case "$1" in
          --build) build_only=1 ;;
          --repo) repo=$2; shift ;;
          --host) host=$2; shift ;;
          --user) user=$2; shift ;;
          -h|--help) usage; exit 0 ;;
          *) extra+=("$1") ;;
        esac
        shift
      done
      if [ ! -f "$repo/darwin.nix" ]; then
        echo "darwin-switch: no darwin.nix in $repo (set NIXBOOK_REPO or --repo)" >&2
        exit 1
      fi
      echo "building $host for $user from $repo" >&2
      out=$(nix-build --no-out-link "''${extra[@]}" \
        --argstr repo "$(cd "$repo" && pwd)" --argstr host "$host" --argstr user "$user" \
        -E '{ repo, host, user }: ((import (/. + repo + "/darwin.nix")).withUser host user).system')
      echo "$out"
      if [ "$build_only" = 1 ]; then
        exit 0
      fi
      # As darwin-rebuild switch: the new generation, then its activation, as
      # root with root's HOME (sudo keeps the caller's on macOS).
      sudo -H nix-env -p /nix/var/nix/profiles/system --set "$out"
      sudo -H "$out/activate"
    '';
  };
in
{
  environment.systemPackages = [ darwin-switch ];
}
