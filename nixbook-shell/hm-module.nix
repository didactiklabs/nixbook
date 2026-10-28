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
  terminalThemeDir = "${config.xdg.stateHome}/quickshell/user/generated/terminal";
  # A new interactive shell in a terminal other than kitty (which includes
  # the theme itself) starts with the generated colours. `$(<file)` is read
  # by the shell itself, without running cat.
  replayTerminalColors = ''
    if [[ $- == *i* && -t 1 && "$TERM" != xterm-kitty && -r "${terminalThemeDir}/sequences.txt" ]]; then
      printf '%s' "$(<"${terminalThemeDir}/sequences.txt")"
    fi
  '';

  # A failed command, for Claude (ai.initiative.terminal / recentContext,
  # src/services/RecentContext.qml): the last one, written to the shell's
  # runtime dir only while the shell made terminal-on there; the command
  # and its exit code, never its output; not Ctrl+C, nor a command starting
  # with a space.
  failedCommandZsh = ''
    if [[ -o interactive ]]; then
      zmodload zsh/datetime 2>/dev/null
      __nixbook_cmd=""
      __nixbook_preexec() { __nixbook_cmd="$1"; }
      __nixbook_precmd() {
        local code=$? cmd=$__nixbook_cmd dir="''${XDG_RUNTIME_DIR:-/run/user/$UID}/nixbook-shell"
        __nixbook_cmd=""
        [[ -n $cmd && $cmd != " "* && -e $dir/terminal-on ]] || return 0
        (( code != 0 && code != 130 && code != 148 )) || return 0
        cmd=''${cmd//$'\n'/ }
        printf '%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$code" "$PWD" "''${cmd//$'\t'/ }" >| "$dir/terminal-failed"
      }
      autoload -Uz add-zsh-hook
      add-zsh-hook preexec __nixbook_preexec
      add-zsh-hook precmd __nixbook_precmd
    fi
  '';
  failedCommandBash = ''
    if [[ $- == *i* ]]; then
      __nixbook_last=""
      __nixbook_precmd() {
        local code=$? dir="''${XDG_RUNTIME_DIR:-/run/user/$UID}/nixbook-shell" n cmd
        [[ -e $dir/terminal-on ]] || return 0
        read -r n cmd < <(HISTTIMEFORMAT= history 1)
        # No new command (an empty line), or one kept out of the history.
        [[ $n != "$__nixbook_last" ]] || return 0
        __nixbook_last=$n
        [[ -n $cmd ]] || return 0
        (( code != 0 && code != 130 && code != 148 )) || return 0
        printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$code" "$PWD" "''${cmd//$'\t'/ }" >| "$dir/terminal-failed"
      }
      PROMPT_COMMAND="__nixbook_precmd''${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    fi
  '';

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
  # Which VPN CLIs the package bundles: those the NixOS system runs, or both
  # under standalone Home Manager (no osConfig to ask).
  vpnClients = {
    withTailscale = os == null || (os.services.tailscale.enable or false);
    withNetbird = os == null || (os.services.netbird.enable or false);
  };
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

  # How the calendars, contacts and to-do list sync, through the shell's
  # accounts (nixbook-accounts): for the config assistant and the AI chat.
  calendarHowTo = {
    calendarConnect = {
      en = "To sync the shell's calendar, contacts and tasks with Google, open the accounts window (the person icon in a calendar or to-do widget, the Contacts or Calendar window, or `nixbook-shell ipc call accounts launch`) and add Google. The first time, it walks you through making your own Google Cloud app (about 5 minutes: a project with the People, Tasks and Calendar APIs, a published app, a Desktop client whose JSON you download); then the browser opens Google's sign-in. iCloud, Fastmail, Nextcloud or another CalDAV/CardDAV server are added in the same window with a user name and an app password. Tokens and passwords are kept in the keyring.";
      fr = "Pour synchroniser le calendrier, les contacts et les tâches du shell avec Google, ouvrez la fenêtre des comptes (l'icône de personne d'un widget calendrier ou tâches, la fenêtre Contacts ou Agenda, ou `nixbook-shell ipc call accounts launch`) et ajoutez Google. La première fois, elle vous guide pour créer votre propre application Google Cloud (environ 5 minutes : un projet avec les API People, Tasks et Calendar, une application publiée, un client Desktop dont vous téléchargez le JSON) ; ensuite le navigateur ouvre la connexion Google. iCloud, Fastmail, Nextcloud ou un autre serveur CalDAV/CardDAV s'ajoutent dans la même fenêtre avec un nom d'utilisateur et un mot de passe d'application. Jetons et mots de passe sont gardés dans le trousseau.";
      de = "Um Kalender, Kontakte und Aufgaben der Shell mit Google zu synchronisieren, öffne das Kontenfenster (das Personensymbol in einem Kalender- oder Aufgaben-Widget, das Kontakte- oder Kalenderfenster, oder `nixbook-shell ipc call accounts launch`) und füge Google hinzu. Beim ersten Mal führt es dich durch das Anlegen einer eigenen Google-Cloud-App (etwa 5 Minuten: ein Projekt mit den People-, Tasks- und Calendar-APIs, eine veröffentlichte App, ein Desktop-Client, dessen JSON du herunterlädst); danach öffnet der Browser die Google-Anmeldung. iCloud, Fastmail, Nextcloud oder ein anderer CalDAV/CardDAV-Server werden im selben Fenster mit Benutzername und App-Passwort hinzugefügt. Tokens und Passwörter liegen im Schlüsselbund.";
      vi = "Để đồng bộ lịch, danh bạ và công việc của shell với Google, mở cửa sổ tài khoản (biểu tượng người trong widget lịch hoặc công việc, cửa sổ Danh bạ hoặc Lịch, hoặc `nixbook-shell ipc call accounts launch`) và thêm Google. Lần đầu, cửa sổ hướng dẫn bạn tạo ứng dụng Google Cloud của riêng mình (khoảng 5 phút: một dự án bật các API People, Tasks và Calendar, một ứng dụng đã xuất bản, một client Desktop có tệp JSON để tải về); sau đó trình duyệt mở trang đăng nhập Google. iCloud, Fastmail, Nextcloud hoặc máy chủ CalDAV/CardDAV khác được thêm trong cùng cửa sổ bằng tên người dùng và mật khẩu ứng dụng. Token và mật khẩu được giữ trong keyring.";
    };
    calendarOtherAccounts = {
      en = "Accounts are added and removed in the accounts window (`nixbook-shell ipc call accounts launch`): Google, iCloud, Fastmail, Nextcloud or any CalDAV/CardDAV server (a user name and an app password; iCloud and Fastmail need an app password made in their settings). Several accounts work together: their calendars, contacts and task lists show side by side. Removing an account takes its data out of the shell, not out of the account. From a terminal: `nixbook-accounts status`, `nixbook-accounts add google`, `nixbook-accounts remove <account>`.";
      fr = "Les comptes s'ajoutent et se retirent dans la fenêtre des comptes (`nixbook-shell ipc call accounts launch`) : Google, iCloud, Fastmail, Nextcloud ou tout serveur CalDAV/CardDAV (un nom d'utilisateur et un mot de passe d'application ; iCloud et Fastmail demandent un mot de passe d'application créé dans leurs réglages). Plusieurs comptes fonctionnent ensemble : leurs calendriers, contacts et listes de tâches s'affichent côte à côte. Retirer un compte enlève ses données du shell, pas du compte. Depuis un terminal : `nixbook-accounts status`, `nixbook-accounts add google`, `nixbook-accounts remove <compte>`.";
      de = "Konten werden im Kontenfenster hinzugefügt und entfernt (`nixbook-shell ipc call accounts launch`): Google, iCloud, Fastmail, Nextcloud oder jeder CalDAV/CardDAV-Server (Benutzername und App-Passwort; iCloud und Fastmail brauchen ein App-Passwort aus ihren Einstellungen). Mehrere Konten arbeiten zusammen: ihre Kalender, Kontakte und Aufgabenlisten erscheinen nebeneinander. Ein Konto zu entfernen nimmt seine Daten aus der Shell, nicht aus dem Konto. Im Terminal: `nixbook-accounts status`, `nixbook-accounts add google`, `nixbook-accounts remove <konto>`.";
      vi = "Tài khoản được thêm và gỡ trong cửa sổ tài khoản (`nixbook-shell ipc call accounts launch`): Google, iCloud, Fastmail, Nextcloud hoặc bất kỳ máy chủ CalDAV/CardDAV nào (tên người dùng và mật khẩu ứng dụng; iCloud và Fastmail cần mật khẩu ứng dụng tạo trong phần cài đặt của chúng). Nhiều tài khoản dùng cùng lúc: lịch, danh bạ và danh sách công việc của chúng hiện cạnh nhau. Gỡ một tài khoản chỉ xóa dữ liệu khỏi shell, không xóa khỏi tài khoản. Từ terminal: `nixbook-accounts status`, `nixbook-accounts add google`, `nixbook-accounts remove <tài-khoản>`.";
    };
    calendarEvents = {
      en = "Calendar events show as dots in the sidebar, desktop and bar clock calendars; the Next Event bar widget and desktop widget (desktop right click > Widgets) show the next ones, with a Join button for meetings. The Calendar window (launcher entry Calendar, a click on the bar clock or a calendar day, `nixbook-shell ipc call calendar launch`) shows the month and each day's events; an event opens in its editor (title, time, calendar, repeat, reminders, place; for a recurring event, this occurrence or all of them), New (Ctrl+N) adds one. Changes go to the event's account at once; the shell syncs every 30 minutes (setting `calendar.refreshMinutes`), and the sync button (the sidebar calendar's header, the Calendar window, F5) syncs now.";
      fr = "Les événements du calendrier apparaissent en points dans les calendriers du panneau latéral, du bureau et de l'horloge de la barre ; le widget de barre et le widget de bureau Prochain événement (clic droit sur le bureau > Widgets) montrent les prochains, avec un bouton Rejoindre pour les réunions. La fenêtre Agenda (entrée Calendar du lanceur, un clic sur l'horloge de la barre ou un jour du calendrier, `nixbook-shell ipc call calendar launch`) montre le mois et les événements de chaque jour ; un événement s'ouvre dans son éditeur (titre, heure, calendrier, répétition, rappels, lieu ; pour un événement récurrent, cette occurrence ou toutes), Nouveau (Ctrl+N) en ajoute un. Les modifications partent tout de suite vers le compte de l'événement ; le shell synchronise toutes les 30 minutes (réglage `calendar.refreshMinutes`), et le bouton de synchronisation (en-tête du calendrier du panneau latéral, fenêtre Agenda, F5) synchronise tout de suite.";
      de = "Kalendertermine erscheinen als Punkte in den Kalendern der Seitenleiste, des Desktops und der Leistenuhr; das Leisten- und das Desktop-Widget Nächster Termin (Rechtsklick auf den Desktop > Widgets) zeigen die nächsten, mit einem Beitreten-Knopf für Besprechungen. Das Kalenderfenster (Starter-Eintrag Calendar, ein Klick auf die Leistenuhr oder einen Kalendertag, `nixbook-shell ipc call calendar launch`) zeigt den Monat und die Termine jedes Tages; ein Termin öffnet sich im Editor (Titel, Zeit, Kalender, Wiederholung, Erinnerungen, Ort; bei wiederkehrenden Terminen dieses Vorkommen oder alle), Neu (Strg+N) legt einen an. Änderungen gehen sofort an das Konto des Termins; die Shell synchronisiert alle 30 Minuten (Einstellung `calendar.refreshMinutes`), und der Synchronisieren-Knopf (Kopf des Seitenleisten-Kalenders, Kalenderfenster, F5) synchronisiert sofort.";
      vi = "Sự kiện lịch hiện thành chấm trong lịch ở thanh bên, màn hình nền và đồng hồ trên thanh; widget Sự kiện tiếp theo trên thanh và trên màn hình nền (chuột phải màn hình nền > Widgets) hiện các sự kiện sắp tới, có nút Tham gia cho cuộc họp. Cửa sổ Lịch (mục Calendar trong trình khởi chạy, bấm vào đồng hồ trên thanh hoặc một ngày trong lịch, `nixbook-shell ipc call calendar launch`) hiện cả tháng và sự kiện từng ngày; một sự kiện mở trong trình chỉnh sửa (tiêu đề, thời gian, lịch, lặp lại, nhắc nhở, địa điểm; với sự kiện lặp lại: lần này hoặc tất cả), Mới (Ctrl+N) thêm sự kiện. Thay đổi được gửi ngay đến tài khoản của sự kiện; shell đồng bộ mỗi 30 phút (cài đặt `calendar.refreshMinutes`), và nút đồng bộ (đầu lịch thanh bên, cửa sổ Lịch, F5) đồng bộ ngay.";
    };
    calendarReminders = {
      en = "Calendar reminders are the shell's own notifications (app \"Calendar\"): one at each reminder time of an event (its own reminders, else its calendar's defaults, as set in Google Calendar or on the server), with Join (a meeting link), Snooze 5 min and Open (the Calendar window on that day); it stays until handled and respects Do Not Disturb. An event's reminders are set in its editor (none, at the start, 5, 10, 30 minutes, 1 hour, 1 day before). A reminder missed while the shell wasn't running shows if at most 10 minutes late.";
      fr = "Les rappels du calendrier sont des notifications du shell lui-même (application « Calendar ») : une à chaque horaire de rappel d'un événement (ses propres rappels, sinon ceux par défaut de son calendrier, tels que réglés dans Google Agenda ou sur le serveur), avec Rejoindre (lien de réunion), Reporter 5 min et Ouvrir (la fenêtre Agenda sur ce jour) ; elle reste jusqu'à ce qu'on la traite et respecte Ne pas déranger. Les rappels d'un événement se règlent dans son éditeur (aucun, au début, 5, 10, 30 minutes, 1 heure, 1 jour avant). Un rappel manqué pendant que le shell ne tournait pas s'affiche s'il a au plus 10 minutes de retard.";
      de = "Kalendererinnerungen sind Benachrichtigungen der Shell selbst (App „Calendar“): eine zu jeder Erinnerungszeit eines Termins (seine eigenen Erinnerungen, sonst die Standardwerte seines Kalenders, wie in Google Kalender oder auf dem Server eingestellt), mit Beitreten (Besprechungslink), 5 Min. schlummern und Öffnen (das Kalenderfenster an diesem Tag); sie bleibt, bis sie erledigt ist, und respektiert Nicht stören. Die Erinnerungen eines Termins stellst du in seinem Editor ein (keine, zu Beginn, 5, 10, 30 Minuten, 1 Stunde, 1 Tag vorher). Eine verpasste Erinnerung, während die Shell nicht lief, erscheint, wenn sie höchstens 10 Minuten zu spät ist.";
      vi = "Nhắc nhở lịch là thông báo của chính shell (ứng dụng \"Calendar\"): một thông báo vào mỗi thời điểm nhắc của sự kiện (nhắc nhở riêng của sự kiện, nếu không thì mặc định của lịch, như đã đặt trong Google Lịch hoặc trên máy chủ), có nút Tham gia (liên kết họp), Báo lại 5 phút và Mở (cửa sổ Lịch vào ngày đó); thông báo ở lại đến khi được xử lý và tôn trọng chế độ Không làm phiền. Nhắc nhở của sự kiện được đặt trong trình chỉnh sửa (không có, lúc bắt đầu, 5, 10, 30 phút, 1 giờ, 1 ngày trước). Nhắc nhở bị lỡ khi shell không chạy vẫn hiện nếu trễ không quá 10 phút.";
    };
    calendarTasks = {
      en = "The to-do list (sidebar, desktop widget, bar clock popup, the launcher's add task) is your accounts' task lists (Google Tasks, the to-do lists of a CalDAV server such as iCloud's Reminders) once an account is added: adding, ticking, moving and deleting a task changes it in its account, new tasks go to the first task list, and finished tasks stay listed for 14 days. Without an account it is a local list.";
      fr = "La liste de tâches (panneau latéral, widget du bureau, popup de l'horloge, l'ajout de tâche du lanceur) est formée des listes de tâches de vos comptes (Google Tasks, les listes de tâches d'un serveur CalDAV comme les Rappels d'iCloud) dès qu'un compte est ajouté : ajouter, cocher, déplacer ou supprimer une tâche la modifie dans son compte, les nouvelles tâches vont dans la première liste, et les tâches terminées restent affichées 14 jours. Sans compte, c'est une liste locale.";
      de = "Die Aufgabenliste (Seitenleiste, Desktop-Widget, Uhr-Popup der Leiste, Aufgabe hinzufügen im Starter) besteht aus den Aufgabenlisten deiner Konten (Google Tasks, die Aufgabenlisten eines CalDAV-Servers wie die Erinnerungen von iCloud), sobald ein Konto hinzugefügt ist: Hinzufügen, Abhaken, Verschieben und Löschen ändert die Aufgabe in ihrem Konto, neue Aufgaben landen in der ersten Aufgabenliste, und erledigte bleiben 14 Tage sichtbar. Ohne Konto ist es eine lokale Liste.";
      vi = "Danh sách công việc (thanh bên, widget màn hình nền, popup đồng hồ trên thanh, thêm công việc từ trình khởi chạy) là các danh sách công việc của tài khoản bạn (Google Tasks, danh sách việc của máy chủ CalDAV như Lời nhắc của iCloud) khi đã thêm tài khoản: thêm, đánh dấu xong, chuyển và xóa công việc sẽ thay đổi trong tài khoản của nó, công việc mới vào danh sách đầu tiên, và công việc đã xong vẫn hiện trong 14 ngày. Khi chưa có tài khoản, đó là danh sách cục bộ.";
    };
    calendarTroubleshoot = {
      en = "If the calendar, contacts or to-do list aren't synced, open the accounts window (`nixbook-shell ipc call accounts launch`): an account that needs signing in again says so (Sign in). From a terminal, `nixbook-accounts status` shows each account and its last sync failure, and `nixbook-accounts calendar sync`, `contacts sync` or `tasks sync` sync now (their error, if any, is printed). The local copies are in ~/.local/state/nixbook-accounts/.";
      fr = "Si le calendrier, les contacts ou la liste de tâches ne se synchronisent pas, ouvrez la fenêtre des comptes (`nixbook-shell ipc call accounts launch`) : un compte à reconnecter le signale (Se connecter). Depuis un terminal, `nixbook-accounts status` montre chaque compte et son dernier échec de synchronisation, et `nixbook-accounts calendar sync`, `contacts sync` ou `tasks sync` synchronisent tout de suite (en affichant l'erreur s'il y en a une). Les copies locales sont dans ~/.local/state/nixbook-accounts/.";
      de = "Wenn Kalender, Kontakte oder Aufgabenliste nicht synchronisiert werden, öffne das Kontenfenster (`nixbook-shell ipc call accounts launch`): ein Konto, das neu angemeldet werden muss, sagt es (Anmelden). Im Terminal zeigt `nixbook-accounts status` jedes Konto und seinen letzten Synchronisierungsfehler, und `nixbook-accounts calendar sync`, `contacts sync` oder `tasks sync` synchronisieren sofort (mit dem Fehler, falls einer auftritt). Die lokalen Kopien liegen in ~/.local/state/nixbook-accounts/.";
      vi = "Nếu lịch, danh bạ hoặc danh sách công việc không đồng bộ, mở cửa sổ tài khoản (`nixbook-shell ipc call accounts launch`): tài khoản cần đăng nhập lại sẽ báo (Đăng nhập). Từ terminal, `nixbook-accounts status` hiện từng tài khoản và lỗi đồng bộ gần nhất, và `nixbook-accounts calendar sync`, `contacts sync` hoặc `tasks sync` đồng bộ ngay (in ra lỗi nếu có). Bản sao cục bộ nằm trong ~/.local/state/nixbook-accounts/.";
    };
  };

  # The shell's own features (themes, notifications, the chat panel): for
  # the config assistant and the AI chat. Keep these up to date with every
  # feature added or changed (AGENTS.md).
  shellHowTo = {
    themeSwitch = {
      en = "To change the shell's theme, open Settings > Appearance > Theme (or right click the desktop > Theme) and pick Material (colours from the wallpaper), Persona (Persona 5 Royal, 3 Reload or 4 Revival) Chiikawa (Chiikawa, Usagi or Momonga), Cyberpunk 2077 (Yellow or Red) or Studio Ghibli (My Neighbor Totoro, Spirited Away or Princess Mononoke), then its variant. Each theme keeps its own variant and options (palette, animations, shapes, fonts); in Nix it is programs.nixbook-shell.settings.appearance.theme and appearance.<theme>.variant.";
      fr = "Pour changer le thème du shell, ouvrez Paramètres > Apparence > Thème (ou clic droit sur le bureau > Thème) et choisissez Material (couleurs du fond d'écran), Persona (Persona 5 Royal, 3 Reload ou 4 Revival) Chiikawa (Chiikawa, Usagi ou Momonga), Cyberpunk 2077 (Yellow ou Red) ou Studio Ghibli (Mon voisin Totoro, Le Voyage de Chihiro ou Princesse Mononoké), puis sa variante. Chaque thème garde sa variante et ses options (palette, animations, formes, polices) ; dans Nix, c'est programs.nixbook-shell.settings.appearance.theme et appearance.<thème>.variant.";
      de = "Um das Design der Shell zu ändern, öffne Einstellungen > Darstellung > Design (oder Rechtsklick auf den Desktop > Design) und wähle Material (Farben aus dem Hintergrundbild), Persona (Persona 5 Royal, 3 Reload oder 4 Revival) Chiikawa (Chiikawa, Usagi oder Momonga), Cyberpunk 2077 (Yellow oder Red) oder Studio Ghibli (Mein Nachbar Totoro, Chihiros Reise ins Zauberland oder Prinzessin Mononoke), dann seine Variante. Jedes Design behält seine Variante und Optionen (Palette, Animationen, Formen, Schriften); in Nix ist es programs.nixbook-shell.settings.appearance.theme und appearance.<design>.variant.";
      vi = "Để đổi giao diện (theme) của shell, mở Cài đặt > Giao diện > Theme (hoặc chuột phải màn hình nền > Theme) và chọn Material (màu theo hình nền), Persona (Persona 5 Royal, 3 Reload hoặc 4 Revival) Chiikawa (Chiikawa, Usagi hoặc Momonga), Cyberpunk 2077 (Yellow hoặc Red) hoặc Studio Ghibli (Hàng xóm của tôi là Totoro, Vùng đất linh hồn hoặc Công chúa Mononoke), rồi chọn biến thể. Mỗi theme giữ biến thể và tùy chọn riêng (bảng màu, hiệu ứng, hình dạng, phông chữ); trong Nix là programs.nixbook-shell.settings.appearance.theme và appearance.<theme>.variant.";
    };
    themeWallpaper = {
      en = "Each theme variant keeps its own desktop, lock screen and login screen wallpapers: switching theme or variant puts them back (the Chiikawa, Cyberpunk and Studio Ghibli variants start with their own desktop wallpaper), and a wallpaper picked while in a variant becomes that variant's. Settings > Appearance > Theme has a table of every variant: click a cell to choose its desktop, lock or login wallpaper, the × to unset it (the lock screen then uses the desktop wallpaper, the login screen the lock screen's). A switch there turns it off (appearance.wallpaperPerTheme).";
      fr = "Chaque variante de thème garde ses fonds d'écran du bureau, de l'écran de verrouillage et de l'écran de connexion : changer de thème ou de variante les remet (les variantes Chiikawa, Cyberpunk et Studio Ghibli commencent avec leur propre fond de bureau), et un fond choisi dans une variante devient le sien. Paramètres > Apparence > Thème contient un tableau de toutes les variantes : cliquez sur une case pour choisir son fond de bureau, de verrouillage ou de connexion, sur le × pour le retirer (le verrouillage reprend alors le fond du bureau, la connexion celui du verrouillage). Un interrupteur le désactive (appearance.wallpaperPerTheme).";
      de = "Jede Designvariante behält ihre eigenen Hintergrundbilder für Desktop, Sperrbildschirm und Anmeldebildschirm: Beim Wechsel von Design oder Variante kommen sie zurück (die Chiikawa-, Cyberpunk- und Studio-Ghibli-Varianten starten mit ihrem eigenen Desktop-Bild), und ein in einer Variante gewähltes Bild wird zu ihrem. Einstellungen > Darstellung > Design enthält eine Tabelle aller Varianten: Klick auf eine Zelle wählt ihr Desktop-, Sperr- oder Anmeldebild, das × entfernt es (der Sperrbildschirm nutzt dann das Desktop-Bild, die Anmeldung das des Sperrbildschirms). Ein Schalter schaltet es ab (appearance.wallpaperPerTheme).";
      vi = "Mỗi biến thể theme giữ hình nền riêng cho màn hình nền, màn hình khóa và màn hình đăng nhập: đổi theme hoặc biến thể sẽ đặt lại chúng (các biến thể Chiikawa, Cyberpunk và Studio Ghibli bắt đầu với hình nền riêng), và hình chọn khi đang ở một biến thể sẽ thành của biến thể đó. Cài đặt > Giao diện > Theme có bảng mọi biến thể: bấm vào ô để chọn hình nền màn hình nền, khóa hoặc đăng nhập, bấm × để bỏ (màn hình khóa khi đó dùng hình nền màn hình nền, màn hình đăng nhập dùng hình của màn hình khóa). Một công tắc để tắt (appearance.wallpaperPerTheme).";
    };
    wallpaperFolders = {
      en = "In the wallpaper selector (Mod+W), click a folder to open it; the back arrow beside the title goes back to the previous folder (also Alt+Left or the mouse's back button), Alt+Right goes forward again and Alt+Up opens the parent folder.";
      fr = "Dans le sélecteur de fonds d'écran (Mod+W), cliquez sur un dossier pour l'ouvrir ; la flèche retour à côté du titre revient au dossier précédent (aussi Alt+Gauche ou le bouton précédent de la souris), Alt+Droite avance de nouveau et Alt+Haut ouvre le dossier parent.";
      de = "In der Hintergrundbild-Auswahl (Mod+W) öffnet ein Klick einen Ordner; der Zurück-Pfeil neben dem Titel geht zum vorherigen Ordner zurück (auch Alt+Links oder die Zurück-Taste der Maus), Alt+Rechts wieder vorwärts und Alt+Hoch öffnet den übergeordneten Ordner.";
      vi = "Trong trình chọn hình nền (Mod+W), bấm vào một thư mục để mở; mũi tên quay lại cạnh tiêu đề trở về thư mục trước (hoặc Alt+Trái, hay nút quay lại của chuột), Alt+Phải đi tiếp và Alt+Lên mở thư mục cha.";
    };
    themeSounds = {
      en = "Each theme has its own notification sounds: Persona 5's chime and cut-in effect in Material and Persona 5 (the Velvet Room's chime and the Evoker in Persona 3 Reload, the Midnight Channel's TV in Persona 4), the characters' chimes and little voices in Chiikawa, a message ping and the Relic malfunctioning in Cyberpunk 2077, the films' own sounds recreated in Studio Ghibli (raindrops on an umbrella and the forest spirit's roar, the bathhouse bell and drum, the kodama's rattle and the wolf's howl). A sound file set in Settings > General > Sounds (notification) or in the cut-in settings replaces the theme's.";
      fr = "Chaque thème a ses propres sons de notification : le carillon et l'effet de cut-in de Persona 5 en Material et Persona 5 (le carillon de la Velvet Room et l'Evoker dans Persona 3 Reload, la télé de la Midnight Channel dans Persona 4), les carillons et petites voix des personnages en Chiikawa, un bip de message et le Relic qui déraille en Cyberpunk 2077, les sons des films recréés en Studio Ghibli (gouttes de pluie sur un parapluie et rugissement de l'esprit de la forêt, cloche et tambour des bains, crécelle des kodamas et hurlement du loup). Un fichier son choisi dans Paramètres > Général > Sons (notification) ou dans les réglages du cut-in remplace celui du thème.";
      de = "Jedes Design hat eigene Benachrichtigungstöne: Persona 5s Glockenton und Cut-in-Effekt in Material und Persona 5 (der Klang des Velvet Room und der Evoker in Persona 3 Reload, der Fernseher des Midnight Channel in Persona 4), die Töne und kleinen Stimmen der Figuren in Chiikawa, ein Nachrichtenton und das gestörte Relic in Cyberpunk 2077, die Klänge der Filme nachgebaut in Studio Ghibli (Regentropfen auf einem Schirm und das Brüllen des Waldgeists, Glocke und Trommel des Badehauses, das Klappern der Kodama und das Heulen des Wolfs). Eine in Einstellungen > Allgemein > Töne (Benachrichtigung) oder in den Cut-in-Einstellungen gesetzte Tondatei ersetzt den des Designs.";
      vi = "Mỗi theme có âm thanh thông báo riêng: tiếng chuông và hiệu ứng cut-in của Persona 5 ở Material và Persona 5 (tiếng chuông Velvet Room và Evoker ở Persona 3 Reload, chiếc TV Midnight Channel ở Persona 4), tiếng chuông và giọng nói nhỏ của các nhân vật ở Chiikawa, tiếng báo tin nhắn và Relic trục trặc ở Cyberpunk 2077, âm thanh của các bộ phim được tái tạo ở Studio Ghibli (giọt mưa trên ô và tiếng gầm của thần rừng, chuông và trống nhà tắm, tiếng lắc lư của kodama và tiếng sói hú). Tệp âm thanh đặt trong Cài đặt > Chung > Âm thanh (thông báo) hoặc trong cài đặt cut-in sẽ thay âm thanh của theme.";
    };
    themeCutIns = {
      en = "Important notifications (critical ones and those matching the cut-in rules in Settings > Bar > Notifications > Cut-ins) take over the screen: a Persona cut-in in the Persona theme, the character popping up with a speech bubble in the Chiikawa theme, an incoming holocall glitching in in the Cyberpunk 2077 theme, a frosted-glass card drifting in on the wind with the film's spirit in the Studio Ghibli theme. Click runs the notification's action, right click or Escape dismisses it; the Preview button shows one. When a desktop agent clicks, types or presses keys on your desktop, a cut-in on screen is dismissed the same way so it doesn't get in its way (it stays in the notification centre).";
      fr = "Les notifications importantes (critiques, ou correspondant aux règles de cut-in dans Paramètres > Barre > Notifications > Cut-ins) prennent l'écran : un cut-in Persona dans le thème Persona, le personnage qui surgit avec une bulle dans le thème Chiikawa, un holoappel entrant qui apparaît en glitch dans le thème Cyberpunk 2077, une carte en verre dépoli portée par le vent avec l'esprit du film dans le thème Studio Ghibli. Un clic lance l'action de la notification, un clic droit ou Échap la ferme ; le bouton Aperçu en montre un. Quand un agent du bureau clique, tape ou appuie sur des touches sur votre bureau, un cut-in affiché est fermé de la même façon pour ne pas le gêner (il reste dans le centre de notifications).";
      de = "Wichtige Benachrichtigungen (kritische und solche, die zu den Cut-in-Regeln unter Einstellungen > Leiste > Benachrichtigungen > Cut-ins passen) übernehmen den Bildschirm: ein Persona-Cut-in im Persona-Design, die Figur mit einer Sprechblase im Chiikawa-Design, ein eingehender Holoanruf mit Glitch im Cyberpunk-2077-Design, eine Milchglas-Karte, die mit dem Geist des Films im Wind hereinschwebt, im Studio-Ghibli-Design. Klick führt die Aktion aus, Rechtsklick oder Escape schließt; der Vorschau-Knopf zeigt eines. Wenn ein Desktop-Agent auf deinem Desktop klickt, tippt oder Tasten drückt, wird ein angezeigtes Cut-in genauso geschlossen, damit es ihm nicht im Weg ist (es bleibt in der Benachrichtigungszentrale).";
      vi = "Thông báo quan trọng (khẩn cấp, hoặc khớp quy tắc cut-in trong Cài đặt > Thanh > Thông báo > Cut-ins) chiếm màn hình: cut-in Persona ở theme Persona, nhân vật hiện lên với bong bóng thoại ở theme Chiikawa, cuộc gọi holo đến kèm hiệu ứng glitch ở theme Cyberpunk 2077, một tấm thẻ kính mờ bay vào theo gió cùng linh hồn của bộ phim ở theme Studio Ghibli. Bấm để chạy hành động của thông báo, chuột phải hoặc Escape để đóng; nút Xem trước hiển thị một ví dụ. Khi một tác nhân màn hình bấm, gõ hoặc nhấn phím trên màn hình của bạn, cut-in đang hiện sẽ được đóng như vậy để không cản đường nó (thông báo vẫn còn trong trung tâm thông báo).";
    };
    notificationDuplicates = {
      en = "Duplicate notifications are filtered (Settings > Bar > Notifications > Duplicates, notifications.deduplicate): your phone's copy (KDE Connect) of a message a desktop app already showed is dropped, the same notification again within the window (30 minutes) replaces the earlier one, and a re-posted chat thread replaces the old one. The history is cleaned by the same rules when the shell starts; run `nixbook-shell ipc call notificationHistory dedupe` to clean it now.";
      fr = "Les notifications en double sont filtrées (Paramètres > Barre > Notifications > Doublons, notifications.deduplicate) : la copie de votre téléphone (KDE Connect) d'un message déjà affiché par une application du bureau est ignorée, la même notification revenue dans la fenêtre (30 minutes) remplace la précédente, et une conversation renvoyée remplace l'ancienne. L'historique est nettoyé selon les mêmes règles au démarrage du shell ; `nixbook-shell ipc call notificationHistory dedupe` le nettoie tout de suite.";
      de = "Doppelte Benachrichtigungen werden gefiltert (Einstellungen > Leiste > Benachrichtigungen > Duplikate, notifications.deduplicate): die Kopie deines Telefons (KDE Connect) einer Nachricht, die eine Desktop-App schon gezeigt hat, wird verworfen, dieselbe Benachrichtigung innerhalb des Zeitfensters (30 Minuten) ersetzt die frühere, und ein erneut gesendeter Chatverlauf ersetzt den alten. Der Verlauf wird beim Start der Shell nach denselben Regeln bereinigt; `nixbook-shell ipc call notificationHistory dedupe` bereinigt ihn sofort.";
      vi = "Thông báo trùng lặp được lọc (Cài đặt > Thanh > Thông báo > Trùng lặp, notifications.deduplicate): bản sao từ điện thoại (KDE Connect) của tin nhắn mà ứng dụng trên máy tính đã hiện sẽ bị bỏ, cùng một thông báo lặp lại trong khoảng thời gian (30 phút) sẽ thay thế thông báo trước, và cuộc trò chuyện được gửi lại sẽ thay thế bản cũ. Lịch sử được dọn theo cùng quy tắc khi shell khởi động; chạy `nixbook-shell ipc call notificationHistory dedupe` để dọn ngay.";
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
      en = "To use Claude in the AI chat (left sidebar), with your own Claude account and no API key: install Claude Code and log in once (run claude in a terminal), then pick Claude with /model claude or the button in Settings > Desktop agents > Claude in the side panel, where you also choose the model (Sonnet is faster) whether it may search the web, and which folders it may read (none by default: it reads none of your files unless you list a folder, or attach a file to a message). It can see and drive the desktop; it runs no commands and edits no files unless you turn on Command line there: it then runs commands as you (never in your terminal windows), only in the folders you allow (a sandbox; turn off Only in the allowed folders for full access), and asks in the chat before anything that changes the system or your files.";
      fr = "Pour utiliser Claude dans le chat IA (panneau de gauche), avec votre propre compte Claude et sans clé API : installez Claude Code et connectez-vous une fois (lancez claude dans un terminal), puis choisissez Claude avec /model claude ou le bouton dans Paramètres > Agents du bureau > Claude dans le panneau latéral, où vous choisissez aussi le modèle (Sonnet est plus rapide) s'il peut chercher sur le web, et les dossiers qu'il peut lire (aucun par défaut : il ne lit aucun de vos fichiers sauf dans un dossier que vous ajoutez, ou un fichier joint à un message). Il peut voir et piloter le bureau ; il ne lance aucune commande et ne modifie aucun fichier, sauf si vous y activez Ligne de commande : il lance alors des commandes en votre nom (jamais dans vos fenêtres de terminal), seulement dans les dossiers autorisés (un bac à sable ; désactivez Seulement dans les dossiers autorisés pour un accès complet), et demande dans le chat avant tout ce qui modifie le système ou vos fichiers.";
      de = "Um Claude im KI-Chat (linke Seitenleiste) mit deinem eigenen Claude-Konto und ohne API-Schlüssel zu nutzen: Installiere Claude Code und melde dich einmal an (claude in einem Terminal starten), dann wähle Claude mit /model claude oder dem Knopf unter Einstellungen > Desktop-Agenten > Claude in der Seitenleiste, wo du auch das Modell (Sonnet ist schneller) die Websuche und die Ordner festlegst, die Claude lesen darf (standardmäßig keine: es liest keine deiner Dateien, außer in Ordnern, die du einträgst, oder eine an eine Nachricht angehängte Datei). Claude kann den Desktop sehen und steuern; es führt keine Befehle aus und bearbeitet keine Dateien, außer du schaltest dort Kommandozeile ein: Dann führt es Befehle als du aus (nie in deinen Terminalfenstern), nur in den erlaubten Ordnern (eine Sandbox; schalte Nur in den erlaubten Ordnern aus für vollen Zugriff), und fragt im Chat, bevor es etwas am System oder an deinen Dateien ändert.";
      vi = "Để dùng Claude trong chat AI (thanh bên trái), với tài khoản Claude của bạn và không cần khóa API: cài Claude Code và đăng nhập một lần (chạy claude trong terminal), rồi chọn Claude bằng /model claude hoặc nút trong Cài đặt > Tác nhân màn hình > Claude trong bảng bên, nơi bạn cũng chọn mô hình (Sonnet nhanh hơn) có cho phép tìm kiếm web không, và những thư mục nó được đọc (mặc định không có: nó không đọc tệp nào của bạn, trừ trong thư mục bạn thêm vào hoặc tệp bạn đính kèm vào tin nhắn). Nó có thể xem và điều khiển màn hình; nó không chạy lệnh hay sửa tệp nào, trừ khi bạn bật Dòng lệnh ở đó: khi đó nó chạy lệnh với quyền của bạn (không bao giờ trong cửa sổ terminal của bạn), chỉ trong các thư mục được phép (một sandbox; tắt Chỉ trong thư mục được phép để có toàn quyền), và hỏi trong chat trước mọi việc thay đổi hệ thống hoặc tệp của bạn.";
    };
    agentDesktopSandbox = {
      en = "The AI agents' own desktop is sandboxed: its apps see none of your files (only the folders you allow in Settings > Desktop agents), none of your windows, clipboard or screen, and can't capture, type or click into your desktop. Two switches in Settings > Desktop agents, both on, take effect when it next opens: Hide the system's services from their apps (no system daemon's socket), and Keep their apps off this computer's local services (their own network: the internet and your local network, but not a dev server on localhost or the printer pages; switch it off if the agent should open those).";
      fr = "Le bureau des agents IA est isolé (bac à sable) : ses applications ne voient aucun de vos fichiers (seulement les dossiers autorisés dans Paramètres > Agents du bureau), ni vos fenêtres, ni votre presse-papiers, ni votre écran, et ne peuvent ni capturer votre bureau ni y taper ou cliquer. Deux interrupteurs dans Paramètres > Agents du bureau, activés par défaut, s'appliquent à sa prochaine ouverture : cacher les services du système à leurs applications (aucun socket des démons du système), et tenir leurs applications à l'écart des services locaux de cet ordinateur (leur propre réseau : internet et votre réseau local, mais pas un serveur de dev sur localhost ni les pages de l'imprimante ; désactivez-le si l'agent doit les ouvrir).";
      de = "Der eigene Desktop der KI-Agenten ist abgeschottet (Sandbox): Seine Apps sehen keine deiner Dateien (nur die in Einstellungen > Desktop-Agenten erlaubten Ordner), keine deiner Fenster, deine Zwischenablage oder deinen Bildschirm, und können deinen Desktop weder aufnehmen noch hineintippen oder -klicken. Zwei Schalter unter Einstellungen > Desktop-Agenten, beide an, gelten ab dem nächsten Öffnen: Die Dienste des Systems vor ihren Apps verbergen (kein Socket der System-Daemons) und ihre Apps von den lokalen Diensten dieses Computers fernhalten (ein eigenes Netz: Internet und dein lokales Netz, aber kein Dev-Server auf localhost und keine Druckerseiten; schalte es aus, wenn der Agent diese öffnen soll).";
      vi = "Màn hình riêng của các tác nhân AI được cách ly (sandbox): ứng dụng trên đó không thấy tệp nào của bạn (chỉ các thư mục bạn cho phép trong Cài đặt > Tác nhân màn hình), không thấy cửa sổ, bộ nhớ tạm hay màn hình của bạn, và không thể chụp, gõ hay bấm vào màn hình của bạn. Hai công tắc trong Cài đặt > Tác nhân màn hình, mặc định bật, có hiệu lực từ lần mở tiếp theo: ẩn các dịch vụ hệ thống khỏi ứng dụng của chúng (không socket nào của các daemon hệ thống), và giữ ứng dụng của chúng tránh xa các dịch vụ cục bộ của máy này (mạng riêng: internet và mạng nội bộ của bạn, nhưng không có máy chủ dev trên localhost hay trang máy in; tắt đi nếu tác nhân cần mở chúng).";
    };
    desktopMemory = {
      en = "AI agents keep a memory of this desktop so repeated tasks go faster: notes they write (app shortcuts, where things are), recipes (steps that worked, run again in one call; a recipe that worked on three days becomes a macro), app names they learned and what gets used. A note gets stronger when the tasks it was given for go well and weaker when they fail; notes unused for months move to an archive, where agents find them again when needed; once a week a small model merges notes on the same app. Every agent receives the part about its task when it connects, as hints. Review, delete or clear it in Settings > Desktop agents > Desktop memory, or with nixbook-desktop-mcp memory show.";
      fr = "Les agents IA gardent une mémoire de ce bureau pour aller plus vite sur les tâches répétées : des notes qu'ils écrivent (raccourcis d'applications, où sont les choses), des recettes (les étapes qui ont marché, relancées en un appel ; une recette qui a marché trois jours devient une macro), les noms d'applications appris et ce qui est utilisé. Une note se renforce quand les tâches pour lesquelles elle a servi réussissent et s'affaiblit quand elles échouent ; les notes inutilisées depuis des mois passent dans une archive, où les agents les retrouvent au besoin ; une fois par semaine un petit modèle fusionne les notes sur la même application. Chaque agent reçoit en se connectant la partie qui concerne sa tâche, comme des indications. Consultez-la, supprimez ou effacez-la dans Paramètres > Agents du bureau > Mémoire du bureau, ou avec nixbook-desktop-mcp memory show.";
      de = "KI-Agenten führen ein Gedächtnis dieses Desktops, damit wiederholte Aufgaben schneller gehen: Notizen, die sie schreiben (App-Tastenkürzel, wo Dinge sind), Rezepte (Schritte, die funktioniert haben, mit einem Aufruf wiederholt; ein Rezept, das an drei Tagen funktioniert hat, wird ein Makro), gelernte App-Namen und was genutzt wird. Eine Notiz wird stärker, wenn die Aufgaben, für die sie gegeben wurde, gelingen, und schwächer, wenn sie scheitern; monatelang ungenutzte Notizen wandern in ein Archiv, wo Agenten sie bei Bedarf wiederfinden; einmal pro Woche führt ein kleines Modell Notizen zur selben App zusammen. Jeder Agent bekommt beim Verbinden den Teil zu seiner Aufgabe als Hinweise. Ansehen, löschen oder leeren unter Einstellungen > Desktop-Agenten > Desktop-Gedächtnis oder mit nixbook-desktop-mcp memory show.";
      vi = "Các tác nhân AI giữ một bộ nhớ về màn hình này để các việc lặp lại nhanh hơn: ghi chú chúng viết (phím tắt ứng dụng, vị trí các thứ), công thức (các bước đã chạy được, chạy lại trong một lệnh; công thức chạy được trong ba ngày thành macro), tên ứng dụng đã học và những gì được dùng. Ghi chú mạnh lên khi các việc nó được dùng cho thành công và yếu đi khi thất bại; ghi chú không dùng nhiều tháng chuyển vào kho lưu trữ, nơi tác nhân tìm lại khi cần; mỗi tuần một mô hình nhỏ gộp các ghi chú về cùng một ứng dụng. Mỗi tác nhân nhận phần liên quan đến việc của nó khi kết nối, dưới dạng gợi ý. Xem, xóa hoặc dọn sạch trong Cài đặt > Tác nhân màn hình > Bộ nhớ màn hình, hoặc bằng nixbook-desktop-mcp memory show.";
    };
    agentReminders = {
      en = "Ask Claude (or any agent) \"remind me when I open Gmail to label the invoices\", \"next time I open Discord, remind me…\" or \"remind me at 18:00…\": the reminder comes as a notification when that app or window is focused, or at that time, once (or every day if you ask). See or delete reminders in Settings > Desktop agents > Desktop memory > Reminders.";
      fr = "Demandez à Claude (ou à un agent) « rappelle-moi quand j'ouvre Gmail de trier les factures », « la prochaine fois que j'ouvre Discord, rappelle-moi… » ou « rappelle-moi à 18h00… » : le rappel arrive en notification quand cette application ou fenêtre a le focus, ou à cette heure, une fois (ou chaque jour si vous le demandez). Voyez ou supprimez les rappels dans Paramètres > Agents du bureau > Mémoire du bureau > Rappels.";
      de = "Bitte Claude (oder einen Agenten): „erinnere mich, wenn ich Gmail öffne, die Rechnungen zu sortieren“, „wenn ich Discord das nächste Mal öffne, erinnere mich…“ oder „erinnere mich um 18:00…“: Die Erinnerung kommt als Benachrichtigung, wenn diese App oder dieses Fenster den Fokus hat, oder zu dieser Zeit, einmal (oder täglich, wenn gewünscht). Erinnerungen ansehen oder löschen unter Einstellungen > Desktop-Agenten > Desktop-Gedächtnis > Erinnerungen.";
      vi = "Hãy nhờ Claude (hoặc một tác nhân) \"nhắc tôi khi mở Gmail để phân loại hóa đơn\", \"lần tới tôi mở Discord, nhắc tôi…\" hoặc \"nhắc tôi lúc 18:00…\": lời nhắc hiện thành thông báo khi ứng dụng hoặc cửa sổ đó được chọn, hoặc vào giờ đó, một lần (hoặc mỗi ngày nếu bạn muốn). Xem hoặc xóa lời nhắc trong Cài đặt > Tác nhân màn hình > Bộ nhớ màn hình > Nhắc nhở.";
    };
    agentInitiative = {
      en = "Turn on Settings > Desktop agents > Talk to me on its own and Claude speaks first when it can help: when you come back (your day, a plan coming up or just past, your usual setup), when a recipe it knows broke, when it learned something, and with Read my notifications also on, about notifications (advice or a suggestion). Time-critical things come as its own speech bubble on the left under the bar, in your theme's look (answer right in it and Claude answers there; paste an image with Ctrl+V, drop a file on the reply box or click its clip to send it along; the expand button moves the talk to the side panel; Not now, Don't tell me this; at most 8 a day, none at night or in a meeting); the rest waits as a bubble beside the robot in the bar, with a count of how many you haven't read (it goes down as you read, answer or dismiss them): click it to bring it back, right-click for not now. Don't tell me this silences only that: for a notification, the notifications like it (the same app and title, numbers aside), never the whole app; Settings > Desktop agents lists each one with Tell me again, and a button undoes them all. Now and then, at random and at most four times a day, it also says a light word in the bar: a break after a long stretch, the music on repeat, a tip for the app you're in, something it can now do in one step, a plan coming up, a question about something you care about. With Be curious also on, it watches what you do (the app and window title in front; never password managers or private windows), learns it once a day through the small model, saves it to what it knows about you and tells you what it learned in its bubble; reply to correct it. It asks only what it can't tell.";
      fr = "Activez Paramètres > Agents du bureau > Me parler de lui-même et Claude prend la parole quand il peut aider : à votre retour (votre journée, un projet proche ou passé, votre installation habituelle), quand une recette qu'il connaît est cassée, quand il a appris quelque chose, et avec Lire mes notifications activé, à propos des notifications (un conseil ou une suggestion). L'urgent arrive dans sa propre bulle, à gauche sous la barre, aux couleurs de votre thème (répondez directement dedans et Claude y répond ; collez une image avec Ctrl+V, déposez un fichier sur la zone de réponse ou cliquez son trombone pour le joindre ; le bouton agrandir passe la conversation au panneau latéral ; Pas maintenant, Ne plus me dire ça ; 8 par jour au plus, rien la nuit ni en réunion) ; le reste attend sous forme de bulle à côté du robot dans la barre, avec le nombre de messages non lus (il baisse quand vous les lisez, y répondez ou les écartez) : cliquez pour la rouvrir, clic droit pour plus tard. Ne me dis plus ça ne fait taire que cela : pour une notification, celles qui lui ressemblent (même application et même titre, chiffres à part), jamais toute l'application ; Paramètres > Agents du bureau les liste une à une avec Redis-le-moi, et un bouton les annule toutes. De temps en temps, au hasard et quatre fois par jour au plus, il glisse aussi un mot dans la barre : une pause après une longue session, la musique en boucle, une astuce pour l'application ouverte, ce qu'il sait désormais faire en une étape, un projet qui approche, une question sur ce qui vous tient à cœur. Avec Être curieux activé aussi, il observe ce que vous faites (l'application et le titre de la fenêtre au premier plan ; jamais les gestionnaires de mots de passe ni les fenêtres privées), l'apprend une fois par jour via le petit modèle, l'enregistre dans ce qu'il sait de vous et vous dit ce qu'il a appris dans sa bulle ; répondez pour le corriger. Il ne demande que ce qu'il ne peut pas deviner.";
      de = "Schalte Einstellungen > Desktop-Agenten > Von sich aus mit mir reden ein, und Claude spricht zuerst, wenn es helfen kann: wenn du zurückkommst (dein Tag, ein Plan bald oder gerade vorbei, dein übliches Setup), wenn ein Rezept, das es kennt, kaputt ist, wenn es etwas gelernt hat, und mit Meine Benachrichtigungen lesen auch zu Benachrichtigungen (ein Rat oder ein Vorschlag). Dringendes kommt als eigene Sprechblase links unter der Leiste, im Stil deines Themes (antworte direkt darin, und Claude antwortet dort; füge ein Bild mit Strg+V ein, zieh eine Datei auf das Antwortfeld oder klicke seine Büroklammer, um sie mitzuschicken; der Vergrößern-Knopf verlegt das Gespräch ins Seitenpanel; Nicht jetzt, Sag mir das nicht mehr; höchstens 8 am Tag, nachts und in Besprechungen nichts); der Rest wartet als Sprechblase neben dem Roboter in der Leiste, mit der Zahl des noch Ungelesenen (sie sinkt, wenn du liest, antwortest oder wegklickst): Klick holt sie zurück, Rechtsklick für später. Sag mir das nicht mehr bringt nur das zum Schweigen: bei einer Benachrichtigung die ähnlichen (gleiche App und gleicher Titel, Zahlen außen vor), nie die ganze App; Einstellungen > Desktop-Agenten listet jede einzeln mit Sag es mir wieder, und ein Knopf hebt alle auf. Ab und zu, zufällig und höchstens viermal am Tag, sagt es auch ein lockeres Wort in der Leiste: eine Pause nach langer Arbeit, die Musik in Dauerschleife, ein Tipp für die offene App, was es jetzt in einem Schritt kann, ein Plan, der näher rückt, eine Frage zu etwas, das dir wichtig ist. Mit Neugierig sein beobachtet es außerdem, was du tust (App und Fenstertitel im Vordergrund; nie Passwortmanager oder private Fenster), lernt es einmal am Tag über das kleine Modell, speichert es in dem, was es über dich weiß, und sagt dir in seiner Sprechblase, was es gelernt hat; antworte, um es zu korrigieren. Es fragt nur, was es nicht erraten kann.";
      vi = "Bật Cài đặt > Tác nhân màn hình > Tự nói chuyện với tôi và Claude sẽ chủ động lên tiếng khi có thể giúp: khi bạn quay lại (ngày của bạn, một kế hoạch sắp tới hoặc vừa qua, thiết lập quen thuộc), khi một công thức nó biết bị hỏng, khi nó học được điều gì, và khi bật thêm Đọc thông báo của tôi, về các thông báo (lời khuyên hoặc gợi ý). Việc gấp hiện trong bong bóng riêng ở bên trái dưới thanh, theo phong cách giao diện của bạn (trả lời ngay trong đó và Claude trả lời tại đó; dán ảnh bằng Ctrl+V, kéo thả tệp vào ô trả lời hoặc bấm biểu tượng ghim để gửi kèm; nút mở rộng chuyển cuộc trò chuyện sang bảng bên; Để sau, Đừng nói điều này nữa; tối đa 8 lần một ngày, không vào ban đêm hay khi họp); phần còn lại chờ dưới dạng bong bóng cạnh robot trên thanh, kèm số tin chưa đọc (giảm dần khi bạn đọc, trả lời hoặc bỏ qua): bấm để mở lại, chuột phải để để sau. Đừng nói điều này nữa chỉ tắt đúng điều đó: với thông báo, là các thông báo giống nó (cùng ứng dụng và tiêu đề, bỏ qua con số), không bao giờ cả ứng dụng; Cài đặt > Tác nhân màn hình liệt kê từng mục với Nói lại cho tôi, và một nút để bỏ tất cả. Thỉnh thoảng, ngẫu nhiên và tối đa bốn lần một ngày, nó cũng nói một câu nhẹ nhàng trên thanh: nghỉ một chút sau thời gian dài, bản nhạc nghe đi nghe lại, mẹo cho ứng dụng đang mở, việc nó giờ làm được trong một bước, kế hoạch sắp tới, một câu hỏi về điều bạn quan tâm. Khi bật thêm Tò mò, nó quan sát bạn làm gì (ứng dụng và tiêu đề cửa sổ đang mở; không bao giờ trình quản lý mật khẩu hay cửa sổ riêng tư), mỗi ngày một lần học điều đó qua mô hình nhỏ, lưu vào những gì nó biết về bạn và cho bạn biết nó đã học được gì trong bong bóng; trả lời để sửa lại. Nó chỉ hỏi những gì nó không tự đoán được.";
    };
    agentRoutines = {
      en = "Ask Claude for a routine: \"whenever the music ends, play something I like\", \"when my headphones connect, resume the music\", \"when a PDF lands in Downloads, open it\", \"every weekday at 9:00, restore my work layout\". It does it on its own when that happens (music, apps, window titles, notifications, coming back, the lock, a time, battery and power, Wi-Fi, VPN, audio output, monitors, Downloads, calendar events). It never fights you: music you stop stays stopped, and a routine you undo twice turns itself off. See, switch off or delete them in Settings > Desktop agents > Routines. With Learn routines from my habits (Suggest or On its own) it also finds routines by itself from what you usually do (it needs usage habits on), and asks first or just starts doing them. A routine Claude adds stays off until you answer Yes, do it to its bubble, which says what it would do. It also reacts to no music for a while, an app in front, the first time at the computer each day, a long sitting, fullscreen, Do Not Disturb, the battery charged, Bluetooth, your phone, a USB drive, a full disk, rain and screenshots; and once a day it may suggest a routine that would help you, from what it knows about you.";
      fr = "Demandez une routine à Claude : « quand la musique s'arrête, mets quelque chose que j'aime », « quand mon casque se connecte, reprends la musique », « quand un PDF arrive dans Téléchargements, ouvre-le », « en semaine à 9h, remets ma disposition de travail ». Il le fait tout seul quand cela arrive (musique, applications, titres de fenêtres, notifications, retour, verrouillage, une heure, batterie et alimentation, Wi-Fi, VPN, sortie audio, écrans, Téléchargements, événements du calendrier). Il ne vous contredit jamais : la musique que vous arrêtez reste arrêtée, et une routine annulée deux fois se désactive. Voyez, désactivez ou supprimez-les dans Paramètres > Agents du bureau > Routines. Avec Apprendre des routines de mes habitudes (Suggérer ou Tout seul), il en trouve aussi lui-même à partir de ce que vous faites d'habitude (il faut les habitudes d'utilisation activées), et demande d'abord ou s'y met directement. Une routine ajoutée par Claude reste désactivée tant que vous n'avez pas répondu Oui, fais-le à sa bulle, qui dit ce qu'elle ferait. Il réagit aussi à l'absence de musique un moment, à une application au premier plan, à la première fois devant l'ordinateur de la journée, à une longue session, au plein écran, au mode Ne pas déranger, à la batterie chargée, au Bluetooth, à votre téléphone, à une clé USB, à un disque plein, à la pluie et aux captures d'écran ; et une fois par jour il peut vous suggérer une routine utile, d'après ce qu'il sait de vous.";
      de = "Bitte Claude um eine Routine: „wenn die Musik endet, spiel etwas, das ich mag“, „wenn sich mein Kopfhörer verbindet, setz die Musik fort“, „wenn ein PDF in Downloads landet, öffne es“, „werktags um 9:00 stell mein Arbeitslayout her“. Es macht das von selbst, wenn es passiert (Musik, Apps, Fenstertitel, Benachrichtigungen, Zurückkommen, Sperre, eine Uhrzeit, Akku und Strom, WLAN, VPN, Audioausgang, Monitore, Downloads, Kalendertermine). Es arbeitet nie gegen dich: Musik, die du stoppst, bleibt aus, und eine Routine, die du zweimal rückgängig machst, schaltet sich ab. Ansehen, abschalten oder löschen unter Einstellungen > Desktop-Agenten > Routinen. Mit Routinen aus meinen Gewohnheiten lernen (Vorschlagen oder Von selbst) findet es auch selbst Routinen aus dem, was du gewöhnlich tust (Nutzungsgewohnheiten müssen an sein), und fragt zuerst oder legt einfach los. Eine Routine, die Claude hinzufügt, bleibt aus, bis du in ihrer Sprechblase Ja, mach es antwortest; sie sagt, was sie tun würde. Es reagiert auch auf eine Weile ohne Musik, eine App im Vordergrund, das erste Mal am Rechner am Tag, lange Sitzungen, Vollbild, Nicht stören, geladenen Akku, Bluetooth, dein Handy, einen USB-Stick, eine volle Festplatte, Regen und Screenshots; und einmal am Tag kann es dir eine hilfreiche Routine vorschlagen, nach dem, was es über dich weiß.";
      vi = "Hãy nhờ Claude tạo một thói quen tự động: \"khi nhạc hết, phát bài tôi thích\", \"khi tai nghe kết nối, phát tiếp nhạc\", \"khi có PDF trong Tải xuống, mở nó\", \"các ngày trong tuần lúc 9:00, khôi phục bố cục làm việc\". Nó tự làm khi điều đó xảy ra (nhạc, ứng dụng, tiêu đề cửa sổ, thông báo, khi bạn quay lại, khóa màn hình, một giờ cố định, pin và nguồn, Wi-Fi, VPN, đầu ra âm thanh, màn hình, Tải xuống, sự kiện lịch). Nó không bao giờ làm ngược ý bạn: nhạc bạn tắt sẽ không bị bật lại, và thói quen bạn hoàn tác hai lần sẽ tự tắt. Xem, tắt hoặc xóa trong Cài đặt > Tác nhân màn hình > Thói quen tự động. Với Học thói quen từ thói quen sử dụng của tôi (Gợi ý hoặc Tự làm), nó còn tự tìm thói quen từ những gì bạn thường làm (cần bật thói quen sử dụng), rồi hỏi trước hoặc tự bắt đầu làm. Thói quen do Claude thêm sẽ tắt cho đến khi bạn trả lời Có, làm đi trong bong bóng của nó, nơi ghi rõ nó sẽ làm gì. Nó cũng phản ứng khi không có nhạc một lúc, khi một ứng dụng ở phía trước, lần đầu ngồi vào máy trong ngày, ngồi lâu, toàn màn hình, chế độ Không làm phiền, pin đã sạc, Bluetooth, điện thoại của bạn, ổ USB, ổ đĩa đầy, trời mưa và ảnh chụp màn hình; và mỗi ngày một lần nó có thể gợi ý một thói quen hữu ích, dựa trên những gì nó biết về bạn.";
    };
    aiOff = {
      en = "To turn every AI feature off at once, switch off Settings > Desktop agents > AI features (the same as Settings > Panels > AI: No). Then nothing calls a model and no agent acts: no chat in the side panel, Claude never speaks on its own (Mod+C included), no routine runs, no memory pass, no fix, the equalizer agent rests, and every agent's desktop tools are refused. What agents remember stays, and each feature keeps its own switch for when you turn AI back on. AI: Local keeps only what never goes to an online model like Claude.";
      fr = "Pour désactiver toutes les fonctions d'IA d'un coup, désactivez Paramètres > Agents du bureau > Fonctions d'IA (comme Paramètres > Panneaux > IA : Non). Alors rien n'appelle de modèle et aucun agent n'agit : pas de chat dans le panneau latéral, Claude ne parle jamais de lui-même (Mod+C compris), aucune routine ne tourne, pas de passe de mémoire, pas de correction, l'agent de l'égaliseur se repose, et les outils du bureau sont refusés à tout agent. Ce que les agents ont retenu reste, et chaque fonction garde son propre interrupteur pour quand vous réactivez l'IA. IA : Local ne garde que ce qui ne passe jamais par un modèle en ligne comme Claude.";
      de = "Um alle KI-Funktionen auf einmal auszuschalten, schalte Einstellungen > Desktop-Agenten > KI-Funktionen aus (wie Einstellungen > Panels > KI: Nein). Dann ruft nichts mehr ein Modell auf und kein Agent handelt: kein Chat in der Seitenleiste, Claude spricht nie von sich aus (Mod+C eingeschlossen), keine Routine läuft, kein Gedächtnisdurchlauf, keine Korrektur, der Equalizer-Agent ruht, und die Desktop-Werkzeuge werden jedem Agenten verweigert. Was die Agenten sich gemerkt haben, bleibt, und jede Funktion behält ihren eigenen Schalter für später. KI: Lokal behält nur, was nie an ein Online-Modell wie Claude geht.";
      vi = "Để tắt mọi tính năng AI cùng lúc, tắt Cài đặt > Tác nhân màn hình > Tính năng AI (giống Cài đặt > Bảng > AI: Không). Khi đó không gì gọi mô hình và không tác nhân nào hành động: không có trò chuyện ở bảng bên, Claude không tự nói (kể cả Mod+C), không chạy thói quen tự động, không có lượt ghi nhớ, không có bản sửa, tác nhân bộ cân bằng âm nghỉ, và công cụ màn hình bị từ chối với mọi tác nhân. Những gì tác nhân đã nhớ vẫn còn, và mỗi tính năng giữ công tắc riêng cho lúc bạn bật lại AI. AI: Cục bộ chỉ giữ những gì không bao giờ gửi tới mô hình trực tuyến như Claude.";
    };
    agentFixes = {
      en = "Turn on Settings > Desktop agents > Fixes it makes itself > Make fixes on its own and Claude fixes nixbook itself: fixes and polish only (a bug, a rough edge, wording); a new feature, or a fix it finds too big, goes to Features it builds (ask how features are built). Tell an agent something is broken (\"report this\") or type it in that section; it also picks up the errors the shell prints, the desktop tools' crashes, failed services and errors in the logs of what nixbook defines, a failed update, CI failing on main and crashes of nixbook's programs (what isn't nixbook's, like another app's crash or the kernel, is only listed, never sent to Claude unless you press Fix now). Each fix is made in a clone of the repository by a session that can only edit files there, checked (its size, the tests, the shell started headless), committed with a changelog entry and opened as a pull request. Once CI passes you get a notification with Merge, Look and Drop (also in Settings). Nothing reaches main without you, unless you let fixes merge on their own once CI passes (docs-only ones, or every one: a fix touching what agents may do always waits for you). What a merged fix breaks (main's checks, the updated shell) is never reverted: it is queued as a fix of its own. One it can't do (a place off limits, credentials, hardware, or its change failing twice) is dropped with why and what would make it doable: you get a notification with Retry, As a feature and Dismiss, and it waits in the section's Dropped list with the same buttons, never tried again unless you press Retry. At most 2 a day on its own by default: set Fixes a day on its own in that section (0: no limit; Most a fix may spend still caps each one); Fix now starts one at once; pressed while another is being made (Queue then), or asked of an agent, it waits in a queue shared with the features instead: Queued, #N, with Earlier, Later and Unqueue buttons, each starting on its own once the one before it is done. It reaches GitHub only with its own token, set in that section (a fine-grained token for the repository, Contents and Pull requests), never your gh login; Claude never sees it. Only machines whose Nix configuration enables it have it.";
      fr = "Activez Paramètres > Agents du bureau > Corrections qu'il fait lui-même > Faire des corrections de lui-même et Claude corrige nixbook lui-même : corrections et finitions uniquement (un bogue, un défaut, une formulation) ; une nouvelle fonctionnalité, ou une correction trouvée trop grosse, va dans Fonctionnalités qu'il construit. Dites à un agent que quelque chose est cassé (« signale ça ») ou écrivez-le dans cette section ; il relève aussi les erreurs que le shell affiche, les plantages des outils du bureau, les services en échec et les erreurs dans les journaux de ce que nixbook définit, une mise à jour échouée, la CI en échec sur main et les plantages des programmes de nixbook (ce qui n'est pas à nixbook, comme le plantage d'une autre application ou le noyau, est seulement listé, jamais envoyé à Claude sauf si vous appuyez sur Corriger maintenant). Chaque correction est faite dans un clone du dépôt par une session qui ne peut modifier que les fichiers de ce clone, vérifiée (sa taille, les tests, le shell démarré sans écran), commitée avec une entrée de journal des modifications et ouverte en pull request. Quand la CI passe, une notification propose Fusionner, Voir et Abandonner (aussi dans les Paramètres). Rien n'arrive sur main sans vous, sauf si vous laissez les corrections fusionner seules une fois la CI passée (celles de documentation seulement, ou toutes : une correction touchant ce que les agents peuvent faire attend toujours votre accord). Ce qu'une correction fusionnée casse (les vérifications de main, le shell mis à jour) n'est jamais annulé : c'est mis en file comme une correction à part. Celle qu'il ne peut pas faire (un endroit interdit, des identifiants, du matériel, ou sa modification refusée deux fois) est abandonnée avec la raison et ce qui la rendrait faisable : une notification propose Réessayer, En fonctionnalité et Ignorer, et elle attend dans la liste Abandonnées de la section avec les mêmes boutons, jamais réessayée sauf si vous appuyez sur Réessayer. Au plus 2 par jour de lui-même par défaut : réglez Corrections par jour de lui-même dans cette section (0 : sans limite ; Dépense maximale par correction plafonne toujours chacune) ; Corriger maintenant en lance une tout de suite ; pendant qu'une autre est en cours (le bouton devient Mettre en file), ou demandée à un agent, elle attend dans une file partagée avec les fonctionnalités : En file, n° N, avec les boutons Plus tôt, Plus tard et Retirer de la file, chacune démarrant seule quand la précédente est finie. Il n'accède à GitHub qu'avec son propre jeton, défini dans cette section (un jeton à granularité fine pour le dépôt, Contents et Pull requests), jamais votre connexion gh ; Claude ne le voit jamais. Seules les machines dont la configuration Nix l'active l'ont.";
      de = "Schalte Einstellungen > Desktop-Agenten > Korrekturen, die es selbst macht > Selbst Korrekturen machen ein, und Claude korrigiert nixbook selbst: nur Fehlerbehebungen und Feinschliff (ein Fehler, eine Unebenheit, eine Formulierung); eine neue Funktion, oder eine Korrektur, die sich als zu groß erweist, kommt zu Funktionen, die es baut. Sag einem Agenten, dass etwas kaputt ist („melde das“), oder schreib es in diesen Abschnitt; es greift auch die Fehler auf, die die Shell ausgibt, Abstürze der Desktop-Werkzeuge, fehlgeschlagene Dienste und Fehler in den Logs dessen, was nixbook definiert, ein fehlgeschlagenes Update, rote CI auf main und Abstürze von nixbooks Programmen (was nicht zu nixbook gehört, etwa der Absturz einer anderen App oder der Kernel, wird nur aufgelistet, nie an Claude geschickt, außer du drückst Jetzt korrigieren). Jede Korrektur entsteht in einem Klon des Repositorys durch eine Sitzung, die nur dort Dateien bearbeiten kann, wird geprüft (ihre Größe, die Tests, die Shell ohne Bildschirm gestartet), mit einem Changelog-Eintrag committet und als Pull Request geöffnet. Sobald die CI durchläuft, bekommst du eine Benachrichtigung mit Zusammenführen, Ansehen und Verwerfen (auch in den Einstellungen). Nichts landet ohne dich auf main, außer du lässt Korrekturen nach bestandener CI von selbst zusammenführen (nur Doku-Korrekturen oder alle: eine Korrektur an dem, was Agenten dürfen, wartet immer auf dich). Was eine zusammengeführte Korrektur kaputt macht (die Prüfungen von main, die aktualisierte Shell), wird nie zurückgenommen: es kommt als eigene Korrektur in die Warteschlange. Eine, die es nicht schafft (ein gesperrter Ort, Zugangsdaten, Hardware, oder ihre Änderung zweimal abgelehnt), wird mit Grund und dem, was sie machbar machen würde, aufgegeben: eine Benachrichtigung bietet Erneut versuchen, Als Funktion und Verwerfen, und sie wartet in der Liste Aufgegeben des Abschnitts mit denselben Knöpfen, nie wieder versucht, außer du drückst Erneut versuchen. Standardmäßig höchstens 2 am Tag von selbst: stell Korrekturen pro Tag von selbst in diesem Abschnitt ein (0: keine Grenze; Höchstausgabe pro Korrektur begrenzt weiter jede); Jetzt korrigieren startet eine sofort; während eine andere läuft (der Knopf heißt dann Einreihen), oder von einem Agenten verlangt, wartet sie in einer mit den Funktionen geteilten Warteschlange: In der Warteschlange, Nr. N, mit den Knöpfen Früher, Später und Aus der Warteschlange, jede startet von selbst, sobald die vorige fertig ist. Es greift nur mit seinem eigenen Token auf GitHub zu, das in diesem Abschnitt gesetzt wird (ein Fine-grained-Token für das Repository, Contents und Pull requests), nie mit deiner gh-Anmeldung; Claude sieht es nie. Nur Rechner, deren Nix-Konfiguration es aktiviert, haben es.";
      vi = "Bật Cài đặt > Tác nhân màn hình > Tự sửa lỗi > Tự sửa lỗi và Claude sẽ tự sửa nixbook: chỉ sửa lỗi và chỉnh chu (một lỗi, một chỗ chưa mượt, câu chữ); một tính năng mới, hoặc một bản sửa quá lớn, sẽ chuyển sang Tính năng nó xây dựng. Hãy nói với một tác nhân rằng có gì đó bị hỏng (\"báo lỗi này\") hoặc gõ vào mục đó; nó cũng ghi nhận các lỗi mà shell in ra, các lần công cụ màn hình bị sập, các dịch vụ bị lỗi và lỗi trong nhật ký của những gì nixbook định nghĩa, một lần cập nhật thất bại, CI lỗi trên main và các lần chương trình của nixbook bị sập (những gì không thuộc nixbook, như một ứng dụng khác bị sập hay nhân hệ điều hành, chỉ được liệt kê, không bao giờ gửi cho Claude trừ khi bạn bấm Sửa ngay). Mỗi bản sửa được làm trong một bản sao của kho mã bởi một phiên chỉ được sửa tệp trong đó, được kiểm tra (kích thước, các bài kiểm thử, shell khởi động không màn hình), commit kèm mục nhật ký thay đổi và mở thành pull request. Khi CI qua, bạn nhận thông báo với Hợp nhất, Xem và Bỏ (cũng có trong Cài đặt). Không gì vào main mà không có bạn, trừ khi bạn cho phép các bản sửa tự hợp nhất khi CI qua (chỉ bản sửa tài liệu, hoặc tất cả: bản sửa đụng tới quyền của tác nhân luôn chờ bạn). Những gì một bản sửa đã gộp làm hỏng (kiểm tra của main, shell sau khi cập nhật) không bao giờ bị hoàn tác: nó được xếp hàng thành một bản sửa riêng. Bản sửa nó không làm được (một chỗ bị cấm, thông tin đăng nhập, phần cứng, hoặc thay đổi bị từ chối hai lần) bị bỏ kèm lý do và điều gì sẽ giúp làm được: bạn nhận thông báo với Thử lại, Thành tính năng và Bỏ qua, và nó chờ trong danh sách Đã bỏ của mục đó với cùng các nút, không bao giờ thử lại trừ khi bạn bấm Thử lại. Mặc định tối đa 2 lần mỗi ngày tự động: đặt Số bản sửa mỗi ngày trong mục đó (0: không giới hạn; Chi tối đa mỗi bản sửa vẫn giới hạn từng bản); Sửa ngay bắt đầu một bản sửa ngay lập tức; nếu đang có một cái khác chạy (nút khi đó là Xếp hàng), hoặc khi nhờ một tác nhân, nó sẽ chờ trong hàng đợi chung với các tính năng: Đang xếp hàng, số N, với các nút Sớm hơn, Muộn hơn và Bỏ khỏi hàng đợi, mỗi cái tự bắt đầu khi cái trước xong. Nó chỉ truy cập GitHub bằng token riêng, đặt trong mục đó (một fine-grained token cho kho mã, Contents và Pull requests), không bao giờ dùng đăng nhập gh của bạn; Claude không bao giờ thấy token. Chỉ những máy có cấu hình Nix bật tính năng này mới có nó.";
    };
    agentFeatures = {
      en = "Turn on Settings > Desktop agents > Features it builds > Build the features I ask for and Claude builds what you ask nixbook to do (a new widget, setting, shortcut or behaviour), apart from the fixes. Ask an agent (\"I wish the bar showed…\", \"add a way to…\": it files it with its request_feature tool) or type it in that section; a fix it finds too big for a fix comes there too, with what it found (a too-big one from before gets an As a feature button). Ask an agent \"did you file it?\" or \"how is my feature going?\" and its list_requests tool shows each fix and feature request: when and by whom it was filed, and whether it is queued, building, a pull request (its link and checks), merged, dropped or too big. With Settings > Desktop agents > Propose fixes and features on (and Talk to me on its own), the agent may also offer one itself every two days at most, from what it saw go wrong or get in your way (what failed in its memory, routines you undid, its tools' errors, the apps pairing saw you in): Yes, do it files it, Don't tell me this never proposes it again. Each feature is built like a fix (a clone of the repository, a session that can only edit files there, the same checks and off-limits places) but may be bigger (15 files and 600 lines by default, new files allowed), committed as feat(…) and opened as a pull request. It is never merged on its own: once CI passes you get Merge, Look and Drop. One it can't do (a design choice only you can make, more than it may change, a place off limits, credentials, hardware, or its change failing twice) is dropped with why and what would make it doable: you get a notification with Retry and Dismiss, and it waits in the section's Dropped list, never tried again unless you press Retry. It uses the GitHub token and model set in Fixes it makes itself; at most 1 a day on its own by default (Features a day on its own in that section, 0: no limit; Most a feature may spend caps each one), Build now starts one at once (while another is being made, it waits in the queue shared with the fixes and starts on its own after). Say \"build it now\" (or later \"start building that feature\") and the agent starts it the same way; \"fix it now\" does so for a fix, and asking how it goes gives where it stands (queued, being made, pull request open, CI passed). Only machines whose Nix configuration enables the fixer have it.";
      fr = "Activez Paramètres > Agents du bureau > Fonctionnalités qu'il construit > Construire les fonctionnalités que je demande et Claude construit ce que vous demandez à nixbook (un nouveau widget, réglage, raccourci ou comportement), à part des corrections. Demandez-le à un agent (« j'aimerais que la barre affiche… », « ajoute un moyen de… » : il le dépose avec son outil request_feature) ou écrivez-le dans cette section ; une correction qu'il trouve trop grosse y arrive aussi, avec ce qu'il a trouvé (une ancienne a un bouton En fonctionnalité). Demandez à un agent « tu l'as déposé ? » ou « où en est ma fonctionnalité ? » et son outil list_requests montre chaque correction et demande de fonctionnalité : quand et par qui elle a été déposée, et si elle est en attente, en construction, en pull request (son lien et ses vérifications), fusionnée, abandonnée ou trop grosse. Avec Paramètres > Agents du bureau > Proposer des corrections et des fonctionnalités (et Me parler de lui-même), l'agent peut aussi en proposer une lui-même, au plus tous les deux jours, d'après ce qu'il a vu échouer ou vous gêner (ce qui a échoué dans sa mémoire, les routines que vous avez annulées, les erreurs de ses outils, les applications où l'accompagnement vous a vu) : Oui, fais-le la dépose, Ne me dis plus ça ne la propose plus jamais. Chaque fonctionnalité est construite comme une correction (un clone du dépôt, une session qui ne peut modifier que les fichiers de ce clone, les mêmes vérifications et zones interdites) mais peut être plus grande (15 fichiers et 600 lignes par défaut, nouveaux fichiers permis), commitée en feat(…) et ouverte en pull request. Elle n'est jamais fusionnée seule : quand la CI passe, vous avez Fusionner, Voir et Abandonner. Celle qu'il ne peut pas faire (un choix de conception qui vous revient, plus qu'il ne peut changer, un endroit interdit, des identifiants, du matériel, ou sa modification refusée deux fois) est abandonnée avec la raison et ce qui la rendrait faisable : une notification propose Réessayer et Ignorer, et elle attend dans la liste Abandonnées de la section, jamais réessayée sauf si vous appuyez sur Réessayer. Elle utilise le jeton GitHub et le modèle de Corrections qu'il fait lui-même ; au plus 1 par jour de lui-même par défaut (Fonctionnalités par jour de lui-même dans cette section, 0 : sans limite ; Dépense maximale par fonctionnalité plafonne chacune), Construire maintenant en lance une tout de suite (pendant qu'une autre est en cours, elle attend dans la file partagée avec les corrections et démarre seule ensuite). Dites « construis-la maintenant » (ou plus tard « commence à construire cette fonctionnalité ») et l'agent la lance de même ; « corrige-le maintenant » fait pareil pour une correction, et demander où elle en est donne son état (en attente, en cours, pull request ouverte, CI réussie). Seules les machines dont la configuration Nix active le correcteur l'ont.";
      de = "Schalte Einstellungen > Desktop-Agenten > Funktionen, die es baut > Die Funktionen bauen, die ich wünsche ein, und Claude baut, was du dir von nixbook wünschst (ein neues Widget, eine Einstellung, ein Tastenkürzel oder Verhalten), getrennt von den Korrekturen. Sag es einem Agenten („ich hätte gern, dass die Leiste … zeigt“, „füg eine Möglichkeit hinzu, …“: er reicht es mit seinem Werkzeug request_feature ein) oder schreib es in diesen Abschnitt; eine Korrektur, die sich als zu groß erweist, landet auch dort, mit dem, was es gefunden hat (eine ältere bekommt einen Knopf Als Funktion). Frag einen Agenten „hast du es eingereicht?“ oder „wie steht es um meine Funktion?“, und sein Werkzeug list_requests zeigt jede Korrektur und jeden Funktionswunsch: wann und von wem eingereicht, und ob er wartet, gebaut wird, ein Pull Request ist (sein Link und seine Prüfungen), zusammengeführt, verworfen oder zu groß ist. Mit Einstellungen > Desktop-Agenten > Korrekturen und Funktionen vorschlagen (und Von selbst mit mir reden) kann der Agent auch selbst eine vorschlagen, höchstens alle zwei Tage, nach dem, was er schiefgehen oder dich stören sah (was in seinem Gedächtnis fehlschlug, Routinen, die du rückgängig gemacht hast, Fehler seiner Werkzeuge, die Apps, in denen ihn das Begleiten dich sah): Ja, mach das reicht sie ein, Sag mir das nicht mehr schlägt sie nie wieder vor. Jede Funktion wird wie eine Korrektur gebaut (ein Klon des Repositorys, eine Sitzung, die nur dort Dateien bearbeiten kann, dieselben Prüfungen und Sperrbereiche), darf aber größer sein (standardmäßig 15 Dateien und 600 Zeilen, neue Dateien erlaubt), wird als feat(…) committet und als Pull Request geöffnet. Sie wird nie von selbst zusammengeführt: sobald die CI durchläuft, bekommst du Zusammenführen, Ansehen und Verwerfen. Eine, die es nicht schafft (eine Designentscheidung, die bei dir liegt, mehr als es ändern darf, ein gesperrter Ort, Zugangsdaten, Hardware, oder ihre Änderung zweimal abgelehnt), wird mit Grund und dem, was sie machbar machen würde, aufgegeben: eine Benachrichtigung bietet Erneut versuchen und Verwerfen, und sie wartet in der Liste Aufgegeben des Abschnitts, nie wieder versucht, außer du drückst Erneut versuchen. Sie nutzt das GitHub-Token und das Modell aus Korrekturen, die es selbst macht; standardmäßig höchstens 1 am Tag von selbst (Funktionen pro Tag von selbst in diesem Abschnitt, 0: keine Grenze; Höchstausgabe pro Funktion begrenzt jede), Jetzt bauen startet eine sofort (während eine andere läuft, wartet sie in der mit den Korrekturen geteilten Warteschlange und startet danach von selbst). Sag „bau es jetzt“ (oder später „fang an, diese Funktion zu bauen“), und der Agent startet sie genauso; „korrigier das jetzt“ tut das für eine Korrektur, und auf die Frage, wie es läuft, nennt er den Stand (wartet, wird gebaut, Pull Request offen, CI bestanden). Nur Rechner, deren Nix-Konfiguration den Korrektor aktiviert, haben es.";
      vi = "Bật Cài đặt > Tác nhân màn hình > Tính năng nó xây dựng > Xây dựng các tính năng tôi yêu cầu và Claude sẽ xây dựng những gì bạn muốn nixbook làm (một widget, cài đặt, phím tắt hay hành vi mới), tách riêng với các bản sửa lỗi. Hãy nhờ một tác nhân (\"tôi muốn thanh trên cùng hiển thị…\", \"thêm cách để…\": nó ghi lại bằng công cụ request_feature) hoặc gõ vào mục đó; một bản sửa mà nó thấy quá lớn cũng chuyển sang đó, kèm điều nó tìm thấy (bản cũ có nút Thành tính năng). Hỏi một tác nhân \"bạn đã ghi lại chưa?\" hoặc \"tính năng của tôi thế nào rồi?\" và công cụ list_requests của nó cho thấy từng bản sửa và yêu cầu tính năng: được ghi lại khi nào và bởi ai, và nó đang chờ, đang xây dựng, là một pull request (đường dẫn và các bước kiểm tra), đã hợp nhất, đã bỏ hay quá lớn. Khi bật Cài đặt > Tác nhân màn hình > Đề xuất sửa lỗi và tính năng (và Tự nói chuyện với tôi), tác nhân cũng có thể tự đề xuất một cái, tối đa hai ngày một lần, từ những gì nó thấy hỏng hoặc làm phiền bạn (điều thất bại trong bộ nhớ, các thói quen tự động bạn đã hủy, lỗi của công cụ, các ứng dụng mà chế độ đồng hành thấy bạn dùng): Có, làm đi sẽ ghi lại, Đừng nói điều này nữa sẽ không bao giờ đề xuất lại. Mỗi tính năng được xây như một bản sửa (một bản sao kho mã, một phiên chỉ được sửa tệp trong đó, cùng các bước kiểm tra và vùng cấm) nhưng có thể lớn hơn (mặc định 15 tệp và 600 dòng, được thêm tệp mới), commit dạng feat(…) và mở thành pull request. Nó không bao giờ tự hợp nhất: khi CI qua, bạn có Hợp nhất, Xem và Bỏ. Tính năng nó không làm được (một lựa chọn thiết kế chỉ bạn quyết, nhiều hơn mức được phép thay đổi, một chỗ bị cấm, thông tin đăng nhập, phần cứng, hoặc thay đổi bị từ chối hai lần) bị bỏ kèm lý do và điều gì sẽ giúp làm được: bạn nhận thông báo với Thử lại và Bỏ qua, và nó chờ trong danh sách Đã bỏ của mục đó, không bao giờ thử lại trừ khi bạn bấm Thử lại. Nó dùng token GitHub và mô hình đặt ở Tự sửa lỗi; mặc định tối đa 1 lần mỗi ngày tự động (Số tính năng mỗi ngày trong mục đó, 0: không giới hạn; Chi tối đa mỗi tính năng giới hạn từng cái), Xây ngay bắt đầu một cái ngay lập tức (nếu đang có một cái khác chạy, nó chờ trong hàng đợi chung với các bản sửa và tự bắt đầu sau đó). Nói \"xây ngay đi\" (hoặc sau đó \"bắt đầu xây tính năng đó\") và tác nhân sẽ bắt đầu y như vậy; \"sửa ngay đi\" làm thế cho một bản sửa, và hỏi tiến độ sẽ cho biết trạng thái (đang chờ, đang làm, pull request đã mở, CI đã qua). Chỉ những máy có cấu hình Nix bật trình sửa lỗi mới có nó.";
    };
    personalMemory = {
      en = "Claude in the side panel remembers what you tell it about your life (events, plans, people, interests) across conversations: it keeps the meaningful parts, one entry per subject, and gets only what a conversation needs (your profile, events coming up, the entries about what you talk about). Ask it to remember or forget something; review or delete entries in Settings > Desktop agents > About you, or with nixbook-desktop-mcp personal show.";
      fr = "Claude dans le panneau latéral se souvient de ce que vous lui dites de votre vie (événements, projets, proches, centres d'intérêt) d'une conversation à l'autre : il garde l'essentiel, une entrée par sujet, et ne reçoit que ce dont une conversation a besoin (votre profil, les événements à venir, les entrées sur ce dont vous parlez). Demandez-lui de retenir ou d'oublier quelque chose ; consultez ou supprimez les entrées dans Paramètres > Agents du bureau > À propos de vous, ou avec nixbook-desktop-mcp personal show.";
      de = "Claude in der Seitenleiste merkt sich über Gespräche hinweg, was du ihm über dein Leben erzählst (Ereignisse, Pläne, Menschen, Interessen): Es behält das Wesentliche, einen Eintrag pro Thema, und bekommt nur, was ein Gespräch braucht (dein Profil, anstehende Ereignisse, die Einträge zu dem, worüber du sprichst). Bitte es, sich etwas zu merken oder zu vergessen; Einträge ansehen oder löschen unter Einstellungen > Desktop-Agenten > Über dich oder mit nixbook-desktop-mcp personal show.";
      vi = "Claude trong bảng bên ghi nhớ những gì bạn kể về cuộc sống của mình (sự kiện, kế hoạch, người thân, sở thích) qua các cuộc trò chuyện: nó giữ những phần quan trọng, mỗi chủ đề một mục, và chỉ nhận những gì cuộc trò chuyện cần (hồ sơ của bạn, sự kiện sắp tới, các mục về điều bạn đang nói). Hãy bảo nó nhớ hoặc quên điều gì đó; xem hoặc xóa các mục trong Cài đặt > Tác nhân màn hình > Về bạn, hoặc bằng nixbook-desktop-mcp personal show.";
    };
    fullAiMode = {
      en = "Full AI mode (Mod+Shift+T, or Settings > Desktop agents > Full AI mode): Claude runs the desktop and you tell it what to do in its speech bubble (Mod+C). A small mascot moves around the screen: a thought cloud for what it thinks and does, a speech balloon for its answers, and Yes / No right on the balloon when it asks you something. It takes neither your keyboard nor your mouse. It also reacts to what happens (a notification, a download, the battery, a screen, the network, you coming back): it ignores it, tells you, asks what to do or does it, on its own only for what you told it or chose twice before, and learns from your answers (Settings > Desktop agents > Full AI mode: React to what happens; Forget what Full AI learned). While it is on, it reacts instead of Claude's usual initiative. Mod+Shift+T again leaves; locking the screen leaves too.";
      fr = "Le mode IA complète (Mod+Maj+T, ou Paramètres > Agents du bureau > Mode IA complète) : Claude pilote le bureau et vous lui dites quoi faire dans sa bulle (Mod+C). Une petite mascotte se déplace sur l'écran : un nuage de pensée pour ce qu'elle pense et fait, une bulle pour ses réponses, et Oui / Non directement sur la bulle quand elle vous pose une question. Elle ne prend ni votre clavier ni votre souris. Elle réagit aussi à ce qui se passe (une notification, un téléchargement, la batterie, un écran, le réseau, votre retour) : elle l'ignore, vous le dit, vous demande quoi faire ou le fait, seule uniquement pour ce que vous lui avez dit ou choisi deux fois déjà, et apprend de vos réponses (Paramètres > Agents du bureau > Mode IA complète : Réagir à ce qui se passe ; Oublier ce que l'IA complète a appris). Pendant ce temps, elle réagit à la place de l'initiative habituelle de Claude. Mod+Maj+T de nouveau quitte le mode ; verrouiller l'écran aussi.";
      de = "Der volle KI-Modus (Mod+Umschalt+T, oder Einstellungen > Desktop-Agenten > Voller KI-Modus): Claude steuert den Desktop und du sagst ihm in seiner Sprechblase (Mod+C), was zu tun ist. Ein kleines Maskottchen bewegt sich über den Bildschirm: eine Gedankenwolke für das, was es denkt und tut, eine Sprechblase für seine Antworten und Ja / Nein direkt auf der Blase, wenn es dich etwas fragt. Es nimmt weder Tastatur noch Maus. Es reagiert auch auf das, was passiert (eine Benachrichtigung, ein Download, der Akku, ein Bildschirm, das Netz, deine Rückkehr): es ignoriert es, sagt es dir, fragt, was zu tun ist, oder tut es, allein nur bei dem, was du ihm gesagt oder zweimal gewählt hast, und lernt aus deinen Antworten (Einstellungen > Desktop-Agenten > Voller KI-Modus: Auf Ereignisse reagieren; Vergessen, was die volle KI gelernt hat). Solange er an ist, reagiert er statt Claudes üblicher Initiative. Erneut Mod+Umschalt+T beendet ihn; das Sperren des Bildschirms auch.";
      vi = "Chế độ AI toàn phần (Mod+Shift+T, hoặc Cài đặt > Tác nhân màn hình > Chế độ AI toàn phần): Claude điều khiển màn hình và bạn bảo nó làm gì trong bong bóng của nó (Mod+C). Một linh vật nhỏ di chuyển trên màn hình: đám mây suy nghĩ cho điều nó nghĩ và làm, bong bóng lời thoại cho câu trả lời, và Có / Không ngay trên bong bóng khi nó hỏi bạn. Nó không chiếm bàn phím hay chuột. Nó cũng phản ứng với những gì xảy ra (thông báo, tải xuống, pin, màn hình, mạng, khi bạn quay lại): bỏ qua, báo cho bạn, hỏi bạn nên làm gì hoặc tự làm, tự làm chỉ với điều bạn đã dặn hoặc đã chọn hai lần, và học từ câu trả lời của bạn (Cài đặt > Tác nhân màn hình > Chế độ AI toàn phần: Phản ứng với sự kiện; Quên những gì AI toàn phần đã học). Khi bật, nó phản ứng thay cho sáng kiến thường ngày của Claude. Nhấn Mod+Shift+T lần nữa để thoát; khóa màn hình cũng thoát.";
    };
    agentsInParallel = {
      en = "The desktop agents can work while you do, without taking your mouse or keyboard: in Zen they act in the page itself (reading pages, clicking, typing, filling forms) in any tab, in the background or in another workspace, through nixbook's Zen extension; in other apps they use the app's own controls through its accessibility tree, on any workspace. Off limits in Zen: private windows, password fields, the Banking container, password managers, your Google account, PayPal and banks. A click on Send, Pay or Order is asked first (a notification with Allow / No).";
      fr = "Les agents du bureau peuvent travailler pendant que vous travaillez, sans prendre votre souris ni votre clavier : dans Zen ils agissent dans la page elle-même (lire, cliquer, écrire, remplir des formulaires) dans n'importe quel onglet, en arrière-plan ou dans un autre espace, grâce à l'extension Zen de nixbook ; dans les autres applications ils passent par leurs propres commandes via l'arbre d'accessibilité, sur n'importe quel espace. Interdit dans Zen : les fenêtres privées, les champs de mot de passe, le conteneur Banking, les gestionnaires de mots de passe, votre compte Google, PayPal et les banques. Un clic sur Envoyer, Payer ou Commander est demandé avant (une notification avec Autoriser / Non).";
      de = "Die Desktop-Agenten können arbeiten, während du arbeitest, ohne Maus oder Tastatur zu übernehmen: in Zen handeln sie in der Seite selbst (lesen, klicken, tippen, Formulare ausfüllen) in jedem Tab, im Hintergrund oder in einem anderen Arbeitsbereich, über nixbooks Zen-Erweiterung; in anderen Apps über deren eigene Bedienelemente per Barrierefreiheitsbaum, auf jedem Arbeitsbereich. In Zen tabu: private Fenster, Passwortfelder, der Banking-Container, Passwortmanager, dein Google-Konto, PayPal und Banken. Ein Klick auf Senden, Bezahlen oder Bestellen wird vorher erfragt (eine Benachrichtigung mit Erlauben / Nein).";
      vi = "Các tác nhân màn hình có thể làm việc cùng lúc với bạn mà không chiếm chuột hay bàn phím: trong Zen chúng thao tác ngay trong trang (đọc, bấm, gõ, điền biểu mẫu) ở bất kỳ thẻ nào, chạy nền hoặc ở không gian làm việc khác, nhờ tiện ích Zen của nixbook; trong ứng dụng khác chúng dùng chính các điều khiển của ứng dụng qua cây trợ năng, ở bất kỳ không gian nào. Trong Zen không được đụng: cửa sổ riêng tư, ô mật khẩu, container Banking, trình quản lý mật khẩu, tài khoản Google, PayPal và ngân hàng. Bấm Gửi, Thanh toán hay Đặt hàng thì sẽ hỏi trước (một thông báo với Cho phép / Không).";
    };
    appsThroughThePage = {
      en = "The desktop agents also work inside Electron apps nixbook starts through its bridge (nixbook-electron-app: Discord in Vesktop, Slack, YouTube Music, Actual Budget), like Zen's tabs: they read the app's page, click, type (even in Discord's message box) and press keys in the page itself, its window in the background or on another workspace, without your mouse or keyboard (page_list, page_read, page_act). Discord also has its own tool: find a channel or a person, read the last messages, send or reply, react; every message or reaction sent in your name is asked first (a notification with Allow / No), and so is Enter in Discord's or Slack's message box. YouTube Music: playing and the queue go through its own MCP server, the page for the rest (lyrics, the library). An app that runs without the bridge (it restarted itself to update, an autostart entry or another launcher started it) is put back on it: one that has just started is restarted through it at once, otherwise (or during a call) you get a notification with Restart with bridge; it is never closed unasked. Password managers are never bridged; customHomeManagerModules.nixbookShellConfig.electronBridge turns it off or picks the apps. Automating your own account may break Discord's or Slack's terms.";
      fr = "Les agents du bureau travaillent aussi dans les applications Electron que nixbook lance par son pont (nixbook-electron-app : Discord dans Vesktop, Slack, YouTube Music, Actual Budget), comme dans les onglets de Zen : ils lisent la page de l'application, cliquent, écrivent (même dans la zone de message de Discord) et appuient sur des touches dans la page elle-même, sa fenêtre en arrière-plan ou dans un autre espace, sans votre souris ni votre clavier (page_list, page_read, page_act). Discord a aussi son propre outil : trouver un salon ou une personne, lire les derniers messages, envoyer ou répondre, réagir ; chaque message ou réaction envoyé en votre nom est demandé avant (une notification avec Autoriser / Non), comme Entrée dans la zone de message de Discord ou de Slack. YouTube Music : la lecture et la file passent par son propre serveur MCP, la page pour le reste (paroles, bibliothèque). Une application lancée sans le pont (elle s'est relancée pour une mise à jour, une entrée de démarrage automatique ou un autre lanceur l'a ouverte) y est remise : si elle vient de démarrer, elle est relancée par le pont aussitôt, sinon (ou pendant un appel) une notification propose Redémarrer avec le pont ; elle n'est jamais fermée sans vous demander. Les gestionnaires de mots de passe ne passent jamais par le pont ; customHomeManagerModules.nixbookShellConfig.electronBridge le désactive ou choisit les applications. Automatiser votre propre compte peut enfreindre les conditions de Discord ou de Slack.";
      de = "Die Desktop-Agenten arbeiten auch in Electron-Apps, die nixbook über seine Brücke startet (nixbook-electron-app: Discord in Vesktop, Slack, YouTube Music, Actual Budget), wie in Zens Tabs: Sie lesen die Seite der App, klicken, tippen (sogar in Discords Nachrichtenfeld) und drücken Tasten in der Seite selbst, ihr Fenster im Hintergrund oder auf einem anderen Arbeitsbereich, ohne deine Maus oder Tastatur (page_list, page_read, page_act). Discord hat auch ein eigenes Werkzeug: einen Kanal oder eine Person finden, die letzten Nachrichten lesen, senden oder antworten, reagieren; jede in deinem Namen gesendete Nachricht oder Reaktion wird vorher erfragt (eine Benachrichtigung mit Erlauben / Nein), ebenso Enter in Discords oder Slacks Nachrichtenfeld. YouTube Music: Wiedergabe und Warteschlange über seinen eigenen MCP-Server, die Seite für den Rest (Songtexte, Bibliothek). Eine App, die ohne die Brücke läuft (sie hat sich für ein Update neu gestartet, ein Autostart-Eintrag oder ein anderer Starter hat sie geöffnet), kommt wieder auf sie: gerade gestartet wird sie sofort über die Brücke neu gestartet, sonst (oder während eines Anrufs) fragt eine Benachrichtigung mit Mit Brücke neu starten; sie wird nie ungefragt geschlossen. Passwortmanager laufen nie über die Brücke; customHomeManagerModules.nixbookShellConfig.electronBridge schaltet sie ab oder wählt die Apps. Das eigene Konto zu automatisieren kann gegen Discords oder Slacks Bedingungen verstoßen.";
      vi = "Các tác nhân màn hình cũng làm việc trong các ứng dụng Electron mà nixbook mở qua cầu nối của nó (nixbook-electron-app: Discord trong Vesktop, Slack, YouTube Music, Actual Budget), giống như các thẻ của Zen: chúng đọc trang của ứng dụng, bấm, gõ (cả trong ô tin nhắn của Discord) và nhấn phím ngay trong trang, cửa sổ chạy nền hoặc ở không gian khác, không cần chuột hay bàn phím của bạn (page_list, page_read, page_act). Discord còn có công cụ riêng: tìm kênh hoặc người, đọc các tin nhắn mới nhất, gửi hoặc trả lời, thả cảm xúc; mỗi tin nhắn hay cảm xúc gửi đi dưới tên bạn đều được hỏi trước (một thông báo với Cho phép / Không), cũng như phím Enter trong ô tin nhắn của Discord hay Slack. YouTube Music: phát nhạc và hàng chờ qua máy chủ MCP riêng của nó, trang cho phần còn lại (lời bài hát, thư viện). Ứng dụng chạy mà không có cầu nối (nó tự khởi động lại để cập nhật, do mục tự khởi động hoặc trình mở khác mở) sẽ được đưa lại vào cầu nối: nếu vừa mới mở thì được khởi động lại qua cầu nối ngay, nếu không (hoặc đang trong cuộc gọi) bạn nhận một thông báo với nút Khởi động lại với cầu nối; nó không bao giờ bị đóng mà không hỏi bạn. Trình quản lý mật khẩu không bao giờ qua cầu nối; customHomeManagerModules.nixbookShellConfig.electronBridge để tắt hoặc chọn ứng dụng. Tự động hóa tài khoản của chính bạn có thể vi phạm điều khoản của Discord hoặc Slack.";
    };
    jellyfin = {
      en = "Jellyfin: in Settings > Desktop agents > Apps it can use, turn Jellyfin on, enter your server, then sign in with your own Jellyfin username and password (no admin or API key needed; with two-factor authentication such as the JellyfinSecurity plugin, an app password made for it). That signs in Claude and the player of this computer, each with its own login; the password isn't kept, and Sign out ends Claude's session on the server. Films and episodes then play fullscreen in mpv on this computer. Say or type \"play Edgerunners season 1 episode 2\" in Claude's bubble to start one at once; ask Claude to play on Moonfin or the TV to use those instead. Audio and subtitles: say them (\"play Edgerunners season 1 episode 2 in Japanese with English subtitles\", \"without subtitles\"; the next episodes keep them), ask Claude to switch them while it plays, or to set your defaults for every player (\"always Japanese audio with English subtitles\": Jellyfin's audio and subtitle language preferences, subtitle mode Smart). An admin's API key still works: Use an admin API key instead.";
      fr = "Jellyfin : dans Paramètres > Agents du bureau > Applications utilisables, activez Jellyfin, saisissez votre serveur, puis connectez-vous avec votre propre nom d'utilisateur et mot de passe Jellyfin (ni administrateur ni clé d'API nécessaire ; avec une authentification à deux facteurs comme le plugin JellyfinSecurity, un mot de passe d'application créé pour cela). Cela connecte Claude et le lecteur de cet ordinateur, chacun avec sa propre session ; le mot de passe n'est pas gardé, et Se déconnecter ferme la session de Claude sur le serveur. Films et épisodes se lancent alors en plein écran dans mpv sur cet ordinateur. Dites ou tapez « lance Edgerunners saison 1 épisode 2 » dans la bulle de Claude pour en lancer un tout de suite ; demandez à Claude de le lire sur Moonfin ou la télé pour les utiliser à la place. Audio et sous-titres : dites-les (« lance Edgerunners saison 1 épisode 2 en japonais sous-titré en anglais », « en VOSTFR », « en VF », « sans sous-titres » ; les épisodes suivants les gardent), demandez à Claude de les changer pendant la lecture, ou de régler vos choix par défaut pour tous les lecteurs (« toujours l'audio japonais avec les sous-titres anglais » : les préférences de langue audio et de sous-titres de Jellyfin, mode de sous-titres Intelligent). Une clé d'API d'administrateur marche toujours : Utiliser plutôt une clé d'API d'administrateur.";
      de = "Jellyfin: Unter Einstellungen > Desktop-Agenten > Nutzbare Apps Jellyfin einschalten, den Server eingeben und dich mit deinem eigenen Jellyfin-Benutzernamen und Passwort anmelden (kein Admin und kein API-Schlüssel nötig; mit Zwei-Faktor-Authentifizierung wie dem JellyfinSecurity-Plugin ein dafür erstelltes App-Passwort). Damit werden Claude und der Player dieses Computers angemeldet, jeder mit eigener Sitzung; das Passwort wird nicht gespeichert, und Abmelden beendet Claudes Sitzung auf dem Server. Filme und Folgen laufen dann im Vollbild in mpv auf diesem Computer. Sag oder tippe „spiel Edgerunners Staffel 1 Folge 2“ in Claudes Sprechblase, um sofort eine zu starten; bitte Claude, auf Moonfin oder dem Fernseher abzuspielen, um diese zu nutzen. Ton und Untertitel: sag sie („spiel Edgerunners Staffel 1 Folge 2 auf Japanisch mit englischen Untertiteln“, „als OmU“, „ohne Untertitel“; die nächsten Folgen behalten sie), bitte Claude, sie während der Wiedergabe zu wechseln, oder deine Standards für alle Player einzustellen („immer japanischer Ton mit englischen Untertiteln“: Jellyfins Ton- und Untertitelsprache, Untertitelmodus Smart). Ein Admin-API-Schlüssel geht weiterhin: Stattdessen einen Admin-API-Schlüssel verwenden.";
      vi = "Jellyfin: trong Cài đặt > Tác nhân màn hình > Ứng dụng có thể dùng, bật Jellyfin, nhập máy chủ, rồi đăng nhập bằng tên người dùng và mật khẩu Jellyfin của chính bạn (không cần quản trị viên hay khóa API; nếu có xác thực hai lớp như plugin JellyfinSecurity, dùng một mật khẩu ứng dụng tạo cho việc này). Việc đó đăng nhập cho Claude và trình phát của máy này, mỗi bên một phiên riêng; mật khẩu không được lưu, và Đăng xuất sẽ kết thúc phiên của Claude trên máy chủ. Phim và tập phim sẽ phát toàn màn hình trong mpv trên máy này. Nói hoặc gõ \"xem Edgerunners mùa 1 tập 2\" trong bong bóng của Claude để phát ngay; nhờ Claude phát trên Moonfin hoặc TV để dùng chúng. Âm thanh và phụ đề: hãy nói ra (\"xem Edgerunners mùa 1 tập 2 tiếng Nhật phụ đề tiếng Anh\", \"không phụ đề\"; các tập sau giữ nguyên), nhờ Claude đổi khi đang phát, hoặc đặt mặc định cho mọi trình phát (\"luôn âm thanh tiếng Nhật với phụ đề tiếng Anh\": tùy chọn ngôn ngữ âm thanh và phụ đề của Jellyfin, chế độ phụ đề Thông minh). Khóa API của quản trị viên vẫn dùng được: Dùng khóa API quản trị viên thay thế.";
    };
    jellyfinTranscoding = {
      en = "Jellyfin playback on this computer plays files as they are (direct play): mpv plays almost anything, and nixbook lifts jellyfin-mpv-shim's 10 Mbit/s limit for servers it doesn't see on the local network (behind a public address, a reverse proxy or a VPN), which made the server transcode most 1080p and every 4K file. A limit can still come from nixbookShellConfig.jellyfinMcp.player.maxBitrateMbps or from the server: Dashboard > Users > the user > Internet streaming bitrate limit, or Dashboard > Playback > Streaming. Ask Claude \"why is it transcoding?\": it reads the server's reasons (ContainerBitrateExceedsLimit is a bitrate limit).";
      fr = "La lecture Jellyfin sur cet ordinateur lit les fichiers tels quels (lecture directe) : mpv lit presque tout, et nixbook lève la limite de 10 Mbit/s de jellyfin-mpv-shim pour les serveurs qu'il ne voit pas sur le réseau local (derrière une adresse publique, un proxy inverse ou un VPN), qui faisait transcoder au serveur la plupart des fichiers 1080p et tous les 4K. Une limite peut encore venir de nixbookShellConfig.jellyfinMcp.player.maxBitrateMbps ou du serveur : Tableau de bord > Utilisateurs > l'utilisateur > Limite de débit de streaming Internet, ou Tableau de bord > Lecture > Streaming. Demandez à Claude « pourquoi ça transcode ? » : il lit les raisons du serveur (ContainerBitrateExceedsLimit est une limite de débit).";
      de = "Jellyfin spielt auf diesem Computer Dateien so ab, wie sie sind (Direktwiedergabe): mpv spielt fast alles, und nixbook hebt jellyfin-mpv-shims Grenze von 10 Mbit/s für Server auf, die es nicht im lokalen Netz sieht (hinter einer öffentlichen Adresse, einem Reverse-Proxy oder einem VPN), wegen der der Server die meisten 1080p- und alle 4K-Dateien transkodierte. Eine Grenze kann noch von nixbookShellConfig.jellyfinMcp.player.maxBitrateMbps oder vom Server kommen: Dashboard > Benutzer > der Benutzer > Bitratenlimit für Internet-Streaming, oder Dashboard > Wiedergabe > Streaming. Frag Claude „warum wird transkodiert?“: Es liest die Gründe des Servers (ContainerBitrateExceedsLimit ist eine Bitratengrenze).";
      vi = "Jellyfin trên máy này phát tệp nguyên bản (phát trực tiếp): mpv phát được gần như mọi thứ, và nixbook bỏ giới hạn 10 Mbit/s của jellyfin-mpv-shim cho máy chủ không nằm trong mạng nội bộ (sau địa chỉ công khai, reverse proxy hay VPN), giới hạn khiến máy chủ chuyển mã phần lớn tệp 1080p và mọi tệp 4K. Giới hạn vẫn có thể đến từ nixbookShellConfig.jellyfinMcp.player.maxBitrateMbps hoặc từ máy chủ: Bảng điều khiển > Người dùng > người dùng đó > Giới hạn bitrate phát trực tuyến qua Internet, hoặc Bảng điều khiển > Phát lại > Phát trực tuyến. Hỏi Claude \"sao lại chuyển mã?\": nó đọc lý do của máy chủ (ContainerBitrateExceedsLimit là giới hạn bitrate).";
    };
    keepSync = {
      en = "To sync your notes with Google Keep, open the Notes window and click Keep (next to New): give it your Google account's email and its master token (the button beside the field opens gpsoauth's alternative flow, which explains how to get one). The two are kept in the keyring, never in the notes nor in the settings. What you change in the shell is pushed to Keep, what changes in Keep comes back (when both changed, the newer one wins); deletions are not synced: a note deleted in one place stays in the other. The shell syncs every keep.refreshMinutes (15) when keep.enable is on, and Sync now syncs at once. Settings > General > Google Keep has the interval and the two directions (keep.push sends the shell's new notes to Keep, keep.pull brings Keep's new notes in). Google has no public Keep API, so this goes through an unofficial client (gkeepapi).";
      fr = "Pour synchroniser vos notes avec Google Keep, ouvrez la fenêtre Notes et cliquez sur Keep (à côté de Nouveau) : donnez-lui l'email de votre compte Google et son master token (le bouton à côté du champ ouvre le flux alternatif de gpsoauth, qui explique comment l'obtenir). Les deux sont gardés dans le trousseau, jamais dans les notes ni dans les réglages. Ce que vous changez dans le shell est envoyé à Keep, ce qui change dans Keep revient ici (si les deux changent, le plus récent gagne) ; les suppressions ne sont pas synchronisées : une note supprimée d'un côté reste de l'autre. Le shell synchronise toutes les keep.refreshMinutes (15) si keep.enable est actif, et Synchroniser maintenant le fait tout de suite. Paramètres > Général > Google Keep a l'intervalle et les deux sens (keep.push envoie les nouvelles notes du shell à Keep, keep.pull ramène les nouvelles notes de Keep). Google n'a pas d'API Keep publique, donc tout passe par un client non officiel (gkeepapi).";
      de = "Um deine Notizen mit Google Keep zu synchronisieren, öffne das Notizen-Fenster und klicke auf Keep (neben Neu): gib die E-Mail deines Google-Kontos und dessen Master-Token ein (der Knopf neben dem Feld öffnet gpsoauths alternativen Ablauf, der erklärt, wie man eines bekommt). Beides liegt im Schlüsselbund, nie in den Notizen und nie in den Einstellungen. Was du in der Shell änderst, wird zu Keep geschickt, was sich in Keep ändert, kommt zurück (ändern sich beide, gewinnt das neuere); Löschungen werden nicht synchronisiert: eine gelöschte Notiz bleibt an der anderen Stelle. Die Shell synchronisiert alle keep.refreshMinutes (15), wenn keep.enable an ist, und Jetzt synchronisieren macht es sofort. Einstellungen > Allgemein > Google Keep hat das Intervall und beide Richtungen (keep.push sendet die neuen Notizen der Shell an Keep, keep.pull holt Keeps neue Notizen). Google hat keine öffentliche Keep-API, das läuft also über einen inoffiziellen Client (gkeepapi).";
      vi = "Để đồng bộ ghi chú của bạn với Google Keep, mở cửa sổ Ghi chú và bấm Keep (cạnh nút Mới): nhập email tài khoản Google và master token của tài khoản (nút cạnh ô có nhập mở luồng thay thế của gpsoauth, giải thích cách lấy token này). Cả hai được giữ trong keyring, không bao giờ nằm trong ghi chú hay trong cài đặt. Những gì bạn sửa trong shell sẽ được gửi sang Keep, những gì đổi trong Keep sẽ quay lại (nếu cả hai đều đổi, bên nào mới hơn thắng); việc xóa không được đồng bộ: ghi chú bị xóa ở một nơi vẫn còn ở nơi kia. Shell đồng bộ mỗi keep.refreshMinutes (15) khi keep.enable bật, và nút Đồng bộ ngay làm ngay lập tức. Cài đặt > Chung > Google Keep có khoảng thời gian và hai chiều (keep.push gửi ghi chú mới của shell sang Keep, keep.pull lấy ghi chú mới từ Keep về). Google không có API Keep công khai, nên việc này đi qua một thư viện không chính thức (gkeepapi).";
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
      default =
        (import ./default.nix {
          inherit pkgs;
          inherit (vpnClients) withTailscale withNetbird;
        }).package;
      defaultText = lib.literalExpression "(import ./nixbook-shell { inherit pkgs; }).package";
      description = ''
        The `nixbook-shell` launcher. Build it with your own quickshell pin
        through `import ./nixbook-shell { inherit pkgs quickshellSrc; }`.
        Under NixOS, the tailscale / netbird CLIs are only bundled when the
        system enables `services.tailscale` / `services.netbird`
        (`withTailscale` / `withNetbird`); standalone, both are.
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

    selfImprove.enable = lib.mkEnableOption ''
      the desktop agent fixing this configuration's repository itself
      (`nixbook-improve`, services/SelfImprove.qml): fixes and polish only,
      each a pull request made with its own GitHub token (set in Settings >
      Desktop agents, kept in the keyring; never the user's gh login or ssh
      key), and apart the features asked for (never merged on its own).
      Without it the Settings sections, the agents' `report_problem`,
      `request_feature` and `list_requests` tools, their improvement ideas
      and `nixbook-improve`
      are absent or refuse; with it both stay off until turned on in
      Settings (`ai.improve.enable`, `ai.improve.features.enable`)'';

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
                "personal"
                "ui"
                "pages"
                # The name of `pages` before: read as it.
                "browser"
              ]
            );
            default = [
              "observe"
              "screen"
              "windows"
              "input"
              "shell"
              "memory"
              "personal"
              "ui"
              "pages"
            ];
            description = ''
              Tool groups AI agents get: `observe` (windows, workspaces,
              apps), `screen` (screenshots, reading the clipboard and the
              recent notifications), `windows`
              (focus, move, close, launch apps), `input` (keyboard, pointer,
              writing the clipboard), `shell` (the shell's IPC, notifications),
              `memory` (notes agents keep about this desktop, and the digest of
              it they get when they connect), `personal` (what you tell
              agents about your life, remembered across conversations: an
              entry per subject, only the relevant part sent), `ui` (any app's window as text
              through its accessibility tree, and acting on its elements;
              needs the accessibility bus, nixbook's `niri.accessibility`;
              Firefox-based and Chromium/Electron apps through
              `desktopMcp.browserAccessibility`, on by default; Electron apps
              also need `--force-renderer-accessibility`: nixbook wraps its own,
              nixbookShellConfig.electronAccessibility), `pages` (web pages
              through the page itself: Zen's tabs, with nixbook's extension, and
              the Electron apps started through `nixbook-electron-app`, e.g.
              Vesktop, Slack, YouTube Music; read, click, type, forms, in the
              background, without the pointer or keys; Discord's messages
              through its own client too (find, read, send, react); sending a
              message, reacting, or a click or Enter that sends or pays is
              asked first (a notification with Allow / No);
              `browser.blockedSites` / `browser.blockedContainers` and
              `pages.blockedApps` are off limits, by default password managers,
              Google account and payment sites, banks and the Banking container,
              and password manager apps are never bridged; `browser`, its name
              before, means the same).
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

      browserAccessibility = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          The `ui` tools in Firefox-based and Chromium/Electron apps: sets
          `GNOME_ACCESSIBILITY` and `ACCESSIBILITY_ENABLED` in the session so
          they publish their accessibility tree (GTK and Qt apps always do).
          They then keep it up to date on every page change, all session long:
          more CPU, memory and scrolling jank in heavy pages. Off, agents read
          those apps with screenshots. Apps started before need a restart.
          Electron apps' pages also need `--force-renderer-accessibility` on
          their command line (the variables alone leave them empty): nixbook
          wraps Vesktop, Slack and YouTube Music with it
          (nixbookShellConfig.electronAccessibility, which follows this).
        '';
      };

      habits.enable = lib.mkEnableOption ''
        usage habits for good (otherwise Settings > Desktop agents turns them
        on and off): the `nixbook-habits` user service counts, on this
        machine and without any model, which app has the focus and for how
        long, the windows opened, the layouts restored and the themes chosen
        (app ids and times only: never window titles, files or input, but
        the cues of learned routines keep device and network names, and the
        music taste each track's artist, title and album, a year;
        nothing while locked, while an agent acts, for password managers or
        private browser windows). The launcher ranks apps with it, a weekly
        report sums it up, a theme switched at the same hour is suggested
        then, and agents get a short summary. Tune it with the
        `desktopMcp.settings` keys `habitsKeepDays` (28), `habitsAgents`
        (`digest`, `timeline` or `off`), `habitsTheme` (`suggest`, `auto` or
        `off`), `habitsWeeklyReport`, `habitsOpenAtUsualTime` (desktop ids
        opened at their usual time), `habitsIgnoreApps` and
        `habitsIgnoreTitles`. The music every player plays (MPRIS: artist,
        title, album, played or skipped) teaches agents the user's taste:
        `habitsMusic` (true), `habitsMusicKeepDays` (365),
        `habitsMusicIgnorePlayers` (regexes; default: web browsers)'';
    };

    electronBridge.apps = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            app = lib.mkOption {
              type = lib.types.strMatching "[a-z0-9][a-z0-9-]{0,31}";
              description = "The name agents know it by (`discord`).";
            };
            command = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "The app's own command (not the bridged wrapper).";
            };
            markers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Its store paths: a process naming one is the app.";
            };
            a11y = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "With its accessibility tree on.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        The Electron apps started through `nixbook-electron-app`
        (`package.passthru.electronBridge`) on this machine. When it lists
        any, the `nixbook-electron-watch` user service watches them: one
        that runs without the bridge (it restarted itself, an autostart
        entry or another launcher started it) is restarted through it when
        it has just started and isn't in a call, otherwise you get a
        notification with "Restart with bridge" (never stopped unasked).
        Written to `~/.config/nixbook-shell/electron-bridge.json`. nixbook
        fills it from the apps lib/electronA11y.nix bridges.
      '';
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

      mcpServers = lib.mkOption {
        type = lib.types.attrsOf (pkgs.formats.json { }).type;
        default = {
          nixos.command = lib.getExe pkgs.mcp-nixos;
        };
        defaultText = lib.literalExpression "{ nixos.command = lib.getExe pkgs.mcp-nixos; }";
        example = lib.literalExpression ''
          {
            nixos.command = lib.getExe pkgs.mcp-nixos;
            trek = { type = "http"; url = "https://trek.example.org/mcp"; };
          }
        '';
        description = ''
          MCP servers the AI chat's Claude model gets besides the desktop one,
          in Claude Code's `mcpServers` format, written to
          `~/.config/nixbook-shell/assistant-mcp.json`. All their tools are
          allowed. Not given while the chat's tools are disabled. The default,
          [MCP-NixOS](https://mcp-nixos.io), answers from the real NixOS,
          Home Manager and nix-darwin package and option data instead of
          guessing. `desktop` is reserved. The file is in the Nix store,
          which every user can read: no tokens or secrets in `env` or
          `headers` (point the server at a file of its own instead).
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
          Manager ones without NixOS), and how the calendars, contacts and
          to-do list sync through the shell's accounts: `calendarConnect`,
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

        # Terminal theming (appearance.wallpaperTheming.enableTerminal,
        # scripts/colors/applycolor.sh): kitty reads the generated theme,
        # last so it wins over stylix's colours (`include`: kitty skips it,
        # with a log line, while theming is off and the file is gone; its
        # globinclude takes no absolute path), and reloads it on SIGUSR1;
        # other terminals get the colours as escape sequences, written to the
        # open ones and replayed by each new interactive shell.
        programs.kitty.extraConfig = lib.mkIf config.programs.kitty.enable (
          lib.mkAfter "include ${terminalThemeDir}/kitty-theme.conf"
        );
        programs.zsh.initContent = lib.mkIf config.programs.zsh.enable (
          lib.mkAfter (replayTerminalColors + failedCommandZsh)
        );
        programs.bash.initExtra = lib.mkIf config.programs.bash.enable (
          lib.mkAfter (replayTerminalColors + failedCommandBash)
        );

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
            (
              cfg.desktopMcp.settings
              // {
                http.port = cfg.desktopMcp.http.port;
                habits = cfg.desktopMcp.habits.enable;
                # The fixer's availability: report_problem, request_feature,
                # list_requests, improvement ideas, Settings, nixbook-improve.
                improve = cfg.selfImprove.enable;
              }
            );
        # The AI chat's other MCP servers (assistant.mcpServers, services/Ai.qml).
        xdg.configFile."nixbook-shell/assistant-mcp.json".source =
          (pkgs.formats.json { }).generate "assistant-mcp.json"
            { inherit (cfg.assistant) mcpServers; };
        # The ui tools: Firefox-based and Chromium/Electron apps publish their
        # accessibility tree only when asked to (GTK and Qt apps always do).
        systemd.user.sessionVariables =
          lib.mkIf (cfg.desktopMcp.browserAccessibility && lib.elem "ui" cfg.desktopMcp.settings.tools)
            {
              GNOME_ACCESSIBILITY = "1";
              ACCESSIBILITY_ENABLED = "1";
            };

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

        # Launcher entry for the Tasks window (the to-do list, Google Tasks-like).
        xdg.desktopEntries.nixbook-shell-tasks = {
          name = "Tasks";
          genericName = "To-do list";
          comment = "Your tasks and their deadlines (Google Tasks once an account is connected)";
          exec = "${lib.getExe cfg.package} ipc call tasks open";
          icon = "x-office-calendar";
          terminal = false;
          categories = [
            "Office"
            "ProjectManagement"
          ];
          settings.Keywords = "tasks;todo;to-do;google tasks;deadline;checklist;";
        };

        # Launcher entry for the Notes window (the notes widget's notes).
        xdg.desktopEntries.nixbook-shell-notes = {
          name = "Notes";
          genericName = "Notes";
          comment = "Your desktop notes, searchable, pinned first";
          exec = "${lib.getExe cfg.package} ipc call notes launch";
          icon = "accessories-text-editor";
          terminal = false;
          categories = [
            "Office"
            "Utility"
          ];
          settings.Keywords = "notes;note;memo;sticky;jot;";
        };

        # Launcher entry for the Calendar window (every account's events,
        # through nixbook-accounts).
        xdg.desktopEntries.nixbook-shell-calendar = {
          name = "Calendar";
          genericName = "Calendar";
          comment = "Your calendars: the month, each day's events, new events";
          exec = "${lib.getExe cfg.package} ipc call calendar launch";
          icon = "x-office-calendar";
          terminal = false;
          categories = [
            "Office"
            "Calendar"
          ];
          settings.Keywords = "calendar;events;agenda;meeting;appointment;schedule;google calendar;icloud;";
        };

        # Launcher entry for the Contacts window (Google Contacts, through
        # nixbook-accounts).
        xdg.desktopEntries.nixbook-shell-contacts = {
          name = "Contacts";
          genericName = "Contacts";
          comment = "Your contacts: search, call, write, edit";
          exec = "${lib.getExe cfg.package} ipc call contacts launch";
          icon = "x-office-address-book";
          terminal = false;
          categories = [
            "Office"
            "ContactManagement"
          ];
          settings.Keywords = "contacts;people;address book;phone;email;google contacts;birthday;";
        };

        home.packages = [
          cfg.package
          cfg.package.passthru.quickshell
          # `nixbook-accounts status|add|remove…` from a terminal too.
          cfg.package.passthru.accounts
          # The faces appearance.fonts names (fonts.nix).
          cfg.package.passthru.fonts
          # Condensed display face used by the optional Persona theme
          # (appearance.persona.fonts) for titles and numbers.
          pkgs.oswald
          # Rounded face used by the optional Chiikawa theme
          # (appearance.chiikawa.fonts, themes.json style.fonts).
          pkgs.nunito
          # (Rajdhani, the Cyberpunk 2077 theme's condensed tech face, and
          # Zen Maru Gothic and Klee One, the Studio Ghibli theme's faces, are
          # in fonts.nix: nixpkgs doesn't ship them.)
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
              # The user's only (their location, shared folders…).
              run install -m600 "$shell_tmp/config.json" "$shell_config"
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
        # The Electron apps' bridge watcher (electronBridge.apps): an app
        # running without its bridge, restarted through it while it is young
        # and not in a call, otherwise the user asked (notification).
        xdg.configFile."nixbook-shell/electron-bridge.json" = lib.mkIf (cfg.electronBridge.apps != [ ]) {
          text = builtins.toJSON { inherit (cfg.electronBridge) apps; };
        };
        systemd.user.services.nixbook-electron-watch = lib.mkIf (cfg.electronBridge.apps != [ ]) {
          Unit = {
            Description = "nixbook-shell: Electron apps running without their bridge";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
            X-Restart-Triggers = [ (builtins.toJSON cfg.electronBridge.apps) ];
          };
          Service = {
            ExecStart = "${cfg.package.passthru.electronBridge}/bin/nixbook-electron-app watch";
            Restart = "on-failure";
            RestartSec = 5;
            Slice = "app.slice";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

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

        # Usage habits: the recorder reads niri's event stream and writes
        # ~/.local/state/nixbook-shell/habits.* (0600). It needs no network
        # at all. On from Settings > Desktop agents (`habits on`: the flag
        # file, and the unit started), or always with desktopMcp.habits.enable.
        systemd.user.services.nixbook-habits = {
          Unit = {
            Description = "nixbook-shell usage habits (counted locally, no model)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
            ConditionPathExists = lib.mkIf (
              !cfg.desktopMcp.habits.enable
            ) "${config.xdg.stateHome}/nixbook-shell/habits-enabled";
          };
          Service = {
            ExecStart = "${lib.getExe cfg.package.passthru.desktopMcp} habits watch";
            Restart = "on-failure";
            RestartSec = 5;
            Slice = "background.slice";
            NoNewPrivileges = true;
            # AF_UNIX only already keeps it off the network (IPAddressDeny
            # needs root's BPF firewall: a user unit only logged a warning).
            RestrictAddressFamilies = [ "AF_UNIX" ];
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
            # Usable, but second to the user's own apps.
            CPUWeight = 50;
            IOWeight = 50;
          };
        };
        # The others, one per chat tab of the side panel working at once
        # (nixbook-agent-desktop@2, @3…): the same, each its own desktop.
        systemd.user.services."nixbook-agent-desktop@" = {
          Unit = {
            Description = "A desktop of their own for AI agents, number %i (nested niri)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe cfg.package.passthru.agentDesktop;
            Environment = [ "NIXBOOK_AGENT_DESKTOP=%i" ];
            Slice = "app.slice";
            # Usable, but second to the user's own apps.
            CPUWeight = 50;
            IOWeight = 50;
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
            # The clipboard history (passwords copied, too): kept the user's
            # only, and off the network (it only talks to the compositor).
            NoNewPrivileges = true;
            RestrictAddressFamilies = [ "AF_UNIX" ];
            UMask = "0077";
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
