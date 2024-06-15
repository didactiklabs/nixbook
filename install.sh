#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

wget -q --spider http://google.com
if [ ! $? -eq 0 ]; then
    echo "We are offline, this installation won't work choom !"
fi

echo '''
    ⣿⣿⣿⣿⠻⢿⡛⠋⠉⠉⠙⠉⠉⠋⠛⠷⠻⠿⠒⠉⠛⠿⠿⢉⣉⠉⡻⢿⣿⣿
    ⣿⣿⣿⡷⡀⢠⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡞⠉⢻⣏⣾⡿
    ⣿⣿⣿⠷⡜⠃⠀⢀⡴⠾⠹⠷⣄⠀⠀⠀⠀⠀⣠⣴⢶⣢⡀⠀⠑⡤⣪⡗⢿⡇
    ⣿⣿⣿⡆⡄⠀⠰⠋⢀⣠⣤⣦⠠⡀⠀⠀⠀⠀⣀⠀⠀⠀⠙⢆⠀⠘⠁⡇⠀⠀
    ⣿⣿⣿⢟⠃⠀⠀⡴⠋⠀⣀⠙⣿⣷⠀⠀⠀⠞⡿⠛⠛⠓⢦⡀⠀⠸⢊⡇⠀⠀
    ⣿⣿⣿⣿⠀⠀⠘⡅⠀⠺⣿⠇⡸⠉⠀⠀⠀⢸⠀⣾⣷⠀⠀⢻⠄⢰⢹⡧⡀⠀
    ⣿⣯⣎⢻⠀⠀⠀⠸⠶⠤⠤⠾⠋⠀⠀⠀⠀⠀⠢⣈⠁⣀⣠⠏⠀⠸⢊⡴⢾⠀
    ⣿⣿⣟⣧⠆⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣀⡀⠀⠀⠀⠉⠈⠁⠀⠀⢠⣯⡇⢸⠇
    ⣿⣿⡿⣿⣄⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⣼⠟⢁⠎⠀
    ⣿⣿⣷⡄⠁⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠃⣠⠊⠀⠀
    ⣿⣿⣿⡟⠻⣱⠀⠀⠀⠀⠀⣠⠄⠒⠒⠒⠀⢄⠀⠀⠀⠀⠀⢀⠶⡐⠁⠀⠀⠀
    ⣿⡿⠛⠋⠀⠈⢃⠀⠀⠀⠀⠉⠁⠀⠀⠉⠉⠙⠀⠀⠀⠀⠀⣎⠀⠀⠀⠀⠀⠀
    ⠂⠈⢉⣽⣉⣉⣿⣷⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⠗⠒⠢⠤⢤⣀⠀
    ⠉⠉⣻⣿⣿⣿⢿⡗⠟⠙⠗⢤⣀⠀⠀⠀⢀⣀⢤⠾⣟⣡⢻⣿⣿⣶⣦⣤⣀⣉
    ⠉⠉⠁⠀⠀⠀⢸⠀⠀⠀⠀⠀⠘⠛⠂⠘⠋⠛⢀⣀⡴⠃⡜⠉⠙⠛⠻⠿⢿⣿
'''
echo "Welcome to the nova Nixbook installation script choom !"
echo ""
read -p "Enter your desired main username: " username
if [[ -z "$username" ]]; then
    echo "Username cannot be empty"
    exit 1
fi
echo "Your username is: $username"
echo ""

read -p "Enter your desired hostname: " hostname
if [[ -z "$hostname" ]]; then
    echo "Hostname cannot be empty"
    exit 1
fi
echo "Your hostname is: $hostname"
echo ""

if [ ! -d "./profiles/$username-$hostname" ]; then
    echo "The directory doesn't ./profiles/$username-$hostname exist."
    while true; do
        read -p "You must not have created your profile yet and it will use the default one, do you agree with that ? (yes/no): " yn
        case $yn in
        [Yy]*)
            echo "Continuing installation..."
            ;;
        [Nn]*)
            echo "Aborted installation..."
            exit 1
            ;;
        *)
            echo "Please answer yes or no."
            ;;
        esac
    done
else
    while true; do
        read -p "The directory ./profiles/$username-$hostname exists, installing your profile. Should we continue ? (yes/no): " yn
        case $yn in
        [Yy]*)
            echo "Continuing installation..."
            break
            ;;
        [Nn]*)
            echo "Aborted installation..."
            exit 1
            ;;
        *)
            echo "Please answer yes or no."
            ;;
        esac
    done
fi

nixos_dir="/home/$username/Documents/nixos"
config_tpl="./configuration.nix.tpl"
config_file="./configuration.nix"

if [ -d "$nixos_dir" ]; then
    echo "The directory $nixos_dir exists. A previous configuration might already be installed, please delete it to install this one !"
    if [ $PWD == "$nixos_dir" ]; then
        echo ""
        echo "!!! WARNING !!! ----> You are trying to configure NixOS from a pre-existing configuration."
        echo "You should copy this repo somewhere else before deleting it and running the script !!"
    fi
    exit 0
else
    echo "The directory $nixos_dir does not exist, creating it..."
    mkdir -p "$nixos_dir"
fi

echo "Removing old /etc/nixos configuration link..."
rm -rf /etc/nixos || {
    echo "Failed to remove /etc/nixos"
    exit 1
}
echo "Regenerating hardware configuration files..."
nixos-generate-config --show-hardware-config >$nixos_dir/hardware-configuration.nix

if [ ! -f "$config_tpl" ]; then
    echo "Configuration template not found: $config_tpl"
    exit 1
fi

echo "Configuring hostname & username..."
sed "s/%USERNAME%/$username/g" "$config_tpl" | sed "s/%HOSTNAME%/$hostname/g" >"$config_file" || {
    echo "Failed to create configuration.nix"
    exit 1
}

echo "Copying nixos configuration to user directory..."
cp -r ./* "$nixos_dir" || {
    echo "Failed to copy files to $nixos_dir"
    exit 1
}
cp -r ./.* "$nixos_dir" || {
    echo "Failed to copy dotfiles to $nixos_dir"
    exit 1
}
cd $nixos_dir

echo "Linking nixos directory to /etc/nixos ..."
ln -sfn "$nixos_dir" /etc/nixos || {
    echo "Failed to create symlink to /etc/nixos"
    exit 1
}

echo "Reconfiguring nixos..."
nixos-rebuild boot || {
    echo "nixos-rebuild boot failed"
    exit 1
}
nixos-rebuild switch || {
    echo "nixos-rebuild switch failed"
    exit 1
}
echo '''
    ⠀⢀⣣⠏⠀⠀⠀⠀⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⠀⠀⠀⣧⣀⡀
    ⠀⢼⠏⠀⠀⠀⠀⢠⡃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⣗⠀⠀⠀⣰⡟⠀⠀
    ⠀⡾⠀⢀⣀⣰⣤⣼⣷⣼⣿⣷⣮⣕⡒⠤⠀⠀⠀⠀⠀⠀⠙⣦⣤⣴⡟⠀⠀⢠
    ⢰⡇⢐⣿⠏⠉⠉⠉⠙⠙⠋⠉⠁⠀⠈⠢⣄⡉⠑⠲⠶⣶⣾⣿⣿⣿⣿⣄⣠⣿
    ⢸⡇⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠷⣶⣮⣭⣽⣿⣿⣿⣿⣿⣿⣿
    ⢸⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠹⣿⣿⣿⣿⠿⢿⠟⢁⣭
    ⢸⣿⣿⡇⣀⠠⠀⡀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣄⣀⠀⡠⠨⡙⠻⣿⣿⠏⢠⣏⠳
    ⠘⢿⣿⣿⠀⢱⢉⠿⠳⣆⠀⠀⠀⠀⠩⠋⢲⡿⠈⢙⣶⠄⠘⢆⢹⡟⠀⣿⢿⠀
    ⠀⠈⠻⣿⡇⠈⠄⢿⣤⣬⠀⠀⠀⠀⠀⢀⡈⠻⠶⢾⡟⠀⠀⡸⠀⠀⢔⠅⢚⣴
    ⣄⣴⣾⣿⣿⠀⠀⢑⠒⠋⠀⠀⠀⠀⠀⠀⠀⠉⢏⠀⠀⠀⠔⠀⠀⠀⠁⡤⢿⣿
    ⠿⢿⣿⣿⣿⣷⢴⠟⠀⠀⢀⡀⠀⠀⠀⠀⠀⠀⠙⠵⠤⠊⠀⠀⣼⣿⡏⢀⠔⠁
    ⠀⠀⠹⣿⣿⠟⢮⠀⠀⠀⠈⠉⠁⠀⠀⠀⠀⠀⠀⠁⠀⠀⣠⣾⣿⣿⡷⠉⠀⠀
    ⣆⠀⠀⢿⡇⠀⠀⢱⣤⡀⠀⠉⠛⠋⠉⠁⠀⠀⠀⢀⣴⣾⣿⣿⠟⠛⠢⡄⠀⠀
    ⠈⠀⠀⠸⣿⣆⠀⠀⢿⣿⣦⣀⠀⠀⠀⠀⣀⢤⣾⣿⣿⡿⠟⠁⠀⠀⠀⠹⡄⠀
    ⠀⠀⠀⠀⠀⠈⠀⠀⠀⠛⠛⠿⠷⠒⠒⠯⠀⠀⠶⠾⠋⠀⠀⠀⠀⠀⠀⠀⠿⠄
'''
echo "Installation Complete choom !"
echo ""
while true; do
    read -p "Do you wish to reboot now? (yes/no) " yn
    case $yn in
    [Yy]*)
        echo "Rebooting now..."
        reboot
        ;;
    [Nn]*)
        echo "Exiting without reboot"
        exit 0
        ;;
    *)
        echo "Please answer yes or no."
        ;;
    esac
done
