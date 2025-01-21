{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  configYaml = ''
    k9s:
      liveViewAutoRefresh: false
      refreshRate: 2
      maxConnRetry: 5
      readOnly: false
      noExitOnCtrlC: false
      ui:
        skin: transparent
        enableMouse: false
        headless: false
        logoless: false
        crumbsless: false
        reactive: false
        noIcons: false
        defaultsToFullScreen: false
      skipLatestRevCheck: false
      disablePodCounting: false
      shellPod:
        image: busybox:1.35.0
        namespace: default
        limits:
          cpu: 100m
          memory: 100Mi
      imageScans:
        enable: false
        exclusions:
          namespaces: []
          labels: {}
      logger:
        tail: 100
        buffer: 5000
        sinceSeconds: -1
        textWrap: false
        showTime: false
      thresholds:
        cpu:
          critical: 90
          warn: 70
        memory:
          critical: 90
          warn: 70
  '';
  transparentYaml = ''
    # -----------------------------------------------------------------------------
    # Transparent skin
    # Preserve your terminal session background color
    # -----------------------------------------------------------------------------

    # Skin...
    k9s:
      body:
        bgColor: default
      prompt:
        bgColor: default
      info:
        sectionColor: default
      dialog:
        bgColor: default
        labelFgColor: default
        fieldFgColor: default
      frame:
        crumbs:
          bgColor: default
        title:
          bgColor: default
          counterColor: default
        menu:
          fgColor: default
      views:
        charts:
          bgColor: default
        table:
          bgColor: default
          header:
            fgColor: default
            bgColor: default
        xray:
          bgColor: default
        logs:
          bgColor: default
          indicator:
            bgColor: default
            toggleOnColor: default
            toggleOffColor: default
        yaml:
          colonColor: default
          valueColor: default
  '';
  pluginsYaml = ''
    plugins:
      httproutes:
        shortCut: Shift-O
        description: Open in Browser
        dangerous: false
        scopes:
          - httproutes
        command: bash
        background: false
        confirm: false
        args:
          - -c
          - for host in $(echo "$COL-HOSTNAMES" | tr -d '[]' | tr ',' ' '); do echo "Opening https://$host"; xdg-open "https://$host" & sleep 1; done
      ingress:
        shortCut: Shift-O
        description: Open in Browser
        dangerous: false
        scopes:
          - ingresses
        command: bash
        background: false
        confirm: false
        args:
          - -c
          - "xdg-open https://$COL-HOSTS"
      neat:
        shortCut: Shift-Y
        description: Clean yaml
        dangerous: false
        scopes:
          - all
        command: bash
        background: false
        confirm: false
        args:
          - -c
          - "kubectl get $RESOURCE_NAME $COL-NAME -n $NAMESPACE -o yaml | kubectl neat | vim"
      vmssh:
        shortCut: Shift-S
        description: Connect by SSH to the VM
        dangerous: false
        scopes:
          - virtualmachines
        command: bash
        background: false
        confirm: false
        args:
          - -c
          - "virtctl ssh --local-ssh $COL-NAME -n $NAMESPACE"
      vmconsole:
        shortCut: Shift-C
        description: Enter VM console
        dangerous: false
        scopes:
          - virtualmachines
        command: bash
        background: false
        confirm: false
        args:
          - -c
          - "virtctl console $COL-NAME -n $NAMESPACE"
      kl:
        shortCut: Shift-L
        description: Logs with kl
        dangerous: false
        scopes:
          - pods
        command: bash
        background: false
        confirm: false
        args:
          - -c
          - "kl -n $NAMESPACE"
      debug-node:
        shortCut: Shift-D
        description: Add debug container for nodes
        dangerous: false
        scopes:
          - nodes
        command: bash
        background: false
        confirm: true
        args:
          - -c
          - "kubectl debug node/$COL-NAME -it --image=busybox --profile=sysadmin"
      debug-pod:
        shortCut: Shift-D
        description: Add debug pod
        dangerous: false
        scopes:
          - pods
        command: bash
        background: false
        confirm: false
        args:
          - -c
          - >-
            kubectl run -n=$NAMESPACE --overrides='{"spec": {"nodeName": "$COL-NODE"}}' --image=nicolaka/netshoot:v0.12 debug-$COL-NODE -- sleep infinity
      debug:
        shortCut: Shift-D
        description: Add debug container
        dangerous: false
        scopes:
          - containers
        command: bash
        background: false
        confirm: false
        args:
          - -c
          - "kubectl debug -it --context $CONTEXT -n=$NAMESPACE $POD --target=$NAME --image=nicolaka/netshoot:v0.12 --share-processes -- bash"
      dive:
        shortCut: d
        confirm: false
        description: "Dive image"
        scopes:
          - containers
        command: bash
        background: false
        args:
          - -c
          - "docker pull $COL-IMAGE && dive $COL-IMAGE --source=podman"
      kustomizationsuspend:
        shortCut: s
        confirm: true
        description: "Fluxcd kustomization suspend"
        scopes:
          - kustomizations
        command: bash
        background: false
        args:
          - -c
          - "flux suspend kustomization -n $NAMESPACE $COL-NAME"
      kustomizationresume:
        shortCut: r
        confirm: true
        description: "Fluxcd kustomization resume"
        scopes:
          - kustomizations
        command: bash
        background: false
        args:
          - -c
          - "flux resume kustomization -n $NAMESPACE $COL-NAME"
  '';
  didactiklabsConfYaml = ''
    k9s:
      cluster: kubernetes
      readOnly: false
      namespace:
        active: all
        lockFavorites: false
        favorites:
        - all
        - kube-system
        - default
      view:
        active: pods
      portForwardAddress: localhost
  '';
in
{
  # https://github.com/adi1090x/rofi
  config = lib.mkIf cfg.kubeTools.enable {
    home.file = {
      ".config/k9s/skins/transparent.yaml" = {
        text = transparentYaml;
      };
      ".local/share/k9s/clusters/kubernetes/kubernetes-admin@didactik.labs/config.yaml" = {
        text = didactiklabsConfYaml;
      };
      ".config/k9s/config.yaml" = {
        text = configYaml;
      };
      ".config/k9s/plugins.yaml" = {
        text = pluginsYaml;
      };
    };
  };
}
