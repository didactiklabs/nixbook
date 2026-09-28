/*
  Fast repository checks: pure evaluation, nothing is built.

    tests/run.sh repo
    # or one check: nix-instantiate --eval --strict --json tests/repo.nix -A <name>

  Each attribute is an independent check that evaluates to "ok" (or, for
  `packages.<name>`, the .drv path) and throws with the reason otherwise:
    - machines: hive.nix nodes and profiles/ directories agree (a machine can't be
      half-added or half-removed);
    - orphans: every module file under nixosModules/ and homeManagerModules/ is
      referenced somewhere (an unimported module silently does nothing);
    - packages.<name>: every custom package in customPkgs/ instantiates (its .drv evaluates),
      including the ones no profile uses;
    - shellLib: unit tests of the nixbook-shell settings helpers (nixbook-shell/tests/lib.nix);
    - shellStandalone: nixbook-shell/ evaluates on its own (nixbook-shell/tests/standalone.nix).
*/
let
  sources = import ../npins;
  pkgs = import sources.nixpkgs {
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "qtwebengine-5.15.19"
        "pnpm-10.29.2"
        "electron-40.10.5"
      ];
    };
    overlays = [ (import ../nixosModules/overlays.nix { inherit sources; }) ];
  };
  inherit (pkgs) lib;

  sorted = lib.sort lib.lessThan;
  dirsIn =
    dir: sorted (lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir)));
  nixFilesIn =
    dir:
    sorted (
      lib.attrNames (
        lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (builtins.readDir dir)
      )
    );

  # -- Machines -----------------------------------------------------------------
  hiveNodes = sorted (lib.attrNames (removeAttrs (import ../hive.nix) [ "meta" ]));
  profiles = dirsIn ../profiles;

  # -- Orphan modules -----------------------------------------------------------
  # All Nix sources outside VCS/tooling state and the vendored nixbook-shell
  # tree (symlinks such as `result` are never followed).
  skippedDirs = [
    ".git"
    ".devenv"
    ".direnv"
    ".tmp"
    ".gcroots"
    "src"
  ];
  nixSourcesUnder =
    dir:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" && !lib.elem name skippedDirs then
          nixSourcesUnder (dir + "/${name}")
        else if type == "regular" && lib.hasSuffix ".nix" name then
          [ (dir + "/${name}") ]
        else
          [ ]
      ) (builtins.readDir dir)
    );
  searchable = nixSourcesUnder ../.;
  # Read each file once; search file by file (one regex over the whole repo
  # overflows the regex engine's stack).
  contents = map (p: {
    path = p;
    text = builtins.readFile p;
  }) searchable;
  mentions = needle: text: lib.length (builtins.split (lib.escapeRegex needle) text) > 1;
  # A module is referenced when another file mentions `/<name>` (or, for
  # `<name>.nix` and directories, `/<stem>` followed by a delimiter).
  isReferenced =
    dir: entry:
    let
      self = dir + "/${entry}";
      stem = lib.removeSuffix ".nix" entry;
      needles = [
        "/${entry}"
      ]
      ++ map (end: "/${stem}${end}") [
        "\n"
        " "
        ")"
        ";"
        "\""
      ];
    in
    lib.any (f: f.path != self && lib.any (n: mentions n f.text) needles) contents;
  moduleEntries =
    dir:
    lib.filter (e: e != "default.nix") (
      lib.attrNames (
        lib.filterAttrs (n: t: t == "directory" || lib.hasSuffix ".nix" n) (builtins.readDir dir)
      )
    );
  # Entry points imported from outside the repo, by design.
  externalEntryPoints = [
    # Standalone Home Manager entry for non-NixOS hosts (see README.md).
    "homeManagerModules/entrypoint.nix"
  ];
  orphansIn =
    prefix: dir:
    lib.filter (e: !lib.elem e externalEntryPoints) (
      map (e: "${prefix}/${e}") (lib.filter (e: !isReferenced dir e) (moduleEntries dir))
    );
  orphans =
    orphansIn "nixosModules" ../nixosModules ++ orphansIn "homeManagerModules" ../homeManagerModules;

  # -- Custom packages ----------------------------------------------------------
  customPkgFiles = nixFilesIn ../customPkgs;
  customPkgDirs = dirsIn ../customPkgs;

  # -- nixbook-shell -------------------------------------------------------------
  # Its own tests (nixbook-shell/tests/lib.nix), plus proof that the directory
  # is self-contained: copied alone to the store, it still builds its package
  # and a Home Manager configuration using only its module.
  shellLibFailures = import ../nixbook-shell/tests/lib.nix { inherit lib; };
  standaloneShell = import ../nixbook-shell/tests/standalone.nix {
    inherit pkgs;
    homeManager = sources.home-manager;
  };

  check = what: ok: if ok then "ok" else throw "tests/repo.nix: ${what}";
in
{
  machines =
    check "hive.nix nodes (${toString hiveNodes}) differ from profiles/ (${toString profiles})"
      (hiveNodes == profiles);
  orphans = check "modules referenced from nowhere: ${toString orphans}" (orphans == [ ]);
  shellLib = check "nixbook-shell lib.nix unit tests failed:\n${
    lib.generators.toPretty { } shellLibFailures
  }" (shellLibFailures == [ ]);
  shellStandalone = check "nixbook-shell/ is not self-contained" (standaloneShell == "ok");
  # Not a check: the node names, for CI's host matrix.
  inherit hiveNodes;
  packages = lib.genAttrs (map (lib.removeSuffix ".nix") customPkgFiles ++ customPkgDirs) (
    name:
    let
      path = ../customPkgs + "/${if lib.elem name customPkgDirs then name else "${name}.nix"}";
    in
    (import path { inherit pkgs; }).drvPath
  );
}
