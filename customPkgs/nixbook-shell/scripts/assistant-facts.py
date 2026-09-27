"""Build the fact file for the config assistant (services/ConfigAssistant.qml,
no AI): one plain sentence per fact, in four languages, which the shell
retrieves for each question and answers from.

  assistant-facts.py <input.json> <binds.kdl>  >  system-facts.json

input.json (from homeManagerModules/nixbookShellConfig.nix): host, user,
enabled/declared NixOS and Home Manager module names, the shell settings
pinned in Nix ({"dot.path": value}), package names, every setting path.
binds.kdl: niri's rendered `binds { ... }` block (may be empty).

Every fact also exists in French, German and Vietnamese (`factsI18n`, same
order), so answers come in the language of the question; keybind
descriptions are written per action (niri's compositional actions such as
"move-column-to-workspace-down" are translated word by word).
"""

import json
import re
import sys

LANGS = ("en", "fr", "de", "vi")


def t(en, fr, de, vi):
    return {"en": en, "fr": fr, "de": de, "vi": vi}


# nixbook-shell IPC targets bound in niriConfig.nix.
IPC = {
    ("search", "toggle"): t(
        "open the app launcher (search and start apps, calculator, commands)",
        "ouvrir le lanceur d'applications (chercher et lancer des applications, calculatrice, commandes)",
        "den App-Starter öffnen (Apps suchen und starten, Rechner, Befehle)",
        "mở trình khởi chạy ứng dụng (tìm và mở ứng dụng, máy tính, lệnh)"),
    ("search", "workspacesToggle"): t(
        "open the shell's workspace overview",
        "ouvrir l'aperçu des espaces de travail du shell",
        "die Arbeitsbereich-Übersicht der Shell öffnen",
        "mở tổng quan không gian làm việc của shell"),
    ("search", "clipboardToggle"): t(
        "open the clipboard history",
        "ouvrir l'historique du presse-papiers",
        "den Zwischenablage-Verlauf öffnen",
        "mở lịch sử bộ nhớ tạm (clipboard)"),
    ("sidebarLeft", "toggle"): t(
        "open the left sidebar (AI chat assistant, translator)",
        "ouvrir le panneau de gauche (assistant IA / chat, traducteur)",
        "die linke Seitenleiste öffnen (KI-Chat-Assistent, Übersetzer)",
        "mở bảng bên trái (trợ lý AI / chat, dịch)"),
    ("sidebarRight", "toggle"): t(
        "open the right sidebar (quick settings, notifications, calendar)",
        "ouvrir le panneau de droite (paramètres rapides, notifications, calendrier)",
        "die rechte Seitenleiste öffnen (Schnelleinstellungen, Benachrichtigungen, Kalender)",
        "mở bảng bên phải (cài đặt nhanh, thông báo, lịch)"),
    ("settings", "toggle"): t(
        "open the shell settings window: the menu to configure the shell (bar, dock, widgets, theme, wallpaper, notifications)",
        "ouvrir la fenêtre des paramètres du shell : le menu pour configurer le shell (barre, dock, widgets, thème, fond d'écran, notifications)",
        "das Einstellungsfenster der Shell öffnen: das Menü zum Konfigurieren der Shell (Leiste, Dock, Widgets, Design, Hintergrundbild, Benachrichtigungen)",
        "mở cửa sổ cài đặt của shell: menu để cấu hình shell (thanh, dock, widget, giao diện, hình nền, thông báo)"),
    ("session", "toggle"): t(
        "open the power menu: lock the screen, log out, suspend, reboot or shut down",
        "ouvrir le menu d'alimentation : verrouiller l'écran, se déconnecter, mettre en veille, redémarrer ou éteindre",
        "das Energiemenü öffnen: Bildschirm sperren, abmelden, Standby, neu starten oder herunterfahren",
        "mở menu nguồn: khóa màn hình, đăng xuất, ngủ, khởi động lại hoặc tắt máy"),
    ("wallpaperSelector", "toggle"): t(
        "open the wallpaper selector (change the wallpaper)",
        "ouvrir le sélecteur de fond d'écran (changer le fond d'écran)",
        "die Hintergrundbild-Auswahl öffnen (Hintergrundbild ändern)",
        "mở trình chọn hình nền (đổi hình nền)"),
    ("region", "screenshot"): t(
        "take a screenshot of a screen region",
        "faire une capture d'écran d'une zone",
        "ein Bildschirmfoto eines Bereichs machen",
        "chụp màn hình một vùng"),
    ("region", "ocr"): t(
        "copy the text of a screen region (OCR)",
        "copier le texte d'une zone de l'écran (OCR)",
        "den Text eines Bildschirmbereichs kopieren (OCR)",
        "sao chép chữ trong một vùng màn hình (OCR)"),
    ("region", "record"): t(
        "record a screen region",
        "enregistrer une zone de l'écran",
        "einen Bildschirmbereich aufnehmen",
        "quay một vùng màn hình"),
    ("region", "search"): t(
        "search a screen region with Google Lens",
        "rechercher une zone de l'écran avec Google Lens",
        "einen Bildschirmbereich mit Google Lens suchen",
        "tìm một vùng màn hình bằng Google Lens"),
    ("bar", "toggle"): t(
        "show or hide the bar",
        "afficher ou masquer la barre",
        "die Leiste ein- oder ausblenden",
        "hiện hoặc ẩn thanh"),
    ("lock", "activate"): t(
        "lock the screen",
        "verrouiller l'écran",
        "den Bildschirm sperren",
        "khóa màn hình"),
    ("overlay", "toggle"): t(
        "open the overlay widgets",
        "ouvrir les widgets en surimpression",
        "die Overlay-Widgets öffnen",
        "mở các widget nổi"),
    ("mediaControls", "toggle"): t(
        "open the media controls",
        "ouvrir les contrôles multimédia",
        "die Mediensteuerung öffnen",
        "mở điều khiển đa phương tiện"),
}

NIRI = {
    "toggle-window-floating": t(
        "toggle the focused window between floating and tiled",
        "basculer la fenêtre active entre flottante et en mosaïque",
        "das aktive Fenster zwischen schwebend und gekachelt umschalten",
        "chuyển cửa sổ đang dùng giữa nổi và xếp ô"),
    "toggle-overview": t(
        "open niri's overview of all workspaces and windows",
        "ouvrir la vue d'ensemble de niri (tous les espaces de travail et fenêtres)",
        "die niri-Übersicht öffnen (alle Arbeitsbereiche und Fenster)",
        "mở tổng quan của niri (tất cả không gian làm việc và cửa sổ)"),
    "switch-preset-column-width": t(
        "cycle the column width presets",
        "changer la largeur de la colonne (préréglages)",
        "die Spaltenbreite wechseln (Vorgaben)",
        "đổi độ rộng cột (các mức có sẵn)"),
    "switch-focus-between-floating-and-tiling": t(
        "move focus between floating and tiled windows",
        "passer le focus entre les fenêtres flottantes et en mosaïque",
        "den Fokus zwischen schwebenden und gekachelten Fenstern wechseln",
        "chuyển tiêu điểm giữa cửa sổ nổi và xếp ô"),
    "close-window": t(
        "close the focused window",
        "fermer la fenêtre active",
        "das aktive Fenster schließen",
        "đóng cửa sổ đang dùng"),
    "fullscreen-window": t(
        "make the focused window fullscreen",
        "mettre la fenêtre active en plein écran",
        "das aktive Fenster im Vollbild anzeigen",
        "đưa cửa sổ đang dùng ra toàn màn hình"),
    "maximize-column": t(
        "maximize the column",
        "maximiser la colonne",
        "die Spalte maximieren",
        "phóng to cột"),
    "center-column": t(
        "center the column",
        "centrer la colonne",
        "die Spalte zentrieren",
        "căn giữa cột"),
    "consume-or-expel-window-left": t(
        "move the window into or out of the column on the left",
        "faire entrer ou sortir la fenêtre de la colonne de gauche",
        "das Fenster in die linke Spalte aufnehmen oder daraus lösen",
        "đưa cửa sổ vào hoặc ra khỏi cột bên trái"),
    "consume-or-expel-window-right": t(
        "move the window into or out of the column on the right",
        "faire entrer ou sortir la fenêtre de la colonne de droite",
        "das Fenster in die rechte Spalte aufnehmen oder daraus lösen",
        "đưa cửa sổ vào hoặc ra khỏi cột bên phải"),
    "power-off-monitors": t(
        "turn the monitors off",
        "éteindre les écrans",
        "die Bildschirme ausschalten",
        "tắt màn hình"),
    "quit": t(
        "quit niri (log out)",
        "quitter niri (se déconnecter)",
        "niri beenden (abmelden)",
        "thoát niri (đăng xuất)"),
    "screenshot": t(
        "take a screenshot (niri)",
        "faire une capture d'écran (niri)",
        "ein Bildschirmfoto machen (niri)",
        "chụp màn hình (niri)"),
    "screenshot-window": t(
        "take a screenshot of the focused window (niri)",
        "faire une capture de la fenêtre active (niri)",
        "ein Bildschirmfoto des aktiven Fensters machen (niri)",
        "chụp cửa sổ đang dùng (niri)"),
    "screenshot-screen": t(
        "take a screenshot of the screen (niri)",
        "faire une capture de l'écran (niri)",
        "ein Bildschirmfoto des Bildschirms machen (niri)",
        "chụp toàn màn hình (niri)"),
}

# Word-by-word parts of niri's compositional actions
# (focus-column-left, move-column-to-workspace-down, ...).
NOUNS = {
    "column": t("the column", "la colonne", "die Spalte", "cột"),
    "window": t("the window", "la fenêtre", "das Fenster", "cửa sổ"),
    "workspace": t("the workspace", "l'espace de travail", "den Arbeitsbereich", "không gian làm việc"),
    "monitor": t("the monitor", "l'écran", "den Bildschirm", "màn hình"),
}
# German "go to …" needs the dative: zur Spalte, zum Fenster, …
TO_DE = {"column": "zur Spalte", "window": "zum Fenster", "workspace": "zum Arbeitsbereich", "monitor": "zum Bildschirm"}
# "the column on the left" / "to the left"
WHERE = {
    "left": t("on the left", "de gauche", "links", "bên trái"),
    "right": t("on the right", "de droite", "rechts", "bên phải"),
    "up": t("above (previous)", "du haut (précédent)", "oben (vorherige)", "phía trên (trước)"),
    "down": t("below (next)", "du bas (suivant)", "unten (nächste)", "phía dưới (tiếp theo)"),
    "first": t("first", "du début", "ersten", "đầu tiên"),
    "last": t("last", "de la fin", "letzten", "cuối cùng"),
}
TOWARD = {
    "left": t("left", "vers la gauche", "nach links", "sang trái"),
    "right": t("right", "vers la droite", "nach rechts", "sang phải"),
    "up": t("up", "vers le haut", "nach oben", "lên trên"),
    "down": t("down", "vers le bas", "nach unten", "xuống dưới"),
}


def compose(name):
    """niri action name → {lang: description}, or None."""
    m = re.fullmatch(r"focus-(column|window|workspace|monitor)-(left|right|up|down|first|last)", name)
    if m:
        n, d = NOUNS[m[1]], WHERE[m[2]]
        return t(f"focus {n['en']} {d['en']}",
                 f"aller à {n['fr']} {d['fr']}",
                 f"{TO_DE[m[1]]} {d['de']} wechseln",
                 f"chuyển đến {n['vi']} {d['vi']}")
    m = re.fullmatch(r"move-(column|window|workspace)-(left|right|up|down)", name)
    if m:
        n, d = NOUNS[m[1]], TOWARD[m[2]]
        return t(f"move {n['en']} {d['en']}",
                 f"déplacer {n['fr']} {d['fr']}",
                 f"{n['de']} {d['de']} verschieben",
                 f"di chuyển {n['vi']} {d['vi']}")
    m = re.fullmatch(r"move-(column|window|workspace)-to-(workspace|monitor)-(left|right|up|down)", name)
    if m:
        n, n2, d = NOUNS[m[1]], NOUNS[m[2]], WHERE[m[3]]
        return t(f"move {n['en']} to {n2['en']} {d['en']}",
                 f"déplacer {n['fr']} vers {n2['fr']} {d['fr']}",
                 f"{n['de']} auf {n2['de']} {d['de']} verschieben",
                 f"di chuyển {n['vi']} sang {n2['vi']} {d['vi']}")
    return None


def describe(action: str):
    args = re.findall(r'"((?:[^"\\]|\\.)*)"', action)
    name = action.split()[0] if action else ""
    if name == "spawn" and args:
        if args[:3] == ["nixbook-shell", "ipc", "call"] and len(args) >= 5:
            fallback = f"nixbook-shell panel: {args[3]} {args[4]}"
            return IPC.get((args[3], args[4]), t(fallback, fallback, fallback, fallback))
        if args[0] == "wpctl":
            if "set-mute" in args:
                return t("mute or unmute the audio", "couper ou rétablir le son",
                         "den Ton stumm schalten oder wieder einschalten", "tắt hoặc bật tiếng")
            if args[-1].endswith("-"):
                return t("turn the volume down", "baisser le volume", "die Lautstärke verringern", "giảm âm lượng")
            return t("turn the volume up", "monter le volume", "die Lautstärke erhöhen", "tăng âm lượng")
        if args[0] == "brightnessctl":
            if args[-1].endswith("-"):
                return t("turn the brightness down", "baisser la luminosité", "die Helligkeit verringern", "giảm độ sáng")
            return t("turn the brightness up", "augmenter la luminosité", "die Helligkeit erhöhen", "tăng độ sáng")
        if args[0] in ("bash", "sh") and "hypridle" in action:
            return t("toggle caffeine mode (idle inhibition): keeps the display on and disables automatic locking and suspend",
                     "activer/désactiver le mode caféine (inhibition de veille) : garde l'écran allumé et désactive le verrouillage et la mise en veille automatiques",
                     "den Koffein-Modus umschalten (Ruhezustand verhindern): hält den Bildschirm an und deaktiviert automatisches Sperren und Standby",
                     "bật/tắt chế độ caffeine (chặn ngủ): giữ màn hình sáng, tắt tự động khóa và ngủ")
        if args[0] in ("bash", "sh"):
            return t("run a script", "lancer un script", "ein Skript ausführen", "chạy một script")
        if args[0] == "kitty":
            return t("open a terminal (kitty)", "ouvrir un terminal (kitty)",
                     "ein Terminal öffnen (kitty)", "mở terminal (kitty)")
        prog = " ".join(args)
        return t(f"launch {prog}", f"lancer {prog}", f"{prog} starten", f"mở {prog}")
    if name in NIRI:
        return NIRI[name]
    composed = compose(name)
    if composed:
        return composed
    rest = " ".join(args) or " ".join(action.split()[1:])
    generic = (name.replace("-", " ") + (" " + rest if rest else "")).strip()
    return t(generic, generic, generic, generic)


PRESS = t("Press {k} to {d}.", "Appuyez sur {k} pour {d}.", "{k} – {d}.", "Nhấn {k} để {d}.")
SETTING = t("The shell setting {p} is set in Nix to {v}.",
            "Le réglage du shell {p} est défini dans Nix à {v}.",
            "Die Shell-Einstellung {p} ist in Nix auf {v} gesetzt.",
            "Thiết lập shell {p} được đặt trong Nix là {v}.")
PACKAGE = t("The package {p} is installed.", "Le paquet {p} est installé.",
            "Das Paket {p} ist installiert.", "Gói {p} đã được cài đặt.")


def binds(kdl: str):
    for line in kdl.splitlines():
        m = re.match(r'\s*"?([^"{\s]+)"?\s*(?:[^{]*)\{\s*(.*?);?\s*\}\s*$', line)
        if m:
            yield m.group(1), describe(m.group(2))


def main():
    info = json.load(open(sys.argv[1]))
    kdl = open(sys.argv[2]).read() if len(sys.argv) > 2 else ""
    host, user = info["host"], info["user"]
    facts = {lang: [] for lang in LANGS}
    kinds = []  # "bind:<key>", "core", "setting", "package"

    def add(kind, texts):
        kinds.append(kind)
        for lang in LANGS:
            facts[lang].append(texts[lang])

    for key, what in binds(kdl):
        add(f"bind:{key}", {lang: PRESS[lang].format(k=key, d=what[lang]) for lang in LANGS})
    # The core statements as retrievable facts too, so questions about them
    # ("how do I apply my changes?") aren't mistaken for uncovered ones.
    for texts in [
        t("To apply a configuration change, run `colmena apply-local --sudo switch` from the nixbook repository.",
          "Pour appliquer une modification de la configuration, lancez `colmena apply-local --sudo switch` depuis le dépôt nixbook.",
          "Um eine Konfigurationsänderung anzuwenden, führe `colmena apply-local --sudo switch` im nixbook-Repository aus.",
          "Để áp dụng thay đổi cấu hình, chạy `colmena apply-local --sudo switch` trong kho nixbook."),
        t(f"System settings (NixOS modules and their options) are changed in profiles/{host}/default.nix.",
          f"Les réglages système (modules NixOS et leurs options) se changent dans profiles/{host}/default.nix.",
          f"Systemeinstellungen (NixOS-Module und ihre Optionen) werden in profiles/{host}/default.nix geändert.",
          f"Thiết lập hệ thống (module NixOS và tùy chọn) được đổi trong profiles/{host}/default.nix."),
        t(f"This user's Home Manager modules and their options are changed in profiles/{host}/{user}/default.nix.",
          f"Les modules Home Manager de cet utilisateur et leurs options se changent dans profiles/{host}/{user}/default.nix.",
          f"Die Home-Manager-Module dieses Benutzers und ihre Optionen werden in profiles/{host}/{user}/default.nix geändert.",
          f"Module Home Manager của người dùng này và tùy chọn được đổi trong profiles/{host}/{user}/default.nix."),
        t("Shell settings (bar, dock, widgets, notifications, theme) set in Nix are in homeManagerModules/nixbookShellConfig/settings.nix (shared) or nixbookShellConfig.settings in the user profile; the others are changed in the shell's Settings window.",
          "Les réglages du shell (barre, dock, widgets, notifications, thème) définis dans Nix sont dans homeManagerModules/nixbookShellConfig/settings.nix (communs) ou nixbookShellConfig.settings dans le profil utilisateur ; les autres se changent dans la fenêtre des paramètres du shell.",
          "In Nix gesetzte Shell-Einstellungen (Leiste, Dock, Widgets, Benachrichtigungen, Design) stehen in homeManagerModules/nixbookShellConfig/settings.nix (gemeinsam) oder nixbookShellConfig.settings im Benutzerprofil; die übrigen werden im Einstellungsfenster der Shell geändert.",
          "Thiết lập shell (thanh, dock, widget, thông báo, giao diện) đặt trong Nix nằm ở homeManagerModules/nixbookShellConfig/settings.nix (dùng chung) hoặc nixbookShellConfig.settings trong hồ sơ người dùng; các thiết lập khác đổi trong cửa sổ cài đặt của shell."),
        t("The keyboard shortcuts are documented in KEYBINDS.md in the nixbook repository.",
          "Les raccourcis clavier sont documentés dans KEYBINDS.md dans le dépôt nixbook.",
          "Die Tastenkürzel sind in KEYBINDS.md im nixbook-Repository dokumentiert.",
          "Các phím tắt được ghi trong KEYBINDS.md của kho nixbook."),
    ]:
        add("core", texts)
    for path, value in sorted(info["pinned"].items()):
        v = json.dumps(value, ensure_ascii=False)
        add("setting", {lang: SETTING[lang].format(p=path, v=v) for lang in LANGS})
    # Home Manager's desktop-entry shadows (hidden launcher entries) and
    # session scripts aren't things anyone asks about: only noise.
    packages = [p for p in info["packages"] if not p.endswith((".desktop", ".sh"))]
    for p in packages:
        add("package", {lang: PACKAGE[lang].format(p=p) for lang in LANGS})
    json.dump({
        "host": host,
        "user": user,
        "facts": facts["en"],
        "factsI18n": {lang: facts[lang] for lang in LANGS if lang != "en"},
        "kinds": kinds,
        "modules": {"all": sorted(set(info["osAll"] + info["hmAll"])),
                    "enabled": sorted(set(info["osEnabled"] + info["hmEnabled"]))},
        "packages": packages,
        "settingPaths": sorted(set(info.get("settingPaths", []))),
    }, sys.stdout, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
