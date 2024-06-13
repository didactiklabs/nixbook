#!/usr/bin/env bash

set -e
mkdir -p $HOME/Documents/nixos
cp /etc/nixos/hardware-configuration.nix ./
rm -rf /etc/nixos
cat ./nixos/configuration.nix.tpl | sed "s/%USERNAME%/$USERNAME/g" >./configuration.nix
cp -r ./* $HOME/Documents/nixos/
ln -s $HOME/Documents/nixos /etc/nixos
nixos-rebuild boot
nixos-rebuild switch
echo "Redemarrez votre systeme"
