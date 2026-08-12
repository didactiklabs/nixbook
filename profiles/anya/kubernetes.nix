{
  # config,
  lib,
  pkgs,
  ...
}:
# let
# When using easyCerts=true the IP Address must resolve to the master on creation.
# So use simply 127.0.0.1 in that case. Otherwise you will have errors like this https://github.com/NixOS/nixpkgs/issues/59364
# kubeMasterIP = "10.207.7.1";
# kubeMasterHostname = "anya";
# kubeMasterAPIServerPort = 6443;
# in
{
  # resolve master hostname
  # networking.extraHosts = "${kubeMasterIP} ${kubeMasterHostname}";

  # packages for administration tasks
  environment.systemPackages = with pkgs; [
    # kompose
    kubectl
    kubernetes
  ];

  # --- kubeadm worker node prerequisites ---
  # `kubeadm join` needs a CRI runtime (containerd with the CRI plugin)
  # reachable at /var/run/containerd/containerd.sock, plus the kubelet
  # binary/service and the usual kernel networking bits.

  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins."io.containerd.grpc.v1.cri" = {
        # kubeadm defaults to the systemd cgroup driver on cgroup v2
        containerd.runtimes.runc.options.SystemdCgroup = true;
        # sandbox (pause) image kubeadm expects
        sandbox_image = "registry.k8s.io/pause:3.10";
      };
    };
  };

  # kubelet: provide the binary and the (kubeadm-managed) service.
  # kubeadm writes the actual config/flags into
  # /var/lib/kubelet and /etc/kubernetes, so we only give it a stub unit
  # that is enabled but not started until kubeadm drops in its config.
  systemd.services.kubelet = {
    description = "Kubernetes Kubelet (managed by kubeadm)";
    wantedBy = [ "multi-user.target" ];
    after = [ "containerd.service" ];
    requires = [ "containerd.service" ];
    path = with pkgs; [
      kubernetes
      util-linux
      iproute2
      ethtool
      socat
      iptables
      conntrack-tools
    ];
    serviceConfig = {
      ExecStart = "${pkgs.kubernetes}/bin/kubelet \\
        --kubeconfig=/etc/kubernetes/kubelet.conf \\
        --config=/var/lib/kubelet/config.yaml \\
        --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock";
      Restart = "always";
      RestartSec = "10s";
    };
    # Don't crash-loop before kubeadm has written the config files.
    unitConfig.ConditionPathExists = "/var/lib/kubelet/config.yaml";
  };

  # Networking prerequisites for the pod network / kube-proxy.
  boot.kernelModules = [
    "br_netfilter"
    "overlay"
  ];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
  };
  # services = {
  #   kubernetes = {
  #     roles = [
  #       "master"
  #       "node"
  #     ];
  #     masterAddress = "${kubeMasterIP}";
  #     apiserverAddress = "https://${kubeMasterIP}:${toString kubeMasterAPIServerPort}";
  #     easyCerts = true;
  #     apiserver = {
  #       securePort = kubeMasterAPIServerPort;
  #       advertiseAddress = kubeMasterIP;
  #       serviceClusterIpRange = "10.244.0.0/16";
  #       extraSANs = [
  #         "10.0.0.1"
  #         "anya"
  #         "10.244.0.1"
  #         "${kubeMasterIP}"
  #       ];
  #     };
  #
  #     # use coredns
  #     addons.dns.enable = true;
  #     addons.dns.corefile = ''
  #       .:10053 {
  #         errors
  #         health :10054
  #         kubernetes ${config.services.kubernetes.addons.dns.clusterDomain} in-addr.arpa ip6.arpa {
  #           pods insecure
  #           fallthrough in-addr.arpa ip6.arpa
  #         }
  #         prometheus :10055
  #         forward . 10.207.0.1
  #         cache 30
  #         loop
  #         reload
  #         loadbalance
  #       }
  #     '';
  #
  #     # needed if you use swap
  #     kubelet.extraOpts = "--fail-swap-on=false";
  #     apiserver.extraOpts = "--allow-privileged=true";
  #   };
  #   nfs.server.enable = true;
  #   nfs.server.exports = ''
  #     /data/nfs/hdda         ${kubeMasterIP}(rw,async,no_subtree_check,no_root_squash,crossmnt)
  #   '';
  # };
}
