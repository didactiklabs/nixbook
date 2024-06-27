{pkgs, ...}: {
  config = {
    home.packages = [
      pkgs.ueberzugpp # for image preview ranger
    ];
    programs = {
      zathura.enable = true;
      imv.enable = true;
      ranger = {
        enable = true;
        extraConfig = ''
          set preview_images true
          set preview_images_method ueberzug
          set preview_files true
        '';
      };
      zoxide = {
        enable = true;
        enableZshIntegration = true;
      };
      bat = {
        enable = true;
        ## cf https://github.com/sharkdp/bat#customization
        config = {
          map-syntax = ["*.jenkinsfile:Groovy" "*.props:Java Properties"];
        };
      };
      fzf = {
        enable = true;
        enableZshIntegration = true;
      };
      eza = {
        enable = true;
        enableZshIntegration = true;
      };
      ripgrep = {
        enable = true;
      };

      zsh = {
        autosuggestion.enable = true;
        plugins = [
          {
            # will source zsh-autosuggestions.plugin.zsh
            name = "zsh-syntax-highlighting";
            src = pkgs.fetchFromGitHub {
              owner = "zsh-users";
              repo = "zsh-syntax-highlighting";
              rev = "refs/tags/0.8.0";
              sha256 = "sha256-iJdWopZwHpSyYl5/FQXEW7gl/SrKaYDEtTH9cGP7iPo=";
            };
          }
          {
            # will source zsh-autosuggestions.plugin.zsh
            name = "zsh-bat";
            src = pkgs.fetchFromGitHub {
              owner = "fdellwing";
              repo = "zsh-bat";
              rev = "master";
              sha256 = "sha256-7TL47mX3eUEPbfK8urpw0RzEubGF2x00oIpRKR1W43k=";
            };
          }
        ];
        enable = true;
        shellAliases = {
          vpn = "sudo ${pkgs.openvpn}/bin/openvpn --up ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --down ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --config";
          k = "kubectl";
          top = "btop";
          df = "duf";
          cd = "z";
          neofetch = "fastfetch";
          grep = "rg";
        };
        initExtra = ''
          fastfetch
        '';
        oh-my-zsh = {
          enable = true;
        };
      };
    };
  };
}
