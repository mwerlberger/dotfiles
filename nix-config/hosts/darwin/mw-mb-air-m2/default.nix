{
  inputs,
  pkgs,
  username ? "mw",
  ...
}:
{
  system.primaryUser = "mw";

  # imports = [
  #   "${inputs.secrets}/work.nix"
  #   ./secrets.nix
  # ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "uninstall";
      upgrade = true;
    };
    brewPrefix = "/opt/homebrew/bin";
    caskArgs = {
      no_quarantine = true;
    };
    casks = [
      {
        name = "ghostty";
        greedy = true;
      }
      {
        name = "vivaldi";
        greedy = true;
      }
      "notion"
      "telegram"
      "libreoffice"
      "signal"
      "grid"
      "google-chrome"
      "handbrake"
      "tailscale"
      "bambu-studio"
      "element"
      "microsoft-outlook"
      "monitorcontrol"
      "raycast"
      "mattermost"
    ];
    brews = [
      "pulumi"
      "wget"
      "curl"
    ];
  };

  environment.systemPackages = with pkgs; [
    (python312Full.withPackages (
      ps: with ps; [
        pip
        jmespath
        requests
        setuptools
        pyyaml
        pyopenssl
      ]
    ))
    # inputs.agenix.packages."${system}".default
    # karabiner-elements
    # mkcert
    # pinentry.curses
    # spotify
    # sqlite
    # utm
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    bat
    caddy
    code-cursor
    cowsay
    discord
    docker
    docker-compose
    eza
    ffmpeg
    file
    fish
    fzf # A command-line fuzzy finder
    gawk
    git
    git-crypt
    git-filter-repo
    git-lfs
    glow # markdown previewer in terminal\
    gnupg
    gnused
    gnutar
    go
    go-outline
    gocode-gomod
    godef
    golint
    google-cloud-sdk
    gopkgs
    gopls
    gotools
    graphite-cli
    ice-bar
    iperf3
    jq
    jujutsu
    just
    maccy
    neofetch
    neovim
    nil
    nixfmt-rfc-style
    nixpkgs-fmt
    nmap
    nss
    nss.tools
    numi
    opentofu
    p7zip
    podman
    pre-commit
    pwgen
    raycast
    rectangle
    ripgrep
    rsync
    skim
    slack
    socat # replacement of openbsd-netcat
    stats
    tmux
    tree
    unzip
    wget
    which
    xh
    xz
    yq
    yq-go # yaml processer https://github.com/mikefarah/yq
    yt-dlp
    zip
    zstd
  ];

  system.stateVersion = 4;
}
