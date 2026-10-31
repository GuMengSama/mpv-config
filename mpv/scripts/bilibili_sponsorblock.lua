-- bilibili_sponsorblock.lua
--
-- Skips sponsored segments of Bilibili videos
-- using data from https://github.com/hanydd/BilibiliSponsorBlock

local utils = require "mp.utils"

local options = {
    -- install.sh turns this off when SponsorBlock is left out
    enabled = true,

    server_address = "https://bsbsb.top",

    -- Categories to skip, comma-separated
    -- (sponsor, selfpromo, interaction, intro, outro, preview, music_offtopic, filler)
    categories = "sponsor",

    -- If true, each segment is only skipped once, so you can seek back into it
    skip_once = true,

    -- Create chapters at segment boundaries (uosc colors them on the timeline)
    make_chapters = true,

    -- Segments shorter than this (in seconds) are ignored
    min_duration = 1,

    -- Length of the sha256 prefix (4-32) sent to the server instead of the video id
    sha256_length = 4,

    -- Full paths, because mpv launched from Chrome may not have a usable PATH
    curl_path = "/usr/bin/curl",
    shasum_path = "/usr/bin/shasum",
}

require("mp.options").read_options(options, "bilibili_sponsorblock")

local USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) mpv-bilibili-sponsorblock"

local segments = {}
local generation = 0
local observing = false

local function log_osd(text)
    mp.osd_message("[bilibili sponsorblock] " .. text)
end

local function url_encode(s)
    return (s:gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function json_list(csv)
    local items = {}
    for item in csv:gmatch("[^,%s]+") do
        items[#items + 1] = '"' .. item .. '"'
    end
    return "[" .. table.concat(items, ",") .. "]"
end

-- Runs curl without blocking playback; calls back with the parsed JSON, or nil
local function fetch_json(url, callback)
    local args = {options.curl_path, "-sS", "-f", "--max-time", "10", "-A", USER_AGENT, url}
    mp.command_native_async({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    }, function(success, result)
        if not success or result.status ~= 0 then
            -- curl exits with 22 on HTTP errors; the server returns 404 when it has no segments
            if result and result.status ~= 22 then
                mp.msg.warn("request failed: " .. url .. " " .. (result.stderr or ""))
            end
            return callback(nil)
        end
        callback(utils.parse_json(result.stdout))
    end)
end

local function sha256_prefix(text)
    local result = mp.command_native({
        name = "subprocess",
        args = {options.shasum_path, "-a", "256"},
        stdin_data = text,
        capture_stdout = true,
        playback_only = false,
    })
    if not result or result.status ~= 0 then return nil end
    return result.stdout:sub(1, options.sha256_length)
end

local function create_chapter(title, time)
    local chapters = mp.get_property_native("chapter-list") or {}
    chapters[#chapters + 1] = {title = title, time = time}
    table.sort(chapters, function(a, b) return a.time < b.time end)
    mp.set_property_native("chapter-list", chapters)
end

local function skip_segments(_, pos)
    if not pos then return end
    for _, s in ipairs(segments) do
        if not s.skipped and pos >= s.start_time and pos < s.end_time - 0.3 then
            mp.commandv("seek", s.end_time, "absolute")
            if options.skip_once then s.skipped = true end
            log_osd(s.category .. " skipped")
            return
        end
    end
end

local function use_segments(found)
    segments = found
    if #segments == 0 then return end
    mp.msg.info(#segments .. " segment(s) to skip")
    for _, s in ipairs(segments) do
        if options.make_chapters then
            local title = s.category:gsub("^%l", string.upper):gsub("_", " ")
            local id = s.uuid:sub(1, 6)
            create_chapter(title .. " segment start (" .. id .. ")", s.start_time)
            create_chapter(title .. " segment end (" .. id .. ")", s.end_time)
        end
    end
    if not observing then
        mp.observe_property("time-pos", "number", skip_segments)
        observing = true
    end
end

-- Keeps only skip segments that belong to this part of a multi-part video
local function filter_segments(raw, cid)
    local found = {}
    for _, s in ipairs(raw) do
        local start_time, end_time = s.segment[1], s.segment[2]
        local right_part = cid == nil or s.cid == nil or tostring(s.cid) == tostring(cid)
        if s.actionType == "skip" and right_part and end_time - start_time >= options.min_duration then
            found[#found + 1] = {
                start_time = start_time,
                end_time = end_time,
                category = s.category,
                uuid = s.UUID or "",
            }
        end
    end
    table.sort(found, function(a, b) return a.start_time < b.start_time end)
    return found
end

-- Follows a b23.tv short link one hop and returns where it points, without loading the page
local function resolve_short_link(url, callback)
    mp.command_native_async({
        name = "subprocess",
        args = {options.curl_path, "-sS", "--max-time", "10", "-A", USER_AGENT,
                "-o", "/dev/null", "-w", "%{redirect_url}", url},
        capture_stdout = true,
        playback_only = false,
    }, function(success, result)
        if not success or result.status ~= 0 or result.stdout == "" then
            mp.msg.warn("could not resolve short link: " .. url)
            return callback(nil)
        end
        callback(result.stdout)
    end)
end

-- Returns the video-info query ("bvid=..." or "aid=...") and the part number, or nil
local function parse_video_url(url)
    if not url:find("bilibili%.com") then return nil end
    local part = tonumber(url:match("[?&]p=(%d+)")) or 1
    local bvid = url:match("/video/(BV1%w+)") or url:match("[?&]bvid=(BV1%w+)")
    if bvid then return "bvid=" .. bvid:sub(1, 12), part end
    local aid = url:match("/video/[aA][vV](%d+)") or url:match("[?&]aid=(%d+)")
    if aid then return "aid=" .. aid, part end
    return nil
end

local function fetch_segments(bvid, cid, this_generation)
    local prefix = sha256_prefix(bvid)
    if not prefix then return mp.msg.warn("could not hash video id") end

    local url = options.server_address .. "/api/skipSegments/" .. prefix
        .. "?categories=" .. url_encode(json_list(options.categories))
        .. "&actionTypes=" .. url_encode('["skip"]')

    fetch_json(url, function(response)
        if this_generation ~= generation or type(response) ~= "table" then return end

        -- The hash prefix matches several videos; pick ours
        for _, video in ipairs(response) do
            if video.videoID == bvid then
                return use_segments(filter_segments(video.segments or {}, cid))
            end
        end
    end)
end

-- Looks up the BV id and this part's cid (segments are tagged with the cid of their part)
local function load_video(query, part, this_generation)
    local view_url = "https://api.bilibili.com/x/web-interface/view?" .. query
    fetch_json(view_url, function(view)
        if this_generation ~= generation then return end
        if type(view) ~= "table" or view.code ~= 0 or not view.data then
            return mp.msg.warn("could not look up video " .. query)
        end
        local cid
        for _, page in ipairs(view.data.pages or {}) do
            if page.page == part then cid = page.cid end
        end
        if not cid then
            return mp.msg.warn("could not find cid for part " .. part .. ", not skipping")
        end
        mp.msg.info("Bilibili video " .. view.data.bvid .. " part " .. part)
        fetch_segments(view.data.bvid, cid, this_generation)
    end)
end

local function file_loaded()
    generation = generation + 1
    local this_generation = generation
    segments = {}

    local path = mp.get_property("path", "")
    if path:find("^https?://b23%.tv/") then
        return resolve_short_link(path, function(target)
            if this_generation ~= generation or not target then return end
            local query, part = parse_video_url(target)
            if query then load_video(query, part, this_generation) end
        end)
    end

    local query, part = parse_video_url(path)
    if query then load_video(query, part, this_generation) end
end

if options.enabled then
    mp.register_event("file-loaded", file_loaded)
end
