-- loading_message.lua
--
-- Shows a message while a stream is being opened, so the window opened by
-- force-window=immediate is not blank while yt-dlp resolves the URL

local host

mp.register_event("start-file", function()
    host = mp.get_property("path", ""):match("^%a[%w+.-]*://([^/?#]+)")
    if host then
        host = host:gsub("^www%.", "")
        mp.osd_message("Loading " .. host .. "…", 600)
    end
end)

mp.register_event("file-loaded", function()
    if host then
        mp.osd_message("")
        host = nil
    end
end)

local failed

mp.register_event("end-file", function(event)
    failed = event.reason == "error" and host or nil
    host = nil
end)

-- If the stream fails to open, keep the window up long enough to say so
-- before mpv quits
mp.add_hook("on_after_end_file", 50, function(hook)
    if not failed then return end
    mp.osd_message("Could not open " .. failed, 4)
    failed = nil
    hook:defer()
    mp.add_timeout(4, function() hook:cont() end)
end)
