{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.starship;
in
{
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
      enableFishIntegration = config.customHomeManagerModules.fishConfig.enable or false;
      settings = {
        add_newline = true;
        scan_timeout = 30;
        command_timeout = 5000;

        format = ''
          [╭─](bold #${config.lib.stylix.colors.base04})$nix_shell$username$hostname$kubernetes[ ](bold #${config.lib.stylix.colors.base04})$directory$git_branch$git_status
          [╰─](bold #${config.lib.stylix.colors.base04})$character'';

        line_break.disabled = false;

        # UPDATED: The character module now uses an arrow symbol.
        character = {
          success_symbol = "[❯](bold #${config.lib.stylix.colors.base0B})";
          error_symbol = "[❯](bold #${config.lib.stylix.colors.base08})";
          vimcmd_symbol = "[❮](bold #${config.lib.stylix.colors.base0A})";
        };

        # Modules for the context (top) line.
        nix_shell = {
          disabled = false;
          format = "[ $state]($style) ";
          impure_msg = "impure";
          pure_msg = "pure";
          style = "bold #${config.lib.stylix.colors.base0D}";
        };

        username = {
          show_always = true;
          style_user = "bold #${config.lib.stylix.colors.base0E}";
          style_root = "bold #${config.lib.stylix.colors.base08}";
          format = "[$user]($style)";
        };

        hostname = {
          ssh_only = false;
          format = "[@$hostname]($style)";
          trim_at = ".";
          style = "bold #${config.lib.stylix.colors.base0E}";
        };

        kubernetes = {
          disabled = false;
          symbol = "☸";
          format = "[ $symbol $context]($style)";
          style = "bold #${config.lib.stylix.colors.base0C}";
        };

        directory = {
          style = "bold #${config.lib.stylix.colors.base0B}";
          format = "[in  $path]($style)[$read_only]($read_only_style) ";
          truncation_length = 4;
          truncation_symbol = "…/";
          read_only = "🔒";
          read_only_style = "bold #${config.lib.stylix.colors.base0A}";
        };

        git_branch = {
          symbol = "";
          format = "[on $symbol $branch]($style) ";
          style = "bold #${config.lib.stylix.colors.base0A}";
        };

        git_status = {
          format = ''([\[$all_status$ahead_behind\]]($style)) '';
          style = "bold #${config.lib.stylix.colors.base0A}";
          conflicted = "=";
          ahead = "⇡";
          behind = "⇣";
          diverged = "⇕";
          untracked = "?";
          stashed = "";
          modified = "!";
          staged = "+";
          renamed = "»";
          deleted = "✘";
        };

        # Disabling modules that are not used in the new format.
        time.disabled = true;
        package.disabled = true;
        python.disabled = true;
        git_metrics.disabled = true;
      };
    };
  };
}
