let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
    };
  };
  createConfiguration = parent: {
    networking.hostName = parent.hostName;
    deployment = {
      # Allow local deployment with `colmena apply-local`
      allowLocalDeployment = true;

      # Disable SSH deployment.
      targetHost = null;
    };
    imports = [ ./profiles/${parent.hostName}/configuration.nix ];
  };
in
{
  meta = {
    nixpkgs = pkgs;
  };
  totoro = createConfiguration { hostName = "totoro"; };
  anya = createConfiguration { hostName = "anya"; };
  nishinoya = createConfiguration { hostName = "nishinoya"; };
}
