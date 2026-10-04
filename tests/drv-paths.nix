/*
  The system derivation (toplevel .drv) of every colmena node, without building
  anything. CI (tests/changed-hosts.sh, .github/workflows/build.yaml) compares
  them between two commits and only builds the machines whose system changed.

    colmena eval -E '(import ./tests/drv-paths.nix)'   # { "<node>": "/nix/store/…-nixos-system-….drv", … }

  getRevision is switched off: /etc/nixos/version embeds the commit, so every
  commit would otherwise change every machine. Nothing else differs from what
  `colmena build` evaluates.
*/
{ nodes, lib, ... }:
lib.mapAttrs (
  _: node:
  (node.extendModules {
    modules = [ { customNixOSModules.getRevision.enable = lib.mkForce false; } ];
  }).config.system.build.toplevel.drvPath
) nodes
