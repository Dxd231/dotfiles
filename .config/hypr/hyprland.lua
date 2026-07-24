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
    gaps_in             = 10,
    gaps_out            = 35,
    border_size         = 3,
    allow_tearing       = true,

    col = {
      active_border     = on_primary,
      inactive_border   = "rgba(00000050)",
  },
    layout              = "scrolling"
  }
})
-- ==================
-- DECORATION
-- ==================
hl.config({
  decoration = {
    rounding              = 1,
    rounding_power        = 3.0,
    dim_special           = 0.2,
    dim_inactive          = true,
    dim_strength          = 0.3,
    active_opacity        = 1.0,
    inactive_opacity      = 1.0,
    border_part_of_window = false,
    shadow = {
        enabled       = false,
        range         = 15,
        render_power  = 3,
        offset        = "0.3 0.3",
        color         = "rgba(00000070)"
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
-- Beziers
hl.curve("easeInOutBack",   { type = "bezier", points = { {0.68, -0.6}, {0.32, 1.6} } })
hl.curve("easeoutCubic",    { type = "bezier", points = { {0.33, 1}, {0.68, 1} } })
hl.curve("easeOutCirc",     { type = "bezier", points = { {0, 0.55}, {0.45, 1} } })
hl.curve("easeOutQuart",    { type = "bezier", points = { {0.25, 1}, {0.5, 1} } })
hl.curve("easeInOutSine",   { type = "bezier", points = { {0.37, 0}, {0.63, 1} } })
hl.curve("easeOutBack",     { type = "bezier", points = { {0.34, 1.56}, {0.64, 1} } })
-- Springs
hl.curve("easy",            { type = "spring", mass = 1, stiffness = 662, dampening = 35.6 })
-- hl.curve("bouncy",          { type = "spring", mass = 1, stiffness = 610, dampening = 25 })
-- Snappy / Fast (good for window switching)
hl.curve("snappy",          { type = "spring", mass = 1, stiffness = 600, dampening = 25 })

-- Gentle / Smooth (good for fade or workspace sliding)
hl.curve("smooth",          { type = "spring", mass = 1, stiffness = 650, dampening = 30 })

-- Bouncy / Playful (visible overshoot and spring back)
hl.curve("bouncy",          { type = "spring", mass = 1, stiffness = 650, dampening = 25 })


hl.animation({ leaf = "windowsIn",                enabled = true, speed = 1, spring = "smooth",       style = "slide top" })
hl.animation({ leaf = "windowsOut",               enabled = true, speed = 4, bezier = "easeOutBack",  style = "popin" })
hl.animation({ leaf = "workspaces",               enabled = true, speed = 1, spring = "easy",         style = "slidevert" })
hl.animation({ leaf = "border",                   enabled = true, speed = 3, bezier = "easeoutCubic" })
hl.animation({ leaf = "specialWorkspace",         enabled = true, speed = 2, spring = "snappy",       style =  "slidevert -100%" })
hl.animation({ leaf = "windowsMove",              enabled = true, speed = 4, spring = "easy",         style = "slide" })
hl.animation({ leaf = "layers",                   enabled = true, speed = 4, spring = "easy",         style = "fade" })
-- hl.animation({ leaf = "layersOut",                enabled = true, speed = 5, spring = "easy",         style = "fade" })

hl.config({  
  scrolling = {
    column_width = 0.66,
    focus_fit_method = 1,
    follow_focus = true,
  },
  dwindle = {
    preserve_split = true
  },
  misc = {
    disable_hyprland_logo = true
  }
})
