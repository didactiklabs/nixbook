# The internal CAs of nixosModules/caCertificates.nix, for macOS. nix-darwin's
# security.pki builds /etc/ssl/certs/ca-certificates.crt (Nix's tools, curl,
# git from Nix); apps using the macOS keychain don't read it (Safari, the App
# Store apps): those need the certificate in the keychain, by hand.
{
  config,
  lib,
  ...
}:
let
  cfg = config.customDarwinModules.caCertificates;
  certs = {
    rpcu = ../assets/certs/rpcu-ca.crt;
    bealv = ../assets/certs/bealv-ca.crt;
    didactiklabs = ../assets/certs/didactiklabs-ca.crt;
    logicmg = ../assets/certs/logicmg-ca.crt;
  };
in
{
  options.customDarwinModules.caCertificates = lib.mapAttrs (name: _: {
    enable = lib.mkEnableOption "the ${name} internal CA certificate in Nix's trust store";
  }) certs;

  config.security.pki.certificateFiles = lib.attrValues (
    lib.filterAttrs (name: _: cfg.${name}.enable) certs
  );
}
