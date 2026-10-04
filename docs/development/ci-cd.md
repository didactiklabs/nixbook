# CI/CD

Four GitHub Actions workflows keep the repository healthy.

| Workflow            | Runs on                       | Trigger                    | Purpose                                       |
| ------------------- | ----------------------------- | -------------------------- | --------------------------------------------- |
| `checks.yaml`       | GitHub-hosted `ubuntu-latest` | push / PR to `main`        | Cheap evaluation, lint and script checks      |
| `build.yaml`        | Self-hosted runners           | push / PR to `main`        | Full system builds; push to the binary cache  |
| `npins-update.yaml` | GitHub-hosted                 | every 3 days, manual       | Dependency update PRs with auto-merge         |
| `docs.yaml`         | GitHub-hosted                 | changes to `docs/`, manual | Build this website; deploy it to GitHub Pages |

## Checks

`checks.yaml` runs on free GitHub-hosted runners, so it never competes with the builders:

- **lint** — `devenv test` (treefmt, shellcheck, mdsh), then fails if treefmt changed any file;
- **repo** — `run-tests repo`, `shell`, `iso`, `docs`;
- **host (\<name\>)** — one leg per hive node, plus an _all modules_ leg; the matrix is read from `hive.nix`, so new machines are picked up automatically. Legs install the hardware stub and evaluate through `colmena eval`.

Evaluation warnings become annotations. A Nix store cache (saved from `main` only) keeps runs fast.

## Builds

`build.yaml` runs on self-hosted runners sharing one Nix store, in three jobs:

1. **changed** — `tests/changed-hosts.sh` evaluates every machine's system derivation and compares it with the base commit's (the PR's base, or the previous `main`). Only machines whose derivation changed need building.
2. **build** — a matrix leg per profile (totoro, anya, nishinoya, tanjiro, hanamichi). Unchanged legs report "unchanged" and pass in seconds — every leg still reports, because the `build (<profile>)` checks are the **merge gate**. If anything about the comparison fails, every profile is built.
3. **push-cache** — on `main` only, once the matrix finishes: builds the whole hive with `colmena build --keep-result` (a no-op on the shared store) and uploads every system to the **S3 binary cache**, signed, with retries.

A new push to a PR cancels its previous run; `main` runs are never cancelled half-way.

Because only changed machines are built, docs-only changes and pins used by a single machine are cheap.

## Dependency updates

`npins-update.yaml` runs every 3 days (and on demand): it updates each pin independently (up to 10 in parallel), keeps `devenv.yaml`'s nixpkgs revision in sync with the npins one, and opens a pull request per pin with **auto-merge** — so a pin lands as soon as its builds and checks pass. See [Dependencies](./dependencies).

## Documentation

`docs.yaml` builds this website with `devenv shell -- doc-build` on pull requests that touch it, and on `main` deploys `docs/.vitepress/dist` to **GitHub Pages**. See [This documentation](./documentation).
