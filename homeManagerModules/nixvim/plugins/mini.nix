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
    programs.nixvim.plugins.mini = {
      enable = true;
      mockDevIcons = true;
      modules = {
        # Text objects
        ai = {
          n_lines = 50;
          search_method = "cover_or_next";
        };
        # Surround actions
        surround = {
          mappings = {
            add = "gsa";
            delete = "gsd";
            find = "gsf";
            find_left = "gsF";
            highlight = "gsh";
            replace = "gsr";
            update_n_lines = "gsn";
          };
        };
        # Autopairs
        pairs = { };
        # Move lines/selections
        move = {
          mappings = {
            left = "<C-Left>";
            right = "<C-Right>";
            down = "<C-Down>";
            up = "<C-Up>";
            line_left = "<C-Left>";
            line_right = "<C-Right>";
            line_down = "<C-Down>";
            line_up = "<C-Up>";
          };
        };
        # Better f/t motions
        jump = {
          mappings = {
            forward = "f";
            backward = "F";
            forward_till = "t";
            backward_till = "T";
            repeat_forward = ";";
            repeat_backward = ",";
          };
        };
        # Icons
        icons = { };
        # Indentation guides
        indentscope = {
          symbol = "│";
          options.try_as_border = true;
        };
        # Buffer management
        bufremove = { };
        # Diff view
        diff = {
          view.style = "sign";
        };
        # Git hunk actions
        git = { };
        # Trailspace trimmer
        trailspace = { };
      };
    };
  };
}
