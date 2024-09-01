{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules;
  subscriptionsConfig = ''
    https://www.youtube.com/channel/UCf9h3TSEiAiwubyWpLUtdwg
    https://www.youtube.com/channel/UCTt2AnK--mnRmICnf-CCcrw
    https://www.youtube.com/channel/UCL-y95OCyfWeGVIH-gpG1aA
    https://www.youtube.com/channel/UC8Q0SLrZLiTj5s4qc9aad-w
    https://www.youtube.com/channel/UCutXfzLC5wrV3SInT_tdY0w
    https://www.youtube.com/channel/UCUo1RqYV8tGjV38sQ8S5p9A
    https://www.youtube.com/channel/UCWnfDPdZw6A23UtuBpYBbAg
  '';
in
{
  config = lib.mkIf cfg.desktopApps.enable {
    home = {
      file = {
        ".config/ytfzf/subscriptions" = {
          text = subscriptionsConfig;
        };
      };
    };
  };
}
