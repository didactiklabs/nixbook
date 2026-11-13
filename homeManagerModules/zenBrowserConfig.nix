{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  shell = cfg.nixbookShellConfig;
  # nixbook-shell's desktop agents in Zen (nixbookShellConfig.zenAgent).
  agent = shell.enable && shell.zenAgent.enable;
  zenAgent = config.programs.nixbook-shell.package.passthru.zenAgent;
  # YouTube links opened by the shell (nixbookShellConfig.youtubeLinks): an
  # extension for Zen, the shell asked first by the router for other apps.
  youtubeLinks = shell.enable && shell.youtubeLinks.enable;
  ytLinks = config.programs.nixbook-shell.package.passthru.youtubeLinks;

  # Links opened in apps (openInApps): a router for xdg-open's http(s)
  # links, and a Zen extension + native host for the links clicked in Zen.
  openInApps = cfg.zenBrowserConfig.openInApps;
  openHosts = lib.attrNames openInApps;
  # The router stands in for Zen as the http(s) handler when either needs it.
  routed = openInApps != { } || youtubeLinks;
  zenExe = lib.getExe' config.programs.zen-browser.finalPackage "zen-twilight";
  router = pkgs.writeShellScriptBin "nixbook-open-url" ''
    # The http(s) link handler (xdg-open, $BROWSER): a YouTube video or
    # YouTube Music song or playlist to the shell (nixbookShellConfig.youtubeLinks),
    # a link on one of zenBrowserConfig.openInApps' hosts to its app,
    # anything else to Zen. The app is started detached (through niri when it can: a
    # scope of its own), so this returns at once.
    url="''${1-}"
    host=""
    case "$url" in
      [hH][tT][tT][pP]://* | [hH][tT][tT][pP][sS]://*)
        host=''${url#*://}
        host=''${host%%[/?#]*}
        host=''${host##*@}
        host=''${host%%:*}
        host=''${host,,}
        ;;
    esac
    ${lib.optionalString youtubeLinks ''
      # YouTube videos and YouTube Music songs and playlists: the shell
      # (nixbookShellConfig.youtubeLinks), unless it can't take the link.
      case "$host" in
        youtube.com | www.youtube.com | m.youtube.com | music.youtube.com | youtu.be)
          if [ "$#" -eq 1 ] && ${ytLinks.open}/bin/nixbook-youtube-link "$url"; then
            exit 0
          fi
          ;;
      esac
    ''}
    app=""
    case "$host" in
    ${lib.concatStrings (
      lib.mapAttrsToList (h: cmd: ''
        ${lib.escapeShellArg h}) app=${lib.escapeShellArg cmd} ;;
      '') openInApps
    )}
    esac
    if [ -n "$app" ] && [ "$#" -eq 1 ]; then
      if [ -n "''${NIRI_SOCKET-}" ] && command -v niri >/dev/null 2>&1 \
        && niri msg action spawn -- "$app" "$url" >/dev/null 2>&1; then
        exit 0
      fi
      ${pkgs.util-linux}/bin/setsid -f "$app" "$url" </dev/null >/dev/null 2>&1
      exit 0
    fi
    exec ${zenExe} "$@"
  '';
  openInAppsId = "open-in-apps@nixbook";
  openInAppsExtension =
    pkgs.runCommand "nixbook-open-in-apps.xpi"
      {
        nativeBuildInputs = [ pkgs.zip ];
        manifest = builtins.toJSON {
          manifest_version = 2;
          name = "nixbook open in apps";
          version = "1.0";
          description = "Opens the links of some sites in their desktop app (nixbook's zenBrowserConfig.openInApps) instead of a tab.";
          browser_specific_settings.gecko = {
            id = openInAppsId;
            strict_min_version = "128.0";
          };
          background = {
            scripts = [
              "hosts.js"
              "links.js"
              "background.js"
            ];
            persistent = true;
          };
          permissions = [
            "webRequest"
            "webRequestBlocking"
            "nativeMessaging"
            "tabs"
          ]
          ++ map (h: "*://${h}/*") openHosts;
        };
        hosts = "const OPEN_IN_APPS = ${builtins.toJSON openHosts};\nconst SHELL_YOUTUBE_LINKS = ${lib.boolToString youtubeLinks};\n";
        passAsFile = [
          "manifest"
          "hosts"
        ];
      }
      ''
        cp $manifestPath manifest.json
        cp $hostsPath hosts.js
        cp ${./zenOpenInApps/background.js} background.js
        sed '/^\.pragma library/d' ${../nixbook-shell/src/modules/common/functions/youtube_links.js} > links.js
        zip -q -X -9 $out manifest.json hosts.js links.js background.js
      '';
  openInAppsHost =
    let
      hostConfig = pkgs.writeText "nixbook-open-in-app.json" (builtins.toJSON { apps = openInApps; });
      exe = pkgs.writeShellScript "nixbook-open-in-app" ''
        exec ${pkgs.python3}/bin/python3 -I ${./zenOpenInApps/host.py} ${hostConfig} "$@"
      '';
    in
    pkgs.runCommand "nixbook-open-in-app-host" { } ''
      mkdir -p $out/lib/mozilla/native-messaging-hosts
      cat > $out/lib/mozilla/native-messaging-hosts/nixbook_open_in_app.json <<EOF
      ${builtins.toJSON {
        name = "nixbook_open_in_app";
        description = "Opens a link in the app nixbook's zenBrowserConfig.openInApps names for its host";
        path = "${exe}";
        type = "stdio";
        allowed_extensions = [ openInAppsId ];
      }}
      EOF
    '';
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
    offerToSaveLogins = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to let Zen Browser offer to save passwords.

        When false (default), the OfferToSaveLogins policy and
        signon.rememberSignons setting are disabled so the browser never
        prompts to save logins. Set to true to enable the built-in password
        manager and the "ask to save passwords" prompt.
      '';
    };
    openInApps = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        pearDesktop.nixbookOpenLinks # { "music.youtube.com" = ".../bin/pear-desktop"; }
      '';
      description = ''
        Links opened in a desktop app instead of the browser: host → the
        command opening such a link (`COMMAND URL`, detached). Both the
        links other apps open (xdg-open: http(s) goes through a small
        router, `nixbook-open-url`, which sends everything else to Zen;
        also `$BROWSER`) and the ones clicked or typed in Zen (a
        force-installed extension stops the page load and hands the link
        to the app through a native messaging host; a tab opened for the
        link alone is closed; private windows are left alone; when the
        app can't be started the page loads in Zen as usual).

        A bridged Electron app opens its own links
        (lib/electronA11y.nix's `nixbookOpenLinks`: YouTube Music for
        music.youtube.com); most Electron apps ignore a URL on their
        command line.
      '';
    };
  };
  config = lib.mkIf cfg.zenBrowserConfig.enable {
    programs.zen-browser = lib.mkMerge [
      (lib.mkIf agent {
        # The desktop agents in Zen (nixbook-shell's zen/ extension and its
        # native host, nixbook-desktop-mcp's page_* tools): force-installed,
        # unsigned (Zen doesn't require signing; the profile turns the check
        # off), its host bridging to a private Unix socket.
        nativeMessagingHosts = [ zenAgent.host ];
        policies.ExtensionSettings.${zenAgent.extensionId} = {
          installation_mode = "force_installed";
          install_url = "file://${zenAgent.extension}";
          # In private windows too would let agents read them: not allowed.
          private_browsing = false;
        };
        profiles."default".settings."xpinstall.signatures.required" = false;
      })
      (lib.mkIf youtubeLinks {
        nativeMessagingHosts = [ ytLinks.host ];
        policies.ExtensionSettings.${ytLinks.extensionId} = {
          installation_mode = "force_installed";
          install_url = "file://${ytLinks.extension}";
          private_browsing = false;
        };
        profiles."default".settings."xpinstall.signatures.required" = false;
      })
      (lib.mkIf (openInApps != { }) {
        nativeMessagingHosts = [ openInAppsHost ];
        policies.ExtensionSettings.${openInAppsId} = {
          installation_mode = "force_installed";
          install_url = "file://${openInAppsExtension}";
          private_browsing = false;
        };
        profiles."default".settings."xpinstall.signatures.required" = false;
      })
      {
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
          OfferToSaveLogins = cfg.zenBrowserConfig.offerToSaveLogins;
          # Note: Tracking protection disabled to allow third-party cookies.
          # uBlock Origin handles ad/tracker blocking instead.
          # Tracking protection disabled globally so anti-bot captchas (e.g.
          # Skyscanner's) aren't blocked. uBlock Origin handles ad/tracker
          # blocking instead. Unlocked so it can still be toggled per-site.
          EnableTrackingProtection = {
            Value = false;
            Locked = false;
            Cryptomining = false;
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
            "signon.rememberSignons" = cfg.zenBrowserConfig.offerToSaveLogins;

            # Content blocking
            "browser.contentblocking.category" = "custom";

            # Homepage
            # "browser.startup.homepage" = "https://home.bealv.io";
            "browser.newtabpage.enabled" = false;

            # UX preferences
            "browser.tabs.warnOnClose" = false;
            # No preview card (page thumbnail) when hovering a tab: it covers
            # the neighbouring tabs.
            "browser.tabs.hoverPreview.enabled" = false;
            "browser.tabs.hoverPreview.showThumbnails" = false;
            "browser.tabs.groups.hoverPreview.enabled" = false;
            "browser.download.panel.shown" = true;
            "browser.download.useDownloadDir" = false;
            "general.smoothScroll" = true;
            "general.autoScroll" = true;
            "browser.toolbars.bookmarks.visibility" = "always";
            "dom.disable_open_during_load" = false;
            "browser.bookmarks.showMobileBookmarks" = true;
            "browser.tabs.restorePinnedTabs.onStartup" = true;

            # Golinks - treat "go" as a valid domain so go/foo resolves to http://go/foo
            "browser.fixup.domainwhitelist.go" = true;

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
            # Split view (Alt+G/V/H/U)
            {
              id = "zen-split-view-grid";
              key = "g";
              modifiers.alt = true;
            }
            {
              id = "zen-split-view-vertical";
              key = "v";
              modifiers.alt = true;
            }
            {
              id = "zen-split-view-horizontal";
              key = "h";
              modifiers.alt = true;
            }
            {
              id = "zen-split-view-unsplit";
              key = "u";
              modifiers.alt = true;
            }
            {
              id = "zen-new-empty-split-view";
              key = "*";
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

          keyboardShortcutsVersion = 21;
        };
      }
    ];

    # Zen killed while saving can leave zen-sessions.jsonlz4 empty or cut
    # (2026-10-28): the zen-browser module's session step then fails, and
    # the whole Home Manager activation with it ("Invalid magic number").
    # Set aside as Zen does itself (*.corrupt): it starts from its backups.
    # Not while Zen runs (the module skips the sessions then too).
    home.activation.zenSessionsGuard =
      let
        zen = config.programs.zen-browser;
        dir = "${zen.profilesPath}/${zen.profiles.default.path}";
      in
      lib.hm.dag.entryBetween [ "zen-browser-default" ] [ "writeBoundary" ] ''
        zenSessions="${dir}/zen-sessions.jsonlz4"
        if [ -f "$zenSessions" ] && ! ${lib.getExe pkgs.lsof} "${dir}/.parentlock" >/dev/null 2>&1 \
          && ! ${lib.getExe pkgs.mozlz4a} -d "$zenSessions" /dev/null >/dev/null 2>&1; then
          echo "zen-browser: $zenSessions can't be read; set aside as $zenSessions.nixbook.corrupt"
          run mv -f "$zenSessions" "$zenSessions.nixbook.corrupt"
        fi
      '';

    xdg.mimeApps.defaultApplications = lib.mkMerge [
      {
        "text/html" = "zen-twilight.desktop";
        "x-scheme-handler/http" = "zen-twilight.desktop";
        "x-scheme-handler/https" = "zen-twilight.desktop";
      }
      # Ahead of Zen: links to an app's host go to it, the rest to Zen.
      (lib.mkIf routed {
        "x-scheme-handler/http" = lib.mkBefore [ "nixbook-open-url.desktop" ];
        "x-scheme-handler/https" = lib.mkBefore [ "nixbook-open-url.desktop" ];
      })
    ];
    # Not an xdg.desktopEntries (that would put it in home.packages).
    xdg.dataFile."applications/nixbook-open-url.desktop" = lib.mkIf routed {
      text = lib.generators.toINI { } {
        "Desktop Entry" = {
          Type = "Application";
          Name = "Open link";
          Comment = "Opens a link in its app (zenBrowserConfig.openInApps) or the shell (YouTube), else in Zen";
          Exec = "${router}/bin/nixbook-open-url %u";
          MimeType = "x-scheme-handler/http;x-scheme-handler/https;";
          NoDisplay = true;
          Terminal = false;
        };
      };
    };
    home.sessionVariables = lib.mkIf routed {
      BROWSER = lib.mkForce "${router}/bin/nixbook-open-url";
    };
  };
}
