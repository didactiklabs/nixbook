{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.ollama;
in
{
  options.customNixOSModules.ollama = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Ollama local LLM inference server.

        Ollama is an open-source framework for running large language models
        locally.  This module:

        - Runs Ollama as a systemd service (services.ollama)
        - Uses ROCm GPU acceleration for AMD GPUs
        - Preloads the Gemini Gemma 4 27B model on first start
        - Exposes the Ollama API at http://localhost:11434

        Used on: anya (gaming/streaming desktop with AMD GPU).
        Reference: https://wiki.nixos.org/wiki/Ollama
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = pkgs.ollama-rocm;
      loadModels = [ "gemma4:latest" ];
      host = "0.0.0.0";
    };
  };
}
