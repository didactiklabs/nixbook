{ config, pkgs, lib, ... }:
let cfg = config.customNixOSModules;
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
    logicmg.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable caCertificates globally or not.
      '';
    };
  };
  config = {
    security.pki.certificateFiles =
      [ "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ]
      ++ lib.optional cfg.caCertificates.bealv.enable
      ../assets/certs/bealv-ca.crt
      ++ lib.optional cfg.caCertificates.didactiklabs.enable
      ../assets/certs/didactiklabs-ca.crt
      ++ lib.optional cfg.caCertificates.logicmg.enable
      ../assets/certs/logicmg-ca.crt;
    environment.etc = {
      "ssl/certs/didactiklabs-ca.crt" = {
        source = ../assets/certs/didactiklabs-ca.crt;
        mode = "0644";
      };
    };
  };
}
