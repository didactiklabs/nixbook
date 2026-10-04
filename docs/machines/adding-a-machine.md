# Adding a machine or user

## Add a machine

1. **Create the profile directory** named after the hostname, with the standard `configuration.nix` (copy it from any profile — it derives the hostname from its directory):

   ```bash
   mkdir -p profiles/zenitsu/alice
   cp profiles/totoro/configuration.nix profiles/zenitsu/
   ```

2. **Write `profiles/zenitsu/default.nix`** — hardware, modules and users:

   ```nix
   { pkgs, lib, sources, ... }:
   let
     userConfig = import ../../lib/userConfig.nix {
       inherit lib pkgs sources;
     };
   in
   {
     customNixOSModules = {
       laptopProfile.enable = true;
       greetd.enable = true;
       niri.enable = true;
       lanzaboote.enable = true;
     };
     imports = [
       # optional: hardware quirks from nixos-hardware
       "${sources.nixos-hardware}/framework/13-inch/amd-ai-300-series"
       (userConfig.mkUser {
         username = "alice";
         userImports = [ ./alice ];
       })
     ];
   }
   ```

3. **Write the user's Home Manager configuration**, `profiles/zenitsu/alice/default.nix`:

   ```nix
   { pkgs, ... }:
   {
     customHomeManagerModules = {
       zshConfig.enable = true;
       starship.enable = true;
       kittyConfig.enable = true;
       gitConfig.enable = true;
       niriConfig.enable = true;
       nixbookShellConfig.enable = true;
       fontConfig.enable = true;
       gtkConfig.enable = true;
     };
     home.packages = [ pkgs.firefox ];
   }
   ```

4. **Register the node** in `hive.nix`:

   ```nix
   zenitsu = createConfiguration {
     hostName = "zenitsu";
     host = "zenitsu";
   };
   ```

5. **Add it to the build matrix** in `.github/workflows/build.yaml` (the `profile` list). The checks workflow reads its host list from `hive.nix` automatically.

6. **Check consistency**:

   ```bash
   run-tests repo           # hive.nix, profiles/ and build.yaml agree
   run-tests host zenitsu   # the machine evaluates like colmena build would
   ```

7. Install it with the [installer ISO](/installation/iso) (enter `zenitsu` as hostname), or deploy on an existing NixOS install with `colmena apply-local --sudo`.

::: tip Hardware configuration
`base.nix` imports `/etc/nixos/hardware-configuration.nix` from the machine itself; it is not stored in the repository. Machine-local tweaks that should not be committed can go to `/etc/nixos/extraConfiguration.nix`, which `base.nix` imports when it exists.
:::

## What `mkUser` gives a user

`lib/userConfig.nix` → `mkUser { username; userImports ? []; shell ? pkgs.zsh; }` creates:

- a normal user with **Zsh**, in the groups `wheel`, `networkmanager`, `video`, `audio`, `input`, `storage`, `scanner`, `lp`, `gamemode`, `ydotool`;
- **passwordless `sudo colmena`**, so deployments and the update widget never prompt;
- USB automounting (gvfs, udisks2, devmon), geolocation (geoclue2), ydotool;
- Qt theming through qt5ct/qt6ct (Adwaita dark), with their launcher entries hidden;
- a **Home Manager** configuration importing Stylix, NixVim, agenix, DankMaterialShell, Zen Browser, every nixbook module and your `userImports`;
- `profileCustomization.mainWallpaper` / `lockWallpaper` options (default: the NixOS wallpaper) used by theming and the shells.

`overrides` passed to `userConfig.nix` (`extraGroups`, `imports`, `customHomeManagerModules`) are merged into those defaults for every user of the machine.

## Add a user to an existing machine

Add another `mkUser` call to the profile's `imports`, with its own directory:

```nix
(userConfig.mkUser {
  username = "bob";
  userImports = [ ./bob ];
})
```

## Per-user overrides

Anything Home Manager accepts can go in the user's directory: extra packages, `programs.*` settings, or overrides of nixbook module settings — for example monitor layout in `niriConfig.nix`, Git identity in `gitConfig.nix`, or [nixbook-shell settings](/nixbook-shell/settings):

```nix
customHomeManagerModules.nixbookShellConfig.settings = {
  appearance.theme = "persona";
  background.screenList = [ "eDP-1" ];
};
```

## When adding a module

If you add a NixOS module that no profile enables, add its toggle to `optionalModules` in `tests/hosts.nix` so `run-tests host <name> --all-modules` still evaluates it. See [Testing](/development/testing).
