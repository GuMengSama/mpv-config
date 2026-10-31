-- anime4k.lua
--
-- Anime4K presets (high-end GPU): Ctrl+1-6 pick a mode, Ctrl+0 turns it off.
-- The keys are only bound when the shaders are installed (the Anime4K
-- feature in install.sh), so they do nothing otherwise

local utils = require "mp.utils"

local function shader(name)
    return "~~/shaders/Anime4K_" .. name .. ".glsl"
end

local modes = {
    {key = "Ctrl+1", name = "mode-a", title = "Mode A (HQ)", shaders = {
        "Clamp_Highlights", "Restore_CNN_VL", "Upscale_CNN_x2_VL",
        "AutoDownscalePre_x2", "AutoDownscalePre_x4", "Upscale_CNN_x2_M"}},
    {key = "Ctrl+2", name = "mode-b", title = "Mode B (HQ)", shaders = {
        "Clamp_Highlights", "Restore_CNN_Soft_VL", "Upscale_CNN_x2_VL",
        "AutoDownscalePre_x2", "AutoDownscalePre_x4", "Upscale_CNN_x2_M"}},
    {key = "Ctrl+3", name = "mode-c", title = "Mode C (HQ)", shaders = {
        "Clamp_Highlights", "Upscale_Denoise_CNN_x2_VL",
        "AutoDownscalePre_x2", "AutoDownscalePre_x4", "Upscale_CNN_x2_M"}},
    {key = "Ctrl+4", name = "mode-aa", title = "Mode A+A (HQ)", shaders = {
        "Clamp_Highlights", "Restore_CNN_VL", "Upscale_CNN_x2_VL", "Restore_CNN_M",
        "AutoDownscalePre_x2", "AutoDownscalePre_x4", "Upscale_CNN_x2_M"}},
    {key = "Ctrl+5", name = "mode-bb", title = "Mode B+B (HQ)", shaders = {
        "Clamp_Highlights", "Restore_CNN_Soft_VL", "Upscale_CNN_x2_VL",
        "AutoDownscalePre_x2", "AutoDownscalePre_x4", "Restore_CNN_Soft_M", "Upscale_CNN_x2_M"}},
    {key = "Ctrl+6", name = "mode-ca", title = "Mode C+A (HQ)", shaders = {
        "Clamp_Highlights", "Upscale_Denoise_CNN_x2_VL",
        "AutoDownscalePre_x2", "AutoDownscalePre_x4", "Restore_CNN_M", "Upscale_CNN_x2_M"}},
}

if not utils.file_info(mp.command_native({"expand-path", shader("Clamp_Highlights")})) then
    return
end

for _, mode in ipairs(modes) do
    local paths = {}
    for i, name in ipairs(mode.shaders) do
        paths[i] = shader(name)
    end
    mp.add_key_binding(mode.key, mode.name, function()
        mp.command_native({"change-list", "glsl-shaders", "set", table.concat(paths, ":")})
        mp.osd_message("Anime4K: " .. mode.title)
    end)
end

mp.add_key_binding("Ctrl+0", "off", function()
    mp.command_native({"change-list", "glsl-shaders", "clr", ""})
    mp.osd_message("GLSL shaders cleared")
end)
