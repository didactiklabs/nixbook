{
  osConfig,
  ...
}:
{
  programs.dank-material-shell = {
    plugins = {
      sathiAi = {
        settings = {
          geminiApiKeyFile = osConfig.age.secrets.gemini-api-key.path;
        };
      };
    };
  };
}
