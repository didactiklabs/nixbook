let
  subscriptionsConfig = ''
    https://www.youtube.com/channel/UCf9h3TSEiAiwubyWpLUtdwg # Laganne
    https://www.youtube.com/channel/UCTt2AnK--mnRmICnf-CCcrw # Rire Jaune
    https://www.youtube.com/channel/UC8Q0SLrZLiTj5s4qc9aad-w # Mister V
    https://www.youtube.com/channel/UCutXfzLC5wrV3SInT_tdY0w # WongFu Productions
    https://www.youtube.com/channel/UCUo1RqYV8tGjV38sQ8S5p9A # HugoDécrypte
    https://www.youtube.com/channel/UCWnfDPdZw6A23UtuBpYBbAg # Dr Nozman
    https://www.youtube.com/channel/UCOGJ1pFCYj65_kDgAlHRH8w # Thao Huynh
    https://www.youtube.com/channel/UCfz8x0lVzJpb_dgWm9kPVrw # DevOps Toolkit
    https://www.youtube.com/channel/UCZgt6AzoyjslHTC9dz0UoTw # ByteByteGo
    https://www.youtube.com/channel/UCHnyfMqiRRG1u-2MsSQLbXA # Veritasium
  '';
in
{
  config = {
    home = {
      file = {
        ".config/ytfzf/subscriptions" = {
          text = subscriptionsConfig;
        };
      };
    };
  };
}
