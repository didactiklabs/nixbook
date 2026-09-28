# The Momonga cursor on this machine (assets/cursors/Momonga, an Xcursor theme
# converted from its Windows .cur files: 24 to 192 px, the usual cursor-name
# aliases, Adwaita for the rest). Overrides the shared Stylix cursor
# (homeManagerModules/stylixConfig.nix) and gtkConfig's GTK cursor settings.
{ pkgs, lib, ... }:
let
  momonga-cursor = pkgs.stdenvNoCC.mkDerivation {
    pname = "momonga-cursor";
    version = "1.0";
    src = ../assets/cursors/Momonga;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/share/icons/Momonga
      cp -a . $out/share/icons/Momonga/
    '';
  };
  size = 32;
in
{
  # home.pointerCursor (Wayland, X11, GTK) through Stylix.
  stylix.cursor = lib.mkForce {
    package = momonga-cursor;
    name = "Momonga";
    inherit size;
  };
  gtk.gtk3.extraConfig = {
    gtk-cursor-theme-name = lib.mkForce "Momonga";
    gtk-cursor-theme-size = lib.mkForce size;
  };
  # gtkrc-2.0: the last assignment wins.
  gtk.gtk2.extraConfig = lib.mkAfter ''
    gtk-cursor-theme-name="Momonga"
    gtk-cursor-theme-size=${toString size}
  '';
}
