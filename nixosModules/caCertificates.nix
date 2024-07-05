{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customNixOSModules;
  sources = builtins.toString ../.;
in {
  options.customNixOSModules.caCertificates = {
    bealv.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable caCertificates globally or not.
      '';
    };
    didactiklabs.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable caCertificates globally or not.
      '';
    };
  };
  config = {
    security.pki.certificateFiles =
      [
        "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ]
      ++ lib.optional cfg.caCertificates.bealv.enable ../assets/certs/bealv-ca.crt
      ++ lib.optional cfg.caCertificates.didactiklabs.enable ../assets/certs/didactiklabs-ca.crt;
    system.activationScripts.didactiklabsCa = lib.mkIf cfg.caCertificates.didactiklabs.enable {
      text = ''
        install -m 644 ${sources}/assets/certs/didactiklabs-ca.crt /etc/ssl/certs/didactiklabs-ca.crt
      '';
    };
  };
}
