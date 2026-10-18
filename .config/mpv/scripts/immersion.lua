-- immersion.lua
-- Logs real playback time for the Quickshell immersion tracker. It only records raw facts
-- (what played, for how long, which audio / sub language); the shell decides what counts.
--
--   <state>/quickshell/immersion/mpv.jsonl   one JSON line per playback segment
--   <state>/quickshell/immersion/live.json   what this player is doing right now
--
-- <state> is $XDG_STATE_HOME, or ~/.local/state.

local utils = require("mp.utils")

local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home == "" then
  state_home = (os.getenv("HOME") or "") .. "/.local/state"
end
local dir = state_home .. "/quickshell/immersion"
local log_path = dir .. "/mpv.jsonl"
local live_path = dir .. "/live.json"
local pid = utils.getpid()

mp.command_native({ name = "subprocess", args = { "mkdir", "-p", dir }, playback_only = false })

local FLUSH_EVERY = 300 -- a long segment is cut so a crash loses little and midnight stays close
local MIN_SECS = 2

local cur = {}            -- facts about the file being played, refreshed while it plays
local seg_start_clock     -- mp.get_time() when the open segment began
local seg_start_epoch     -- os.time() when it began
local session_secs = 0    -- seconds counted since this file loaded

local function track_lang(kind)
  local t = mp.get_property_native("current-tracks/" .. kind)
  if type(t) ~= "table" then
    return ""
  end
  return t.lang or ""
end

local function track_name(kind)
  local t = mp.get_property_native("current-tracks/" .. kind)
  if type(t) ~= "table" then
    return ""
  end
  return t.title or ""
end

-- read the player's current file into `cur`; keeps the old values when nothing is loaded
local function refresh()
  local path = mp.get_property("path")
  if not path or path == "" then
    return
  end
  cur.path = path
  cur.title = mp.get_property("media-title") or ""
  cur.dur = mp.get_property_number("duration", 0) or 0
  cur.pos = mp.get_property_number("time-pos", cur.pos or 0) or 0
  -- tracks vanish while a file unloads, so an empty value never replaces a known one
  local a = track_lang("audio")
  if a ~= "" or not cur.alang then
    cur.alang = a
    cur.aname = track_name("audio")
  end
  local s = track_lang("sub")
  if s ~= "" or not cur.slang then
    cur.slang = s
  end
end

local function write_live(playing)
  local f = io.open(live_path, "w")
  if not f then
    return
  end
  local running = seg_start_clock and (mp.get_time() - seg_start_clock) or 0
  f:write(utils.format_json({
    pid = pid,
    playing = playing and true or false,
    path = cur.path or "",
    title = cur.title or "",
    alang = cur.alang or "",
    slang = cur.slang or "",
    dur = cur.dur or 0,
    pos = cur.pos or 0,
    segStart = seg_start_epoch or 0,
    sessionSecs = math.floor(session_secs + running),
    updated = os.time(),
  }))
  f:close()
end

-- close the open segment and append it to the log
local function flush()
  if not seg_start_clock then
    return
  end
  local secs = mp.get_time() - seg_start_clock
  local start = seg_start_epoch
  seg_start_clock = nil
  seg_start_epoch = nil
  session_secs = session_secs + secs
  if secs < MIN_SECS or not cur.path then
    return
  end
  local f = io.open(log_path, "a")
  if not f then
    return
  end
  f:write(utils.format_json({
    id = start .. "-" .. pid,
    start = start,
    ["end"] = os.time(),
    secs = math.floor(secs + 0.5),
    path = cur.path,
    title = cur.title or "",
    dur = cur.dur or 0,
    pos = cur.pos or 0,
    alang = cur.alang or "",
    aname = cur.aname or "",
    slang = cur.slang or "",
  }), "\n")
  f:close()
end

local function begin()
  if seg_start_clock then
    return
  end
  refresh()
  if not cur.path then
    return
  end
  seg_start_clock = mp.get_time()
  seg_start_epoch = os.time()
  write_live(true)
end

local function is_playing()
  return mp.get_property_bool("core-idle") == false
    and mp.get_property_bool("eof-reached") ~= true
    and (mp.get_property("path") or "") ~= ""
end

local function sync()
  if is_playing() then
    begin()
  else
    if seg_start_clock then
      refresh()
      flush()
    end
    write_live(false)
  end
end

mp.observe_property("core-idle", "bool", sync)
mp.observe_property("eof-reached", "bool", sync)

-- a new file starts a fresh session
mp.register_event("start-file", function()
  flush()
  session_secs = 0
  cur = {}
end)
mp.register_event("end-file", function()
  flush()
  write_live(false)
end)
mp.register_event("file-loaded", function()
  refresh()
  sync()
end)

-- track switches (audio language changed by hand) change what a later segment is worth
-- (the first value after a file loads only fills in the language, it doesn't split the segment)
mp.observe_property("current-tracks/audio", "native", function()
  local before = cur.alang or ""
  if seg_start_clock and before ~= "" and track_lang("audio") ~= before then
    flush()
    begin()
  else
    refresh()
  end
end)
mp.observe_property("current-tracks/sub", "native", function()
  refresh()
end)

-- The IPC socket path is shared by every mpv: a second player takes it over, and when that one leaves
-- the first is left listening on a socket nobody can reach. The shell then leaves heal-<pid> here (see
-- Services/Mpv.qml), and this binds the socket again (mpv replaces the stale file when it binds).
local heal_path = dir .. "/heal-" .. pid
local function heal_ipc()
  if not utils.file_info(heal_path) then
    return
  end
  os.remove(heal_path)
  local sock = mp.get_property("input-ipc-server")
  if sock and sock ~= "" then
    mp.set_property("input-ipc-server", "")
    mp.set_property("input-ipc-server", sock)
  end
end

mp.add_periodic_timer(5, function()
  heal_ipc()
  if seg_start_clock then
    refresh()
    if mp.get_time() - seg_start_clock >= FLUSH_EVERY then
      flush()
      begin()
    end
    write_live(true)
  end
end)

mp.register_event("shutdown", function()
  refresh()
  flush()
  write_live(false)
end)
