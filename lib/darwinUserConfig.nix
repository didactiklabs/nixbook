# A Home Manager user on a macOS machine (nix-darwin): lib/userConfig.nix's
# mkUser for darwin.nix. The same Home Manager base (lib/homeManagerBase.nix),
# the home in /Users, and none of the Linux desktop services.
{
  pkgs,
  lib,
  sources,
}:
let
  homeManagerBase = import ./homeManagerBase.nix { inherit pkgs sources; };
  # On NixOS, nixosModules/niri.nix gives every user niri-flake's Home
  # Manager module (programs.niri.*), which niriConfig.nix sets even when off.
  # Here only its settings part: niri itself is a Linux compositor.
  niriFlake =
    (import sources.flake-compat {
      src = sources.niri-flake;
    }).defaultNix;
in
{
  mkUser =
    {
      username,
      userImports ? [ ],
    }:
    let
      home = "/Users/${username}";
    in
    {
      # The account itself is macOS's (made in Setup Assistant): nix-darwin
      # only manages users listed in users.knownUsers, and this one isn't.
      users.users.${username} = {
        inherit home;
        shell = pkgs.zsh;
      };
      # The user the user-level macOS preferences (system.defaults) are for.
      system.primaryUser = username;

      home-manager = {
        useUserPackages = true;
        useGlobalPkgs = true;
        backupFileExtension = "before-nixbook";
        users.${username} = {
          imports = homeManagerBase.imports ++ [ niriFlake.homeModules.config ] ++ userImports;

          options.profileCustomization = homeManagerBase.profileCustomizationOptions;

          config = {
            # niri is a Linux compositor: nothing of it on macOS. Its
            # config.kdl (written by niri-flake's module whenever its options
            # are set, checked by running niri) is left out, and with it every
            # use of the niri package; tests/darwin.nix checks none is left.
            xdg.configFile.niri-config.enable = lib.mkForce false;
            home = {
              stateVersion = "24.05";
              inherit username;
              homeDirectory = home;
              sessionPath = [
                "$HOME/go/bin"
                "$HOME/.local/go/bin"
              ];
              sessionVariables.NIXPKGS_ALLOW_UNFREE = 1;
            };
            programs = {
              go = {
                enable = true;
                env.GOPATH = "${home}/go";
              };
              home-manager.enable = true;
            };
          };
        };
      };
    };
}
