{
  programs.nixvim.autoCmd = [
    {
      event = "VimEnter";
      pattern = [
        "*"
      ];
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
}
