# Contributing

## Where things go

| You want to…                          | Put it in                                                             |
| ------------------------------------- | --------------------------------------------------------------------- |
| A system feature shared by machines   | A module in `nixosModules/` (`customNixOSModules.<name>`)             |
| A user feature shared by users        | A module in `homeManagerModules/` (`customHomeManagerModules.<name>`) |
| Something for one machine             | `profiles/<hostname>/default.nix`                                     |
| Something for one user on one machine | `profiles/<hostname>/<user>/`                                         |
| A package missing from nixpkgs        | `customPkgs/<name>.nix` + an npins pin                                |
| nixpkgs config or overlays            | `lib/pkgs.nix`, `lib/overlays.nix`                                    |
| A desktop shell feature               | `nixbook-shell/`                                                      |

Start from `base.nix`, `hive.nix` and the relevant profile to see how things are wired.

## Writing a module

Every module declares an `enable` option under its namespace, with a description — it becomes part of the [options reference](/reference/options):

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.customNixOSModules.myFeature;
in
{
  options.customNixOSModules.myFeature = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable my feature. Explain what it configures and
        which machines use it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # …
  };
}
```

Then:

1. import it from the directory's `default.nix` (`run-tests repo` fails on modules imported from nowhere);
2. if no profile enables it, add it to `optionalModules` in `tests/hosts.nix`;
3. run `generate-docs` and commit `docs/MODULES.md`;
4. describe the feature in the matching page of this website (`docs/`).

## Keeping documentation in sync

- **`docs/MODULES.md`** — regenerate with `generate-docs` whenever options change (CI checks it).
- **`KEYBINDS.md`** — update the matching table whenever you add, change or remove a key binding (Niri, Sway, Kitty, NixVim or per-profile overrides). Its tables are also the website's [Keybindings](/desktop/keybindings) page.
- **nixbook-shell's assistant** — when you add or change a shell feature, update the assistant's how-to answers in `nixbook-shell/hm-module.nix` (English, French, German and Vietnamese) and its lexicon in `src/services/ConfigAssistant.qml`, so it never gives outdated help.
- **`README.md`** and **`AGENTS.md`** — keep them accurate for humans and AI agents.

## Git workflow

1. Start from an up-to-date `main` (`git fetch origin && git checkout main && git pull --ff-only`) and create a feature branch. Never commit on `main`.
2. Commit on the branch — Conventional Commits, e.g. with [`goji`](/user/development#goji).
3. Push and open a pull request against `main`.
4. Before updating the PR, rebase it on `main` and `git push --force-with-lease`.
5. **Merging deploys**: machines follow `main` through `osupdate` and the update widgets. Merge with a **rebase merge** once the checks and builds pass.
6. Delete the branch afterwards.

::: warning AI agents
Agents working on this repository must never commit, push or merge without being asked, and must ask before any git action. See `AGENTS.md`.
:::

## Before opening a PR

```bash
treefmt              # format
devenv test          # lint
run-tests repo       # repository consistency
run-tests host <machine-you-changed>
```
