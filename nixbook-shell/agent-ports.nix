{
  config,
  lib,
  pkgs,
  ...
}:
# The debugging ports desktop-mcp's browser and discord tools use (Zen's
# WebDriver BiDi, Vesktop's DevTools, Home Manager's desktopMcp.zen and
# desktopMcp.vesktop): the apps bind them to 127.0.0.1 already, so nothing
# off this machine reaches them; this nftables table makes sure of it (a
# packet to them coming in on any other interface is dropped, whatever the
# app binds) and keeps the other local users off them (only the user whose
# app it is may connect). A table of its own, loaded by its own unit: the
# rest of the ruleset (the NixOS firewall, Tailscale's, Podman's) is left
# alone, and nftables needn't be the system's firewall.
#
# Not a wall between the user's own programs: anything running as that user
# can connect (as it can read the apps' profiles anyway).
let
  cfg = config.nixbook-shell.agentPorts;
  hmUsers = config.home-manager.users or { };
  # [ { user; port; } ] of each Home Manager user's enabled debugging ports.
  ports = lib.concatLists (
    lib.mapAttrsToList (
      user: hm:
      let
        mcp = hm.programs.nixbook-shell.desktopMcp or { };
        one =
          app:
          lib.optional (mcp.${app}.enable or false) {
            inherit user;
            inherit (mcp.${app}) port;
          };
      in
      one "zen" ++ one "vesktop"
    ) hmUsers
  );
  allPorts = lib.concatMapStringsSep ", " (p: toString p.port) ports;
  rules = ''
    chain input {
      type filter hook input priority filter - 10; policy accept;
      # From another machine: never, whatever address the app binds.
      tcp dport { ${allPorts} } iifname != "lo" drop
    }
    chain output {
      type filter hook output priority filter - 10; policy accept;
      # On this machine: only the user whose app it is.
      ${lib.concatMapStringsSep "\n  " (
        p: ''tcp dport ${toString p.port} oifname "lo" meta skuid != "${p.user}" reject with tcp reset''
      ) ports}
    }
  '';
  ruleset = pkgs.writeText "nixbook-agent-ports.nft" ''
    table inet nixbook-agent-ports {
    ${rules}
    }
  '';
  nft = lib.getExe pkgs.nftables;
in
{
  options.nixbook-shell.agentPorts.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether to firewall the debugging ports Home Manager users open for
      desktop-mcp (`programs.nixbook-shell.desktopMcp.zen` and `.vesktop`):
      dropped when they come from another machine, and refused to the other
      local users. A table of its own (`inet nixbook-agent-ports`), loaded
      by `nixbook-agent-ports.service`, independent of the NixOS firewall.
      Does nothing while no user opens such a port.
    '';
  };

  config = lib.mkIf (cfg.enable && ports != [ ]) {
    # With NixOS's nftables, a table of its ruleset (its reloads flush the rest).
    networking.nftables.tables.nixbook-agent-ports = lib.mkIf config.networking.nftables.enable {
      family = "inet";
      content = rules;
    };
    # Otherwise (iptables firewall, or none), loaded on its own.
    systemd.services.nixbook-agent-ports = lib.mkIf (!config.networking.nftables.enable) {
      description = "Firewall desktop-mcp's app debugging ports";
      wantedBy = [ "multi-user.target" ];
      before = [ "network-pre.target" ];
      wants = [ "network-pre.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "-${nft} delete table inet nixbook-agent-ports";
        ExecStart = "${nft} -f ${ruleset}";
        ExecStop = "${nft} delete table inet nixbook-agent-ports";
      };
    };
  };
}
