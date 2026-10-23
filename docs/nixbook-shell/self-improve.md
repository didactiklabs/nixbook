# Fixes it makes itself

The desktop agent can fix nixbook itself: **fixes and polish only** (a bug, a rough edge, wrong wording), each as a pull request with its changelog entry, merged when you say so. Apart from them, and switched on apart, it can **build the features you ask for** ([below](#features-it-builds)): a fix it finds too big goes there too. The agent can also [propose one of either](#proposed-by-the-agent) from what it saw get in your way.

Only machines whose Nix configuration enables it have it (totoro, for now):

```nix
customHomeManagerModules.nixbookShellConfig.selfImprove.enable = true;
# outside nixbook: programs.nixbook-shell.selfImprove.enable = true;
```

Elsewhere there are no Settings sections, agents don't get the `report_problem`, `request_feature` and `list_requests` tools, and `nixbook-improve` refuses to run. Where it is enabled, it stays off until you turn it on: **Settings → Desktop agents → Fixes it makes itself → Make fixes on its own** (`ai.improve.enable`). It uses your Claude Code login for the fixing session, and its own GitHub token (below) for GitHub.

## Its GitHub token

It reaches GitHub **only with its own token**, never your `gh` login or ssh key. Create a **fine-grained token** (GitHub → Settings → Developer settings → Fine-grained tokens) for the repository only. Set **Contents** and **Pull requests** to _Read and write_ and nothing else (no _Workflows_, no _Administration_). Paste it in the section's **GitHub token** field: **Save and check** checks that it can read the repository, push and open pull requests (a dry-run push and a pull request from a branch that doesn't exist: nothing is created) and names a missing permission; then it keeps it in your keyring (`secret-tool`, service `nixbook-improve`). It warns you about a classic token, which reaches every repository you can, and about an admin token. **Forget the token** removes it. Without a token it opens no pull request.

- `gh` runs with that token and an empty config directory, so it can't fall back to your login. git pushes and fetches over https with the token alone; an ssh repository URL is used as https.
- Its git calls to GitHub use none of your git config (`GIT_CONFIG_GLOBAL=/dev/null`): your credential helpers or an https-to-ssh rewrite can't get in the way of the token. Its commits are never signed with your key: they're Claude's, and a background job shouldn't raise a pinentry prompt.
- If **Save and check** refuses a token, nothing is saved and the previous token stays in use. "GitHub doesn't accept this token for git" means GitHub doesn't know it (a typo, expired, regenerated), or the organization hasn't approved it yet.
- The fixing session never has it: it isn't in its environment, and its file tools can't reach the keyring.
- Without _Workflows_ permission, GitHub itself refuses a push that touches `.github/workflows`, on top of the guard.
- Merging uses the same token. If `main`'s rules require more than the token may do (a review, an admin bypass), the merge fails and the notification says why: merge it on GitHub instead.

## What it fixes

Things to fix arrive in an inbox. Filing them is plain code, with no model call, and uses only what your user can already read: a source it can't read is skipped (no new permission; `dmesg` itself stays restricted). It looks 10 minutes after the shell starts, then every 6 hours, or when you press **Look for bugs now**.

- **What you report.** Tell an agent something of nixbook is broken or annoying ("the bar's clock is cut off, report this"): its `report_problem` tool files it. You can also type it in Settings. Your words stay on this computer: the PR says it in the session's own words, since the repository is public.
- **The shell's errors.** The QML errors the running shell prints (a `TypeError`, an `Unable to assign`, a binding loop…), read from its journal 10 minutes after it starts, then every 6 hours. A missing optional file or an icon the theme lacks isn't counted.
- Each error keeps the revision the shell printing it ran (`/etc/nixos/version`). `main` may have moved since, so the session gets the lines around it at that revision and finds the same code on `main`.
- **The desktop tools' crashes.** An exception in `nixbook-desktop-mcp`, as opposed to a refusal, read from its audit log.
- **Failed units.** A systemd unit nixbook defines (system or user) in the failed state, with its last log lines. One running again later is dropped from the list.
- **Errors in nixbook's units' logs.** Error lines (priority `err` and worse) in the journal of a unit nixbook defines, even when it keeps running.
- **The system update.** The last `osupdate` failed (the end of its log), or printed a Nix warning (`evaluation warning:`, `trace: warning:`).
- **CI on `main`.** A workflow whose latest run on `main` failed in a job's step (read with the token); the session gets the failed jobs' logs. One green again is dropped from the list. A failure only in `ciIgnoreJobs` (`push-cache`: uploading to the binary cache), or of a job that lost its runner (no failed step), isn't a bug for a fix.
- **Crashes of nixbook's programs.** A coredump of a program nixbook packages (`customPkgs/`, the shell).

**Only what nixbook defines is sent to Claude unasked.** Nix writes out what that is: the units of its own module files (system: `/etc/nixbook/owned-units.json`, from `nixosModules/ownedUnits.nix`; user: `~/.config/nixbook-shell/owned.json`) and its packages. The rest is listed under **Seen, not nixbook's**, for you to know: another unit failing, another app's crash, the kernel's errors (from the journal). It never starts a session; **Fix now** sends one anyway, telling Claude it may not be nixbook's to fix.

Logs stay on this computer: they go to the Claude session as context, never into a commit or a pull request.

What you report, a failed update or a red CI get a fix soon. A shell or unit error has to show up 3 times first; a crash, a failed unit (two looks) or a Nix warning (two updates) twice. It makes at most `perDay` fixes on its own (2 by default; **Fixes a day on its own** in the section, `0` for no limit, while **Most a fix may spend**, `budgetUsd`, still caps each run). **Fix now** next to an item starts one at once, without counting toward that limit. Items it tried without fixing them (failed, skipped, too big) stay listed, with why (but those it found harmless and unfixable, which leave on their own), so **Fix now** can try again, after you give the token a missing permission for instance.

## How a fix is made

1. A clone of the repository (`~/.local/share/nixbook-shell/improve/repo`) is brought to `main`, on an `agent/fix-<item>` branch.
2. A **Claude Code session** (your Claude Code login) reads the item and changes the files. It runs in `--restricted` mode: its file tools stay inside the clone, and it can't run commands, browse the web, or use settings, hooks or MCP servers. It never sees your files, your logins or a token. It may answer _skip_ (not a bug, or not enough to go on; when nothing here can fix it and it does no harm, such as another app's log noise, it is _ignored_: dropped from the list and never tried again) or _too big_ (a feature or a refactor): the item then moves to the [feature requests](#features-it-builds) with what the session found, and a notification says so. When nothing here can do it (it needs a place off limits, credentials, hardware, a change outside nixbook) it answers _can't_, and the item is [dropped with why](#what-it-cant-do).
3. **The guard** refuses what isn't a fix: more than `maxFiles` files (5) or `maxLines` changed lines (150), a new file (except Markdown), a deleted or binary file, or anything off limits (below).
4. **The checks** (on this computer):
   - `treefmt`;
   - the tests of what it touched (`tests/run.sh shell` for the shell's scripts and backends, `tests/run.sh repo` for Nix files);
   - for the shell, **the shell started on a headless sway** (`nixbook-shell/tests/shell-loads.sh`), first at the base revision and then with the change. It must stay up and print no QML warning the base didn't.

   When something fails, the session gets the output once and tries again. If it fails a second time, the item is marked failed and nothing is pushed. Failed in a second run as well, it is [dropped](#what-it-cant-do).

5. **The commit** is its changelog entry: `fix(scope): …` or `polish(scope): …`, then what was wrong, the cause, what changed and how to see it. Below that come where the report came from and an `Agent-Fix: <item>` trailer. These titles are what the updates widget lists as the changelog.
6. The branch is pushed and a **pull request** opened (label `agent-fix`), with what was checked and the files changed.
7. Once **CI** finishes (a cancelled or skipped job isn't a failure; a failure without a log, a lost runner, gets no retry), a notification says **Fix ready** with **Merge**, **Look** and **Drop** (the same buttons are in Settings). If CI fails, the session gets the failed jobs' logs and tries once more, then the PR is left to you. Merge is a rebase merge, made with its token.

## What it costs

Nothing runs between fixes but the shell's timers: it looks for bugs 10 minutes after the shell starts and then every 6 hours (a few log reads and GitHub calls, seconds of CPU), and checks its open PRs every 30 minutes while one waits. A run waiting on CI or on you is an idle process. A fix itself (at most `perDay` a day on its own, plus each **Fix now**) is a few minutes of work: the Claude Code session, the tests of what it touched, and the shell started headless (a headless sway and a second, software-rendered shell for about 25 seconds). Fixes run at the lowest CPU and disk priority (`Nice=19`, `CPUWeight=idle`, `IOSchedulingClass=idle`), so they only take what your own work leaves; the Nix builds they start are the system's `nix-daemon`'s, at its usual priority.

## Seeing what it does

- **The status line** at the top of the section always says something:
  - _Off_, or that it needs its token;
  - while fixing, _Fixing "…" — Claude reads ThumbnailImage.qml (3 min)_, live, with a progress bar and **Stop**;
  - a PR waiting for CI or for you;
  - otherwise _Idle_, with its last activity.
- **Activity** lists what it did and decided lately:
  - each look for bugs and what it found;
  - why no fix was started (nothing seen often enough yet, with the counts; today's fixes made; no token);
  - a fix's start, retries and end;
  - CI, merges and what a merge broke;
  - errors.
- **The bar.** The bar's robot shows a wrench while a fix is being made, and its tooltip says what it is doing.
- **Stop** ends the fix being made before its PR is out: the Claude session and the checks are stopped, and the item goes back to the inbox.

A PR you merge or close on GitHub leaves the list too: it checks its open PRs when the shell starts, every 30 minutes while one waits, and when it looks for bugs (`nixbook-improve sync`). Merged there, it is watched after the update like the others.

## Merged on its own

Two switches, both off by default, merge a fix without asking once its CI passes:

- **Merge docs-only fixes on its own** (`ai.improve.autoMerge`): when every file it changed matches `autoMergePaths` (`docs/**`, `**/*.md`).
- **Merge every fix on its own once CI passes** (`ai.improve.autoMergeFixes`): any fix.

Such a fix gets GitHub's **auto-merge** as soon as its PR opens: GitHub merges it the moment its required checks pass, even if the fixer has stopped meanwhile (a reboot). The fixer still merges it itself once it sees CI pass, should GitHub not have. A fix whose CI fails has its auto-merge turned off, so a later re-run can't merge it behind your back.

Either way, a fix touching what agents may do (their tools, permissions, switches and defaults: the sensitive files below) always waits for your **Merge**: otherwise the fixer could merge a loosening of its own limits without you seeing it. You get a notification after each merge, the Activity says why it merged, and the watch after the merge (main's checks, the updated shell, what broke fixed forward) applies the same. A merged fix reaches this computer with your next update.

## Off limits

- **Never changed by a fix** (refused before the push, and again by CI): `.github/`, the fixer itself (`nixbook-shell/improve/`, `SelfImprove.qml`), the agent desktop's sandbox, the tests, `nixosModules/`, `installer/`, `lib/`, `profiles/`, `npins/`, `hive.nix`, `base.nix`, the devenv files, `AGENTS.md` and `CLAUDE.md`, secrets.
- **Never merged on its own** (sensitive: what agents may do): `desktop-mcp.py`, `Ai.qml`, `AiChatSession.qml`, `Initiative.qml`, `Routines.qml`, `Config.qml` and `builtin-defaults.json`, the Desktop agents settings page, the shell's Nix files, `customPkgs/` and `homeManagerModules/`. The PR and the notification say so.

CI's **agent-guard** job (`checks.yaml`) runs `nixbook-improve guard` on every `agent/` branch, built from the base branch rather than from the PR. It checks the paths, the size and that each commit is `fix(…)` or `polish(…)` with a body and its trailer; on an `agent/feature-` branch (`--feature`), a feature's size and `feat(…)` commits with an `Agent-Feature:` trailer. A branch of reverts made by an older version is only checked for its paths. To have GitHub refuse a merge without it, make it a required check of `main`'s ruleset.

## Features it builds

**Settings → Desktop agents → Features it builds → Build the features I ask for** (`ai.improve.features.enable`, off by default) has the same fixer build what you ask nixbook to do: a new widget, setting, shortcut or behaviour. It has its own list, status line and activity in Settings, its own daily limit, and other rules; the token, model and repository are the fixes'.

- **What it builds.** Ask an agent ("I wish the bar showed the week number", "add a way to…"): its `request_feature` tool files it (`report_problem` tells agents to use it for anything bigger than a fix). You can also type it in the section. A fix the session finds too big comes here on its own, with what the session found ("Too big for a fix: …"); one found too big before that has an **As a feature** button.
- **How it goes.** Ask an agent ("did you file it?", "how's my feature going?"): its read-only `list_requests` tool reads `nixbook-improve status` and gives each fix and feature request, newest first, with when it was filed, by whom (you, through an agent or Settings, or the fixer from what it found), its status (queued, building, pull request with its link and checks, merged, skipped, too big, failed, dropped) and why. It is there while fixes or features are on.
- **How.** Like a fix, on an `agent/feature-<item>` branch, by a session with the same confinement and off-limits places, but with its own instructions: build it whole but small, reuse what exists, update the settings, docs, `KEYBINDS.md` and the assistant's answers it touches. It may change up to `maxFiles` files (15) and `maxLines` lines (600) and add files (still no deleted or binary file), with up to `budgetUsd` (8) of Claude Code and 90 minutes. It may answer _skip_ (it exists already, with how to use it; too vague; not this repository's) or _too big_ (it needs a design choice or more than that: left to you with what it would take). The same checks run.
- **The commit** is `feat(scope): …` with what it does, how to use it and how it is made, and an `Agent-Feature: <item>` trailer; the pull request has the label `agent-feature`.
- **Never merged on its own**, whatever the auto-merge switches: once CI passes you get **Feature ready** with **Merge**, **Look** and **Drop**. After a merge, main's checks and the updated shell are watched, as for a fix: what it broke is fixed forward, never reverted.
- One it can't build (a design choice only you can make, more than it may change, a place off limits, credentials, hardware, or its change failing twice) is [dropped with why](#what-it-cant-do).
- At most `perDay` (1) on its own a day, after the day's fixes (**Features a day on its own**, `0` for no limit, each run capped by **Most a feature may spend**); **Build now** starts one at once. One run at a time, fix or feature.
- **From an agent.** Say "build it now" when you ask, or later "start building that feature": the agent starts it as **Build now** does (`build_now` of `request_feature`, or `start_improvement` with the id from `list_improvements`), past the day's limit. "Fix it now" does the same for a fix (`fix_now` of `report_problem`). Ask it "how is that feature going?" and `list_improvements` tells it: queued, being made (and what it does now), pull request open with CI running, passed or failed, merged, or skipped and why. It only starts one when you ask in the chat, and only while that kind is on.

## Proposed by the agent

With **Talk to me on its own** and **Propose fixes and features of nixbook** on (Settings → Desktop agents, `ai.initiative.improveIdeas`, on by default but idle while both fixes and features are off), every two days at most the small model looks at what the agent saw go wrong or get in your way and may propose one fix or feature, among the kinds you have on:

- what failed in its memory (notes with failures, a failed step of a recipe), an app it couldn't find for you;
- routines you undid;
- its desktop tools' errors this week (not refusals: those are on purpose);
- the apps pairing and curiosity saw you work in (names only), its kinds of words you rarely take up or told it to stop;
- your habits, devices and networks, and the topics you care about (not people);
- what is filed already and what you turned down, so nothing is proposed twice.

It is offered in the bar with why ("Exporting your notes failed three times. Shall I ask for this feature of nixbook? …"): **Yes, do it** files it for the fixer (`note` or `request`), **Don't tell me this** remembers it and never proposes it again. It never proposes loosening what agents may do. `nixbook-desktop-mcp initiative improve` asks for one now.

## After the merge

Nothing is ever reverted: what a merge broke is fixed forward.

- **main's checks.** The merged commit's checks are watched. If one fails, a fix for it is queued (an item of its own, `regression`, picked before the others, with the merged change and its files) and a critical notification says so, with **Look**.
- **The updated shell.** Once you update (the updates widget), 5 minutes after the shell starts on a revision that contains a fix, its journal is read. A QML warning in the fix's files that the shell didn't print before, or the shell crashing and restarting, queues a fix the same way. A crash while the shell was starting doesn't count once it came back and stayed up a minute: right after an update that is the shell's own startup more than the fix, and its core dump is reported on its own.

## What it can't do

A fix or feature it can't do is **dropped** with a short reason: what the session looked at, why it can't be done here, and what would make it doable. That happens when the session says so (a place off limits, credentials, hardware, something outside nixbook, a feature needing a design choice or more than it may change), or when its change failed its checks in two runs. You get a notification, **Couldn't do: …**, with **Retry** (a run at once, from scratch), **As a feature** (for a fix) and **Dismiss** (forget it). Left unanswered, it waits in the section's **Dropped** list with the same buttons. A dropped item doesn't count toward the day's limit and is never picked again on its own. Agents see it, with its reason, through `list_requests`.

## Settings

| Setting                         | Default                  | What                                               |
| ------------------------------- | ------------------------ | -------------------------------------------------- |
| `ai.improve.enable`             | `false`                  | Make fixes on its own                              |
| `ai.improve.model`              | `"sonnet"`               | The fixing session's model (`opus`…)               |
| `ai.improve.perDay`             | `2`                      | Fixes started on their own per day                 |
| `ai.improve.maxFiles`           | `5`                      | Files a fix may change                             |
| `ai.improve.maxLines`           | `150`                    | Lines a fix may change                             |
| `ai.improve.budgetUsd`          | `3`                      | A session's spending limit (`--max-budget-usd`)    |
| `ai.improve.autoMerge`          | `false`                  | Merge low-risk fixes on its own                    |
| `ai.improve.autoMergePaths`     | `["docs/**", "**/*.md"]` | What counts as low-risk                            |
| `ai.improve.autoMergeFixes`     | `false`                  | Merge every fix on its own (never a sensitive one) |
| `ai.improve.ciIgnoreJobs`       | `["push-cache"]`         | CI jobs whose failure isn't the code's             |
| `ai.improve.repo`               | `""` (`updates.repoUrl`) | The GitHub repository                              |
| `ai.improve.features.enable`    | `false`                  | Build the features asked for                       |
| `ai.improve.features.perDay`    | `1`                      | Features started on their own per day              |
| `ai.improve.features.maxFiles`  | `15`                     | Files a feature may change                         |
| `ai.improve.features.maxLines`  | `600`                    | Lines a feature may change                         |
| `ai.improve.features.budgetUsd` | `8`                      | A feature session's spending limit                 |
| `ai.initiative.improveIdeas`    | `true`                   | The agent proposes fixes and features              |

CI's guard always uses the default limits, so raising `maxFiles` or `maxLines` (or the features') here gets a bigger change refused there.

## Command line

`nixbook-improve status` (the inbox and the runs), `stop`, `sync`, `note TEXT` (a fix), `request TEXT` (a feature), `to-feature ID` (a fix item to the features), `collect`, `run [--item ID] [--no-push]` (`--no-push`: a dry run that stops at the local commit), `merge|drop|look PR`, `token set|forget|status` (`set` reads it on stdin), `health REV`, `guard BASE [HEAD] [--feature]`. State lives in `~/.local/state/nixbook-shell/improve/`; the clone and each run's logs in `~/.local/share/nixbook-shell/improve/`.
