{
  config,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim.plugins.startify = {
      enable = true;

      settings = {
        custom_header = [
          ""
          "     ███╗   ██╗██╗██╗  ██╗██╗   ██╗██╗███╗   ███╗"
          "     ████╗  ██║██║╚██╗██╔╝██║   ██║██║████╗ ████║"
          "     ██╔██╗ ██║██║ ╚███╔╝ ██║   ██║██║██╔████╔██║"
          "     ██║╚██╗██║██║ ██╔██╗ ╚██╗ ██╔╝██║██║╚██╔╝██║"
          "     ██║ ╚████║██║██╔╝ ██╗ ╚████╔╝ ██║██║ ╚═╝ ██║"
          "     ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝     ╚═╝"
        ];

        # When opening a file or bookmark, change to its directory.
        change_to_dir = true;

        # By default, the fortune header uses ASCII characters, because they work for everyone.
        # If you set this option to 1 and your 'encoding' is "utf-8", Unicode box-drawing characters will
        # be used instead.
        use_unicode = true;

        lists = [
          {
            type = "dir";
            header = ["   Recent Files"];
          }
        ];
        files_number = 10;

        skiplist = [
          "flake.lock"
        ];
      };
    };
  };
}
