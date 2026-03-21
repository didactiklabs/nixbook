{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
in
{
  options.customNixOSModules.caCertificates = {
    bealv.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to install the Bealv internal CA certificate system-wide.

        Adds assets/certs/bealv-ca.crt to the system PKI trust store and
        exposes it at /etc/ssl/certs/bealv-ca.crt so tools like curl, git,
        and browsers trust internal Bealv HTTPS endpoints without warnings.
      '';
    };
    didactiklabs.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to install the DidactikLabs internal CA certificate system-wide.

        Adds assets/certs/didactiklabs-ca.crt to the system PKI trust store
        and exposes it at /etc/ssl/certs/didactiklabs-ca.crt so all system
        tools trust internal DidactikLabs HTTPS endpoints (e.g. the Atuin
        sync server, private container registries, etc.).
      '';
    };
    logicmg.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to install the LogicMG internal CA certificate system-wide.

        Adds assets/certs/logicmg-ca.crt to the system PKI trust store so
        all system tools trust internal LogicMG HTTPS endpoints.

        Used on: nishinoya (aamoyel's machine).
      '';
    };
  };
  config = {
    security.pki.certificateFiles = [
      "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ]
    ++ lib.optional cfg.caCertificates.bealv.enable ../assets/certs/bealv-ca.crt
    ++ lib.optional cfg.caCertificates.didactiklabs.enable ../assets/certs/didactiklabs-ca.crt
    ++ lib.optional cfg.caCertificates.logicmg.enable ../assets/certs/logicmg-ca.crt;
    environment.etc = {
      "ssl/certs/ca-certs.crt" = {
        source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        mode = "0644";
      };
      "ssl/certs/didactiklabs-ca.crt" = lib.mkIf cfg.caCertificates.didactiklabs.enable {
        source = ../assets/certs/didactiklabs-ca.crt;
        mode = "0644";
      };
      "ssl/certs/bealv-ca.crt" = lib.mkIf cfg.caCertificates.bealv.enable {
        source = ../assets/certs/bealv-ca.crt;
        mode = "0644";
      };
    };
  };
}
