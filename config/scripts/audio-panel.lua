-- SPDX-License-Identifier: GPL-2.0-or-later
-- Persistent audio-only interface for mpv. No external dependencies.
-- This script manages AUTO_MUSIC across file-loading boundaries.
local mp = require("mp")
local assdraw = require("mp.assdraw")
local options = require("mp.options")

local opts = { scale = 1.0, font_size = 24, row_height = 34, smoothness = 18 }
local overlay = mp.create_osd_overlay("ass-events")
overlay.z = 100
local active, dirty = false, true
local offset, target_offset, last_pos, dragging = 0, 0, -1, nil
local managed_audio = false
local previous_tick = mp.get_time()
local layout, hits = nil, {}
local render, activate
local bindings = { "click", "double", "move", "leave", "wheel-up", "wheel-down" }
local colors = {
    bg = "181818",
    panel = "101010",
    row = "242424",
    selected = "333333",
    text = "FFFFFF",
    muted = "AAAAAA",
    accent = "EEEEEE",
    track = "555555",
}
local icons = {
    prev = string.char(238, 128, 132),
    next = string.char(238, 128, 133),
    play = string.char(238, 132, 129),
    pause = string.char(238, 128, 130),
}

local function clamp(n, lo, hi)
    return math.max(lo, math.min(hi, n))
end
local function number(name, fallback)
    return mp.get_property_number(name, fallback or 0)
end
local function mark()
    dirty = true
end
local function escaped(s)
    local clean = tostring(s or ""):gsub("[\r\n]", " ")
    return mp.command_native({ "escape-ass", clean })
end
local function time_string(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 3600 then
        return string.format(
            "%d:%02d:%02d",
            math.floor(seconds / 3600),
            math.floor(seconds / 60) % 60,
            seconds % 60
        )
    end
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function entry_name(entry)
    if not entry then
        return ""
    end
    if entry.title and entry.title ~= "" then
        return entry.title
    end
    local name = (entry.filename or ""):gsub("\\", "/"):match("([^/]+)$") or ""
    return name:gsub("%.[^%.]+$", "")
end
local function mouse()
    local p = mp.get_property_native("mouse-pos") or {}
    local scale = math.max(0.5, opts.scale)
    return (p.x or -1000) / scale, (p.y or -1000) / scale
end
local function inside(x, y, r)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end
local function rect(a, x, y, w, h, color)
    if w <= 0 or h <= 0 then
        return
    end
    a:new_event()
    a:append(string.format("{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H%s&\\1a&H00&}", color))
    a:draw_start()
    a:rect_cw(x, y, x + w, y + h)
    a:draw_stop()
end
local function polygon(a, points, color)
    a:new_event()
    a:append(string.format("{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H%s&}", color))
    a:draw_start()
    a:move_to(points[1], points[2])
    for i = 3, #points, 2 do
        a:line_to(points[i], points[i + 1])
    end
    a:line_to(points[1], points[2])
    a:draw_stop()
end
local function text(a, x, y, s, size, color, clip, align)
    a:new_event()
    a:append(
        string.format(
            "{\\an%d\\pos(%.2f,%.2f)\\fnSegoe UI\\fs%.2f\\bord0\\shad0\\q2\\1c&H%s&}",
            align or 7,
            x,
            y,
            size,
            color or colors.text
        )
    )
    if clip then
        a:append(string.format("{\\clip(%d,%d,%d,%d)}", clip[1], clip[2], clip[3], clip[4]))
    end
    a:append(escaped(s))
end
local function hit(id, x, y, w, h, value)
    hits[#hits + 1] = { id = id, x = x, y = y, w = w, h = h, value = value }
end
local function icon(a, x, y, glyph, size, color)
    a:new_event()
    a:append(
        string.format(
            "{\\an5\\pos(%.2f,%.2f)\\fnmpv-osd-symbols\\fs%.2f\\bord0\\shad0\\1c&H%s&}",
            x,
            y,
            size,
            color or colors.text
        )
    )
    a:append(glyph)
end
local function speaker_icon(a, x, y, muted)
    -- Both states share the same speaker geometry and fixed center.
    -- Vector paths avoid font-dependent glyphs, spacing and baselines.
    local function shape(points)
        local translated = {}
        for i = 1, #points, 2 do
            translated[i] = x + points[i]
            translated[i + 1] = y + points[i + 1]
        end
        polygon(a, translated, colors.text)
    end
    shape({ -13, -4, -9, -4, -3, -10, -3, 10, -9, 4, -13, 4 })
    if muted then
        shape({ 3, -6, 4.5, -7.5, 14, 6, 12.5, 7.5 })
        shape({ 12.5, -7.5, 14, -6, 4.5, 7.5, 3, 6 })
    else
        -- Two filled arc bands form the sound waves in front of the speaker.
        for _, radius in ipairs({ 10, 16 }) do
            local points = {}
            for i = 0, 12 do
                local angle = -0.62 + 1.24 * i / 12
                points[#points + 1] = -3 + (radius + 1) * math.cos(angle)
                points[#points + 1] = (radius + 1) * math.sin(angle)
            end
            for i = 12, 0, -1 do
                local angle = -0.62 + 1.24 * i / 12
                points[#points + 1] = -3 + (radius - 1) * math.cos(angle)
                points[#points + 1] = (radius - 1) * math.sin(angle)
            end
            shape(points)
        end
    end
end
local function circle(a, x, y, r, color)
    local points = {}
    for i = 0, 20 do
        local angle = i * math.pi * 2 / 20
        points[#points + 1] = x + math.cos(angle) * r
        points[#points + 1] = y + math.sin(angle) * r
    end
    polygon(a, points, color)
end
local function mpv_logo(a, x, y, size)
    -- Monochrome adaptation of mpv-player/mpv/etc/mpv.svg.
    -- Preserve the original circles and triangle in one fixed square.
    local scale = size / 55.898388
    local function dot(cx, cy, r, color)
        local points = {}
        for i = 0, 48 do
            local angle = i * math.pi * 2 / 48
            points[#points + 1] = x + (cx - 32 + r * math.cos(angle)) * scale
            points[#points + 1] = y + (cy - 32 + r * math.sin(angle)) * scale
        end
        polygon(a, points, color)
    end
    dot(32, 32, 27.949194, colors.text)
    dot(32.727058, 31.1457, 25.950588, "555555")
    dot(34.224396, 29.4335, 20, "303030")
    dot(31.632556, 32.1185, 12.848894, colors.text)
    polygon(a, {
        x + (28.374316 - 32) * scale,
        y + (26.3468 - 32) * scale,
        x + (28.374316 - 32) * scale,
        y + (37.797 - 32) * scale,
        x + (37.590396 - 32) * scale,
        y + (31.9323 - 32) * scale,
    }, "303030")
end
local function scroll(delta)
    if not layout then
        return
    end
    target_offset = clamp(target_offset + delta, 0, layout.max_scroll)
    mark()
end
local function update_drag(x, y)
    if not layout or not dragging then
        return
    end
    if dragging == "seek" and layout.duration > 0 then
        local ratio = clamp((x - layout.seek.x) / layout.seek.w, 0, 1)
        mp.commandv("seek", ratio * layout.duration, "absolute+exact")
    elseif dragging == "volume" then
        mp.set_property_number("volume", clamp((x - layout.volume.x) / layout.volume.w, 0, 1) * 100)
    elseif dragging == "scrollbar" then
        local ratio = clamp((y - layout.list_y) / layout.list_h, 0, 1)
        target_offset = ratio * layout.max_scroll
        offset = target_offset
    end
    mark()
end
local function on_click(event)
    if not active then
        return
    end
    if event.canceled or event.event == "up" then
        dragging = nil
        return
    end
    if event.event ~= "down" and event.event ~= "press" then
        return
    end
    if dirty then
        render()
    end
    local x, y = mouse()
    for i = #hits, 1, -1 do
        local r = hits[i]
        if inside(x, y, r) then
            if r.id == "row" then
                if r.value ~= number("playlist-pos", -1) then
                    mp.commandv("playlist-play-index", r.value)
                end
                mp.set_property_bool("pause", false)
            elseif r.id == "play" then
                mp.commandv("cycle", "pause")
            elseif r.id == "prev" then
                mp.commandv("playlist-prev", "weak")
            elseif r.id == "next" then
                mp.commandv("playlist-next", "weak")
            elseif r.id == "mute" then
                mp.commandv("cycle", "mute")
            elseif r.id == "quit" then
                mp.commandv("quit")
            elseif r.id == "minimize" then
                mp.set_property_bool("window-minimized", true)
            elseif r.id == "drag" then
                mp.commandv("begin-vo-dragging")
            else
                dragging = r.id
                update_drag(x, y)
            end
            if event.event == "press" then
                dragging = nil
            end
            mark()
            return
        end
    end
end

render = function()
    if not active then
        return
    end
    local pixel_w, pixel_h = mp.get_osd_size()
    if not pixel_w or not pixel_h or pixel_w < 1 or pixel_h < 1 then
        return
    end
    local scale = math.max(0.5, opts.scale)
    local w, h = math.floor(pixel_w / scale), math.floor(pixel_h / scale)
    local row = math.max(28, opts.row_height)
    local panel_y = math.max(54, h - 138)
    local list_y = 30
    local list_h = math.max(0, panel_y - list_y - 12)
    local list = mp.get_property_native("playlist") or {}
    local count = #list
    local max_scroll = math.max(0, count * row - list_h)
    local pos = number("playlist-pos", -1)
    if pos >= 0 and pos ~= last_pos then
        local top = pos * row
        if top < target_offset then
            target_offset = top
        elseif top + row > target_offset + list_h then
            target_offset = top + row - list_h
        end
        last_pos = pos
    end
    target_offset = clamp(target_offset, 0, max_scroll)
    offset = clamp(offset, 0, max_scroll)
    local duration = number("duration")
    local current = number("time-pos")
    local volume = number("volume", 100)
    local muted = mp.get_property_native("mute", false)
    local paused = mp.get_property_native("pause", false)
    local mx, my = mouse()
    local a = assdraw.ass_new()
    hits = {}
    rect(a, 0, 0, w, h, colors.bg)
    rect(a, 0, 0, w, list_y - 3, colors.panel)

    -- A quiet drag region replaces the title bar entirely.
    rect(a, w / 2 - 14, 11, 28, 2, "555555")
    hit("drag", 0, 0, math.max(0, w - 82), 26)
    rect(a, w - 67, 12, 12, 1, colors.muted)
    polygon(a, { w - 28, 7, w - 27, 6, w - 15, 18, w - 16, 19 }, colors.muted)
    polygon(a, { w - 16, 6, w - 15, 7, w - 27, 19, w - 28, 18 }, colors.muted)
    hit("minimize", w - 82, 0, 38, 26)
    hit("quit", w - 44, 0, 44, 26)

    -- Match the bottom separator while keeping it above the clipped list.
    rect(a, 16, list_y - 3, w - 32, 1, "383838")

    -- Clip fractional rows so smooth scrolling cannot overlap controls.
    local first = math.floor(offset / row)
    local last = math.min(count - 1, math.ceil((offset + list_h) / row))
    for index = first, last do
        local entry = list[index + 1]
        if entry then
            local y = list_y + index * row - offset
            local top = math.max(list_y, y)
            local bottom = math.min(list_y + list_h, y + row)
            if bottom > top then
                local r = { x = 12, y = top, w = w - 42, h = bottom - top }
                local selected = index == pos
                if selected or inside(mx, my, r) then
                    rect(a, r.x, r.y, r.w, r.h, selected and colors.selected or colors.row)
                end
                local name = entry_name(entry)
                local clip = { 16, math.floor(top), math.floor(w - 30), math.floor(bottom) }
                if selected then
                    icon(a, 28, y + row / 2, icons.play, 13)
                end
                clip[1] = 46
                text(a, 46, y + 4, name, opts.font_size, selected and colors.text or "D0D0D0", clip)
                hit("row", r.x, r.y, r.w, r.h, index)
            end
        end
    end
    if max_scroll > 0 and list_h > 0 then
        local thumb = math.max(22, list_h * list_h / (count * row))
        local thumb_y = list_y + (list_h - thumb) * offset / max_scroll
        rect(a, w - 17, thumb_y, 3, thumb, "888888")
        hit("scrollbar", w - 26, list_y, 24, list_h)
    end

    -- Native mpv symbols and a monochrome, opaque bottom controller.
    rect(a, 0, panel_y, w, h - panel_y, colors.panel)
    rect(a, 16, panel_y + 1, w - 32, 1, "383838")
    -- Reserve a separate line for the current title above the seek bar.
    local title = mp.get_property("metadata/by-key/title", "")
    if title == "" then
        title = entry_name(list[pos + 1])
    end
    if title == "" then
        title = mp.get_property("media-title", "")
    end
    local title_clip = { 22, math.floor(panel_y + 6), math.floor(w - 22), math.floor(panel_y + 36) }
    text(a, 22, panel_y + 9, title, opts.font_size, colors.text, title_clip)
    local seek = { x = 22, y = panel_y + 45, w = math.max(20, w - 44), h = 22 }
    local ratio = clamp(duration > 0 and current / duration or 0, 0, 1)
    rect(a, seek.x, seek.y + 9, seek.w, 3, colors.track)
    rect(a, seek.x, seek.y + 9, seek.w * ratio, 3, colors.accent)
    circle(a, seek.x + seek.w * ratio, seek.y + 10.5, 4.5, colors.text)
    hit("seek", seek.x, seek.y, seek.w, seek.h)
    local cy = panel_y + 98
    local function button(id, x, glyph, size)
        local r = { x = x - 23, y = cy - 23, w = 46, h = 46 }
        if inside(mx, my, r) then
            circle(a, x, cy, 21, colors.row)
        end
        if id == "mute" then
            speaker_icon(a, x, cy, muted)
        else
            icon(a, x, cy, glyph, size)
        end
        hit(id, r.x, r.y, r.w, r.h)
    end
    button("prev", 40, icons.prev, 25)
    button("play", 96, paused and icons.play or icons.pause, 32)
    button("next", 152, icons.next, 25)
    local vx = math.max(238, w - 280)
    local logo_x = w / 2
    local show_logo = logo_x - 18 > 178 and logo_x + 18 < vx - 30
    -- Use the visible next-icon edge, not its wider mouse hit target.
    local next_icon_right = 152 + 8
    local time_left = next_icon_right + 12
    local time_right = show_logo and logo_x - 14 - 12 or vx - 23 - 12
    local time_center = (time_left + time_right) / 2
    local time_clip =
        { math.floor(time_left), math.floor(cy - 20), math.floor(time_right), math.floor(cy + 20) }
    -- Center numeric labels on the same axis as the buttons and slider.
    -- Segoe UI numerals need a one-pixel optical correction at this size.
    local label_y = cy - 1
    if w > 650 then
        text(
            a,
            time_center,
            label_y,
            time_string(current) .. " / " .. time_string(duration),
            opts.font_size,
            colors.text,
            time_clip,
            5
        )
    end
    if show_logo then
        mpv_logo(a, logo_x, cy, 28)
    end
    button("mute", vx)
    local vol = { x = vx + 31, y = cy - 18, w = math.max(20, w - vx - 110), h = 36 }
    local fill = vol.w * clamp(volume / 100, 0, 1)
    rect(a, vol.x, cy - 1.5, vol.w, 3, colors.track)
    rect(a, vol.x, cy - 1.5, fill, 3, muted and colors.muted or colors.text)
    circle(a, vol.x + fill, cy, 4, colors.text)
    text(
        a,
        w - 22,
        label_y,
        string.format("%d%%", math.floor(volume + 0.5)),
        opts.font_size,
        colors.text,
        nil,
        6
    )
    hit("volume", vol.x, vol.y, vol.w, vol.h)
    layout = {
        count = count,
        max_scroll = max_scroll,
        list_y = list_y,
        list_h = list_h,
        duration = duration,
        seek = seek,
        volume = vol,
    }
    overlay.res_x = w
    overlay.res_y = h
    overlay.data = a.text
    overlay:update()
    dirty = false
end

activate = function(value)
    value = not not value
    if value == active then
        mark()
        return
    end
    active = value
    dragging = nil
    if active then
        mp.add_forced_key_binding("MBTN_LEFT", "click", on_click, { complex = true })
        mp.add_forced_key_binding("MBTN_LEFT_DBL", "double", function() end)
        mp.add_forced_key_binding("MOUSE_MOVE", "move", function()
            local x, y = mouse()
            update_drag(x, y)
            mark()
        end)
        mp.add_forced_key_binding("MOUSE_LEAVE", "leave", mark)
        mp.add_forced_key_binding("WHEEL_UP", "wheel-up", function()
            scroll(-opts.row_height * 2)
        end, { repeatable = true })
        mp.add_forced_key_binding("WHEEL_DOWN", "wheel-down", function()
            scroll(opts.row_height * 2)
        end, { repeatable = true })
        mark()
    else
        for _, name in ipairs(bindings) do
            mp.remove_key_binding(name)
        end
        overlay:remove()
        layout = nil
    end
end

options.read_options(opts, "audio-panel", mark)

-- Never watch transient codec properties to decide window/fullscreen state.
-- Apply the profile only on an actual audio/video mode transition.
local function set_audio_mode(value)
    if value == managed_audio then
        return
    end
    if value then
        mp.commandv("apply-profile", "AUTO_MUSIC")
    else
        mp.commandv("apply-profile", "AUTO_MUSIC", "restore")
    end
    managed_audio = value
    activate(value)
end
local function audio_extension(path)
    local clean = path:lower():gsub("[%?#].*$", "")
    local ext = clean:match("%.([%w]+)$")
    if not ext then
        return false
    end
    local extensions = mp.get_property_native("options/audio-exts") or {}
    if type(extensions) == "string" then
        for item in extensions:gmatch("[^,]+") do
            if ext == item then
                return true
            end
        end
    else
        for _, item in ipairs(extensions) do
            if ext == item then
                return true
            end
        end
    end
    return false
end
local function audio_playback_flags()
    -- Read playback policy from the config instead of hardcoding options.
    -- File-local settings are reset before the next file's resume is read.
    for _, profile in ipairs(mp.get_property_native("profile-list") or {}) do
        if profile.name == "AUDIO_PLAYBACK" then
            for _, option in ipairs(profile.options or {}) do
                local ok, err = mp.set_property("file-local-options/" .. option.key, option.value)
                if not ok then
                    mp.msg.error("AUDIO_PLAYBACK: " .. tostring(err))
                end
            end
            return
        end
    end
    mp.msg.error("Missing AUDIO_PLAYBACK profile")
end
mp.add_hook("on_load", 50, function()
    if audio_extension(mp.get_property("path", "")) then
        set_audio_mode(true)
        audio_playback_flags()
    end
    -- An unknown extension is not evidence of video. Preserve the window
    -- mode until on_preloaded can inspect tracks, avoiding fullscreen flashes.
end)
mp.add_hook("on_preloaded", 50, function()
    local audio, video = false, false
    for _, track in ipairs(mp.get_property_native("track-list") or {}) do
        if track.type == "audio" then
            audio = true
        end
        if track.type == "video" and not track.image and not track.albumart then
            video = true
        end
    end
    local audio_only = audio and not video
    set_audio_mode(audio_only)
    if audio_only then
        audio_playback_flags()
    end
end)
for _, name in ipairs({
    "playlist",
    "playlist-pos",
    "metadata",
    "media-title",
    "pause",
    "mute",
    "volume",
    "osd-dimensions",
}) do
    mp.observe_property(name, "native", mark)
end
mp.observe_property("time-pos", "number", mark)
mp.add_periodic_timer(1 / 60, function()
    local now = mp.get_time()
    local dt = clamp(now - previous_tick, 0, 0.05)
    previous_tick = now
    if not active then
        return
    end
    local difference = target_offset - offset
    if math.abs(difference) > 0.1 then
        offset = offset + difference * (1 - math.exp(-math.max(1, opts.smoothness) * dt))
        dirty = true
    elseif difference ~= 0 then
        offset = target_offset
        dirty = true
    end
    if dirty then
        render()
    end
end)
mp.register_event("shutdown", function()
    overlay:remove()
end)
