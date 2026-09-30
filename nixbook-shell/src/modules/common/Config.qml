pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false

    // One-time migrations of values an older default wrote into config.json
    // (the shell writes the whole default tree there on first run), once both
    // it and the persistent state are loaded.
    readonly property bool migrationsReady: root.ready && Persistent.ready
    onMigrationsReadyChanged: {
        if (!root.migrationsReady) return;
        const done = Persistent.states.migrations;
        // screenSnip.savePath used to default to "" (copy only): save to
        // ~/Pictures/Screenshots like niri. Once, so clearing it again sticks.
        if (!done.screenshotSavePath) {
            if (root.options.screenSnip.savePath === "" && !NixManaged.isPinned("screenSnip.savePath"))
                root.options.screenSnip.savePath = "~/Pictures/Screenshots";
            done.screenshotSavePath = true;
        }
        // apps.* used to default to KDE's kcmshell6 and a Hyprland script, none
        // of which is installed, so the Wi-Fi/Bluetooth/volume "Details"
        // buttons did nothing. Replace only those dead commands.
        if (!done.appCommands) {
            const apps = root.options.apps;
            const replace = (key, isDead, value) => {
                if (isDead(apps[key] ?? "") && !NixManaged.isPinned("apps." + key))
                    apps[key] = value;
            };
            const kcm = cmd => cmd.startsWith("kcmshell6 ");
            replace("bluetooth", kcm, "overskride");
            replace("network", kcm, "nm-connection-editor");
            replace("networkEthernet", kcm, "nm-connection-editor");
            replace("volumeMixer", cmd => cmd.includes("/.config/hypr/"), "pavucontrol-qt || pavucontrol");
            done.appCommands = true;
        }
        // The side panel button's icon used to default to Gemini's, whose
        // icon is gone: Claude's.
        if (!done.sidebarIconNoGemini) {
            if (root.options.custom.distroIcon === "google-gemini-symbolic" && !NixManaged.isPinned("custom.distroIcon"))
                root.options.custom.distroIcon = "spark-symbolic";
            done.sidebarIconNoGemini = true;
        }
    }
    property int readWriteDelay: 50 // milliseconds
    property bool blockWrites: false

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    // Save soon. Assigning a list property doesn't emit the adapter's
    // update (so nothing would be written): call this after one.
    function save() {
        fileWriteTimer.restart();
    }

    // Re-read config.json now (Home Manager activation rewrites it; see
    // NixManaged's `nixManaged reload` IPC).
    function reloadFile() {
        configFileView.reload();
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.writeAdapter()
        }
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: {
            fileWriteTimer.restart();
            NixManaged.scheduleEnforce(); // pinned (Nix) settings can't drift
        }
        onLoaded: {
            Themes.migrate();
            root.ready = true;
            NixManaged.scheduleEnforce();
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property string panelFamily: "ii" // "ii", "waffle"

            property JsonObject policies: JsonObject {
                property int ai: 1 // 0: No | 1: Yes | 2: Local
            }

            property JsonObject ai: JsonObject {
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal!\n- Always be brief and to the point, unless asked otherwise\n- Don't repeat the user's question\n- Be approachable: Avoid using overly complicated, domain-specific terms and provide analogies when asked to explain a concept\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n\nThanks!\n"
                property string tool: "functions" // search, functions, or none
                // Append this machine's context to the system prompt: what its
                // Nix configuration sets up (~/.config/nixbook-shell/
                // system-context.md, generated by the Home Manager module) and a
                // summary of the shell's live settings. Sent to the chosen
                // provider with every request.
                property bool includeSystemContext: true
                // Claude through Claude Code (`claude -p`, the user's own
                // Claude login): the "Claude" model, with the desktop tools
                // (nixbook-desktop-mcp) unless the tool is "none".
                property JsonObject claudeCode: JsonObject {
                    property string command: "" // empty: `claude` on PATH, ~/.local/bin, the Nix profiles
                    property string model: "" // empty: Claude Code's default; e.g. "sonnet" (faster), "opus"
                    // Tools it may use besides the desktop ones; others (Bash,
                    // Edit, Write…) are refused.
                    property list<string> allowedTools: ["WebSearch", "WebFetch", "Read", "Glob", "Grep"]
                    // The claude.ai connectors of the Claude account (Gmail,
                    // Calendar, Drive…), all their tools allowed.
                    property bool connectors: false
                }
            }

            property JsonObject appearance: JsonObject {
                // The theme (modules/common/themes.json, Themes.qml): "material"
                // (wallpaper colours) | "persona" | … Each theme with variants
                // has an object of its own below, named after its id, holding
                // at least `variant`.
                property string theme: "material"
                // A wallpaper per theme variant, put back when switching to it
                // (services/ThemeWallpapers.qml): "<theme>/<variant>=<path>"
                // (or "<theme>=<path>") entries. Strings: JsonAdapter saves a
                // changed list<string>, not a free-form object or list<var>.
                property bool wallpaperPerTheme: true
                property list<string> themeWallpapers: []
                // Same for the lock and login screens ("" / no entry: the lock
                // screen uses the desktop wallpaper, the login screen the lock
                // screen's).
                property list<string> themeLockWallpapers: []
                property list<string> themeLoginWallpapers: []
                // Persona art direction (Atlus): see modules/common/Persona.qml.
                property JsonObject persona: JsonObject {
                    // Legacy switch (before `theme`): true is migrated to
                    // theme "persona" on load (Themes.migrate). Not a Nix
                    // option (lib.nix legacyKeys).
                    property bool enable: false
                    property string variant: "p5" // p5 | p3r | p4 (Persona 4 Revival)
                    property bool palette: true   // replace the wallpaper palette
                    property bool motion: true    // snappy slam-in / overshoot animations
                    property bool shapes: true    // sharp corners, slanted frames, hard shadows
                    property bool halftone: true  // halftone texture on frames
                    property bool fonts: true     // condensed display font for titles
                }
                // Chiikawa theme: see modules/common/Chiikawa.qml.
                property JsonObject chiikawa: JsonObject {
                    property string variant: "chiikawa" // momonga | usagi | chiikawa
                    property bool palette: true   // the character's pastel palette
                    property bool motion: true    // bouncy animations
                    property bool shapes: true    // extra round corners
                    property bool fonts: true     // rounded font (Nunito)
                    property bool mascot: true    // the character on panels and the loading screen
                }
                // Cyberpunk 2077 theme: see modules/common/Cyberpunk.qml.
                property JsonObject cyberpunk: JsonObject {
                    property string variant: "yellow" // yellow | red
                    property bool palette: true   // the neon-on-black palette
                    property bool motion: true    // sharp, snappy animations
                    property bool shapes: true    // near-square corners
                    property bool fonts: true     // condensed tech font (Rajdhani)
                    property bool glitch: true    // RGB-split glitch and scanlines in the cut-in
                }
                property bool extraBackgroundTint: true
                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen
                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk"
                }
                property JsonObject transparency: JsonObject {
                    property bool enable: false
                    property bool automatic: true
                    property real backgroundTransparency: 0.11
                    property real contentTransparency: 0.57
                }
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property JsonObject terminalGenerationProps: JsonObject {
                        property real harmony: 0.6
                        property real harmonizeThreshold: 100
                        property real termFgBoost: 0.35
                        property bool forceDarkMode: false
                    }
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                    property string accentColor: ""
                }
            }

            property JsonObject audio: JsonObject {
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: false
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 99
                }
            }

            property JsonObject profile: JsonObject {
                property string avatarPath: ""
                property string avatarPicture: ""
                property string descriptionText: "::distro::"
                property string displayName: ""
                property bool onlinePresets: false

            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "overskride"
                property string changePassword: "kitty -1 --hold=yes fish -i -c 'passwd'"
                property string network: "nm-connection-editor"
                property string networkEthernet: "nm-connection-editor"
                property string taskManager: "plasma-systemmonitor --page-name Processes"
                property string terminal: "kitty -1" // This is only for shell actions
                property string update: "systemctl start --no-block nixos-upgrade-manual.service"
                property string volumeMixer: "pavucontrol-qt || pavucontrol"
            }

            property JsonObject settings: JsonObject {
                property string style: "default" // default - minimal
                property list<string> collapsedSections: []
                property bool hideLocked: false // settings menu: hide locked (externally managed) settings
            }

            property JsonObject background: JsonObject {
                // Lock screen wallpaper; "" = the desktop wallpaper.
                property string lockWall: ""
                // Login screen (greetd greeter, nixbook-shell.greeter NixOS
                // option) wallpaper; "" = the lock screen wallpaper.
                property string greeterWall: ""
                property bool widgetsLocked: false
                property bool showGrid: true
                property bool showBlur: false
                property real blurRadius: 32
                property string splitRatio: "100" // 25 50 100
                property string splitSide: "left"
                property bool showSnapLines: true
                property JsonObject widgets: JsonObject {
                    property bool blurWidgets: false
                    property real blurRadius: 32
                    property bool shadow: true
                    // Opacity of the desktop widgets' card backgrounds (1 = solid).
                    property real cardOpacity: 0.75
                    // Per-monitor overrides: "<widget>@<output>" -> { x, y, z,
                    // sizeMode, ringSize, height, fontSize, enable, ... }; see
                    // DesktopWidgets.qml. `screenPositions` is the older,
                    // position-only map, still read as a fallback.
                    property var perScreen: ({})
                    property var screenPositions: ({})
                    property JsonObject clock: JsonObject {
                        property bool enable: true
                        property bool showOnlyWhenLocked: false
                        property string placementStrategy: "leastBusy" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                        property real z: 0
                        property string style: "cookie"        // Options: "cookie", "digital"
                        property string color: ""
                        property string styleLocked: "cookie"  // Options: "cookie", "digital"
                        property JsonObject cookie: JsonObject {
                            property int sides: 14
                            property string dialNumberStyle: "full"   // Options: "dots" , "numbers", "full" , "none"
                            property string hourHandStyle: "fill"     // Options: "classic", "fill", "hollow", "hide"
                            property string minuteHandStyle: "medium" // Options "classic", "thin", "medium", "bold", "hide"
                            property string secondHandStyle: "dot"    // Options: "dot", "line", "classic", "hide"
                            property string dateStyle: "bubble"       // Options: "border", "rect", "bubble" , "hide"
                            property bool timeIndicators: true
                            property bool hourMarks: false
                            property bool constantlyRotate: false
                            property bool useSineCookie: false
                        }
                        property JsonObject digital: JsonObject {
                            property bool adaptiveAlignment: true
                            property bool showDate: true
                            property bool animateChange: true
                            property bool vertical: false
                            property JsonObject font: JsonObject {
                                property string family: "Google Sans Flex"
                                property real weight: 350
                                property real width: 100
                                property real size: 90
                                property real roundness: 0
                            }
                        }
                        property JsonObject pixel: JsonObject {
                            property string orientation: "vertical"
                        }
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                            property bool followClock: false
                        }
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string sizeMode: "1x3"
                        property bool expanded: false
                    }

                    property JsonObject calendar: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string sizeMode: "2x2"
                    }
                    // The next calendar events (DankCalendar).
                    property JsonObject nextEvent: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                    }
                    property JsonObject worldClock: JsonObject {
                        property bool enable: false
                        property list<string> timezones: ["Australia/Sydney", "Asia/Tokyo", "Europe/London", "America/New_York"]
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string sizeMode: "2x2"
                        property int clockCount: 4 
                    }

                    property JsonObject notes: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                    }

                    property JsonObject todo: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                    }

                    property JsonObject userCard: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string sizeMode: "1x2" 
                    }

                    property JsonObject images: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                    }

                    property JsonObject visualizer: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0
                        property real y: 0
                        property real z: -1000
                        property string style: "bars" // "bars", "mirror", "aurora", "ring", "dots"
                        property string colorSource: "theme" // "theme", "cover"
                        property real sensitivity: 1
                        property int height: 260 // mirror, aurora and dots
                        property int ringSize: 380
                        // Stop animating while windows cover the desktop on
                        // that screen (niri): it's then only seen blurred
                        // through them, and redrawing the wallpaper layer every
                        // frame also made niri re-blur every window (~50% GPU).
                        property bool pauseBehindWindows: true
                    }

                    property JsonObject customImage: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string path: ""
                        property string shape: "Cookie4Sided"
                        property real size: 200
                    }

                    property JsonObject sticker: JsonObject {
                        property bool enable: false
                        property list<var> items: [] // if someone sees this and wants to add more stickers, make a PR too lazy 
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string path: ""
                        property real size: 200
                        property real rotation: 0
                        property string outlineColor: "#ffffff" //dont work =(
                        property real outlineWidth: 8
                    }

                    property JsonObject resources: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property bool vertical: false
                    }

                    property JsonObject timers: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property bool vertical: false
                    }

                    property JsonObject media: JsonObject {
                        property bool enable: false
                        property bool showLyrics: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 800
                        property real y: 500
                        property real z: 0
                        property string sizeMode: "1x3" 
                    }

                    property JsonObject customText: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 300
                        property real z: 0
                        property string content: "Hello world"
                        property string fontFamily: "Caveat"
                        property int fontSize: 72
                        property string color: "" // "" = automatic, otherwise an Appearance color name
                        property string alignment: "center" // "left", "center", "right"
                        property bool shadow: true
                    }
                }
                property list<string> screenList: [] 
                property string wallpaperPath: ""
                property bool centeredWallpaper: false
                property string centeredWallpaperShape: "Cookie7Sided"
                property int centeredWallpaperSize: 400
                property string centeredWallpaperColor: "primaryContainer"
                property bool centeredWallpaperOnlyWhenLocked: false
                property string wallpaperAnimation: "magic"
                property bool enableWallpaperPreview: false
                property string thumbnailPath: ""
            }

            property JsonObject bar: JsonObject {
                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    property int hoverRegionWidth: 2
                    property bool pushWindows: false
                }
                property bool showFrame: false
                property real frameThickness: 4
                property string frameColor: "black"
                property bool followFrameColor: false
                property bool centerOnlyReserveFrame: false
                property bool bottom: false // Instead of top
                property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle
                property string groupColor: "layer1"
                property string borderless: "pills"
                property bool showBackground: true
                property bool verbose: true
                property bool vertical: false
                property JsonObject resources: JsonObject {
                    property string style: "filled"
                    property bool showValue: false
                    property bool alwaysShowSwap: false
                    property bool alwaysShowCpu: true
                    property bool alwaysShowCpuTemp: false
                    property bool alwaysShowDisk: false
                    property bool alwaysShowRam: true
                    property int memoryWarningThreshold: 95
                    property int swapWarningThreshold: 85
                    property int cpuWarningThreshold: 90
                }

                property JsonObject dynamicIsland: JsonObject {
                    property string visualizerStyle: "dots" // "dots", "wave", "none"
                    property bool showMediaControls: false
                    property string leftWidget: "none"
                    property string rightWidget: "none"
                }
                property JsonObject divider: JsonObject {
                    property string style: "rect" // rect - dot - space
                    property int spacing: 20
                }

                property JsonObject layouts: JsonObject {
                    property list<string> leftLayout: ["launcherButton", "workspaces", "activeWindow"]
                    property list<string> middleLayout: ["clockWidget"]
                    property list<string> rightLayout: ["sysTray", "utilButtons", "systemIcons", "powerButton"]
                }
                
                property list<string> screenList: [] // List of names, like "eDP-1", find out with `niri msg outputs`
                property JsonObject utilButtons: JsonObject {
                    property bool showScreenSnip: true
                    property bool showColorPicker: true
                    property bool showMicToggle: false
                    property bool showKeyboardToggle: false
                    property bool showWallpaperToggle: true
                    property bool showDarkModeToggle: false
                    property bool showPerformanceProfileToggle: false
                    property bool showScreenRecord: false       
                    property bool isRecording: false
                }

                property JsonObject workspaces: JsonObject {
                    property bool monochromeIcons: true
                    property int shown: 10
                    property bool showAppIcons: false
                    property string indicatorStyle: "dot" // "dot" or "icon"
                    property bool alwaysShowNumbers: true
                    property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
                    property bool useNerdFont: false
                }
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property bool enableGPS: true // gps based location
                    property string city: "" // When 'enableGPS' is false
                    property bool useUSCS: false // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: false
                    }
                }
                property JsonObject tooltips: JsonObject {
                    property bool enable: true
                    property bool clickToShow: false
                }
                property JsonObject media: JsonObject {
                    property string preferredPlayer: ""
                    property bool alwaysVisible: false
                    property bool onlyTitle: false
                    property int maxWidth: 280
                    property int minWidth: 100
                    property bool showLyrics: false
                }
            }

            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
            }

            property JsonObject calendar: JsonObject {
                property string locale: "en-GB"
                property int refreshMinutes: 30 // Re-read DankCalendar's events (the refresh button syncs now)
            }

            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }

            property JsonObject crosshair: JsonObject {
                // Valorant crosshair format. Use https://www.vcrdb.net/builder
                property string code: "0;P;d;1;0l;10;0o;2;1b;0"
            }

            property JsonObject dock: JsonObject {
                property bool enable: false
                property bool showBackground: true
                property bool showPinButton: true
                property bool showAppsButton: true
                property bool showMedia: true
                property bool monochromeIcons: true
                property real height: 60
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true // When false, only reveals on empty workspace
                property list<string> pinnedApps: [ // IDs of pinned entries
                    "org.kde.dolphin", "kitty",]
                property list<string> ignoredAppRegexes: []
            }

            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false // Enable faster scrolling with touchpad
                    property int mouseScrollDeltaThreshold: 120 // delta >= this then it gets detected as mouse scroll rather than touchpad
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
            }

            property JsonObject language: JsonObject {
                property string ui: "auto" // UI language. "auto" for system locale, or specific language code like "zh_CN", "en_US"
                property JsonObject translator: JsonObject {
                    property string engine: "auto" // Run `trans -list-engines` for available engines. auto should use google
                    property string targetLanguage: "auto" // Run `trans -list-all` for available languages
                    property string sourceLanguage: "auto"
                }
            }

            property JsonObject launcher: JsonObject {
                property list<string> pinnedApps: [ "org.kde.dolphin", "kitty", "cmake-gui"]
            }

            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
            }

            property JsonObject lock: JsonObject {
                property bool launchOnStartup: false
                property bool showWidgets: false
                property bool showMedia: true
                property bool showToolbars: true
                property JsonObject blur: JsonObject {
                    property bool enable: true
                    property real radius: 100
                    property real extraZoom: 1.1
                    property int size: 20
                }
                property bool centerClock: true
                property bool showLockedText: true
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property bool materialShapeChars: true
            }

            property JsonObject media: JsonObject {
                // Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)
                property bool filterDuplicatePlayers: true
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                property string position: "top_right"
                // Popups: one card per notification instead of one per app
                // (the notification centre stays grouped by app).
                property bool splitPopups: true
                // Persona style: which notifications get the full-screen cut-in
                // (modules/ii/notificationPopup/PersonaCutIn.qml).
                // Popups that stay on screen until dismissed instead of timing
                // out: messages from people. Matched on app name, title and
                // notification hints (not the message text), case-insensitive.
                property JsonObject persistent: JsonObject {
                    property bool enable: true
                    property list<string> apps: []
                    property list<string> keywords: []
                }
                // Quiet: notifications that don't pop up, cut in or chime, but
                // still go to the notification centre and the history — e.g.
                // the phone's or the browser's copy of a calendar reminder
                // DankCalendar already shows. Apps (exact name) and rules
                // (the cut-in syntax, NotificationUtils.ruleMatches).
                property JsonObject quiet: JsonObject {
                    property bool enable: true
                    property list<string> apps: []
                    property list<string> keywords: []
                }
                // Log of every notification (kept after it is dismissed),
                // services/NotificationHistory.qml. retentionDays 0 = forever.
                property JsonObject history: JsonObject {
                    property bool enable: true
                    property int retentionDays: 30
                }
                // Drop duplicate notifications (services/Notifications.qml
                // duplicateVerdict): the phone's mirrored copy of a message the
                // desktop app also showed, within `window` seconds (the desktop
                // one is kept; the phone can lag 15+ minutes), and a sender
                // repeating itself within `repeatWindow` seconds. relayApps:
                // app names of notifications mirrored from another device.
                // history: also drop the superseded copies (a thread re-post's
                // previous version, a mirrored copy) from the history.
                property JsonObject deduplicate: JsonObject {
                    property bool enable: true
                    property int window: 1800
                    property int repeatWindow: 2
                    property list<string> relayApps: ["KDE Connect", "GSConnect"]
                    property bool history: true
                }
                property JsonObject cutIn: JsonObject {
                    property bool enable: true
                    property bool critical: true // urgency "critical", set by the app
                    property list<string> apps: [] // app names (as shown on notifications)
                    // Rules matched in the app name, title, text and notification
                    // hints (browsers/KDE put the origin site there): "a + b"
                    // needs both, "!a" absent, "app:/title:/body:/last:/line:/hint:a"
                    // one field, "\"a\"" whole word (NotificationUtils.ruleMatches).
                    property list<string> keywords: []
                    // Rules (same syntax as `keywords`) that veto a cut-in,
                    // even for critical notifications or chosen apps.
                    property list<string> blacklist: []
                    // Played when a cut-in shows (even with the chime off);
                    // empty soundFile = the theme's critical sound (Themes.sound).
                    property bool sound: true
                    property string soundFile: ""
                    // A newer copy of a cut-in still queued or on screen (a chat
                    // thread re-posted with one more message) takes its place
                    // instead of a second cut-in.
                    property bool mergeUpdates: true
                }
            }

            property JsonObject osd: JsonObject {
                property int timeout: 1000
            }

            property JsonObject osk: JsonObject {
                property string layout: "qwerty_full"
                property bool pinnedOnStartup: false
            }

            property JsonObject overlay: JsonObject {
                property bool openingZoomAnimation: true
                property bool darkenScreen: true
                property real clickthroughOpacity: 0.8
                property JsonObject floatingImage: JsonObject {
                    property string imageSource: "https://media.tenor.com/H5U5bJzj3oAAAAAi/kukuru.gif"
                    property real scale: 0.5
                }
            }

            property JsonObject regionSelector: JsonObject {
                property JsonObject targetRegions: JsonObject {
                    property bool content: true
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                    property int selectionPadding: 5
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: true
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                property JsonObject annotation: JsonObject {
                    property bool useSatty: false
                }
            }

            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
                property int historyLength: 60
            }

            property JsonObject tray: JsonObject {
                property bool monochromeIcons: true
                property bool showItemId: false
                property bool invertPinnedItems: true // Makes the below a whitelist for the tray and blacklist for the pinned area
                property list<var> pinnedItems: [ "Fcitx" ]
                property bool filterPassive: true
            }

            property JsonObject musicRecognition: JsonObject {
                property int timeout: 16
                property int interval: 4
            }

            property JsonObject search: JsonObject {
                property int nonAppResultDelay: 30 // This prevents lagging when typing
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string clipboard: ";"
                    property string emojis: ":"
                    property string symbols: "."
                    property string themes: "@"
                    property string layouts: "#"
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
                    property bool useCircleSelection: false
                }
            }

            property JsonObject sidebar: JsonObject {
                property bool banner: true
                property bool bottomGroup: true
                property bool mediaPlayer: false
                property string bannerImage: ""
                property bool keepRightSidebarLoaded: true
                property JsonObject translator: JsonObject {
                    property bool enable: false
                    property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                }
                
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                }
                property JsonObject cornerOpen: JsonObject {
                    property bool enable: true
                    property bool bottom: false
                    property bool valueScroll: true
                    property bool clickless: false
                    property int cornerRegionWidth: 250
                    property int cornerRegionHeight: 5
                    property string bottomLeftAction: "sidebarLeftOpen"
                    property string bottomRightAction: "sidebarRightOpen"
                    property bool visualize: false
                    property bool clicklessCornerEnd: true
                    property int clicklessCornerVerticalOffset: 1
                }

                property JsonObject quickToggles: JsonObject {
                    property string style: "android" // Options: classic, android
                    property JsonObject android: JsonObject {
                        property int columns: 5
                        property list<var> toggles: [
                            { "size": 2, "type": "network" },
                            { "size": 2, "type": "bluetooth"  },
                            { "size": 1, "type": "idleInhibitor" },
                            { "size": 1, "type": "mic" },
                            { "size": 2, "type": "audio" },
                            { "size": 2, "type": "nightLight" }
                        ]
                    }
                }

                property JsonObject quickSliders: JsonObject {
                    property bool enable: true
                    property bool showMic: false
                    property bool showVolume: true
                    property bool showBrightness: true
                }
            }

            property JsonObject custom: JsonObject {
                property string distroIcon: "spark-symbolic"
                property bool colorizeIcon: true
            }

            property JsonObject screenRecord: JsonObject {
                property string savePath: Directories.videos.replace("file://","") // strip "file://"
            }

            property JsonObject screenSnip: JsonObject {
                // ~ and $HOME are expanded; empty: only copy to the clipboard.
                property string savePath: "~/Pictures/Screenshots"
            }

            property JsonObject sounds: JsonObject {
                property bool battery: false
                property bool pomodoro: false
                property string theme: "freedesktop"
                // Chime on every incoming notification (not in Do Not Disturb).
                // Empty notificationFile = the theme's chime (Themes.sound:
                // Persona 5's by default, the characters' own in Chiikawa).
                property bool notification: true
                property string notificationFile: ""
            }

            property JsonObject time: JsonObject {
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "hh:mm"
                property bool showDate: true
                property string shortDateFormat: "dd/MM"
                property string dateWithYearFormat: "dd/MM/yyyy"
                property string dateFormat: "ddd, dd/MM"
                property JsonObject pomodoro: JsonObject {
                    property int breakTime: 300
                    property int cyclesBeforeLongBreak: 4
                    property int focus: 1500
                    property int longBreak: 900
                }
                property bool secondPrecision: false
            }

            property JsonObject updates: JsonObject {
                property bool enableCheck: true
                property int checkInterval: 120 // minutes
                property string repoUrl: "" // NixOS configuration repository to compare /etc/nixos/version with; empty = no check
            }
            
            property JsonObject wallpaperSelector: JsonObject {
                property bool useSystemFileDialog: false
                property bool showBlurBackground: false
                property bool showHomePath: true
                property string userPath: "" // This can be set to any path and it will show up as a quick access in the wallpaper selector"
                property string liveWallpapersPath: ""
                property bool showSearchbar: true
                property int columns: 4
                property bool closeAfterSelection: true
                property int changeInterval: 0 
                property string sortMode: "time"
            }

            property JsonObject windowLayouts: JsonObject {
                property bool closeOthers: false // Restoring a layout closes the windows it doesn't have
            }

            property JsonObject windows: JsonObject {
                property bool showTitlebar: true // Client-side decoration for shell apps
                property bool centerTitle: true
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }

            property JsonObject workSafety: JsonObject {
                property JsonObject enable: JsonObject {
                    property bool wallpaper: false
                    property bool clipboard: false
                }
                property JsonObject triggerCondition: JsonObject {
                    property list<string> networkNameKeywords: ["airport", "cafe", "college", "company", "eduroam", "free", "guest", "public", "school", "university"]
                    property list<string> fileKeywords: ["anime", "booru", "ecchi", "hentai", "yande.re", "konachan", "breast", "nipples", "pussy", "nsfw", "spoiler", "girl"]
                    property list<string> linkKeywords: ["hentai", "porn", "sukebei", "hitomi.la", "rule34", "gelbooru", "fanbox", "dlsite"]
                }
            }
        }
    }
}
