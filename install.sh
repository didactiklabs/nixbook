#!/usr/bin/env bash

set -e

if [ -n "$1" ]; then
    rm -f /etc/nixos/configuration.nix
    cp -rf ./* /etc/nixos/
    cat /etc/nixos/configuration.nix.tpl | sed "s/%USERNAME%/${1}/g" >/etc/nixos/configuration.nix
    read -n 1 -p "Please start Wifi, configure it, then press enter" donocare
    nixos-rebuild boot
    nixos-rebuild switch
    cd /etc/nixos
    nixos-rebuild switch
    echo "Redemarrez votre systeme"
fi
