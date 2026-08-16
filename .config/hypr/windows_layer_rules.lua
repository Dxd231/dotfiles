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
hl.window_rule({ match = { class = "org%.wezfurlong%.wezterm" },    float = true })
hl.window_rule({ match = { class = "org.pulseaudio.pavucontrol" },  float = true })
hl.window_rule({ match = { class = "nm-connection-editor" },        float = true })
hl.window_rule({ match = { class = "blueman-manager" },             float = true })
hl.window_rule({ match = { class = "steam" },                       float = true })
hl.window_rule({ match = { class = "xdg-desktop-portal" },          float = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" },      float = true })
hl.window_rule({ match = { class = "zoom" },                        float = true })
hl.window_rule({ match = { class = "waypaper" },                    float = true })
hl.window_rule({ match = { class = "Waydroid" },                    float = true })
hl.window_rule({ match = { class = "zalo" },                        float = true })
-- hl.window_rule({ match = { class = "org.kde.dolphin" },            opacity = "0.7 override 0.7 override 0.7 override" })

-- clipse floating clipboard
hl.window_rule({ match = { class = "clipse" }, float = true, size = { 622, 652 }, stay_focused = true })

-- Librewolf: force opaque + tiled, but PiP floats
-- hl.window_rule({ match = { class = "librewolf" },
--     opacity = "1 override 1 override 1 override",
--     tile = true,
-- })
hl.window_rule({ match = { class = "librewolf", title = "Picture-in-Picture" }, float = true, border_size = 0 })

-- No border when fullscreen
hl.window_rule({ match = { fullscreen = true }, border_size = 0 })

-- Steam games: fullscreen + immediate (tearing)
hl.window_rule({ match = { class = "steam_app_default" }, fullscreen = true, immediate = true })
hl.window_rule({ match = { class = "steam_app_3224770" }, fullscreen = true })

-- kitty: transparency
hl.window_rule({ match = { class = "kitty" }, opacity = "0.8 override 0.8 override 0.8 override" })

-- No border on workspace 1 windows
hl.window_rule({ match = { workspace = "w[1]" }, border_size = 0 })

-- Floating windows: rounded corners + fully opaque
hl.window_rule({ match = { float = true }, rounding = 2 })

-- Fullscreen apps
hl.window_rule({ match = { class = "org.vinegarhq.Sober" },   fullscreen = true })
hl.window_rule({ match = { class = "com.mojang.minecraft" },  fullscreen = true })

-- Desktop gremlins overlay: no decoration
hl.window_rule({ match = { title = "ilgwg_desktop_gremlins.py" },
    no_blur   = true,
    no_shadow = true,
    border_size = 0,
})

-- Spotify: slight transparency
hl.window_rule({ match = { class = "spotify" }, opacity = "0.9 0.9 0.9" })

-- =============================================================================
-- Workspace Rules
-- =============================================================================

-- Workspaces 1–8 on DP-3
hl.workspace_rule({ workspace = "1", monitor = "DP-3", default = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-3", persistent = true})
hl.workspace_rule({ workspace = "3", monitor = "DP-3", persistent = true})
hl.workspace_rule({ workspace = "4", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "5", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "6", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "7", monitor = "DP-3", persistent = true})
hl.workspace_rule({ workspace = "8", monitor = "DP-3", persistent = true})
hl.workspace_rule({ workspace = "9", monitor = "DP-3", persistent = true })
hl.workspace_rule({ workspace = "10", monitor = "DP-3", persistent = true })

-- -- Workspace 9 on HDMI-A-1 with master layout and custom gaps
-- hl.workspace_rule({ workspace = "name:1",
--     monitor  = "DP-3",
--     layout   = "master",
-- })

-- Special workspace 1: dwindle with large outer gaps
hl.workspace_rule({ workspace = "s[1]",
    layout   = "scrolling",
    gaps_out = 70,
})

-- hl.workspace_rule({ workspace = "1",
--     layout   = "dwindle",
-- })


hl.window_rule({
    float = true,
    center = true,
    size = "500 500",
    match = {
        class = "hyprland-share-picker"
    }
})
-- =============================================================================
-- Layer Rules
-- =============================================================================

-- swaync: no animation, blur, semi-transparent
hl.layer_rule({ match = { namespace = "swaync-control-center" },
    blur        = true,
    ignore_alpha = 0.5,
    animation = "slide top"
})
hl.layer_rule({ match = { namespace = "swaync-notification-window" },
    blur        = true,
    ignore_alpha = 0.5,
    animation = "slide"
})

hl.layer_rule({ match = { namespace = "snappy-switcher" },
    blur        = true,
    ignore_alpha = 0.5,
    animation = "slide"
})

-- rofi: no animation, blur, semi-transparent
hl.layer_rule({ match = { namespace = "rofi" },
    no_anim     = true,
    blur        = true,
    ignore_alpha = 0.5,
})

-- fuzzel/launcher: blur, semi-transparent
hl.layer_rule({ match = { namespace = "launcher" },
    blur        = true,
    ignore_alpha = 0.5,
    animation = "slide top"
})

hl.layer_rule({ match = { namespace = "quickshell:thebar" },
    blur        = true,
    ignore_alpha = 0.5,
    blur_popups = true,
})

hl.layer_rule({ match = { namespace = "quickshell:wallpaperswitcher" },
    blur        = true,
    ignore_alpha = 0.3,
    blur_popups = true,
})


hl.layer_rule({
    match = { namespace = "quickshell:mypopup" },
    blur = true,
    ignore_alpha = 0.3,
})

hl.layer_rule({
    match = { namespace = "quickshell:popup" },
    blur = true,
    ignore_alpha = 0.3,
})

hl.layer_rule({
    match = { namespace = "quickshell:applauncher" },
    blur = true,
    ignore_alpha = 0.3,
    animation = "slidefade"
})

hl.layer_rule({
    match = { namespace = "quickshell:wallpaperswitcher" },
    blur = true,
    ignore_alpha = 0.3,
    animation = "slide bottom"
})

hl.layer_rule({
    match = { namespace = "quickshell:osd" },
    blur = true,
    ignore_alpha = 0.3,
    animation = "fade"
})

hl.layer_rule({
    match = { namespace = "quickshell:clipboardmanager" },
    blur = true,
    ignore_alpha = 0.3,
    animation = "slidefade top"
})

hl.layer_rule({
    match = { namespace = "quickshell:center" },
    blur = true,
    ignore_alpha = 0.3,
    animation = "slidefade left"
})
