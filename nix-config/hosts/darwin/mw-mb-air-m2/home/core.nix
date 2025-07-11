{pkgs, ...}: {
  # home-manager packages are installed to `/etc/profiles/per-user/mw/bin/`
  home.packages = with pkgs; [
    # editors, coding
    # neovim
    git
    graphite-cli
    just
    nixpkgs-fmt
    jujutsu
    podman
    xh
    docker-compose
    rancher
    code-cursor

    # Shell and Tooling
    fish
    eza
    yazi
    bat
    ripgrep # recursively searches directories for a regex pattern
    jq # A lightweight and flexible command-line JSON processor
    yq-go # yaml processer https://github.com/mikefarah/yq
    fzf # A command-line fuzzy finder
    skim

    # archives
    zip
    xz
    unzip
    p7zip

    # network
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing

    # misc
    cowsay
    file
    which
    tree
    gnused
    gnutar
    gawk
    zstd
    caddy
    gnupg

    # productivity
    glow # markdown previewer in terminal\
  ];

  programs = {
    # modern vim
    neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
    };

    # A modern replacement for ‘ls’
    # useful in bash/zsh prompt, not in nushell.
    eza = {
      enable = true;
      icons = "auto";
      git = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
    };

    # terminal file manager
    yazi = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        manager = {
          show_hidden = true;
          sort_dir_first = true;
        };
      };
    };

    # skim provides a single executable: sk.
    # Basically anywhere you would want to use grep, try sk instead.
    skim = {
      enable = true;
      enableBashIntegration = true;
    };
  };
}
