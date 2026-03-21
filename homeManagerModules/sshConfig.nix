{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.sshConfig;
in
{
  options.customHomeManagerModules.sshConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable SSH client configuration.

        Configures programs.ssh with sensible keep-alive defaults applied to
        all hosts (Match *):
          - compression: false    — disabled to reduce CPU overhead on fast links
          - serverAliveInterval: 10s  — send a keep-alive every 10 seconds
          - serverAliveCountMax: 2    — disconnect after 2 missed keep-alives (20s)

        enableDefaultConfig = false so NixOS's generated defaults do not
        conflict with this configuration.

        SSH keys are managed separately via agenix secrets.
        The GnuPG agent SSH socket (YubiKey SSH) is configured at the
        system level in nixosModules/tools.nix.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."*" = {
        compression = false;
        serverAliveInterval = 10;
        serverAliveCountMax = 2;
      };
    };
  };
}
