-- SPDX-License-Identifier: GPL-2.0-or-later
local mp = require("mp")
local utils = require("mp.utils")
local root = assert(os.getenv("MPV_TEST_ROOT"), "Missing test directory")
mp.register_event("file-loaded", function()
    mp.add_timeout(0.2, function()
        local failures = {}
        local function check(value, message)
            if not value then
                failures[#failures + 1] = message
            end
        end
        local list = mp.get_property_native("playlist") or {}
        check(#list == 2, "Playlist must contain exactly the two sibling audio files")
        for _, entry in ipairs(list) do
            local directory, name = utils.split_path(entry.filename)
            check(directory:gsub("[/\\]+$", "") == root, "Playlist escaped the opened directory")
            check(name:match("%.wav$") ~= nil, "Playlist contains a non-audio entry")
        end
        local cover = false
        for _, track in ipairs(mp.get_property_native("track-list") or {}) do
            cover = cover or track.albumart == true
        end
        check(cover, "External cover was not loaded")
        check(not mp.get_property_bool("osc"), "Cover disabled the custom audio controller")
        check(not mp.get_property_bool("fullscreen"), "Cover requested fullscreen")
        local report = assert(io.open(utils.join_path(root, "result.json"), "w"))
        report:write(utils.format_json({ failures = failures }))
        report:close()
        mp.commandv("quit", #failures == 0 and 0 or 1)
    end)
end)
mp.add_timeout(8, function()
    mp.commandv("quit", 2)
end)
