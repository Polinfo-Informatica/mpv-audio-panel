-- SPDX-License-Identifier: GPL-2.0-or-later
-- Classify the decoded signal and negotiated output; never infer GPU support from its brand.
local mp = require("mp")

local reporting_contexts = { d3d11 = true, winvk = true, wayland = true, waylandvk = true }
local hdr_transfers = { pq = true, hlg = true, scrgb = true }
local sdr_transfers = {
    srgb = true,
    ["bt.1886"] = true,
    ["gamma1.8"] = true,
    ["gamma2.0"] = true,
    ["gamma2.2"] = true,
    ["gamma2.4"] = true,
    ["gamma2.6"] = true,
    ["gamma2.8"] = true,
}

local function finite(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum and value <= maximum
end

local function classify(get, low_power, seen_hdr10plus)
    local track = get("current-tracks/video") or {}
    local decoded = get("video-params") or {}
    local source = get("video-out-params") or {}
    local target = get("video-target-params") or {}
    local video = track.type == "video"
        and not track.image
        and not track.albumart
        and finite(decoded.w, 1, 100000)
        and finite(decoded.h, 1, 100000)
    local vo = get("current-vo")
    local renderer = video and get("vo-configured") == true and (vo == "gpu-next" or vo == "gpu")
    local next_renderer = renderer and vo == "gpu-next"
    local dolby = source.colormatrix == "dolbyvision"
    local hdr = source.gamma == "pq" or source.gamma == "hlg" or dolby
    local target_known = type(target.gamma) == "string"
        and target.gamma ~= ""
        and target.gamma ~= "auto"
    local native = next_renderer
        and reporting_contexts[get("current-gpu-context")] == true
        and get("target-colorspace-hint") == "auto"
        and get("target-colorspace-hint-mode") == "target"
        and get("target-colorspace-hint-strict") == true
        and hdr_transfers[target.gamma] == true
    local r, g, b = source["scene-max-r"], source["scene-max-g"], source["scene-max-b"]
    local metadata = finite(r, 0, 10000)
        and finite(g, 0, 10000)
        and finite(b, 0, 10000)
        and (r > 0 or g > 0 or b > 0)
    local hdr10plus = next_renderer
        and source.gamma == "pq"
        and not dolby
        and target_known
        and (metadata or seen_hdr10plus == true)
    return {
        video = not not video,
        renderer = not not renderer,
        hdr_source = not not (video and hdr),
        hdr_output = not not (hdr and native),
        hdr_tonemap = not not (renderer and hdr and not native),
        sdr = not not (renderer and target_known and not hdr and sdr_transfers[source.gamma]),
        generic_hdr = not not (renderer and hdr and not dolby and not hdr10plus and not low_power),
        hdr10plus = not not (hdr10plus and not low_power),
        dolby_vision = not not (next_renderer and dolby and target_known and not low_power),
        low_power = not not (video and low_power),
        metadata_seen = not not (hdr10plus or seen_hdr10plus),
    }
end

-- Degrade optional processing only after sustained drops, never during startup or seeking.
local function advance(previous, sample)
    local state = previous or { grace = sample.time + 5, streak = 0, low_power = false }
    local dt = state.time and sample.time - state.time or 0
    local jumped = state.position
        and sample.position
        and math.abs(sample.position - state.position - dt * sample.speed) > 2
    local delta = math.max(
        sample.render_drops - (state.render_drops or sample.render_drops),
        sample.decode_drops - (state.decode_drops or sample.decode_drops)
    )
    local reset = not sample.eligible or jumped or dt < 0.5 or dt > 2.5 or delta < 0
    if reset then
        state.grace = sample.time + 3
        state.streak = 0
    elseif sample.time >= state.grace then
        local threshold = math.max(3, math.ceil((sample.fps or 30) * dt * 0.10))
        state.streak = delta >= threshold and state.streak + 1 or 0
        if state.streak >= 3 then
            state.low_power = true
        end
    end
    state.time, state.position = sample.time, sample.position
    state.render_drops, state.decode_drops = sample.render_drops, sample.decode_drops
    return state
end

local ready, seen_hdr10plus, monitor = false, false, nil
local published, pending = {}, nil
local function get(name)
    return mp.get_property_native(name)
end
local function update()
    pending = nil
    local state = ready and classify(get, monitor and monitor.low_power, seen_hdr10plus) or {}
    seen_hdr10plus = state.metadata_seen == true
    local changed = false
    for _, key in ipairs({
        "video",
        "renderer",
        "hdr_source",
        "hdr_output",
        "hdr_tonemap",
        "sdr",
        "generic_hdr",
        "hdr10plus",
        "dolby_vision",
        "low_power",
    }) do
        local value = state[key] == true
        if published[key] ~= value then
            changed = true
        end
        state[key] = value
    end
    state.metadata_seen = nil
    if changed then
        published = state
        mp.set_property_native("user-data/video-safety", state)
    end
end
local function schedule()
    if not pending then
        pending = mp.add_timeout(0.05, update)
    end
end
local function reset()
    ready, seen_hdr10plus, monitor = false, false, nil
    update()
end
mp.register_event("start-file", reset)
mp.register_event("end-file", reset)
mp.register_event("file-loaded", function()
    ready = true
    schedule()
end)
mp.observe_property("vid", "native", function()
    seen_hdr10plus, monitor = false, nil
    schedule()
end)
for _, name in ipairs({
    "video-params",
    "video-out-params",
    "video-target-params",
    "vo-configured",
    "current-vo",
    "current-gpu-context",
    "target-colorspace-hint",
    "target-colorspace-hint-mode",
    "target-colorspace-hint-strict",
    "display-names",
}) do
    mp.observe_property(name, "native", schedule)
end
mp.add_periodic_timer(1, function()
    if not ready then
        return
    end
    local fps = mp.get_property_number("container-fps", 30)
    if not finite(fps, 1, 240) then
        fps = 30
    end
    local speed = mp.get_property_number("speed", 1)
    local eligible = published.video
        and published.renderer
        and not get("pause")
        and not get("seeking")
        and not get("paused-for-cache")
        and speed >= 0.95
        and speed <= 1.05
    local was_low_power = monitor and monitor.low_power
    monitor = advance(monitor, {
        time = mp.get_time(),
        position = mp.get_property_number("time-pos"),
        speed = speed,
        render_drops = mp.get_property_number("frame-drop-count", 0),
        decode_drops = mp.get_property_number("decoder-frame-drop-count", 0),
        fps = fps,
        eligible = eligible,
    })
    if monitor.low_power and not was_low_power then
        mp.msg.warn("Sustained frame drops: reducing optional video processing for this track.")
        schedule()
    end
end)
update()

-- Pure decisions are also exercised by the regression suite with synthetic capability reports.
return { classify = classify, advance = advance }
