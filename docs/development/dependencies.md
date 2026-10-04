# Dependencies (npins)

Nixbook uses no flakes: every external input is pinned with [npins](https://github.com/andir/npins) in `npins/sources.json`, and imported with `import ./npins`.

## What is pinned

| Kind              | Pins                                                                                                                                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core              | `nixpkgs` (nixos-unstable), `home-manager`, `agenix`, `disko`, `stylix`, `nixvim`, `nixos-hardware`, `flake-compat`                                                                                                                 |
| Boot              | `lanzaboote`, `crane`, `rust-overlay`                                                                                                                                                                                               |
| Desktop           | `niri-flake`, `quickshell`, `dms`, `dms-plugin-registry`, `dankcalendar`, `zen-browser-flake`                                                                                                                                       |
| Gaming & hardware | `nix-proton-cachyos`, `ds4drv`, `foxblat`                                                                                                                                                                                           |
| Applications      | `globalprotect-openconnect`, `99` (NixVim plugin)                                                                                                                                                                                   |
| Custom packages   | `ginx`, `goji`, `rtk`, `opencode-manager`, `openchoreo`, `crd-wizard`, `kl`, `sofka`, `kratix-cli`, `pvmigrate`, `songbird`, `witr`, `ytui`, `jtui`, `fcitx5-lotus`, `schnelle-umlaute`, `actual-budget`, `pear-desktop`, `moonfin` |

Some pins are **frozen** (`npins freeze`) to stay on a known-good version; the update workflow skips them.

`nixbook-shell/` has its own `npins/` (nixpkgs, quickshell, dankcalendar) so it can be used outside nixbook; inside nixbook, the repository's pins are passed to it instead.

## Updating

Automatically: the [npins-update workflow](./ci-cd#dependency-updates) opens one auto-merging PR per pin every 3 days.

By hand, in the devenv shell:

```bash
npins update nixpkgs          # one pin
npins update                  # every pin
npins add github owner repo   # a new pin (use --branch to track a branch)
npins freeze kl               # keep a pin where it is
```

When you update `nixpkgs`, keep `devenv.yaml`'s `nixpkgs` URL on the same revision (`run-tests repo` checks it; the workflow does it automatically).

## Using a pin

```nix
let
  sources = import ./npins;
in
{
  imports = [ "${sources.nixos-hardware}/framework/13-inch/amd-ai-300-series" ];
}
```

Flake-only projects are imported through `flake-compat`:

```nix
(import sources.flake-compat { src = sources.dms; }).defaultNix.homeModules.dank-material-shell
```

## Binary cache

Machines and CI use the DidactikLabs S3 cache (`https://s3.didactiklabs.io/nix-cache`) in front of cache.nixos.org. CI pushes every system built from `main`, so a machine updating to `main` mostly downloads instead of building.
