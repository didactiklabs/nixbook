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
      setAsDefaultBrowser = true;
      # https://mozilla.github.io/policy-templates/
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
        OfferToSaveLogins = false;
        # Note: Tracking protection disabled to allow third-party cookies.
        # uBlock Origin handles ad/tracker blocking instead.
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = false;
        };
      };
      profiles."default" = {
        isDefault = true;

        # Zen mods from the theme store (by UUID)
        mods = [
          "3ff55ba7-4690-4f74-96a8-9e4416685e4e" # Colored container tab
          "2317fd93-c3ed-4f37-b55a-304c1816819e" # Audio Indicator Enhanced
          "1b88a6d1-d931-45e8-b6c3-bfdca2c7e9d6" # remove tab x
          "72f8f48d-86b9-4487-acea-eb4977b18f21" # better ctrl+tab
        ];

        # Containers matching current setup
        containersForce = true;
        containers = {
          Personal = {
            color = "blue";
            icon = "fingerprint";
            id = 1;
          };
          Work = {
            color = "orange";
            icon = "briefcase";
            id = 2;
          };
          Banking = {
            color = "green";
            icon = "dollar";
            id = 3;
          };
          Shopping = {
            color = "pink";
            icon = "cart";
            id = 4;
          };
        };

        # Workspaces matching current setup
        spacesForce = true;
        spaces = {
          "Default" = {
            id = "5ff3d0e8-e140-44be-8c37-a8a02902a350";
            icon = "🎮️";
            container = 1; # Personal
            position = 1000;
          };
          "Business" = {
            id = "cb40b3b0-440e-4f00-aa84-249710108bea";
            icon = "💸";
            container = 4; # Shopping
            position = 2000;
          };
          "Work" = {
            id = "29617e20-9847-4e53-afe9-15a52c5e4c55";
            icon = "💻️";
            container = 2; # Work
            position = 3000;
          };
        };

        search = {
          force = true;
          default = "ddg";
        };

        settings = {
          # Privacy & telemetry
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.unified" = false;
          "datareporting.healthreport.uploadEnabled" = false;
          "datareporting.policy.dataSubmissionEnabled" = false;
          "browser.ping-centre.telemetry" = false;
          "app.shield.optoutstudies.enabled" = false;
          "privacy.donottrackheader.enabled" = true;
          "privacy.globalprivacycontrol.was_ever_enabled" = true;
          "privacy.clearOnShutdown_v2.formdata" = true;
          "signon.rememberSignons" = false;

          # Content blocking
          "browser.contentblocking.category" = "custom";

          # Homepage
          # "browser.startup.homepage" = "https://home.bealv.io";
          "browser.newtabpage.enabled" = false;

          # UX preferences
          "browser.tabs.warnOnClose" = false;
          "browser.download.panel.shown" = true;
          "browser.download.useDownloadDir" = false;
          "general.smoothScroll" = true;
          "general.autoScroll" = true;
          "browser.toolbars.bookmarks.visibility" = "always";
          "dom.disable_open_during_load" = false;
          "browser.bookmarks.showMobileBookmarks" = true;
          "browser.tabs.restorePinnedTabs.onStartup" = true;

          # URL bar
          "browser.urlbar.suggest.searches" = true;
          "browser.urlbar.suggest.history" = true;
          "browser.urlbar.suggest.bookmark" = true;
          "browser.urlbar.suggest.engines" = false;
          "browser.urlbar.suggest.openpage" = false;
          "browser.urlbar.placeholderName" = "DuckDuckGo";

          # Language
          "intl.accept_languages" = "en-US, en";
          "intl.regional_prefs.use_os_locales" = true;
          "browser.translations.neverTranslateLanguages" = "fr";

          # Network & prefetch
          "network.dns.disablePrefetch" = true;
          "network.http.speculative-parallel-limit" = 0;
          "network.prefetch-next" = false;

          # Cookies - allow third-party cookies
          "network.cookie.cookieBehavior" = 0;

          # Media & performance
          "media.ffmpeg.vaapi.enabled" = true;
          "gfx.webrender.all" = true;
          "layers.acceleration.force-enabled" = true;

          # Sync settings
          "services.sync.engine.history" = false;
          "services.sync.engine.passwords" = false;
          "services.sync.engine.addresses" = true;
          "services.sync.declinedEngines" = "passwords,creditcards,forms,history";

          # Zen-specific
          "zen.view.compact.toolbar-flash-popup" = true;
          "zen.view.use-single-toolbar" = false;
          "zen.view.compact.enable-at-startup" = false;
          "zen.view.switchWorkspaceOnContainerTabOpen" = true;
          "zen.urlbar.behavior" = "normal";
          "mod.sameerasw.zen_urlbar_zoom_anim" = false;

          # Audio Indicator Enhanced mod settings
          "zen.mods.AudioIndicatorEnhanced.hoverScaleAnimationEnabled" = true;
          "zen.mods.AudioIndicatorEnhanced.returnOldIcons" = true;
          "zen.mods.AudioIndicatorEnhanced.reverseAudioIcons" = false;
          "zen.mods.AudioIndicatorEnhanced.audioWave.enabled" = true;
          "zen.mods.AudioIndicatorEnhanced.bigEssentialIcons.enabled" = true;
        };

        keyboardShortcuts = [
          # Workspace switching (Alt+1-5)
          {
            id = "zen-workspace-switch-1";
            key = "1";
            modifiers.alt = true;
          }
          {
            id = "zen-workspace-switch-2";
            key = "2";
            modifiers.alt = true;
          }
          {
            id = "zen-workspace-switch-3";
            key = "3";
            modifiers.alt = true;
          }
          {
            id = "zen-workspace-switch-4";
            key = "4";
            modifiers.alt = true;
          }
          {
            id = "zen-workspace-switch-5";
            key = "5";
            modifiers.alt = true;
          }
          # Tab switching (Ctrl+1-8, Ctrl+9 for last tab)
          {
            id = "key_selectTab1";
            key = "1";
            modifiers.accel = true;
          }
          {
            id = "key_selectTab2";
            key = "2";
            modifiers.accel = true;
          }
          {
            id = "key_selectTab3";
            key = "3";
            modifiers.accel = true;
          }
          {
            id = "key_selectTab4";
            key = "4";
            modifiers.accel = true;
          }
          {
            id = "key_selectTab5";
            key = "5";
            modifiers.accel = true;
          }
          {
            id = "key_selectTab6";
            key = "6";
            modifiers.accel = true;
          }
          {
            id = "key_selectTab7";
            key = "7";
            modifiers.accel = true;
          }
          {
            id = "key_selectTab8";
            key = "8";
            modifiers.accel = true;
          }
          {
            id = "key_selectLastTab";
            key = "9";
            modifiers.accel = true;
          }
        ];

        keyboardShortcutsVersion = 16;
      };
    };

    xdg.mimeApps.defaultApplications = {
      "text/html" = "zen-twilight.desktop";
      "x-scheme-handler/http" = "zen-twilight.desktop";
      "x-scheme-handler/https" = "zen-twilight.desktop";
    };
  };
}
