{
  pkgs,
  sources,
  ...
}:
let
  ds4drv = pkgs.python313Packages.ds4drv.overrideAttrs (oldAttrs: {
    src = sources.ds4drv;
  });
  ginx = import ../customPkgs/ginx.nix { inherit pkgs; };
  osupdate = pkgs.writeShellScriptBin "osupdate" ''
    set -euo pipefail
    echo last applied revisions: $(${pkgs.jq}/bin/jq .rev /etc/nixos/version)
    echo applying revision: "$(${pkgs.git}/bin/git ls-remote https://github.com/didactiklabs/nixbook HEAD | awk '{print $1}')"...

    echo Running ginx...
    ${ginx}/bin/ginx --source https://github.com/didactiklabs/nixbook -b main --now -- ${pkgs.colmena}/bin/colmena apply-local --sudo
  '';
in
{
  environment.systemPackages = with pkgs; [
    accountsservice
    wlsunset
    cups-pk-helper
    ginx
    sshfs
    lsof
    osupdate
    ds4drv
    efibootmgr
    colmena
    tailscale
    update-systemd-resolved
    gnupg
    pinentry-qt
    wget
    devbox
    go-task
    runme
    # usb mount auto
    usbutils
    udiskie
    udisks
    # yubikey
    yubico-piv-tool
    yubico-pam
    yubioath-flutter
    yubikey-personalization
    npins
  ];

  services.udev = {
    packages = with pkgs; [
      game-devices-udev-rules
      yubikey-personalization
    ];
    extraRules = ''
      KERNEL=="uinput", MODE="0666"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0666"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:054C:05C4.*", MODE="0666"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0666"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="0005:054C:09CC.*", MODE="0666"
    '';
  };

  systemd.user.services.ds4drv = {
    enable = true;
    description = "Controller Support.";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${ds4drv}/bin/ds4drv --hidraw --emulate-xpad";
      Restart = "always";
    };
  };

  programs = {
    kdeconnect.enable = true;
    yubikey-touch-detector.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true; # yubikey ssh
      pinentryPackage = pkgs.pinentry-qt;
    };
  };
}
