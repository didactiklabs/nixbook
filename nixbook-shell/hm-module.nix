{
  config,
  options,
  pkgs,
  lib,
  osConfig ? null,
  ...
}:
# programs.nixbook-shell: runs nixbook-shell as a user service, publishes the
# settings set in Nix (applied on every activation and locked in the shell's
# Settings menu) and the machine context its AI chat and config assistant use.
let
  cfg = config.programs.nixbook-shell;
  # Imported directly, not taken from cfg.package: the `settings` option type
  # is generated from it, and option types can't depend on config.
  settingsLib = import ./lib.nix { inherit lib; };
  inherit (cfg.package.passthru) configName;

  jsonFormat = pkgs.formats.json { };

  # Everything set in Nix: applied on every activation with Nix winning, and
  # locked in the Settings menu. Keys Nix doesn't set are never touched: they
  # keep the shell's built-in default or the value chosen from the menu.
  pinnedSettings = settingsLib.pinnedSettings cfg.settings;
  pinnedPaths = settingsLib.flattenPaths [ ] pinnedSettings;
  pinnedFile = jsonFormat.generate "nixbook-shell-pinned.json" pinnedSettings;
  nixManagedFile = jsonFormat.generate "nix-managed.json" {
    paths = pinnedPaths;
  };

  # Where the running shell renders the apps' colours (services/AppTheming.qml,
  # which apps is up to Settings > Appearance): the Qt palette qt6ct/qt5ct read.
  appsDir = "${config.xdg.stateHome}/quickshell/user/generated/apps";

  # Neovim keymaps from an evaluated nixvim configuration
  # (`programs.nixvim`, when its Home Manager module is imported): read after
  # every override, so they are the keys Neovim really gets. Only these
  # fields are read (a keymap's removed `lua` option throws when touched).
  nixvim = config.programs.nixvim or null;
  nixvimEnabled = nixvim != null && (nixvim.enable or false);
  nixvimKeymap =
    scope: km:
    let
      action = km.action or null;
      lspBuf = km.lspBufAction or null;
    in
    {
      inherit (km) key;
      inherit scope;
      mode = km.mode or "n";
      action =
        if lspBuf != null then
          "vim.lsp.buf.${lspBuf}()"
        else if builtins.isAttrs action then
          action.__raw or (builtins.toJSON action)
        else
          action;
      lua = lspBuf != null || builtins.isAttrs action;
      desc = km.options.desc or null;
    };
  # "after/ftplugin/markdown.lua" -> "filetype:markdown"
  nixvimFileScope =
    name:
    let
      ft = builtins.match "(after/)?ftplugin/([^/]+)\\.(lua|vim)" name;
    in
    if ft != null then "filetype:${builtins.elemAt ft 1}" else "file:${name}";
  nixvimKeymaps = lib.optionals nixvimEnabled (
    map (nixvimKeymap null) (nixvim.keymaps or [ ])
    ++ lib.concatLists (
      lib.mapAttrsToList (event: map (nixvimKeymap "event:${event}")) (nixvim.keymapsOnEvents or { })
    )
    ++ map (nixvimKeymap "event:LspAttach") (nixvim.lsp.keymaps or [ ])
    ++ lib.concatLists (
      lib.mapAttrsToList (name: file: map (nixvimKeymap (nixvimFileScope name)) (file.keymaps or [ ])) (
        nixvim.files or { }
      )
    )
  );

  names = pkgList: lib.unique (lib.sort lib.lessThan (map lib.getName pkgList));

  # The operating system as configured, for questions about it ("which
  # kernel?", "is bluetooth on?", "what is my keyboard layout?"). Read from
  # the evaluated NixOS (osConfig) and Home Manager configurations; every
  # lookup has a fallback, so it evaluates on any NixOS release and under
  # standalone Home Manager (no osConfig: only the Home Manager part).
  os = osConfig;
  osGet = path: default: if os == null then default else lib.attrByPath path default os;
  hmGet = path: default: lib.attrByPath path default config;
  osUser = config.home.username;
  pkgName =
    p:
    if p == null then
      null
    else if lib.isDerivation p then
      lib.getName p
    else
      baseNameOf (toString p);
  experimental = osGet [ "nix" "settings" "experimental-features" ] [ ];
  firstLayout = l: if l == null || l == "" then null else lib.head (lib.splitString "," l);
  # Every option set with an `enable` option, on or off (toggles.nix): the
  # NixOS ones from nixbook-shell's NixOS module (nixos-module.nix) when it is
  # imported, the Home Manager ones from this configuration's options.
  osToggles = osGet [ "nixbook-shell" "toggles" ] [ ];
  hmToggles = (import ./toggles.nix { inherit lib; }) {
    inherit options config;
    scope = "home-manager";
  };
  osInfo = {
    nixos = os != null;
    host = osGet [ "networking" "hostName" ] null;
    user = osUser;
    release = osGet [ "system" "nixos" "release" ] null;
    codeName = osGet [ "system" "nixos" "codeName" ] null;
    platform = pkgs.stdenv.hostPlatform.system;
    kernel = if os == null then null else os.boot.kernelPackages.kernel.version;
    timeZone = osGet [ "time" "timeZone" ] null;
    autoTimeZone = osGet [ "services" "automatic-timezoned" "enable" ] false;
    locale = osGet [ "i18n" "defaultLocale" ] null;
    # The compositor's own layout first (niri), else the system's.
    keyboard =
      let
        niri = hmGet [ "programs" "niri" "settings" "input" "keyboard" "xkb" ] { };
        xkb = osGet [ "services" "xserver" "xkb" ] { };
        layout = firstLayout (niri.layout or null);
      in
      if layout != null then
        {
          inherit layout;
          variant = niri.variant or "";
        }
      else
        {
          layout = firstLayout (xkb.layout or null);
          variant = xkb.variant or "";
        };
    bootloader =
      if osGet [ "boot" "lanzaboote" "enable" ] false then
        "systemd-boot (Secure Boot, lanzaboote)"
      else if osGet [ "boot" "loader" "systemd-boot" "enable" ] false then
        "systemd-boot"
      else if osGet [ "boot" "loader" "grub" "enable" ] false then
        "GRUB"
      else
        null;
    shell = pkgName (osGet [ "users" "users" osUser "shell" ] null);
    editor =
      let
        e = hmGet [ "home" "sessionVariables" "EDITOR" ] (
          osGet [ "environment" "variables" "EDITOR" ] null
        );
      in
      if e == null then null else baseNameOf (toString e);
    nix =
      let
        p = osGet [ "nix" "package" ] null;
      in
      if p == null then null else "${lib.getName p} ${lib.getVersion p}";
    flakes = lib.elem "flakes" (
      if builtins.isList experimental then experimental else lib.splitString " " experimental
    );
    users = lib.attrNames (
      lib.filterAttrs (_: u: u.isNormalUser or false) (osGet [ "users" "users" ] { })
    );
    toggles = osToggles ++ hmToggles;
  };

  # How the calendars and to-do list sync, through DankCalendar (`dcal`,
  # always part of the shell): for the config assistant and the AI chat.
  calendarHowTo = {
    calendarConnect = {
      en = "To sync the shell's calendar with Google Calendar, click the person icon (Connect a Google account) in a calendar or to-do widget (sidebar, desktop, bar clock popup), or run `dcal account add google`: the browser opens Google's login, you sign in and accept, and that's all. DankCalendar (dcal) ships its own Google OAuth client, so no client ID, secret or Google Cloud project is needed; the token is kept in the keyring and renewed by dcal.";
      fr = "Pour synchroniser le calendrier du shell avec Google Agenda, cliquez sur l'icône de personne (Connecter un compte Google) dans un widget calendrier ou tâches (panneau latéral, bureau, horloge de la barre), ou lancez `dcal account add google` : le navigateur ouvre la connexion Google, vous vous connectez et acceptez, c'est tout. DankCalendar (dcal) fournit son propre client OAuth Google : aucun identifiant client, secret ni projet Google Cloud n'est nécessaire ; le jeton est gardé dans le trousseau et renouvelé par dcal.";
      de = "Um den Kalender der Shell mit Google Kalender zu synchronisieren, klicke auf das Personensymbol (Google-Konto verbinden) in einem Kalender- oder Aufgaben-Widget (Seitenleiste, Desktop, Uhr-Popup der Leiste) oder führe `dcal account add google` aus: Der Browser öffnet die Google-Anmeldung, du meldest dich an und stimmst zu, fertig. DankCalendar (dcal) bringt einen eigenen Google-OAuth-Client mit, es braucht also keine Client-ID, kein Secret und kein Google-Cloud-Projekt; das Token liegt im Schlüsselbund und wird von dcal erneuert.";
      vi = "Để đồng bộ lịch của shell với Google Lịch, bấm biểu tượng người (Kết nối tài khoản Google) trong widget lịch hoặc công việc (thanh bên, màn hình nền, popup đồng hồ trên thanh), hoặc chạy `dcal account add google`: trình duyệt mở trang đăng nhập Google, bạn đăng nhập và chấp nhận, vậy là xong. DankCalendar (dcal) có sẵn client OAuth Google riêng nên không cần client ID, secret hay dự án Google Cloud; token được giữ trong keyring và dcal tự gia hạn.";
    };
    calendarOtherAccounts = {
      en = "To add another calendar account (Microsoft/Outlook, CalDAV such as Nextcloud, iCloud, an iCal feed URL, a local calendar) or remove one, open DankCalendar (the calendar icon in a calendar or to-do widget, or `dcal show`) and use its settings; `dcal account list` lists the accounts.";
      fr = "Pour ajouter un autre compte de calendrier (Microsoft/Outlook, CalDAV comme Nextcloud, iCloud, une URL de flux iCal, un calendrier local) ou en retirer un, ouvrez DankCalendar (l'icône calendrier d'un widget calendrier ou tâches, ou `dcal show`) et passez par ses paramètres ; `dcal account list` liste les comptes.";
      de = "Um ein weiteres Kalenderkonto (Microsoft/Outlook, CalDAV wie Nextcloud, iCloud, eine iCal-Feed-URL, einen lokalen Kalender) hinzuzufügen oder eines zu entfernen, öffne DankCalendar (das Kalendersymbol in einem Kalender- oder Aufgaben-Widget, oder `dcal show`) und nutze seine Einstellungen; `dcal account list` listet die Konten auf.";
      vi = "Để thêm tài khoản lịch khác (Microsoft/Outlook, CalDAV như Nextcloud, iCloud, URL nguồn iCal, lịch cục bộ) hoặc gỡ một tài khoản, mở DankCalendar (biểu tượng lịch trong widget lịch hoặc công việc, hoặc `dcal show`) và dùng phần cài đặt của nó; `dcal account list` liệt kê các tài khoản.";
    };
    calendarEvents = {
      en = "Calendar events show as dots in the sidebar, desktop and bar clock calendars; the Next Event bar widget and desktop widget (desktop right click > Widgets) show the next ones, with a Join button for meetings; click a day in the sidebar calendar to see its events and add one (+); clicking the bar clock, the Next Event widget or a day in the desktop calendar opens DankCalendar. Events are created and edited in DankCalendar's window, which syncs them to Google; the shell rereads them every 30 minutes (setting `calendar.refreshMinutes`), and the refresh button in the sidebar calendar's header (or the sync button, right click on the calendar icon) syncs now.";
      fr = "Les événements du calendrier apparaissent en points dans les calendriers du panneau latéral, du bureau et de l'horloge de la barre ; le widget de barre et le widget de bureau Prochain événement (clic droit sur le bureau > Widgets) montrent les prochains, avec un bouton Rejoindre pour les réunions ; cliquez sur un jour du calendrier du panneau latéral pour voir ses événements et en ajouter un (+) ; un clic sur l'horloge de la barre, le widget Prochain événement ou un jour du calendrier du bureau ouvre DankCalendar. Les événements se créent et se modifient dans la fenêtre de DankCalendar, qui les synchronise avec Google ; le shell les relit toutes les 30 minutes (réglage `calendar.refreshMinutes`), et le bouton d'actualisation dans l'en-tête du calendrier du panneau latéral (ou le bouton de synchronisation, clic droit sur l'icône calendrier) synchronise tout de suite.";
      de = "Kalendertermine erscheinen als Punkte in den Kalendern der Seitenleiste, des Desktops und der Leistenuhr; das Leisten- und das Desktop-Widget Nächster Termin (Rechtsklick auf den Desktop > Widgets) zeigen die nächsten, mit einem Beitreten-Knopf für Besprechungen; klicke auf einen Tag im Seitenleisten-Kalender, um seine Termine zu sehen und einen hinzuzufügen (+); ein Klick auf die Leistenuhr, das Widget Nächster Termin oder einen Tag im Desktop-Kalender öffnet DankCalendar. Termine werden im Fenster von DankCalendar erstellt und bearbeitet, das sie mit Google synchronisiert; die Shell liest sie alle 30 Minuten neu (Einstellung `calendar.refreshMinutes`), und der Aktualisieren-Knopf im Kopf des Seitenleisten-Kalenders (oder die Synchronisieren-Aktion, Rechtsklick auf das Kalendersymbol) synchronisiert sofort.";
      vi = "Sự kiện lịch hiện thành chấm trong lịch ở thanh bên, màn hình nền và đồng hồ trên thanh; widget Sự kiện tiếp theo trên thanh và trên màn hình nền (chuột phải màn hình nền > Widgets) hiện các sự kiện sắp tới, có nút Tham gia cho cuộc họp; bấm vào một ngày trong lịch thanh bên để xem sự kiện và thêm mới (+); bấm vào đồng hồ trên thanh, widget Sự kiện tiếp theo hoặc một ngày trong lịch màn hình nền sẽ mở DankCalendar. Sự kiện được tạo và sửa trong cửa sổ DankCalendar, nơi đồng bộ chúng lên Google; shell đọc lại mỗi 30 phút (cài đặt `calendar.refreshMinutes`), và nút làm mới ở đầu lịch thanh bên (hoặc nút đồng bộ, chuột phải vào biểu tượng lịch) đồng bộ ngay.";
    };
    calendarReminders = {
      en = "Calendar reminders (event notifications) come from DankCalendar: a notification before each event at the event's own Google reminder times, or 10 minutes before by default, with Join (meeting link), Open, Snooze and Dismiss buttons; it stays until handled and respects Do Not Disturb. The default time, sound, snooze length and all-day reminders are set in DankCalendar's settings (open it from a calendar widget); `dcal reminders test` sends a test one.";
      fr = "Les rappels du calendrier (notifications d'événements) viennent de DankCalendar : une notification avant chaque événement aux horaires de rappel Google de l'événement, ou 10 minutes avant par défaut, avec les boutons Rejoindre (lien de réunion), Ouvrir, Reporter et Ignorer ; elle reste jusqu'à ce qu'on la traite et respecte le mode Ne pas déranger. Le délai par défaut, le son, la durée de report et les rappels des journées entières se règlent dans les paramètres de DankCalendar (ouvrez-le depuis un widget calendrier) ; `dcal reminders test` en envoie un de test.";
      de = "Kalendererinnerungen (Terminbenachrichtigungen) kommen von DankCalendar: eine Benachrichtigung vor jedem Termin zu dessen Google-Erinnerungszeiten, sonst standardmäßig 10 Minuten vorher, mit den Knöpfen Beitreten (Besprechungslink), Öffnen, Schlummern und Verwerfen; sie bleibt, bis sie erledigt ist, und respektiert Nicht stören. Standardzeit, Ton, Schlummerdauer und ganztägige Erinnerungen stellst du in den Einstellungen von DankCalendar ein (über ein Kalender-Widget öffnen); `dcal reminders test` schickt eine Testerinnerung.";
      vi = "Nhắc nhở lịch (thông báo sự kiện) đến từ DankCalendar: một thông báo trước mỗi sự kiện theo thời gian nhắc của sự kiện trên Google, hoặc mặc định 10 phút trước, có các nút Tham gia (liên kết họp), Mở, Báo lại và Bỏ qua; thông báo ở lại đến khi được xử lý và tôn trọng chế độ Không làm phiền. Thời gian mặc định, âm thanh, thời lượng báo lại và nhắc cả ngày được đặt trong cài đặt của DankCalendar (mở từ widget lịch); `dcal reminders test` gửi một thông báo thử.";
    };
    calendarTasks = {
      en = "The to-do list (sidebar, desktop widget, bar clock popup, the launcher's add task) is synced with Google Tasks once a Google account is connected: adding, ticking and deleting a task changes it in the account, new tasks go to the first task list, and finished tasks stay listed for 14 days. Without an account it is a local list.";
      fr = "La liste de tâches (panneau latéral, widget du bureau, popup de l'horloge, l'ajout de tâche du lanceur) est synchronisée avec Google Tasks dès qu'un compte Google est connecté : ajouter, cocher ou supprimer une tâche la modifie dans le compte, les nouvelles tâches vont dans la première liste, et les tâches terminées restent affichées 14 jours. Sans compte, c'est une liste locale.";
      de = "Die Aufgabenliste (Seitenleiste, Desktop-Widget, Uhr-Popup der Leiste, Aufgabe hinzufügen im Starter) wird mit Google Tasks synchronisiert, sobald ein Google-Konto verbunden ist: Hinzufügen, Abhaken und Löschen ändert die Aufgabe im Konto, neue Aufgaben landen in der ersten Aufgabenliste, und erledigte bleiben 14 Tage sichtbar. Ohne Konto ist es eine lokale Liste.";
      vi = "Danh sách công việc (thanh bên, widget màn hình nền, popup đồng hồ trên thanh, thêm công việc từ trình khởi chạy) được đồng bộ với Google Tasks khi đã kết nối tài khoản Google: thêm, đánh dấu xong và xóa công việc sẽ thay đổi trong tài khoản, công việc mới vào danh sách đầu tiên, và công việc đã xong vẫn hiện trong 14 ngày. Khi chưa có tài khoản, đó là danh sách cục bộ.";
    };
    calendarTroubleshoot = {
      en = "If the calendar shows no events or the to-do list isn't synced, check the DankCalendar daemon with `systemctl --user status dcal` and its logs with `journalctl --user -u dcal`; `dcal account list` shows the accounts, `dcal sync` syncs now, and `dcal account reauth <account-id>` signs in again when Google asks.";
      fr = "Si le calendrier n'affiche aucun événement ou si la liste de tâches n'est pas synchronisée, vérifiez le démon DankCalendar avec `systemctl --user status dcal` et ses journaux avec `journalctl --user -u dcal` ; `dcal account list` montre les comptes, `dcal sync` synchronise tout de suite, et `dcal account reauth <id-du-compte>` reconnecte quand Google le demande.";
      de = "Wenn der Kalender keine Termine zeigt oder die Aufgabenliste nicht synchronisiert wird, prüfe den DankCalendar-Dienst mit `systemctl --user status dcal` und seine Logs mit `journalctl --user -u dcal`; `dcal account list` zeigt die Konten, `dcal sync` synchronisiert sofort, und `dcal account reauth <konto-id>` meldet neu an, wenn Google danach fragt.";
      vi = "Nếu lịch không hiện sự kiện hoặc danh sách công việc không đồng bộ, kiểm tra dịch vụ DankCalendar bằng `systemctl --user status dcal` và nhật ký bằng `journalctl --user -u dcal`; `dcal account list` hiện các tài khoản, `dcal sync` đồng bộ ngay, và `dcal account reauth <id-tài-khoản>` đăng nhập lại khi Google yêu cầu.";
    };
  };

  # The shell's own features (themes, notifications, the chat panel): for
  # the config assistant and the AI chat. Keep these up to date with every
  # feature added or changed (AGENTS.md).
  shellHowTo = {
    themeSwitch = {
      en = "To change the shell's theme, open Settings > Appearance > Theme (or right click the desktop > Theme) and pick Material (colours from the wallpaper), Persona (Persona 5 Royal, 3 Reload or 4 Revival) Chiikawa (Chiikawa, Usagi or Momonga) or Cyberpunk 2077 (Yellow or Red), then its variant. Each theme keeps its own variant and options (palette, animations, shapes, fonts); in Nix it is programs.nixbook-shell.settings.appearance.theme and appearance.<theme>.variant.";
      fr = "Pour changer le thème du shell, ouvrez Paramètres > Apparence > Thème (ou clic droit sur le bureau > Thème) et choisissez Material (couleurs du fond d'écran), Persona (Persona 5 Royal, 3 Reload ou 4 Revival) Chiikawa (Chiikawa, Usagi ou Momonga) ou Cyberpunk 2077 (Yellow ou Red), puis sa variante. Chaque thème garde sa variante et ses options (palette, animations, formes, polices) ; dans Nix, c'est programs.nixbook-shell.settings.appearance.theme et appearance.<thème>.variant.";
      de = "Um das Design der Shell zu ändern, öffne Einstellungen > Darstellung > Design (oder Rechtsklick auf den Desktop > Design) und wähle Material (Farben aus dem Hintergrundbild), Persona (Persona 5 Royal, 3 Reload oder 4 Revival) Chiikawa (Chiikawa, Usagi oder Momonga) oder Cyberpunk 2077 (Yellow oder Red), dann seine Variante. Jedes Design behält seine Variante und Optionen (Palette, Animationen, Formen, Schriften); in Nix ist es programs.nixbook-shell.settings.appearance.theme und appearance.<design>.variant.";
      vi = "Để đổi giao diện (theme) của shell, mở Cài đặt > Giao diện > Theme (hoặc chuột phải màn hình nền > Theme) và chọn Material (màu theo hình nền), Persona (Persona 5 Royal, 3 Reload hoặc 4 Revival) Chiikawa (Chiikawa, Usagi hoặc Momonga) hoặc Cyberpunk 2077 (Yellow hoặc Red), rồi chọn biến thể. Mỗi theme giữ biến thể và tùy chọn riêng (bảng màu, hiệu ứng, hình dạng, phông chữ); trong Nix là programs.nixbook-shell.settings.appearance.theme và appearance.<theme>.variant.";
    };
    themeWallpaper = {
      en = "Each theme variant keeps its own desktop, lock screen and login screen wallpapers: switching theme or variant puts them back (the Chiikawa and Cyberpunk variants start with their own desktop wallpaper), and a wallpaper picked while in a variant becomes that variant's. Settings > Appearance > Theme has a table of every variant: click a cell to choose its desktop, lock or login wallpaper, the × to unset it (the lock screen then uses the desktop wallpaper, the login screen the lock screen's). A switch there turns it off (appearance.wallpaperPerTheme).";
      fr = "Chaque variante de thème garde ses fonds d'écran du bureau, de l'écran de verrouillage et de l'écran de connexion : changer de thème ou de variante les remet (les variantes Chiikawa et Cyberpunk commencent avec leur propre fond de bureau), et un fond choisi dans une variante devient le sien. Paramètres > Apparence > Thème contient un tableau de toutes les variantes : cliquez sur une case pour choisir son fond de bureau, de verrouillage ou de connexion, sur le × pour le retirer (le verrouillage reprend alors le fond du bureau, la connexion celui du verrouillage). Un interrupteur le désactive (appearance.wallpaperPerTheme).";
      de = "Jede Designvariante behält ihre eigenen Hintergrundbilder für Desktop, Sperrbildschirm und Anmeldebildschirm: Beim Wechsel von Design oder Variante kommen sie zurück (die Chiikawa- und Cyberpunk-Varianten starten mit ihrem eigenen Desktop-Bild), und ein in einer Variante gewähltes Bild wird zu ihrem. Einstellungen > Darstellung > Design enthält eine Tabelle aller Varianten: Klick auf eine Zelle wählt ihr Desktop-, Sperr- oder Anmeldebild, das × entfernt es (der Sperrbildschirm nutzt dann das Desktop-Bild, die Anmeldung das des Sperrbildschirms). Ein Schalter schaltet es ab (appearance.wallpaperPerTheme).";
      vi = "Mỗi biến thể theme giữ hình nền riêng cho màn hình nền, màn hình khóa và màn hình đăng nhập: đổi theme hoặc biến thể sẽ đặt lại chúng (các biến thể Chiikawa và Cyberpunk bắt đầu với hình nền riêng), và hình chọn khi đang ở một biến thể sẽ thành của biến thể đó. Cài đặt > Giao diện > Theme có bảng mọi biến thể: bấm vào ô để chọn hình nền màn hình nền, khóa hoặc đăng nhập, bấm × để bỏ (màn hình khóa khi đó dùng hình nền màn hình nền, màn hình đăng nhập dùng hình của màn hình khóa). Một công tắc để tắt (appearance.wallpaperPerTheme).";
    };
    themeSounds = {
      en = "Each theme has its own notification sounds: Persona 5's chime and cut-in effect in Material and Persona, the characters' own chime and jingle in Chiikawa, a digital blip and a glitch alarm in Cyberpunk 2077. A sound file set in Settings > General > Sounds (notification) or in the cut-in settings replaces the theme's.";
      fr = "Chaque thème a ses propres sons de notification : le carillon et l'effet de cut-in de Persona 5 en Material et Persona, le carillon et le jingle des personnages en Chiikawa, un bip numérique et une alarme glitchée en Cyberpunk 2077. Un fichier son choisi dans Paramètres > Général > Sons (notification) ou dans les réglages du cut-in remplace celui du thème.";
      de = "Jedes Design hat eigene Benachrichtigungstöne: Persona 5s Glockenton und Cut-in-Effekt in Material und Persona, der eigene Ton und Jingle der Figuren in Chiikawa, ein digitaler Piep und ein Glitch-Alarm in Cyberpunk 2077. Eine in Einstellungen > Allgemein > Töne (Benachrichtigung) oder in den Cut-in-Einstellungen gesetzte Tondatei ersetzt den des Designs.";
      vi = "Mỗi theme có âm thanh thông báo riêng: tiếng chuông và hiệu ứng cut-in của Persona 5 ở Material và Persona, tiếng chuông và đoạn nhạc của các nhân vật ở Chiikawa, tiếng bíp kỹ thuật số và chuông báo glitch ở Cyberpunk 2077. Tệp âm thanh đặt trong Cài đặt > Chung > Âm thanh (thông báo) hoặc trong cài đặt cut-in sẽ thay âm thanh của theme.";
    };
    themeCutIns = {
      en = "Important notifications (critical ones and those matching the cut-in rules in Settings > Bar > Notifications > Cut-ins) take over the screen: a Persona cut-in in the Persona theme, the character popping up with a speech bubble in the Chiikawa theme, an incoming holocall glitching in in the Cyberpunk 2077 theme. Click runs the notification's action, right click or Escape dismisses it; the Preview button shows one.";
      fr = "Les notifications importantes (critiques, ou correspondant aux règles de cut-in dans Paramètres > Barre > Notifications > Cut-ins) prennent l'écran : un cut-in Persona dans le thème Persona, le personnage qui surgit avec une bulle dans le thème Chiikawa, un holoappel entrant qui apparaît en glitch dans le thème Cyberpunk 2077. Un clic lance l'action de la notification, un clic droit ou Échap la ferme ; le bouton Aperçu en montre un.";
      de = "Wichtige Benachrichtigungen (kritische und solche, die zu den Cut-in-Regeln unter Einstellungen > Leiste > Benachrichtigungen > Cut-ins passen) übernehmen den Bildschirm: ein Persona-Cut-in im Persona-Design, die Figur mit einer Sprechblase im Chiikawa-Design, ein eingehender Holoanruf mit Glitch im Cyberpunk-2077-Design. Klick führt die Aktion aus, Rechtsklick oder Escape schließt; der Vorschau-Knopf zeigt eines.";
      vi = "Thông báo quan trọng (khẩn cấp, hoặc khớp quy tắc cut-in trong Cài đặt > Thanh > Thông báo > Cut-ins) chiếm màn hình: cut-in Persona ở theme Persona, nhân vật hiện lên với bong bóng thoại ở theme Chiikawa, cuộc gọi holo đến kèm hiệu ứng glitch ở theme Cyberpunk 2077. Bấm để chạy hành động của thông báo, chuột phải hoặc Escape để đóng; nút Xem trước hiển thị một ví dụ.";
    };
    loginScreen = {
      en = "The login screen is nixbook-shell's own (on a machine with customNixOSModules.greetd enabled, it is the default as soon as a user runs nixbook-shell; customNixOSModules.greetd.greeter = \"tuigreet\" keeps the text login): it has your theme, palette, fonts, account picture, cursor and login screen wallpaper. Click an account picture under the card (or press Up / Down) to switch account, click or scroll the session pill to switch session, type the password and press Enter (a security key or fingerprint works too; the eye button shows what you typed, Esc clears it); the buttons in the corner suspend, reboot or power off. It remembers the last account and session. If it can't start, tuigreet (a text login) takes over.";
      fr = "L'écran de connexion est celui de nixbook-shell (sur une machine avec customNixOSModules.greetd, c'est le choix par défaut dès qu'un utilisateur utilise nixbook-shell ; customNixOSModules.greetd.greeter = \"tuigreet\" garde la connexion texte) : il reprend votre thème, palette, polices, photo de compte, curseur et fond d'écran de connexion. Cliquez une photo de compte sous la carte (ou Haut / Bas) pour changer de compte, cliquez ou faites défiler la pastille de session pour changer de session ; tapez le mot de passe puis Entrée (une clé de sécurité ou l'empreinte fonctionnent aussi ; le bouton œil affiche la saisie, Échap l'efface) ; les boutons dans le coin mettent en veille, redémarrent ou éteignent. Il retient le dernier compte et la dernière session. S'il ne peut pas démarrer, tuigreet (connexion en mode texte) prend le relais.";
      de = "Der Anmeldebildschirm ist der von nixbook-shell (auf einer Maschine mit customNixOSModules.greetd ist er Standard, sobald ein Benutzer nixbook-shell nutzt; customNixOSModules.greetd.greeter = \"tuigreet\" behält die Textanmeldung): mit deinem Design, deiner Palette, Schriften, Kontobild, Mauszeiger und Anmelde-Hintergrundbild. Klicke ein Kontobild unter der Karte (oder Hoch / Runter), um das Konto zu wechseln, klicke oder scrolle auf der Sitzungs-Pille, um die Sitzung zu wechseln, gib das Passwort ein und drücke Enter (Sicherheitsschlüssel oder Fingerabdruck gehen auch; der Augen-Knopf zeigt die Eingabe, Esc löscht sie); die Knöpfe in der Ecke versetzen in Bereitschaft, starten neu oder schalten aus. Er merkt sich das letzte Konto und die letzte Sitzung. Startet er nicht, übernimmt tuigreet (Textanmeldung).";
      vi = "Màn hình đăng nhập là của nixbook-shell (trên máy bật customNixOSModules.greetd, nó là mặc định ngay khi có người dùng chạy nixbook-shell; customNixOSModules.greetd.greeter = \"tuigreet\" giữ đăng nhập dạng chữ): có theme, bảng màu, phông chữ, ảnh tài khoản, con trỏ và hình nền đăng nhập của bạn. Bấm ảnh tài khoản dưới thẻ (hoặc phím Lên / Xuống) để đổi tài khoản, bấm hoặc cuộn nút phiên để đổi phiên, nhập mật khẩu rồi Enter (khóa bảo mật hoặc vân tay cũng được; nút con mắt hiện mật khẩu đã gõ, Esc xóa nó); các nút ở góc để ngủ, khởi động lại hoặc tắt máy. Nó nhớ tài khoản và phiên gần nhất. Nếu không khởi động được, tuigreet (đăng nhập dạng chữ) sẽ thay thế.";
    };
    chatPanel = {
      en = "The AI chat panel (left sidebar) has buttons for its shortcuts under its tabs: Extend (Ctrl+O) makes it wider, Pin (Ctrl+P) keeps it open beside your windows, Detach (Ctrl+D) opens the chat in a window of its own (Ctrl+D again, or Attach, puts it back). Ctrl+PageUp/PageDown switch between the chat and the translator.";
      fr = "Le panneau du chat IA (panneau latéral gauche) a sous ses onglets des boutons pour ses raccourcis : Étendre (Ctrl+O) l'élargit, Épingler (Ctrl+P) le garde ouvert à côté des fenêtres, Détacher (Ctrl+D) ouvre le chat dans sa propre fenêtre (Ctrl+D à nouveau, ou Rattacher, le remet). Ctrl+PageHaut/PageBas passent du chat au traducteur.";
      de = "Das KI-Chat-Panel (linke Seitenleiste) hat unter seinen Tabs Knöpfe für seine Tastenkürzel: Erweitern (Strg+O) macht es breiter, Anheften (Strg+P) hält es neben den Fenstern offen, Lösen (Strg+D) öffnet den Chat in einem eigenen Fenster (nochmals Strg+D oder Andocken holt ihn zurück). Strg+Bild auf/ab wechseln zwischen Chat und Übersetzer.";
      vi = "Bảng chat AI (thanh bên trái) có các nút phím tắt dưới các tab: Mở rộng (Ctrl+O) làm bảng rộng hơn, Ghim (Ctrl+P) giữ bảng mở cạnh cửa sổ, Tách (Ctrl+D) mở chat trong cửa sổ riêng (nhấn lại Ctrl+D hoặc Gắn lại để đưa về). Ctrl+PageUp/PageDown chuyển giữa chat và trình dịch.";
    };
    screenshot = {
      en = "To take a screenshot, open the screenshot selector (the Print key, or nixbook-shell ipc call region screenshot): drag a rectangle, then left click copies it to the clipboard and right click opens it for annotation. To take a whole window or a whole screen without drawing, pick Window or Screen in the toolbar at the bottom (or press W or S in the selector; press it again to go back to the rectangle): hovering a window or a screen selects it, and a click takes it. A window is captured whole, even where it is covered or off screen. Esc cancels. Screenshots are also saved to ~/Pictures/Screenshots (created if missing); change the folder, or empty it to only copy, in Settings > Services > Screenshot Path.";
      fr = "Pour faire une capture d'écran, ouvrez le sélecteur de capture (la touche Impr. écran, ou nixbook-shell ipc call region screenshot) : tracez un rectangle, puis clic gauche le copie dans le presse-papiers et clic droit l'ouvre pour l'annoter. Pour capturer une fenêtre entière ou un écran entier sans tracer, choisissez Fenêtre ou Écran dans la barre d'outils en bas (ou appuyez sur W ou S dans le sélecteur ; à nouveau pour revenir au rectangle) : survoler une fenêtre ou un écran le sélectionne, un clic le capture. Une fenêtre est capturée en entier, même cachée ou hors de l'écran. Échap annule. Les captures sont aussi enregistrées dans ~/Pictures/Screenshots (créé s'il manque) ; changez le dossier, ou videz-le pour seulement copier, dans Paramètres > Services > Screenshot Path.";
      de = "Für einen Screenshot öffne die Bildschirmauswahl (die Druck-Taste, oder nixbook-shell ipc call region screenshot): Ziehe ein Rechteck, dann kopiert ein Linksklick es in die Zwischenablage und ein Rechtsklick öffnet es zum Beschriften. Um ein ganzes Fenster oder einen ganzen Bildschirm ohne Zeichnen aufzunehmen, wähle Fenster oder Bildschirm in der Werkzeugleiste unten (oder drücke W oder S in der Auswahl; nochmals für das Rechteck): Mit der Maus über einem Fenster oder Bildschirm wird es ausgewählt, ein Klick nimmt es auf. Ein Fenster wird vollständig aufgenommen, auch wenn es verdeckt oder außerhalb des Bildschirms ist. Esc bricht ab. Screenshots werden auch in ~/Pictures/Screenshots gespeichert (wird bei Bedarf angelegt); den Ordner ändern, oder leeren, um nur zu kopieren, unter Einstellungen > Dienste > Screenshot Path.";
      vi = "Để chụp màn hình, mở bộ chọn chụp màn hình (phím Print, hoặc nixbook-shell ipc call region screenshot): kéo một hình chữ nhật, rồi chuột trái sao chép vào bộ nhớ tạm và chuột phải mở để chú thích. Để chụp cả một cửa sổ hoặc cả một màn hình mà không cần kéo, chọn Cửa sổ hoặc Màn hình trên thanh công cụ phía dưới (hoặc nhấn W hoặc S trong bộ chọn; nhấn lại để quay về hình chữ nhật): di chuột lên cửa sổ hoặc màn hình sẽ chọn nó, bấm chuột để chụp. Cửa sổ được chụp trọn vẹn, kể cả phần bị che hoặc nằm ngoài màn hình. Esc để hủy. Ảnh chụp cũng được lưu vào ~/Pictures/Screenshots (tự tạo nếu chưa có); đổi thư mục, hoặc để trống để chỉ sao chép, trong Cài đặt > Dịch vụ > Screenshot Path.";
    };
    screenRecord = {
      en = "To record the screen, press Shift+Print or click the record button in the bar (or the Record region button of the overlay, or nixbook-shell ipc call region recordWithSound): the same selector as for screenshots opens. Drag a rectangle, or pick Window or Screen in the toolbar at the bottom (or press W or S): hovering a window or a screen selects it, a click starts recording it. A window is recorded where it is shown on screen when you click (move it and the recording keeps that area); a screen is recorded whole. The desktop audio (what plays on the default output) is recorded too. Press Shift+Print or click the record button again (or the stop button) to stop: the video is then copied to the clipboard as a file (paste it into a file manager or a chat). Recordings are saved to ~/Videos; change the folder in Settings > Services > Video Recording Path.";
      fr = "Pour enregistrer l'écran, appuyez sur Maj+Impr. écran ou cliquez sur le bouton d'enregistrement de la barre (ou le bouton Enregistrer une zone de l'overlay, ou nixbook-shell ipc call region recordWithSound) : le même sélecteur que pour les captures s'ouvre. Tracez un rectangle, ou choisissez Fenêtre ou Écran dans la barre d'outils en bas (ou appuyez sur W ou S) : survoler une fenêtre ou un écran le sélectionne, un clic lance son enregistrement. Une fenêtre est enregistrée là où elle est affichée au moment du clic (si elle bouge, l'enregistrement garde cette zone) ; un écran est enregistré en entier. Le son du bureau (ce qui joue sur la sortie par défaut) est aussi enregistré. Appuyez à nouveau sur Maj+Impr. écran ou cliquez sur le bouton d'enregistrement (ou le bouton stop) pour arrêter : la vidéo est alors copiée dans le presse-papiers comme fichier (à coller dans un gestionnaire de fichiers ou un chat). Les enregistrements sont dans ~/Videos ; changez le dossier dans Paramètres > Services > Video Recording Path.";
      de = "Um den Bildschirm aufzunehmen, drücke Umschalt+Druck oder klicke auf den Aufnahmeknopf in der Leiste (oder den Knopf Bereich aufnehmen im Overlay, oder nixbook-shell ipc call region recordWithSound): Es öffnet sich dieselbe Auswahl wie für Screenshots. Ziehe ein Rechteck, oder wähle Fenster oder Bildschirm in der Werkzeugleiste unten (oder drücke W oder S): Mit der Maus über einem Fenster oder Bildschirm wird es ausgewählt, ein Klick startet die Aufnahme. Ein Fenster wird dort aufgenommen, wo es beim Klick angezeigt wird (wird es verschoben, bleibt die Aufnahme bei diesem Bereich); ein Bildschirm wird vollständig aufgenommen. Der Desktop-Ton (was auf der Standardausgabe spielt) wird mit aufgenommen. Drücke erneut Umschalt+Druck oder klicke auf den Aufnahmeknopf (oder den Stoppknopf), um zu beenden: Das Video wird dann als Datei in die Zwischenablage kopiert (in einen Dateimanager oder Chat einfügen). Aufnahmen werden in ~/Videos gespeichert; den Ordner ändern unter Einstellungen > Dienste > Video Recording Path.";
      vi = "Để quay màn hình, nhấn Shift+Print hoặc bấm nút quay trên thanh (hoặc nút Quay vùng trong overlay, hoặc nixbook-shell ipc call region recordWithSound): bộ chọn giống như khi chụp màn hình sẽ mở ra. Kéo một hình chữ nhật, hoặc chọn Cửa sổ hoặc Màn hình trên thanh công cụ phía dưới (hoặc nhấn W hoặc S): di chuột lên cửa sổ hoặc màn hình sẽ chọn nó, bấm chuột để bắt đầu quay. Cửa sổ được quay tại vị trí nó hiển thị lúc bấm (nếu di chuyển cửa sổ, bản quay vẫn giữ vùng đó); màn hình được quay toàn bộ. Âm thanh của máy (những gì phát ra ở đầu ra mặc định) cũng được thu. Nhấn lại Shift+Print hoặc bấm lại nút quay (hoặc nút dừng) để dừng: video sau đó được sao chép vào bộ nhớ tạm dưới dạng tệp (dán vào trình quản lý tệp hoặc cuộc trò chuyện). Bản quay được lưu vào ~/Videos; đổi thư mục trong Cài đặt > Dịch vụ > Video Recording Path.";
    };
    desktopControlStop = {
      en = "To stop the AI agents controlling the desktop (Claude, the AI chat, any agent using nixbook-desktop-mcp), press Mod+Shift+Escape, or click the robot in the bar (it turns into a red hand), or use the switch in Settings > Desktop agents: every agent's desktop tools are refused until you press or click again. Desktop control is paused until you first allow it, and keeps the position you left it in across reboots. In the AI chat, the send button becomes a stop button while an answer is being written, and /stop does the same.";
      fr = "Pour arrêter les agents IA qui contrôlent le bureau (Claude, le chat IA, tout agent utilisant nixbook-desktop-mcp), appuyez sur Mod+Maj+Échap, ou cliquez sur le robot dans la barre (il devient une main rouge), ou utilisez l'interrupteur dans Paramètres > Agents du bureau : les outils du bureau sont refusés à tous les agents jusqu'à un nouvel appui ou clic. Le contrôle du bureau est en pause tant que vous ne l'avez pas autorisé, et garde la position choisie après un redémarrage. Dans le chat IA, le bouton d'envoi devient un bouton d'arrêt pendant qu'une réponse s'écrit, et /stop fait de même.";
      de = "Um die KI-Agenten zu stoppen, die den Desktop steuern (Claude, der KI-Chat, jeder Agent über nixbook-desktop-mcp), drücke Mod+Umschalt+Escape, klicke auf den Roboter in der Leiste (er wird zu einer roten Hand) oder nutze den Schalter unter Einstellungen > Desktop-Agenten: Die Desktop-Werkzeuge werden allen Agenten verweigert, bis du erneut drückst oder klickst. Die Desktop-Steuerung ist pausiert, bis du sie zum ersten Mal erlaubst, und behält deine Einstellung auch nach einem Neustart. Im KI-Chat wird der Senden-Knopf zum Stopp-Knopf, während eine Antwort geschrieben wird, und /stop tut dasselbe.";
      vi = "Để dừng các tác nhân AI đang điều khiển màn hình (Claude, chat AI, mọi tác nhân dùng nixbook-desktop-mcp), nhấn Mod+Shift+Escape, hoặc bấm vào robot trên thanh (nó thành bàn tay đỏ), hoặc dùng công tắc trong Cài đặt > Tác nhân màn hình: công cụ điều khiển màn hình bị từ chối với mọi tác nhân cho đến khi bạn nhấn hoặc bấm lại. Điều khiển màn hình tạm dừng cho đến khi bạn cho phép lần đầu, và giữ nguyên lựa chọn của bạn sau khi khởi động lại. Trong chat AI, nút gửi thành nút dừng khi câu trả lời đang được viết, và /stop cũng vậy.";
    };
    windowLayouts = {
      en = "To save and restore window layouts (where every window is: monitor, workspace, column and size, and the apps to reopen), press Mod+G: pick a saved layout to restore it, or type a new name to save the windows as they are. The desktop's right-click menu has a Window layouts submenu, and Settings > Window layouts lists them to restore, update, rename or delete. AI agents can save and restore them too.";
      fr = "Pour enregistrer et restaurer des dispositions de fenêtres (où est chaque fenêtre : écran, espace de travail, colonne et taille, et les applications à rouvrir), appuyez sur Mod+G : choisissez une disposition enregistrée pour la restaurer, ou tapez un nouveau nom pour enregistrer les fenêtres telles qu'elles sont. Le menu du clic droit sur le bureau a un sous-menu Dispositions de fenêtres, et Paramètres > Dispositions de fenêtres les liste pour restaurer, mettre à jour, renommer ou supprimer. Les agents IA peuvent aussi les enregistrer et les restaurer.";
      de = "Um Fensteranordnungen zu speichern und wiederherzustellen (wo jedes Fenster ist: Bildschirm, Arbeitsbereich, Spalte und Größe, und welche Apps wieder zu öffnen sind), drücke Mod+G: Wähle eine gespeicherte Anordnung zum Wiederherstellen oder gib einen neuen Namen ein, um die Fenster so zu speichern, wie sie sind. Das Rechtsklickmenü des Desktops hat ein Untermenü Fensteranordnungen, und Einstellungen > Fensteranordnungen listet sie zum Wiederherstellen, Aktualisieren, Umbenennen oder Löschen. KI-Agenten können sie ebenfalls speichern und wiederherstellen.";
      vi = "Để lưu và khôi phục bố cục cửa sổ (vị trí của từng cửa sổ: màn hình, không gian làm việc, cột và kích thước, và các ứng dụng cần mở lại), nhấn Mod+G: chọn một bố cục đã lưu để khôi phục, hoặc gõ tên mới để lưu các cửa sổ như hiện tại. Menu chuột phải trên màn hình nền có menu con Bố cục cửa sổ, và Cài đặt > Bố cục cửa sổ liệt kê chúng để khôi phục, cập nhật, đổi tên hoặc xóa. Tác nhân AI cũng có thể lưu và khôi phục chúng.";
    };
    claudePanel = {
      en = "To use Claude in the AI chat (left sidebar), with your own Claude account and no API key: install Claude Code and log in once (run claude in a terminal), then pick Claude with /model claude or the button in Settings > Desktop agents > Claude in the side panel, where you also choose the model (Sonnet is faster) whether it may search the web, and which folders it may read (none by default: it reads none of your files unless you list a folder, or attach a file to a message). It can see and drive the desktop, but never runs commands or edits files.";
      fr = "Pour utiliser Claude dans le chat IA (panneau de gauche), avec votre propre compte Claude et sans clé API : installez Claude Code et connectez-vous une fois (lancez claude dans un terminal), puis choisissez Claude avec /model claude ou le bouton dans Paramètres > Agents du bureau > Claude dans le panneau latéral, où vous choisissez aussi le modèle (Sonnet est plus rapide) s'il peut chercher sur le web, et les dossiers qu'il peut lire (aucun par défaut : il ne lit aucun de vos fichiers sauf dans un dossier que vous ajoutez, ou un fichier joint à un message). Il peut voir et piloter le bureau, mais ne lance jamais de commandes et ne modifie aucun fichier.";
      de = "Um Claude im KI-Chat (linke Seitenleiste) mit deinem eigenen Claude-Konto und ohne API-Schlüssel zu nutzen: Installiere Claude Code und melde dich einmal an (claude in einem Terminal starten), dann wähle Claude mit /model claude oder dem Knopf unter Einstellungen > Desktop-Agenten > Claude in der Seitenleiste, wo du auch das Modell (Sonnet ist schneller) die Websuche und die Ordner festlegst, die Claude lesen darf (standardmäßig keine: es liest keine deiner Dateien, außer in Ordnern, die du einträgst, oder eine an eine Nachricht angehängte Datei). Claude kann den Desktop sehen und steuern, führt aber nie Befehle aus und bearbeitet keine Dateien.";
      vi = "Để dùng Claude trong chat AI (thanh bên trái), với tài khoản Claude của bạn và không cần khóa API: cài Claude Code và đăng nhập một lần (chạy claude trong terminal), rồi chọn Claude bằng /model claude hoặc nút trong Cài đặt > Tác nhân màn hình > Claude trong bảng bên, nơi bạn cũng chọn mô hình (Sonnet nhanh hơn) có cho phép tìm kiếm web không, và những thư mục nó được đọc (mặc định không có: nó không đọc tệp nào của bạn, trừ trong thư mục bạn thêm vào hoặc tệp bạn đính kèm vào tin nhắn). Nó có thể xem và điều khiển màn hình, nhưng không bao giờ chạy lệnh hay sửa tệp.";
    };
    agentDesktopSandbox = {
      en = "The AI agents' own desktop is sandboxed: its apps see none of your files (only the folders you allow in Settings > Desktop agents), none of your windows, clipboard or screen, and can't capture, type or click into your desktop. Two switches in Settings > Desktop agents, both on, take effect when it next opens: Hide the system's services from their apps (no system daemon's socket), and Keep their apps off this computer's local services (their own network: the internet and your local network, but not a dev server on localhost or the printer pages; switch it off if the agent should open those).";
      fr = "Le bureau des agents IA est isolé (bac à sable) : ses applications ne voient aucun de vos fichiers (seulement les dossiers autorisés dans Paramètres > Agents du bureau), ni vos fenêtres, ni votre presse-papiers, ni votre écran, et ne peuvent ni capturer votre bureau ni y taper ou cliquer. Deux interrupteurs dans Paramètres > Agents du bureau, activés par défaut, s'appliquent à sa prochaine ouverture : cacher les services du système à leurs applications (aucun socket des démons du système), et tenir leurs applications à l'écart des services locaux de cet ordinateur (leur propre réseau : internet et votre réseau local, mais pas un serveur de dev sur localhost ni les pages de l'imprimante ; désactivez-le si l'agent doit les ouvrir).";
      de = "Der eigene Desktop der KI-Agenten ist abgeschottet (Sandbox): Seine Apps sehen keine deiner Dateien (nur die in Einstellungen > Desktop-Agenten erlaubten Ordner), keine deiner Fenster, deine Zwischenablage oder deinen Bildschirm, und können deinen Desktop weder aufnehmen noch hineintippen oder -klicken. Zwei Schalter unter Einstellungen > Desktop-Agenten, beide an, gelten ab dem nächsten Öffnen: Die Dienste des Systems vor ihren Apps verbergen (kein Socket der System-Daemons) und ihre Apps von den lokalen Diensten dieses Computers fernhalten (ein eigenes Netz: Internet und dein lokales Netz, aber kein Dev-Server auf localhost und keine Druckerseiten; schalte es aus, wenn der Agent diese öffnen soll).";
      vi = "Màn hình riêng của các tác nhân AI được cách ly (sandbox): ứng dụng trên đó không thấy tệp nào của bạn (chỉ các thư mục bạn cho phép trong Cài đặt > Tác nhân màn hình), không thấy cửa sổ, bộ nhớ tạm hay màn hình của bạn, và không thể chụp, gõ hay bấm vào màn hình của bạn. Hai công tắc trong Cài đặt > Tác nhân màn hình, mặc định bật, có hiệu lực từ lần mở tiếp theo: ẩn các dịch vụ hệ thống khỏi ứng dụng của chúng (không socket nào của các daemon hệ thống), và giữ ứng dụng của chúng tránh xa các dịch vụ cục bộ của máy này (mạng riêng: internet và mạng nội bộ của bạn, nhưng không có máy chủ dev trên localhost hay trang máy in; tắt đi nếu tác nhân cần mở chúng).";
    };
    desktopMemory = {
      en = "AI agents keep a memory of this desktop so repeated tasks go faster: notes they write (app shortcuts, where things are, recipes), app names they learned and what gets used. Every agent receives it when it connects, as hints. Review, delete or clear it in Settings > Desktop agents > Desktop memory, or with nixbook-desktop-mcp memory show.";
      fr = "Les agents IA gardent une mémoire de ce bureau pour aller plus vite sur les tâches répétées : des notes qu'ils écrivent (raccourcis d'applications, où sont les choses, recettes), les noms d'applications appris et ce qui est utilisé. Chaque agent la reçoit en se connectant, comme des indications. Consultez-la, supprimez ou effacez-la dans Paramètres > Agents du bureau > Mémoire du bureau, ou avec nixbook-desktop-mcp memory show.";
      de = "KI-Agenten führen ein Gedächtnis dieses Desktops, damit wiederholte Aufgaben schneller gehen: Notizen, die sie schreiben (App-Tastenkürzel, wo Dinge sind, Rezepte), gelernte App-Namen und was genutzt wird. Jeder Agent bekommt es beim Verbinden als Hinweise. Ansehen, löschen oder leeren unter Einstellungen > Desktop-Agenten > Desktop-Gedächtnis oder mit nixbook-desktop-mcp memory show.";
      vi = "Các tác nhân AI giữ một bộ nhớ về màn hình này để các việc lặp lại nhanh hơn: ghi chú chúng viết (phím tắt ứng dụng, vị trí các thứ, công thức), tên ứng dụng đã học và những gì được dùng. Mỗi tác nhân nhận nó khi kết nối, dưới dạng gợi ý. Xem, xóa hoặc dọn sạch trong Cài đặt > Tác nhân màn hình > Bộ nhớ màn hình, hoặc bằng nixbook-desktop-mcp memory show.";
    };
  };

  # Generic answers to "how do I …" questions; the configuration's own way
  # of doing it (a deploy tool, an update script) overrides one by name.
  defaultHowTo =
    calendarHowTo
    // shellHowTo
    // (
      if os != null then
        {
          apply = {
            en = "To apply a change to the NixOS configuration, run `sudo nixos-rebuild switch`.";
            fr = "Pour appliquer une modification de la configuration NixOS, lancez `sudo nixos-rebuild switch`.";
            de = "Um eine Änderung der NixOS-Konfiguration anzuwenden, führe `sudo nixos-rebuild switch` aus.";
            vi = "Để áp dụng thay đổi cấu hình NixOS, chạy `sudo nixos-rebuild switch`.";
          };
          update = {
            en = "To update the system, update nixpkgs (`sudo nix-channel --update`, or `nix flake update` for a flake) and run `sudo nixos-rebuild switch`.";
            fr = "Pour mettre à jour le système, mettez à jour nixpkgs (`sudo nix-channel --update`, ou `nix flake update` pour un flake) puis lancez `sudo nixos-rebuild switch`.";
            de = "Um das System zu aktualisieren, aktualisiere nixpkgs (`sudo nix-channel --update` oder `nix flake update` bei einem Flake) und führe `sudo nixos-rebuild switch` aus.";
            vi = "Để cập nhật hệ thống, cập nhật nixpkgs (`sudo nix-channel --update`, hoặc `nix flake update` với flake) rồi chạy `sudo nixos-rebuild switch`.";
          };
          rollback = {
            en = "To roll back (undo) the last system change, run `sudo nixos-rebuild switch --rollback`, or choose an older generation in the boot menu.";
            fr = "Pour revenir en arrière (annuler) la dernière modification du système, lancez `sudo nixos-rebuild switch --rollback`, ou choisissez une génération plus ancienne dans le menu de démarrage.";
            de = "Um die letzte Systemänderung zurückzusetzen (rückgängig zu machen), führe `sudo nixos-rebuild switch --rollback` aus oder wähle im Bootmenü eine ältere Generation.";
            vi = "Để quay lại (hoàn tác) thay đổi hệ thống gần nhất, chạy `sudo nixos-rebuild switch --rollback`, hoặc chọn một thế hệ (generation) cũ hơn trong menu khởi động.";
          };
          generations = {
            en = "To list the system generations (previous versions of the system), run `nixos-rebuild list-generations`.";
            fr = "Pour lister les générations du système (versions précédentes du système), lancez `nixos-rebuild list-generations`.";
            de = "Um die Systemgenerationen (frühere Versionen des Systems) aufzulisten, führe `nixos-rebuild list-generations` aus.";
            vi = "Để liệt kê các thế hệ (generation, phiên bản trước) của hệ thống, chạy `nixos-rebuild list-generations`.";
          };
          gc = {
            en = "To free disk space, delete old generations and unused packages with `sudo nix-collect-garbage -d` (garbage collection), then apply the configuration again to clean the boot menu.";
            fr = "Pour libérer de l'espace disque, supprimez les anciennes générations et les paquets inutilisés avec `sudo nix-collect-garbage -d` (ramasse-miettes), puis appliquez de nouveau la configuration pour nettoyer le menu de démarrage.";
            de = "Um Speicherplatz freizugeben, lösche alte Generationen und ungenutzte Pakete mit `sudo nix-collect-garbage -d` (Garbage Collection) und wende die Konfiguration erneut an, um das Bootmenü aufzuräumen.";
            vi = "Để giải phóng dung lượng đĩa, xóa các thế hệ cũ và gói không dùng bằng `sudo nix-collect-garbage -d` (dọn rác), rồi áp dụng lại cấu hình để dọn menu khởi động.";
          };
          search = {
            en = "To find a package, run `nix search nixpkgs <name>` or search https://search.nixos.org/packages.";
            fr = "Pour trouver un paquet, lancez `nix search nixpkgs <nom>` ou cherchez sur https://search.nixos.org/packages.";
            de = "Um ein Paket zu finden, führe `nix search nixpkgs <name>` aus oder suche auf https://search.nixos.org/packages.";
            vi = "Để tìm một gói, chạy `nix search nixpkgs <tên>` hoặc tìm trên https://search.nixos.org/packages.";
          };
          try = {
            en = "To try a program without installing it, run `nix shell nixpkgs#<name>` (or `nix run nixpkgs#<name>`).";
            fr = "Pour essayer un programme sans l'installer, lancez `nix shell nixpkgs#<nom>` (ou `nix run nixpkgs#<nom>`).";
            de = "Um ein Programm ohne Installation auszuprobieren, führe `nix shell nixpkgs#<name>` (oder `nix run nixpkgs#<name>`) aus.";
            vi = "Để dùng thử một chương trình mà không cài, chạy `nix shell nixpkgs#<tên>` (hoặc `nix run nixpkgs#<tên>`).";
          };
          install = {
            en = "To install a program for good, add it to environment.systemPackages (system) or home.packages (Home Manager) in the configuration, then apply it.";
            fr = "Pour installer un programme durablement, ajoutez-le à environment.systemPackages (système) ou home.packages (Home Manager) dans la configuration, puis appliquez-la.";
            de = "Um ein Programm dauerhaft zu installieren, füge es in der Konfiguration zu environment.systemPackages (System) oder home.packages (Home Manager) hinzu und wende sie an.";
            vi = "Để cài một chương trình lâu dài, thêm nó vào environment.systemPackages (hệ thống) hoặc home.packages (Home Manager) trong cấu hình, rồi áp dụng.";
          };
          logs = {
            en = "To see a service's logs, run `journalctl -u <service>` (`journalctl --user -u <service>` for a user service); `systemctl status <service>` shows whether it is running.";
            fr = "Pour voir les journaux (logs) d'un service, lancez `journalctl -u <service>` (`journalctl --user -u <service>` pour un service utilisateur) ; `systemctl status <service>` indique s'il tourne.";
            de = "Um die Protokolle (Logs) eines Dienstes zu sehen, führe `journalctl -u <dienst>` aus (`journalctl --user -u <dienst>` für einen Benutzerdienst); `systemctl status <dienst>` zeigt, ob er läuft.";
            vi = "Để xem nhật ký (log) của một dịch vụ, chạy `journalctl -u <dịch vụ>` (`journalctl --user -u <dịch vụ>` với dịch vụ người dùng); `systemctl status <dịch vụ>` cho biết nó có đang chạy không.";
          };
          options = {
            en = "To look up configuration options, run `man configuration.nix` (NixOS) or `man home-configuration.nix` (Home Manager), or search https://search.nixos.org/options.";
            fr = "Pour chercher des options de configuration, lancez `man configuration.nix` (NixOS) ou `man home-configuration.nix` (Home Manager), ou cherchez sur https://search.nixos.org/options.";
            de = "Um Konfigurationsoptionen nachzuschlagen, führe `man configuration.nix` (NixOS) oder `man home-configuration.nix` (Home Manager) aus oder suche auf https://search.nixos.org/options.";
            vi = "Để tra cứu tùy chọn cấu hình, chạy `man configuration.nix` (NixOS) hoặc `man home-configuration.nix` (Home Manager), hoặc tìm trên https://search.nixos.org/options.";
          };
        }
      else
        {
          apply = {
            en = "To apply a change to the Home Manager configuration, run `home-manager switch`.";
            fr = "Pour appliquer une modification de la configuration Home Manager, lancez `home-manager switch`.";
            de = "Um eine Änderung der Home-Manager-Konfiguration anzuwenden, führe `home-manager switch` aus.";
            vi = "Để áp dụng thay đổi cấu hình Home Manager, chạy `home-manager switch`.";
          };
          generations = {
            en = "To list the Home Manager generations (previous versions), run `home-manager generations`; run a generation's `activate` script to roll back to it.";
            fr = "Pour lister les générations Home Manager (versions précédentes), lancez `home-manager generations` ; lancez le script `activate` d'une génération pour y revenir.";
            de = "Um die Home-Manager-Generationen (frühere Versionen) aufzulisten, führe `home-manager generations` aus; das `activate`-Skript einer Generation setzt auf sie zurück.";
            vi = "Để liệt kê các thế hệ Home Manager (phiên bản trước), chạy `home-manager generations`; chạy script `activate` của một thế hệ để quay lại nó.";
          };
          gc = {
            en = "To free disk space, run `home-manager expire-generations '-30 days'` then `nix-collect-garbage` (garbage collection).";
            fr = "Pour libérer de l'espace disque, lancez `home-manager expire-generations '-30 days'` puis `nix-collect-garbage` (ramasse-miettes).";
            de = "Um Speicherplatz freizugeben, führe `home-manager expire-generations '-30 days'` und dann `nix-collect-garbage` (Garbage Collection) aus.";
            vi = "Để giải phóng dung lượng đĩa, chạy `home-manager expire-generations '-30 days'` rồi `nix-collect-garbage` (dọn rác).";
          };
          search = {
            en = "To find a package, run `nix search nixpkgs <name>` or search https://search.nixos.org/packages.";
            fr = "Pour trouver un paquet, lancez `nix search nixpkgs <nom>` ou cherchez sur https://search.nixos.org/packages.";
            de = "Um ein Paket zu finden, führe `nix search nixpkgs <name>` aus oder suche auf https://search.nixos.org/packages.";
            vi = "Để tìm một gói, chạy `nix search nixpkgs <tên>` hoặc tìm trên https://search.nixos.org/packages.";
          };
          try = {
            en = "To try a program without installing it, run `nix shell nixpkgs#<name>` (or `nix run nixpkgs#<name>`).";
            fr = "Pour essayer un programme sans l'installer, lancez `nix shell nixpkgs#<nom>` (ou `nix run nixpkgs#<nom>`).";
            de = "Um ein Programm ohne Installation auszuprobieren, führe `nix shell nixpkgs#<name>` (oder `nix run nixpkgs#<name>`) aus.";
            vi = "Để dùng thử một chương trình mà không cài, chạy `nix shell nixpkgs#<tên>` (hoặc `nix run nixpkgs#<tên>`).";
          };
          install = {
            en = "To install a program for good, add it to home.packages in the Home Manager configuration, then run `home-manager switch`.";
            fr = "Pour installer un programme durablement, ajoutez-le à home.packages dans la configuration Home Manager, puis lancez `home-manager switch`.";
            de = "Um ein Programm dauerhaft zu installieren, füge es in der Home-Manager-Konfiguration zu home.packages hinzu und führe `home-manager switch` aus.";
            vi = "Để cài một chương trình lâu dài, thêm nó vào home.packages trong cấu hình Home Manager, rồi chạy `home-manager switch`.";
          };
          logs = {
            en = "To see a user service's logs, run `journalctl --user -u <service>`; `systemctl --user status <service>` shows whether it is running.";
            fr = "Pour voir les journaux (logs) d'un service utilisateur, lancez `journalctl --user -u <service>` ; `systemctl --user status <service>` indique s'il tourne.";
            de = "Um die Protokolle (Logs) eines Benutzerdienstes zu sehen, führe `journalctl --user -u <dienst>` aus; `systemctl --user status <dienst>` zeigt, ob er läuft.";
            vi = "Để xem nhật ký (log) của dịch vụ người dùng, chạy `journalctl --user -u <dịch vụ>`; `systemctl --user status <dịch vụ>` cho biết nó có đang chạy không.";
          };
          options = {
            en = "To look up Home Manager options, run `man home-configuration.nix` or search https://home-manager-options.extranix.com.";
            fr = "Pour chercher des options Home Manager, lancez `man home-configuration.nix` ou cherchez sur https://home-manager-options.extranix.com.";
            de = "Um Home-Manager-Optionen nachzuschlagen, führe `man home-configuration.nix` aus oder suche auf https://home-manager-options.extranix.com.";
            vi = "Để tra cứu tùy chọn Home Manager, chạy `man home-configuration.nix` hoặc tìm trên https://home-manager-options.extranix.com.";
          };
        }
    );
  packages =
    config.home.packages ++ lib.optionals (osConfig != null) osConfig.environment.systemPackages;

  # The Neovim keymaps, for scripts/assistant-facts.py.
  nvimInfo = {
    inherit (cfg.assistant.nixvim) leader localLeader keymaps;
  };
  # What scripts/assistant-facts.py turns into facts and the AI context.
  howTo = lib.filterAttrs (_: v: v != null) cfg.assistant.howTo;
  contextInfo = {
    nvim = nvimInfo;
    os = cfg.assistant.os;
    inherit howTo;
  };

  # Machine context for the Intelligence tab's system prompt
  # (services/Ai.qml appends it while ai.includeSystemContext is on), plus the
  # niri keybinds and Neovim keymaps when there are any. No secrets: it is a
  # store path.
  systemContextFile =
    pkgs.runCommand "nixbook-shell-system-context.md"
      {
        header = cfg.assistant.context;
        niriKdl = cfg.assistant.niriConfig;
        info = builtins.toJSON contextInfo;
        passAsFile = [
          "header"
          "niriKdl"
          "info"
        ];
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        {
          printf '# About this machine (reference)\n'
          printf 'The sections below are generated from this machine'"'"'s configuration. Use them as reference together with your own knowledge: they do not limit what you can answer. Answer any question; when you are not sure, say so.\n\n'
          cat "$headerPath"
        } > "$out"
        if [ -s "$niriKdlPath" ]; then
          {
            printf '\n## Keyboard shortcuts (niri, rendered from the configuration)\n'
            printf 'The niri keybinds as configured (Mod = the Super/Windows key; a spawn of nixbook-shell ipc call <target> <fn> opens a shell panel).\n```kdl\n'
            # Store paths only add noise: /nix/store/<hash>-kitty-0.49/bin/kitty -> kitty
            ${lib.getExe pkgs.gawk} '/^binds \{/,/^\}/' "$niriKdlPath" \
              | ${lib.getExe pkgs.gnused} -E 's#/nix/store/[a-z0-9]{32}-[^/ "]*/bin/##g'
            printf '```\n'
          } >> "$out"
        fi
        python3 ${./scripts/assistant-facts.py} --markdown "$infoPath" >> "$out"
      '';

  # The same, as retrievable one-sentence facts for the chat's config
  # assistant (services/ConfigAssistant.qml, no AI: it answers from these —
  # keys, modules, installed packages, settings). Built by
  # scripts/assistant-facts.py.
  systemFactsFile =
    let
      info = {
        host = if osConfig != null then osConfig.networking.hostName else "unknown";
        user = config.home.username;
        inherit (cfg.assistant) coreFacts modules;
        pinned = lib.genAttrs pinnedPaths (
          path: lib.attrByPath (lib.splitString "." path) null pinnedSettings
        );
        packages = names packages;
        # Every setting the shell has (answers naming another are flagged).
        settingPaths = settingsLib.flattenPaths [ ] settingsLib.builtinDefaults ++ settingsLib.liveKeys;
        inherit (contextInfo) nvim os howTo;
      };
    in
    pkgs.runCommand "nixbook-shell-system-facts.json"
      {
        info = builtins.toJSON info;
        niriKdl = cfg.assistant.niriConfig;
        passAsFile = [
          "info"
          "niriKdl"
        ];
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        ${lib.getExe pkgs.gawk} '/^binds \{/,/^\}/' "$niriKdlPath" \
          | ${lib.getExe pkgs.gnused} -E 's#/nix/store/[a-z0-9]{32}-[^/ "]*/bin/##g' > binds.kdl
        python3 ${./scripts/assistant-facts.py} "$infoPath" binds.kdl > "$out"
      '';

  # Four-language sentence, as scripts/assistant-facts.py expects.
  factType = lib.types.submodule {
    options = lib.genAttrs [ "en" "fr" "de" "vi" ] (lang: lib.mkOption { type = lib.types.str; });
  };
in
{
  # The apps coloured like the shell are switched on from the Settings menu
  # now (appearance.wallpaperTheming.apps), live.
  imports =
    map
      (
        app:
        lib.mkRemovedOptionModule [ "programs" "nixbook-shell" "appTheming" app ] ''
          The apps coloured from the shell's palette are switched on and off in
          the shell: Settings > Appearance > Color generation > Apps.
        ''
      )
      [
        "vesktop"
        "youtubeMusic"
        "zen"
      ];

  options.programs.nixbook-shell = {
    enable = lib.mkEnableOption ''
      nixbook-shell, a Quickshell (QML) desktop shell (bar, dock, sidebars,
      launcher, notifications, lock screen, desktop widgets). It runs as the
      `nixbook-shell` user service, bound to `graphical-session.target`, under
      niri; bind keys to `nixbook-shell ipc call <target> <function>`
      to drive its panels'';

    package = lib.mkOption {
      type = lib.types.package;
      default = (import ./default.nix { inherit pkgs; }).package;
      defaultText = lib.literalExpression "(import ./nixbook-shell { inherit pkgs; }).package";
      description = ''
        The `nixbook-shell` launcher. Build it with your own quickshell pin
        through `import ./nixbook-shell { inherit pkgs quickshellSrc; }`.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule settingsLib.settingsModule;
      default = { };
      # ~450 generated leaves: document the option, not every leaf.
      visible = "shallow";
      example = lib.literalExpression ''
        {
          bar.bottom = true;
          background.screenList = [ "eDP-1" ];
          appearance.theme = "persona";
          appearance.persona.variant = "p3r";
        }
      '';
      description = ''
        nixbook-shell settings (the dot-paths of
        `~/.config/nixbook-shell/config.json`, as nested attributes).

        Every key set here is applied on each activation and **locked** in the
        shell's Settings menu (red lock, control disabled); every key left unset
        stays editable from the menu and persists across restarts, reboots and
        switches. Removing a key unlocks it in the running shell after the next
        switch.

        The keys are typed options generated from the shell's built-in
        defaults (`builtin-defaults.json`), so a misspelt key fails
        evaluation. `nixbook-shell config diff` prints the settings changed
        from the menu as Nix lines; `nixbook-shell config pinned` lists the
        locked keys. Runtime state (wallpaper path, accent colour, avatar,
        preset metadata) has no option: the shell and its scripts own it.
      '';
    };

    cliphist.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the cliphist store daemon the shell's clipboard history (search
        `clipboardToggle`) reads from. Turn it off if something else already
        runs `cliphist store`.
      '';
    };

    splash.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Show the shell's loading screen from the moment the session starts
        (`nixbook-shell splash`, the `nixbook-shell-splash` user service),
        until the shell has loaded and its own loading screen takes over: no
        black screen or half-drawn desktop between the login screen and the
        shell.
      '';
    };

    # "The shell's palette": the one it shows, the wallpaper's or a theme
    # variant's own (Persona, Chiikawa, Cyberpunk…), light or dark. Which apps
    # follow it is chosen in the shell (Settings > Appearance > Color
    # generation > Apps); only what has to be set up outside it is here.
    appTheming = {
      qt.enable = lib.mkEnableOption ''
        Qt apps following the shell's palette when "Qt & KDE" is on in the
        shell's Settings (Appearance > Color generation > Apps): Qt goes
        through qt6ct/qt5ct with the Breeze style and a custom palette (the
        colour scheme the shell generates). KDE apps (Dolphin…) get the same
        scheme in ~/.config/kdeglobals from the shell alone. Running apps
        follow palette changes. Sets `qt.*`: turn off anything else theming Qt
        (e.g. stylix's `qt` target)
      '';
    };

    desktopMcp = {
      settings = lib.mkOption {
        type = lib.types.submodule {
          freeformType = (pkgs.formats.json { }).type;
          options.tools = lib.mkOption {
            type = lib.types.listOf (
              lib.types.enum [
                "observe"
                "screen"
                "windows"
                "input"
                "shell"
                "memory"
              ]
            );
            default = [
              "observe"
              "screen"
              "windows"
              "input"
              "shell"
              "memory"
            ];
            description = ''
              Tool groups AI agents get: `observe` (windows, workspaces,
              apps), `screen` (screenshots, reading the clipboard), `windows`
              (focus, move, close, launch apps), `input` (keyboard, pointer,
              writing the clipboard), `shell` (the shell's IPC, notifications),
              `memory` (notes agents keep about this desktop, and the digest of
              it they get when they connect).
            '';
          };
        };
        default = { };
        example = lib.literalExpression ''
          {
            tools = [ "observe" "windows" ];
            actionsPerMinute = 60;
            inputDenyApps = [ "^org\\.gnome\\.Nautilus$" ];
          }
        '';
        description = ''
          Settings of `nixbook-desktop-mcp`, the desktop control MCP server
          AI agents (Claude Code, opencode, the shell's AI chat…) use to see
          and drive the desktop, written to
          `~/.config/nixbook-shell/desktop-mcp.json`. Other keys:
          `inputDenyApps`, `inputDenyTitles` (regexes: no keyboard or pointer
          input into those windows; set to replace the defaults, which cover
          terminals, password managers and password prompts),
          `shellIpcDenyTargets`, `allowSuperKey`, `maxTextLength` (typed text and
          tasks), `maxNoteLength` (a note),
          `actionsPerMinute`, `notifyOnControl`, `screenshotMaxEdge`,
          `ocrLanguages` (read_screen's tesseract languages, e.g. `eng+fra`).
          `nixbook-desktop-mcp config` prints the effective settings.
        '';
      };

      http = {
        enable = lib.mkEnableOption ''
          the desktop control MCP server over HTTP, for agents that can't
          start it themselves (the `nixbook-desktop-mcp` user service). It
          listens on 127.0.0.1 only, so nothing off this machine can reach
          it and no firewall port is opened; clients need the bearer token
          from `nixbook-desktop-mcp token`, and must run as this user'';
        port = lib.mkOption {
          type = lib.types.port;
          default = 7823;
          description = "Port on 127.0.0.1 of the HTTP MCP endpoint (`/mcp`).";
        };
      };
    };

    assistant = {
      context = lib.mkOption {
        type = lib.types.lines;
        default = ''
          ## Desktop shell: nixbook-shell
          The bar, dock, sidebars, launcher, notifications, lock screen and desktop
          widgets are nixbook-shell, a Quickshell (QML) shell configured by the Home
          Manager module `programs.nixbook-shell`. Its settings live in
          `~/.config/nixbook-shell/config.json` and are edited from its Settings
          window ("Shell settings" in the launcher). Settings set in Nix
          (`programs.nixbook-shell.settings`) are locked in that window; everything
          else is editable there. `nixbook-shell config diff` prints the settings
          changed from the menu as Nix lines, `nixbook-shell ipc call <target>
          <function>` drives panels.

          Settings set in Nix on this machine:
          ${cfg.assistant.pinnedLines}

          ## Packages installed (Home Manager${lib.optionalString (osConfig != null) " and NixOS"})
          ${lib.concatStringsSep ", " (names packages)}
        '';
        defaultText = lib.literalMD "a description of the shell, the settings set in Nix and the installed packages";
        description = ''
          Markdown appended to the AI chat's system prompt while
          `ai.includeSystemContext` is on: what the assistant should know about
          this machine and how its configuration is changed. The niri keybinds
          (`assistant.niriConfig`) and Neovim keymaps (`assistant.nixvim`) are
          appended to it.
        '';
      };

      pinnedLines = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        internal = true;
        default = lib.concatStringsSep "\n" (
          map (
            path:
            "- `${path}` = `${builtins.toJSON (lib.attrByPath (lib.splitString "." path) null pinnedSettings)}`"
          ) pinnedPaths
        );
        description = "The settings set in Nix, one Markdown list item each (for `assistant.context`).";
      };

      coreFacts = lib.mkOption {
        type = lib.types.listOf factType;
        default = [
          {
            en = "Shell settings (bar, dock, widgets, notifications, theme) set in Nix are in programs.nixbook-shell.settings of the Home Manager configuration; the others are changed in the shell's Settings window.";
            fr = "Les réglages du shell (barre, dock, widgets, notifications, thème) définis dans Nix sont dans programs.nixbook-shell.settings de la configuration Home Manager ; les autres se changent dans la fenêtre des paramètres du shell.";
            de = "In Nix gesetzte Shell-Einstellungen (Leiste, Dock, Widgets, Benachrichtigungen, Design) stehen in programs.nixbook-shell.settings der Home-Manager-Konfiguration; die übrigen werden im Einstellungsfenster der Shell geändert.";
            vi = "Thiết lập shell (thanh, dock, widget, thông báo, giao diện) đặt trong Nix nằm ở programs.nixbook-shell.settings của cấu hình Home Manager; các thiết lập khác đổi trong cửa sổ cài đặt của shell.";
          }
        ];
        description = ''
          Core statements for the config assistant (no AI), in English, French,
          German and Vietnamese: where and how this machine's configuration is
          changed and applied.
        '';
      };

      modules = {
        all = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Configuration modules the config assistant knows of.";
        };
        enabled = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "The enabled ones among `modules.all`.";
        };
      };

      niriConfig = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = lib.literalExpression "config.programs.niri.finalConfig";
        description = ''
          The rendered niri configuration (KDL): its `binds { … }` block
          becomes keybind facts and is appended to the AI context. Empty: no
          keybinds.
        '';
      };

      os = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = osInfo;
        defaultText = lib.literalMD "read from the evaluated NixOS (`osConfig`) and Home Manager configurations";
        description = ''
          The operating system as configured (NixOS release, kernel, host, time
          zone, locale, keyboard layout, bootloader, shell, editor, Nix,
          accounts, and `toggles`: every NixOS and Home Manager option set with
          a real `enable` option, discovered from the options trees, on or off
          — the NixOS ones need nixbook-shell's NixOS module), for the
          config assistant ("which kernel?", "is bluetooth enabled?", "which
          services are enabled?") and the AI context. Built from the evaluated
          configuration; override a key to correct or hide it (null).
        '';
      };

      howTo = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr factType);
        default = { };
        description = ''
          Answers to "how do I …" questions about the system, by name: `apply`,
          `update`, `rollback`, `generations`, `gc`, `search`, `try`,
          `install`, `logs`, `options` (generic NixOS ones by default, Home
          Manager ones without NixOS), and how the calendars and to-do list
          sync through DankCalendar: `calendarConnect`,
          `calendarOtherAccounts`, `calendarEvents`, `calendarReminders`, `calendarTasks`,
          `calendarTroubleshoot`. Set one to your configuration's own way
          (a deploy tool, an update script), or to null to drop it; the others
          keep their default.
        '';
      };

      nixvim = {
        keymaps = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                key = lib.mkOption {
                  type = lib.types.str;
                  description = "The key sequence, as in nixvim (`<leader>ff`, `<C-p>`, `gd`).";
                };
                mode = lib.mkOption {
                  type = with lib.types; either str (listOf str);
                  default = "n";
                  description = "Mode(s), as in nixvim (`\"\"` = normal, visual and operator-pending).";
                };
                action = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "The mapped keys or command (`:bnext<CR>`), or Lua code when `lua`.";
                };
                lua = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Whether `action` is Lua code.";
                };
                desc = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "What it does (else it is described from `action`).";
                };
                scope = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "filetype:markdown";
                  description = ''
                    Where it applies: null (everywhere), `event:<Event>`
                    (`event:LspAttach`: buffers with an LSP server),
                    `filetype:<ft>` or `file:<runtime file>`.
                  '';
                };
              };
            }
          );
          default = nixvimKeymaps;
          defaultText = lib.literalMD ''
            the keymaps of the evaluated `programs.nixvim` configuration when
            nixvim's Home Manager module is imported and enabled (`keymaps`,
            `keymapsOnEvents`, `lsp.keymaps`, `files.<name>.keymaps`), else `[ ]`
          '';
          description = ''
            Neovim keymaps for the config assistant (listed and looked up by key,
            "what does <leader>ff do in vim?") and the AI context. Read from the
            final nixvim configuration, so an override anywhere shows here as
            Neovim gets it. A later keymap for the same key, modes and scope
            replaces an earlier one.
          '';
        };
        leader = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = if nixvimEnabled then nixvim.globals.mapleader or null else null;
          defaultText = lib.literalExpression "config.programs.nixvim.globals.mapleader or null";
          description = "Neovim's `mapleader` (null: its default, backslash).";
        };
        localLeader = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = if nixvimEnabled then nixvim.globals.maplocalleader or null else null;
          defaultText = lib.literalExpression "config.programs.nixvim.globals.maplocalleader or null";
          description = "Neovim's `maplocalleader` (null: its default, backslash).";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        warnings =
          map (
            key:
            "programs.nixbook-shell.settings.${key} was removed (it did nothing) and is ignored: remove it."
          ) (settingsLib.removedKeysSet cfg.settings)
          ++ lib.optional (cfg.settings.appearance.persona.enable != null) ''
            programs.nixbook-shell.settings.appearance.persona.enable is deprecated: use
            appearance.theme = "${
              if cfg.settings.appearance.persona.enable then "persona" else "material"
            }" (the themes are in nixbook-shell/src/modules/common/themes.json).
          '';

        # Defaults one by one, so setting one answer keeps the others.
        programs.nixbook-shell.assistant.howTo = lib.mapAttrs (_: lib.mkDefault) defaultHowTo;

        xdg.configFile."quickshell/${configName}".source = cfg.package.passthru.shell;

        # The manifest the shell reads to know which settings Nix owns: every
        # pinned leaf path. Drives the red lock icon and the disabled control in
        # the Settings menu (src/modules/common/NixManaged.qml).
        xdg.configFile."nixbook-shell/nix-managed.json".source = nixManagedFile;
        # ...and their values: NixManaged.qml restores any pinned key that gets
        # changed at runtime (menu, QuickConfig, IPC, scripts); `nixbook-shell config`
        # reads them too.
        xdg.configFile."nixbook-shell/nix-pinned-values.json".source = pinnedFile;
        # Machine context for the AI assistant (see above).
        xdg.configFile."nixbook-shell/system-context.md".source = systemContextFile;
        xdg.configFile."nixbook-shell/system-facts.json".source = systemFactsFile;
        # Desktop control for AI agents (scripts/desktop-mcp.py).
        xdg.configFile."nixbook-shell/desktop-mcp.json".source =
          (pkgs.formats.json { }).generate "desktop-mcp.json"
            (cfg.desktopMcp.settings // { http.port = cfg.desktopMcp.http.port; });

        # Launcher entry for the Settings window (nixbook-shell's own launcher, fuzzel…).
        xdg.desktopEntries.nixbook-shell-settings = {
          name = "Shell settings";
          genericName = "Desktop shell settings";
          comment = "Settings of the nixbook-shell desktop shell (bar, dock, widgets, theme…)";
          exec = "${lib.getExe cfg.package} ipc call settings open";
          icon = "preferences-desktop";
          terminal = false;
          categories = [
            "Settings"
            "DesktopSettings"
          ];
          settings.Keywords = "settings;preferences;shell;nixbook;bar;dock;theme;wallpaper;persona;";
        };

        home.packages = [
          cfg.package
          cfg.package.passthru.quickshell
          # The faces appearance.fonts names (fonts.nix).
          cfg.package.passthru.fonts
          # Condensed display face used by the optional Persona theme
          # (appearance.persona.fonts) for titles and numbers.
          pkgs.oswald
          # Rounded face used by the optional Chiikawa theme
          # (appearance.chiikawa.fonts, themes.json style.fonts).
          pkgs.nunito
          # (Rajdhani, the Cyberpunk 2077 theme's condensed tech face, is in
          # fonts.nix: nixpkgs doesn't ship it.)
          # `dcal`: DankCalendar's CLI (accounts, sync) for the user too.
          cfg.package.passthru.dankcalendar
          # `nixbook-desktop-mcp`: the desktop control MCP server, for
          # `claude mcp add` and the like, and its pause/resume kill switch.
          cfg.package.passthru.desktopMcp
        ];

        # The shell writes its settings, generated Material You palette and
        # wallpaper state into these; nothing creates them for us on a fresh user.
        #
        # config.json itself stays a real file (the shell rewrites it live from the
        # Settings panel, so it cannot be an xdg.configFile): every key Nix sets is
        # merged into it on each activation (Nix wins), every other key is left
        # alone. Runs after linkGeneration so the running shell, told to reload,
        # sees the new lock manifest too.
        home.activation.nixbookShellDirs = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
          run mkdir -p \
            "''${XDG_CONFIG_HOME:-$HOME/.config}/nixbook-shell" \
            "''${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/wallpaper" \
            "''${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/user/generated"

          shell_config="''${XDG_CONFIG_HOME:-$HOME/.config}/nixbook-shell/config.json"

          shell_tmp=$(mktemp -d)
          echo '{}' > "$shell_tmp/empty.json"
          shell_live="$shell_tmp/empty.json"
          shell_ok=1
          if [ -s "$shell_config" ]; then
            if ${lib.getExe pkgs.jq} -e 'type == "object"' "$shell_config" >/dev/null 2>&1; then
              shell_live="$shell_config"
            else
              warnEcho "nixbook-shell: $shell_config is not a valid JSON object, leaving it alone"
              shell_ok=0
            fi
          fi
          if [ "$shell_ok" = 1 ]; then
            if ${lib.getExe pkgs.jq} -n \
                  --slurpfile live "$shell_live" \
                  --slurpfile pinned ${pinnedFile} \
                  '$live[0] * $pinned[0]' > "$shell_tmp/config.json"; then
              run install -m644 "$shell_tmp/config.json" "$shell_config"
            else
              warnEcho "nixbook-shell: failed to merge settings into $shell_config"
            fi
          fi
          rm -rf "$shell_tmp"

          # A running shell doesn't notice the swapped symlinks: have it re-read
          # the lock manifest, the pinned values and config.json. No-op when the
          # shell isn't running.
          if [ -z "''${DRY_RUN:-}" ]; then
            XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
              ${lib.getExe cfg.package} ipc call nixManaged reload >/dev/null 2>&1 || true
          fi
        '';

        systemd.user.services.nixbook-shell = {
          Unit = {
            Description = "nixbook-shell Quickshell desktop shell";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe cfg.package;
            Restart = "on-failure";
            RestartSec = 2;
            Slice = "app.slice";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # DankCalendar's daemon, behind the shell's calendars and to-do list
        # (sync, reminders, tray icon; its window opens on demand), as its own
        # dcal.service does. Its window is a quickshell instance started from
        # PATH: the shell's quickshell is put first, so the window (what
        # "Open DankCalendar" and the calendar clicks show) exists whatever the
        # user manager's PATH holds.
        systemd.user.services.dcal = {
          Unit = {
            Description = "DankCalendar (calendar sync for nixbook-shell)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = toString (
              pkgs.writeShellScript "dcal-session" ''
                export PATH=${lib.makeBinPath [ cfg.package.passthru.quickshell ]}''${PATH:+:$PATH}
                exec ${lib.getExe cfg.package.passthru.dankcalendar} run --session --hidden
              ''
            );
            Restart = "on-failure";
            RestartSec = 2;
            Slice = "app.slice";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # Started before the shell (Before=): a small instance that is up well
        # before the shell's QML has loaded. It quits by itself once the shell's
        # BootSplash is on screen (the marker below), or after 20 s.
        systemd.user.services.nixbook-shell-splash = lib.mkIf cfg.splash.enable {
          Unit = {
            Description = "nixbook-shell loading screen (until the shell is up)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
            Before = [ "nixbook-shell.service" ];
          };
          Service = {
            Type = "simple";
            # Only while the shell isn't up yet (session start), never when a
            # switch (re)starts this unit under a running shell.
            ExecCondition = "${pkgs.bash}/bin/bash -c '! ${pkgs.systemd}/bin/systemctl --user is-active --quiet nixbook-shell.service'";
            # A marker left by the previous shell start in this session.
            ExecStartPre = "${pkgs.coreutils}/bin/rm -f %t/nixbook-shell/boot-splash-shown";
            ExecStart = "${lib.getExe cfg.package} splash";
            Restart = "no";
            Slice = "app.slice";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # The desktop control MCP server over HTTP (desktopMcp.http). It binds
        # 127.0.0.1 itself; the unit also keeps it off IPv6 and any socket
        # family but loopback TCP and Unix sockets (niri, Wayland, ydotoold).
        systemd.user.services.nixbook-desktop-mcp = lib.mkIf cfg.desktopMcp.http.enable {
          Unit = {
            Description = "nixbook-shell desktop control MCP server (127.0.0.1 only)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe cfg.package.passthru.desktopMcp} serve --http --port ${toString cfg.desktopMcp.http.port}";
            Restart = "on-failure";
            RestartSec = 2;
            Slice = "app.slice";
            NoNewPrivileges = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
            ];
            UMask = "0077";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # The agents' own desktop (scripts/agent-desktop.sh): started on demand
        # by `nixbook-desktop-mcp desktop agent` and the agents' next action,
        # stopped by `desktop stop` or with the session.
        systemd.user.services.nixbook-agent-desktop = {
          Unit = {
            Description = "A desktop of their own for AI agents (nested niri)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe cfg.package.passthru.agentDesktop;
            Slice = "app.slice";
          };
        };

        systemd.user.services.cliphist = lib.mkIf cfg.cliphist.enable {
          Unit = {
            Description = "Clipboard history store for nixbook-shell (cliphist)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${cfg.package.passthru.cliphistWatch}";
            Restart = "on-failure";
            RestartSec = 2;
            Slice = "background.slice";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      }

      # appTheming.qt: qt6ct/qt5ct pointed at the palette the shell renders.
      (lib.mkIf cfg.appTheming.qt.enable {
        qt =
          let
            appearance.Appearance = {
              custom_palette = true;
              color_scheme_path = "${appsDir}/qt-colors.conf";
              style = "Breeze";
            };
          in
          {
            enable = true;
            platformTheme.name = "qtct";
            style.name = "breeze";
            qt5ctSettings = appearance;
            qt6ctSettings = appearance;
          };
      })
    ]
  );
}
