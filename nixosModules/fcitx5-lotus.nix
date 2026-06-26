{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customNixOSModules.fcitx5-lotus;

  fcitx5-lotus = import ../customPkgs/fcitx5-lotus.nix { inherit pkgs; };

  invalidUsers = lib.filter (
    user: user == "" || (builtins.match "[A-Za-z_][A-Za-z0-9_-]*" user) == null
  ) cfg.users;
in
{
  options.customNixOSModules.fcitx5-lotus = {
    enable = lib.mkEnableOption ''
      Fcitx5 Lotus — an open-source Vietnamese input method for fcitx5.

      Unlike a plain fcitx5 addon, Lotus relies on a privileged uinput server
      that injects key events, so it needs system-level support: a udev rule
      granting the server access to /dev/uinput, a `uinput_proxy` system user,
      and a per-user `fcitx5-lotus-server@<user>.service` instance.

      Set `users` to the list of login users that should get a Lotus server.
      The Lotus fcitx5 addon is added to i18n.inputMethod.fcitx5.addons, so add
      "lotus" to the user's fcitx5 input-method group to use it.

      https://github.com/LotusInputMethod/fcitx5-lotus
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = fcitx5-lotus;
      defaultText = lib.literalExpression "import ../customPkgs/fcitx5-lotus.nix { inherit pkgs; }";
      description = "The fcitx5-lotus package to install.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Login users to start a system-level fcitx5-lotus-server instance for.
        Each user gets one fcitx5-lotus-server@<user>.service.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.users != [ ];
        message = "customNixOSModules.fcitx5-lotus requires at least one user. Set customNixOSModules.fcitx5-lotus.users = [ \"alice\" ];";
      }
      {
        assertion = invalidUsers == [ ];
        message = "customNixOSModules.fcitx5-lotus.users contains invalid Linux usernames: ${lib.concatStringsSep ", " invalidUsers}.";
      }
    ];

    # NOTE: the Lotus fcitx5 *addon* is added in the user's Home Manager
    # fcitx5 config (customHomeManagerModules.fcitx5Config.lotus = true), since
    # this repo configures i18n.inputMethod at the Home Manager level, not the
    # system level. This module only provides the system-level pieces the Lotus
    # server needs (uinput access, the proxy user and the per-user service).

    users.users.uinput_proxy = {
      isSystemUser = true;
      group = "input";
    };

    services.udev.packages = [ cfg.package ];
    systemd.packages = [ cfg.package ];

    systemd.targets.multi-user.wants = map (user: "fcitx5-lotus-server@${user}.service") cfg.users;
  };
}
