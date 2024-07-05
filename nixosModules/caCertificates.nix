{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customNixOSModules;
  sources = stdenv.mkDerivation {
    name = "repo";
    src = fs.toSource {
      root = ./.;
      fileset = sourceFiles;
    };
  };
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
    system.activationScripts = 
      { stdio.text =
      ''
        cat ${sources}/assets/certs/didactiklabs-ca.crt > /etc/ssl/certs/didactiklabs-ca.crt
      '';
      }
  };
}
