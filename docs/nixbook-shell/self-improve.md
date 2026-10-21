# Fixes it makes itself

The desktop agent can fix nixbook itself: **fixes and polish only** (a bug, a rough edge, wrong wording), each as a pull request with its changelog entry, merged when you say so. New features and big changes are never made here: those it leaves for you, saying what a real change would be.

Only machines whose Nix configuration enables it have it (totoro, for now):

```nix
customHomeManagerModules.nixbookShellConfig.selfImprove.enable = true;
# outside nixbook: programs.nixbook-shell.selfImprove.enable = true;
```

Elsewhere there is no Settings section, agents don't get the `report_problem` tool, and `nixbook-improve` refuses to run. Where it is enabled, it stays off until you turn it on: **Settings → Desktop agents → Fixes it makes itself → Make fixes on its own** (`ai.improve.enable`). It uses your Claude Code login for the fixing session, and its own GitHub token (below) for GitHub.

## Its GitHub token

It reaches GitHub **only with its own token**, never your `gh` login or ssh key. Create a **fine-grained token** (GitHub → Settings → Developer settings → Fine-grained tokens) for the repository only. Set **Contents** and **Pull requests** to _Read and write_ and nothing else (no _Workflows_, no _Administration_). Paste it in the section's **GitHub token** field: **Save and check** checks that it can read the repository, then keeps it in your keyring (`secret-tool`, service `nixbook-improve`). It warns you about a classic token, which reaches every repository you can, and about an admin token. **Forget the token** removes it. Without a token it opens no pull request.

- `gh` runs with that token and an empty config directory, so it can't fall back to your login. git pushes and fetches over https with the token alone; an ssh repository URL is used as https.
- The fixing session never has it: it isn't in its environment, and its file tools can't reach the keyring.
- Without _Workflows_ permission, GitHub itself refuses a push that touches `.github/workflows`, on top of the guard.
- Merging uses the same token. If `main`'s rules require more than the token may do (a review, an admin bypass), the merge fails and the notification says why: merge it on GitHub instead.

## What it fixes

Things to fix arrive in an inbox. Filing them is plain code, with no model call:

- **What you report.** Tell an agent something of nixbook is broken or annoying ("the bar's clock is cut off, report this"): its `report_problem` tool files it. You can also type it in Settings. Your words stay on this computer: the PR says it in the session's own words, since the repository is public.
- **The shell's errors.** The QML errors the running shell prints (a `TypeError`, an `Unable to assign`, a binding loop…), read from its journal 10 minutes after it starts, then every 6 hours. A missing optional file or an icon the theme lacks isn't counted.
- **The desktop tools' crashes.** An exception in `nixbook-desktop-mcp`, as opposed to a refusal, read from its audit log.

What you report gets a fix soon. An error has to show up 3 times first, and a crash twice. It makes at most `perDay` fixes on its own (2 by default). **Fix now** next to an item starts one at once, without counting toward that limit.

## How a fix is made

1. A clone of the repository (`~/.local/share/nixbook-shell/improve/repo`) is brought to `main`, on an `agent/fix-<item>` branch.
2. A **Claude Code session** (your Claude Code login) reads the item and changes the files. It runs in `--restricted` mode: its file tools stay inside the clone, and it can't run commands, browse the web, or use settings, hooks or MCP servers. It never sees your files, your logins or a token. It may answer _skip_ (not a bug, or not enough to go on) or _too big_ (a feature or a refactor: you get a notification saying what a real change would be).
3. **The guard** refuses what isn't a fix: more than `maxFiles` files (5) or `maxLines` changed lines (150), a new file (except Markdown), a deleted or binary file, or anything off limits (below).
4. **The checks** (on this computer):
   - `treefmt`;
   - the tests of what it touched (`tests/run.sh shell` for the shell's scripts and backends, `tests/run.sh repo` for Nix files);
   - for the shell, **the shell started on a headless sway** (`nixbook-shell/tests/shell-loads.sh`), first at the base revision and then with the change. It must stay up and print no QML warning the base didn't.

   When something fails, the session gets the output once and tries again. If it fails a second time, the item is marked failed and nothing is pushed.

5. **The commit** is its changelog entry: `fix(scope): …` or `polish(scope): …`, then what was wrong, the cause, what changed and how to see it. Below that come where the report came from and an `Agent-Fix: <item>` trailer. These titles are what the updates widget lists as the changelog.
6. The branch is pushed and a **pull request** opened (label `agent-fix`), with what was checked and the files changed.
7. Once **CI** finishes, a notification says **Fix ready** with **Merge**, **Look** and **Drop** (the same buttons are in Settings). If CI fails, the session gets the failed jobs' logs and tries once more, then the PR is left to you. Merge is a rebase merge, made with its token.

## Merged on its own

**Merge on its own once CI passes, when it only touched the docs** (`ai.improve.autoMerge`, off by default) merges a fix without asking when every file it changed matches `autoMergePaths` (`docs/**`, `**/*.md`) and none is sensitive. You get a notification after the merge.

## Off limits

- **Never changed by a fix** (refused before the push, and again by CI): `.github/`, the fixer itself (`nixbook-shell/improve/`, `SelfImprove.qml`), the agent desktop's sandbox, the tests, `nixosModules/`, `installer/`, `lib/`, `profiles/`, `npins/`, `hive.nix`, `base.nix`, the devenv files, `AGENTS.md` and `CLAUDE.md`, secrets.
- **Never merged on its own** (sensitive: what agents may do): `desktop-mcp.py`, `Ai.qml`, `AiChatSession.qml`, `Initiative.qml`, `Routines.qml`, `Config.qml` and `builtin-defaults.json`, the Desktop agents settings page, the shell's Nix files, `customPkgs/` and `homeManagerModules/`. The PR and the notification say so.

CI's **agent-guard** job (`checks.yaml`) runs `nixbook-improve guard` on every `agent/` branch, built from the base branch rather than from the PR. It checks the paths, the size and that each commit is `fix(…)` or `polish(…)` with a body and its trailer. To have GitHub refuse a merge without it, make it a required check of `main`'s ruleset.

## After the merge

- **main's checks.** The merged commit's checks are watched. If one fails, a revert PR is opened at once and a notification offers **Merge the revert**.
- **The updated shell.** Once you update (the updates widget), 5 minutes after the shell starts on a revision that contains a fix, its journal is read. A QML warning in the fix's files that the shell didn't print before, or the shell restarting, opens a revert PR the same way. After the revert merges, update again to take the fix off this computer.

## Settings

| Setting                     | Default                  | What                                            |
| --------------------------- | ------------------------ | ----------------------------------------------- |
| `ai.improve.enable`         | `false`                  | Make fixes on its own                           |
| `ai.improve.model`          | `"sonnet"`               | The fixing session's model (`opus`…)            |
| `ai.improve.perDay`         | `2`                      | Fixes started on their own per day              |
| `ai.improve.maxFiles`       | `5`                      | Files a fix may change                          |
| `ai.improve.maxLines`       | `150`                    | Lines a fix may change                          |
| `ai.improve.budgetUsd`      | `3`                      | A session's spending limit (`--max-budget-usd`) |
| `ai.improve.autoMerge`      | `false`                  | Merge low-risk fixes on its own                 |
| `ai.improve.autoMergePaths` | `["docs/**", "**/*.md"]` | What counts as low-risk                         |
| `ai.improve.repo`           | `""` (`updates.repoUrl`) | The GitHub repository                           |

CI's guard always uses the default limits, so raising `maxFiles` or `maxLines` here gets a bigger fix refused there.

## Command line

`nixbook-improve status` (the inbox and the runs), `note TEXT`, `collect`, `run [--item ID] [--no-push]` (`--no-push`: a dry run that stops at the local commit), `merge|drop|look PR`, `token set|forget|status` (`set` reads it on stdin), `health REV`, `guard BASE [HEAD]`. State lives in `~/.local/state/nixbook-shell/improve/`; the clone and each run's logs in `~/.local/share/nixbook-shell/improve/`.
