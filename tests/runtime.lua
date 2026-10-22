-- SPDX-License-Identifier: GPL-2.0-or-later
local mp = require("mp")
local utils = require("mp.utils")
local root = assert(os.getenv("MPV_TEST_ROOT"), "Missing test directory")
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
        check(mp.get_property_bool("fullscreen") == not audio, prefix .. "fullscreen")
        check(mp.get_property_bool("osc") == not audio, prefix .. "controller")
        check(mp.get_property_bool("resume-playback") == not audio, prefix .. "resume policy")
        check(mp.get_property_bool("save-position-on-quit") == not audio, prefix .. "save policy")
        if audio then
            check(mp.get_property("target-colorspace-hint") == "no", prefix .. "color-space hint")
            check(mp.get_property("title-bar") == "no", prefix .. "title bar")
        end
        if case[3] then
            check(mp.get_property("video-params/gamma") == case[3], prefix .. "transfer function")
            check(mp.get_property("hdr-compute-peak") == "yes", prefix .. "HDR peak profile")
        end
        next_case()
    end)
end)
mp.add_timeout(25, function()
    mp.msg.error("Runtime test timed out")
    mp.commandv("quit", 2)
end)
mp.add_timeout(0.1, next_case)
