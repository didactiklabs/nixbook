-- Video quality for what yt-dlp plays (YouTube…), from the gear button in
-- modernx's control bar (left click: a menu, right click: back to the
-- default) (mpvConfig.nix). Nothing is asked from the site again: mpv's
-- yt-dlp hook already lists every format of the video as an "edition", the
-- best first, and switching edition goes on from the same moment. This puts
-- them in a short list, one line per size and frame rate (the format yt-dlp
-- ranks first for it), with every format one step further.
--
-- The quality a video starts at: `default` in script-opts/quality.conf
-- (best, or a height: 2160, 1440, 1080, 720, 480, 360), else nixbook-shell's
-- setting (Settings > Apps & accounts > YouTube: media.videoQuality in its
-- config.json, read at each video), else the best. A height means the best
-- format that is not taller. A quality picked in the menu stays for the next
-- videos of the session. The button reads the state from user-data/quality.

local options = require("mp.options")
local input = require("mp.input")
local utils = require("mp.utils")
local opts = { default = "", settings = "" }
options.read_options(opts, "quality")

local function settings_path()
    if opts.settings ~= "" then return opts.settings end
    local config = os.getenv("XDG_CONFIG_HOME")
    if not config or config == "" then config = (os.getenv("HOME") or "") .. "/.config" end
    return config .. "/nixbook-shell/config.json"
end

-- "best" or a height.
local function limit_of(value)
    local n = tonumber(value)
    if n and n >= 100 then return math.floor(n) end
    return "best"
end

local function default_limit()
    if opts.default ~= "" then return limit_of(opts.default) end
    local file = io.open(settings_path(), "r")
    if not file then return "best" end
    local text = file:read("*a")
    file:close()
    local settings = utils.parse_json(text or "")
    local media = type(settings) == "table" and settings.media
    return limit_of(type(media) == "table" and media.videoQuality or "")
end

-- The formats of the video: mpv's editions whose title is one of its yt-dlp
-- hook's, "401 - 3840x2160 (2160p60) (av1 60 fps 8981 kbps)".
local function formats()
    local list = {}
    for _, edition in ipairs(mp.get_property_native("edition-list") or {}) do
        local title = edition.title or ""
        local w, h = title:match("^%S+ %- (%d+)x(%d+)")
        if h then
            local codec, fps = title:match("%((%w+) (%d+) fps")
            local kbps = title:match(" fps (%d+) kbps%)")
            list[#list + 1] = {
                id = edition.id, title = title, w = tonumber(w), h = tonumber(h),
                codec = codec or "", fps = tonumber(fps) or 0, kbps = tonumber(kbps),
            }
        end
    end
    return list
end

-- "1080p60": the height, with the frame rate when it is a fast one.
local function name_of(format)
    return format.h .. "p" .. (format.fps > 30 and format.fps or "")
end

-- One per size and frame rate, the first of each (yt-dlp's best), as listed:
-- largest first.
local function qualities(list)
    local seen, out = {}, {}
    for _, format in ipairs(list) do
        local name = name_of(format)
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = format
        end
    end
    return out
end

-- The format for a limit: the first one not taller, the smallest when all are.
local function pick(list, limit)
    if #list == 0 then return nil end
    if limit == "best" then return list[1] end
    for _, format in ipairs(list) do
        if format.h <= limit then return format end
    end
    return list[#list]
end

-- What the session asked for in the menu: "best", a height, or nil (the default).
local chosen = nil
local function wanted_limit()
    return chosen or default_limit()
end

local function current(list)
    local id = mp.get_property_number("current-edition")
    for _, format in ipairs(list) do
        if format.id == id then return format end
    end
    return nil
end

local function publish()
    local list = formats()
    local now = current(list)
    local limit = wanted_limit()
    mp.set_property_native("user-data/quality", {
        available = #qualities(list) > 1,
        name = now and name_of(now) or "",
        limit = tostring(limit),
        default = chosen == nil,
    })
end

local function detail(format)
    local parts = {}
    if format.codec ~= "" then parts[#parts + 1] = format.codec:upper() end
    if format.kbps then
        parts[#parts + 1] = format.kbps >= 1000 and string.format("%.1f Mb/s", format.kbps / 1000)
            or (format.kbps .. " kb/s")
    end
    return table.concat(parts, " ")
end

local function switch(format, message)
    if not format then return end
    if mp.get_property_number("current-edition") ~= format.id then
        mp.set_property_number("edition", format.id)
    end
    if message then mp.osd_message("Quality: " .. name_of(format) .. " (" .. detail(format) .. ")") end
    publish()
end

-- limit: "best", a height, or nil for the default again.
local function set(limit)
    chosen = limit
    local list = formats()
    if #list == 0 then
        mp.osd_message("Quality: this video has one only")
        return
    end
    switch(pick(list, wanted_limit()), true)
end

local function every_format()
    local list = formats()
    local now = current(list)
    local items, default_item = {}, 1
    for i, format in ipairs(list) do
        items[i] = ((now and now.id == format.id) and "● " or "   ") .. format.title
        if now and now.id == format.id then default_item = i end
    end
    input.select({
        prompt = "Format:",
        items = items,
        default_item = default_item,
        submit = function(i) switch(list[i], true) end,
    })
end

local function menu()
    local list = formats()
    if #list == 0 then
        mp.osd_message("Quality: this video has one only")
        return
    end
    local now = current(list)
    local items, choices, default_item = {}, {}, 1
    local function add(label, act)
        items[#items + 1] = label
        choices[#choices + 1] = act
    end
    local start = pick(list, default_limit())
    add((chosen == nil and "● " or "   ") .. "Default" .. (start and (": " .. name_of(start)) or ""),
        function() set(nil) end)
    for _, format in ipairs(qualities(list)) do
        local on = chosen ~= nil and now ~= nil and name_of(now) == name_of(format)
        if on then default_item = #items + 1 end
        add((on and "● " or "   ") .. name_of(format) .. "  " .. detail(format), function()
            -- The same size and rate for the next videos, or the nearest under it.
            chosen = format.h
            switch(format, true)
        end)
    end
    add("   Every format…", every_format)
    input.select({
        prompt = "Quality:",
        items = items,
        default_item = default_item,
        submit = function(i) if choices[i] then choices[i]() end end,
    })
end

mp.register_script_message("quality-menu", menu)
mp.register_script_message("quality-default", function() set(nil) end)
mp.register_script_message("quality-set", function(value)
    set(value == "default" and nil or limit_of(value))
end)

-- Each video starts at the quality wanted, as soon as its formats are known
-- (they aren't yet in the on_preloaded hook): a format isn't opened until it
-- is the one shown, so the first one costs nothing.
local applied = nil
local function start()
    local path = mp.get_property("path") or ""
    local list = formats()
    if #list > 0 and applied ~= path then
        applied = path
        switch(pick(list, wanted_limit()), false)
    end
    publish()
end
mp.register_event("file-loaded", start)
mp.register_event("end-file", function(event)
    -- The same video opened again later starts at the wanted quality again;
    -- not after the reload a switch itself makes.
    if event.reason ~= "redirect" and event.reason ~= "reload" then applied = nil end
    mp.set_property_native("user-data/quality", { available = false, name = "", limit = "", default = true })
end)
mp.observe_property("current-edition", "number", publish)
mp.observe_property("edition-list", "native", start)
