{
  pkgs,
  lib,
  config,
  ...
}:
{
  config.system.build.scripts = {
    installer = pkgs.writeShellScriptBin "installer" ''
      set -euo pipefail
      set +H
      export PATH="$PATH:${
        lib.makeBinPath (
          with pkgs;
          [
            hwinfo
            gawk
            gnused
            gnugrep
            coreutils
            openssl
            dosfstools
            e2fsprogs
            gptfdisk
            lvm2
            cryptsetup
            nixos-install-tools
            util-linux
            kbd
            jq
            config.nix.package
            gum
            git
          ]
        )
      }"
      # The profiles' nixpkgs instance allows unfree packages; colmena runs are
      # made with this set too.
      export NIXPKGS_ALLOW_UNFREE=1

      REPO_URL="''${NIXBOOK_REPO:-https://github.com/didactiklabs/nixbook}"
      BRANCH="''${NIXBOOK_BRANCH:-main}"
      WORK=/tmp/nixbook-installer
      REPO="$WORK/nixbook"
      LOG="$WORK/install.log"
      COLMENA_SRC="${pkgs.colmena.src}"
      EVAL_HOST="${./eval-host.nix}"

      umask 077
      mkdir -p "$WORK"

      title() { gum style --bold --foreground 212 "$*"; }
      warn() { gum style --foreground 214 "$*"; }
      die() {
        gum style --foreground 196 "ERROR: $*" >&2
        exit 1
      }
      # Runs a command (or shell function) behind a spinner; its stderr goes to
      # the log, whose tail is shown if it fails.
      spin() {
        local label="$1" pid
        shift
        echo "== $label" >>"$LOG"
        "$@" 2>>"$LOG" &
        pid=$!
        gum spin --title "$label" -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 0.2; done"
        if ! wait "$pid"; then
          tail -n 30 "$LOG" >&2
          die "$label failed (full log: $LOG)"
        fi
      }
      evalHostInfo() {
        nix-instantiate --eval --strict --json "$EVAL_HOST" -A info \
          --argstr repo "$REPO" --argstr host "$TARGET_HOSTNAME" --argstr colmenaSrc "$COLMENA_SRC" \
          >"$WORK/host.json"
      }

      clear
      gum style --border rounded --padding "1 2" --border-foreground 212 \
        "Nixbook installer" "" \
        "Installs one of the nixbook machines on this computer," \
        "ready to use after a single reboot."

      #### NETWORK
      # Everything is downloaded: the configuration and the packages.
      until git ls-remote --exit-code --heads "$REPO_URL" "$BRANCH" >/dev/null 2>&1; do
        warn "Cannot reach $REPO_URL (branch $BRANCH)."
        case $(gum choose --header "An internet connection is required." \
          "Connect to Wi-Fi" "Retry (plug in Ethernet first)" "Quit") in
          "Connect to Wi-Fi") nmtui-connect || true ;;
          Retry*) ;;
          *) exit 1 ;;
        esac
      done

      rm -rf "$REPO"
      spin "Downloading the nixbook configuration ($BRANCH)" \
        git clone --quiet --branch "$BRANCH" "$REPO_URL" "$REPO"

      #### MACHINE
      mapfile -t HOSTS < <(nix-instantiate --eval --json -E \
        "builtins.attrNames (removeAttrs (import $REPO/hive.nix) [ \"meta\" \"defaults\" ])" |
        jq -r '.[]')
      [ ''${#HOSTS[@]} -gt 0 ] || die "No machine found in $REPO/hive.nix"
      TARGET_HOSTNAME=$(gum choose --header "Which machine is this?" "''${HOSTS[@]}")
      [ -n "$TARGET_HOSTNAME" ] || exit 1

      # Read the machine's keymap and accounts before anything is erased. The
      # real hardware configuration only exists after partitioning: evaluate
      # with a stand-in (neither depends on it).
      cat >"$WORK/hardware-stub.nix" <<'EOF'
      {
        fileSystems."/" = { device = "/dev/disk/by-label/root"; fsType = "ext4"; };
        fileSystems."/boot" = { device = "/dev/disk/by-label/BOOT"; fsType = "vfat"; };
        nixpkgs.hostPlatform = "x86_64-linux";
      }
      EOF
      export NIXBOOK_HARDWARE_CONFIG="$WORK/hardware-stub.nix"
      spin "Reading the $TARGET_HOSTNAME configuration" evalHostInfo
      KEYMAP=$(jq -r .keyMap "$WORK/host.json")
      mapfile -t USERS < <(jq -r '.users[]' "$WORK/host.json")

      # Type passphrases in the layout the machine boots with: the initrd asks
      # for the LUKS passphrase with the profile's console keymap.
      loadkeys "$KEYMAP" >/dev/null 2>&1 || warn "Could not load keymap $KEYMAP."
      echo "Keyboard layout set to $KEYMAP (the one $TARGET_HOSTNAME uses)."

      #### DISK
      # Whole disks only, without the installer's own boot media.
      BOOT_MEDIA=""
      if ISO_SRC=$(findmnt -nvo SOURCE /iso 2>/dev/null); then
        BOOT_MEDIA=$(lsblk -dpno PKNAME "$ISO_SRC" 2>/dev/null || true)
        [ -n "$BOOT_MEDIA" ] || BOOT_MEDIA="$ISO_SRC"
      fi
      DISK_CHOICES=()
      while read -r name type ro size model; do
        [ "$type" = disk ] && [ "$ro" = 0 ] || continue
        case "$name" in /dev/zram* | /dev/loop* | /dev/fd* | /dev/sr*) continue ;; esac
        [ "$name" != "$BOOT_MEDIA" ] || continue
        DISK_CHOICES+=("$name  $size  $(printf '%b' "$model")")
      done < <(lsblk -dpnr -o NAME,TYPE,RO,SIZE,MODEL)
      [ ''${#DISK_CHOICES[@]} -gt 0 ] || die "No usable disk found on this machine."
      TARGET_DISK=$(gum choose --header "Install on which disk? (it will be erased)" "''${DISK_CHOICES[@]}")
      TARGET_DISK=''${TARGET_DISK%% *}
      [ -n "$TARGET_DISK" ] || exit 1

      #### ENCRYPTION
      USE_LUKS=0
      if gum confirm "Encrypt the disk (LUKS)? You will type the passphrase at every boot."; then
        USE_LUKS=1
        while true; do
          LUKS_PASS=$(gum input --password --header "Disk passphrase (keyboard: $KEYMAP)" || true)
          LUKS_PASS_CONFIRM=$(gum input --password --header "Confirm the disk passphrase" || true)
          if [ -n "$LUKS_PASS" ] && [ "$LUKS_PASS" = "$LUKS_PASS_CONFIRM" ]; then
            break
          fi
          warn "The passphrases are empty or do not match, try again."
        done
        printf '%s' "$LUKS_PASS" >"$WORK/luks-pass"
        unset LUKS_PASS LUKS_PASS_CONFIRM
      fi

      #### PARTITIONS (LVM logical volumes)
      # Swap the size of the RAM (hibernation), at most a quarter of the disk.
      SWAP_GB=$(awk '/MemTotal/ { printf "%d", ($2 / 1048576) + 0.999 }' /proc/meminfo)
      DISK_GB=$(($(lsblk -bdno SIZE "$TARGET_DISK") / 1073741824))
      if [ "$SWAP_GB" -gt $((DISK_GB / 4)) ]; then SWAP_GB=$((DISK_GB / 4)); fi
      if [ "$SWAP_GB" -lt 1 ]; then SWAP_GB=1; fi
      LVM_LVS=""
      LV_SUMMARY=""
      addLv() { # name size type [mountpoint]
        if [ "$3" = swap ]; then
          LVM_LVS+="
                $1 = {
                  size = \"$2\";
                  content = {
                    type = \"swap\";
                    discardPolicy = \"both\";
                    resumeDevice = true;
                  };
                };"
        else
          LVM_LVS+="
                $1 = {
                  size = \"$2\";
                  content = {
                    type = \"filesystem\";
                    format = \"$3\";
                    mountpoint = \"$4\";
                    mountOptions = [ \"noatime\" ];
                    extraArgs = [ \"-L\" \"$1\" ];
                  };
                };"
        fi
        LV_SUMMARY+="  $1: $2 $3 ''${4:-}"$'\n'
      }

      LAYOUT=$(gum choose --header "Partition layout" \
        "Recommended: ''${SWAP_GB}G swap, ext4 / on the rest of the disk" \
        "Custom")
      if [[ "$LAYOUT" == Recommended* ]]; then
        addLv swap "''${SWAP_GB}G" swap
        addLv root "100%FREE" ext4 /
      else
        echo "Define the logical volumes; a root (/) volume is required."
        HAS_ROOT=0
        USED_NAMES=" "
        USED_MOUNTS=" "
        while true; do
          if [ -n "$LVM_LVS" ] && ! gum confirm "Add another volume?"; then
            [ "$HAS_ROOT" -eq 1 ] && break
            warn "A root (/) volume is required."
            continue
          fi
          PART_NAME=$(gum input --placeholder "Volume name (e.g. root, home, swap)" || true)
          if ! [[ "$PART_NAME" =~ ^[a-z][a-z0-9_]{0,11}$ ]] || [[ "$USED_NAMES" == *" $PART_NAME "* ]]; then
            warn "Use a new name of 1-12 lowercase letters, digits or _."
            continue
          fi
          PART_SIZE=$(gum input --placeholder "Size (e.g. 20G, 512M, 100%FREE for the rest)" || true)
          if ! [[ "$PART_SIZE" =~ ^([0-9]+[KMGT]|[0-9]{1,3}%(FREE|VG))$ ]]; then
            warn "Use a size like 20G, 512M or 100%FREE."
            continue
          fi
          PART_TYPE=$(gum choose --header "File system" ext4 xfs btrfs swap || true)
          [ -n "$PART_TYPE" ] || continue
          PART_MOUNT=""
          if [ "$PART_TYPE" != swap ]; then
            PART_MOUNT=$(gum input --placeholder "Mount point (e.g. /, /home, /var)" || true)
            if ! [[ "$PART_MOUNT" =~ ^/[A-Za-z0-9/._-]*$ ]] || [[ "$USED_MOUNTS" == *" $PART_MOUNT "* ]]; then
              warn "Use a new absolute mount point like /home."
              continue
            fi
            [ "$PART_MOUNT" != / ] || HAS_ROOT=1
            USED_MOUNTS+="$PART_MOUNT "
          fi
          USED_NAMES+="$PART_NAME "
          addLv "$PART_NAME" "$PART_SIZE" "$PART_TYPE" "$PART_MOUNT"
        done
      fi

      #### ACCOUNTS
      declare -A PASSWORD_HASHES=()
      for user in "''${USERS[@]}"; do
        while true; do
          PASS=$(gum input --password --header "Password for $user" || true)
          PASS_CONFIRM=$(gum input --password --header "Confirm the password for $user" || true)
          if [ -n "$PASS" ] && [ "$PASS" = "$PASS_CONFIRM" ]; then
            break
          fi
          warn "The passwords are empty or do not match, try again."
        done
        PASSWORD_HASHES[$user]=$(printf '%s' "$PASS" | openssl passwd -6 -stdin)
        unset PASS PASS_CONFIRM
      done

      #### CONFIRM
      gum style --border rounded --padding "0 1" \
        "Machine:    $TARGET_HOSTNAME ($REPO_URL, $BRANCH)" \
        "Disk:       $TARGET_DISK  (ALL DATA WILL BE ERASED)" \
        "Encryption: $([ "$USE_LUKS" -eq 1 ] && echo LUKS || echo none)" \
        "Accounts:   ''${USERS[*]:-none}" \
        "Volumes:" "$LV_SUMMARY"
      gum confirm --default=false "Erase $TARGET_DISK and install $TARGET_HOSTNAME?" || exit 1

      #### From here on, nothing is asked until the reboot.
      trap 'warn "Installation failed. Log: $LOG. Run \"sudo installer\" to start again."' ERR

      if [ "$USE_LUKS" -eq 1 ]; then
        PRIMARY_CONTENT='{
                      type = "luks";
                      name = "crypted";
                      passwordFile = "'"$WORK/luks-pass"'";
                      settings.allowDiscards = true;
                      content = {
                        type = "lvm_pv";
                        vg = "vg1";
                      };
                    }'
      else
        PRIMARY_CONTENT='{
                      type = "lvm_pv";
                      vg = "vg1";
                    }'
      fi

      # Persistent disk identifier when there is one.
      DISK_ID="$TARGET_DISK"
      for link in /dev/disk/by-id/*; do
        case "$link" in *-part*) continue ;; esac
        if [ "$(readlink -f "$link")" = "$(readlink -f "$TARGET_DISK")" ]; then
          DISK_ID="$link"
          break
        fi
      done

      cat >"$WORK/disko.nix" <<EOF
      {
        disko.devices = {
          disk.main = {
            type = "disk";
            device = "$DISK_ID";
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  size = "512M";
                  type = "EF00";
                  priority = 1;
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                    # Root-only: bootctl refuses a world-readable random seed.
                    mountOptions = [ "fmask=0077" "dmask=0077" ];
                    extraArgs = [ "-n" "BOOT" ];
                  };
                };
                primary = {
                  size = "100%";
                  content = $PRIMARY_CONTENT;
                };
              };
            };
          };
          lvm_vg.vg1 = {
            type = "lvm_vg";
            lvs = {$LVM_LVS
            };
          };
        };
      }
      EOF

      title "Erasing $TARGET_DISK..."
      umount -R /mnt 2>/dev/null || true
      swapoff -a || true
      vgchange -an >/dev/null 2>&1 || true
      if [ -e /dev/mapper/crypted ]; then cryptsetup close crypted || true; fi
      for vg in $(pvs --noheadings -o pv_name,vg_name 2>/dev/null | grep "$TARGET_DISK" | awk '{print $2}' || true); do
        vgremove -ff "$vg" || true
      done
      for part in $(lsblk -lnpo NAME "$TARGET_DISK" | tail -n +2); do
        wipefs -af "$part" >/dev/null 2>&1 || true
      done
      wipefs -af "$TARGET_DISK" >/dev/null || true
      sgdisk --zap-all "$TARGET_DISK" >/dev/null || true
      # Fast on SSDs; disks without discard support are fine after the wipe above.
      blkdiscard -f "$TARGET_DISK" 2>/dev/null || true
      partprobe "$TARGET_DISK" || true

      title "Partitioning and formatting..."
      ${pkgs.disko}/bin/disko --mode disko "$WORK/disko.nix" 2>&1 | tee -a "$LOG"

      title "Detecting the hardware..."
      nixos-generate-config --root /mnt 2>&1 | tee -a "$LOG"
      # Only the hardware configuration is used (base.nix imports it).
      rm -f /mnt/etc/nixos/configuration.nix
      HW=/mnt/etc/nixos/hardware-configuration.nix
      if [ "$USE_LUKS" -eq 1 ]; then
        # nixos-generate-config does not see LUKS under LVM: it only checks
        # the file systems' own device mapper parents.
        LUKS_DEV=$(cryptsetup status crypted | awk '/device:/ { print $2 }')
        LUKS_UUID=$(blkid -s UUID -o value "$LUKS_DEV")
        [ -n "$LUKS_UUID" ] || die "Could not find the UUID of the LUKS partition."
        sed -i '/^}$/d' "$HW"
        cat >>"$HW" <<EOF
        boot.initrd.luks.devices."crypted" = {
          device = "/dev/disk/by-uuid/$LUKS_UUID";
          allowDiscards = true;
        };
      }
      EOF
      fi
      cat "$HW" >>"$LOG"

      title "Building $TARGET_HOSTNAME (this downloads and can take a while)..."
      export NIXBOOK_HARDWARE_CONFIG="$HW"
      # Built straight into the new disk's store: the live system's store is
      # in RAM.
      nix-build --store /mnt --out-link "$WORK/system" "$EVAL_HOST" -A toplevel \
        --argstr repo "$REPO" --argstr host "$TARGET_HOSTNAME" --argstr colmenaSrc "$COLMENA_SRC" \
        2>&1 | tee -a "$LOG"
      SYSTEM=$(readlink "$WORK/system")

      title "Installing..."
      nixos-install --root /mnt --system "$SYSTEM" --no-root-password 2>&1 | tee -a "$LOG"

      for user in "''${!PASSWORD_HASHES[@]}"; do
        printf '%s:%s\n' "$user" "''${PASSWORD_HASHES[$user]}" |
          nixos-enter --root /mnt --silent -c "chpasswd -e" ||
          warn "Could not set the password of $user: set it with 'passwd $user' as root."
      done

      rm -f "$WORK/luks-pass"
      mkdir -p /mnt/var/log
      cp "$LOG" /mnt/var/log/nixbook-install.log
      trap - ERR

      gum style --border rounded --padding "1 2" --border-foreground 42 \
        "$TARGET_HOSTNAME is installed." "" \
        "Remove the USB drive and reboot." \
        "With Secure Boot, the keys are enrolled over the first boots" \
        "(the machine reboots once by itself)."
      if gum confirm "Reboot now?"; then
        umount -R /mnt || true
        reboot
      fi
    '';
  };
}
