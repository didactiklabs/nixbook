# Evaluates one node of a nixbook checkout exactly as `colmena build` does
# (colmena's own hive evaluator), so the installer can build and install the
# final system straight from the live ISO, without colmena's deployment step.
#
#   nix-instantiate --eval --strict --json eval-host.nix -A info \
#     --argstr repo /path/to/nixbook --argstr host totoro --argstr colmenaSrc <colmena source>
#
# base.nix imports the hardware configuration from $NIXBOOK_HARDWARE_CONFIG
# when it is set (the installer points it at /mnt/etc/nixos).
{
  repo,
  host,
  colmenaSrc,
}:
let
  hive = import "${colmenaSrc}/src/nix/hive/eval.nix" {
    rawHive = import (repo + "/hive.nix");
  };
  inherit (hive.nodes.${host}) config;
in
{
  toplevel = config.system.build.toplevel;
  # What the installer asks for before it touches the disk: the console
  # keymap the initrd unlocks LUKS with, and the accounts that need a password.
  info = {
    inherit (config.console) keyMap;
    users = builtins.filter (name: config.users.users.${name}.isNormalUser) (
      builtins.attrNames config.users.users
    );
  };
}
