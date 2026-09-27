{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
  gitRepo = if builtins.pathExists ../.git then builtins.fetchGit ../. else null;
  # A tree with uncommitted changes has an all-zero `rev`; `dirtyRev` is
  # "<commit>-dirty" (the commit the changes were made on).
  dirty = gitRepo != null && gitRepo ? dirtyRev;
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
    inherit dirty;
    rev =
      if gitRepo != null then
        if dirty then lib.removeSuffix "-dirty" gitRepo.dirtyRev else gitRepo.rev
      else
        {
          rev = "unknown"; # Default value when there's no .git directory
        }
        .rev;
    lastModifiedDate =
      if gitRepo != null then
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
          - rev: the full commit SHA (via builtins.fetchGit; for a tree with
            uncommitted changes, the commit they were made on)
          - dirty: whether the tree had uncommitted changes
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
