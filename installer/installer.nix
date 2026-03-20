{
  pkgs,
  lib,
  config,
  ...
}:
let
  nixbookSource = lib.cleanSource ../.;
in
{
  config.system.build.scripts = {
    installer = pkgs.writeScriptBin "installer" ''
      set -euo pipefail
      set +H
      export PATH="$PATH:${
        lib.makeBinPath (
          with pkgs;
          [
            hwinfo
            gawk
            gnused
            busybox
            openssl
            dosfstools
            e2fsprogs
            gawk
            gptfdisk
            lvm2
            nixos-install-tools
            util-linux
            config.nix.package
            gum
            git
          ]
        )
      }"

      clear
      echo "Welcome to the Nixbook Interactive Installer!"
      echo ""

      #### DISK SELECTION
      echo "Available disks:"
      DISKS=()
      for i in $(lsblk -pln -o NAME,TYPE | grep disk | awk '{ print $1 }'); do
        if [[ "$i" != "/dev/fd0" ]]; then
          DISKS+=("$i")
        fi
      done

      if [ ''${#DISKS[@]} -eq 0 ]; then
        echo "ERROR: No usable disk found on this machine!"
        exit 1
      fi

      TARGET_DISK=$(gum choose "''${DISKS[@]}")
      if [ -z "$TARGET_DISK" ]; then
        echo "No disk selected. Exiting."
        exit 1
      fi

      echo "Selected disk: $TARGET_DISK"

      #### HOSTNAME SELECTION
      TARGET_HOSTNAME=$(gum input --placeholder "Enter target hostname (e.g. totoro, anya, hephaestus)")
      if [ -z "$TARGET_HOSTNAME" ]; then
        echo "Hostname cannot be empty. Exiting."
        exit 1
      fi

      #### ENCRYPTION
      USE_LUKS=$(gum choose "Yes, encrypt disk (LUKS)" "No, do not encrypt")
      if [[ "$USE_LUKS" == "Yes"* ]]; then
        IFS= read -r -s -p "Enter LUKS password: " LUKS_PASS
        echo
        IFS= read -r -s -p "Confirm LUKS password: " LUKS_PASS_CONFIRM
        echo
        if [ "$LUKS_PASS" != "$LUKS_PASS_CONFIRM" ]; then
          echo "Passwords do not match. Exiting."
          exit 1
        fi
        printf '%s' "$LUKS_PASS" > /tmp/luks-pass
        unset LUKS_PASS LUKS_PASS_CONFIRM
        echo "Encryption enabled."
      else
        echo "Encryption disabled."
      fi

      #### USER CONFIGURATION
      echo "Let's configure the main user for the new system."
      while true; do
        TARGET_USER=$(gum input --placeholder "Enter username for the new system" || true)
        if [ -n "$TARGET_USER" ]; then
          break
        fi
        echo "Username cannot be empty."
      done

      while true; do
        TARGET_PASSWORD=$(gum input --password --placeholder "Enter password for $TARGET_USER" || true)
        TARGET_PASSWORD_CONFIRM=$(gum input --password --placeholder "Confirm password for $TARGET_USER" || true)

        if [ -n "$TARGET_PASSWORD" ] && [ "$TARGET_PASSWORD" = "$TARGET_PASSWORD_CONFIRM" ]; then
          break
        fi
        echo "Passwords do not match or are empty. Please try again."
      done

       USER_PASSWORD_HASH=$(printf '%s' "$TARGET_PASSWORD" | openssl passwd -6 -stdin)

      #### PARTITION SELECTION
      echo "Let's configure your partitions (Logical Volumes). You must define at least a root (/) partition."

      HAS_ROOT=0
      LVM_LVS=""
      while true; do
        if [ -n "$LVM_LVS" ]; then
          if ! gum confirm "Add another partition?"; then
            if [ "$HAS_ROOT" -eq 1 ]; then
              break
            else
              echo "You must configure a root (/) partition before continuing."
              sleep 2
              continue
            fi
          fi
        fi

        PART_NAME=$(gum input --placeholder "Partition name (e.g. root, var, nix, swap)" || true)
        if [ -z "$PART_NAME" ]; then
          if [ -n "$LVM_LVS" ] && [ "$HAS_ROOT" -eq 1 ]; then
            break
          elif [ -n "$LVM_LVS" ] && [ "$HAS_ROOT" -eq 0 ]; then
            echo "You must configure a root (/) partition before continuing."
            sleep 2
            continue
          else
            continue
          fi
        fi

        PART_SIZE=$(gum input --placeholder "Size (e.g. 20G, 100G, 100%FREE)" || true)
        if [ -z "$PART_SIZE" ]; then
          echo "Cancelled adding partition."
          sleep 1
          continue
        fi

        PART_TYPE=$(gum choose "ext4" "xfs" "btrfs" "swap" || true)
        if [ -z "$PART_TYPE" ]; then
          echo "Cancelled adding partition."
          sleep 1
          continue
        fi

        if [ "$PART_TYPE" != "swap" ]; then
          PART_MOUNT=$(gum input --placeholder "Mountpoint (e.g. /, /var, /home)" || true)
          if [ -z "$PART_MOUNT" ]; then
            echo "Cancelled adding partition."
            sleep 1
            continue
          fi

          if [ "$PART_MOUNT" = "/" ]; then
            HAS_ROOT=1
          fi

          LVM_LVS="$LVM_LVS
            $PART_NAME = {
              size = \"$PART_SIZE\";
              content = {
                type = \"filesystem\";
                format = \"$PART_TYPE\";
                mountpoint = \"$PART_MOUNT\";
                mountOptions = [ \"noatime\" ];
                extraArgs = [ \"-L\" \"$PART_NAME\" ];
              };
            };"
        else
          LVM_LVS="$LVM_LVS
            $PART_NAME = {
              size = \"$PART_SIZE\";
              content = {
                type = \"swap\";
                discardPolicy = \"both\";
                resumeDevice = true;
              };
            };"
        fi
      done

       echo "Generating disko configuration..."

       # Get persistent disk identifier (use by-id if available, otherwise use device path)
       DISK_ID=""
       for link in /dev/disk/by-id/*; do
         case "$link" in *-part*) continue;; esac
         if [ "$(readlink -f "$link")" = "$(readlink -f "$TARGET_DISK")" ]; then
           DISK_ID="$link"
           break
         fi
       done
       if [ -z "$DISK_ID" ]; then
         DISK_ID="$TARGET_DISK"
       fi

       echo "Using disk identifier: $DISK_ID"

       echo "{
         disko.devices = {
           disk.main = {
             type = \"disk\";
             device = \"$DISK_ID\";
             content = {
               type = \"gpt\";
               partitions = {
                 ESP = {
                   size = \"512M\";
                   type = \"EF00\";
                   priority = 1;
                   content = {
                     type = \"filesystem\";
                     format = \"vfat\";
                     mountpoint = \"/boot\";
                     mountOptions = [ \"defaults\" ];
                     extraArgs = [ \"-n\" \"BOOT\" ];
                   };
                 };
                 primary = {
                   size = \"100%\";
                    content = $(if [[ "$USE_LUKS" == "Yes"* ]]; then echo '{
                      type = "luks";
                      name = "crypted";
                      passwordFile = "/tmp/luks-pass";
                      settings = {
                        allowDiscards = true;
                      };
                      content = {
                        type = "lvm_pv";
                        vg = "vg1";
                      };
                    }'; else echo '{
                      type = "lvm_pv";
                      vg = "vg1";
                    }'; fi);
                 };
               };
             };
           };
           lvm_vg = {
             vg1 = {
               type = \"lvm_vg\";
               lvs = {
       $LVM_LVS
               };
             };
           };
         };
       }" > /tmp/disko.nix

      echo "Formatting and mounting disk..."
      # Unmount everything first just in case
      umount -R /mnt || true
      swapoff -a || true

      # Close any existing LUKS/LVM on this disk
      for dm in /dev/mapper/vg1-*; do
        [ -e "$dm" ] && dmsetup remove "$dm" || true
      done
      vgchange -an || true
      [ -e /dev/mapper/crypted ] && cryptsetup close crypted || true

      # Remove LVM volume groups that lived on this disk
      for pv in $(pvs --noheadings -o pv_name,vg_name 2>/dev/null | grep "$TARGET_DISK" | awk '{print $2}' || true); do
        [ -n "$pv" ] && vgremove -ff "$pv" || true
      done
      pvremove -ff "''${TARGET_DISK}"* || true

      # Wipe all signatures, partition table, and zero entire disk
      wipefs -af "$TARGET_DISK" || true
      for part in "''${TARGET_DISK}"p* "''${TARGET_DISK}"[0-9]*; do
        [ -e "$part" ] && wipefs -af "$part" || true
      done
      sgdisk --zap-all "$TARGET_DISK" || true
      blkdiscard "$TARGET_DISK" 2>/dev/null || dd if=/dev/zero of="$TARGET_DISK" bs=1M status=progress 2>/dev/null || true
      partprobe "$TARGET_DISK" || true

       ${pkgs.disko}/bin/disko --mode disko /tmp/disko.nix

       echo "Preparing bootstrap environment..."
       mkdir -p /mnt/etc/nixos

       echo "Copying bootstrap configuration..."

       cp /tmp/disko.nix /mnt/etc/nixos/disko-config.nix
       cp -r ${nixbookSource}/npins /mnt/etc/nixos/
       cp -r ${nixbookSource}/customPkgs /mnt/etc/nixos/
       cp ${nixbookSource}/installer/bootstrap-module.nix /mnt/etc/nixos/bootstrap-module.nix

             # Generate hardware-configuration.nix without fileSystems for bootstrap
             # disko handles fileSystems, LVM, and LUKS for the first boot
             echo "Generating hardware configuration..."
             nixos-generate-config --no-filesystems --root /mnt

       echo "{ config, pkgs, ... }:
       {
         imports = [
           ./bootstrap-module.nix
         ];
         networking.hostName = \"$TARGET_HOSTNAME\";
       }" > /mnt/etc/nixos/configuration.nix

       echo "Installing NixOS..."
       nixos-install --root /mnt --no-root-password

      echo "Configuring user imperatively..."
      nixos-enter --root /mnt -c "useradd -m -G wheel \"$TARGET_USER\" || true"
       printf '%s:%s\n' "$TARGET_USER" "$USER_PASSWORD_HASH" | nixos-enter --root /mnt -c "chpasswd -e"

      echo "Installation complete!"
      gum confirm "Reboot now?" && reboot
    '';
  };
}
