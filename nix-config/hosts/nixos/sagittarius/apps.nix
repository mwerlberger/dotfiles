{ pkgs
, ...
}:
{
  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    gptfdisk
    smartmontools
    e2fsprogs
    fio
    lsof
    ethtool
    nettools
    ipmitool
    tmux
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    curl
    #git
    graphite-cli
    just
    fish
    bat
    eza
    yazi
    ripgrep
    jq
    yq-go
    fzf
    skim
    delta
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
}
