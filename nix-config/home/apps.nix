{ pkgs, ... }: {
  home.packages = with pkgs; [
    vscode
  ];

  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fish = {
    enable = true;
    # interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
    #   "source ${sources.theme-bobthefish}/functions/fish_prompt.fish"
    #   "source ${sources.theme-bobthefish}/functions/fish_right_prompt.fish"
    #   "source ${sources.theme-bobthefish}/functions/fish_title.fish"
    #   (builtins.readFile ./config.fish)
    #   "set -g SHELL ${pkgs.fish}/bin/fish"
    # ]));

    shellAliases = {
      # ga = "git add";
      # gc = "git commit";
      # gco = "git checkout";
      # gcp = "git cherry-pick";
      # gdiff = "git diff";
      # gl = "git prettylog";
      # gp = "git push";
      # gs = "git status";
      # # gt = "git tag";

      # jf = "jj git fetch";
      # jn = "jj new";
      # js = "jj st";
    };

    # plugins = map (n: {
    #   name = n;
    #   src  = sources.${n};
    # }) [
    #   "fish-fzf"
    #   "fish-foreign-env"
    #   "theme-bobthefish"
    # ];
  };

  # modern vim
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    # Explicit to silence the stateVersion (pre-26.05) warnings.
    # Ruby provider disabled (adopting the new 26.05 default) — shrinks the closure.
    withRuby = false;
    withPython3 = true;
  };

  # A modern replacement for ‘ls’
  # useful in bash/zsh prompt, not in nushell.
  programs.eza = {
    enable = true;
    icons = "auto";
    git = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
  };

  # terminal file manager
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    # Keep the legacy shell wrapper name (pre-26.05 default). Change to "y"
    # to adopt the new default.
    shellWrapperName = "yy";
    settings = {
      manager = {
        show_hidden = true;
        sort_dir_first = true;
      };
    };
  };

  # # skim provides a single executable: sk.
  # # Basically anywhere you would want to use grep, try sk instead.
  # skim = {
  #   enable = true;
  #   enableBashIntegration = true;
  # };

}
