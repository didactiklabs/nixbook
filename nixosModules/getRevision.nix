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
  # Read straight from .git at evaluation time. (These used to be
  # runCommand + readFile, i.e. import-from-derivation: evaluation stopped to
  # build them.) A .git *file* (worktree, submodule) has no config/HEAD here.
  gitFile =
    name:
    if builtins.pathExists (../.git + "/${name}") then
      builtins.readFile (../.git + "/${name}")
    else
      null;
  gitConfig = gitFile "config";
  gitHead = gitFile "HEAD";
  # The first `url = …` of .git/config (the remote the repo was cloned from).
  remoteUrls = lib.concatMap (
    line:
    let
      m = builtins.match "[[:space:]]*url = (.*)" line;
    in
    if m == null then [ ] else m
  ) (lib.splitString "\n" gitConfig);
  jsonFile = builtins.toJSON {
    url = if gitConfig != null && remoteUrls != [ ] then lib.head remoteUrls else "unknown";
    # "refs/heads/<branch>", or "detached" for a checked-out commit.
    branch =
      if gitHead == null then
        "unknown"
      else
        let
          m = builtins.match "ref: ([^\n]*).*" gitHead;
        in
        if m == null then "detached" else lib.head m;
    inherit dirty;
    rev =
      if gitRepo != null then
        if dirty then lib.removeSuffix "-dirty" gitRepo.dirtyRev else gitRepo.rev
      else
        "unknown"; # no .git directory
    lastModifiedDate = if gitRepo != null then gitRepo.lastModifiedDate else "unknown";
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
