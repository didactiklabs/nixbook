{
  lib,
  pkgs,
  ...
}:
{

  # packages for administration tasks
  environment.systemPackages = with pkgs; [
    # kompose
    kubectl
    kubernetes # provides kubeadm + kubelet binaries
  ];

  # --- kubeadm worker node prerequisites ---
  #
  # This mirrors the approach used in the ../hephaestus control-plane setup
  # (nixosModules/kubernetes/default.nix), reduced to what a node that only
  # runs `kubeadm join` as a worker needs:
  #   * a containerd CRI runtime at /var/run/containerd/containerd.sock
  #   * a kubelet systemd unit shaped the way kubeadm expects (env-file driven)
  #   * a writable /opt/cni/bin populated with the upstream CNI plugins
  #   * the standard kubernetes sysctls / kernel modules

  boot.kernelModules = [
    "br_netfilter"
    "overlay"
  ];
  boot.kernel.sysctl = {
    # net.ipv4.ip_forward is already enabled in nixosModules/core.nix
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins = {
        "io.containerd.grpc.v1.cri" = {
          # CNI pods drop their binaries here (see prepareCniDir below).
          cni.bin_dir = "/opt/cni/bin";
          device_ownership_from_security_context = true;
        };
        "io.containerd.grpc.v1.cri".containerd.runtimes.runc = {
          runtime_type = "io.containerd.runc.v2";
        };
        # kubeadm defaults to the systemd cgroup driver on cgroup v2.
        "io.containerd.grpc.v1.cri".containerd.runtimes.runc.options = {
          SystemdCgroup = true;
        };
      };
    };
  };

  # CNI needs a writable /opt/cni/bin outside the nix store where the pod
  # network (flannel/calico/cilium ...) can also drop its own binaries.
  system.activationScripts.prepareCniDir.text = ''
    mkdir -p /opt/cni/bin
    for cnibin in ${pkgs.cni-plugins}/bin/*; do
      ln -sf "$cnibin" /opt/cni/bin/"$(basename "$cnibin")"
    done
  '';

  # kubeadm creates these on join; pre-create the parent dirs so the kubelet
  # and containerd don't race on first boot.
  systemd.tmpfiles.rules = [
    "d /etc/kubernetes 0755 root root -"
    "d /etc/kubernetes/manifests 0755 root root -"
    "d /opt/cni/bin 0755 root root -"
  ];

  # kubelet unit, shaped exactly the way kubeadm expects (same layout as the
  # upstream image-builder / kubeadm systemd dropin, ported from hephaestus).
  #
  # kubeadm join drives the kubelet in two stages:
  #   1. writes /etc/kubernetes/bootstrap-kubelet.conf + /var/lib/kubelet/config.yaml
  #      and /var/lib/kubelet/kubeadm-flags.env, then (re)starts the kubelet.
  #   2. the kubelet uses the bootstrap kubeconfig to TLS-bootstrap and writes
  #      its own /etc/kubernetes/kubelet.conf.
  #
  # The flags live in split env vars; the kubeadm-flags.env EnvironmentFile is
  # optional (leading '-') so the unit doesn't fail before join has run. It is
  # Restart=always with no ConditionPathExists, so it simply retries until
  # kubeadm has laid down the files.
  systemd.services.kubelet = {
    enable = true;
    description = "kubelet: The Kubernetes Node Agent";
    documentation = [ "https://kubernetes.io/docs/home/" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "containerd.service" ];
    wants = [ "containerd.service" ];
    path = [
      "/opt/cni/bin"
      pkgs.kubernetes
      pkgs.util-linux
      pkgs.file
      pkgs.iproute2
      pkgs.iptables
      pkgs.socat
      pkgs.ethtool
      pkgs.conntrack-tools
    ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 10;
      Environment = [
        ''KUBELET_KUBECONFIG_ARGS="--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"''
        ''KUBELET_CONFIG_ARGS="--config=/var/lib/kubelet/config.yaml --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock --fail-swap-on=false"''
      ];
      # kubeadm writes kubeadm-flags.env during join; both files are optional.
      EnvironmentFile = [
        "-/var/lib/kubelet/kubeadm-flags.env"
        "-/etc/sysconfig/kubelet"
      ];
      ExecStart = [
        "${pkgs.kubernetes}/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS"
      ];
    };
  };
}
