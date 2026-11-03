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
    { "terrainLodDist", "adv-detail", "400" }, { "wmoLodDist", "adv-detail", "300" }, { "entityLodDist", "adv-detail", "10" },
    { "lodObjectCullSize", "adv-detail", "15" }, { "lodObjectMinSize", "adv-detail", "20" },
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
    return #bad == 0 and table.concat(pages, "|") == "adv-effects:Advanced: effects|adv-distance:Advanced: distance|adv-detail:Advanced: detail|adv-shadows:Advanced: shadows",
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

-- Task 3: the profiles and the safety net (spec A4). A game on Everyday with every catalogue setting at its default.
local function game(extra)
    local e = H.boot(cvarsWith(extra), { fresh = true, defaults = false })
    e.slash("profile everyday")
    OUT, SETLOG = {}, {}
    return e, e.ns.profiles
end
local function logout(e)
    SETLOG = {}
    e.fire("PLAYER_LOGOUT")
end

-- Review Focus 1: every way a risky value can be kept ends with the safe value in the game at logout and the kept value back
-- after entering the world.
test("AV-SAFE-1 a risky value kept by /fset set or by the window's edit is put back to safe at logout and applied again after entering the world", function()
    local results = {}
    local paths = {
        set = function(e, p) e.slash("set farclip 10000") end,
        window = function(e, p) p.setProfileValue("everyday", "farclip", "10000", true) end,
        crowded = function(e, p) p.setProfileValue("crowded", "farclip", "10000", true) e.slash("profile crowded") end,
    }
    for name, keep in pairs(paths) do
        local e, p = game()
        keep(e, p)
        local applied = CVARS.farclip == "10000"
        logout(e)
        local safe = CVARS.farclip == "1000" and #SETLOG == 1 and SETLOG[1] == "farclip" and ForeverSettingsDB.want.farclip == "10000"
        e.fire("PLAYER_ENTERING_WORLD")
        local back = CVARS.farclip == "10000"
        if not (applied and safe and back) then results[#results + 1] = name .. ":" .. tostring(applied) .. tostring(safe) .. tostring(back) end
    end
    return #results == 0, table.concat(results, " ")
end)

test("AV-SAFE-2 Save as Everyday never keeps an Advanced value, so a risky value set outside the addon is the player's own and left alone at logout", function()
    local e, p = game()
    CVARS.farclip = "10000"                                -- the player's own console command
    p.save("everyday", true)
    local notKept = ForeverSettingsDB.profiles.everyday.values.farclip == nil and ForeverSettingsDB.want.farclip == nil
    logout(e)
    return notKept and CVARS.farclip == "10000" and #SETLOG == 0, tostring(CVARS.farclip) .. " " .. #SETLOG
end)

test("AV-SAFE-3 at logout a kept value equal to the safe one, or a game already at the safe value, is left alone; a non-risky value is never touched", function()
    local e = game()
    e.slash("set farclip 1000")
    e.slash("set horizonStart 4000")
    e.slash("set groundEffectDist 500")
    CVARS.horizonStart = "800"                             -- already safe in the game
    CVARS.farclip = "6000"                                 -- moved by the game's own menu after the addon applied 1000
    logout(e)
    return #SETLOG == 0 and CVARS.farclip == "6000" and CVARS.groundEffectDist == "500", table.concat(SETLOG, ",")
end)

test("AV-SAFE-4 a game that raises while a risky value is put back does not break the logout, and the others are still put back", function()
    local e = game()
    e.slash("set farclip 10000")
    e.slash("set shadowTextureSize 4096")
    SETFAIL.farclip = "error"
    local ok = pcall(logout, e)
    SETFAIL.farclip = nil
    return ok and CVARS.shadowTextureSize == "1024", tostring(ok) .. " " .. tostring(CVARS.shadowTextureSize)
end)

test("AV-SAFE-5 Shift held at the first loading screen skips every kept risky value for the session, says so once, and applies the rest", function()
    local e = game()
    e.slash("set farclip 10000")
    e.slash("set shadowTextureSize 4096")
    e.slash("set groundEffectDist 500")
    e.slash("set horizonStart 800")                        -- kept at its safe value: nothing to skip
    logout(e)
    local carried = {}                                     -- the next session: the same game and saved variables, a new addon
    for k, v in pairs(CVARS) do carried[k] = v end
    local e2 = H.boot(carried, { fresh = false, defaults = false })
    CVARS.farclip, CVARS.shadowTextureSize, CVARS.groundEffectDist, CVARS.horizonStart = "1000", "1024", "70", "1600"
    OUT = {}
    SHIFT = true
    e2.fire("PLAYER_ENTERING_WORLD")
    SHIFT = false
    local skipped = CVARS.farclip == "1000" and CVARS.shadowTextureSize == "1024" and CVARS.groundEffectDist == "500"
        and CVARS.horizonStart == "800"
    local said = 0
    for _, line in ipairs(OUT) do
        if line:find("Shift is held: the risky Advanced settings are not applied this session.", 1, true) then said = said + 1 end
    end
    OUT = {}
    e2.fire("PLAYER_ENTERING_WORLD")
    local quiet = CVARS.farclip == "1000" and #OUT == 0
    e2.slash("set farclip 8000")
    local manual = CVARS.farclip == "8000"
    return skipped and said == 1 and quiet and manual, tostring(skipped) .. " " .. said .. " " .. tostring(quiet) .. " " .. tostring(manual)
end)

-- The fresh review of 2026-11-03, finding 2: in a Shift session a click or a command that sets one setting applied every kept
-- risky value with it.
test("AV-SAFE-6 in a Shift session setting one setting applies that one only; the other risky values and Apply all now stay skipped", function()
    local e = game({ graphicsSSAO = "1" })
    e.slash("set farclip 10000")
    e.slash("set shadowTextureSize 4096")
    logout(e)
    local carried = {}
    for k, v in pairs(CVARS) do carried[k] = v end
    local e2 = H.boot(carried, { fresh = false, defaults = false })
    CVARS.farclip, CVARS.shadowTextureSize = "1000", "1024"
    SHIFT = true
    e2.fire("PLAYER_ENTERING_WORLD")
    SHIFT = false
    e2.slash("set graphicsSSAO 0")
    local other = CVARS.graphicsSSAO == "0" and CVARS.farclip == "1000" and CVARS.shadowTextureSize == "1024"
    e2.slash("apply")
    local apply = CVARS.farclip == "1000" and CVARS.shadowTextureSize == "1024"
    e2.slash("set farclip 8000")
    local asked = CVARS.farclip == "8000" and CVARS.shadowTextureSize == "1024"
    COMBAT = true
    e2.slash("set shadowTextureSize 2048")
    COMBAT = false
    e2.fire("PLAYER_REGEN_ENABLED")
    local waited = CVARS.shadowTextureSize == "2048"
    return other and apply and asked and waited, tostring(other) .. tostring(apply) .. tostring(asked) .. tostring(waited)
end)

test("AV-SAFE-6b in a Shift session setting another setting does not bring back a saved picture size above 100%", function()
    local e = game({ graphicsSSAO = "1", RenderScale = "1" })
    e.slash("set RenderScale 1.5")
    logout(e)
    local carried = {}
    for k, v in pairs(CVARS) do carried[k] = v end
    local e2 = H.boot(carried, { fresh = false, defaults = false })
    SHIFT = true
    e2.fire("PLAYER_ENTERING_WORLD")
    SHIFT = false
    e2.slash("set graphicsSSAO 0")
    return CVARS.graphicsSSAO == "0" and CVARS.RenderScale == "1", tostring(CVARS.RenderScale)
end)

-- The fresh review of 2026-11-03, finding 3: taking a risky value out of the profile left the addon's value in the game, and the
-- logout net no longer saw it.
test("AV-SAFE-7 unticking a kept risky value puts the player's own value back in the game, so nothing risky is left behind", function()
    local e, p = game({ farclip = "3000" })
    e.slash("set farclip 10000")
    e.slash("unset farclip")
    local own = CVARS.farclip == "3000" and ForeverSettingsDB.want.farclip == nil
    p.setProfileValue("everyday", "shadowTextureSize", "4096", true)
    p.unsetProfileValue("everyday", "shadowTextureSize", true)
    local safe = CVARS.shadowTextureSize == "1024"
    e.slash("set groundEffectDist 500")
    e.slash("unset groundEffectDist")
    return own and safe and CVARS.groundEffectDist == "500", tostring(CVARS.farclip) .. " " .. tostring(CVARS.shadowTextureSize)
end)

-- The fresh review of 2026-11-03, finding 4: on a client with no list of its own settings /fset set stored the built-in list's
-- spelling (sunShafts) beside the window's (sunshafts).
test("AV-SPELL-1 /fset set keeps an Advanced setting under the catalogue's spelling, whatever was typed, on a client with no list", function()
    local e = H.boot(cvarsWith(), { fresh = true, defaults = false, console = "none" })
    e.slash("profile everyday")
    e.slash("set SunShafts 2")
    e.slash("set weatherdensity 1")
    local values = ForeverSettingsDB.profiles.everyday.values
    local keys = {}
    for k in pairs(values) do keys[#keys + 1] = k end
    table.sort(keys)
    return table.concat(keys, ",") == "WeatherDensity,sunshafts" and ForeverSettingsDB.original.values.sunshafts == "0",
        table.concat(keys, ",") .. " " .. tostring(ForeverSettingsDB.original.values.sunshafts)
end)

-- Review Focus 3: the first change of an Advanced setting is recorded in Original first.
test("AV-ORIG-1 the first keep of an Advanced setting records the player's own value in Original, on the profile in use and on the other, and Original puts it back", function()
    local e, p = game({ farclip = "3000", sunshafts = "2" })
    e.slash("set farclip 10000")
    p.setProfileValue("crowded", "sunshafts", "0", true)
    local recorded = ForeverSettingsDB.original.values.farclip == "3000" and ForeverSettingsDB.original.values.sunshafts == "2"
    e.slash("profile crowded")
    local crowded = CVARS.sunshafts == "0" and CVARS.farclip == "3000"     -- Crowded keeps no farclip: Original's comes back
    e.slash("profile everyday")
    e.slash("profile original")
    return recorded and crowded and CVARS.farclip == "3000" and CVARS.sunshafts == "2",
        tostring(ForeverSettingsDB.original.values.farclip) .. " " .. tostring(ForeverSettingsDB.original.values.sunshafts)
            .. " " .. tostring(CVARS.farclip) .. " " .. tostring(CVARS.sunshafts)
end)

-- Review Focus 2: Maximum and the test never hold an Advanced setting.
test("AV-MAX-1 Maximum's enforced list and the test's list hold no Advanced setting, whatever Everyday keeps", function()
    local e, p = game()
    e.ns.bench.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    e.slash("set farclip 10000")
    e.slash("set sunshafts 2")
    local plan = p.plan("maximum")
    local bad = {}
    for cvar in pairs(plan.want) do if e.ns.advanced.isAdvanced(cvar) then bad[#bad + 1] = "want:" .. cvar end end
    for cvar in pairs(p.maxValues()) do if e.ns.advanced.isAdvanced(cvar) then bad[#bad + 1] = "max:" .. cvar end end
    for _, entry in ipairs(e.ns.bench.resolve()) do if e.ns.advanced.isAdvanced(entry.cvar) then bad[#bad + 1] = "test:" .. entry.cvar end end
    return #bad == 0 and plan.want.graphicsShadowQuality == "4", table.concat(bad, ",")
end)

return H.results()
