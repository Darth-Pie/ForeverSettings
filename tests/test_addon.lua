-- Drives ForeverSettings.lua through its real event and slash-command wiring
-- against stubbed WoW functions (see harness.lua).
local H = assert(load(HARNESS_SRC, "=harness"))()
local check, boot = H.check, H.boot

local function out() return table.concat(OUT, " | ") end

local function count(sub)
    local n = 0
    for _, l in ipairs(OUT) do
        if l:find(sub, 1, true) then n = n + 1 end
    end
    return n
end

-- T1-T6: the loading-screen behaviour
local e = boot({ groundEffectDensity = "48", graphicsSSAO = "3" }, { fresh = true })
e.fire("PLAYER_ENTERING_WORLD")
check("T1 default value applied at the loading screen", CVARS.groundEffectDensity == "64", CVARS.groundEffectDensity)
check("T1 original value recorded", ForeverSettingsDB.original.values.groundEffectDensity == "48", tostring(ForeverSettingsDB.original.values.groundEffectDensity))
check("T1 change announced once", #OUT == 1 and OUT[1]:find("48 -> 64", 1, true) ~= nil, out())

OUT = {}
e.fire("PLAYER_ENTERING_WORLD")
check("T2 second loading screen is silent and changes nothing", #OUT == 0 and CVARS.groundEffectDensity == "64", out())

CVARS.groundEffectDensity = "32"
e.fire("PLAYER_ENTERING_WORLD")
check("T3 a changed value is put back", CVARS.groundEffectDensity == "64", CVARS.groundEffectDensity)
check("T3 the original is not overwritten by later values", ForeverSettingsDB.original.values.groundEffectDensity == "48", tostring(ForeverSettingsDB.original.values.groundEffectDensity))

OUT = {}
CVARS.groundEffectDensity = "64.000000"
e.fire("PLAYER_ENTERING_WORLD")
check("T4 64.000000 counts as 64, nothing is touched", CVARS.groundEffectDensity == "64.000000" and #OUT == 0, out())

CVARS.groundEffectDensity = "48"
COMBAT = true
OUT = {}
e.fire("PLAYER_ENTERING_WORLD")
check("T5 nothing is set in combat, and it stays quiet", CVARS.groundEffectDensity == "48" and #OUT == 0, CVARS.groundEffectDensity .. " / " .. out())
COMBAT = false
e.fire("PLAYER_REGEN_ENABLED")
check("T5 applied when combat ends", CVARS.groundEffectDensity == "64", CVARS.groundEffectDensity)

CVARS.groundEffectDensity = "48"
e.fire("PLAYER_REGEN_ENABLED")
check("T6 leaving combat with nothing pending does not fight a manual change", CVARS.groundEffectDensity == "48", CVARS.groundEffectDensity)

-- T7-T9: /fset set
CVARS.groundEffectDensity = "64"
OUT = {}
e.slash("set graphicsSSAO 2")
check("T7 /fset set applies the value", CVARS.graphicsSSAO == "2", CVARS.graphicsSSAO)
check("T7 /fset set saves it in the list", ForeverSettingsDB.want.graphicsSSAO == "2", tostring(ForeverSettingsDB.want.graphicsSSAO))
check("T7 /fset set records the earlier value", ForeverSettingsDB.original.values.graphicsSSAO == "3", tostring(ForeverSettingsDB.original.values.graphicsSSAO))

OUT = {}
e.slash("set nosuch 1")
check("T8 an unknown CVar is refused and not saved", ForeverSettingsDB.want.nosuch == nil and count("unknown CVar 'nosuch'") == 1, out())

OUT = {}
e.slash("set graphicsSSAO")
check("T9 a missing value shows usage and changes nothing", ForeverSettingsDB.want.graphicsSSAO == "2" and count("usage: /fset set") == 1, out())

-- T10-T12: trouble while applying
ForeverSettingsDB.want.ghost = "1"
OUT = {}
e.fire("PLAYER_ENTERING_WORLD")
e.fire("PLAYER_ENTERING_WORLD")
check("T10 an unknown CVar in the list is reported once, not every loading screen", count("unknown CVar 'ghost'") == 1, out())
ForeverSettingsDB.want.ghost = nil

SETFAIL.groundEffectDensity = "error"
CVARS.groundEffectDensity = "48"
OUT = {}
local ok = pcall(e.fire, "PLAYER_ENTERING_WORLD")
check("T11 SetCVar raising an error does not escape", ok, "error escaped")
check("T11 and it is reported", count("could not set groundEffectDensity") == 1, out())

SETFAIL.groundEffectDensity = "clamp"
OUT = {}
e.fire("PLAYER_ENTERING_WORLD")
check("T12 a value the game refuses to keep is reported as kept at the old value", count("game kept groundEffectDensity at 48") == 1, out())
SETFAIL = {}
CVARS.groundEffectDensity = "64"

-- T13-T16: unset, reset, relogin
e.slash("unset graphicsSSAO")
check("T13 /fset unset removes it from the list", ForeverSettingsDB.want.graphicsSSAO == nil, tostring(ForeverSettingsDB.want.graphicsSSAO))
check("T13 and leaves the current value alone", CVARS.graphicsSSAO == "2", CVARS.graphicsSSAO)
check("T13 and keeps the earlier value for reset", ForeverSettingsDB.original.values.graphicsSSAO == "3", tostring(ForeverSettingsDB.original.values.graphicsSSAO))

e.slash("reset")
check("T14 /fset reset puts back groundEffectDensity", CVARS.groundEffectDensity == "48", CVARS.groundEffectDensity)
check("T14 /fset reset puts back graphicsSSAO", CVARS.graphicsSSAO == "3", CVARS.graphicsSSAO)
check("T14 /fset reset empties the list and returns to Original", next(ForeverSettingsDB.want) == nil and ForeverSettingsDB.orig == nil and ForeverSettingsDB.active == "original", "list not empty or not on Original")

local e2 = boot({ groundEffectDensity = "48", graphicsSSAO = "3" })
e2.fire("PLAYER_ENTERING_WORLD")
check("T15 after a reset the next login does not bring the default back", CVARS.groundEffectDensity == "48" and next(ForeverSettingsDB.want) == nil, CVARS.groundEffectDensity)

e2.slash("profile everyday")                  -- Original is read-only: /fset set needs a profile (Task 6 ruling)
e2.slash("set graphicsSSAO 2")
COMBAT = true
OUT = {}
e2.slash("reset")
check("T16 /fset reset refuses in combat and changes nothing", CVARS.graphicsSSAO == "2" and ForeverSettingsDB.want.graphicsSSAO == "2" and count("in combat") == 1, out())
COMBAT = false

-- T17-T18: dump and status
local e3 = boot({ groundEffectDensity = "48", graphicsSSAO = "3", groundEffectDist = "200" }, { fresh = true })
EXTRACMDS[1] = "notacvar"
OUT = {}
e3.slash("dump ground")
check("T17 dump lists the matching CVars with defaults", count("groundEffectDensity = 48 (default DgroundEffectDensity)") == 1 and count("groundEffectDist = 200") == 1, out())
check("T17 dump leaves out non-matching and non-CVar names", count("graphicsSSAO") == 0 and count("notacvar") == 0, out())
OUT = {}
e3.slash("dump")
check("T17 dump without text shows usage", count("usage: /fset dump") == 1, out())
OUT = {}
e3.slash("dump zzz")
check("T17 dump with no match says so", count("nothing matches 'zzz'") == 1, out())

-- T17b: a client with no console list. dump searches the built-in names and says so; with the client's list it says nothing.
OUT = {}
e3.slash("dump ground")
check("T17b dump says nothing about a built-in list when the client has its own", count("built-in") == 0, out())
local e3b = boot({ groundEffectDensity = "48", graphicsSSAO = "3", groundEffectDist = "200", accountName = "x" }, { fresh = true, console = "none" })
OUT = {}
e3b.slash("dump ground")
check("T17b dump finds the built-in names that exist", count("groundEffectDensity = 48 (default DgroundEffectDensity)") == 1 and count("groundEffectDist = 200") == 1 and count("graphicsSSAO") == 0, out())
check("T17b dump says it used the built-in list", count("built-in") == 1, out())
OUT = {}
e3b.slash("dump zzz")
check("T17b dump with no match still says so and names the list", count("nothing matches 'zzz'") == 1 and count("built-in") == 1, out())
local e3c = boot({ graphicsFoo = "1", groundEffectDensity = "48" }, { fresh = true, console = "legacy" })
OUT = {}
e3c.slash("dump graphicsFoo")
check("T17b dump uses the older global console function", count("graphicsFoo = 1") == 1 and count("built-in") == 0, out())

OUT = {}
e3.slash("")
check("T18 status shows a differing entry", count("groundEffectDensity: want 64, now 48  <- differs") == 1, out())

-- T19-T20: loading order and API namespace
local e4 = boot({ groundEffectDensity = "48" }, { fresh = true, noload = true })
local ok4 = pcall(e4.fire, "PLAYER_ENTERING_WORLD")
check("T19 an event before the addon's own ADDON_LOADED is ignored without error", ok4 and CVARS.groundEffectDensity == "48", "error or changed")
e4.fire("ADDON_LOADED", "SomeOtherAddon")
check("T19 another addon's ADDON_LOADED is ignored", _G.ForeverSettingsDB == nil, "db was created")

local e5 = boot({ groundEffectDensity = "48" }, { fresh = true, useC = true })
e5.fire("PLAYER_ENTERING_WORLD")
check("T20 uses C_CVar when it exists", CVARS.groundEffectDensity == "64" and count("could not set") == 0, out())
e5.slash("dump ground")
check("T20 falls back to the global GetCVarDefault when C_CVar lacks it", count("(default DgroundEffectDensity)") == 1, out())

-- T21 isolation pair: the second boot sees none of the first one's state, namespace or timers
local staleFired = false
local a = boot({ x = "1" }, { fresh = true })
a.ns.marker = 1
ForeverSettingsDB.leak = true
C_Timer.After(1, function() staleFired = true end)
local b = boot({ x = "1" }, { fresh = true })
b.advance(2)
check("T21 a fresh boot has no saved variables from the last", ForeverSettingsDB.leak == nil, tostring(ForeverSettingsDB.leak))
check("T21 a fresh boot has a new namespace", b.ns.marker == nil, tostring(b.ns.marker))
check("T21 a timer from the last boot does not fire in this one", staleFired == false, "stale timer fired")

-- T22 ns.db() is nil before ADDON_LOADED and the saved table after; ns.say prints with the prefix; ns.command acts as /fset
local e6 = boot({ graphicsSSAO = "3" }, { fresh = true, noload = true })
local okBefore, dbBefore = pcall(function() return e6.ns.db() end)
check("T22 ns.db() is nil before the addon's own ADDON_LOADED", okBefore and dbBefore == nil, tostring(okBefore) .. " / " .. tostring(dbBefore))
e6.fire("ADDON_LOADED", "ForeverSettings")
local okAfter, dbAfter = pcall(function() return e6.ns.db() end)
check("T22 ns.db() is the saved table after it", okAfter and dbAfter ~= nil and dbAfter == ForeverSettingsDB, tostring(okAfter) .. " / " .. tostring(dbAfter))
OUT = {}
local okSay = pcall(function() e6.ns.say("hello") end)
check("T22 ns.say prints with the prefix", okSay and #OUT == 1 and OUT[1]:find("ForeverSettings", 1, true) ~= nil and OUT[1]:find("hello", 1, true) ~= nil, out())
local okCmd = pcall(function()
    e6.ns.command("profile everyday")             -- a first install is on Original, which only a profile can be set on
    e6.ns.command("set graphicsSSAO 2")
end)
check("T22 ns.command acts exactly as /fset", okCmd and CVARS.graphicsSSAO == "2" and ForeverSettingsDB.want.graphicsSSAO == "2", tostring(okCmd) .. " / " .. tostring(CVARS.graphicsSSAO))

-- T23 suspended: loading screens and /fset apply change nothing; releasing it restores both
local e7 = boot({ groundEffectDensity = "48" }, { fresh = true })
e7.ns.suspended = true
e7.fire("PLAYER_ENTERING_WORLD")
check("T23 a loading screen changes nothing while suspended", CVARS.groundEffectDensity == "48", CVARS.groundEffectDensity)
OUT = {}
e7.slash("apply")
check("T23 /fset apply says the benchmark is running and changes nothing", CVARS.groundEffectDensity == "48" and count("benchmark running") == 1, tostring(CVARS.groundEffectDensity) .. " / " .. out())
e7.ns.suspended = false
e7.slash("apply")
check("T23 /fset apply works again afterwards", CVARS.groundEffectDensity == "64", CVARS.groundEffectDensity)

-- T24 without the bench module the route says so (stays valid in Task 8 because this boot skips Bench.lua)
local e8 = boot({ graphicsSSAO = "3" }, { fresh = true, bench = false })
OUT = {}
e8.slash("bench check")
check("T24 /fset bench without the module says it is not loaded", count("bench module not loaded") == 1, out())

-- T25 a stub ns.bench: routing, and the one-time recover call before the enforcement apply
local e9 = boot({ groundEffectDensity = "48" }, { fresh = true, bench = false })
local got, recoverCalls, seenAtRecover = nil, 0, nil
e9.ns.bench = {
    handle = function(rest) got = rest end,
    recover = function() recoverCalls = recoverCalls + 1; seenAtRecover = CVARS.groundEffectDensity end,
}
e9.slash("bench check")
check("T25 /fset bench <rest> calls ns.bench.handle(rest)", got == "check", tostring(got))
e9.fire("PLAYER_ENTERING_WORLD")
check("T25 the first loading screen calls recover once", recoverCalls == 1, recoverCalls)
check("T25 recover runs before the enforcement apply", seenAtRecover == "48" and CVARS.groundEffectDensity == "64", tostring(seenAtRecover) .. " / " .. tostring(CVARS.groundEffectDensity))
e9.fire("PLAYER_ENTERING_WORLD")
check("T25 later loading screens do not call recover again", recoverCalls == 1, recoverCalls)

-- T26 a recover that throws does not stop the forced settings from applying
local e10 = boot({ groundEffectDensity = "48" }, { fresh = true, bench = false })
e10.ns.bench = { recover = function() error("boom") end }
OUT = {}
local ok26 = pcall(e10.fire, "PLAYER_ENTERING_WORLD")
check("T26 a failing recover does not escape the loading screen", ok26, "error escaped")
check("T26 the forced setting is still applied", CVARS.groundEffectDensity == "64", CVARS.groundEffectDensity)
check("T26 and the failure is reported", count("benchmark recovery failed") == 1, out())

-- T27-T29 while a benchmark has suspended enforcement, the commands that change the list are refused
local e11 = boot({ groundEffectDensity = "48", graphicsSSAO = "3" }, { fresh = true })
e11.fire("PLAYER_ENTERING_WORLD")                      -- forces 64 and records 48 as the original
e11.ns.suspended = true
OUT = {}
e11.slash("reset")
check("T27 /fset reset is refused while suspended and keeps the list and the originals",
    ForeverSettingsDB.want.groundEffectDensity == "64" and ForeverSettingsDB.original.values.groundEffectDensity == "48"
    and CVARS.groundEffectDensity == "64" and count("benchmark running") == 1, out())
OUT = {}
e11.slash("set graphicsSSAO 2")
check("T28 /fset set is refused while suspended and saves nothing",
    ForeverSettingsDB.want.graphicsSSAO == nil and CVARS.graphicsSSAO == "3" and count("benchmark running") == 1, out())
OUT = {}
e11.slash("unset groundEffectDensity")
check("T29 /fset unset is refused while suspended", ForeverSettingsDB.want.groundEffectDensity == "64" and count("benchmark running") == 1, out())
e11.ns.suspended = false
e11.slash("unset groundEffectDensity")
check("T29 and works again afterwards", ForeverSettingsDB.want.groundEffectDensity == nil, tostring(ForeverSettingsDB.want.groundEffectDensity))

-- Recommender, Task 8: /fset setup (plan 2026-10-29-recommender.md)
local e12 = boot({ graphicsSSAO = "3", RenderScale = "1" }, { fresh = true })
OUT = {}
e12.slash("setup")
check("T30 /fset setup opens the setup Intro and starts nothing",
    e12.ns.guide.state() ~= nil and e12.ns.guide.state().kind == "setup" and e12.ns.guide.state().view == "intro"
    and not e12.ns.bench.active() and #SETLOG == 0, out())
local e13 = boot({ graphicsSSAO = "3" }, { fresh = true, guide = false })
OUT = {}
e13.slash("setup")
check("T30 and without the guide module it says so", count("guide module not loaded") == 1, out())

-- Crowd test, Task 10: /fset crowd
local e14 = boot({ graphicsSSAO = "3", RenderScale = "1" }, { fresh = true })
OUT = {}
e14.slash("crowd")
check("T40 /fset crowd opens the crowd window and starts nothing",
    e14.ns.guide.state() ~= nil and e14.ns.guide.state().kind == "crowd" and e14.ns.guide.state().view == "intro"
    and not e14.ns.bench.active() and #SETLOG == 0, out())
local e15 = boot({ graphicsSSAO = "3" }, { fresh = true, guide = false })
OUT = {}
e15.slash("crowd")
check("T40 and without the guide module it says so", count("guide module not loaded") == 1, out())

-- Words and menu, Task 2: applyAll can be told to say nothing
local e16 = boot({ groundEffectDensity = "48", graphicsSSAO = "3" }, { fresh = true })
e16.ns.db().want = { groundEffectDensity = "64", noSuchCvar = "1" }
OUT = {}
e16.ns.applyAll(true, true)
check("T42 applyAll(true, true) says nothing, not for a change and not for an unknown CVar, yet applies it",
    #OUT == 0 and CVARS.groundEffectDensity == "64", out())
OUT = {}
e16.ns.applyAll(true, true)
check("T42 and nothing for 'everything already matches' either", #OUT == 0, out())
OUT = {}
e16.ns.applyAll(true)
check("T42 without the silent argument it still says so", count("everything already matches") == 1, out())

-- Words and menu, Task 3: /fset settings
local e17 = boot({ graphicsSSAO = "3", RenderScale = "1" }, { fresh = true })
OUT = {}
e17.slash("settings")
check("T43 /fset settings opens the My settings window",
    e17.ns.settings ~= nil and e17.ns.settings.frame() ~= nil and e17.ns.settings.frame():IsShown() and #SETLOG == 0, out())
local e18 = boot({ graphicsSSAO = "3" }, { fresh = true, settings = false })
OUT = {}
e18.slash("settings")
check("T43 and without the module it says so", count("settings module not loaded") == 1, out())

-- A real first install forces nothing: the grass density, like every setting, is the player's to choose.
local e19 = boot({ groundEffectDensity = "48", graphicsShadowQuality = "2", vsync = "0" }, { fresh = true, defaults = false })
e19.fire("PLAYER_ENTERING_WORLD")
local db19 = e19.ns.db()
local forced = next(db19.want) == nil and CVARS.groundEffectDensity == "48" and #SETLOG == 0
OUT = {}
e19.slash("set groundEffectDensity 64")
check("TD-1 a first install forces nothing: an empty list, nothing written, the player on Original, and /fset set is refused there",
    forced and CVARS.groundEffectDensity == "48" and #SETLOG == 0 and e19.ns.profiles.active() == "original"
        and count("Original is read-only") == 1, tostring(forced) .. " " .. tostring(CVARS.groundEffectDensity) .. " " .. out())

-- TP: /fset probe asks the client by name which console variables exist, changing nothing. The names are the ones the
-- macros of the r/wowforever "beyond Ultra" thread set (67 of them, copied here as the spec).
local MACRO_NAMES = {
    "overridefarclip", "farclip", "horizonfarclip", "horizonStart", "horizonClip", "terrainLodDist", "TerrainLodDiv", "wmoLodDist",
    "entityLodDist", "doodadLodDist", "doodadLodScale", "lodObjectCullDist", "lodObjectCullSize", "lodObjectMinSize",
    "lodObjectFadeScale", "M2UseLOD", "smallcull",
    "environmentDetail", "groundEffectDist", "groundEffectDensity", "groundEffectFade", "detailDoodadAlpha", "WeatherDensity",
    "SkyCloudLOD", "volumeFogLevel",
    "shadowMode", "shadowTextureSize", "shadowNumCascades", "shadowBlendCascades", "shadowSoft", "extshadowquality",
    "entityShadowFadeScale", "SSAO", "SSAODistance",
    "waterDetail", "pbrLiquidDetail", "reflectionMode", "rippleDetail", "refraction", "graphicsDepthEffects", "projectedTextures",
    "physicsLevel",
    "graphicsSpellDensity", "spellEffectLevel", "spellClutter", "spellVisualDensityFilterSetting", "particleDensity",
    "particleMTDensity", "showfootprints", "showfootprintparticles",
    "bodyQuota", "componentTextureLevel", "componentCompress", "componentEmissive", "componentSpecular", "componentTexCacheSize",
    "componentTexLoadLimit", "componentThread",
    "giQuality", "graphicsLightMode", "graphicsComputeEffects", "graphicsBloomUserMult", "sunshafts", "characterAmbient",
    "OutlineEngineMode", "M2UseThreads", "terrainMipLevel",
}
local PREFIX_LEN = #"|cff66ccffForeverSettings|r: "
local function tokens(lines)
    local list = {}
    for _, l in ipairs(lines) do
        for word in l:gmatch("[%w_]+") do list[#list + 1] = word end
    end
    return list
end
local function countWord(lines, name)
    local n = 0
    for _, word in ipairs(tokens(lines)) do
        if word:lower() == name:lower() then n = n + 1 end
    end
    return n
end
local function allWithin(lines, width)
    for _, l in ipairs(lines) do
        if #l - PREFIX_LEN > width then return false end
    end
    return true
end

local ep = boot({ groundEffectDensity = "48", groundEffectDist = "200", farclip = "1600", shadowMode = "2", accountName = "x" },
    { fresh = true, defaults = false })
local wantBefore = ForeverSettingsDB.want
OUT = {}
SETLOG = {}
ep.slash("probe")
local header = OUT[1] or ""
local foundWords, missingFirst = {}, nil
for i = 2, #OUT do
    if OUT[i]:find("not here:", 1, true) then missingFirst = i break end
    foundWords[#foundWords + 1] = OUT[i]
end
local missingLines = {}
if missingFirst then for i = missingFirst, #OUT do missingLines[#missingLines + 1] = OUT[i] end end
check("TP-1 probe says how many names it asked about and how many exist here", header:find("probe: asked about 67; here: 4, not here: 63.", 1, true) ~= nil, header)
check("TP-1 probe lists each existing CVar once with its value now and its default",
    countWord(foundWords, "groundEffectDensity") == 1 and countWord(foundWords, "farclip") == 1
        and table.concat(foundWords, "\n"):find("groundEffectDensity = 48 / DgroundEffectDensity", 1, true) ~= nil
        and table.concat(foundWords, "\n"):find("farclip = 1600 / Dfarclip", 1, true) ~= nil, out())
check("TP-1 probe lists the names this client does not have on their own lines, and not the ones it has",
    countWord(missingLines, "M2UseLOD") == 1 and countWord(missingLines, "farclip") == 0 and countWord(missingLines, "groundEffectDist") == 0, out())
check("TP-1 probe changes nothing: no CVar written, the saved list untouched", #SETLOG == 0 and ForeverSettingsDB.want == wantBefore and next(ForeverSettingsDB.want) == nil, #SETLOG)
local order = {}
for _, word in ipairs(tokens(foundWords)) do
    for _, name in ipairs({ "farclip", "groundEffectDensity", "groundEffectDist", "shadowMode" }) do
        if word == name then order[#order + 1] = name end
    end
end
check("TP-1 probe lists the existing names in alphabetical order", table.concat(order, ",") == "farclip,groundEffectDensity,groundEffectDist,shadowMode", table.concat(order, ","))
OUT = {}
ep.slash("")
check("TP-1 the command list names probe", count("probe") == 1, out())

local seen, dupes, listed = {}, {}, {}
for _, name in ipairs(ep.ns.probeCVars or {}) do
    if seen[name:lower()] then dupes[#dupes + 1] = name end
    seen[name:lower()] = true
    listed[#listed + 1] = name
end
table.sort(listed)
local wanted = {}
for _, name in ipairs(MACRO_NAMES) do wanted[#wanted + 1] = name end
table.sort(wanted)
check("TP-2 the built-in names are exactly the thread's, each once whatever its case", #dupes == 0 and table.concat(listed, ",") == table.concat(wanted, ","),
    #listed .. " listed, " .. #dupes .. " repeated")

-- TP-3: every line stays short enough to read, whether most names exist or none do, and no name is lost or repeated
local everything = {}
for _, name in ipairs(MACRO_NAMES) do everything[name] = "1" end
local e_all = boot(everything, { fresh = true, defaults = false })
OUT = {}
e_all.slash("probe")
local allHere = allWithin(OUT, 200) and OUT[1]:find("here: 67, not here: 0.", 1, true) ~= nil
local onceEach = true
for _, name in ipairs(MACRO_NAMES) do
    if countWord(OUT, name) ~= 1 then onceEach = false end
end
local e_none = boot({ accountName = "x" }, { fresh = true, defaults = false })
OUT = {}
e_none.slash("probe")
local noneHere = allWithin(OUT, 200) and OUT[1]:find("here: 0, not here: 67.", 1, true) ~= nil
local onceEachMissing = true
for _, name in ipairs(MACRO_NAMES) do
    if countWord(OUT, name) ~= 1 then onceEachMissing = false end
end
check("TP-3 with every name present the lines are short and each name appears once", allHere and onceEach, #OUT)
check("TP-3 with none present the lines are short and each name appears once", noneHere and onceEachMissing, #OUT)

-- TP-4: names typed after the command are probed instead of the built-in list, in any case, each once
local ep2 = boot({ groundEffectDensity = "48", groundEffectDist = "200", farclip = "1600", shadowMode = "2", accountName = "x" },
    { fresh = true, defaults = false })
OUT = {}
ep2.slash("probe FARCLIP nonsenseName farclip")
check("TP-4 probe with names asks only about those, once each", OUT[1] and OUT[1]:find("asked about 2; here: 1, not here: 1.", 1, true) ~= nil
    and countWord(OUT, "nonsenseName") == 1 and countWord(OUT, "M2UseLOD") == 0 and #SETLOG == 0, out())

-- TP-5: a client that raises when asked about a name still gets a full report
GETHOOK = function(n) if n == "smallcull" then error("boom") end end
OUT = {}
local okRaise = pcall(ep2.slash, "probe")
GETHOOK = nil
check("TP-5 a name the client raises on is reported as not here and the probe finishes", okRaise and countWord(OUT, "smallcull") == 1
    and OUT[1]:find("here: 4, not here: 63.", 1, true) ~= nil, out())

-- TP-6: a client with no default to give shows a question mark and still lists the value
local e_nd = boot({ farclip = "1600" }, { fresh = true, defaults = false, noDefault = true })
OUT = {}
local okNd = pcall(e_nd.slash, "probe farclip")
check("TP-6 no default to give: the value is listed with a question mark", okNd and count("farclip = 1600 / ?") == 1, out())

-- TS: a saved picture size above 100% in the addon's own wiring (spec 2026-11-02-one-saved-picture-size-design.md): it is applied
-- like any saved level; the game's own saved settings always start at a safe size (logout puts a kept size above 100% back to
-- 100%); holding Shift when entering the world skips a saved size above 100% for that session; /fset size saves like the slider.
local function tsGame(extra)
    local cv = { RenderScale = "1", graphicsSSAO = "3", accountName = "x" }
    for k, v in pairs(extra or {}) do cv[k] = v end
    return boot(cv, { fresh = true, defaults = false })
end

local et = tsGame()
et.slash("profile everyday")
et.slash("set RenderScale 1.5")
et.slash("set graphicsSSAO 2")
CVARS.RenderScale, CVARS.graphicsSSAO = "1", "3"
et.fire("PLAYER_ENTERING_WORLD")
check("TS-1 a saved size above 100% is applied at a loading screen like any saved level", CVARS.RenderScale == "1.5" and CVARS.graphicsSSAO == "2",
    tostring(CVARS.RenderScale) .. " / " .. tostring(CVARS.graphicsSSAO))

local ew = tsGame()
ew.slash("profile everyday")
ew.slash("set RenderScale 1.5")
ew.slash("set graphicsSSAO 2")
CVARS.RenderScale, CVARS.graphicsSSAO = "1", "3"
SHIFT = true
OUT = {}
ew.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
check("TS-2 Shift held at the first loading screen skips a saved size above 100% and still puts the others back",
    CVARS.RenderScale == "1" and CVARS.graphicsSSAO == "2", tostring(CVARS.RenderScale) .. " / " .. tostring(CVARS.graphicsSSAO))
check("TS-2 it says so, once, in plain words", count("Shift is held: picture sharpness above 100% is not applied this session.") == 1, out())
OUT = {}
ew.fire("PLAYER_ENTERING_WORLD")
check("TS-2 the skip lasts for the whole session, quietly, though Shift is up", CVARS.RenderScale == "1" and #OUT == 0, tostring(CVARS.RenderScale) .. " " .. out())
ew.slash("set RenderScale 1.75")
check("TS-2 a size the player sets with a command still applies", CVARS.RenderScale == "1.75" and ForeverSettingsDB.want.RenderScale == "1.75", tostring(CVARS.RenderScale))
local ev = tsGame()
ev.slash("profile everyday")
ev.slash("set RenderScale 0.8")
CVARS.RenderScale = "1"
SHIFT = true
ev.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
check("TS-2 Shift does not stop a saved size of 100% or less", CVARS.RenderScale == "0.8", tostring(CVARS.RenderScale))
local el2 = tsGame()
el2.slash("profile everyday")
el2.slash("set RenderScale 1.5")
CVARS.RenderScale = "1"
el2.fire("PLAYER_ENTERING_WORLD")
CVARS.RenderScale = "1"
SHIFT = true
el2.fire("PLAYER_ENTERING_WORLD")                          -- Shift is read at the first loading screen only
SHIFT = false
check("TS-2 Shift is read at the first loading screen of the session only", CVARS.RenderScale == "1.5", tostring(CVARS.RenderScale))
local ex = tsGame()
ex.slash("profile everyday")
ex.slash("set RenderScale 1")
CVARS.RenderScale = "0.8"
SHIFT = true
ex.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
check("TS-2 a saved size of exactly 100% is still applied under Shift", CVARS.RenderScale == "1", tostring(CVARS.RenderScale))

local el = tsGame()
el.slash("profile everyday")
el.slash("set RenderScale 1.5")
OUT, SETLOG = {}, {}
el.fire("PLAYER_LOGOUT")
check("TS-3 logout puts a kept size above 100% back to 100% in the game, silently", CVARS.RenderScale == "1" and #OUT == 0 and #SETLOG == 1
    and SETLOG[1] == "RenderScale", tostring(CVARS.RenderScale) .. " " .. out() .. " " .. #SETLOG)
check("TS-3 and the profile and the enforced list still keep it", ForeverSettingsDB.want.RenderScale == "1.5"
    and ForeverSettingsDB.profiles.everyday.values.RenderScale == "1.5", tostring(ForeverSettingsDB.want.RenderScale))
el.fire("PLAYER_ENTERING_WORLD")
check("TS-3 the next loading screen applies the kept size again", CVARS.RenderScale == "1.5", tostring(CVARS.RenderScale))
el.slash("set RenderScale 0.8")
SETLOG = {}
el.fire("PLAYER_LOGOUT")
check("TS-3 a kept size of 100% or less is left alone at logout", #SETLOG == 0 and CVARS.RenderScale == "0.8", #SETLOG)
el.slash("set RenderScale 2")
CVARS.RenderScale = "0.9"
SETLOG = {}
el.fire("PLAYER_LOGOUT")
check("TS-3 so is a game that already holds 100% or less", #SETLOG == 0 and CVARS.RenderScale == "0.9", #SETLOG)
el.slash("set RenderScale 1")
CVARS.RenderScale = "1.5"                                  -- the game's own menu moved it after the addon applied 100%
SETLOG = {}
el.fire("PLAYER_LOGOUT")
check("TS-3 a kept size of exactly 100% is left alone at logout too", #SETLOG == 0 and CVARS.RenderScale == "1.5", #SETLOG)
local eu = tsGame()
eu.slash("profile everyday")
CVARS.RenderScale = "1.5"                                  -- set in the game's own menu, kept by nothing
SETLOG = {}
eu.fire("PLAYER_LOGOUT")
check("TS-3 a size above 100% that nothing keeps is the player's own and is left alone", #SETLOG == 0 and CVARS.RenderScale == "1.5", #SETLOG)
el.slash("set RenderScale 1.5")
SETFAIL.RenderScale = "error"
local okLogout = pcall(el.fire, "PLAYER_LOGOUT")
SETFAIL.RenderScale = nil
check("TS-3 a game that raises when the size is put back does not break the logout", okLogout, "error escaped")

local es = tsGame()
es.slash("profile everyday")
OUT = {}
es.slash("size")
check("TS-4 /fset size says the current size and that the profile in use keeps none",
    count("picture sharpness is 100% (not kept by the profile in use)") == 1, out())
OUT = {}
es.slash("size 150")
check("TS-4 /fset size 150 keeps 150% in the profile in use and applies it", CVARS.RenderScale == "1.5"
    and ForeverSettingsDB.profiles.everyday.values.RenderScale == "1.5" and ForeverSettingsDB.want.RenderScale == "1.5",
    tostring(CVARS.RenderScale) .. " " .. out())
OUT = {}
es.slash("size")
check("TS-4 /fset size says it is kept", count("picture sharpness is 150% (kept: the addon puts it back at every loading screen)") == 1, out())
es.slash("size 175%")
check("TS-4 a percent sign is accepted", CVARS.RenderScale == "1.75", CVARS.RenderScale)
es.slash("size 55")
check("TS-4 any step of the slider can be asked for", CVARS.RenderScale == "0.55" and ForeverSettingsDB.profiles.everyday.values.RenderScale == "0.55",
    CVARS.RenderScale)
OUT = {}
es.slash("size 201")
check("TS-4 a size out of range is refused and nothing changes", count("50% to 200%") == 1 and CVARS.RenderScale == "0.55", tostring(CVARS.RenderScale) .. " " .. out())
es.slash("size 49")
check("TS-4 below 50% is refused too", CVARS.RenderScale == "0.55", CVARS.RenderScale)
OUT = {}
es.slash("size abc")
check("TS-4 something that is not a number shows the usage", count("usage: /fset size") == 1 and CVARS.RenderScale == "0.55", out())
es.slash("size off")
local viaOff = CVARS.RenderScale == "1" and ForeverSettingsDB.profiles.everyday.values.RenderScale == "1"
es.slash("size 150")
es.slash("size normal")
local viaNormal = CVARS.RenderScale == "1"
es.slash("size 150")
es.slash("size back")
check("TS-4 off, normal and back all set 100%", viaOff and viaNormal and CVARS.RenderScale == "1", tostring(CVARS.RenderScale))
OUT = {}
es.slash("")
check("TS-4 the command list names size", count("size [percent]") == 1, out())
local eo = tsGame()
OUT = {}
eo.slash("size 150")
check("TS-4 on Original (hands off) it is refused like every edit and nothing changes", CVARS.RenderScale == "1" and count("Original is read-only") == 1,
    tostring(CVARS.RenderScale) .. " " .. out())

local en = boot({ graphicsSSAO = "3", accountName = "x" }, { fresh = true, defaults = false })
OUT = {}
local okN1 = pcall(en.slash, "size")
local okN2 = pcall(en.slash, "size 150")
check("TS-4 a client without the setting says so and keeps nothing", okN1 and okN2 and count("this client has no picture sharpness setting") == 2
    and ForeverSettingsDB.want.RenderScale == nil, out())
local ep = boot({ RenderScale = "1", accountName = "x" }, { fresh = true, defaults = false, profiles = false })
OUT = {}
local okP = pcall(ep.slash, "size 150")
check("TS-4 without the profiles module /fset size says so", okP and count("profiles module not loaded") == 1 and CVARS.RenderScale == "1", out())

-- TS-5 to TS-8: the fix pass after the fresh review of the saved picture size.
-- TS-5: the game answers a CVar name in any case, so a size typed as renderscale must be the one the window, the status and the
-- logout revert see.
local eL = tsGame()
eL.slash("profile everyday")
eL.slash("set renderscale 1.5")
check("TS-5 /fset set stores a setting under the game's own spelling, whatever case was typed", ForeverSettingsDB.want.RenderScale == "1.5"
    and ForeverSettingsDB.want.renderscale == nil and ForeverSettingsDB.profiles.everyday.values.RenderScale == "1.5" and CVARS.RenderScale == "1.5",
    tostring(ForeverSettingsDB.want.RenderScale) .. " " .. tostring(ForeverSettingsDB.want.renderscale))
SETLOG = {}
eL.fire("PLAYER_LOGOUT")
check("TS-5 so logout puts it back to 100%", CVARS.RenderScale == "1" and #SETLOG == 1, tostring(CVARS.RenderScale) .. " " .. #SETLOG)
eL.slash("set graphicsssao 2")
check("TS-5 any managed setting is stored as the window spells it", ForeverSettingsDB.want.graphicsSSAO == "2" and ForeverSettingsDB.want.graphicsssao == nil,
    tostring(ForeverSettingsDB.want.graphicsSSAO))
local eK = tsGame()
eK.slash("profile everyday")
ForeverSettingsDB.profiles.everyday.values.renderscale = "1.5"          -- saved by an older version under the spelling that was typed
ForeverSettingsDB.want.renderscale = "1.5"
CVARS.RenderScale = "1.5"
SETLOG = {}
eK.fire("PLAYER_LOGOUT")
check("TS-5 a size already saved under another spelling is put back at logout too", CVARS.RenderScale == "1" and #SETLOG == 1, tostring(CVARS.RenderScale))
CVARS.RenderScale = "1.5"
OUT = {}
eK.slash("size")
check("TS-5 and /fset size knows it is kept", count("picture sharpness is 150% (kept: the addon puts it back at every loading screen)") == 1, out())
eK.slash("unset renderscale")
check("TS-5 /fset unset finds the setting in any case", ForeverSettingsDB.want.renderscale == nil and ForeverSettingsDB.want.RenderScale == nil,
    tostring(ForeverSettingsDB.want.renderscale))
local eU = tsGame()
eU.slash("profile everyday")
eU.slash("set RenderScale 1.5")
eU.slash("unset renderscale")
check("TS-5 and a size stored under the game's spelling too", ForeverSettingsDB.want.RenderScale == nil and ForeverSettingsDB.profiles.everyday.values.RenderScale == nil,
    tostring(ForeverSettingsDB.want.RenderScale))

-- TS-6: a Shift session asked for 100%: whatever put a size above 100% in the game before the first loading screen (a test the last
-- session left unfinished, the game's own saved settings) goes back to 100%, with a plain line; a size of 100% or less is not touched.
local function pendingGame(extra)
    local g = tsGame(extra)
    g.slash("profile everyday")
    g.slash("set RenderScale 1.5")
    g.ns.bench.state().pending = { time = 1, originals = { RenderScale = "1.5" } }
    CVARS.RenderScale = "1"
    return g
end
local er = pendingGame()
SHIFT = true
OUT = {}
er.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
check("TS-6 an unfinished test's put-back does not return a saved size above 100% under Shift", CVARS.RenderScale == "1", tostring(CVARS.RenderScale) .. " " .. out())
check("TS-6 it says so in plain words", count("Shift is held: picture sharpness was above 100%, so it is back at 100% for this session.") == 1, out())
local er2 = pendingGame()
er2.fire("PLAYER_ENTERING_WORLD")
check("TS-6 without Shift the put-back and the saved size stand", CVARS.RenderScale == "1.5", tostring(CVARS.RenderScale))
local eS = tsGame()
eS.slash("profile everyday")
CVARS.RenderScale = "1.5"                                  -- the game's own saved settings held it
SHIFT = true
OUT = {}
eS.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
check("TS-6 under Shift a size above 100% that nothing keeps goes back to 100% too", CVARS.RenderScale == "1" and count("back at 100% for this session") == 1,
    tostring(CVARS.RenderScale) .. " " .. out())
local eW = tsGame()
eW.slash("profile everyday")
CVARS.RenderScale = "1.5"                                  -- the player's own size from the game's menu, nothing kept, no Shift
OUT = {}
eW.fire("PLAYER_ENTERING_WORLD")
check("TS-6 without Shift a size above 100% that nothing keeps is left alone and nothing is said", CVARS.RenderScale == "1.5" and count("back at 100%") == 0,
    tostring(CVARS.RenderScale) .. " " .. out())
local eE = tsGame()
eE.slash("profile everyday")
CVARS.RenderScale = "1.5"
SETFAIL.RenderScale = "error"
SHIFT = true
local okShift = pcall(eE.fire, "PLAYER_ENTERING_WORLD")
SHIFT = false
SETFAIL.RenderScale = nil
check("TS-6 a game that raises when the size is put back does not break the first loading screen", okShift, "error escaped")
local eN = tsGame()
eN.slash("profile everyday")
CVARS.RenderScale = "0.8"
SETLOG = {}
SHIFT = true
OUT = {}
eN.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
check("TS-6 under Shift a size of 100% or less is left alone and nothing is said", CVARS.RenderScale == "0.8" and count("back at 100%") == 0, tostring(CVARS.RenderScale) .. " " .. out())
local e100 = tsGame()
e100.slash("profile everyday")
CVARS.RenderScale = "1"
SETLOG = {}
SHIFT = true
e100.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
local wrote = false
for _, n in ipairs(SETLOG) do if n == "RenderScale" then wrote = true end end
check("TS-6 and exactly 100% is not written again", not wrote, #SETLOG)

-- TS-7: a size asked for in combat in a Shift session waits and is applied when combat ends (a command still applies); a saved
-- size that waited for combat is still skipped.
local ec = tsGame()
ec.slash("profile everyday")
SHIFT = true
ec.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
COMBAT = true
OUT = {}
ec.slash("size 175")
check("TS-7 asking for a size in combat says it will apply afterwards", count("in combat; will apply when combat ends") == 1 and CVARS.RenderScale == "1",
    tostring(CVARS.RenderScale) .. " " .. out())
COMBAT = false
ec.fire("PLAYER_REGEN_ENABLED")
check("TS-7 and it is applied when combat ends, though Shift skips saved sizes", CVARS.RenderScale == "1.75", tostring(CVARS.RenderScale))
local ed = tsGame()
ed.slash("profile everyday")
ed.slash("set RenderScale 1.5")
CVARS.RenderScale = "1"
SHIFT = true
COMBAT = true
ed.fire("PLAYER_ENTERING_WORLD")                           -- the loading screen came in combat: it waits
COMBAT = false
SHIFT = false
ed.fire("PLAYER_REGEN_ENABLED")
check("TS-7 a saved size that waited for combat is still skipped under Shift", CVARS.RenderScale == "1", tostring(CVARS.RenderScale))
local ee = tsGame()
ee.slash("profile everyday")
SHIFT = true
ee.fire("PLAYER_ENTERING_WORLD")
SHIFT = false
COMBAT = true
ee.slash("size 175")
COMBAT = false
ee.fire("PLAYER_REGEN_ENABLED")
local applied = CVARS.RenderScale == "1.75"
CVARS.RenderScale = "1"
ee.fire("PLAYER_REGEN_ENABLED")
local quiet = CVARS.RenderScale == "1"
COMBAT = true
ee.fire("PLAYER_ENTERING_WORLD")                           -- a later loading screen in combat waits too, and is not the player's ask
COMBAT = false
ee.fire("PLAYER_REGEN_ENABLED")
check("TS-7 what waited for combat is applied once; a later loading screen that waited is still skipped under Shift",
    applied and quiet and CVARS.RenderScale == "1", tostring(applied) .. tostring(quiet) .. tostring(CVARS.RenderScale))

-- TS-8: /fset size says the truth when the profile keeps a size the game does not hold (a Shift session, a refused size).
local ex2 = tsGame()
ex2.slash("profile everyday")
ex2.slash("set RenderScale 1.5")
CVARS.RenderScale = "1"
OUT = {}
ex2.slash("size")
check("TS-8 /fset size names the kept size when the game holds another", count("picture sharpness is 100% (kept at 150%, but the game has 100% now)") == 1, out())

return H.results()
