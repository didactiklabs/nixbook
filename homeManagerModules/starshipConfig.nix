{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules.starship;
in {
  options.customHomeManagerModules.starship = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable starship globally or not
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.starship = {
      enable = true;
      enableZshIntegration = true;
      # Configuration written to ~/.config/starship.toml
      settings = {
        add_newline = true;
        scan_timeout = 30;
        command_timeout = 5000;
        # https://starship.rs/config/#prompt
        format = ''
          (\[ $nix_shell \] )(\[ $kubernetes \])(\[ $kubernetes_ns \])(\[ $git_branch $git_metrics \])\[ $character $directory \]
          \[ $username@$hostname \] $time \$ '';

        # https://starship.rs/config/#nix-shell
        nix_shell = {
          disabled = false;
          format = "[$symbol]($style) : [$name]($style)";
          impure_msg = "[impure](bold red)";
          pure_msg = "[pure](bold green)";
          symbol = "";
          style = "bold cyan";
        };

        # https://starship.rs/config/#kubernetes
        kubernetes = {
          disabled = false;
          symbol = "☸";
          format = "[☸]($style) [$context]($style) [$namespace]($style)";
          style = "bold blue";
        };

        # https://starship.rs/config/#git-branch
        git_branch = {
          disabled = false;
          symbol = "";
          format = "[$symbol]($style) : [$branch]($style)";
          style = "bold purple";
          ignore_branches = ["remotes/origin/renovate/*"];
        };

        # https://starship.rs/config/#git-metrics
        git_metrics = {
          disabled = false;
          format = "[+$added]($added_style) / [-$deleted]($deleted_style)";
        };

        # https://starship.rs/config/#character
        character = {
          success_symbol = "[λ](bold blue)";
          error_symbol = "[λ](bold red)";
          format = "[$symbol]($style)";
        };

        # https://starship.rs/config/#directory
        directory = {
          disabled = false;
          truncate_to_repo = false;
          use_logical_path = true;
          style = "bold green";
          #truncation_length = 5;
          format = "[$path]($style)[$lock_symbol]($lock_style)";
        };

        # https://starship.rs/config/#time
        time = {
          disabled = false;
          format = "[$time]($style)";
          time_format = "%H:%M";
        };

        # https://starship.rs/config/#package-version
        package.disabled = true;

        # https://starship.rs/config/#python
        python = {disabled = true;};

        # https://starship.rs/config/#username
        username = {
          disabled = false;
          show_always = true;
          style_user = "bold green";
          style_root = "bold red";
          format = "[$user]($style)";
        };

        # https://starship.rs/config/#hostname
        hostname = {
          disabled = false;
          ssh_only = false;
          format = "[$hostname]($style)";
          trim_at = "-";
          style = "bold yellow";
        };
      };
    };
  };
}
