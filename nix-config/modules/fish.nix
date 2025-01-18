{
  lib,
  sources,
  pkgs,
  ...
}: {
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
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdiff = "git diff";
      gl = "git prettylog";
      gp = "git push";
      gs = "git status";
      gt = "git tag";

      jf = "jj git fetch";
      jn = "jj new";
      js = "jj st";
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
}
