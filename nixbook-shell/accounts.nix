{ pkgs }:
# nixbook-accounts (accounts/): the shell's accounts backend. The user's
# accounts (Google, with the user's own OAuth client: DankCalendar's built-in
# one is for DankCalendar only), secrets in the keyring through secret-tool,
# and their contacts and tasks merged; the calendar is to move here from
# DankCalendar.
pkgs.buildGoModule {
  pname = "nixbook-accounts";
  version = "0.1.0";
  src = ./accounts;
  vendorHash = "sha256-dpopbsJFmPMKOBwsH5wToupxOz3WCtvzPqW4GvvcM0w=";
  env.CGO_ENABLED = 0;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postInstall = ''
    mv $out/bin/accounts $out/bin/nixbook-accounts
    wrapProgram $out/bin/nixbook-accounts --prefix PATH : ${
      pkgs.lib.makeBinPath [
        pkgs.libsecret # secret-tool: the client and token in the keyring
        pkgs.xdg-utils # xdg-open: the providers' sign-in pages
      ]
    }
  '';
  meta.mainProgram = "nixbook-accounts";
}
