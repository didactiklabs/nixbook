# Testing

Besides the full machine builds, every push and pull request runs **cheap regression checks** that report problems within minutes: nothing is built except a few tiny generated files. They all go through `tests/run.sh`, available as `run-tests` in the devenv shell.

## Commands

| Command                                 | Checks                                                                                                                                                                                                                                                               |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `run-tests repo`                        | `hive.nix` nodes, `profiles/` and the `build.yaml` build matrix agree; `devenv.yaml` uses the npins nixpkgs; every module file is imported somewhere; every custom package instantiates; nixbook-shell's `lib.nix` unit tests; `nixbook-shell/` evaluates on its own |
| `run-tests shell`                       | nixbook-shell's scripts: the config CLI and its merge round-trip through Nix, the assistant facts, app colours, widget placement, the desktop-control MCP server (against stub tools and a fake compositor)                                                          |
| `run-tests iso`                         | The installer ISO evaluates                                                                                                                                                                                                                                          |
| `run-tests docs`                        | `docs/MODULES.md` documents the current options (run `generate-docs` if not)                                                                                                                                                                                         |
| `run-tests host <name> [--all-modules]` | The machine evaluates exactly as `colmena build` would, keeps its invariants (`tests/hosts.nix`: hardening sysctls, boot editor off, deployment settings, state version…) and its generated config files build                                                       |
| `run-tests all`                         | All of the above, for every machine                                                                                                                                                                                                                                  |

`--all-modules` evaluates a machine with **every optional `customNixOSModules` toggle forced on**, so modules no profile enables are still evaluated and can't rot unnoticed.

::: tip Hardware configuration
`host` needs `/etc/nixos/hardware-configuration.nix`. On a machine without one (a CI runner, a non-NixOS laptop), install the stub:

```bash
sudo install -D -m 644 tests/hardware-stub.nix /etc/nixos/hardware-configuration.nix
```

:::

## Rules of thumb

- **Adding a machine**: `hive.nix`, `profiles/` and the `build.yaml` matrix must agree — `run-tests repo` checks it.
- **Adding a NixOS module no profile enables**: add its toggle to `optionalModules` in `tests/hosts.nix`.
- **Changing an invariant on purpose** (e.g. a sysctl asserted in `tests/hosts.nix`): update the check in the same change.
- **Changing module options**: run `generate-docs` and commit `docs/MODULES.md`.

## Formatting and linting

```bash
devenv test   # treefmt (nixfmt, prettier, shfmt, gofumpt), shellcheck, mdsh
```

CI fails if `treefmt` would change any file, so run `treefmt` before committing (the git hooks do it for you).

## Testing a change on a real machine

```bash
colmena apply-local --sudo        # from your working tree
```

Or test the installer and a full install in a VM with `test-iso`.

## nixbook-shell tests

From `nixbook-shell/`:

```bash
bash tests/scripts.sh
bash tests/desktop-mcp.sh
nix-instantiate --eval --strict --json --expr 'import ./tests/lib.nix { }'   # []
```
