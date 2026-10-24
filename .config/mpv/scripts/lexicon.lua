-- Keys for the interactive subtitles drawn by the shell (SubOverlay / SubTranscript). The shell does the
-- work; these only ask it over IPC, like jimaku.lua does.
local function shell(...)
  mp.command_native_async({
    name = "subprocess",
    args = { "qs", "ipc", "call", "subs", ... },
    playback_only = false,
  }, function() end)
end

-- transcript panel: pin it open or shut (resting on the right screen edge opens it on its own)
mp.add_key_binding(nil, "panel", function() shell("panel") end)
-- mining, on the word the card is open for (or the one under the pointer): the shell adds the note, then
-- mpvacious adds the audio and picture
mp.add_key_binding(nil, "mine", function() shell("mine") end)
mp.add_key_binding(nil, "known", function() shell("known") end)
mp.add_key_binding(nil, "ignore", function() shell("ignore") end)
mp.add_key_binding(nil, "name", function() shell("name") end)
-- furigana: unknown words / all / off
mp.add_key_binding(nil, "furigana", function() shell("furigana") end)
-- interactive subtitles on/off
mp.add_key_binding(nil, "toggle", function() shell("toggle") end)

-- review pause (Alt+r): pause at the end of a line that holds a word due today or a leech
mp.add_key_binding(nil, "reviewpause", function() shell("reviewpause") end)

-- the shell tells us when the line on screen ends (playback time); we pause just before, so it lands on the
-- frame whatever the shell is doing. 0 cancels. The same time is never fired twice (a resume would pause again).
local target, fired = nil, nil
local on_time
on_time = function(_, pos)
  if target and pos and pos >= target - 0.08 then
    fired = target
    target = nil
    mp.unobserve_property(on_time)
    -- the shell reads this so ModernX does not pop its controls for a pause that is ours
    mp.set_property_native("user-data/lexicon-hold", true)
    mp.set_property_native("pause", true)
    mp.add_timeout(0.4, function() mp.set_property_native("user-data/lexicon-hold", false) end)
  end
end
mp.register_script_message("lexicon-pause-at", function(t)
  local n = tonumber(t)
  if not n or n <= 0 then
    mp.unobserve_property(on_time)
    target = nil
    return
  end
  if fired and math.abs(fired - n) < 0.01 then return end
  if mp.get_property_native("pause") then return end
  mp.unobserve_property(on_time)
  target = n
  mp.observe_property("time-pos", "number", on_time)
end)
-- a seek starts over: the line we left is not waiting for us, and rewinding into a fired one may fire again
mp.register_event("seek", function() mp.unobserve_property(on_time); target = nil; fired = nil end)
