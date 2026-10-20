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
