{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  options.customHomeManagerModules.zenBrowserConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Zen Browser, a privacy-focused Firefox fork.

        Configures Zen Browser (twilight) via its Home Manager module with
        sensible defaults: telemetry and studies disabled, tracking protection
        enabled, Pocket disabled, and smooth scrolling turned on.

        When enabled, sets Zen as the default browser for http/https/html MIME types.
      '';
    };
  };
  config = lib.mkIf cfg.zenBrowserConfig.enable {
    programs.zen-browser = {
      enable = true;
      policies = {
        AutofillAddressEnabled = true;
        AutofillCreditCardEnabled = false;
        DisableAppUpdate = true;
        DisableFeedbackCommands = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = true;
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };
      };
      profiles."default" = {
        isDefault = true;
        settings = {
          # Privacy & telemetry
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.unified" = false;
          "datareporting.healthreport.uploadEnabled" = false;
          "datareporting.policy.dataSubmissionEnabled" = false;
          "browser.ping-centre.telemetry" = false;
          "app.shield.optoutstudies.enabled" = false;

          # UX preferences
          "browser.tabs.warnOnClose" = false;
          "browser.download.panel.shown" = true;
          "general.smoothScroll" = true;
          "browser.urlbar.suggest.searches" = true;
          "browser.urlbar.suggest.history" = true;
          "browser.urlbar.suggest.bookmark" = true;

          # Media & performance
          "media.ffmpeg.vaapi.enabled" = true;
          "gfx.webrender.all" = true;
          "layers.acceleration.force-enabled" = true;
        };
      };
    };

    xdg.mimeApps.defaultApplications = {
      "text/html" = "zen.desktop";
      "x-scheme-handler/http" = "zen.desktop";
      "x-scheme-handler/https" = "zen.desktop";
    };
  };
}
