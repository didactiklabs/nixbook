-- Picture modes on demand (mpvConfig.nix), from the HD button in modernx's
-- control bar (left click: a menu, right click: upscaling off) or the keys
-- Ctrl+1…5 (Ctrl+0: off) and Ctrl+M (smooth motion); on AZERTY, Ctrl and
-- the same digit-row keys. The mode stays for the next files of the
-- session (a series' next episodes). The button reads the state from
-- user-data/upscale.
--
--   Anime A/B/C    Anime4K: restore then upscale, a softer restore, or
--                  denoise and upscale (drawn art only)
--   Film           FSRCNNX: a clean upscale for live action
--   Sharpen        adaptive-sharpen: a bit of bite for soft sources
--   Smooth motion  frame interpolation (24 fps without judder), with any
--
-- Always under them: the `base` shaders (chroma from luma: cleaner colour
-- edges). script-opts/upscale.conf: shaders (one folder of every shader,
-- from Nix), base (file names, comma-separated), quality fast|hq.

local options = require("mp.options")
local input = require("mp.input")
local opts = { shaders = "", base = "", quality = "fast" }
options.read_options(opts, "upscale")

local hq = opts.quality == "hq"
local function anime(list)
    local small = hq and "M" or "S"
    local out = { "Anime4K_Clamp_Highlights.glsl" }
    for _, s in ipairs(list) do out[#out + 1] = "Anime4K_" .. s .. ".glsl" end
    for _, s in ipairs({ "AutoDownscalePre_x2", "AutoDownscalePre_x4", "Upscale_CNN_x2_" .. small }) do
        out[#out + 1] = "Anime4K_" .. s .. ".glsl"
    end
    return out
end
local big = hq and "VL" or "M"
local modes = {
    { name = "Anime A", about = "restore, then upscale (blurry or compressed sources)",
      shaders = anime({ "Restore_CNN_" .. big, "Upscale_CNN_x2_" .. big }) },
    { name = "Anime B", about = "soft restore, then upscale (sources already sharp)",
      shaders = anime({ "Restore_CNN_Soft_" .. big, "Upscale_CNN_x2_" .. big }) },
    { name = "Anime C", about = "denoise and upscale (noisy or grainy sources)",
      shaders = anime({ "Upscale_Denoise_CNN_x2_" .. big }) },
    { name = "Film", about = "a clean upscale for live action (FSRCNNX)",
      shaders = { hq and "FSRCNNX_x2_16-0-4-1.glsl" or "FSRCNNX_x2_8-0-4-1.glsl" } },
    { name = "Sharpen", about = "a bit of bite for soft sources (adaptive-sharpen)",
      shaders = { "adaptive-sharpen.glsl" } },
}

local base = {}
for name in opts.base:gmatch("[^,%s]+") do base[#base + 1] = name end

local current, smooth = 0, false

local function publish()
    local m = modes[current]
    mp.set_property_native("user-data/upscale", {
        mode = current,
        name = m and m.name or "off",
        about = m and m.about or "",
        smooth = smooth,
        quality = opts.quality,
    })
end

local function apply()
    local paths = {}
    if opts.shaders ~= "" then
        for _, s in ipairs(base) do paths[#paths + 1] = opts.shaders .. "/" .. s end
        for _, s in ipairs(modes[current] and modes[current].shaders or {}) do
            paths[#paths + 1] = opts.shaders .. "/" .. s
        end
    end
    mp.set_property_native("glsl-shaders", paths)
    publish()
end

local function set(n)
    if opts.shaders == "" then
        mp.osd_message("Picture modes: no shaders (script-opts/upscale.conf)")
        return
    end
    current = (n >= 1 and n <= #modes) and n or 0
    apply()
    local m = modes[current]
    mp.osd_message(m and (m.name .. ": " .. m.about) or "Upscaling off")
end

local function set_smooth(on)
    smooth = on
    if on then
        mp.set_property("video-sync", "display-resample")
        mp.set_property("tscale", "oversample")
    else
        mp.set_property("video-sync", "audio")
    end
    mp.set_property_bool("interpolation", on)
    publish()
    mp.osd_message(on and "Smooth motion: on" or "Smooth motion: off")
end

local function menu()
    local items, choices = {}, {}
    local function add(label, act)
        items[#items + 1] = label
        choices[#choices + 1] = act
    end
    add((current == 0 and "● " or "   ") .. "Upscaling off", function() set(0) end)
    for i, m in ipairs(modes) do
        add((current == i and "● " or "   ") .. m.name .. ": " .. m.about, function() set(i) end)
    end
    add((smooth and "☑ " or "☐ ") .. "Smooth motion (frame interpolation)", function() set_smooth(not smooth) end)
    input.select({
        prompt = "Picture:",
        items = items,
        default_item = current + 1,
        submit = function(i) if choices[i] then choices[i]() end end,
    })
end

mp.register_script_message("upscale-menu", menu)
mp.register_script_message("upscale-cycle", function() set((current + 1) % (#modes + 1)) end)
mp.register_script_message("upscale-set", function(n) set(tonumber(n) or 0) end)
mp.register_script_message("upscale-off", function() set(0) end)
mp.register_script_message("smooth-toggle", function() set_smooth(not smooth) end)

-- Ctrl and the digit row: its digits, and the symbols an AZERTY keyboard
-- types there without Shift (& é " ' ( … à).
local azerty = { "&", "é", '"', "'", "(" }
for i = 1, #modes do
    local id = "upscale-" .. modes[i].name:lower():gsub("%s+", "-")
    mp.add_key_binding("ctrl+" .. i, id, function() set(i) end)
    mp.add_key_binding("ctrl+" .. azerty[i], id .. "-azerty", function() set(i) end)
end
mp.add_key_binding("ctrl+0", "upscale-off", function() set(0) end)
mp.add_key_binding("ctrl+à", "upscale-off-azerty", function() set(0) end)
mp.add_key_binding("ctrl+m", "smooth-motion", function() set_smooth(not smooth) end)

-- The base shaders from the first file on.
apply()
