# The macOS machines' update commands:
#   osupdate        nixbook's main from GitHub, applied (ginx clones it into a
#                   temporary directory and runs darwin-switch there): no
#                   checkout needed on the Mac, as osupdate on NixOS
#   darwin-switch   a checkout's darwin.nix applied: `colmena apply-local
#                   switch` for the Macs (darwin-rebuild finds its configuration
#                   through <darwin-config>; nixbook's is darwin.nix, with the
#                   same pins as the NixOS machines)
{
  config,
  pkgs,
  lib,
  hostname,
  ...
}:
let
  remote = "https://github.com/didactiklabs/nixbook";
  darwin-switch = pkgs.writeShellApplication {
    name = "darwin-switch";
    runtimeInputs = [
      config.nix.package
      pkgs.coreutils
    ];
    text = ''
      usage() {
        echo "usage: darwin-switch [--build] [--repo DIR] [--host NAME] [--user NAME] [nix-build options…]" >&2
        echo "  builds a checkout's darwin.nix machine (default ${hostname}, for ${config.system.primaryUser})" >&2
        echo "  and activates it; the checkout: --repo, else \$NIXBOOK_REPO, else the current directory" >&2
        echo "  --build: build only.  Without a checkout: osupdate (nixbook's main from GitHub)" >&2
      }
      repo=''${NIXBOOK_REPO:-.}
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
        echo "darwin-switch: no darwin.nix in $repo (--repo DIR, or osupdate for nixbook's main)" >&2
        exit 1
      fi
      repo=$(cd "$repo" && pwd)
      echo "building $host for $user from $repo" >&2
      out=$(nix-build --no-out-link "''${extra[@]}" \
        --argstr repo "$repo" --argstr host "$host" --argstr user "$user" \
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
  osupdate = pkgs.writeShellApplication {
    name = "osupdate";
    runtimeInputs = [
      config.nix.package
      pkgs.git
      pkgs.gawk
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      if [ $# -gt 0 ]; then
        echo "usage: osupdate   (applies ${remote}'s main to this Mac)" >&2
        exit 2
      fi
      target=$(git ls-remote ${remote} refs/heads/main | awk '{print $1}')
      if [ -z "$target" ]; then
        echo "error: can't read ${remote}'s main (no network?)" >&2
        exit 1
      fi
      echo "last applied revision: $(jq -r .rev /etc/nixos/version 2>/dev/null || echo none)"
      echo "applying revision: $target..."
      echo Running ginx...
      # ginx clones main into a temporary directory, runs the command there
      # and removes the clone: darwin-switch builds that clone's darwin.nix
      # (getRevision.nix reads its .git) and activates it (sudo, Touch ID).
      ${lib.getExe pkgs.customPkgs.ginx} --source ${remote} -b main --now -- \
        ${lib.getExe darwin-switch} --repo .
      # ginx exits 0 even when its command fails: check the result.
      applied=$(jq -r .rev /etc/nixos/version)
      if [ "$applied" != "$target" ]; then
        echo "error: the update did not apply (deployed revision: $applied, expected: $target)" >&2
        exit 1
      fi
      echo "updated to $applied"
    '';
  };
in
{
  environment.systemPackages = [
    darwin-switch
    osupdate
    pkgs.customPkgs.ginx
  ];
}
