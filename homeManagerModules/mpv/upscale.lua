-- Anime4K upscaling on demand (mpvConfig.nix): off by default, three modes
-- from the modernx button (left click: the next mode, right click: off) or
-- Ctrl+1/2/3 (Ctrl+0: off; on AZERTY, Ctrl and the same keys). The mode
-- stays for the next files of the session (a series' next episodes). The
-- button reads it from user-data/upscale.
--
-- script-opts/upscale.conf: shaders (the Anime4K folder, from Nix) and
-- quality: fast (the M/S networks, for integrated GPUs) or hq (VL/M).

local options = require("mp.options")
local opts = { shaders = "", quality = "fast" }
options.read_options(opts, "upscale")

local function sets(q)
    local big = q == "hq" and "VL" or "M"
    local small = q == "hq" and "M" or "S"
    local tail = { "AutoDownscalePre_x2", "AutoDownscalePre_x4", "Upscale_CNN_x2_" .. small }
    local function mode(name, about, first)
        local list = { "Clamp_Highlights" }
        for _, s in ipairs(first) do list[#list + 1] = s end
        for _, s in ipairs(tail) do list[#list + 1] = s end
        return { name = name, about = about, shaders = list }
    end
    return {
        mode("A", "restore, then upscale (blurry or compressed sources)",
            { "Restore_CNN_" .. big, "Upscale_CNN_x2_" .. big }),
        mode("B", "soft restore, then upscale (sources already sharp)",
            { "Restore_CNN_Soft_" .. big, "Upscale_CNN_x2_" .. big }),
        mode("C", "denoise and upscale (noisy or grainy sources)",
            { "Upscale_Denoise_CNN_x2_" .. big }),
    }
end

local modes = sets(opts.quality)
local current = 0

local function publish()
    local m = modes[current]
    mp.set_property_native("user-data/upscale", {
        mode = current,
        name = m and m.name or "off",
        about = m and m.about or "",
        quality = opts.quality,
    })
end

local function set(n, quiet)
    if opts.shaders == "" then
        mp.osd_message("Upscale: no shaders (script-opts/upscale.conf)")
        return
    end
    current = (n >= 1 and n <= #modes) and n or 0
    local m = modes[current]
    local paths = {}
    if m then
        for _, s in ipairs(m.shaders) do
            paths[#paths + 1] = opts.shaders .. "/Anime4K_" .. s .. ".glsl"
        end
    end
    mp.set_property_native("glsl-shaders", paths)
    publish()
    if not quiet then
        mp.osd_message(m and ("Upscale " .. m.name .. ": " .. m.about) or "Upscale: off")
    end
end

mp.register_script_message("upscale-cycle", function() set((current + 1) % (#modes + 1)) end)
mp.register_script_message("upscale-set", function(n) set(tonumber(n) or 0) end)
mp.register_script_message("upscale-off", function() set(0) end)
-- Ctrl and the digit row: its digits, and the symbols an AZERTY keyboard
-- types there without Shift (& é " ' … à).
local azerty = { "&", "é", '"' }
for i = 1, #modes do
    mp.add_key_binding("ctrl+" .. i, "upscale-" .. modes[i].name:lower(), function() set(i) end)
    mp.add_key_binding("ctrl+" .. azerty[i], "upscale-" .. modes[i].name:lower() .. "-azerty", function() set(i) end)
end
mp.add_key_binding("ctrl+0", "upscale-off", function() set(0) end)
mp.add_key_binding("ctrl+à", "upscale-off-azerty", function() set(0) end)

publish()
