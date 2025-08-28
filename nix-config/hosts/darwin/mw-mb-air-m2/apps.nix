{ pkgs
, ...
}:
{
  environment.systemPackages = with pkgs; [
    # (python312Full.withPackages (
    #   ps: with ps; [
    #     pip
    #     # jmespath
    #     # requests
    #     # setuptools
    #     # pyyaml
    #     # pyopenssl
    #   ]
    # ))
    # inputs.agenix.packages."${system}".default
    # karabiner-elements
    # mkcert
    # pinentry.curses
    # spotify
    # sqlite
    # utm
    # arc-browser
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    bat
    chatgpt
    code-cursor
    cowsay
    deploy-rs
    discord
    docker
    # docker-compose
    eza
    fastfetch
    ffmpeg
    file
    fish
    fzf
    gawk
    git
    git-crypt
    git-filter-repo
    git-lfs
    glow
    gnupg
    gnused
    gnutar
    # go
    # go-outline
    # gocode-gomod
    # godef
    # golint
    # google-cloud-sdk
    # gopkgs
    # gopls
    # gotools
    graphite-cli
    ice-bar
    iperf3
    jq
    # jujutsu
    just
    libation
    maccy
    neovim
    nil
    nixfmt-rfc-style
    nixpkgs-fmt
    nmap
    # nss
    # nss.tools
    numi
    opentofu
    p7zip
    podman
    pre-commit
    pwgen
    raycast
    rectangle
    # ripgrep
    rsync
    slack
    skim
    socat
    stats
    # tailscale
    tmux
    tree
    unzip
    wget
    which
    xh
    xld
    xz
    yq
    yq-go
    yt-dlp
    zip
    zstd
  ];

  # programs.zsh.enable = true;
  # If you use fish or bash, enable them instead:
  programs.fish.enable = true;
  # programs.bash.enable = true;
}
