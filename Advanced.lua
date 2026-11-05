-- Advanced.lua: the graphics settings only a console command can change, for the Advanced pages (spec
-- 2026-11-03-advanced-page-title-switch-and-menu-design.md A2, A4, A6). Pure data and lookups; it reads the game only to ask
-- which settings exist. Loaded right after Names.lua, before Bench.lua.
local _, ns = ...

local advanced = {}
ns.advanced = advanced

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar

local OFF_ON = { ["0"] = "Off", ["1"] = "On" }

-- One entry per setting: its console name, plain name, one line, the levels offered (the game's default among them), plain words for
-- the levels where numbers mean nothing, the page it sits on, and for a risky setting the safe value the addon puts back when the
-- player logs out (the client's default: none of these is in the game's menu). The settings and their defaults are the ones the
-- retail client answered for in the owner's /fset probe of 2026-11-03; a client that lacks one does not show it.
advanced.CATALOG = {
    -- Effects
    { cvar = "ffxGlow", name = "Glow", line = "A soft glow around bright lights and magic.", levels = { "0", "1" }, levelWords = OFF_ON,
      page = "adv-effects" },
    { cvar = "ffxDeath", name = "Grey death screen", line = "The world turns grey while you are dead.", levels = { "0", "1" },
      levelWords = OFF_ON, page = "adv-effects" },
    { cvar = "WeatherDensity", name = "Weather", line = "How much rain, snow and sand the weather draws.", levels = { "0", "1", "2", "3" },
      levelWords = { ["0"] = "Off", ["1"] = "Low", ["2"] = "Mid", ["3"] = "High" }, page = "adv-effects" },
    { cvar = "sunshafts", name = "Sun rays", line = "Rays of light from the sun through trees and clouds.", levels = { "0", "1", "2" },
      levelWords = { ["0"] = "Off", ["1"] = "Low", ["2"] = "High" }, page = "adv-effects" },
    { cvar = "volumeFogLevel", name = "Fog detail", line = "How detailed fog and mist look.", levels = { "0", "1", "2", "3", "4" },
      page = "adv-effects" },
    { cvar = "reflectionMode", name = "Water reflections", line = "What water reflects: from the sky only up to everything around it.",
      levels = { "0", "1", "2", "3" }, page = "adv-effects" },
    { cvar = "refraction", name = "Water distortion", line = "How water and glass bend what is behind them.", levels = { "0", "1", "2" },
      page = "adv-effects" },
    { cvar = "ResampleSharpness", name = "Sharpening", line = "Sharpens the picture; most visible when picture sharpness is below 100%.",
      levels = { "0", "0.2", "0.5", "1" }, levelWords = { ["0"] = "Off", ["0.2"] = "20%", ["0.5"] = "50%", ["1"] = "100%" },
      page = "adv-effects" },
    -- Distance
    { cvar = "groundEffectDist", name = "Grass and plants distance", line = "How far away grass and plants are drawn.",
      levels = { "70", "140", "200", "260", "320", "400", "500" }, page = "adv-distance" },
    { cvar = "farclip", name = "View distance (further)", line = "How far away the world is drawn, past the game menu's view distance.",
      levels = { "1000", "2000", "4000", "6000", "8000", "10000" }, risky = true, safe = "1000", page = "adv-distance" },
    { cvar = "horizonStart", name = "Distant land start", line = "How far away the distant land begins.",
      levels = { "800", "1600", "2400", "3200", "4000" }, risky = true, safe = "800", page = "adv-distance" },
    { cvar = "horizonClip", name = "Distant land end", line = "How far away the distant land stops.",
      levels = { "1600", "3200", "5000", "7500", "10000" }, risky = true, safe = "1600", page = "adv-distance" },
    -- Detail in the distance
    { cvar = "terrainLodDist", name = "Ground detail distance", line = "How far away the ground keeps its full detail.",
      levels = { "200", "300", "400", "500", "650", "800" }, risky = true, safe = "400", page = "adv-detail" },
    { cvar = "wmoLodDist", name = "Building detail distance", line = "How far away buildings keep their full detail.",
      levels = { "150", "300", "400", "500", "650" }, risky = true, safe = "300", page = "adv-detail" },
    { cvar = "entityLodDist", name = "Character detail distance", line = "How far away characters keep their full detail.",
      levels = { "5", "10", "15", "20", "25" }, risky = true, safe = "10", page = "adv-detail" },
    { cvar = "lodObjectCullSize", name = "Small object cutoff", line = "Objects smaller than this vanish in the distance; lower draws more.",
      levels = { "5", "10", "15", "20", "25" }, risky = true, safe = "15", page = "adv-detail" },
    { cvar = "lodObjectMinSize", name = "Smallest object drawn", line = "Objects smaller than this are never drawn; lower draws more.",
      levels = { "0", "10", "20", "30" }, risky = true, safe = "20", page = "adv-detail" },
    -- Shadows
    { cvar = "shadowTextureSize", name = "Shadow map size", line = "How sharp shadow edges can be. Higher uses more graphics memory.",
      levels = { "1024", "2048", "4096" }, risky = true, safe = "1024", page = "adv-shadows" },
    { cvar = "shadowNumCascades", name = "Shadow layers", line = "How many layers of shadow detail cover the distance.",
      levels = { "1", "2", "3", "4" }, risky = true, safe = "1", page = "adv-shadows" },
    { cvar = "shadowSoft", name = "Soft shadow edges", line = "Softens the edges of shadows.", levels = { "0", "1" },
      levelWords = OFF_ON, risky = true, safe = "0", page = "adv-shadows" },
    { cvar = "shadowBlendCascades", name = "Blended shadow layers", line = "Smooths the seams between shadow layers.",
      levels = { "0", "1" }, levelWords = OFF_ON, risky = true, safe = "0", page = "adv-shadows" },
}

-- The Advanced pages, in the order the page list shows them.
advanced.PAGES = {
    { key = "adv-effects", text = "Advanced: effects" },
    { key = "adv-distance", text = "Advanced: distance" },
    { key = "adv-detail", text = "Advanced: detail" },
    { key = "adv-shadows", text = "Advanced: shadows" },
}

local BY_CVAR = {}
for _, entry in ipairs(advanced.CATALOG) do BY_CVAR[entry.cvar:lower()] = entry end

-- The entry of a setting named in any case (the game answers names without regard to case), or nil.
function advanced.entry(cvar)
    return type(cvar) == "string" and BY_CVAR[cvar:lower()] or nil
end

function advanced.isAdvanced(cvar)
    return advanced.entry(cvar) ~= nil
end

-- The entries whose setting this client has, in catalogue order.
function advanced.available()
    local list = {}
    for _, entry in ipairs(advanced.CATALOG) do
        if GetCVar(entry.cvar) ~= nil then list[#list + 1] = entry end
    end
    return list
end

-- The risky entries this client has.
function advanced.risky()
    local list = {}
    for _, entry in ipairs(advanced.available()) do
        if entry.risky then list[#list + 1] = entry end
    end
    return list
end

-- A level as a player reads it: its word where the entry has one, else the number.
function advanced.levelText(entry, value)
    return entry.levelWords and entry.levelWords[value] or value
end
