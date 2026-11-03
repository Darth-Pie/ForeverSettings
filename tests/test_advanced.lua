-- Tests for Advanced.lua and the Advanced settings (spec 2026-11-03-advanced-page-title-switch-and-menu-design.md A2-A6), driven
-- through the shared harness.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

-- A client with every catalogue setting at its default (the retail probe's defaults), plus what `extra` adds.
local DEFAULTS = {
    ffxGlow = "1", ffxDeath = "1", WeatherDensity = "2", sunshafts = "0", volumeFogLevel = "2", reflectionMode = "3", refraction = "0",
    ResampleSharpness = "0.2", groundEffectDist = "70", farclip = "1000", horizonStart = "800", horizonClip = "1600",
    terrainLodDist = "400", wmoLodDist = "300", entityLodDist = "10", lodObjectCullSize = "15", lodObjectMinSize = "20",
    shadowTextureSize = "1024", shadowNumCascades = "1", shadowSoft = "0", shadowBlendCascades = "0",
}
local function cvarsWith(extra)
    local cv = { graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64", RenderScale = "1", vsync = "0" }
    for k, v in pairs(DEFAULTS) do cv[k] = v end
    for k, v in pairs(extra or {}) do cv[k] = v end
    return cv
end
local function boot(cvars, opts)
    opts = opts or {}
    opts.fresh = true
    local e = H.boot(cvars or cvarsWith(), opts)
    return e, e.ns.advanced
end
local function outText() return table.concat(OUT, " | ") end

-- The catalogue, as the ledger records it: console name, page, risky, safe value.
local WANT = {
    { "ffxGlow", "adv-effects" }, { "ffxDeath", "adv-effects" }, { "WeatherDensity", "adv-effects" }, { "sunshafts", "adv-effects" },
    { "volumeFogLevel", "adv-effects" }, { "reflectionMode", "adv-effects" }, { "refraction", "adv-effects" },
    { "ResampleSharpness", "adv-effects" }, { "groundEffectDist", "adv-distance" },
    { "farclip", "adv-distance", "1000" }, { "horizonStart", "adv-distance", "800" }, { "horizonClip", "adv-distance", "1600" },
    { "terrainLodDist", "adv-distance", "400" }, { "wmoLodDist", "adv-distance", "300" }, { "entityLodDist", "adv-distance", "10" },
    { "lodObjectCullSize", "adv-distance", "15" }, { "lodObjectMinSize", "adv-distance", "20" },
    { "shadowTextureSize", "adv-shadows", "1024" }, { "shadowNumCascades", "adv-shadows", "1" }, { "shadowSoft", "adv-shadows", "0" },
    { "shadowBlendCascades", "adv-shadows", "0" },
}

test("AV-1 the catalogue is the ledgered list, in page order, each with its page, and the risky ones with their safe value", function()
    local _, a = boot()
    local bad = {}
    if #a.CATALOG ~= #WANT then bad[#bad + 1] = "count " .. #a.CATALOG end
    for i, want in ipairs(WANT) do
        local entry = a.CATALOG[i] or {}
        if entry.cvar ~= want[1] or entry.page ~= want[2] or (entry.risky == true) ~= (want[3] ~= nil) or entry.safe ~= want[3] then
            bad[#bad + 1] = tostring(entry.cvar) .. "/" .. want[1]
        end
    end
    local pages = {}
    for _, page in ipairs(a.PAGES) do pages[#pages + 1] = page.key .. ":" .. page.text end
    return #bad == 0 and table.concat(pages, "|") == "adv-effects:Advanced: effects|adv-distance:Advanced: distance|adv-shadows:Advanced: shadows",
        table.concat(bad, ",")
end)

test("AV-2 every entry has a plain name with no console name in it, a line, two or more levels, and the client's default among them", function()
    local _, a = boot()
    local bad = {}
    for _, entry in ipairs(a.CATALOG) do
        local named = type(entry.name) == "string" and entry.name ~= "" and not entry.name:lower():find(entry.cvar:lower(), 1, true)
        local lined = type(entry.line) == "string" and #entry.line > 10
        local default = false
        for _, value in ipairs(entry.levels or {}) do
            if tonumber(value) == tonumber(DEFAULTS[entry.cvar]) then default = true end
        end
        if not (named and lined and #(entry.levels or {}) >= 2 and default) then bad[#bad + 1] = entry.cvar end
        for _, value in ipairs(entry.levels or {}) do
            if entry.levelWords and not entry.levelWords[value] then bad[#bad + 1] = entry.cvar .. ":" .. value .. " has no word" end
        end
    end
    return #bad == 0, table.concat(bad, ",")
end)

test("AV-3 every risky entry's safe value is one of its levels; no other entry has one", function()
    local _, a = boot()
    local bad = {}
    for _, entry in ipairs(a.CATALOG) do
        if entry.risky then
            local found = false
            for _, value in ipairs(entry.levels) do if value == entry.safe then found = true end end
            if not found then bad[#bad + 1] = entry.cvar end
        elseif entry.safe ~= nil then
            bad[#bad + 1] = entry.cvar .. " has a safe value but is not risky"
        end
    end
    return #bad == 0, table.concat(bad, ",")
end)

-- The Forever client has no list of its own settings: the snapshot of a test reads the built-in list, so every Advanced setting
-- must be on it and in the guarded set, or a test that moves one would not put it back.
test("AV-4 no entry is a setting the test measures or the profiles manage; every one is on the built-in list and in the guarded set", function()
    local e, a = boot()
    local measured = {}
    for _, row in ipairs(e.ns.bench.SETTINGS) do
        for _, cvar in ipairs(row.cvars) do measured[cvar:lower()] = true end
    end
    for _, cvar in ipairs(e.ns.profiles.MANAGED) do measured[cvar:lower()] = true end
    local known = {}
    for _, name in ipairs(e.ns.knownCVars) do known[name:lower()] = true end
    local bad = {}
    for _, entry in ipairs(a.CATALOG) do
        if measured[entry.cvar:lower()] then bad[#bad + 1] = entry.cvar .. " is measured" end
        if not e.ns.bench.restore.isGuarded(entry.cvar) then bad[#bad + 1] = entry.cvar .. " is not guarded" end
        if not known[entry.cvar:lower()] then bad[#bad + 1] = entry.cvar .. " is not on the built-in list" end
    end
    return #bad == 0, table.concat(bad, ",")
end)

test("AV-5 available() and risky() list only what the client has; the lookups ignore case", function()
    local cv = cvarsWith()
    cv.farclip, cv.ffxDeath = nil, nil
    local _, a = boot(cv)
    local names = {}
    for _, entry in ipairs(a.available()) do names[entry.cvar] = true end
    local risky = {}
    for _, entry in ipairs(a.risky()) do risky[#risky + 1] = entry.cvar end
    return #a.available() == #WANT - 2 and not names.farclip and not names.ffxDeath and names.ffxGlow
        and #risky == 11 and risky[1] == "horizonStart" and a.isAdvanced("FARCLIP") and a.isAdvanced("WeatherDensity")
        and not a.isAdvanced("graphicsShadowQuality") and a.entry("SunShafts").cvar == "sunshafts",
        #a.available() .. " " .. #risky
end)

test("AV-6 levelText gives the entry's word for a level, else the number", function()
    local _, a = boot()
    local glow, dist, sharp = a.entry("ffxGlow"), a.entry("groundEffectDist"), a.entry("ResampleSharpness")
    return a.levelText(glow, "0") == "Off" and a.levelText(glow, "1") == "On" and a.levelText(dist, "320") == "320"
        and a.levelText(sharp, "0.5") == "50%"
end)

return H.results()
