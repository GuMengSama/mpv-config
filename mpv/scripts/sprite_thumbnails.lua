-- sprite_thumbnails.lua
--
-- Seek bar thumbnails for Bilibili and YouTube videos from the preview sprite
-- sheets the websites use, so they appear at once instead of after a network
-- seek. thumbfast (patched by patches/scripts/thumbfast.lua.patch) passes
-- uosc's requests here while this is active. Other videos, videos without
-- sprites, and local files are left to thumbfast.

local utils = require "mp.utils"
local msg = require "mp.msg"

local options = {
    -- Full paths, because mpv launched from Chrome may not have a usable PATH
    ffmpeg_path = "/opt/homebrew/bin/ffmpeg",
    curl_path = "/usr/bin/curl",

    -- Same thumbnail size as thumbfast's max_width and max_height
    max_width = 200,
    max_height = 200,
}

require("mp.options").read_options(options, "sprite_thumbnails")

local overlay_id = 43
local user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " ..
    "(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

local work_dir = utils.join_path(os.getenv("TMPDIR") or "/tmp", "mpv-sprite-thumbnails-" .. utils.getpid())

-- Bumped on every new file, so replies for an earlier file are ignored
local generation = 0
-- The sprites of the current video: sheet URLs, tiles per row and column,
-- tile size, and the start time of each tile (times[k + 1] for tile k)
local shot
local sheets = {}   -- sheet number -> local path, once downloaded
local tiles = {}    -- tile number -> true, once cut out of its sheet
local width, height -- displayed tile size
local wanted        -- {tile, x, y} that uosc asked for, nil when hidden
local shown         -- tile number on screen
local cutting = false

local function set_active(active)
    mp.set_property_native("user-data/sprite_thumbnails/active", active)
end

local function run(args, callback)
    mp.command_native_async({
        name = "subprocess", args = args, capture_stdout = true, playback_only = false,
    }, function(success, result)
        callback(success and result.status == 0, result and result.stdout)
    end)
end

local function curl(url, out, callback)
    local args = {options.curl_path, "-sfL", "--max-time", "20", "-A", user_agent, url}
    if url:find("bilibili%.com") then
        table.insert(args, 2, "-e")
        table.insert(args, 3, "https://www.bilibili.com/")
    end
    if out then
        table.insert(args, 2, "-o")
        table.insert(args, 3, out)
    end
    run(args, callback)
end

local function tile_path(tile)
    return utils.join_path(work_dir, generation .. "-" .. tile .. ".bgra")
end

local function show(tile)
    shown = tile
    mp.command_native_async({"overlay-add", overlay_id, wanted.x, wanted.y, tile_path(tile),
        0, "bgra", width, height, 4 * width}, function() end)
end

local function render()
    if not wanted then return end
    if tiles[wanted.tile] then
        show(wanted.tile)
        return
    end
    -- Keep the last tile under the cursor until the new one is ready
    if shown then show(shown) end

    local per_sheet = shot.columns * shot.rows
    local sheet = math.floor(wanted.tile / per_sheet) + 1
    if cutting or not sheets[sheet] then return end

    local tile = wanted.tile
    local within = tile % per_sheet
    local w, h = shot.width, shot.height
    local crop = string.format("crop=%d:%d:%d:%d,scale=%d:%d", w, h,
        within % shot.columns * w, math.floor(within / shot.columns) * h, width, height)
    local gen = generation
    cutting = true
    run({options.ffmpeg_path, "-v", "error", "-y", "-i", sheets[sheet], "-vf", crop,
        "-f", "rawvideo", "-pix_fmt", "bgra", tile_path(tile)}, function(ok)
        if gen ~= generation then return end
        cutting = false
        if ok then
            tiles[tile] = true
        else
            msg.warn("could not cut tile " .. tile .. " from " .. sheets[sheet])
        end
        render()
    end)
end

-- The tile for a time: the last one that starts at or before it
local function tile_at(time)
    local times = shot.times
    local lo, hi = 0, #times - 1
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if times[mid + 1] <= time then lo = mid else hi = mid - 1 end
    end
    return lo
end

local function announce()
    local scale = mp.get_property_number("display-hidpi-scale", 1)
    local w, h = shot.width, shot.height
    if w / h > options.max_width / options.max_height then
        width = math.floor(options.max_width * scale + 0.5)
        height = math.floor(h / w * width + 0.5)
    else
        height = math.floor(options.max_height * scale + 0.5)
        width = math.floor(w / h * height + 0.5)
    end
    tiles, shown = {}, nil
    mp.commandv("script-message", "thumbfast-info", utils.format_json({
        width = width, height = height, disabled = false, available = true, overlay_id = overlay_id,
    }))
end

local function start(sprites)
    shot = sprites
    mp.command_native({name = "subprocess", args = {"mkdir", "-p", work_dir}, playback_only = false})
    local gen = generation
    for i, url in ipairs(shot.sheets) do
        local path = utils.join_path(work_dir, gen .. "-sheet" .. i .. ".jpg")
        curl(url, path, function(ok)
            if gen ~= generation then return end
            if ok then
                sheets[i] = path
                render()
            else
                msg.warn("could not download " .. url)
            end
        end)
    end
    announce()
    set_active(true)
end

-- Bilibili's APIs answer {code, data}, or {code, result} for bangumi
local function get_json(url, callback)
    local gen = generation
    curl(url, nil, function(ok, stdout)
        if gen ~= generation then return end
        local json = ok and utils.parse_json(stdout or "")
        local data = json and json.code == 0 and (json.data or json.result)
        if type(data) ~= "table" then
            msg.verbose("no data from " .. url)
            return
        end
        callback(data)
    end)
end

-- Bilibili's player API, as the website uses it. index[1] is a placeholder;
-- the rest are the tile start times
local function videoshot(bvid, cid)
    get_json("https://api.bilibili.com/x/player/videoshot?index=1&bvid=" .. bvid .. "&cid=" .. cid,
        function(data)
            if type(data.image) ~= "table" or #data.image == 0
                or type(data.index) ~= "table" or #data.index < 2 then
                msg.verbose("this video has no preview sprites")
                return
            end
            local sheet_urls, times = {}, {}
            for i, url in ipairs(data.image) do
                sheet_urls[i] = url:sub(1, 2) == "//" and ("https:" .. url) or url
            end
            for i = 2, #data.index do
                times[i - 1] = data.index[i]
            end
            start({
                sheets = sheet_urls,
                columns = data.img_x_len, rows = data.img_y_len,
                width = data.img_x_size, height = data.img_y_size,
                times = times,
            })
        end)
end

local function bilibili(path)
    -- Bangumi episode (a season URL becomes a playlist of these)
    local ep = tonumber(path:match("/bangumi/play/ep(%d+)"))
    if ep then
        get_json("https://api.bilibili.com/pgc/view/web/season?ep_id=" .. ep, function(season)
            local lists = {season.episodes}
            for _, section in ipairs(season.section or {}) do
                table.insert(lists, section.episodes)
            end
            for _, list in ipairs(lists) do
                for _, episode in ipairs(list or {}) do
                    if episode.id == ep then
                        videoshot(episode.bvid, episode.cid)
                        return
                    end
                end
            end
        end)
        return
    end

    local query = path:match("/video/(BV%w+)")
    query = query and ("bvid=" .. query)
    if not query then
        query = path:match("/video/av(%d+)")
        query = query and ("aid=" .. query)
    end
    if not query then return end
    local page = tonumber(path:match("[?&]p=(%d+)")) or 1

    get_json("https://api.bilibili.com/x/web-interface/view?" .. query, function(view)
        local part = view.pages and (view.pages[page] or view.pages[1])
        if part then videoshot(view.bvid, part.cid) end
    end)
end

-- YouTube's storyboards, from the yt-dlp output ytdl_hook leaves behind. The
-- largest one has one tile every 1 / fps seconds
local function youtube()
    local result = mp.get_property_native("user-data/mpv/ytdl/json-subprocess-result")
    local json = result and result.status == 0 and utils.parse_json(result.stdout or "")
    if not json or json.is_live or type(json.formats) ~= "table" then return end

    local best
    for _, f in ipairs(json.formats) do
        if f.format_note == "storyboard" and f.fragments and f.fps and f.fps > 0
            and f.columns and f.rows and f.width and f.height
            and (not best or f.width > best.width) then
            best = f
        end
    end
    if not best then
        msg.verbose("this video has no storyboard")
        return
    end

    local sheet_urls, duration = {}, 0
    for i, fragment in ipairs(best.fragments) do
        sheet_urls[i] = fragment.url
        duration = duration + (fragment.duration or 0)
    end
    local times = {}
    for k = 0, math.max(math.ceil(duration * best.fps - 1e-6), 1) - 1 do
        times[k + 1] = k / best.fps
    end
    start({
        sheets = sheet_urls,
        columns = best.columns, rows = best.rows,
        width = best.width, height = best.height,
        times = times,
    })
end

local function clear()
    wanted, shown = nil, nil
    mp.command_native_async({"overlay-remove", overlay_id}, function() end)
end

mp.register_event("start-file", function()
    generation = generation + 1
    shot, sheets, tiles, cutting = nil, {}, {}, false
    clear()
    set_active(false)
    mp.command_native({name = "subprocess", args = {"rm", "-rf", work_dir}, playback_only = false})

    -- Starts before yt-dlp finishes, since the API doesn't need it
    local path = mp.get_property("path", "")
    if path:find("^https?://[%w.]*bilibili%.com/video/") or path:find("^https?://[%w.]*bilibili%.com/bangumi/play/ep") then
        bilibili(path)
    end
end)

mp.register_event("file-loaded", function()
    local path = mp.get_property("path", "")
    if path:find("^https?://[%w.]*youtube%.com/") or path:find("^https?://youtu%.be/") then
        youtube()
    end
end)

mp.register_script_message("thumb", function(time, x, y)
    time, x, y = tonumber(time), tonumber(x), tonumber(y)
    if not shot or not time or not x or not y then return end
    wanted = {tile = tile_at(time), x = math.floor(x + 0.5), y = math.floor(y + 0.5)}
    render()
end)

mp.register_script_message("clear", clear)

mp.observe_property("display-hidpi-scale", "native", function()
    if shot then announce() end
end)

mp.register_event("shutdown", function()
    mp.command_native({name = "subprocess", args = {"rm", "-rf", work_dir}, playback_only = false})
end)
