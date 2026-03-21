{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
  jsonFile = builtins.toJSON {
    url =
      if builtins.pathExists ../.git then
        builtins.readFile (
          pkgs.runCommand "getRemoteUrl" { buildInputs = [ pkgs.git ]; } ''
            grep -oP '(?<=url = ).*' ${../.git/config} | tr -d '\n' > $out;
          ''
        )
      else
        {
          url = "unknown";
        };
    branch =
      if builtins.pathExists ../.git then
        builtins.readFile (
          pkgs.runCommand "getBranch" { buildInputs = [ pkgs.git ]; } ''
            cat ${../.git/HEAD} | awk '{print $2}' | tr -d '\n' > $out;
          ''
        )
      else
        { branch = "unknown"; };
    rev =
      if builtins.pathExists ../.git then
        let
          gitRepo = builtins.fetchGit ../.; # Fetch the Git repository
        in
        gitRepo.rev # Access the 'rev' attribute directly
      else
        {
          rev = "unknown"; # Default value when there's no .git directory
        }
        .rev;
    lastModifiedDate =
      if builtins.pathExists ../.git then
        let
          gitRepo = builtins.fetchGit ../.; # Fetch the Git repository
        in
        gitRepo.lastModifiedDate
      else
        {
          lastModifiedDate = "unknown";
        }
        .lastModifiedDate;
  };
in
{
  options.customNixOSModules.getRevision = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to embed git metadata about the applied configuration into the system.

        At build time, reads the local .git directory (if present) and writes a JSON
        file to /etc/nixos/version containing:
          - url: the git remote URL (from .git/config)
          - branch: the checked-out branch (from .git/HEAD)
          - rev: the full commit SHA (via builtins.fetchGit)
          - lastModifiedDate: the commit timestamp

        This allows runtime inspection of exactly which nixbook commit is running,
        e.g. via: jq . /etc/nixos/version
        Also consumed by the osupdate script to show the "last applied revision"
        before pulling a new one.

        Enabled by default on all machines.
      '';
    };
  };

  config = lib.mkIf cfg.getRevision.enable {
    environment = {
      etc = {
        "nixos/version".source = pkgs.writeText "projectGit.json" jsonFile;
      };
    };
  };
}
