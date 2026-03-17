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
    programs.nixvim.autoCmd = [
      {
        event = "BufRead";
        pattern = [ "*" ];
        command = "Neotree action=show";
      }
      # Enable spellcheck for some filetypes
      {
        event = "FileType";
        pattern = [
          "tex"
          "latex"
          "markdown"
        ];
        command = "setlocal spell spelllang=en,fr";
      }
    ];
  };
}
