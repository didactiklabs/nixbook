{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.opencodeConfig;
  ollamaModels = import ../nixosModules/ollamaModels.nix;
  # Build opencode provider models attrset from shared ollama model definitions
  # e.g. { "gemma4:26b" = { name = "Gemma 4 26B"; }; ... }
  ollamaProviderModels = builtins.listToAttrs (
    map (m: {
      name = m.id;
      value = {
        inherit (m) name;
      };
    }) ollamaModels
  );
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

    ollama = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable the Ollama provider for OpenCode.

          When enabled, configures an OpenAI-compatible Ollama provider
          with models defined in nixosModules/ollamaModels.nix.
        '';
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:11434/v1";
        description = "The base URL for the Ollama API endpoint.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      settings = {
        plugin = [
          "@ex-machina/opencode-anthropic-auth"
          "opencode-gemini-auth"
          "op-anthropic-auth@0.1.1"
        ];
        provider = lib.mkIf cfg.ollama.enable {
          ollama = {
            npm = "@ai-sdk/openai-compatible";
            name = "Ollama";
            options = {
              baseURL = cfg.ollama.baseUrl;
            };
            models = ollamaProviderModels;
          };
        };
      };
    };
  };
}
