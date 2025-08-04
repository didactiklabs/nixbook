{
  config,
  pkgs,
  ...
}:
let
  # When using easyCerts=true the IP Address must resolve to the master on creation.
  # So use simply 127.0.0.1 in that case. Otherwise you will have errors like this https://github.com/NixOS/nixpkgs/issues/59364
  kubeMasterIP = "10.207.7.1";
  kubeMasterHostname = "anya";
  kubeMasterAPIServerPort = 6443;
in
{
  # resolve master hostname
  networking.extraHosts = "${kubeMasterIP} ${kubeMasterHostname}";

  # packages for administration tasks
  environment.systemPackages = with pkgs; [
    kompose
    kubectl
    kubernetes
  ];
  services = {
    kubernetes = {
      roles = [
        "master"
        "node"
      ];
      masterAddress = kubeMasterHostname;
      apiserverAddress = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
      easyCerts = true;
      apiserver = {
        securePort = kubeMasterAPIServerPort;
        advertiseAddress = kubeMasterIP;
      };

      # use coredns
      addons.dns.enable = true;
      addons.dns.corefile = ''
        .:10053 {
          errors
          health :10054
          kubernetes ${config.services.kubernetes.addons.dns.clusterDomain} in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
          }
          prometheus :10055
          forward . 10.207.0.1
          cache 30
          loop
          reload
          loadbalance
        }
      '';

      # needed if you use swap
      kubelet.extraOpts = "--fail-swap-on=false";
      apiserver.extraOpts = "--allow-privileged=true";
    };
    nfs.server.enable = true;
    nfs.server.exports = ''
      /data/nfs/hdda         ${kubeMasterIP}(rw,async,no_subtree_check,no_root_squash,crossmnt)
    '';
  };
}
