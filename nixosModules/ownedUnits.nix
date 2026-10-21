{ lib, options, ... }:
# Which systemd units this repository defines or configures itself (in its
# own module files, not NixOS's), for the desktop agent's fixer
# (nixbook-improve): a failed unit or an error in its log is something a
# nixbook PR can fix; anything else is listed as "not nixbook's" and never
# sent to it. /etc/nixbook/owned-units.json: {services: [...], timers: [...]}
let
  ours = import ../lib/ownedUnits.nix { inherit lib; } (toString ../.);
in
{
  environment.etc."nixbook/owned-units.json".text = builtins.toJSON {
    services = ours options.systemd.services.definitionsWithLocations;
    timers = ours options.systemd.timers.definitionsWithLocations;
  };
}
