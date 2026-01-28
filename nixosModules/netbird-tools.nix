{ pkgs, ... }:
let
  nswitch = pkgs.writeShellScriptBin "nswitch" ''
    # Get the list of available Networks
    networks=$(netbird networks list 2>/dev/null | grep "ID:" | awk '{print $3}')

    if [[ -z "$networks" ]]; then
      echo "No Netbird networks found or netbird not running."
      exit 1
    fi

    # Use fzf to select a Network
    selected_network=$(echo "$networks" | ${pkgs.fzf}/bin/fzf --prompt="Select Netbird Network> ")

    if [[ -z "$selected_network" ]]; then
      echo "No Network selected. Exiting."
      exit 1
    fi

    echo "Switching to Network: $selected_network..."

    if netbird network select "$selected_network"; then
       echo "Selected $selected_network."
       if netbird up; then
         echo "Successfully brought up netbird."
       else
         echo "Failed to bring up netbird."
         exit 1
       fi
    else
      echo "Failed to select $selected_network."
      exit 1
    fi
  '';
in
{
  environment.systemPackages = [ nswitch ];
}
