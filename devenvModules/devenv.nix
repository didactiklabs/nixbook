_: {
  git-hooks.hooks = {
    shellcheck.enable = true;
    mdsh.enable = true;
    treefmt = {
      enable = true;
      settings.fail-on-change = false;
    };
  };

  difftastic.enable = true;
  treefmt = {
    enable = true;
    config.programs = {
      nixfmt.enable = true;
      prettier = {
        enable = true;
        excludes = [
          ".git"
          ".devenv"
        ];
        settings = {
          proseWrap = "preserve";
        };
      };
      shfmt.enable = true;
      gofumpt.enable = true;
    };
  };
}
