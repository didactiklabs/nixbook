{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  # Shared terminal command + options used by both the server.start hook and the
  # toggle keymap below.
  opencodeCmd = ''"opencode --port"'';
  snacksTerminalOpts = ''{ win = { position = "right", enter = false } }'';
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      # The native nixvim opencode module sets `vim.g.opencode_opts = settings`,
      # installs the `opencode-nvim` plugin and pulls in the `opencode` package
      # dependency, so no raw extraConfigLua / extraPackages is needed.
      plugins.opencode = {
        inherit (config.customHomeManagerModules.opencodeConfig) enable;
        settings = {
          server.start.__raw = ''
            function()
              require("snacks.terminal").open(${opencodeCmd}, ${snacksTerminalOpts})
            end
          '';
        };
      };

      opts.autoread = true;

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
          action.__raw = ''
            function()
              require("snacks.terminal").toggle(${opencodeCmd}, ${snacksTerminalOpts})
            end
          '';
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
