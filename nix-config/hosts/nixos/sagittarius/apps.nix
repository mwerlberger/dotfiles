{
  pkgs,
  pkgs-unstable,
  ...
}:
{
  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    agenix-cli
    bat
    curl
    delta
    dnsutils # provides dig, nslookup, etc.
    e2fsprogs
    ethtool
    eza
    fio
    fish
    fzf
    gptfdisk
    immich-cli
    inetutils
    ipmitool
    jq
    just
    lsof
    nettools
    nil
    nixpkgs-fmt
    pkgs-unstable.claude-code
    pkgs-unstable.graphite-cli
    pciutils
    python314
    uv
    ripgrep
    skim
    smartmontools
    tcpdump
    tmux
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    wireguard-tools
    yazi
    yq-go
  ];
  programs.git = {
    enable = true;
    config = {
      user.email = "code@werlberger.org";
      user.Name = "Manuel Werlberger";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.mosh.enable = true;
  programs.htop.enable = true;
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # For VSCode remote server, we need to add a compatbility wrapper
  programs.nix-ld.enable = true;
  # programs.nix-ld-rs.enable = true;
}
