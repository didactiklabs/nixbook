# Deploy & update

Machines are deployed with [Colmena](https://github.com/zhaofengli/colmena) running **locally** on each machine: every node in `hive.nix` allows local deployment and builds on the target, and SSH deployment is not used.

## First deployment

On a machine already running NixOS whose hostname matches a profile:

```bash
git clone https://github.com/didactiklabs/nixbook
cd nixbook
colmena apply-local --sudo -v switch
```

`base.nix` imports `/etc/nixos/hardware-configuration.nix`, so the machine's generated hardware configuration must exist there.

::: tip
Users created with `mkUser` may run `colmena` through `sudo` without a password, so deployments never prompt.
:::

## Updating

### `osupdate`

```bash
osupdate           # refuses to run while offline
osupdate --force   # skip the network check (or OSUPDATE_FORCE=1)
```

`osupdate` (installed by the `tools` module):

1. checks the network (`nm-online`, 30 s) unless forced;
2. resolves the latest `main` revision of the nixbook repository;
3. runs [`ginx`](/packages/#ginx) to fetch that revision and run `colmena apply-local` in it;
4. verifies that `/etc/nixos/version` now records that revision, and **exits non-zero** if it does not (ginx itself exits 0 even when its command fails).

The same update can run without a terminal as the `nixos-upgrade-manual.service` systemd unit (niced, idle I/O, two-hour timeout), which is what the desktop shells' **update widgets** trigger — passwordless through polkit.

### Manually, without the helper

```bash
ginx --source https://github.com/didactiklabs/nixbook -b main --now -- colmena apply-local --sudo
```

Or from a local checkout (to test uncommitted changes):

```bash
colmena apply-local --sudo
```

A deployment from a tree with uncommitted changes is recorded as **dirty** in `/etc/nixos/version`, together with the commit the changes were made on.

### Update widgets

Both desktop shells show whether the machine is behind `main`:

- **nixbook-shell** — the _Updates_ bar widget compares `/etc/nixos/version` with the repository (`updates.repoUrl`). Hover for the deployed revision, branch and the last run's result; click for a panel with **Check**, **Execute** (runs `nixos-upgrade-manual.service`), the changelog, and a live journal of the run. Right-click re-checks. See [Bar, launcher & panels](/nixbook-shell/bar-and-panels#updates).
- **DankMaterialShell** — the `nixosUpdate` plugin (`dmsConfig.enableNixosUpdate`) does the same from the DMS bar.

## Rolling back

Every deployment is a NixOS generation. To go back:

- pick an older generation in the boot menu, or
- `sudo nixos-rebuild switch --rollback`, or
- check out an older commit and `colmena apply-local --sudo`.

## Checking what is deployed

```bash
jq . /etc/nixos/version
```

```json
{
  "url": "https://github.com/didactiklabs/nixbook",
  "branch": "main",
  "rev": "266b7318…",
  "dirty": false,
  "lastModifiedDate": "…"
}
```
