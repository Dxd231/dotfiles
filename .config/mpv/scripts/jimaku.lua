-- jimaku.lua
-- Fetches the Japanese subtitle of a local video from jimaku.cc and saves it next to the file as
-- <video name>.ja.srt (the work is done by ~/.config/quickshell/scripts/jimaku.py, which the shell's
-- Jimaku panel also uses). It runs when a file loads if the video has no Japanese subtitle yet.
--
--   Alt+j (input.conf: script-binding jimaku/panel)   open the shell's Jimaku panel
--   script-message jimaku-fetch                        fetch again, even if a subtitle exists
--   script-message jimaku-reload <file>                load <file> in place of the subtitle this script added
--
-- Options (script-opts/jimaku.conf): auto=yes

local utils = require("mp.utils")

local cfg = { auto = true }
require("mp.options").read_options(cfg, "jimaku")

local home = os.getenv("HOME") or ""
local script = home .. "/.config/quickshell/scripts/jimaku.py"

local busy = {}     -- path -> true while a fetch for it runs
local added_id      -- id of the subtitle track this script added
local told_nokey = false

local function has_japanese_sub()
  for _, t in ipairs(mp.get_property_native("track-list") or {}) do
    if t.type == "sub" and (t.lang == "ja" or t.lang == "jpn" or t.lang == "jp") then
      return true
    end
  end
  return false
end

local function load_sub(file)
  if added_id then
    mp.commandv("sub-remove", tostring(added_id))
    added_id = nil
  end
  mp.commandv("sub-add", file, "select", "jimaku", "ja")
  added_id = mp.get_property_number("sid")
end

local function fetch(force)
  local path = mp.get_property("path") or ""
  if path:sub(1, 1) ~= "/" or busy[path] then
    return
  end
  busy[path] = true
  if force then
    mp.osd_message("Jimaku: searching…", 3)
  end
  mp.command_native_async({
    name = "subprocess",
    args = { "python3", "-I", script, "fetch" },
    stdin_data = utils.format_json({ path = path, force = force and true or false }),
    capture_stdout = true,
    playback_only = false,
  }, function(_, res)
    busy[path] = nil
    if (mp.get_property("path") or "") ~= path then
      return
    end
    local out = res and res.stdout and utils.parse_json(res.stdout) or nil
    if not out then
      if force then
        mp.osd_message("Jimaku: the fetch script failed", 4)
      end
      return
    end
    if out.ok and out.saved then
      if not out.kept or force then
        load_sub(out.saved)
        mp.osd_message("Jimaku: " .. out.saved:match("[^/]*$"), 4)
      end
    elseif out.state == "nokey" then
      if force or not told_nokey then
        told_nokey = true
        mp.osd_message("Jimaku: add your API key (Alt+j)", 5)
      end
    elseif out.state == "none" then
      mp.osd_message("Jimaku: no subtitles found", 4)
    elseif force or out.error then
      mp.osd_message("Jimaku: " .. (out.error or "failed"), 4)
    end
  end)
end

mp.register_event("start-file", function()
  added_id = nil
end)

mp.register_event("file-loaded", function()
  if not cfg.auto or has_japanese_sub() then
    return
  end
  -- sub-auto picks a neighbouring <name>.ja.srt up on its own, so give it a moment before asking
  mp.add_timeout(1.5, function()
    if not has_japanese_sub() then
      fetch(false)
    end
  end)
end)

mp.register_script_message("jimaku-fetch", function()
  fetch(true)
end)

mp.register_script_message("jimaku-reload", function(file)
  if file and file ~= "" then
    load_sub(file)
    mp.osd_message("Jimaku: " .. file:match("[^/]*$"), 3)
  end
end)

mp.add_key_binding(nil, "panel", function()
  mp.command_native_async({
    name = "subprocess",
    args = { "qs", "ipc", "call", "jimakuPanel", "toggle" },
    playback_only = false,
  }, function() end)
end)
