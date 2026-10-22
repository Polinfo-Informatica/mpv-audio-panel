-- SPDX-License-Identifier: GPL-2.0-or-later
local mp = require("mp")
local utils = require("mp.utils")
local root = assert(os.getenv("MPV_TEST_ROOT"), "Missing test directory")
local mode = os.getenv("MPV_TEST_MODE") or "Both"
local audio_enabled, video_enabled = mode ~= "Video", mode ~= "Audio"
local defaults = {
    fullscreen = mp.get_property_bool("fullscreen"),
    exclusive = mp.get_property_bool("audio-exclusive"),
    resume = mp.get_property_bool("resume-playback"),
    save = mp.get_property_bool("save-position-on-quit"),
}
local cases = {
    { "audio.wav", true },
    { "unknown.mp4", true },
    { "video.y4m", false },
    { "unknown.data", false },
    { "audio.wav", true },
}
if os.getenv("MPV_TEST_HDR") == "1" then
    cases[#cases + 1] = { "pq.mkv", false, "pq" }
    cases[#cases + 1] = { "hlg.mkv", false, "hlg" }
    cases[#cases + 1] = { "audio.wav", true }
end
local index, failures = 0, {}
local function check(condition, message)
    if not condition then
        failures[#failures + 1] = message
        mp.msg.error(message)
    end
end
mp.observe_property("fullscreen", "bool", function(_, value)
    if index == 2 then
        check(not value, "Audio transition requested fullscreen")
    end
end)
local function next_case()
    index = index + 1
    if index > #cases then
        local file = assert(io.open(utils.join_path(root, "result.json"), "w"))
        file:write(utils.format_json({ cases = #cases, failures = failures }))
        file:close()
        mp.commandv("quit", #failures == 0 and 0 or 1)
        return
    end
    mp.commandv("loadfile", utils.join_path(root, cases[index][1]))
end
mp.register_event("file-loaded", function()
    mp.add_timeout(0.35, function()
        local case = cases[index]
        local audio = case[2]
        local prefix = case[1] .. ": "
        local panel = audio and audio_enabled
        local video_mode = not audio and video_enabled
        local expected_fullscreen = video_mode or defaults.fullscreen
        check(mp.get_property_bool("fullscreen") == expected_fullscreen, prefix .. "fullscreen")
        check(mp.get_property_bool("osc") == not panel, prefix .. "controller")
        local expected_exclusive = not panel and defaults.exclusive
        check(
            mp.get_property_bool("audio-exclusive") == expected_exclusive,
            prefix .. "exclusive audio"
        )
        local expected_resume = not panel and defaults.resume
        local expected_save = video_mode or (not panel and defaults.save)
        check(mp.get_property_bool("resume-playback") == expected_resume, prefix .. "resume policy")
        check(
            mp.get_property_bool("save-position-on-quit") == expected_save,
            prefix .. "save policy"
        )
        if panel then
            check(mp.get_property("target-colorspace-hint") == "no", prefix .. "color-space hint")
            check(mp.get_property("title-bar") == "no", prefix .. "title bar")
        end
        if case[3] then
            check(mp.get_property("video-params/gamma") == case[3], prefix .. "transfer function")
            check(mp.get_property("hdr-compute-peak") == "auto", prefix .. "automatic peak policy")
            check(
                not mp.get_property_bool("user-data/video-safety/hdr_output"),
                prefix .. "null output claimed HDR"
            )
        end
        next_case()
    end)
end)
mp.add_timeout(25, function()
    mp.msg.error("Runtime test timed out")
    mp.commandv("quit", 2)
end)
mp.add_timeout(0.1, next_case)
