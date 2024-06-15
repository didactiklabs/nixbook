{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules.gitConfig;
in {
  options.customHomeManagerModules.gitConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable gitConfig globally or not
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.tig
      pkgs.git-extras
      pkgs.git-crypt
      pkgs.ghorg
      pkgs.glab
      pkgs.gh
      ## https://difftastic.wilfred.me.uk/git.html
      pkgs.difftastic
    ];

    programs.git = {
      package = pkgs.gitFull;
      enable = true;
      signing = {
        signByDefault = true;
        gpgPath = "${pkgs.gnupg}/bin/gpg2";
        key = null;
      };
      lfs.enable = true;
      difftastic.enable = true;
      ignores = ["*.vscode" "*.direnv"];
      aliases = {
        lg = "log --graph --pretty=tformat:'%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%an %ai)%Creset'";
        d = "diff";
        s = "status";
        sw = "switch";
        swcr = "switch -C";
        del = "branch -D";
        br = "branch --format='%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(contents:subject) %(color:green)(%(committerdate:relative)) [%(authorname)]' --sort=-committerdate";
        save = "!git add -A && git commit -m 'chore: commit save point'";
        undo = "reset HEAD~1 --mixed";
        res = "!git reset --hard";
        done = "!git push origin HEAD";
        lazy = ''!f() { git add -A && git commit -m "$@" && git push; }; f'';
        pushmr = ''
          !f() { git pull && git checkout -b "$@" && git add -A && git commit -m "$@" && git push origin "$@"; }; f'';
        purge = ''
          !git branch --merged | egrep -v "(^\*|master|main|dev|stage)" | xargs git branch -d'';
      };
      ## https://nix-community.github.io/home-manager/options.html#opt-programs.git.extraConfig
      extraConfig = {
        pull.rebase = true;
        init = {
          defaultBranch = "main";
        };
        core = {
          editor = "vim";
          excludesFile = "";
        };
        remote = {
          prune = true;
        };
      };
    };
  };
}
