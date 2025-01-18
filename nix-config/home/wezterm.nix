{...}: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      local wezterm = require 'wezterm'
      local config = wezterm.config_builder()
      config.color_scheme = "catppuccino-macchiato"
      config.font_size = 12.0
      config.font = wezterm.font "MesloLGS Nerd Font Mono"
      config.macos_window_background_blur = 30
      config.window_background_opacity = 1
      config.window_decorations = 'RESIZE'
      config.audible_bell = "Disabled"
      config.front_end = "WebGpu"

      return config
    '';
  };
}
