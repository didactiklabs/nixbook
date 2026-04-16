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
    programs.nixvim.plugins = {
      lsp.servers.ruff.enable = true;
      none-ls.sources = {
        diagnostics.pylint.enable = lib.mkForce false;
        formatting.black.enable = lib.mkForce false;
      };
    };
  };
}
