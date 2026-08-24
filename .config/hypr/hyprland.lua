require("autostart")
require("windows_layer_rules")
require("keybinds")
require("colors")

hl.monitor({
	output = "DP-3",
	mode = "1920x1080@100",
	position = "0x0",
	scale = "1",
})

hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_QPA_PLATFORMTHEME_QT6", "gtk3")
hl.env("TERMINAL", "kitty")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("MOZ_WEBRENDER", "1")
hl.env("GTK_USE_PORTAL","1")
hl.env("GDK_DEBUG", "portals")
hl.env("QT_IM_MODULES","wayland;fcitx")

hl.config({
  cursor = {
    no_hardware_cursors = 1,
  },
  input = {
    kb_layout = "us",
    numlock_by_default = true,
    repeat_rate = 70,
    repeat_delay = 400,
  },
})

hl.device = {
  name = "kingsis-peripherals-zowie-gaming-mouse",
   sensitivity = -0.3
}

-- ==================
-- GENERAL LAYOUT
-- ==================
hl.config({
  general = {
    gaps_in             = 8,
    gaps_out            = 15,
    border_size         = 0,
    allow_tearing       = true,

    col = {
      active_border     = source_color,
      inactive_border   = "rgba(00000000)",
  },
    layout              = "scrolling"
  }
})
-- ==================
-- DECORATION
-- ==================
hl.config({
  decoration = {
    rounding              = 18,
    rounding_power        = 4.0,
    dim_special           = 0.2,
    dim_inactive          = false,
    dim_strength          = 0.3,
    active_opacity        = 1.0,
    inactive_opacity      = 1.0,
    border_part_of_window = false,
    shadow = {
        enabled       = true,
        range         = 18,
        render_power  = 4,
        offset        = "1 1",
        color         = "rgba(00000090)",
    },
    blur = {
        enabled       = true,
        size          = 3,
        passes        = 3,
        vibrancy      = 0.1696,
    },
  }
})
-- =================
-- ANIMATTION
-- =================

hl.curve("smooth", { type = "spring", mass = 1, stiffness = 1000, dampening = 63.2 })

hl.curve("easeOutBack", { type = "bezier", points = { {0.5, 1}, {0.89, 1} } })

hl.curve("niri_spring", { type = "spring", mass = 1, stiffness = 1000, dampening = 63.2 })

hl.curve("easeoutCubic", { type = "bezier", points = { {0.33, 1}, {0.68, 1} } })

hl.curve("snappy", { type = "spring", mass = 1, stiffness = 900, dampening = 40.3 })

hl.curve("easy", { type = "spring", mass = 1, stiffness = 800, dampening = 56.6 })

hl.animation({ leaf = "windowsIn",                enabled = true, speed = 1, spring = "smooth",               style = "popin 50%" })
hl.animation({ leaf = "windowsOut",               enabled = true, speed = 1, bezier = "easeOutBack",          style = "popin 10%" })
hl.animation({ leaf = "workspaces",               enabled = true, speed = 1, spring = "niri_spring",          style = "slidevert" })
hl.animation({ leaf = "border",                   enabled = true, speed = 3, bezier = "easeoutCubic" })
hl.animation({ leaf = "specialWorkspace",         enabled = true, speed = 1, spring = "snappy",               style =  "slidevert -100%" })
hl.animation({ leaf = "windowsMove",              enabled = true, speed = 4, spring = "easy",                 style = "slide" })
hl.animation({ leaf = "layers",                   enabled = true, speed = 4, spring = "easy",                 style = "slide" })
hl.animation({ leaf = "layersOut",                enabled = true, speed = 5, spring = "easy",                 style = "slide" })

hl.config({
  scrolling = {
    column_width = 0.6,
    focus_fit_method = 1,
    follow_focus = true,
  },
  dwindle = {
    preserve_split = true
  },
  misc = {
    disable_hyprland_logo = true,
    on_focus_under_fullscreen = 1,
    font_family = "Google Sans Code",
    key_press_enables_dpms  = true,
  }
})
-- ~/.config/hypr/hyprland.lua

hl.config({
  input = {
      follow_mouse = 1,
  },
})

hl.config({
  plugin = {
    hypr_autoscroll = {
      enabled = true,
      direct_activation = false,
      button = 274,
      dead_zone = 12.0,
      sensitivity = 2.0,
      acceleration = 1.005,
      max_speed = 1000.0,
      horizontal = true,
      vertical = true,
      frame_interval_ms = 16,
    },
  },
})





