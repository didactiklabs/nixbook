{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.opencodeConfig;
in
{
  options.customHomeManagerModules.opencodeConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable OpenCode AI coding assistant configuration.

        OpenCode is an AI-powered terminal coding assistant that supports
        multiple LLM providers through a plugin system.

        This configuration enables programs.opencode with two authentication
        plugins:
          - opencode-gemini-auth       — Google Gemini OAuth authentication
          - opencode-anthropic-oauth   — Anthropic Claude OAuth authentication

        When enabled, other modules integrate with OpenCode:
          - rtkConfig: runs `rtk init -g --opencode` to wire up the RTK
            auto-rewrite hook for token optimisation
          - goji.nix: goji-ai uses `opencode run` to generate commit messages
          - dmsConfig: the opencodeUsage bar widget shows token consumption

        Requires `opencode auth login` after activation to authenticate with
        a provider.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      settings = {
        plugin = [
          "opencode-gemini-auth"
          "opencode-anthropic-auth"
          "op-anthropic-auth"
        ];
      };
    };
  };
}
