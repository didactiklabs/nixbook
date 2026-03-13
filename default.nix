{
  disk ? null,
  profile ? "totoro",
  ...
}:
let
  sources = import ./npins;
  pkgs = import sources.nixpkgs { };
  disko = import sources.disko { inherit (pkgs) lib; };

  isoInstall = import (sources.nixpkgs + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      ./installer/live-configuration.nix
    ];
    specialArgs = {
      inherit
        disko
        disk
        ;
    };
  };
  inherit (pkgs) lib;
in
rec {
  imports = [ <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix> ];
  inherit lib;
  buildIso =
    (isoInstall.extendModules {
      modules = [
        (sources.nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
        {
          isoImage.squashfsCompression = null;
        }
      ];
    }).config.system.build.isoImage;
  testVm = pkgs.writeScriptBin "test-iso-vm" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Create a 64GB virtual disk if it doesn't exist
    if [ ! -f test-disk.qcow2 ]; then
      echo "Creating 64GB test-disk.qcow2..."
      ${pkgs.qemu}/bin/qemu-img create -f qcow2 .tmp/test-disk.qcow2 64G
    fi

    # We need a writeable copy of the UEFI vars
    if [ ! -f OVMF_VARS.fd ]; then
      cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd ./.tmp
      chmod +w ./.tmp/OVMF_VARS.fd
    fi

    echo "Starting VM with ISO in UEFI mode..."
    ${pkgs.qemu}/bin/qemu-system-x86_64 \
      -enable-kvm \
      -m 4096 \
      -smp 4 \
      -drive if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd \
      -drive if=pflash,format=raw,file=.tmp/OVMF_VARS.fd \
      -cdrom ${buildIso}/iso/*.iso \
      -drive file=.tmp/test-disk.qcow2,format=qcow2,if=virtio \
      -boot d \
      -vga virtio \
      -device virtio-net,netdev=vmnic \
      -netdev user,id=vmnic,hostfwd=tcp::2222-:22 \
      "$@"
  '';
}
