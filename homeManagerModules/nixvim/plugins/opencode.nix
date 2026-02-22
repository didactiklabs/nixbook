{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      extraPackages = [ pkgs.opencode ];

      plugins.opencode = {
        enable = true;
      };

      extraConfigLua = ''
        vim.g.opencode_opts = {
          provider = {
            enabled = "kitty",
            kitty = {
              -- Optional: Configuration for the kitty provider
              -- For example, you can change the window type or focus behavior
              -- window_type = "os", -- "os" or "tab" or "window"
              -- focus = false,
            }
          },
        }
        vim.o.autoread = true
      '';

      keymaps = [
        {
          mode = [ "n" "x" ];
          key = "<C-a>";
          action.__raw = ''function() require("opencode").ask("@this: ", { submit = true }) end'';
          options.desc = "Ask opencode…";
        }
        {
          mode = [ "n" "x" ];
          key = "<C-x>";
          action.__raw = ''function() require("opencode").select() end'';
          options.desc = "Execute opencode action…";
        }
        {
          mode = [ "n" "t" ];
          key = "<C-.>";
          action.__raw = ''function() require("opencode").toggle() end'';
          options.desc = "Toggle opencode";
        }
        {
          mode = [ "n" "x" ];
          key = "go";
          action.__raw = ''function() return require("opencode").operator("@this ") end'';
          options = { desc = "Add range to opencode"; expr = true; };
        }
        {
          mode = "n";
          key = "goo";
          action.__raw = ''function() return require("opencode").operator("@this ") .. "_" end'';
          options = { desc = "Add line to opencode"; expr = true; };
        }
        {
          mode = "n";
          key = "<S-C-u>";
          action.__raw = ''function() require("opencode").command("session.half.page.up") end'';
          options.desc = "Scroll opencode up";
        }
        {
          mode = "n";
          key = "<S-C-d>";
          action.__raw = ''function() require("opencode").command("session.half.page.down") end'';
          options.desc = "Scroll opencode down";
        }
      ];
    };
  };
}
