{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules.sshConfig;
in {
  options.customHomeManagerModules.sshConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable sshConfig globally or not
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      compression = true;
      serverAliveInterval = 10;
      serverAliveCountMax = 2;
    };
  };
}
