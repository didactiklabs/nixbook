{
  config,
  pkgs,
  lib,
  ...
}:
let
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
    shutdown='  Shutdown'
    reboot='  Reboot'
    suspend='  Suspend'
    lock='  Lock'
    logout='  Logout'
    yes='  Yes'
    no='  No'

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
    	echo -e "$lock\n$suspend\n$logout\n$reboot\n$shutdown" | rofi_cmd
    }
    # Execute Command
    run_cmd() {
    	selected="$(confirm_exit)"
    	if [[ "$selected" == "$yes" ]]; then
    		if [[ $1 == '--shutdown' ]]; then
    			systemctl poweroff
    		elif [[ $1 == '--reboot' ]]; then
    			systemctl reboot
            elif [[ $1 == '--suspend' ]]; then
                systemctl suspend
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
    $suspend)
        run_cmd --suspend
        ;;
    esac
  '';

  # Local rofi themes - no external dependencies
  rofi-themes = pkgs.runCommand "rofi-themes-5rows" { 
    # Force rebuild when source changes
    buildInputs = [ pkgs.coreutils ];
  } ''
    mkdir -p $out/files
    cp -r ${../assets/rofi}/* $out/files/
    
    # Make files writable and update colors with stylix theme
    chmod -R u+w $out/files
    cat > $out/files/colors/onedark.rasi <<EOF
      * {
        background:     #${config.lib.stylix.colors.base00};
        background-alt: #${config.lib.stylix.colors.base01};
        foreground:     #${config.lib.stylix.colors.base07};
        selected:       #${config.lib.stylix.colors.base05};
        active:         #${config.lib.stylix.colors.base03};
        urgent:         #${config.lib.stylix.colors.base04};
      }
    EOF
  '';
in
{
  # Local rofi configuration - self-contained without external GitHub dependencies
  config = lib.mkIf cfg.rofiConfig.enable {
    home = {
      packages = [ pkgs.rofi-wayland ];
      file.".config/rofi".source = "${rofi-themes}/files";
      # Define the Nix derivation to create the script file
      file.".config/rofiScripts/rofiLockScript.sh" = {
        text = rofiLockScript;
        executable = true;
      };
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
  };
}
