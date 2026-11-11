#!/usr/bin/env python3
"""Make src/scripts/colors/app-templates/gmail.css: Gmail in the shell's
colours (Meru, Gmail's desktop app; Settings > Appearance > Color
generation > Apps > Gmail), from Catppuccin's Gmail userstyle (MIT,
github.com/catppuccin/userstyles, styles/gmail), which follows Gmail's
pages as they change.

Their style is Less written for Catppuccin's palette. It is compiled once
with every Catppuccin colour replaced by a marker colour, and the markers
are turned into the template's placeholders ({{colors.<role>.default.hex}},
render-app-colors.py), so the shell's palette goes where Catppuccin's
would: base → surface, mantle and crust → the low containers, surface0-2 →
the containers, text → on_surface, the accent → primary… Their colour
functions become CSS colour-mix() (darken: mixed with black, fade: with
transparency) and their icon filters a grey at the role's lightness
(.gray), so all of it follows the palette.

When Gmail changes and Catppuccin's style follows, bump REV (a commit of
catppuccin/userstyles) and run, from nixbook-shell/:

    nix shell -f '<nixpkgs>' lessc -c python3 scripts/gmail-template.py
"""

import os
import re
import subprocess
import sys
import tempfile
import urllib.request

REV = "a572540347086ba9165fa98da690296d86f9d6e9"
STYLE = f"https://raw.githubusercontent.com/catppuccin/userstyles/{REV}/styles/gmail/catppuccin.user.less"
LIB = f"https://raw.githubusercontent.com/catppuccin/userstyles/{REV}/lib/std/v1.less"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "scripts", "colors",
                   "app-templates", "gmail.css")

# Catppuccin's colour → the shell's Material role.
ROLES = {
    "text": "on_surface", "subtext1": "on_surface_variant", "subtext0": "on_surface_variant",
    "overlay2": "outline", "overlay1": "outline", "overlay0": "outline_variant",
    "surface2": "surface_container_highest", "surface1": "surface_container_high",
    "surface0": "surface_container", "base": "surface", "mantle": "surface_container_low",
    "crust": "surface_container_lowest", "accent": "primary",
    "rosewater": "tertiary", "flamingo": "tertiary", "pink": "tertiary", "mauve": "primary",
    "red": "error", "maroon": "error", "peach": "tertiary", "yellow": "tertiary", "green": "secondary",
    "teal": "secondary", "sky": "primary", "sapphire": "primary", "blue": "primary", "lavender": "primary",
}
NAMES = list(ROLES)
# One marker colour each (nothing else in their style uses #fe00xx).
MARK = {name: f"#fe00{i + 1:02x}" for i, name in enumerate(NAMES)}


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read().decode()


def lib_less(text):
    """Their library with the palette as markers, the filters as greys and
    the colour scheme as {{mode}}."""
    for name in NAMES:
        source = "@@accentColor" if name == "accent" else f"@{name}"
        text, n = re.subn(rf"@{name}: @catppuccin\[@@flavor\]\[{re.escape(source)}\];",
                          f"@{name}: {MARK[name]};", text)
        if n != 1:
            sys.exit(f"the library's palette changed: @{name}")
        text, n = re.subn(rf"@{name}-filter: @catppuccin-filters\[@@flavor\]\[{re.escape(source)}\];",
                          f'@{name}-filter: ~"brightness(0) invert(GRAY_{name})";', text)
        if n != 1:
            sys.exit(f"the library's filters changed: @{name}-filter")
    text, n = re.subn(r"color-scheme: if\(@flavor = latte, light, dark\);", 'color-scheme: ~"{{mode}}";', text)
    if n != 1:
        sys.exit("the library's color-scheme changed")
    return text


def functions(text):
    """Less colour functions on a palette colour as CSS colour-mix()."""
    text = re.sub(r"darken\(@(\w+),\s*(\d+)%\)",
                  lambda m: f'~"color-mix(in srgb, @{{{m[1]}}} {100 - 2 * int(m[2])}%, black)"', text)
    text = re.sub(r"lighten\(@(\w+),\s*(\d+)%\)",
                  lambda m: f'~"color-mix(in srgb, @{{{m[1]}}} {100 - 2 * int(m[2])}%, white)"', text)
    text = re.sub(r"fade\(@(\w+),\s*(\d+)%\)",
                  lambda m: f'~"color-mix(in srgb, @{{{m[1]}}} {m[2]}%, transparent)"', text)
    left = re.findall(r"(?<![\w-])(darken|lighten|fade|mix|spin|saturate|desaturate|tint|shade)\(\s*@", text)
    if left:
        sys.exit(f"colour functions not handled: {sorted(set(left))}")
    return text


def style_less(text, lib):
    """Their style for Gmail alone (no @-moz-document, no flavour picking),
    the library inline."""
    text, n = re.subn(r'@import "https://userstyles\.catppuccin\.com/lib/std/v1\.less";', lambda _: lib, text)
    if n != 1:
        sys.exit("the style's library import changed")
    text, n = re.subn(r'@-moz-document domain\("mail\.google\.com"\) \{', "", text)
    if n != 1:
        sys.exit("the style's @-moz-document changed")
    text = text.rstrip()
    if not text.endswith("}"):
        sys.exit("the style doesn't end its @-moz-document")
    text = text[:-1]
    text, n = re.subn(r":root \{\s*@media \(prefers-color-scheme: light\) \{\s*#catppuccin\(@lightFlavor\);\s*\}\s*"
                      r"@media \(prefers-color-scheme: dark\) \{\s*#catppuccin\(@darkFlavor\);\s*\}\s*\}",
                      ":root { #catppuccin(mocha); }", text)
    if n != 1:
        sys.exit("the style's flavour picking changed")
    return functions(text)


# nixbook's own rules, after Catppuccin's: the parts of Gmail its style
# leaves (Gmail changed them), matched by role and structure rather than
# Gmail's class names where they can be. Placeholders as in the template.
EXTRA = """
/* nixbook additions (scripts/gmail-template.py's EXTRA) */
/* Compose: the message body's container (.qz.aiL), white under the
 * editor Catppuccin darkens: a white band showed between the text and the
 * formatting toolbar. */
:root .qz.aiL {
  background-color: {{colors.surface.default.hex}} !important;
}
/* Compose: text given its own colour (a signature made for white paper)
 * shown in the theme's text colour, links in its accent. Only how it is
 * shown while writing: the mail sent keeps its colours. (Not skipping text
 * with a background: pasted signatures carry background-color:
 * transparent on every span.) */
:root [contenteditable="true"][role="textbox"] [style*="color"]:not(a),
:root [contenteditable="true"][role="textbox"] font[color] {
  color: {{colors.on_surface_variant.default.hex}} !important;
}
:root [contenteditable="true"][role="textbox"] a,
:root [contenteditable="true"][role="textbox"] a * {
  color: {{colors.primary.default.hex}} !important;
}
"""


def placeholders(css):
    # Their userstyle header (its @name, @var…): this file has its own.
    css = re.sub(r"/\* ==UserStyle==.*?==/UserStyle== \*/\n?", "", css, count=1, flags=re.S)
    css = css.replace("/* deno-fmt-ignore */\n", "")
    for name in NAMES:
        role = ROLES[name]
        mark = MARK[name][1:]
        # In the logo's data: URL (escaped): no "#" there.
        css = re.sub(rf"%23{mark}\b", f"rgb({{{{colors.{role}.default.red}}}}%2C{{{{colors.{role}.default.green}}}}"
                     f"%2C{{{{colors.{role}.default.blue}}}})", css, flags=re.I)
        css = re.sub(rf"#{mark}\b", f"{{{{colors.{role}.default.hex}}}}", css, flags=re.I)
        css = css.replace(f"GRAY_{name})", f"{{{{colors.{role}.default.gray}}}})")
    if re.search(r"fe00[0-9a-f]{2}", css, re.I) or "GRAY_" in css:
        sys.exit("a marker colour is left in the CSS")
    return css


def main():
    if not shutil_which("lessc"):
        sys.exit("needs lessc: nix shell -f '<nixpkgs>' lessc -c python3 scripts/gmail-template.py")
    less = style_less(fetch(STYLE), lib_less(functions(fetch(LIB))))
    with tempfile.NamedTemporaryFile("w", suffix=".less", delete=False) as f:
        f.write(less)
    try:
        css = subprocess.run(["lessc", f.name], capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError as e:
        sys.exit(f"lessc failed: {e.stderr}")
    finally:
        os.unlink(f.name)
    header = (
        "/* nixbook-shell: Gmail (in Meru) recoloured from the shell's palette. Generated by\n"
        " * scripts/gmail-template.py from Catppuccin's Gmail userstyle\n"
        f" * (github.com/catppuccin/userstyles, {REV[:12]}, styles/gmail;\n"
        " * MIT License, Copyright (c) 2021 Catppuccin): edit that script, not this\n"
        " * file. Put in each Gmail page of Meru by its Electron bridge\n"
        " * (electron-bridge.py's `style`, called by apply-app-colors.sh when the\n"
        " * palette changes) and again after each load. */\n\n"
    )
    with open(OUT, "w") as f:
        f.write(header + placeholders(css) + EXTRA)
    print(f"wrote {os.path.normpath(OUT)}")


def shutil_which(cmd):
    import shutil
    return shutil.which(cmd)


if __name__ == "__main__":
    main()
