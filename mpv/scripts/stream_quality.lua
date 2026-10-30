-- stream_quality.lua
--
-- Replaces uosc's stream quality button with the qualities the current stream
-- really has: one entry per resolution and frame rate, and an Audio submenu
-- with one entry per bitrate (and language, when there are several)

local utils = require "mp.utils"

local formats -- {video, audio, active_video, active_audio} for the current file
local chosen = {} -- path -> {video = format_id, audio = format_id}

local function round(x)
    return math.floor(x + 0.5)
end

local function has(codec)
    return codec ~= nil and codec ~= "none"
end

-- yt-dlp lists formats from worst to best, so a later duplicate replaces an
-- earlier one and each entry keeps the best format for its key
local function unique(list, key)
    local by_key, keys = {}, {}
    for _, f in ipairs(list) do
        local k = key(f)
        if not by_key[k] then
            table.insert(keys, k)
        end
        by_key[k] = f
    end
    local result = {}
    for _, k in ipairs(keys) do
        table.insert(result, by_key[k])
    end
    return result
end

local function parse(json)
    local result = utils.parse_json(json)
    if not result or not result.formats then
        return nil
    end

    local video, muxed, audio = {}, {}, {}
    for _, f in ipairs(result.formats) do
        if has(f.vcodec) and f.height then
            table.insert(has(f.acodec) and muxed or video, f)
        elseif has(f.acodec) then
            table.insert(audio, f)
        end
    end
    -- Formats with audio built in only matter when there is nothing else
    if #video == 0 then
        video = muxed
    end

    video = unique(video, function(f)
        return f.height .. "@" .. round(f.fps or 0)
    end)
    table.sort(video, function(a, b)
        if a.height ~= b.height then return a.height > b.height end
        return (a.fps or 0) > (b.fps or 0)
    end)

    local languages = {}
    for _, f in ipairs(audio) do
        languages[f.language or ""] = true
    end
    local many_languages = next(languages, next(languages)) ~= nil
    -- Bitrates within 10 kbps (e.g. 129k AAC and 127k Opus) count as one
    audio = unique(audio, function(f)
        return round((f.abr or f.tbr or 0) / 10) .. (many_languages and (f.language or "") or "")
    end)
    table.sort(audio, function(a, b)
        if (a.language or "") ~= (b.language or "") then
            return (a.language or "") < (b.language or "")
        end
        return (a.abr or a.tbr or 0) > (b.abr or b.tbr or 0)
    end)

    local active_video, active_audio
    for _, f in ipairs(result.requested_formats or {result}) do
        if has(f.vcodec) then active_video = f.format_id end
        if has(f.acodec) then active_audio = f.format_id end
    end

    return {
        video = video,
        audio = audio,
        many_languages = many_languages,
        active_video = active_video,
        active_audio = active_audio,
    }
end

-- Reloads the stream with the chosen formats and returns to the same position
local function choose(kind, format_id)
    local path = mp.get_property("path")
    chosen[path] = chosen[path] or {video = formats.active_video, audio = formats.active_audio}
    chosen[path][kind] = format_id

    local position = mp.get_property_number("time-pos")
    if position then
        local function seek()
            mp.unregister_event(seek)
            mp.commandv("seek", position, "absolute+exact")
        end
        mp.register_event("file-loaded", seek)
    end
    mp.command("playlist-play-index current")
end

mp.register_script_message("choose", choose)

local function item(kind, f, title, hint, active_id)
    return {
        title = title,
        hint = hint,
        active = f.format_id == active_id,
        value = {"script-message-to", mp.get_script_name(), "choose", kind, f.format_id},
    }
end

local function open_menu()
    if not formats then
        mp.osd_message("Qualities are not known yet", 2)
        return
    end

    local items = {}
    for _, f in ipairs(formats.video) do
        local title = f.width and (f.width .. "x" .. f.height) or (f.height .. "p")
        local hint = f.fps and f.fps > 0 and (round(f.fps) .. " fps") or nil
        table.insert(items, item("video", f, title, hint, formats.active_video))
    end

    local audio_items = {}
    for _, f in ipairs(formats.audio) do
        local rate = f.abr or f.tbr
        local title = rate and (round(rate) .. " kbps") or f.format_id
        local hint = formats.many_languages and f.language or nil
        table.insert(audio_items, item("audio", f, title, hint, formats.active_audio))
    end
    if #audio_items > 1 then
        table.insert(items, {title = "Audio", items = audio_items})
    end

    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json({
        type = "stream_quality",
        title = "Quality",
        items = items,
    }))
end

mp.add_key_binding(nil, "open", open_menu)

-- Set the chosen formats before ytdl_hook (priority 10) runs yt-dlp
mp.add_hook("on_load", 9, function()
    local choice = chosen[mp.get_property("path")]
    if not (choice and choice.video) then return end
    local format = choice.video
    if choice.audio and choice.audio ~= choice.video then
        format = format .. "+" .. choice.audio
    end
    mp.set_property("file-local-options/ytdl-format", format)
end)

mp.register_event("start-file", function()
    formats = nil
end)

-- ytdl_hook leaves yt-dlp's output here, so no second yt-dlp call is needed
mp.observe_property("user-data/mpv/ytdl/json-subprocess-result", "native", function(_, result)
    if result and result.status == 0 and result.stdout ~= "" then
        formats = parse(result.stdout)
    end
end)

mp.register_script_message("uosc-version", function()
    mp.commandv("script-message-to", "uosc", "overwrite-binding", "stream-quality",
        "script-binding " .. mp.get_script_name() .. "/open")
end)
mp.commandv("script-message-to", "uosc", "get-version", mp.get_script_name())
