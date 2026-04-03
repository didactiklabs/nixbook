/*
  Auto-generates documentation for custom NixOS and Home Manager modules.

  Usage:
    nix-build docs/generate-docs.nix
    # Then: cp result/MODULES.md docs/MODULES.md

  This evaluates the module system to extract option metadata (name, type,
  default, description) for all options under `customNixOSModules.*` and
  `customHomeManagerModules.*`, then renders them to Markdown.
*/
let
  sources = import ../npins;
  pkgs = import sources.nixpkgs {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
    };
  };
  inherit (pkgs) lib;

  # -- HM lib with hm extensions (needed for lib.hm.*) -------------------------
  hmLib = import (sources.home-manager + "/modules/lib/stdlib-extended.nix") lib;

  # -- External HM modules (same imports as userConfig.nix) ---------------------
  dmsFlake = import sources.flake-compat { src = sources.dms; };
  dmsPluginRegistryFlake = import sources.flake-compat { src = sources.dms-plugin-registry; };
  zenBrowserFlake = import sources.flake-compat { src = sources.zen-browser-flake; };

  externalHmModules = [
    (import sources.stylix).homeModules.stylix
    (import sources.nixvim).homeModules.nixvim
    (import "${sources.agenix}/modules/age-home.nix")
    dmsFlake.defaultNix.homeModules.dank-material-shell
    dmsPluginRegistryFlake.defaultNix.modules.default
    zenBrowserFlake.defaultNix.homeModules.twilight
  ];

  # -- NixOS Modules -----------------------------------------------------------
  nixosEval = import (sources.nixpkgs + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      (import "${sources.lanzaboote}" {
        inherit pkgs;
        crane = import "${sources.crane}" { inherit pkgs; };
        inherit (sources) rust-overlay;
      }).nixosModules.lanzaboote
      ../nixosModules
      {
        networking.hostName = "docs-eval";
        fileSystems."/" = {
          device = "/dev/null";
          fsType = "ext4";
        };
        boot.loader.systemd-boot.enable = true;
        system.stateVersion = "24.05";
      }
    ];
  };

  # -- Home Manager Modules ----------------------------------------------------
  hmBaseModules = import (sources.home-manager + "/modules/modules.nix") {
    inherit pkgs;
    lib = hmLib;
    check = false;
    useNixpkgsModule = false;
  };

  hmEval = hmLib.evalModules {
    modules =
      hmBaseModules
      ++ externalHmModules
      ++ [
        {
          _module.args = {
            inherit pkgs;
            lib = hmLib;
            osConfig = nixosEval.config;
          };
          _module.check = false;
        }
        ../homeManagerModules
        {
          home.username = "docs";
          home.homeDirectory = "/home/docs";
          home.stateVersion = "24.05";
        }
      ];
  };

  # -- Option extraction -------------------------------------------------------
  isOption = v: v ? _type && v._type == "option";

  collectOptions =
    prefix: tree:
    let
      names = builtins.attrNames tree;
      collect =
        name:
        let
          val = tree.${name};
          fullPath = if prefix == "" then name else "${prefix}.${name}";
        in
        if isOption val then
          [
            {
              inherit fullPath;
              description =
                if val ? description && val.description != null && val.description != "" then
                  val.description
                else
                  null;
              type =
                let
                  t = builtins.tryEval (val.type.description or (val.type.name or "unknown"));
                in
                if t.success then t.value else "unknown";
              default =
                if val ? default then
                  let
                    rendered = builtins.tryEval (
                      if builtins.isBool val.default then
                        (if val.default then "true" else "false")
                      else if builtins.isInt val.default then
                        builtins.toString val.default
                      else if builtins.isFloat val.default then
                        builtins.toString val.default
                      else if builtins.isString val.default then
                        ''"${val.default}"''
                      else if builtins.isList val.default then
                        builtins.toJSON val.default
                      else if builtins.isAttrs val.default then
                        builtins.toJSON val.default
                      else if builtins.isNull val.default then
                        "null"
                      else
                        builtins.toString val.default
                    );
                  in
                  if rendered.success then rendered.value else "*complex value*"
                else
                  null;
            }
          ]
        else if builtins.isAttrs val && !(val ? _type) then
          collectOptions fullPath val
        else
          [ ];
    in
    builtins.concatLists (map collect names);

  nixosOptions =
    if nixosEval.options ? customNixOSModules then
      collectOptions "customNixOSModules" nixosEval.options.customNixOSModules
    else
      [ ];

  hmOptions =
    if hmEval.options ? customHomeManagerModules then
      collectOptions "customHomeManagerModules" hmEval.options.customHomeManagerModules
    else
      [ ];

  # -- Markdown rendering ------------------------------------------------------
  getModuleName =
    opt:
    let
      parts = lib.splitString "." opt.fullPath;
    in
    if builtins.length parts >= 2 then builtins.elemAt parts 1 else "unknown";

  groupByModule =
    options:
    let
      moduleNames = lib.unique (map getModuleName options);
      sorted = builtins.sort (a: b: a < b) moduleNames;
    in
    map (modName: {
      name = modName;
      options = builtins.filter (opt: getModuleName opt == modName) options;
    }) sorted;

  # Escape pipe characters in markdown table values
  escapeTableValue = s: builtins.replaceStrings [ "|" "\n" ] [ "\\|" " " ] s;

  renderOption =
    opt:
    let
      desc =
        if opt.description != null then
          builtins.replaceStrings [ "\n" ] [ " " ] (lib.strings.trim opt.description)
        else
          "*No description provided.*";
      defaultStr = if opt.default != null then opt.default else "*none*";
    in
    ''
      ### `${opt.fullPath}`

      - **Type:** `${opt.type}`
      - **Default:** `${escapeTableValue defaultStr}`

      ${desc}

    '';

  renderGroup = group: ''
    ## ${group.name}

    ${lib.concatStrings (map renderOption group.options)}
  '';

  renderTocEntry = _prefix: group: "- [${group.name}](#${lib.strings.toLower group.name})";

  nixosGroups = groupByModule nixosOptions;
  hmGroups = groupByModule hmOptions;

  markdown = ''
    # Nixbook Custom Module Options

    > **Auto-generated** from the Nix module definitions.
    > Run `nix-build docs/generate-docs.nix && cp result/MODULES.md docs/MODULES.md` to regenerate.

    ## Table of Contents

    ### NixOS Modules

    ${lib.concatMapStringsSep "\n" (renderTocEntry "customNixOSModules") nixosGroups}

    ### Home Manager Modules

    ${lib.concatMapStringsSep "\n" (renderTocEntry "customHomeManagerModules") hmGroups}

    ---

    # NixOS Modules (`customNixOSModules`)

    ${lib.concatStringsSep "\n---\n\n" (map renderGroup nixosGroups)}

    ---

    # Home Manager Modules (`customHomeManagerModules`)

    ${lib.concatStringsSep "\n---\n\n" (map renderGroup hmGroups)}
  '';

in
pkgs.runCommand "nixbook-module-docs"
  {
    nativeBuildInputs = [ pkgs.gnused ];
  }
  ''
    mkdir -p $out
    cat > $out/MODULES.md << 'MARKDOWN'
    ${markdown}
    MARKDOWN
    # Remove leading indentation (2 spaces from the Nix heredoc)
    sed -i 's/^  //' $out/MODULES.md
    echo "Documentation generated at $out/MODULES.md"
  ''
