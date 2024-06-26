{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  loginctl = "${pkgs.systemd}/bin/loginctl";
  rofiLockScript = ''
    #!/usr/bin/env bash
    ## Available Styles
    ## style-1   style-2   style-3   style-4   style-5
    # usage runscript <style>
    # Current Theme
    dir="$HOME/.config/rofi/powermenu/type-1"
    theme=$1

    # CMDs
    uptime="$(uptime | awk '{print $1}')"
    host=$(hostname)

    # Options
    shutdown=' Shutdown'
    reboot=' Reboot'
    lock=' Lock'
    logout=' Logout'
    yes=' Yes'
    no=' No'

    # Rofi CMD
    rofi_cmd() {
    	rofi -dmenu \
    		-p "$host" \
    		-mesg "Uptime: $uptime" \
    		-theme $dir/$theme.rasi
    }

    # Confirmation CMD
    confirm_cmd() {
    	rofi -theme-str 'window {location: center; anchor: center; fullscreen: false; width: 250px;}' \
    		-theme-str 'mainbox {children: [ "message", "listview" ];}' \
    		-theme-str 'listview {columns: 2; lines: 1;}' \
    		-theme-str 'element-text {horizontal-align: 0.5;}' \
    		-theme-str 'textbox {horizontal-align: 0.5;}' \
    		-dmenu \
    		-p 'Confirmation' \
    		-mesg 'Are you Sure?' \
    		-theme $dir/$theme.rasi
    }
    # Ask for confirmation
    confirm_exit() {
    	echo -e "$yes\n$no" | confirm_cmd
    }
    # Pass variables to rofi dmenu
    run_rofi() {
    	echo -e "$lock\n$logout\n$reboot\n$shutdown" | rofi_cmd
    }
    # Execute Command
    run_cmd() {
    	selected="$(confirm_exit)"
    	if [[ "$selected" == "$yes" ]]; then
    		if [[ $1 == '--shutdown' ]]; then
    			systemctl poweroff
    		elif [[ $1 == '--reboot' ]]; then
    			systemctl reboot
    		fi
    	else
    		exit 0
    	fi
    }
    # Actions
    chosen="$(run_rofi)"
    case $chosen in
    $shutdown)
    	run_cmd --shutdown
    	;;
    $reboot)
    	run_cmd --reboot
    	;;
    $lock)
      ${loginctl} lock-session $XDG_SESSION_ID
      ;;
    $logout)
    	${loginctl} terminate-session self
    	;;
    esac
  '';
  rofi-repo = pkgs.fetchFromGitHub {
    owner = "adi1090x";
    repo = "rofi";
    rev = "master";
    sha256 = "sha256-G3sAyIZbq1sOJxf+NBlXMOtTMiBCn6Sat8PHryxRS0w=";
  };

  rofi-themes =
    pkgs.runCommand "rofi-themes" {
      buildInputs = [rofi-repo];
    } ''
      mkdir -p $out/files/colors
      cp -r ${rofi-repo}/files/applets $out/files
      cp -r ${rofi-repo}/files/images $out/files
      cp -r ${rofi-repo}/files/launchers $out/files
      cp -r ${rofi-repo}/files/powermenu $out/files
      cp -r ${rofi-repo}/files/scripts $out/files
      cp -r ${rofi-repo}/files/config.rasi $out/files
      cat > $out/files/colors/onedark.rasi <<EOF
        * {
          background:     rgba(0,0,0,0.3);
          background-alt: #${config.lib.stylix.colors.base01};
          foreground:     #${config.lib.stylix.colors.base07};
          selected:       #${config.lib.stylix.colors.base05};
          active:         #${config.lib.stylix.colors.base03};
          urgent:         #${config.lib.stylix.colors.base04};
        }
      EOF
    '';
in {
  # https://github.com/adi1090x/rofi
  config = lib.mkIf cfg.rofiConfig.enable {
    home.packages = [pkgs.rofi-wayland];
    home.file.".config/rofi".source = "${rofi-themes}/files";
    # Define the Nix derivation to create the script file
    home.file.".config/rofiScripts/rofiLockScript.sh" = {
      text = rofiLockScript;
      executable = true;
    };
  };

  options.customHomeManagerModules.rofiConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Rofi config globally or not.
      '';
    };
    launcher.type = lib.mkOption {
      type = lib.types.str;
      default = "type-1";
      description = ''
        Select launcher type.
      '';
    };
    launcher.style = lib.mkOption {
      type = lib.types.str;
      default = "style-1";
      description = ''
        Select launcher style.
      '';
    };
    powermenu.style = lib.mkOption {
      type = lib.types.str;
      default = "style-1";
      description = ''
        Select powermenu style.
      '';
    };
  };
}
