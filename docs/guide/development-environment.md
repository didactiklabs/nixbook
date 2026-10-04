# Development environment

Nixbook uses [devenv](https://devenv.sh) for everything you need while working on the repository: tools, git hooks, formatters and helper scripts.

## Entering the environment

With [direnv](https://direnv.net) installed, the shell loads automatically when you `cd` into the repository:

```bash
direnv allow
```

Otherwise, enter it by hand:

```bash
devenv shell
```

The environment provides `git`, `colmena`, `npins`, `ragenix` (agenix-compatible secrets CLI), `jq`, `yq-go`, `python3`, Node.js and pnpm (for this website).

## Scripts

| Script          | What it does                                                                |
| --------------- | --------------------------------------------------------------------------- |
| `hello`         | Prints the greeting                                                         |
| `build-iso`     | Builds the installer ISO (`nix-build default.nix -A buildIso`)              |
| `test-iso`      | Builds the ISO and boots it in a QEMU VM with UEFI                          |
| `generate-docs` | Regenerates `docs/MODULES.md` (the [options reference](/reference/options)) |
| `run-tests`     | Cheap regression checks — see [Testing](/development/testing)               |
| `doc-dev`       | Runs this website locally with hot reload (http://localhost:5173/nixbook/)  |
| `doc-build`     | Builds this website into `docs/.vitepress/dist`                             |
| `doc-preview`   | Serves the built website                                                    |

## Git hooks and formatting

The shared devenv module (`devenvModules/devenv.nix`, also imported by other DidactikLabs repositories through npins) configures:

- **treefmt** with `nixfmt` (Nix), `prettier` (Markdown, JSON, YAML, JS/TS), `shfmt` (shell) and `gofumpt` (Go);
- **shellcheck** for shell scripts;
- **mdsh** for Markdown;
- **difftastic** as the diff tool.

The hooks run automatically on commit. To run every check by hand, the way CI does:

```bash
devenv test   # treefmt, shellcheck, mdsh
treefmt       # format everything in place
```

::: warning Vendored code
`nixbook-shell/src/` is a vendored QML tree: it is excluded from treefmt and shellcheck so that upstream-style code stays as written. nixbook's own scripts (`nixbook-shell/scripts/`) are still checked.
:::
