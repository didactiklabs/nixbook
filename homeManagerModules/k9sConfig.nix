{ config, lib, ... }:
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
in
{
  # https://github.com/adi1090x/rofi
  config = lib.mkIf cfg.kubeTools.enable {
    home.file.".config/k9s/skins/transparent.yaml" = {
      text = transparentYaml;
    };
    home.file.".config/k9s/config.yaml" = {
      text = configYaml;
    };
  };
}
