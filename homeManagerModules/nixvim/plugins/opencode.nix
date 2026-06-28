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
        inherit (config.customHomeManagerModules.opencodeConfig) enable;
      };

      extraConfigLua = ''
        local opencode_cmd = "opencode --port"
        local snacks_terminal_opts = {
          win = {
            position = "right",
            enter = false,
          },
        }

        ---@type opencode.Opts
        vim.g.opencode_opts = {
          server = {
            start = function()
              require("snacks.terminal").open(opencode_cmd, snacks_terminal_opts)
            end,
          },
        }
        vim.o.autoread = true

        _G.opencode_toggle = function()
          require("snacks.terminal").toggle(opencode_cmd, snacks_terminal_opts)
        end
      '';

      keymaps = [
        {
          mode = [
            "n"
            "x"
          ];
          key = "<C-a>";
          action.__raw = ''function() require("opencode").ask("@this: ") end'';
          options.desc = "Ask opencode…";
        }
        {
          mode = [
            "n"
            "x"
          ];
          key = "<C-x>";
          action.__raw = ''function() require("opencode").select() end'';
          options.desc = "Execute opencode action…";
        }
        {
          mode = [
            "n"
            "t"
          ];
          key = "<C-o>";
          action.__raw = "function() _G.opencode_toggle() end";
          options.desc = "Toggle opencode";
        }
        {
          mode = [
            "n"
            "x"
          ];
          key = "go";
          action.__raw = ''function() return require("opencode").operator("@this ") end'';
          options = {
            desc = "Add range to opencode";
            expr = true;
          };
        }
        {
          mode = "n";
          key = "goo";
          action.__raw = ''function() return require("opencode").operator("@this ") .. "_" end'';
          options = {
            desc = "Add line to opencode";
            expr = true;
          };
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
