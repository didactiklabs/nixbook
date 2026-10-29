{ pkgs }:
# MCP server for the phones paired with KDE Connect: texts, sharing, the
# phone's clipboard, ring; with KDECONNECT_MCP_READ=1 also its texts,
# notifications and contacts. Talks to kdeconnectd on the session bus. The
# source lives in ./kdeconnect-mcp (no upstream). Given only to the
# nixbook-shell side panel's V (homeManagerModules/nixbookShellConfig.nix),
# never installed on the PATH.
pkgs.buildGoModule {
  pname = "kdeconnect-mcp";
  version = "0.1.0";
  src = ./kdeconnect-mcp;
  vendorHash = "sha256-8wqotPnY18T+FsyWlR0WwOuFJHh572CYVtwu+kBAp10=";
  env.CGO_ENABLED = 0;
  # The tests run the server against a fake kdeconnectd on a private bus.
  nativeCheckInputs = [ pkgs.dbus ];

  meta = {
    description = "MCP server for the phones paired with KDE Connect: send texts, share, read messages and notifications";
    license = pkgs.lib.licenses.mit;
    mainProgram = "kdeconnect-mcp";
  };
}
