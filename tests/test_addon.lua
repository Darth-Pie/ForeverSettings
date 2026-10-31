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

return H.results()
