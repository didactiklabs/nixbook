{
  username ? "khoa", # Default username
  profileName ? "totoro", # Default profile name (e.g., totoro, anya, nishinoya)
  pkgs ? import (import ./npins).nixpkgs {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
    };
  },
  lib ? pkgs.lib,
  sources ? import ./npins,
  extraHomeManagerModules ? [ ],
}:
let
  userConfigModule = import ./nixosModules/userConfig.nix {
    inherit pkgs lib sources;
    # No overrides here as this is for a generic Home Manager import
  };

  # Construct the path to the user's home-manager configuration within the specified profile
  userProfileHomeManagerConfig =
    if builtins.pathExists ./profiles/${profileName}/${username}/default.nix then
      ./profiles/${profileName}/${username}/default.nix
    else
      builtins.error "Home Manager profile not found for user '${username}' in profile '${profileName}'. Make sure the path ./profiles/${profileName}/${username}/default.nix exists.";
in
{
  imports = [
    # Import the user configuration module which contains the mkUser function
    userConfigModule.mkUser
    {
      inherit username;
      # Pass the user's specific home-manager imports from the profile
      userImports = [
        userProfileHomeManagerConfig
      ];
      # Specify a default shell if needed, or let userConfig.nix handle it
      shell = pkgs.zsh; # Assuming zsh is generally desired, can be made configurable
    }
  ]
  ++ extraHomeManagerModules; # Allow adding external home-manager modules
}
