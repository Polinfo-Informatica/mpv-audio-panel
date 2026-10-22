-- SPDX-License-Identifier: GPL-2.0-or-later
local utils = require("mp.utils")
local mock = {
    get_property_native = function() end,
    set_property_native = function() end,
    register_event = function() end,
    observe_property = function() end,
    add_periodic_timer = function() end,
}
local original = package.loaded.mp
package.loaded.mp = mock
local ok, policy =
    pcall(dofile, utils.join_path(os.getenv("MPV_TEST_CONFIG"), "scripts/video-safety.lua"))
package.loaded.mp = original
assert(ok, policy)

local function snapshot(changes)
    local state = {
        ["current-tracks/video"] = { type = "video" },
        ["video-params"] = { w = 3840, h = 2160 },
        ["video-out-params"] = { gamma = "pq", colormatrix = "bt.2020-ncl" },
        ["video-target-params"] = { gamma = "pq" },
        ["vo-configured"] = true,
        ["current-vo"] = "gpu-next",
        ["current-gpu-context"] = "d3d11",
        ["target-colorspace-hint"] = "auto",
        ["target-colorspace-hint-mode"] = "target",
        ["target-colorspace-hint-strict"] = true,
    }
    for key, value in pairs(changes or {}) do
        state[key] = value
    end
    return function(name)
        return state[name]
    end
end
local cases = {
    { "unknown source transfer", { ["video-out-params"] = { gamma = "auto" } }, "sdr", false },
    { "reported PQ output", {}, "hdr_output", true },
    { "reported HLG output", { ["video-target-params"] = { gamma = "hlg" } }, "hdr_output", true },
    {
        "reported scRGB output",
        { ["video-target-params"] = { gamma = "scrgb" } },
        "hdr_output",
        true,
    },
    { "SDR output", { ["video-target-params"] = { gamma = "srgb" } }, "hdr_output", false },
    { "SDR conversion", { ["video-target-params"] = { gamma = "srgb" } }, "hdr_tonemap", true },
    { "missing target", { ["video-target-params"] = {} }, "hdr_output", false },
    { "unknown context", { ["current-gpu-context"] = "unknown" }, "hdr_output", false },
    { "Wayland reporting", { ["current-gpu-context"] = "waylandvk" }, "hdr_output", true },
    { "legacy renderer", { ["current-vo"] = "gpu" }, "hdr_output", false },
    { "legacy renderer conversion", { ["current-vo"] = "gpu" }, "hdr_tonemap", true },
    { "unsupported renderer", { ["current-vo"] = "null" }, "generic_hdr", false },
    { "unconfigured output", { ["vo-configured"] = false }, "hdr_output", false },
    { "forced source hint", { ["target-colorspace-hint-mode"] = "source" }, "hdr_output", false },
    { "forced hint", { ["target-colorspace-hint"] = "yes" }, "hdr_output", false },
    { "non-strict output", { ["target-colorspace-hint-strict"] = false }, "hdr_output", false },
    {
        "album art",
        { ["current-tracks/video"] = { type = "video", albumart = true } },
        "video",
        false,
    },
    {
        "still image",
        { ["current-tracks/video"] = { type = "video", image = true } },
        "video",
        false,
    },
    { "failed decode", { ["video-params"] = {} }, "video", false },
    {
        "container DV tag alone",
        { ["current-tracks/video"] = { type = "video", ["dolby-vision-profile"] = 5 } },
        "dolby_vision",
        false,
    },
    {
        "decoded Dolby Vision",
        { ["video-out-params"] = { colormatrix = "dolbyvision", gamma = "pq" } },
        "dolby_vision",
        true,
    },
    { "missing dynamic metadata", {}, "hdr10plus", false },
    {
        "partial dynamic metadata",
        { ["video-out-params"] = { gamma = "pq", ["scene-max-r"] = 1000 } },
        "hdr10plus",
        false,
    },
    {
        "invalid dynamic metadata",
        {
            ["video-out-params"] = {
                gamma = "pq",
                ["scene-max-r"] = 10001,
                ["scene-max-g"] = 1000,
                ["scene-max-b"] = 1000,
            },
        },
        "hdr10plus",
        false,
    },
}
for _, case in ipairs(cases) do
    assert(policy.classify(snapshot(case[2]))[case[3]] == case[4], case[1])
end
local metadata =
    { gamma = "pq", ["scene-max-r"] = 1000, ["scene-max-g"] = 900, ["scene-max-b"] = 800 }
for _, gamma in ipairs({ "pq", "srgb" }) do
    local state = policy.classify(
        snapshot({ ["video-out-params"] = metadata, ["video-target-params"] = { gamma = gamma } })
    )
    assert(state.hdr10plus, "Metadata conversion must support a negotiated " .. gamma .. " target")
end
assert(
    not policy.classify(snapshot({ ["current-vo"] = "gpu", ["video-out-params"] = metadata })).hdr10plus,
    "Legacy renderer must not select HDR10+ processing"
)
assert(
    not policy.classify(snapshot({ ["video-out-params"] = metadata }), true).hdr10plus,
    "Low power disables specialized processing"
)
assert(
    not policy.classify(snapshot(), true).generic_hdr,
    "Low power disables optional peak computation"
)
assert(
    policy.classify(snapshot(), false, true).hdr10plus,
    "Black scenes retain established metadata support"
)

local function sample(time, drops, eligible, position)
    return {
        time = time,
        render_drops = drops,
        decode_drops = 0,
        fps = 30,
        eligible = eligible,
        position = position or time,
        speed = 1,
    }
end
local state
for time = 0, 5 do
    state = policy.advance(state, sample(time, 0, true))
end
state = policy.advance(state, sample(6, 5, true))
assert(not state.low_power, "One drop burst must not degrade quality")
state = policy.advance(state, sample(7, 10, true))
state = policy.advance(state, sample(8, 15, true))
assert(state.low_power, "Sustained drops must reduce optional work")
local paused
for time = 0, 12 do
    paused = policy.advance(paused, sample(time, time * 10, false))
end
assert(not paused.low_power, "Paused/cache/seek samples must be ignored")
local seeking
for time = 0, 12 do
    seeking = policy.advance(seeking, sample(time, time * 10, true, time * 100))
end
assert(not seeking.low_power, "Position jumps must receive a new grace period")
print(
    "Video safety checks passed: output negotiation, metadata, fallback and sustained-drop policy."
)
