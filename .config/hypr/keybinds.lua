--██╗  ██╗███████╗██╗   ██╗██████╗ ██╗███╗   ██╗██████╗ ███████╗#
--██║ ██╔╝██╔════╝╚██╗ ██╔╝██╔══██╗██║████╗  ██║██╔══██╗██╔════╝#
--█████╔╝ █████╗   ╚████╔╝ ██████╔╝██║██╔██╗ ██║██║  ██║███████╗#
--██╔═██╗ ██╔══╝    ╚██╔╝  ██╔══██╗██║██║╚██╗██║██║  ██║╚════██║#
--██║  ██╗███████╗   ██║   ██████╔╝██║██║ ╚████║██████╔╝███████║#
--╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝#

-- ==================
-- KEYBINDINGS
-- ==================
local mod = "SUPER"
hl.bind(mod .. "+ ALT + S", hl.dsp.exec_cmd("~/.local/bin/save-clipboard-image-now"))
hl.bind(mod .. "+ P", hl.dsp.window.pin())
hl.bind(mod .. "+ O", hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }))
hl.bind(mod .. "+ T", hl.dsp.exec_cmd("kitty"))
hl.bind(mod .. "+ space", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mod .. "+ period", hl.dsp.exec_cmd("qs ipc call emojipicker toggle"))
hl.bind(mod .. "+ SHIFT + R", hl.dsp.exec_cmd("~/appkill.sh"))
hl.bind(mod .. " + H", hl.dsp.exec_cmd("killall -s SIGUSR1 waifuland"))
hl.bind(mod .. "+ W", hl.dsp.exec_cmd("qs -p .config/quickshell/shell.qml ipc call wallpaper toggle"))
hl.bind(mod .. "+ M", hl.dsp.exec_cmd("qs ipc call manga toggle"))
hl.bind(mod .. "+ C", hl.dsp.exec_cmd("qs -p .config/quickshell/shell.qml ipc call controlcenter toggle"))
hl.bind(mod .. "+ SHIFT + C", hl.dsp.exec_cmd("qs -p .config/quickshell/shell.qml ipc call notifications toggle"))
hl.bind(mod .. " + Tab", hl.dsp.exec_cmd("snappy-switcher next"))
hl.bind(mod .. " + SHIFT + Tab", hl.dsp.exec_cmd("snappy-switcher prev"))
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("qs ipc call powermenu toggle"))

hl.bind(
	mod .. " + E",
	hl.dsp.exec_cmd(
		'kitty sh -c \'tmp="$(mktemp -t yazi-cwd.XXXXXX)"; yazi --cwd-file="$tmp"; if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ]; then cd -- "$cwd"; fi; rm -f -- "$tmp"; exec zsh\''
	)
)
hl.bind(mod .. " + G", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a -l"))
hl.bind(mod .. "+ V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mod .. "+ SHIFT + V", hl.dsp.exec_cmd("pidof clipse && pkill clipse || kitty --class clipse -e clipse"))
hl.bind(mod .. "+ SHIFT + F11", hl.dsp.exec_cmd("killall hyprsunset || hyprsunset &"))
hl.bind(mod .. "+ SHIFT + X", hl.dsp.exec_cmd("wl-freeze -a"))
hl.bind(mod .. " + A", hl.dsp.exec_cmd("qs ipc call ocr snip"))
hl.bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator"))

local autoscroll_shortcut = "SUPER + H"

hl.bind(autoscroll_shortcut, function()
	if hl.plugin.hypr_autoscroll then
		hl.plugin.hypr_autoscroll.middle_mode("toggle")
	end
end, {
	description = "Toggle middle-button autoscroll",
})

-- === Audio Controls ===
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("qs ipc call osd volumeUp"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("qs ipc call osd volumeDown"), { locked = true, repeating = true })
hl.bind("xf86audiomute", hl.dsp.exec_cmd("qs ipc call osd mute"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl play-pause"))

-- === Window Management ===
hl.bind(mod .. " + Delete", hl.dsp.window.close())
local mainMod = "SUPER"

local col_wide = true

hl.bind(mainMod .. " + F", function()
	if col_wide then
		hl.dispatch(hl.dsp.layout("colresize 0.6"))
	else
		hl.dispatch(hl.dsp.layout("colresize 1.0"))
	end
	col_wide = not col_wide
end)
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" })) -- 0 = real fullscreen
hl.bind(mod .. " + SHIFT + T", hl.dsp.window.float({ action = "toggle" }))
--hl.bind("ALT + left",               hl.dsp.group.active({ direction = "b" }))
--hl.bind("ALT + right",              hl.dsp.group.active({ direction = "f" }))
hl.bind(mod .. " + U", hl.dsp.focus({ window = "floating" }))

-- =============================================================================
-- Focus Navigation
-- =============================================================================

hl.bind(mod .. " + left", hl.dsp.layout("move -col"))
hl.bind(mod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + right", hl.dsp.layout("move +col"))

hl.bind(mod .. " + ALT + right", hl.dsp.layout("cyclenext"))
hl.bind(mod .. " + ALT + left", hl.dsp.layout("cycleprev"))

hl.bind(mod .. " + SHIFT + mouse_down", hl.dsp.layout("move +col"))
hl.bind(mod .. " + SHIFT + mouse_up", hl.dsp.layout("move -col"))
hl.bind(mod .. " + SHIFT + period", hl.dsp.layout("move +col"))
hl.bind(mod .. " + SHIFT + comma", hl.dsp.layout("move -col"))

-- hl.bind(mod .. " + D",                  hl.dsp.layout("fit_into_view"))

-- =============================================================================
-- Window Movement
-- =============================================================================

hl.bind(mod .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }))
hl.bind(mod .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mod .. " + SHIFT + H", hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
hl.bind(mod .. " + SHIFT + K", hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + SHIFT + L", hl.dsp.window.move({ direction = "right" }))
-- NOTE: SHIFT+down/up each fire twice (movewindow + swapcol), same as original

-- =============================================================================
-- Column Navigation
-- =============================================================================

hl.bind(mod .. " + Home", hl.dsp.focus({ window = "first" }))
hl.bind(mod .. " + End", hl.dsp.focus({ window = "last" }))
-- === Workspace Navigation ===

hl.bind(mod .. " + Page_Down", function()
	local current = hl.get_active_workspace().id
	if current < 9 then
		hl.dispatch(hl.dsp.focus({ workspace = current + 1 }))
	end
end)

hl.bind(mod .. " + Page_Up", function()
	local current = hl.get_active_workspace().id
	if current > 1 then
		hl.dispatch(hl.dsp.focus({ workspace = current - 1 }))
	end
end)

hl.bind(mod .. " + SHIFT + Page_Down", function()
	local current = hl.get_active_workspace().id
	if current < 9 then
		hl.dispatch(hl.dsp.window.move({ workspace = current + 1 }))
	end
end)

hl.bind(mod .. " + SHIFT + Page_Up", function()
	local current = hl.get_active_workspace().id
	if current > 1 then
		hl.dispatch(hl.dsp.window.move({ workspace = current - 1 }))
	end
end)

-- === Move To Workspaces ===
for i = 1, 10 do
	local key = (i == 10) and "0" or tostring(i)
	hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- === Mouse Wheel Navigation ===
hl.bind(mod .. " + mouse_up", function()
	local current = hl.get_active_workspace().id
	if current > 1 then
		hl.dispatch(hl.dsp.focus({ workspace = current - 1 }))
	else
		hl.dispatch(hl.dsp.focus({ workspace = 1 }))
	end
end)
hl.bind(mod .. " + mouse_down", function()
	local current = hl.get_active_workspace().id
	if current < 10 then
		hl.dispatch(hl.dsp.focus({ workspace = current + 1 }))
	else
		hl.dispatch(hl.dsp.focus({ workspace = 10 }))
	end
end)
-- === Column Management ===
-- bind = $mod, bracketleft, layoutmsg, promote

-- === Sizing & Layout ===
hl.bind(mod .. " + R", hl.dsp.layout("promote"))

hl.bind(mod .. " + R", hl.dsp.layout("promote"))

-- =============================================================================
-- Resize
-- =============================================================================

-- Mouse drag
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { description = "Move window" })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { description = "Resize window" })

-- Keyboard pixel resize (code:20 = [-_], code:21 = [=+])
hl.bind(mod .. " + SHIFT + code:20", hl.dsp.layout("colresize -0.1"))
hl.bind(mod .. " + SHIFT + code:21", hl.dsp.layout("colresize +0.1"))
hl.bind(mod .. " + ALT + code:20", hl.dsp.window.resize({ x = 0, y = -50, relative = true }), { repeating = true })
hl.bind(mod .. " + ALT + code:21", hl.dsp.window.resize({ x = 0, y = 50, relative = true }), { repeating = true })
-- =============================================================================
-- Screenshots
-- =============================================================================

-- Handled by the Quickshell shell (qs ipc call capture ...): window and workspace aware.
-- Print / the macro key opens the picker (photo or video; region, window, workspace or screen)
local function capture(fn)
	return hl.dsp.exec_cmd("qs ipc call capture " .. fn)
end
for _, key in ipairs({ "Print", "XF86Launch1" }) do
	hl.bind(key, capture("open"))
	hl.bind("CTRL + " .. key, capture("region"))
	hl.bind("ALT + " .. key, capture("window")) -- the focused window, straight away
end
hl.bind("SHIFT + Print", capture("screen")) -- the whole screen, straight away
hl.bind("CTRL + SHIFT + Print", capture("workspace")) -- every window of this workspace, scrolled-off ones included
-- Screen recording: SUPER+Print starts the picker in video mode, and stops a running recording
hl.bind(mod .. " + Print", capture("record"))
hl.bind(mod .. " + SHIFT + Print", capture("pause"))
hl.bind(mod .. " + CTRL + Print", capture("recordScreen"))

-- === System Controls ===

hl.bind(mod .. " + S", hl.dsp.workspace.toggle_special("music"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:music", follow = false }))

hl.bind(mod .. " + D", hl.dsp.workspace.toggle_special("texthooker"))
hl.bind(mod .. " + SHIFT + D", hl.dsp.window.move({ workspace = "special:texthooker", follow = false }))

hl.bind(mod .. " + N", hl.dsp.workspace.toggle_special("note"))
hl.bind(mod .. " + SHIFT + N", hl.dsp.window.move({ workspace = "special:note", follow = false }))

-- DPMS toggle: wrapped in a timer per wiki recommendation to avoid undefined behavior
hl.bind(mod .. " + SHIFT + P", function()
	hl.timer(function()
		hl.dispatch(hl.dsp.dpms({ action = "toggle", monitor = "HDMI-A-1" }))
	end, { timeout = 500, type = "oneshot" })
end)

-- GAMMA CONTROL

local current = 100

local function gamma(change)
	return function()
		current = current + change
		current = math.max(0, math.min(100, current))
		hl.dispatch(hl.dsp.exec_cmd("hyprctl hyprsunset gamma " .. current))
		hl.dispatch(
			hl.dsp.exec_cmd(
				string.format('notify-send -t 1000 -h int:value:%d "Gamma" "Current Gamma: %d%%"', current, current)
			)
		)
	end
end

hl.bind(mod .. " + F11", gamma(5))
hl.bind(mod .. " + F10", gamma(-5))

-- hl.bind(mod .. " + X", function()
--     local ws = hl.get_active_workspace()
--     if ws == nil then return end
--
--     local current = ws.tiled_layout
--     local next_layout = current == "dwindle" and "scrolling" or "dwindle"
--
--     hl.workspace_rule({
--         workspace = tostring(ws.id),
--         layout = next_layout
--     })
--     os.execute("notify-send 'Layout:' '" .. next_layout .. "' &")
-- end)
--
-- hyprland.lua
-- hl.bind("SUPER + D", function()
--     hl.plugin.scrolloverview.overview("toggle")
-- end)
