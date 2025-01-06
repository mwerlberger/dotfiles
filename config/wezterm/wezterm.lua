local wezterm = require("wezterm")
local config = {}

--config.color_scheme = "AtomOneLight"
config.color_scheme = "Catppuccin Latte"

config.font = wezterm.font("Hasklug Nerd Font Mono")
config.font_size = 14
config.visual_bell = {
	fade_in_duration_ms = 75,
	fade_out_duration_ms = 75,
	target = "CursorColor",
}
config.audible_bell = "Disabled"

return config
