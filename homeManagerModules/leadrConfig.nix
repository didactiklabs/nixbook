{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.leadrConfig;
  leadrPackage = pkgs.callPackage ../customPkgs/leadr.nix { };
in
{
  options.customHomeManagerModules.leadrConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable leadr configuration and deploy config files.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ leadrPackage ];

    # Deploy your existing leadr configuration files
    home.file = {
      ".config/leadr/config.toml".text = ''
        leadr_key = "<C-g>"
        redraw_prompt_line = true

        [panel]
        enabled = true
        delay_ms = 500
        fail_silently = true
        theme_name = "catppuccin-mocha"

        [panel.layout]
        border_type = "Rounded"
        height = 10
        padding = 2

        [panel.layout.columns]
        width = 40
        spacing = 5
        centred = false

        [panel.layout.symbols]
        append = "󰌒"
        arrow = "→"
        evaluate = "󰊕"
        execute = "󰌑"
        insert = ""
        prepend = "⇤"
        replace = " "
        sequence_begin = "󰄾"
        surround = "󰅪"
      '';

      ".config/leadr/mappings.toml".text = ''
        [ghm]
        command = "gh pr create ; gh pr merge --auto"
        description = "Github PR create && merge"
        execute = true

        [ghc]
        command = "gh pr create"
        description = "Github PR create"
        execute = true

        [ga]
        command = "git add ."
        description = "Git add all"
        execute = true

        [gs]
        command = "git status"
        description = "Git status"
        execute = true

        [gfeat]
        command = 'goji -a -m "#CURSOR" -t feat'
        description = "Start a Git commit feat"

        [gfix]
        command = 'goji -a -m "#CURSOR" -t feat'
        description = "Start a Git commit fix"

        [gdoc]
        command = 'goji -a -m "#CURSOR" -t docs'
        description = "Start a Git commit docs"

        [grefactor]
        command = 'goji -a -m "#CURSOR" -t refactor'
        description = "Start a Git commit refactor"

        [id]
        command = "date +%Y%m%d"
        description = "Insert current date in YYYYMMDD format"
        insert_type = "Insert"
        evaluate = true

        [sq]
        command = '"#COMMAND"'
        description = "Surround with quotes"
        insert_type = "Surround"

        [ps]
        command = "sudo "
        description = "Prepend sudo"
        insert_type = "Prepend"

      '';
    };

    # Fish integration
    programs.fish = lib.mkIf config.programs.fish.enable {
      shellInit = lib.mkAfter ''
        # Leadr fish integration
        source (leadr --fish | psub)
      '';
    };

    # Zsh integration
    programs.zsh = lib.mkIf config.programs.zsh.enable {
      initExtra = lib.mkAfter ''
        # Leadr zsh integration
        source <(leadr --zsh)
      '';
    };
  };
}
