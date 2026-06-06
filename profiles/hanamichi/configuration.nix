args:
let
  # Get the current directory's name
  currentDir = builtins.toString ./.;
  hostname = builtins.baseNameOf currentDir;
  # Import the base configuration with the dynamic hostname
  base = import ../../base.nix (args // { inherit hostname; });
in
base
