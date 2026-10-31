-- whisper_subs.lua
--
-- Generates subtitles for the current video with whisper.cpp, chunk by chunk,
-- starting at the playhead and staying ahead of playback

local utils = require "mp.utils"

local options = {
    -- Full paths, because mpv launched from Chrome may not have a usable PATH
    mpv_path = "/opt/homebrew/bin/mpv",
    whisper_path = "/opt/homebrew/bin/whisper-cli",

    model = "~~/models/ggml-large-v3-turbo-q5_0.bin",
    vad_model = "~~/models/ggml-silero-v6.2.0.bin",

    -- Voice activity detection skips silence, which stops whisper from
    -- inventing lines there, but it also skips singing
    vad = true,

    -- Spoken language (zh, ja, en, ...). With auto, it is detected from the
    -- first chunk and kept for the rest of the video
    language = "auto",

    -- Initial prompt, e.g. 以下是普通话的句子。 to get Simplified Chinese
    prompt = "",

    -- Chunk lengths in seconds. The first chunk at the playhead is short so
    -- subtitles appear quickly
    first_chunk = 20,
    chunk = 60,

    -- How far ahead of the playhead to transcribe, in seconds
    lookahead = 180,

    threads = 8,
}

require("mp.options").read_options(options, "whisper_subs")

local enabled = false
local generation = 0
local job -- {start, finish, id} of the running chunk
local covered = {} -- sorted, non-overlapping {start, finish} ranges
local segments = {}
local language
local srt_path, work_dir, track_loaded

local function log_osd(text, duration)
    mp.msg.info(text)
    mp.osd_message("Whisper: " .. text, duration or 3)
end

local function format_time(t, srt)
    local ms = math.floor(t * 1000 + 0.5)
    local h = math.floor(ms / 3600000)
    local m = math.floor(ms / 60000) % 60
    local s = math.floor(ms / 1000) % 60
    if srt then
        return string.format("%02d:%02d:%02d,%03d", h, m, s, ms % 1000)
    end
    return h > 0 and string.format("%d:%02d:%02d", h, m, s) or string.format("%02d:%02d", m, s)
end

local function add_covered(start, finish)
    table.insert(covered, {start = start, finish = finish})
    table.sort(covered, function(a, b) return a.start < b.start end)
    local merged = {}
    for _, r in ipairs(covered) do
        local last = merged[#merged]
        if last and r.start <= last.finish then
            last.finish = math.max(last.finish, r.finish)
        else
            table.insert(merged, r)
        end
    end
    covered = merged
end

-- Returns the next uncovered range at or after pos, or nil if there is
-- nothing to do within the lookahead
local function next_range(pos)
    local start = math.floor(pos)
    local limit = math.huge
    for _, r in ipairs(covered) do
        if r.start <= start and start < r.finish then
            start = r.finish
        elseif r.start > start then
            limit = r.start
            break
        end
    end
    local duration = mp.get_property_number("duration")
    if start >= pos + options.lookahead or (duration and start >= duration - 0.5) then
        return nil
    end
    local length = start - pos < 5 and options.first_chunk or options.chunk
    local finish = math.min(start + length, limit, duration or math.huge)
    return start, finish
end

local function write_srt()
    table.sort(segments, function(a, b) return a.start < b.start end)
    local lines = {}
    for i, s in ipairs(segments) do
        table.insert(lines, string.format("%d\n%s --> %s\n%s\n",
            i, format_time(s.start, true), format_time(s.finish, true), s.text))
    end
    local f = io.open(srt_path, "w")
    if not f then
        log_osd("cannot write " .. srt_path, 5)
        return
    end
    f:write(table.concat(lines, "\n"))
    f:close()

    -- Re-added instead of sub-reload, which drops the track title
    local flag = "select"
    if track_loaded then
        for _, track in ipairs(mp.get_property_native("track-list")) do
            if track.type == "sub" and track["external-filename"] == srt_path then
                flag = track.selected and "select" or "auto"
                mp.commandv("sub-remove", track.id)
            end
        end
    end
    mp.commandv("sub-add", srt_path, flag, "Whisper")
    track_loaded = true
end

local function add_segments(start, finish, result)
    local kept = {}
    for _, s in ipairs(segments) do
        if s.start < start or s.start >= finish then
            table.insert(kept, s)
        end
    end
    segments = kept
    for _, item in ipairs(result.transcription or {}) do
        local text = item.text:gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then
            table.insert(segments, {
                start = start + item.offsets.from / 1000,
                finish = start + item.offsets.to / 1000,
                text = text,
            })
        end
    end
    if #segments > 0 then
        write_srt()
    end
end

local pump

local function run(args, callback)
    local this = generation
    job.id = mp.command_native_async({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    }, function(success, res, err)
        if this ~= generation then return end
        if not success or res.status ~= 0 then
            log_osd("failed: " .. (err or res.stderr or ""), 5)
            mp.msg.error(table.concat(args, " "))
            job = nil
            enabled = false
            return
        end
        callback()
    end)
end

-- Arguments for a second mpv that decodes the chunk's audio to 16 kHz mono WAV.
-- It reuses the URL and HTTP headers the player already resolved, so streams
-- opened through yt-dlp need no second lookup
local function extract_args(start, finish, wav)
    local args = {
        options.mpv_path, mp.get_property("stream-open-filename"),
        "--no-config", "--ytdl=no", "--vid=no", "--sid=no", "--really-quiet",
        "--start=" .. start, "--end=" .. finish, "--hr-seek=yes",
        "--audio-channels=mono", "--audio-samplerate=16000",
        "--o=" .. wav, "--of=wav", "--oac=pcm_s16le",
    }
    local aid = mp.get_property_number("aid")
    if aid then
        table.insert(args, "--aid=" .. aid)
    end
    for _, field in ipairs(mp.get_property_native("http-header-fields") or {}) do
        table.insert(args, "--http-header-fields-append=" .. field)
    end
    for _, name in ipairs({"user-agent", "referrer"}) do
        local value = mp.get_property(name, "")
        if value ~= "" then
            table.insert(args, "--" .. name .. "=" .. value)
        end
    end
    return args
end

pump = function()
    if not enabled or job then return end
    local pos = mp.get_property_number("time-pos")
    if not pos then return end
    local start, finish = next_range(pos)
    if not start then return end

    job = {start = start, finish = finish}
    if start - pos < 5 then
        log_osd(string.format("transcribing %s–%s", format_time(start), format_time(finish)))
    end

    local prefix = utils.join_path(work_dir, "chunk")
    local wav = prefix .. ".wav"
    run(extract_args(start, finish, wav), function()
        local args = {
            options.whisper_path, "-m", options.model, "-t", tostring(options.threads),
            "-l", language or options.language, "-oj", "-of", prefix, "-np", wav,
        }
        if options.vad then
            table.insert(args, "--vad")
            table.insert(args, "-vm")
            table.insert(args, options.vad_model)
        end
        if options.prompt ~= "" then
            table.insert(args, "--prompt")
            table.insert(args, options.prompt)
        end
        run(args, function()
            local f = io.open(prefix .. ".json")
            local result = f and utils.parse_json(f:read("*a"))
            if f then f:close() end
            if not result then
                log_osd("could not read whisper output", 5)
                job, enabled = nil, false
                return
            end
            if not language and result.result and #(result.transcription or {}) > 0 then
                language = result.result.language
                mp.msg.info("language: " .. language)
            end
            add_segments(start, finish, result)
            add_covered(start, finish)
            job = nil
            pump()
        end)
    end)
end

local function stop()
    generation = generation + 1
    if job and job.id then
        mp.abort_async_command(job.id)
    end
    job = nil
end

local function reset()
    stop()
    enabled = false
    covered, segments = {}, {}
    language = options.language ~= "auto" and options.language or nil
    srt_path, track_loaded = nil, false
end

-- Cuts s to at most n bytes without splitting a UTF-8 character, which
-- would make an invalid file name
local function truncate_utf8(s, n)
    if #s <= n then return s end
    while n > 0 and s:byte(n + 1) >= 0x80 and s:byte(n + 1) < 0xC0 do
        n = n - 1
    end
    return s:sub(1, n)
end

local function file_exists(path)
    return utils.file_info(path) ~= nil
end

local function toggle()
    if enabled then
        stop()
        enabled = false
        log_osd("stopped")
        return
    end
    options.model = mp.command_native({"expand-path", options.model})
    options.vad_model = mp.command_native({"expand-path", options.vad_model})
    local required = {options.whisper_path, options.mpv_path, options.model}
    if options.vad then
        table.insert(required, options.vad_model)
    end
    for _, path in ipairs(required) do
        if not file_exists(path) then
            log_osd("not found: " .. path .. "\nInstall it with ./install.sh whisper", 5)
            return
        end
    end

    if not srt_path then
        work_dir = mp.command_native({"expand-path", "~~cache/whisper"})
        if work_dir:sub(1, 1) ~= "/" then
            work_dir = utils.join_path(os.getenv("TMPDIR") or "/tmp", "mpv-whisper")
        end
        mp.command_native({name = "subprocess", args = {"mkdir", "-p", work_dir}})
        local title = mp.get_property("media-title", "video")
        title = truncate_utf8(title:gsub("[/\\:*?\"<>|]", "_"), 100)
        srt_path = utils.join_path(work_dir, title .. ".srt")
    end
    enabled = true
    pump()
end

-- Ctrl+g starts and stops it. Only bound when whisper.cpp and the model are
-- installed (the Whisper feature in install.sh)
if file_exists(options.whisper_path)
    and file_exists(mp.command_native({"expand-path", options.model})) then
    mp.add_key_binding("Ctrl+g", "toggle", toggle)
end

-- After a seek, drop the running chunk if another one is now more urgent
mp.register_event("playback-restart", function()
    if not enabled then return end
    local pos = mp.get_property_number("time-pos")
    if job and pos and not (job.start <= pos and pos < job.finish)
        and next_range(pos) ~= job.start then
        stop()
    end
    pump()
end)

mp.observe_property("time-pos", "number", function()
    if enabled and not job then pump() end
end)

mp.register_event("end-file", reset)
reset()
