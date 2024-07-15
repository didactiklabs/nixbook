{ config, lib, ... }:
let cfg = config.customHomeManagerModules.starship;
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
          [](#${config.lib.stylix.colors.base01})$nix_shell$username$hostname[](bg:#${config.lib.stylix.colors.base08} fg:#${config.lib.stylix.colors.base01})$kubernetes[](bg:#${config.lib.stylix.colors.base02} fg:#${config.lib.stylix.colors.base08})$directory[](fg:#${config.lib.stylix.colors.base02} bg:#${config.lib.stylix.colors.base03})$git_branch$git_metrics[](fg:#${config.lib.stylix.colors.base03} bg:#${config.lib.stylix.colors.base04})$time[ ](fg:#${config.lib.stylix.colors.base04})
        '';
        nix_shell = {
          disabled = false;
          format = "[$symbol ]($style)";
          impure_msg = "[impure](bold red)";
          pure_msg = "[pure](bold green)";
          symbol = "";
          style = "bg:#${config.lib.stylix.colors.base01}";
        };

        # https://starship.rs/config/#kubernetes
        kubernetes = {
          disabled = false;
          symbol = "☸";
          format = "[ ☸ ]($style)[$context ]($style)";
          style = "bg:#${config.lib.stylix.colors.base08}";
        };

        # https://starship.rs/config/#git-branch
        git_branch = {
          disabled = false;
          symbol = "";
          format = "[ $symbol $branch ]($style)";
          style = "bg:#${config.lib.stylix.colors.base03}";
          ignore_branches = [ "remotes/origin/renovate/*" ];
        };
        git_status = {
          disabled = false;
          format = "[$all_status$ahead_behind ]($style)";
          style = "bg:#${config.lib.stylix.colors.base03}";
        };

        # https://starship.rs/config/#git-metrics
        git_metrics = {
          added_style = "bg:#${config.lib.stylix.colors.base03}";
          deleted_style = "bg:#${config.lib.stylix.colors.base03}";
          disabled = false;
          format =
            "[+$added]($added_style)[ / ](bg:#${config.lib.stylix.colors.base03})[-$deleted ]($deleted_style)";
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
          style = "bg:#${config.lib.stylix.colors.base02}";
          #truncation_length = 5;
          format = "[ $path ]($style)";
          truncation_length = 3;
          truncation_symbol = "…/";
        };

        # https://starship.rs/config/#time
        time = {
          disabled = false;
          format = "[ ♥ $time ]($style)";
          style = "bg:#${config.lib.stylix.colors.base04}";
          time_format = "%H:%M";
        };

        # https://starship.rs/config/#package-version
        package.disabled = true;

        # https://starship.rs/config/#python
        python = { disabled = true; };

        # https://starship.rs/config/#username
        username = {
          disabled = false;
          show_always = true;
          style_user = "bg:#${config.lib.stylix.colors.base01}";
          style_root = "bg:#${config.lib.stylix.colors.base01}";
          format = "[$user]($style)";
        };

        # https://starship.rs/config/#hostname
        hostname = {
          disabled = false;
          ssh_only = false;
          format = "[@$hostname ]($style)";
          trim_at = "-";
          style = "bg:#${config.lib.stylix.colors.base01}";
        };
      };
    };
  };
}
