{ pkgs, ... }:
let
  # anya's firmware starts "Linux Boot Manager" (systemd-boot) whatever boot
  # order is set from an OS: `efibootmgr -o` was put back at the next boot, and
  # its setup screen lists no Windows entry. So Windows is made the default
  # inside systemd-boot's own menu, in loader.conf (not with
  # `bootctl set-default`: that EFI variable wins over loader.conf, and Windows
  # has no simple way to write it).
  #
  # NixOS is reached from Windows with linux.bat (linux.bat in this directory),
  # which copies loader-linux.conf (the loader.conf NixOS's installer wrote,
  # default = the current generation) over loader.conf and restarts. The
  # service below puts Windows back as the default at each NixOS boot, so that
  # choice lasts one boot.
  windowsFirst = pkgs.writeShellScript "boot-windows-first" ''
    set -eu
    PATH=${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin
    conf=/boot/loader/loader.conf
    [ -f "$conf" ] || exit 0
    # Without Windows on this partition the menu has no auto-windows entry.
    [ -e /boot/EFI/Microsoft/Boot/bootmgfw.efi ] || exit 0
    if grep -q '^default nixos-' "$conf"; then
      cp "$conf" /boot/loader/loader-linux.conf.tmp
      mv /boot/loader/loader-linux.conf.tmp /boot/loader/loader-linux.conf
    fi
    sed 's/^default .*/default auto-windows/' "$conf" > "$conf.tmp"
    grep -q '^default ' "$conf.tmp" || echo 'default auto-windows' >> "$conf.tmp"
    mv "$conf.tmp" "$conf"
  '';
  # A restart that comes back to NixOS (after an update, or from a remote
  # session: Windows has no ssh nor Sunshine).
  rebootLinux = pkgs.writeShellScriptBin "reboot-linux" ''
    set -eu
    id=$(sudo sed -n 's/^default //p' /boot/loader/loader-linux.conf)
    [ -n "$id" ] || { echo "reboot-linux: no NixOS entry in /boot/loader/loader-linux.conf" >&2; exit 1; }
    exec systemctl reboot --boot-loader-entry="$id"
  '';
in
{
  environment.systemPackages = [ rebootLinux ];
  # After each bootloader install (every switch rewrites loader.conf).
  boot.loader.systemd-boot.extraInstallCommands = ''
    ${windowsFirst}
  '';
  systemd.services.boot-windows-first = {
    description = "Make Windows the boot menu's default again";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = "/boot";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = windowsFirst;
    };
  };
}
