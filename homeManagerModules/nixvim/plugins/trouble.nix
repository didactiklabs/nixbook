{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      keymaps = [
        {
          mode = "n";
          key = "<leader>t";
          action = ":Trouble diagnostics toggle<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<leader>y";
          action = ":Trouble diagnostics focus<CR>";
          options.silent = true;
        }
      ];
      plugins.trouble = {
        enable = true;
      };
    };
  };
}
