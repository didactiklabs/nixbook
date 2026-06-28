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

        YubiKey SSH authentication is supported via two methods:
          1. GPG-based: GnuPG agent with enableSSHSupport (nixosModules/tools.nix)
             uses GPG authentication subkeys stored on the YubiKey smart card.
          2. FIDO2-based: ed25519-sk / ecdsa-sk keys via libfido2
             (nixosModules/tools.nix). Generate with: ssh-keygen -t ed25519-sk
             For resident keys stored on YubiKey: ssh-keygen -t ed25519-sk -O resident

        SSH keys are managed separately via agenix secrets.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*" = {
        Compression = false;
        ServerAliveInterval = 10;
        ServerAliveCountMax = 2;
      };
    };
  };
}
