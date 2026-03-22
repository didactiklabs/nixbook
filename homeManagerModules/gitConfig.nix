{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.gitConfig;
in
{
  options.customHomeManagerModules.gitConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Git configuration and related tooling.

        Configures:
          Core git (programs.git):
            - gitFull package with LFS enabled
            - GPG signing available but off by default (signByDefault = false)
            - pull.rebase = true, push.autoSetupRemote = true
            - defaultBranch = "main", remote.prune = true
            - .vscode and .direnv added to global ignores
            - Aliases: lg (graph log), d (diff), s (status), sw/swcr (switch),
              save (add+commit), undo (reset HEAD~1), lazy (add+commit+push),
              pushmr (branch+commit+push MR), purge (delete merged branches)

          Difftastic (programs.difftastic):
            - Structural diff tool that understands syntax, used as git's diff driver

          GitHub CLI (programs.gh):
            - Extensions: gh-eco, gh-notify, gh-poi, gh-f

          gh-dash (programs.gh-dash):
            - TUI GitHub dashboard with pre-configured PR/issue sections:
              DidactikLabs org PRs, My PRs, Needs Review, Participating

          Extra packages:
            - tig          — ncurses git history browser
            - git-extras   — collection of git utility scripts
            - difftastic   — also available as a standalone binary
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      tig
      git-extras
      ## https://difftastic.wilfred.me.uk/git.html
      difftastic
    ];
    programs = {
      gh = {
        enable = true;
        package = pkgs.gh;
        extensions = with pkgs; [
          gh-eco
          gh-notify
          gh-poi
          gh-f
        ];
      };
      gh-dash = {
        enable = true;
        settings = {
          prSections = [
            {
              title = "DidactikLabs Org Pull Requests";
              filters = "is:open org:didactiklabs";
            }
            {
              title = "My Pull Requests";
              filters = "is:open author:@me";
            }
            {
              title = "Needs My Review";
              filters = "is:open review-requested:@me";
            }
            {
              title = "Participating";
              filters = "is:open involves:@me -author:@me";
            }
          ];
          issuesSections = [
            {
              title = "My Issues";
              filters = "is:open author:@me";
            }
            {
              title = "Assigned";
              filters = "is:open assignee:@me";
            }
            {
              title = "Participating";
              filters = "is:open involves:@me -author:@me";
            }
          ];
        };
      };
      git = {
        package = pkgs.gitFull;
        enable = true;
        signing = {
          signByDefault = false;
          format = null;
          signer = "${pkgs.gnupg}/bin/gpg2";
          key = null;
        };
        lfs.enable = true;
        ignores = [
          "*.vscode"
          "*.direnv"
        ];
        settings = {
          alias = {
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
            pushmr = ''!f() { git pull && git checkout -b "$@" && git add -A && git commit -m "$@" && git push origin "$@"; }; f'';
            purge = ''!git branch --merged | egrep -v "(^\*|master|main|dev|stage)" | xargs git branch -d'';
          };
          push.autoSetupRemote = true;
          pull.rebase = true;
          init = {
            defaultBranch = "main";
          };
          core = {
            excludesFile = "";
          };
          remote = {
            prune = true;
          };
        };
      };
      difftastic = {
        enable = true;
        git.enable = true;
      };
    };
  };
}
