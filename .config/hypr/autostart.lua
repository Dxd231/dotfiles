-- █████╗ ██╗   ██╗████████╗ ██████╗ ███████╗████████╗ █████╗ ██████╗ ████████╗
--██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗╚══██╔══╝
--███████║██║   ██║   ██║   ██║   ██║███████╗   ██║   ███████║██████╔╝   ██║   
--██╔══██║██║   ██║   ██║   ██║   ██║╚════██║   ██║   ██╔══██║██╔══██╗   ██║   
--██║  ██║╚██████╔╝   ██║   ╚██████╔╝███████║   ██║   ██║  ██║██║  ██║   ██║   
--╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   

-- ==================
-- STARTUP APPS
-- ==================
hl.on("hyprland.start", function () 
  hl.exec_cmd("snappy-switcher --daemon")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("/usr/lib/mate-polkit/polkit-mate-authentication-agent-1")
  hl.exec_cmd("fcitx5")
  hl.exec_cmd("swayosd-server")
  hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
  hl.exec_cmd("hyprsunset")
  hl.exec_cmd("swaync")
  hl.exec_cmd("~/material-bibata-cursor/scripts/cursor_matugen.sh")
  hl.exec_cmd("quickshell")
  hl.exec_cmd("hypridle")
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
  hl.exec_cmd("musicpresence")
  hl.exec_cmd("wayvibes ~/wayvibes/soundpacks/nk-cream -v 5 --background")
  hl.exec_cmd("hyprpm reload")
  hl.exec_cmd("awww-daemon")
  hl.exec_cmd("hyprctl dispatch 'hl.dsp.focus({ workspace = 1 })'")
  hl.exec_cmd("systemctl --user enable --now opentabletdriver")
  hl.exec_cmd("spicetify watch -s &>/dev/null")
  hl.exec_cmd("otd-daemon")
end)


