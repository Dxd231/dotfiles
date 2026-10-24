--██╗    ██╗██╗███╗   ██╗██████╗  ██████╗ ██╗    ██╗███████╗     █████╗ ███╗   ██╗██████╗     ██╗      █████╗ ██╗   ██╗███████╗██████╗     ██████╗ ██╗   ██╗██╗     ███████╗███████╗
--██║    ██║██║████╗  ██║██╔══██╗██╔═══██╗██║    ██║██╔════╝    ██╔══██╗████╗  ██║██╔══██╗    ██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗    ██╔══██╗██║   ██║██║     ██╔════╝██╔════╝
--██║ █╗ ██║██║██╔██╗ ██║██║  ██║██║   ██║██║ █╗ ██║███████╗    ███████║██╔██╗ ██║██║  ██║    ██║     ███████║ ╚████╔╝ █████╗  ██████╔╝    ██████╔╝██║   ██║██║     █████╗  ███████╗
--██║███╗██║██║██║╚██╗██║██║  ██║██║   ██║██║███╗██║╚════██║    ██╔══██║██║╚██╗██║██║  ██║    ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗    ██╔══██╗██║   ██║██║     ██╔══╝  ╚════██║
--╚███╔███╔╝██║██║ ╚████║██████╔╝╚██████╔╝╚███╔███╔╝███████║    ██║  ██║██║ ╚████║██████╔╝    ███████╗██║  ██║   ██║   ███████╗██║  ██║    ██║  ██║╚██████╔╝███████╗███████╗███████║
-- ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝

-- =============================================================================
-- Window Rules
-- =============================================================================

-- Float various utility apps
hl.window_rule({ match = { class = "org%.wezfurlong%.wezterm" }, float = true })
hl.window_rule({ match = { class = "org.pulseaudio.pavucontrol" }, float = true })
hl.window_rule({ match = { class = "nm-connection-editor" }, float = true })
hl.window_rule({ match = { class = "blueman-manager" }, float = true })
hl.window_rule({ match = { class = "steam" }, float = true })
hl.window_rule({ match = { class = "xdg-desktop-portal" }, float = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, float = true })
hl.window_rule({ match = { class = "zoom" }, float = true })
hl.window_rule({ match = { class = "waypaper" }, float = true })
hl.window_rule({ match = { class = "Waydroid" }, float = true })
hl.window_rule({ match = { class = "zalo" }, float = true })
-- hl.window_rule({ match = { class = "org.kde.dolphin" },            opacity = "0.7 override 0.7 override 0.7 override" })

-- clipse floating clipboard
hl.window_rule({ match = { class = "clipse" }, float = true, size = { 622, 652 }, stay_focused = true })

-- Jisho lookup window opened from the subtitle word card (Services/Lexicon.qml lookupOnline)
hl.window_rule({ match = { class = "qs-lookup" }, float = true, size = { 1000, 760 }, center = true, pin = true })

hl.window_rule({ match = { class = "org.gnome.Calculator" }, float = true, size = { 360, 616 }, stay_focused = true })

hl.window_rule({ match = { class = "librewolf", title = "Picture-in-Picture" }, float = true, border_size = 0 })

-- Steam games: fullscreen + immediate (tearing)
hl.window_rule({ match = { class = "steam_app_default" }, fullscreen = true, immediate = true })
hl.window_rule({ match = { class = "steam_app_3224770" }, fullscreen = true })

-- kitty: transparency
-- hl.window_rule({ match = { class = "kitty" }, opacity = "0.8 override 0.8 override 0.8 override" })
hl.window_rule({ match = { class = "^th" }, opacity = "1 override 1 override 1 override" })
-- Fullscreen apps
hl.window_rule({ match = { class = "org.vinegarhq.Sober" }, fullscreen = true })
hl.window_rule({ match = { class = "com.mojang.minecraft" }, fullscreen = true })

-- Desktop gremlins overlay: no decoration
hl.window_rule({
	match = { title = "ilgwg_desktop_gremlins.py" },
	no_blur = true,
	no_shadow = true,
	border_size = 0,
})

-- =============================================================================
-- Workspace Rules
-- =============================================================================

-- Workspaces 1–8 on DP-3
hl.workspace_rule({ workspace = "1", monitor = "DP-3", default = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "3", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "5", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "6", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "7", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "8", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "9", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "10", monitor = "DP-3", persistent = true })

-- -- Workspace 9 on HDMI-A-1 with master layout and custom gaps
-- hl.workspace_rule({ workspace = "name:1",
--     monitor  = "DP-3",
--     layout   = "master",
-- })

-- Special workspace 1: dwindle with large outer gaps
hl.workspace_rule({ workspace = "s[1]", layout = "scrolling", gaps_out = 70, gaps_in = 20 })

-- hl.workspace_rule({ workspace = "1",
--     layout   = "dwindle",
-- })

-- ~/.config/hypr/hyprland.lua

hl.window_rule({
	match = { class = "^(com.gabm.satty)$" },
	float = true,
})

-- Or as a named rule (if you want a handle to toggle it dynamically)
hl.window_rule({
	name = "mpv-render-unfocused",
	match = { class = "^(mpv)$" },
	render_unfocused = true,
})

hl.window_rule({
	float = true,
	center = true,
	size = "500 500",
	match = {
		class = "hyprland-share-picker",
	},
})

hl.window_rule({
	match = { title = ".*Private Browsing.*" },
	no_screen_share = true,
})
-- =============================================================================
-- Layer Rules
-- =============================================================================

hl.layer_rule({
	match = { namespace = "snappy-switcher" },
	blur = true,
	ignore_alpha = 0.5,
	animation = "slide",
})

hl.layer_rule({
	match = { namespace = "quickshell:manga" },
	blur = false,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:thebar" },
	blur = false,
	ignore_alpha = 0.2,
	blur_popups = true,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:wallpaperswitcher" },
	blur = true,
	ignore_alpha = 0.3,
	blur_popups = true,
	no_anim = true,
})

hl.layer_rule({ match = { namespace = "selection" }, animation = "fade" })

hl.layer_rule({
	match = { namespace = "quickshell:mypopup" },
	blur = true,
	ignore_alpha = 0.3,
})

hl.layer_rule({
	match = { namespace = "quickshell:popup" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:powermenu" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:mpris_popup" },
	blur = false,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:calendar_popup" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:dock" },
	blur = false,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:applauncher" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:wallpaperswitcher" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:osd" },
	blur = false,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell-share-picker" },
	blur = false,
	ignore_alpha = 0.3,
	animation = "popin 50%",
})

hl.layer_rule({
	match = { namespace = "quickshell:clipboardmanager" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:center" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:volume_popup" },
	blur = false,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:ocr" },
	blur = false,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:ocrcard" },
	blur = false,
	no_anim = true,
})

-- Screenshot / recording panels (the shell animates them itself)
for _, ns in ipairs({
	"quickshell:capture", -- the picker
	"quickshell:capturecard", -- the result card
	"quickshell:capturecount", -- the delay countdown
	"quickshell:captureframe", -- brackets around a region being recorded
	"quickshell:capturegrab", -- the hidden window that renders window / workspace shots
}) do
	hl.layer_rule({
		match = { namespace = ns },
		blur = false,
		no_anim = true,
	})
end

hl.layer_rule({
	match = { namespace = "quickshell:controlcenter" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:system_status_popup" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

hl.layer_rule({
	match = { namespace = "quickshell:dock_preview" },
	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})

-- Remaining quickshell panels: no compositor animation, the shell animates them itself
for _, ns in ipairs({
	"quickshell:closing_apps",
	"quickshell:closing_goodbye",
	"quickshell:closing_tint",
	"quickshell:copy_toast",
	"quickshell:emoji_picker",
	"quickshell:screen_frame",
	"quickshell:session_restore",
	"quickshell:shelf",
	"quickshell:shelf_edge",
	"quickshell:subs",
	"quickshell:tray_menu_dismiss",
}) do
	hl.layer_rule({
		match = { namespace = ns },
		no_anim = true,
	})
end
