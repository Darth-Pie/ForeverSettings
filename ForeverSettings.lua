-- ForeverSettings: keeps chosen CVars at the values you want.
-- It re-applies them at every loading screen, so a menu change, a switch to the
-- raid/battleground graphics set, or a reset at load does not undo them.
--
--   /fset                      show the list
--   /fset set <cvar> <value>   add or change an entry (applied now and at every loading screen)
--   /fset unset <cvar>         stop forcing it; the current value stays as it is
--   /fset apply                apply the list now
--   /fset reset                put back every CVar this addon changed, then empty the list
--   /fset dump <text>          list CVars whose name contains <text>, with current and default values

local _, ns = ...

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or _G.SetCVar
local GetCVarDefault = C_CVar and C_CVar.GetCVarDefault or _G.GetCVarDefault

-- Seeded into the saved list the first time the addon runs. After that the
-- saved list is the only source: change it with /fset, not by editing this.
local DEFAULTS = {
    -- Nothing is forced on a first install: every setting is the player's to choose (My settings, or /fset set).
}

local PREFIX = "|cff66ccffForeverSettings|r: "
local MAX_DUMP = 40

local db
local pending = false
local recovered = false
local warned = {}

local function say(msg)
    print(PREFIX .. msg)
end

-- Shared with the other files of this addon (Bench.lua, UI.lua).
ns.say = say
ns.db = function() return db end
ns.suspended = false

-- The graphics CVars this addon knows by name: every name in the Config.wtf of both Blizzard clients that the
-- benchmark's guarded set (Bench.lua) would cover, plus the master presets and the frame-rate caps. The client's
-- own list of commands is not always there (the Forever client has no C_Console.GetAllCommands), so this list is
-- what the snapshot and /fset dump fall back on. Names only; whether one exists is asked of GetCVar.
local KNOWN_CVARS = {
    "CombatLogPeriodicSpells", "doodadLodScale", "entityShadowFadeScale", "farclip",
    "fctSpellMechanics", "floatingCombatTextCombatLogPeriodicSpells", "floatingCombatTextPetSpellDamage", "floatingCombatTextSpellMechanics",
    "giQuality", "graphicsBloomUserMult", "graphicsComputeEffects", "graphicsDepthEffects",
    "graphicsEnvironmentDetail", "graphicsGroundClutter", "graphicsLightMode", "graphicsLiquidDetail",
    "graphicsOutlineMode", "graphicsParticleDensity", "graphicsPBRLiquidDetail", "graphicsProjectedTextures",
    "graphicsQuality", "graphicsShadowQuality", "graphicsSpellDensity", "graphicsSSAO",
    "graphicsTextureResolution", "graphicsViewDistance", "groundEffectDensity", "groundEffectDist",
    "guildRosterView", "horizonClip", "horizonStart", "lodObjectCullSize",
    "lodObjectFadeScale", "lodObjectMinSize", "maxFPS", "maxFPSBk",
    "NamePlateHorizontalScale", "OutlineEngineMode", "particleDensity", "pbrLiquidDetail",
    "PetSpellDamage", "projectedTextures", "RAIDentityShadowFadeScale", "RAIDfarclip",
    "RAIDgiQuality", "raidGraphicsBloomUserMult", "raidGraphicsComputeEffects", "raidGraphicsDepthEffects",
    "raidGraphicsEnvironmentDetail", "raidGraphicsGroundClutter", "raidGraphicsLightMode", "raidGraphicsLiquidDetail",
    "raidGraphicsOutlineMode", "raidGraphicsParticleDensity", "raidGraphicsPBRLiquidDetail", "raidGraphicsProjectedTextures",
    "RAIDgraphicsQuality", "raidGraphicsShadowQuality", "raidGraphicsSpellDensity", "raidGraphicsSSAO",
    "raidGraphicsTextureResolution", "raidGraphicsViewDistance", "RAIDgroundEffectDensity", "RAIDgroundEffectDist",
    "RAIDhorizonClip", "RAIDhorizonStart", "RAIDlodObjectCullSize", "RAIDlodObjectMinSize",
    "RAIDOutlineEngineMode", "RAIDparticleDensity", "RAIDpbrLiquidDetail", "RAIDprojectedTextures",
    "RAIDreflectionMode", "RAIDrefraction", "RAIDrippleDetail", "RAIDshadowBlendCascades",
    "RAIDshadowMode", "RAIDshadowNumCascades", "RAIDshadowSoft", "RAIDshadowTextureSize",
    "RAIDSSAO", "RAIDsunShafts", "RAIDterrainLodDist", "RAIDTerrainLodDiv",
    "RAIDWaterDetail", "RAIDweatherDensity", "RAIDwmoLodDist", "reflectionMode",
    "refraction", "RenderScale", "rippleDetail", "shadowBlendCascades",
    "shadowMode", "shadowNumCascades", "shadowSoft", "shadowTextureSize",
    "spellClutter", "spellVisualDensityFilterSetting", "SSAO", "sunShafts",
    "targetFPS", "terrainLodDist", "TerrainLodDiv", "useMaxFPS",
    "vsync", "waterDetail", "weatherDensity", "wmoLodDist",
}
ns.knownCVars = KNOWN_CVARS

local function consoleEntryName(entry)
    if type(entry) == "string" then return entry end
    if type(entry) == "table" then
        local name = entry.command or entry.name
        if type(name) == "string" then return name end
    end
    return nil
end

-- The names the client lists as console commands, or nil when it has no usable list: C_Console.GetAllCommands, else
-- the older global ConsoleGetAllCommands. A function that errors, or answers with something unusable, counts as none.
local function clientNames()
    local sources = {}
    if type(C_Console) == "table" and type(C_Console.GetAllCommands) == "function" then
        sources[#sources + 1] = C_Console.GetAllCommands
    end
    if type(ConsoleGetAllCommands) == "function" then sources[#sources + 1] = ConsoleGetAllCommands end
    for _, fn in ipairs(sources) do
        local ok, all = pcall(fn)
        if ok and type(all) == "table" then
            local names = {}
            for _, entry in ipairs(all) do
                local name = consoleEntryName(entry)
                if name then names[#names + 1] = name end
            end
            if #names > 0 then return names end
        end
    end
    return nil
end

-- Every CVar name to look at: the client's list when it has one, plus the built-in list (so a partial client list
-- cannot hide a setting). A name in both, in any case, appears once, spelt as the client has it. Not every name is a
-- CVar in this client: ask GetCVar. The second value is "client" or "built-in", for messages.
function ns.cvarNames()
    local client = clientNames()
    local seen, names = {}, {}
    for _, list in ipairs({ client or {}, KNOWN_CVARS }) do
        for _, name in ipairs(list) do
            local key = name:lower()
            if not seen[key] then
                seen[key] = true
                names[#names + 1] = name
            end
        end
    end
    return names, client and "client" or "built-in"
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function same(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and y ~= nil and x == y
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- The enforced list in the benchmark's write order (master presets, menu-level, then raw): a menu-level write can
-- rewrite a raw setting, so the raw one has to come after it. Alphabetical when the benchmark is not loaded.
local function orderedKeys(t)
    local keys = sortedKeys(t)
    if ns.bench and ns.bench.restore and ns.bench.restore.order then return ns.bench.restore.order(keys) end
    return keys
end

-- manual: the user asked for it, so say something even when nothing changed. silent: say nothing at all (the My settings
-- window shows the result in its rows).
local function applyAll(manual, silent)
    local say = silent and function() end or say
    if ns.suspended then
        if manual then say("benchmark running; try again afterwards") end
        return
    end
    if InCombatLockdown() then
        pending = true
        if manual then say("in combat; will apply when combat ends") end
        return
    end
    pending = false
    local changed = 0
    for _, name in ipairs(orderedKeys(db.want)) do
        local value = db.want[name]
        local current = GetCVar(name)
        if current == nil then
            if not warned[name] then
                warned[name] = true
                say("unknown CVar '" .. name .. "', skipped (find the right name with /fset dump <part of it>)")
            end
        elseif not same(current, value) then
            local ok, result = pcall(SetCVar, name, value)
            local after = GetCVar(name)
            if ok and result ~= false and same(after, value) then
                changed = changed + 1
                say(name .. " " .. tostring(current) .. " -> " .. value)
            elseif ok and result ~= false then
                say("game kept " .. name .. " at " .. tostring(after) .. " (wanted " .. value .. ")")
            else
                say("could not set " .. name .. " to " .. value)
            end
        end
    end
    if changed == 0 and manual then say("everything already matches") end
end

ns.applyAll = applyAll

local function showList()
    local keys = sortedKeys(db.want)
    if #keys == 0 then
        say("the list is empty; add one with /fset set <cvar> <value>")
    end
    for _, name in ipairs(keys) do
        local current = GetCVar(name)
        local flag = (current ~= nil and same(current, db.want[name])) and "" or "  <- differs"
        say(name .. ": want " .. db.want[name] .. ", now " .. tostring(current) .. flag)
    end
    say("commands: set, unset, apply, reset, dump <text>, profile, bench, minimap")
end

local function dump(needle)
    if needle == "" then say("usage: /fset dump <part of a CVar name>") return end
    local all, source = ns.cvarNames()
    if source == "built-in" then
        say("this client has no list of its CVars; searching the built-in list of graphics settings")
    end
    needle = needle:lower()
    local names = {}
    for _, n in ipairs(all) do
        if n:lower():find(needle, 1, true) and GetCVar(n) ~= nil then names[#names + 1] = n end
    end
    table.sort(names)
    for i = 1, math.min(#names, MAX_DUMP) do
        local n = names[i]
        local default = GetCVarDefault and GetCVarDefault(n)
        say(n .. " = " .. tostring(GetCVar(n)) .. " (default " .. tostring(default) .. ")")
    end
    if #names > MAX_DUMP then say((#names - MAX_DUMP) .. " more; use a longer filter") end
    if #names == 0 then say("nothing matches '" .. needle .. "'") end
end

local function handleSlash(msg)
    local cmd, rest = trim(msg or ""):match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()
    -- While a benchmark runs it owns the settings. set, unset and reset (through Profiles.lua) and apply (applyAll)
    -- each refuse on their own, so no guard is needed here.
    if cmd == "set" then
        local name, value = rest:match("^(%S+)%s+(.+)$")
        if not name then say("usage: /fset set <cvar> <value>") return end
        if GetCVar(name) == nil then say("unknown CVar '" .. name .. "'") return end
        warned[name] = nil
        if not ns.profiles then say("profiles module not loaded") return end
        ns.profiles.setValue(name, trim(value))
    elseif cmd == "unset" then
        if not ns.profiles then say("profiles module not loaded") return end
        ns.profiles.unsetValue(rest)
    elseif cmd == "apply" then
        applyAll(true)
    elseif cmd == "reset" then
        if not ns.profiles then say("profiles module not loaded") return end
        ns.profiles.switch("original")
    elseif cmd == "dump" then
        dump(rest)
    elseif cmd == "bench" then
        if ns.bench and ns.bench.handle then
            ns.bench.handle(rest)
        else
            say("bench module not loaded")
        end
    elseif cmd == "setup" then
        if ns.guide and ns.guide.open then
            ns.guide.open("setup")
        else
            say("guide module not loaded")
        end
    elseif cmd == "crowd" then
        if ns.guide and ns.guide.open then
            ns.guide.open("crowd")
        else
            say("guide module not loaded")
        end
    elseif cmd == "settings" then
        if ns.settings and ns.settings.open then
            ns.settings.open()
        else
            say("settings module not loaded")
        end
    elseif cmd == "profile" then
        if ns.profiles and ns.profiles.handle then
            ns.profiles.handle(rest)
        else
            say("profiles module not loaded")
        end
    elseif cmd == "minimap" then
        if ns.ui and ns.ui.toggleButton then
            ns.ui.toggleButton()
        else
            say("ui module not loaded")
        end
    else
        showList()
    end
end

-- The /fset handler. A menu calls this too, so both reach the same code.
function ns.command(msg)
    if db then handleSlash(msg) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "ForeverSettings" then return end
        ForeverSettingsDB = ForeverSettingsDB or {}
        db = ForeverSettingsDB
        if db.want == nil then
            db.want = {}
            for k, v in pairs(DEFAULTS) do db.want[k] = v end
        end
        if ns.profiles then
            local ok, err = pcall(ns.profiles.migrate)
            if not ok then say("profiles could not start: " .. tostring(err)) end
        end
    elseif not db then
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not recovered then
            recovered = true
            if ns.bench and ns.bench.recover then
                local ok, err = pcall(ns.bench.recover)
                if not ok then say("benchmark recovery failed: " .. tostring(err)) end
            end
        end
        if ns.profiles and ns.profiles.refresh then
            local ok, err = pcall(ns.profiles.refresh)
            if not ok then say("profiles could not refresh: " .. tostring(err)) end
        end
        applyAll(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then applyAll(false) end
    end
end)

SLASH_FOREVERSETTINGS1 = "/fset"
SlashCmdList["FOREVERSETTINGS"] = ns.command
