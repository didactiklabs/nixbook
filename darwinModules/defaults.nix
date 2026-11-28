# macOS preferences (System Settings) for a tiling window manager. Every value
# is a mkDefault: a profile sets its own over it.
{ lib, ... }:
{
  system.defaults = {
    # "Displays have separate Spaces": OmniWM needs it on (spans-displays is
    # its opposite), and AeroSpace's docs recommend the same. Takes effect
    # after logging out once.
    spaces.spans-displays = lib.mkDefault false;
    dock = {
      autohide = lib.mkDefault true;
      # Spaces keep their order (the window manager numbers them).
      mru-spaces = lib.mkDefault false;
      # Mission Control groups windows by app: easier to read with many
      # tiled windows.
      expose-group-apps = lib.mkDefault true;
      show-recents = lib.mkDefault false;
    };
    NSGlobalDomain = {
      AppleInterfaceStyle = lib.mkDefault "Dark";
      AppleShowAllExtensions = lib.mkDefault true;
      # Key repeat instead of the accent picker when a letter is held.
      ApplePressAndHoldEnabled = lib.mkDefault false;
      InitialKeyRepeat = lib.mkDefault 25;
      KeyRepeat = lib.mkDefault 2;
      # Windows move between tiles at once, no zoom animation on open.
      NSAutomaticWindowAnimationsEnabled = lib.mkDefault false;
    };
    finder = {
      ShowPathbar = lib.mkDefault true;
      FXPreferredViewStyle = lib.mkDefault "Nlsv";
      _FXShowPosixPathInTitle = lib.mkDefault true;
    };
    trackpad.Clicking = lib.mkDefault true;
    screencapture.location = lib.mkDefault "~/Pictures/Screenshots";
  };
}
