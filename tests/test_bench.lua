-- Tests for Bench.lua, driven through the shared harness (harness.lua).
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local env = H.boot({}, { fresh = true })
local bench = env.ns.bench

local function rep(v, n) local t = {} for i = 1, n do t[i] = v end return t end
local function rep2(v1, n1, v2, n2)
    local t = rep(v1, n1)
    for _ = 1, n2 do t[#t + 1] = v2 end
    return t
end
local function alternate(a, b, n) local t = {} for i = 1, n do t[i] = (i % 2 == 1) and a or b end return t end
local function near(x, y, tol) return math.abs(x - y) <= (tol or 1e-6) end
-- every numeric field of want matches got within 1e-6, other fields exactly
local function matches(got, want)
    for k, v in pairs(want) do
        if type(v) == "number" then
            if got[k] == nil or not near(got[k], v) then return false, k .. "=" .. tostring(got[k]) end
        elseif got[k] ~= v then
            return false, k .. "=" .. tostring(got[k])
        end
    end
    return true
end

local s, g = bench.stats, bench.guard

-- Task 2: stats
test("B2-1 even frames", function()
    return matches(s.summarize(rep(0.005, 1000)), { n = 1000, meanMs = 5.0, fps = 200, low1Fps = 200, maxMs = 5.0, hitches = 0 })
end)
test("B2-2 one slow frame among 100", function()
    local r = s.summarize(rep2(0.010, 99, 0.100, 1))
    return matches(r, { n = 100, meanMs = 10.9, low1Fps = 100, maxMs = 100, hitches = 1 })
end)
test("B2-2b fps of that run to the precision the spec shows", function()
    return near(s.summarize(rep2(0.010, 99, 0.100, 1)).fps, 100 / 1.09, 1e-6)
end)
test("B2-3 two slow frames move the 1% low", function()
    return s.summarize(rep2(0.010, 98, 0.100, 2)).low1Fps == 10
end)
test("B2-4 percentile edges", function()
    return s.percentile({ 7 }, 0.99) == 7 and s.percentile({ 1, 2, 3 }, 1.0) == 3 and s.percentile({ 1, 2, 3, 4 }, 0.5) == 2
end)
test("B2-10 irregular frame times", function()
    local r = s.summarize({ 0.004, 0.0065, 0.0081, 0.0059, 0.012 })
    return matches(r, { n = 5, meanMs = 7.3, fps = 5 / 0.0365, low1Fps = 1 / 0.012, maxMs = 12, hitches = 0 })
end)
test("B2-11 summarize leaves the caller's array in order", function()
    local d = { 0.02, 0.01, 0.03 }
    s.summarize(d)
    return d[1] == 0.02 and d[2] == 0.01 and d[3] == 0.03
end)
test("B2-13 an empty array gives n = 0 and no error", function()
    return s.summarize({}).n == 0
end)

-- Task 2: guards
test("B2-5 noisy boundary", function()
    return (not g.noisy(100, 105)) and g.noisy(100, 106) and not g.noisy(10, 10.4)
end)
test("B2-6 responds boundary", function()
    return g.responds(10, 9.0) and g.responds(10, 8.9) and not g.responds(10, 9.1)
end)
test("B2-7 background cap", function()
    return g.backgroundCap(rep(0.033, 200))
        and g.backgroundCap(rep2(0.032, 100, 0.034, 100))
        and (not g.backgroundCap(rep(0.016, 200)))
        and (not g.backgroundCap(alternate(0.020, 0.046, 200)))
end)
test("B2-7b a median near 33 ms with a wide spread is not a cap", function()
    local d = rep(0.010, 50)
    for _ = 1, 100 do d[#d + 1] = 0.033 end
    for _ = 1, 50 do d[#d + 1] = 0.080 end
    return not g.backgroundCap(d)
end)
test("B2-8 noEffect", function()
    return g.noEffect(10.0, { 10.1, 9.9, 10.2 }) and (not g.noEffect(10.0, { 10.1, 11.0 }))
        and g.noEffect(10.0, { 10.4999 }) and (not g.noEffect(10.0, { 10.5 })) and (not g.noEffect(10.0, {}))
end)
test("B2-9 timeShifted", function()
    return (not g.timeShifted(12, 0, 12, 9)) and g.timeShifted(12, 0, 12, 10) and g.timeShifted(12, 10, 12, 0)
        and g.timeShifted(23, 55, 0, 5) and (not g.timeShifted(23, 58, 0, 4))
end)
test("B2-12 the constants are the spec's values", function()
    local K = bench.K
    return K.SETTLE == 3.0 and K.MEASURE == 8.0 and K.MIN_FRAMES == 200 and K.STALL == 1.0 and K.NOISE == 0.05
        and K.SENSITIVITY == 0.10 and K.HITCH == 0.050 and K.PROBE_CEILING == 12 and K.HISTORY == 10
        and K.POLL == 0.25 and K.GAME_MINUTES == 10 and K.CONTROL_FACTOR == 0.75 and K.CHECK_WINDOWS == 3
        and K.WATCHDOG == 5
end)

-- Task 3: state, settings table, tiers, probe, list, window arithmetic
-- Each test boots its own game so nothing leaks between them.
local function newBench(cvars, opts)
    opts = opts or {}
    opts.fresh = true
    local e = H.boot(cvars, opts)
    return e, e.ns.bench
end
local function outText() return table.concat(OUT, " | ") end
local function has(sub)
    for _, l in ipairs(OUT) do
        if l:find(sub, 1, true) then return true end
    end
    return false
end

test("B3-12 state() is nil before the saved variables load and holds tiers and history after", function()
    local _, b0 = newBench({}, { noload = true })
    local e1, b1 = newBench({})
    local st = b1.state()
    return b0.state() == nil and type(st) == "table" and type(st.tiers) == "table" and type(st.history) == "table"
        and e1.ns.db().bench == st
end)

test("B3-1 the settings table has the nine rows of spec section 9", function()
    local _, b = newBench({})
    local keys = {}
    for _, row in ipairs(b.SETTINGS) do keys[#keys + 1] = row.key end
    local raw
    for _, row in ipairs(b.SETTINGS) do if row.key == "clutterraw" then raw = row end end
    local light
    for _, row in ipairs(b.SETTINGS) do if row.key == "lighting" then light = row end end
    return table.concat(keys, ",") == "shadows,ssao,compute,lighting,liquid,texture,clutter,clutterraw,renderscale"
        and raw and table.concat(raw.tiers, ",") == "48,64,128" and raw.cvars[1] == "groundEffectDensity"
        and light and light.cvars[1] == "giQuality" and light.cvars[2] == "graphicsLightMode" and light.confirmed == false
end)

test("B3-2 resolve skips missing CVars and rows without tiers, and says why", function()
    local _, b = newBench({ graphicsShadowQuality = "4", groundEffectDensity = "64", graphicsSSAO = "3" })
    local resolved, skipped = b.resolve()
    local why = {}
    for _, sk in ipairs(skipped) do why[sk.key] = sk.reason end
    return #resolved == 1 and resolved[1].key == "clutterraw" and resolved[1].cvar == "groundEffectDensity"
        and why.shadows and why.shadows:find("/fset bench probe graphicsShadowQuality", 1, true) ~= nil
        and why.compute and why.compute:find("graphicsComputeEffects", 1, true) ~= nil
        and why.compute:find("not found", 1, true) ~= nil
end)

test("B3-2b resolve uses tiers saved by probe, and the first candidate CVar that exists", function()
    local _, b = newBench({ graphicsShadowQuality = "4", graphicsLightMode = "2" })
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2" }
    b.state().tiers.graphicsLightMode = { "0", "1" }
    local r1 = b.resolve()
    local _, b2 = newBench({ giQuality = "1", graphicsLightMode = "2" })
    b2.state().tiers.giQuality = { "0", "1" }
    b2.state().tiers.graphicsLightMode = { "0", "1" }
    local r2 = b2.resolve()
    local keys1 = {}
    for _, r in ipairs(r1) do keys1[r.key] = r.cvar end
    local keys2 = {}
    for _, r in ipairs(r2) do keys2[r.key] = r.cvar end
    return keys1.shadows == "graphicsShadowQuality" and keys1.lighting == "graphicsLightMode" and keys2.lighting == "giQuality"
end)

test("B3-3 a read-back such as 0.750000 equals 0.75 (Review Focus 4)", function()
    local _, b = newBench({ RenderScale = "1.000000" })
    DERIVED.RenderScale = function(v, cv) cv.RenderScale = string.format("%.6f", tonumber(v)) end
    SetCVar("RenderScale", 0.75)
    local entry = { tiers = { "0.5", "0.75", "1" } }
    local list = b.tiersToMeasure(entry, CVARS.RenderScale)
    return CVARS.RenderScale == "0.750000" and b.sameValue("0.75", CVARS.RenderScale) and (not b.sameValue("0.75", "0.76"))
        and #list == 2 and list[1] == "0.5" and list[2] == "1"
end)

test("B3-3b tiersToMeasure leaves out the current tier and keeps all when the current value is no tier", function()
    local _, b = newBench({})
    local entry = { tiers = { "48", "64", "128" } }
    local a = b.tiersToMeasure(entry, "64")
    local c = b.tiersToMeasure(entry, "64.000000")
    local d = b.tiersToMeasure(entry, "70")
    return table.concat(a, ",") == "48,128" and table.concat(c, ",") == "48,128" and table.concat(d, ",") == "48,64,128"
end)

test("B3-4 countWindows: 7 settings of 5 tiers is 38 windows", function()
    local _, b = newBench({})
    local resolved, currents = {}, {}
    for i = 1, 7 do
        local cvar = "cvar" .. i
        resolved[i] = { key = "k" .. i, cvar = cvar, tiers = { "0", "1", "2", "3", "4" } }
        currents[cvar] = "2"
    end
    return b.countWindows(resolved, currents) == 38
end)

test("B3-5 probe finds the accepted range when the game clamps above it, and restores the value", function()
    local _, b = newBench({ graphicsSSAO = "2" })
    DERIVED.graphicsSSAO = function(v, cv) if tonumber(v) > 3 then cv.graphicsSSAO = "3" end end
    local tiers, reason = b.probe("graphicsSSAO")
    return tiers and table.concat(tiers, ",") == "0,1,2,3" and CVARS.graphicsSSAO == "2"
        and table.concat(b.state().tiers.graphicsSSAO, ",") == "0,1,2,3", tostring(reason)
end)

test("B3-6 probe stops at the ceiling of 12 (13 values) and restores the value", function()
    local _, b = newBench({ graphicsSSAO = "5" })
    local tiers = b.probe("graphicsSSAO")
    return tiers and #tiers == 13 and tiers[1] == "0" and tiers[13] == "12" and CVARS.graphicsSSAO == "5"
end)

test("B3-7 probe of a CVar that never reads back returns nil and leaves it alone", function()
    local _, b = newBench({ graphicsSSAO = "99" })
    SETFAIL.graphicsSSAO = "clamp"
    local tiers, reason = b.probe("graphicsSSAO")
    return tiers == nil and reason == "no value read back" and CVARS.graphicsSSAO == "99" and b.state().tiers.graphicsSSAO == nil
end)

test("B3-7b a single accepted value is not a range", function()
    local _, b = newBench({ graphicsSSAO = "3" })
    SETFAIL.graphicsSSAO = "clamp"
    local tiers, reason = b.probe("graphicsSSAO")
    return tiers == nil and reason == "fewer than two values read back"
end)

test("B3-7c SetCVar raising an error during a probe does not escape", function()
    local _, b = newBench({ graphicsSSAO = "99" })
    SETFAIL.graphicsSSAO = "error"
    local ok, tiers, reason = pcall(b.probe, "graphicsSSAO")
    return ok and tiers == nil and reason == "no value read back"
end)

test("B3-8 probe refuses raw CVars with explicit tier lists", function()
    local _, b = newBench({ groundEffectDensity = "64", RenderScale = "1" })
    local t1, r1 = b.probe("groundEffectDensity")
    local t2, r2 = b.probe("RenderScale")
    return t1 == nil and r1 == "raw CVar: tiers are an explicit list" and t2 == nil and r2 == r1 and CVARS.groundEffectDensity == "64"
end)

test("B3-9 probe of an unknown CVar says so", function()
    local _, b = newBench({})
    local tiers, reason = b.probe("nosuch")
    return tiers == nil and reason == "unknown CVar"
end)

test("B3-10 probe refuses in combat and changes nothing", function()
    local _, b = newBench({ graphicsSSAO = "2" })
    COMBAT = true
    local tiers, reason = b.probe("graphicsSSAO")
    return tiers == nil and reason == "in combat" and CVARS.graphicsSSAO == "2"
end)

test("B3-13 list prints one line per row, with unconfirmed rows marked and tiers shown", function()
    local _, b = newBench({ graphicsShadowQuality = "4", groundEffectDensity = "64" })
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2" }
    OUT = {}
    b.list()
    local lines = 0
    for _ in ipairs(OUT) do lines = lines + 1 end
    return lines == 9 and has("Shadows (graphicsShadowQuality) = 4  tiers: 0 1 2")
        and has("Ground clutter (raw) (groundEffectDensity) = 64  tiers: 48 64 128")
        and has("Secondary lighting: CVar not found (tried giQuality, graphicsLightMode) (unconfirmed)")
        and has("SSAO: CVar not found"), outText()
end)

-- Task 4: guarded set and restore
local function pendingOf(b) return b.state().pending end
local function keysOf(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return table.concat(keys, ",")
end

test("B4-1 isGuarded matches the spec's substrings and nothing unrelated", function()
    local _, b = newBench({})
    local r = b.restore
    return r.isGuarded("graphicsSSAO") and r.isGuarded("RAIDgraphicsQuality") and r.isGuarded("groundEffectDensity")
        and r.isGuarded("giQuality") and r.isGuarded("vsync")
        and (not r.isGuarded("accountName")) and (not r.isGuarded("engineSurvey"))
        and (not r.isGuarded("Sound_MasterVolume")) and (not r.isGuarded("portal"))
end)

test("B4-2 order puts menu-level graphics CVars before the raw ones they derive", function()
    local _, b = newBench({})
    local o = b.restore.order({ "giQuality", "graphicsLightMode", "RAIDgraphicsQuality", "groundEffectDensity" })
    return table.concat(o, ",") == "RAIDgraphicsQuality,graphicsLightMode,giQuality,groundEffectDensity"
end)

test("B4-3 apply restores in order, so a derived raw value ends at its original", function()
    local _, b = newBench({ graphicsLightMode = "0", giQuality = "1" })
    DERIVED.graphicsLightMode = function(v, cv) cv.giQuality = "2" end
    b.restore.writePending({ graphicsLightMode = "1", giQuality = "3" })
    local status, issues = b.restore.apply({ graphicsLightMode = "1", giQuality = "3" })
    return status == "done" and #issues == 0 and CVARS.graphicsLightMode == "1" and CVARS.giQuality == "3"
        and pendingOf(b) == nil, tostring(CVARS.giQuality)
end)

test("B4-4 a CVar the game will not restore is reported and saved, and pending is still cleared", function()
    local _, b = newBench({ RAIDgraphicsQuality = "2" })
    SETFAIL.RAIDgraphicsQuality = "clamp"
    b.restore.writePending({ RAIDgraphicsQuality = "6" })
    OUT = {}
    local status, issues = b.restore.apply({ RAIDgraphicsQuality = "6" })
    local saved = b.state().lastRestoreIssues
    return status == "done" and #issues == 1 and issues[1] == "RAIDgraphicsQuality: was 6, now 2"
        and saved and saved[1] == issues[1] and pendingOf(b) == nil and has("could not restore RAIDgraphicsQuality: was 6, now 2"), outText()
end)

test("B4-5 SetCVar raising an error for one CVar does not stop the others", function()
    local _, b = newBench({ graphicsSSAO = "2", vsync = "0" })
    SETFAIL.graphicsSSAO = "error"
    b.restore.writePending({ graphicsSSAO = "3", vsync = "1" })
    local ok, status, issues = pcall(b.restore.apply, { graphicsSSAO = "3", vsync = "1" })
    return ok and status == "done" and CVARS.vsync == "1" and #issues == 1 and issues[1] == "graphicsSSAO: was 3, now 2"
end)

test("B4-6 a restore due in combat waits for combat to end and pending survives until then (Review Focus 3)", function()
    local e, b = newBench({ graphicsSSAO = "2", vsync = "0" })
    LOCKED.graphicsSSAO = true
    b.restore.writePending({ graphicsSSAO = "3", vsync = "1" })
    COMBAT = true
    local status, issues = b.restore.apply({ graphicsSSAO = "3", vsync = "1" })
    local during = status == "deferred" and #issues == 0 and CVARS.graphicsSSAO == "2" and CVARS.vsync == "0"
        and pendingOf(b) ~= nil and b.state().lastRestoreIssues == nil
    COMBAT = false
    e.fire("PLAYER_REGEN_ENABLED")
    return during, "state during combat was wrong"
end)

test("B4-6b after combat ends the deferred restore completes and pending is cleared", function()
    local e, b = newBench({ graphicsSSAO = "2", vsync = "0" })
    LOCKED.graphicsSSAO = true
    b.restore.writePending({ graphicsSSAO = "3", vsync = "1" })
    COMBAT = true
    b.restore.apply({ graphicsSSAO = "3", vsync = "1" })
    COMBAT = false
    e.fire("PLAYER_REGEN_ENABLED")
    e.fire("PLAYER_REGEN_ENABLED")
    return CVARS.graphicsSSAO == "3" and CVARS.vsync == "1" and pendingOf(b) == nil
        and #b.state().lastRestoreIssues == 0, tostring(CVARS.graphicsSSAO)
end)

test("B4-7 recover restores a saved pending and says so; with none it is false and silent", function()
    local _, b = newBench({ graphicsSSAO = "2" })
    local none = b.recover()
    local silent = #OUT == 0
    b.restore.writePending({ graphicsSSAO = "3" })
    OUT = {}
    local did = b.recover()
    return none == false and silent and did == true and CVARS.graphicsSSAO == "3" and pendingOf(b) == nil
        and has("restored settings from an interrupted benchmark"), outText()
end)

test("B4-8 capture holds exactly the guarded CVars that exist", function()
    local _, b = newBench({ graphicsSSAO = "3", groundEffectDensity = "64", accountName = "x", Sound_MasterVolume = "1", vsync = "0" })
    EXTRACMDS[1] = "graphicsFakeCommand"
    EXTRACMDS[2] = "notacvar"
    local got = b.restore.capture()
    return keysOf(got) == "graphicsSSAO,groundEffectDensity,vsync" and got.groundEffectDensity == "64" and got.vsync == "0"
end)

test("B4-9 capture without the console API uses the built-in names and says so", function()
    local _, b = newBench({ graphicsSSAO = "3", groundEffectDensity = "64", accountName = "x", vsync = "0" }, { console = "none" })
    local got, source = b.restore.capture()
    return keysOf(got) == "graphicsSSAO,groundEffectDensity,vsync" and got.vsync == "0" and source == "built-in", keysOf(got)
end)

test("B4-9b capture with the console list says the names came from the client", function()
    local _, b = newBench({ graphicsSSAO = "3" })
    local _, source = b.restore.capture()
    return source == "client"
end)

test("T12-5 the older global console function is used when C_Console is missing", function()
    local _, b = newBench({ graphicsFoo = "1", vsync = "0", accountName = "x" }, { console = "legacy" })
    local got, source = b.restore.capture()
    return keysOf(got) == "graphicsFoo,vsync" and source == "client", keysOf(got) .. " / " .. tostring(source)
end)

test("T12-6 a console list that is unusable falls back to the built-in names without an error", function()
    local shapes = {
        function() return "nope" end,
        function() return {} end,
        function() return { {}, { help = "x" }, 5 } end,
        function() error("forbidden") end,
        function() return nil end,
    }
    local bad = {}
    for i, shape in ipairs(shapes) do
        local _, b = newBench({ graphicsSSAO = "3", graphicsFoo = "1", vsync = "0" })
        _G.C_Console = { GetAllCommands = shape }
        local ok, got, source = pcall(b.restore.capture)
        if not (ok and keysOf(got) == "graphicsSSAO,vsync" and source == "built-in") then bad[#bad + 1] = i end
    end
    return #bad == 0, "shapes that failed: " .. table.concat(bad, ",")
end)

test("T12-7 console entries may be strings or tables with a name", function()
    local _, b = newBench({ graphicsFoo = "1", graphicsBar = "2", vsync = "0" })
    _G.C_Console = { GetAllCommands = function() return { "graphicsFoo", { name = "graphicsBar" } } end }
    local got, source = b.restore.capture()
    return keysOf(got) == "graphicsBar,graphicsFoo,vsync" and source == "client", keysOf(got)
end)

test("T12-8 a partial console list does not hide the built-in names", function()
    local _, b = newBench({ graphicsSSAO = "3", groundEffectDensity = "64", vsync = "0" })
    _G.C_Console = { GetAllCommands = function() return { { command = "vsync" } } end }
    local got = b.restore.capture()
    return keysOf(got) == "graphicsSSAO,groundEffectDensity,vsync", keysOf(got)
end)

test("T12-9 a name in both lists, in different case, is captured once under the client's spelling", function()
    local _, b = newBench({ GROUNDEFFECTDENSITY = "64" })
    _G.C_Console = { GetAllCommands = function() return { { command = "GROUNDEFFECTDENSITY" } } end }
    local got = b.restore.capture()
    return keysOf(got) == "GROUNDEFFECTDENSITY", keysOf(got)
end)

test("B4-10 writePending stores the originals and the injected time", function()
    local _, b = newBench({ graphicsSSAO = "3" })
    b.restore.writePending({ graphicsSSAO = "3" })
    local p = pendingOf(b)
    return p ~= nil and p.time == 1790000000 and p.originals.graphicsSSAO == "3" and b.now() == 1790000000
end)

test("B4-11 a corrupt pending (no originals) is cleared by recover without an error", function()
    local _, b = newBench({ graphicsSSAO = "2" })
    b.state().pending = { time = 1 }
    local ok, did = pcall(b.recover)
    return ok and did == false and pendingOf(b) == nil, tostring(ok) .. " / " .. tostring(did)
end)

-- Task 5: one measurement window
-- A fake renderer: the frame time for every frame. Index-based or accumulated so a test knows where it is.
local function constant(dt) return function() return dt end end
local function byIndex(base, special)       -- special[n] = dt overrides frame number n
    local n = 0
    return function()
        n = n + 1
        return special[n] or base
    end
end
local function startWindow(b)
    local results = {}
    local started = b.runWindow(function(r) results[#results + 1] = r end)
    return results, started
end

test("B5-1 constant 5 ms frames: one result, 1600 frames, mean 5 ms", function()
    local e, b = newBench({})
    local results = startWindow(b)
    e.pump(11.5, constant(0.005))
    local r = results[1]
    return #results == 1 and r.ok and math.abs(r.summary.n - 1600) <= 1 and near(r.summary.meanMs, 5.0, 1e-6)
        and r.retried == false and (not b.measuring())
end)

test("B5-2 the settle period is discarded from the statistics", function()
    local e, b = newBench({})
    local results = startWindow(b)
    local t = 0
    e.pump(11.5, function()
        local dt = (t < 3.0) and 0.010 or 0.005
        t = t + dt
        return dt
    end)
    local r = results[1]
    return r and r.ok and near(r.summary.meanMs, 5.0, 1e-6) and r.summary.maxMs <= 5.000001, r and tostring(r.summary and r.summary.meanMs)
end)

test("B5-3 one stalled frame restarts the window once and the stall is not counted", function()
    local e, b = newBench({})
    local results = startWindow(b)
    e.pump(18, byIndex(0.005, { [1000] = 1.2 }))
    local r = results[1]
    return #results == 1 and r.ok and r.retried == true and r.summary.maxMs < 100 and math.abs(r.summary.n - 1600) <= 1
end)

test("B5-3b a second stall ends the window as inconclusive", function()
    local e, b = newBench({})
    local results = startWindow(b)
    e.pump(20, byIndex(0.005, { [1000] = 1.2, [2000] = 1.2 }))
    return #results == 1 and results[1].ok == false and results[1].reason == "stall"
end)

test("B5-4 too few frames is reported, not measured", function()
    local e, b = newBench({})
    local results = startWindow(b)
    e.pump(11.5, constant(0.1))
    return #results == 1 and results[1].ok == false and results[1].reason == "few"
end)

test("B5-5 combat, zoning, movement and falling each end the window with their reason", function()
    local reasons = {}
    for _, case in ipairs({
        { "combat", function(e) e.fire("PLAYER_REGEN_DISABLED") end },
        { "zoning", function(e) e.fire("PLAYER_ENTERING_WORLD") end },
        { "zoning", function(e) e.fire("PLAYER_LEAVING_WORLD") end },
        { "movement", function() SPEED = 7 end },
        { "movement", function() FALLING = true end },
    }) do
        local e, b = newBench({})
        local results = startWindow(b)
        e.pump(4, constant(0.005))
        case[2](e)
        e.pump(2, constant(0.005))
        reasons[#reasons + 1] = (#results == 1 and results[1].ok == false and results[1].reason or "wrong") .. (b.measuring() and "!" or "")
    end
    return table.concat(reasons, ",") == "combat,zoning,zoning,movement,movement", table.concat(reasons, ",")
end)

test("B5-5b an event before any window starts does nothing", function()
    local e, b = newBench({})
    e.fire("PLAYER_REGEN_DISABLED")
    e.fire("PLAYER_ENTERING_WORLD")
    local results = startWindow(b)
    e.pump(11.5, constant(0.005))
    return #results == 1 and results[1].ok
end)

test("B5-6 the watchdog ends a window that never receives a frame", function()
    local e, b = newBench({})
    local results = startWindow(b)
    e.advance(4.9)
    local early = #results == 0 and b.measuring()
    e.advance(0.3)
    return early and #results == 1 and results[1].ok == false and results[1].reason == "no frames" and (not b.measuring())
end)

test("B5-6b the watchdog does nothing once frames have arrived", function()
    local e, b = newBench({})
    local results = startWindow(b)
    e.pump(1, constant(0.005))
    e.advance(5.1)
    return #results == 0 and b.measuring()
end)

test("B5-6c an old window's watchdog does not end a later window (#273)", function()
    local e, b = newBench({})
    local first = startWindow(b)
    e.fire("PLAYER_REGEN_DISABLED")            -- window A ends at once; its timer is still pending
    local second = startWindow(b)
    e.pump(1, constant(0.005))                 -- window B has received frames
    e.advance(5.1)                             -- A's timer comes due
    return #first == 1 and #second == 0 and b.measuring()
end)

test("B5-7 the timing frame has no parent and is shown", function()
    local e, b = newBench({})
    startWindow(b)
    local f
    for _, fr in ipairs(H.frames()) do
        if fr.scripts.OnUpdate then f = fr end
    end
    return f ~= nil and f.parent == nil and f.shown == true
end)

test("B5-8 a 33 ms window carries the background-cap flag, and game time is recorded", function()
    local e, b = newBench({})
    GAMETIME = { 13, 7 }
    local results = startWindow(b)
    e.pump(12, constant(0.033))
    local r = results[1]
    local flagged = false
    for _, f in ipairs(r and r.flags or {}) do
        if f == "possible background-window cap" then flagged = true end
    end
    return r and r.ok and flagged and r.gameTime[1] == 13 and r.gameTime[2] == 7
end)

test("B5-8b a clean window has no flags", function()
    local e, b = newBench({})
    local results = startWindow(b)
    e.pump(11.5, constant(0.005))
    return results[1].ok and #results[1].flags == 0
end)

test("B5-9 a second window starts clean, and a window cannot start while one runs", function()
    local e, b = newBench({})
    local first = startWindow(b)
    local _, startedAgain = startWindow(b)
    e.pump(11.5, constant(0.005))
    local second = startWindow(b)
    e.pump(11.5, constant(0.004))
    return startedAgain == false and #first == 1 and #second == 1 and math.abs(second[1].summary.n - 2000) <= 1
        and near(second[1].summary.meanMs, 4.0, 1e-6)
end)

-- Task 6: preflight, environment probes, control test, check
-- Fake renderer for check: the frame time follows RenderScale, so the control has a known, calculable drop.
local function renderCost(cv) return 0.004 + 0.004 * tonumber(cv.RenderScale) end
local function checkCvars() return { RenderScale = "1", graphicsShadowQuality = "2", vsync = "0" } end
local function runCheck(e, b, costFn, seconds)
    local results = {}
    b.check(function(r) results[#results + 1] = r end)
    e.pump(seconds or 50, costFn or renderCost)
    return results
end

test("B6-10 environment() passes on the harness and names each assumption", function()
    local _, b = newBench(checkCvars())
    local list = b.environment()
    local names, allOk = {}, true
    for _, c in ipairs(list) do
        names[#names + 1] = c.name
        if not c.ok then allOk = false end
    end
    return allOk and #list == 5 and table.concat(names, "|"):find("GetUnitSpeed", 1, true) ~= nil
        and table.concat(names, "|"):find("CVar list", 1, true) ~= nil
end)

local function envEntry(b, name)
    for _, c in ipairs(b.environment()) do if c.name == name then return c end end
end

test("B6-10b environment() fails when GetUnitSpeed is missing, and when no known graphics CVar exists at all", function()
    -- The probes read the stubbed globals when asked, so ask right after each boot.
    local _, b1 = newBench(checkCvars(), { nounitspeed = true })
    local c1 = envEntry(b1, "GetUnitSpeed")
    local _, b2 = newBench({ accountName = "x" }, { console = "none" })
    local c2 = envEntry(b2, "CVar list")
    return c1 and c1.ok == false and c2 and c2.ok == false and type(c2.detail) == "string"
end)

test("B6-10c a console list that is not a table no longer fails the environment (the built-in list serves)", function()
    local _, b = newBench(checkCvars())
    _G.C_Console = { GetAllCommands = function() return "nope" end }
    local c = envEntry(b, "CVar list")
    return c and c.ok == true and type(c.note) == "string" and c.note:find("built-in", 1, true) ~= nil
end)

test("B6-10d the CVar-list entry names the built-in list when used and has no note with the client's list", function()
    local _, b1 = newBench(checkCvars(), { console = "none" })
    local c1 = envEntry(b1, "CVar list")
    local _, b2 = newBench(checkCvars())
    local c2 = envEntry(b2, "CVar list")
    return c1 and c1.ok and type(c1.note) == "string" and c1.note:find("built-in", 1, true) ~= nil
        and c2 and c2.ok and c2.note == nil
end)

test("B6-5 vsync and an FPS cap each add a warning and do not refuse", function()
    local function warningsFor(extra)
        local cv = checkCvars()
        for k, v in pairs(extra) do cv[k] = v end
        local _, b = newBench(cv)
        local ok, _, warnings = b.preflight()
        return ok, table.concat(warnings, " | ")
    end
    local okV, wV = warningsFor({ vsync = "1" })
    local okU, wU = warningsFor({ useMaxFPS = "1" })
    local okM, wM = warningsFor({ maxFPS = "200" })
    local okOff, wOff = warningsFor({ maxFPS = "200", useMaxFPS = "0" })
    local okNone, wNone = warningsFor({})
    return okV and wV:find("vsync", 1, true) ~= nil and okU and wU:find("frame-rate limit", 1, true) ~= nil
        and okM and wM:find("frame-rate limit", 1, true) ~= nil and okOff and wOff == "" and okNone and wNone == ""
end)

test("B6-7 pickControl: render scale times 0.75, else the cheapest shadow tier, else lighting, else nothing", function()
    local _, b = newBench({})
    local rs = { key = "renderscale", label = "Render scale", cvar = "RenderScale", tiers = { "0.5", "1" } }
    local sh = { key = "shadows", label = "Shadows", cvar = "graphicsShadowQuality", tiers = { "0", "1", "2" } }
    local li = { key = "lighting", label = "Secondary lighting", cvar = "giQuality", tiers = { "0", "1" } }
    local c1 = b.pickControl({ rs, sh }, { RenderScale = "1.000000", graphicsShadowQuality = "2" })
    local c2 = b.pickControl({ sh }, { graphicsShadowQuality = "2" })
    local c3 = b.pickControl({ sh, li }, { graphicsShadowQuality = "0", giQuality = "1" })
    local c4 = b.pickControl({ sh }, { graphicsShadowQuality = "0" })
    return c1.cvar == "RenderScale" and c1.value == "0.75" and c1.label == "Render scale"
        and c2.cvar == "graphicsShadowQuality" and c2.value == "0"
        and c3.cvar == "giQuality" and c3.value == "0" and c4 == nil
end)

test("B6-1 check: baseline and spread printed, the control responds, everything is put back", function()
    local e, b = newBench(checkCvars())
    local results = runCheck(e, b)
    local r = results[1]
    return #results == 1 and r.ok and near(r.baselineMs, 8.0, 0.01) and r.spread < 0.01 and r.drop > 0.10
        and has("baseline 8.00 ms") and has("spread") and has("control") and has("ok")
        and CVARS.RenderScale == "1" and e.ns.suspended == false and b.active() == false and pendingOf(b) == nil, outText()
end)

test("B6-2 a frame time that does not follow the control ends the check with 'did not respond'", function()
    local e, b = newBench(checkCvars())
    local results = runCheck(e, b, function() return 0.008 end)
    local r = results[1]
    return #results == 1 and r.ok == false and r.reason == "control did not respond" and has("did not respond")
        and CVARS.RenderScale == "1" and pendingOf(b) == nil and b.active() == false, outText()
end)

test("B6-3 a leftover pending is restored first and the check runs on the restored values (Review Focus 2)", function()
    local e, b = newBench(checkCvars())
    CVARS.RenderScale = "0.5"
    b.state().pending = { time = 1, originals = { RenderScale = "1", graphicsShadowQuality = "2", vsync = "0" } }
    local results = runCheck(e, b)
    local r = results[1]
    return r and r.ok and near(r.baselineMs, 8.0, 0.01) and CVARS.RenderScale == "1"
        and has("Settings from an interrupted test were put back first."), outText()
end)

test("B6-4 refusals: combat, moving, a run already active, a missing environment piece", function()
    local reasons = {}
    do
        local e, b = newBench(checkCvars())
        COMBAT = true
        local r = runCheck(e, b, renderCost, 1)[1]
        reasons[1] = r and r.reason or "none"
        COMBAT = false
    end
    do
        local e, b = newBench(checkCvars())
        SPEED = 7
        local r = runCheck(e, b, renderCost, 1)[1]
        reasons[2] = r and r.reason or "none"
    end
    do
        local e, b = newBench(checkCvars())
        local first = {}
        b.check(function(r) first[#first + 1] = r end)
        local second = {}
        b.check(function(r) second[#second + 1] = r end)
        reasons[3] = second[1] and second[1].reason or "none"
        e.pump(50, renderCost)
        reasons[4] = (#first == 1 and first[1].ok) and "first still ok" or "first broken"
    end
    do
        local e, b = newBench(checkCvars(), { nounitspeed = true })
        local r = runCheck(e, b, renderCost, 1)[1]
        reasons[5] = r and r.reason or "none"
    end
    return table.concat(reasons, ",") == "preflight,preflight,preflight,first still ok,preflight", table.concat(reasons, ",")
end)

test("B6-4b a refused check changes nothing: no snapshot, no suspension", function()
    local e, b = newBench(checkCvars())
    COMBAT = true
    runCheck(e, b, renderCost, 1)
    return pendingOf(b) == nil and e.ns.suspended == false and b.active() == false and has("you are in combat"), outText()
end)

test("B6-6 with no control available the check stops and says to probe first", function()
    local e, b = newBench({ graphicsSSAO = "3", vsync = "0" })
    local r = runCheck(e, b, constant(0.008), 1)[1]
    return r and r.ok == false and r.reason == "no control" and has("run /fset bench probe") and pendingOf(b) == nil
        and e.ns.suspended == false, outText()
end)

test("B6-8 a spread above the noise limit prints the warning", function()
    local e, b = newBench(checkCvars())
    local t = 0
    local r = runCheck(e, b, function(cv)
        local mult = (t < 11) and 1.0 or ((t < 22) and 1.1 or ((t < 33) and 1.2 or 0.8))
        local dt = mult * renderCost(cv)
        t = t + dt
        return dt
    end)[1]
    return r and r.ok and r.spread > 0.05 and has("noise limit"), outText()
end)

test("B6-9 check prints the line about closing browsers, streaming and VR software", function()
    local e, b = newBench(checkCvars())
    runCheck(e, b, renderCost, 1)
    return has("close browsers, streaming and VR software before measuring"), outText()
end)

test("B6-11 check prints each environment probe as PASS or FAIL", function()
    local e, b = newBench(checkCvars(), { nounitspeed = true })
    runCheck(e, b, renderCost, 1)
    return has("environment: FAIL GetUnitSpeed") and has("environment: PASS IsFalling"), outText()
end)

test("B6-12 a second check right after the first starts clean", function()
    local e, b = newBench(checkCvars())
    local first = runCheck(e, b)
    local second = runCheck(e, b)
    return #first == 1 and first[1].ok and #second == 1 and second[1].ok
end)

test("B6-13 a control the game will not accept ends the check and everything is put back", function()
    local e, b = newBench(checkCvars())
    SETFAIL.RenderScale = "clamp"
    local r = runCheck(e, b)[1]
    return r and r.ok == false and r.reason == "control rejected" and CVARS.RenderScale == "1" and pendingOf(b) == nil
        and e.ns.suspended == false, outText()
end)

-- Task 7: full run, report, history, mark, progress
-- The windows are shrunk so a whole run is quick; the fake renderer's frame time is
-- 2 ms + 4 ms x RenderScale + 0.5 ms x shadow tier, so every delta has a known answer.
local function shrink(b)
    b.K.SETTLE, b.K.MEASURE, b.K.MIN_FRAMES = 0.05, 0.2, 20
end
local function runCvars()
    return { RenderScale = "1", graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64", vsync = "0" }
end
local function newRun(cvars, opts)
    local e, b = newBench(cvars or runCvars(), opts)
    shrink(b)
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    return e, b
end
local function runCost(cv)
    return 0.002 + 0.004 * tonumber(cv.RenderScale) + 0.0005 * tonumber(cv.graphicsShadowQuality)
end
local function doRun(e, b, costFn, seconds)
    local results = {}
    b.run(function(r) results[#results + 1] = r end)
    e.pump(seconds or 60, costFn or runCost)
    return results
end
local function rowsOf(entry, cvar)
    local list = {}
    for _, row in ipairs(entry.rows) do
        if row.cvar == cvar then list[#list + 1] = row end
    end
    return list
end
local function reportText(b, entry) return table.concat(b.report(entry), "\n") end
local function copyOf(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

test("B7-1 every tier's delta matches the model, and the starting tier has delta 0", function()
    local e, b = newRun()
    local entry = doRun(e, b)[1]
    local rows = entry and rowsOf(entry, "graphicsShadowQuality") or {}
    local want = { ["0"] = -1.0, ["1"] = -0.5, ["2"] = 0, ["3"] = 0.5, ["4"] = 1.0 }
    local okAll = #rows == 5
    for _, row in ipairs(rows) do
        okAll = okAll and row.deltaMs ~= nil and near(row.deltaMs, want[row.value], 0.05)
        if row.value == "2" then okAll = okAll and near(row.meanMs, 7.0, 0.05) end   -- the reused row is the baseline's mean
    end
    return entry ~= nil and entry.valid == true and okAll and near(entry.baselineMs, 7.0, 0.05), outText()
end)

test("B7-2 baseline drift reruns each setting once, then its rows are inconclusive with no delta", function()
    local e, b = newRun()
    b.K.MIN_FRAMES = 5      -- the fake frame time compounds 2% per window; keep late windows above the minimum
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        local done = p and p.done or 0
        return runCost(cv) * (1.02 ^ math.max(0, done - 3))   -- 2% slower per window once the baseline is taken
    end, 120)[1]
    local rows = entry and rowsOf(entry, "graphicsShadowQuality") or {}
    local allBad = #rows == 5
    for _, row in ipairs(rows) do
        allBad = allBad and row.status == "inconclusive" and row.deltaMs == nil and row.meanMs == nil
            and row.reason:find("baseline drifted", 1, true) ~= nil
    end
    return entry ~= nil and allBad and entry.reruns == 4, outText()
end)

test("B7-21 a rerun adds its windows to the progress total, so the count never passes the total and ends equal to it", function()
    local e, b = newRun()
    b.K.MIN_FRAMES = 5      -- same drifting frame time as B7-2: every setting is rerun once
    local startTotal, lastTotal, over
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if p then
            startTotal = startTotal or p.total
            lastTotal = p.total
            if p.done > p.total then over = "done " .. p.done .. " of " .. p.total end
        end
        local done = p and p.done or 0
        return runCost(cv) * (1.02 ^ math.max(0, done - 3))
    end, 120)[1]
    return entry ~= nil and entry.reruns == 4 and over == nil and lastTotal > startTotal and lastTotal == entry.windows,
        tostring(over) .. " start " .. tostring(startTotal) .. " last " .. tostring(lastTotal) .. " windows " .. tostring(entry and entry.windows)
end)

test("B7-22 progress counts the repeats: none at the start, one more for every rerun, as many at the end as the run reran", function()
    local e, b = newRun()
    b.K.MIN_FRAMES = 5      -- same drifting frame time as B7-2: every setting is rerun once
    local first, last, steady = nil, 0, true
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if p then
            first = first or p.repeats
            if type(p.repeats) ~= "number" or p.repeats < last then steady = false else last = p.repeats end
        end
        local done = p and p.done or 0
        return runCost(cv) * (1.02 ^ math.max(0, done - 3))
    end, 120)[1]
    return entry ~= nil and first == 0 and steady and last == entry.reruns and last == 4,
        tostring(first) .. " " .. tostring(steady) .. " " .. tostring(last) .. " " .. tostring(entry and entry.reruns)
end)

test("B7-3 a setting that does not change the frame time is 'no measurable effect or not applied', never 'free'", function()
    local e, b = newRun()
    local entry = doRun(e, b)[1]
    local text = reportText(b, entry)
    local ssaoRows = rowsOf(entry, "graphicsSSAO")
    local flagged = #ssaoRows == 5
    for _, row in ipairs(ssaoRows) do
        local has_ = false
        for _, f in ipairs(row.flags) do if f == "no measurable effect or not applied" then has_ = true end end
        flagged = flagged and has_
    end
    return flagged and text:find("no measurable effect or not applied", 1, true) ~= nil
        and text:lower():find("free", 1, true) == nil, text
end)

test("B7-4 a tier the game clamps is recorded as rejected and costs no window", function()
    local e, b = newRun()
    DERIVED.graphicsSSAO = function(v, cv) if tonumber(v) > 2 then cv.graphicsSSAO = "2" end end
    local resolved = b.resolve()
    local currents = {}
    for _, r in ipairs(resolved) do currents[r.cvar] = CVARS[r.cvar] end
    local expected = b.countWindows(resolved, currents) - 2
    local entry = doRun(e, b)[1]
    local rows = entry and rowsOf(entry, "graphicsSSAO") or {}
    local rejected = {}
    for _, row in ipairs(rows) do
        if row.status == "rejected" then rejected[#rejected + 1] = row.value .. ":" .. row.reason end
    end
    return entry ~= nil and table.concat(rejected, ",") == "3:rejected, clamped to 2,4:rejected, clamped to 2"
        and entry.windows == expected, tostring(entry and entry.windows) .. " vs " .. tostring(expected)
end)

test("B7-5 SetCVar raising an error for one CVar rejects its rows and the run still finishes", function()
    local e, b = newRun()
    SETFAIL.graphicsSSAO = "error"
    local entry = doRun(e, b)[1]
    local ssao = entry and rowsOf(entry, "graphicsSSAO") or {}
    local shadows = entry and rowsOf(entry, "graphicsShadowQuality") or {}
    local rejected = 0
    for _, row in ipairs(ssao) do if row.status == "rejected" then rejected = rejected + 1 end end
    return entry ~= nil and entry.valid and rejected == 4 and #shadows == 5 and shadows[1].deltaMs ~= nil, outText()
end)

test("B7-6 two stalls in a window make that row inconclusive and print no number for it", function()
    local e, b = newRun()
    local n = 0
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if p and p.label == "Shadows 3" then
            n = n + 1
            if n == 20 or n == 40 then return 1.2 end
        end
        return runCost(cv)
    end)[1]
    local row
    for _, r in ipairs(entry and rowsOf(entry, "graphicsShadowQuality") or {}) do if r.value == "3" then row = r end end
    local line
    for _, l in ipairs(b.report(entry)) do if l:match("^  3  inconclusive") then line = l end end
    return row ~= nil and row.status == "inconclusive" and row.meanMs == nil and row.reason == "inconclusive (stall)"
        and line == "  3  inconclusive (stall)", tostring(line)
end)

test("B7-7 no resolvable settings: the run refuses, snapshots nothing and releases nothing (Review Focus 5)", function()
    local e, b = newBench({ vsync = "0", graphicsSSAO = "3" })
    shrink(b)
    local entry = doRun(e, b, constant(0.008), 2)[1]
    return entry and entry.ok == false and entry.reason == "nothing to measure" and pendingOf(b) == nil
        and e.ns.suspended == false and b.active() == false and #b.history() == 0 and has("nothing to measure"), outText()
end)

test("B7-8 after a run every guarded CVar is back, the suspension is released and one history entry exists", function()
    local e, b = newRun()
    local before = copyOf(CVARS)
    local entry = doRun(e, b)[1]
    local same_ = true
    for k, v in pairs(before) do if CVARS[k] ~= v then same_ = false end end
    return entry and entry.valid and same_ and e.ns.suspended == false and b.active() == false
        and pendingOf(b) == nil and #b.history() == 1 and b.history()[1] == entry, outText()
end)

test("B7-8b eleven runs keep ten history entries, newest last", function()
    local e, b = newRun({ RenderScale = "1", graphicsShadowQuality = "2", vsync = "0" })
    shrink(b)
    b.state().tiers.graphicsShadowQuality = { "0", "2" }
    local last
    for i = 1, 11 do
        b.now = function() return 1000 + i end
        last = doRun(e, b, runCost, 30)[1]
    end
    local h = b.history()
    return #h == 10 and h[10] == last and h[1].time == 1002 and h[10].time == 1011
end)

test("B7-9 report lines have the spec's format", function()
    local e, b = newRun()
    local entry = doRun(e, b)[1]
    local lines = b.report(entry)
    local heading, row = false, false
    for _, l in ipairs(lines) do
        if l:match("^Shadows %(graphicsShadowQuality%)   baseline [%d%.]+ ms") then heading = true end
        if l:match("^  %S+  [%d%.]+ ms  [%+%-][%d%.]+ ms  %d+ fps  1%% low %d+") then row = true end
    end
    return heading and row and lines[1]:find("Benchmark at Test Zone (none): baseline", 1, true) ~= nil, table.concat(lines, "\n")
end)

test("B7-10 mark saves one labelled entry and prints one line; it refuses in combat", function()
    local e, b = newBench({ RenderScale = "1", graphicsShadowQuality = "2", vsync = "0" })
    shrink(b)
    local results = {}
    b.mark("menu-high", function(r) results[#results + 1] = r end)
    e.pump(2, constant(0.008))
    local labelled = 0
    for _, l in ipairs(OUT) do if l:find("menu-high", 1, true) then labelled = labelled + 1 end end
    local h = b.history()
    local savedOk = #results == 1 and results[1].ok and #h == 1 and h[1].label == "menu-high" and h[1].valid
        and near(h[1].rows[1].meanMs, 8.0, 0.01) and labelled == 1 and b.active() == false
    OUT = {}
    COMBAT = true
    local refused = {}
    b.mark("menu-low", function(r) refused[#refused + 1] = r end)
    return savedOk and #refused == 1 and refused[1].ok == false and #b.history() == 1 and has("you are in combat"), outText()
end)

test("B7-11 a game-time shift of 10 minutes flags the later rows only", function()
    local e, b = newRun()
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if p and p.done >= 6 then GAMETIME = { 12, 10 } end
        return runCost(cv)
    end)[1]
    local rows = entry and rowsOf(entry, "graphicsShadowQuality") or {}
    local function flagged(row)
        for _, f in ipairs(row.flags or {}) do if f == "lighting may have changed" then return true end end
        return false
    end
    local laterFlagged, earlyClean = false, false
    for _, row in ipairs(rows) do
        if row.value == "4" then laterFlagged = flagged(row) end
        if row.value == "0" then earlyClean = not flagged(row) end
    end
    return entry ~= nil and laterFlagged and earlyClean, outText()
end)

test("B7-12 bench.now is used for the entry's time", function()
    local e, b = newRun()
    b.now = function() return 424242 end
    local entry = doRun(e, b)[1]
    return entry and entry.time == 424242 and entry.zone == "Test Zone" and entry.instanceType == "none"
        and entry.groupSize == 0 and entry.resolution == "3440x1440" and entry.renderScale == "1"
end)

test("B7-13 progress is nil when idle, counts windows during a run and is nil again after", function()
    local e, b = newRun()
    local idle = b.progress() == nil
    local seen, total
    local results = {}
    b.run(function(r) results[#results + 1] = r end)
    local first = b.progress()
    e.pump(60, function(cv)
        local p = b.progress()
        if p then seen = p.done; total = p.total end
        return runCost(cv)
    end)
    return idle and first ~= nil and first.done == 0 and first.total > 20 and seen ~= nil and seen == first.total - 1
        and #results == 1 and b.progress() == nil, tostring(seen) .. "/" .. tostring(total)
end)

test("B7-14 moving mid-run ends it as invalid, with everything put back", function()
    local e, b = newRun()
    b.K.POLL = 0.05
    local before = copyOf(CVARS)
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if p and p.done >= 6 then SPEED = 7 end
        return runCost(cv)
    end)[1]
    local same_ = true
    for k, v in pairs(before) do if CVARS[k] ~= v then same_ = false end end
    return entry and entry.valid == false and entry.reason == "movement" and same_ and e.ns.suspended == false
        and #b.history() == 1 and b.history()[1].valid == false and b.active() == false, outText()
end)

-- Task 8: commands, stop, wiring, recovery
local function equalTables(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end
local function restoredTo(before) return equalTables(copyOf(CVARS), before) end

test("B8-2 each subcommand reaches the right function", function()
    local e, b = newBench({ graphicsSSAO = "3" })
    local calls = {}
    e.ns.guide.open = function(kind) calls[#calls + 1] = "guide:" .. kind end      -- /fset bench and check open the guided window
    b.stop = function() calls[#calls + 1] = "stop" end
    b.list = function() calls[#calls + 1] = "list" end
    b.probe = function(c) calls[#calls + 1] = "probe:" .. tostring(c) return { "0", "1" } end
    b.mark = function(l) calls[#calls + 1] = "mark:" .. tostring(l) end
    for _, rest in ipairs({ "", "check", "stop", "list", "probe graphicsSSAO", "mark menu-high" }) do b.handle(rest) end
    local good = table.concat(calls, ",") == "guide:run,guide:check,stop,list,probe:graphicsSSAO,mark:menu-high" and has("graphicsSSAO: tiers 0 1")
    OUT = {}
    b.handle("mark")
    b.handle("probe")
    b.handle("nonsense")
    return good and #calls == 6 and has("usage: /fset bench mark <label>") and has("usage: /fset bench probe <cvar>")
        and has("usage: /fset bench [check"), table.concat(calls, ",") .. " / " .. outText()
end)

test("B8-2b a failed probe says why", function()
    local _, b = newBench({ graphicsSSAO = "99" })
    SETFAIL.graphicsSSAO = "clamp"
    OUT = {}
    b.handle("probe graphicsSSAO")
    return has("cannot probe graphicsSSAO: no value read back"), outText()
end)

test("B8-8 report prints the latest entry, the second most recent, or says there is none", function()
    local _, b = newBench({ graphicsSSAO = "3" })
    local function entry(label)
        return { label = label, valid = true, rows = { { setting = label, value = "current", meanMs = 7, fps = 142.9, low1Fps = 120, hitches = 0, flags = {} } } }
    end
    local h = b.state().history
    h[1], h[2] = entry("first"), entry("second")
    OUT = {}
    b.handle("report")
    local latest = has("second:") and not has("first:")
    OUT = {}
    b.handle("report 2")
    local older = has("first:") and not has("second:")
    OUT = {}
    b.handle("report 5")
    return latest and older and has("no saved benchmark"), outText()
end)

test("B8-10 stop with nothing running says so", function()
    local _, b = newBench({ graphicsSSAO = "3" })
    local did = b.stop()
    return did == false and has("no benchmark is running"), outText()
end)

test("B8-1 a second /fset bench during a run is refused and leaves pending untouched (Review Focus 1)", function()
    local e, b = newRun()
    b.run()
    e.pump(0.3, runCost)
    local pend = pendingOf(b)
    local snapshot = pend and copyOf(pend.originals) or {}
    OUT = {}
    b.handle("")                                          -- now opens the guided window, which shows the run in progress
    local refused = e.ns.guide.state() ~= nil and e.ns.guide.state().view == "running"
    -- The bench itself still refuses a second run when asked directly (the window is not the only caller).
    local again
    b.run(function(r) again = r end)
    local refusedByBench = again ~= nil and again.ok == false and again.reason == "preflight"
    local named = false
    for _, problem in ipairs(again and again.problems or {}) do
        if problem == "a run is already active" then named = true end
    end
    local untouched = pendingOf(b) == pend and equalTables(pend.originals, snapshot)
    e.pump(60, runCost)
    local h = b.history()
    return pend ~= nil and refused and refusedByBench and named and untouched and #h == 1 and h[1].valid and e.ns.suspended == false, outText()
end)

test("B8-3 stop mid-run ends it as invalid, with everything put back", function()
    local e, b = newRun()
    local before = copyOf(CVARS)
    b.run()
    e.pump(1.0, runCost)
    local stopped = b.stop()
    e.pump(1, runCost)
    local h = b.history()
    return stopped == true and #h == 1 and h[1].valid == false and h[1].reason == "stopped" and restoredTo(before)
        and e.ns.suspended == false and b.active() == false and pendingOf(b) == nil and has("stopping the benchmark"), outText()
end)

test("B8-4 an error inside a step aborts the run and restores, and nothing escapes", function()
    local e, b = newRun()
    local before = copyOf(CVARS)
    local fired = false
    GETHOOK = function(n)
        local p = b.progress()
        if not fired and n == "graphicsShadowQuality" and p and p.done >= 6 then
            fired = true
            error("boom")
        end
    end
    local ok, entry = pcall(function() return doRun(e, b)[1] end)
    return ok and fired and entry ~= nil and entry.valid == false and entry.reason:find("error:", 1, true) == 1
        and restoredTo(before) and e.ns.suspended == false and b.active() == false and pendingOf(b) == nil, outText()
end)

test("B8-4b an error inside a check step ends the check and restores", function()
    local e, b = newBench(checkCvars())
    shrink(b)
    local before = copyOf(CVARS)
    local armed, fired = false, false
    GETHOOK = function(n)
        if armed and not fired and n == "RenderScale" then
            fired = true
            error("boom")
        end
    end
    local results = {}
    b.check(function(r) results[#results + 1] = r end)
    local ok = pcall(e.pump, 5, function(cv)
        armed = true           -- the first GetCVar("RenderScale") after the frames start is the control step's
        return renderCost(cv)
    end)
    local r = results[1]
    return ok and fired and r ~= nil and r.ok == false and r.reason:find("error:", 1, true) == 1 and restoredTo(before)
        and e.ns.suspended == false and b.active() == false, outText()
end)

test("B8-4d when the restore itself fails the flags are still released and pending is kept for the next login", function()
    local e, b = newRun()
    local broken = false
    GETHOOK = function(n)
        local p = b.progress()
        if p and p.done >= 6 then broken = true end
        if broken and n == "graphicsShadowQuality" then error("boom") end   -- and stays broken for the restore
    end
    local ok, entry = pcall(function() return doRun(e, b)[1] end)
    return ok and entry ~= nil and entry.valid == false and e.ns.suspended == false and b.active() == false
        and pendingOf(b) ~= nil and has("restore failed"), outText()
end)

test("B8-5 combat starting mid-run: the run ends, the restore waits for combat to end, pending survives (Review Focus 3)", function()
    local e, b = newRun()
    LOCKED.graphicsShadowQuality = true
    local before = copyOf(CVARS)
    local fired = false
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if not fired and p and p.done >= 5 then
            fired = true
            COMBAT = true
            e.fire("PLAYER_REGEN_DISABLED")
        end
        return runCost(cv)
    end)[1]
    local during = entry ~= nil and entry.valid == false and entry.reason == "combat" and pendingOf(b) ~= nil
        and CVARS.graphicsShadowQuality ~= before.graphicsShadowQuality and e.ns.suspended == false
    COMBAT = false
    e.fire("PLAYER_REGEN_ENABLED")
    return during and restoredTo(before) and pendingOf(b) == nil, outText()
end)

test("B8-6 crash recovery: the restore message comes before the enforcement, and the forced value wins", function()
    local e = H.boot({ graphicsShadowQuality = "4", groundEffectDensity = "128" }, { fresh = true })
    local b = e.ns.bench
    b.state().pending = { time = 1, originals = { graphicsShadowQuality = "2", groundEffectDensity = "48" } }
    OUT = {}
    e.fire("PLAYER_ENTERING_WORLD")
    local restoreAt, enforceAt
    for i, l in ipairs(OUT) do
        if l:find("restored settings from an interrupted benchmark", 1, true) then restoreAt = restoreAt or i end
        if l:find("groundEffectDensity 48 -> 64", 1, true) then enforceAt = enforceAt or i end
    end
    return restoreAt ~= nil and enforceAt ~= nil and restoreAt < enforceAt and CVARS.graphicsShadowQuality == "2"
        and CVARS.groundEffectDensity == "64" and pendingOf(b) == nil, outText()
end)

test("B8-7 while a run is active, enforcement is suspended and /fset apply only says so", function()
    local e, b = newRun()
    local seen
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if p and p.label == "Ground clutter (raw) 48" and seen == nil then
            local before = CVARS.groundEffectDensity
            e.slash("apply")
            seen = { before = before, after = CVARS.groundEffectDensity }
        end
        return runCost(cv)
    end)[1]
    return seen ~= nil and seen.before == "48" and seen.after == "48" and has("benchmark running") and entry.valid, outText()
end)

-- Added in Task 9, after the mutation run showed B7-8 cannot see a broken final restore: the sweep restores
-- each setting it touched, so the end state was right even with the final restore disabled.
test("B7-8c a CVar moved as a side effect of a sweep is put back by the final restore", function()
    local e, b = newRun()
    DERIVED.graphicsSSAO = function(v, cv) cv.vsync = "1" end
    local before = copyOf(CVARS)
    local entry = doRun(e, b)[1]
    return entry and entry.valid and CVARS.vsync == "0" and restoredTo(before), outText()
end)

-- Added after the fresh review of the whole build (the review's findings, each seen failing first).
test("B4-2b master presets come first in the restore order", function()
    local _, b = newBench({})
    local o = b.restore.order({ "graphicsComputeEffects", "graphicsQuality", "RAIDgraphicsQuality", "giQuality" })
    return table.concat(o, ",") == "graphicsQuality,RAIDgraphicsQuality,graphicsComputeEffects,giQuality", table.concat(o, ",")
end)

test("B4-12 restore writes only the CVars whose value differs", function()
    local _, b = newBench({ graphicsSSAO = "3", vsync = "0", graphicsQuality = "6" })
    SETLOG = {}
    b.restore.apply({ graphicsSSAO = "3", vsync = "1", graphicsQuality = "6" })
    return #SETLOG == 1 and SETLOG[1] == "vsync" and CVARS.vsync == "1", table.concat(SETLOG, ",")
end)

test("B4-13 a master preset is written first, so re-applying it cannot clobber a sub-setting that was restored", function()
    local _, b = newBench({ graphicsQuality = "3", graphicsComputeEffects = "2" })
    DERIVED.graphicsQuality = function(v, cv) cv.graphicsComputeEffects = "5" end
    b.restore.apply({ graphicsQuality = "6", graphicsComputeEffects = "3" })
    return CVARS.graphicsQuality == "6" and CVARS.graphicsComputeEffects == "3", tostring(CVARS.graphicsComputeEffects)
end)

test("B3-14 probe puts back raw CVars that a menu-level CVar rewrites, not only the probed one", function()
    local _, b = newBench({ graphicsGroundClutter = "5", groundEffectDensity = "64" })
    DERIVED.graphicsGroundClutter = function(v, cv) cv.groundEffectDensity = "100" end
    local tiers = b.probe("graphicsGroundClutter")
    return tiers ~= nil and CVARS.graphicsGroundClutter == "5" and CVARS.groundEffectDensity == "64", tostring(CVARS.groundEffectDensity)
end)

test("B3-15 probe is refused while a benchmark is running and changes nothing", function()
    local e, b = newRun()
    b.run()
    e.pump(0.1, runCost)
    local before = copyOf(CVARS)
    local tiers, reason = b.probe("graphicsSSAO")
    return tiers == nil and reason == "a benchmark is running" and equalTables(copyOf(CVARS), before), tostring(reason)
end)

test("B3-16 probe refuses a raw CVar however its name is capitalised", function()
    local _, b = newBench({ RenderScale = "1" })
    local t1, r1 = b.probe("renderscale")
    local t2, r2 = b.probe("RENDERSCALE")
    return t1 == nil and r1 == "raw CVar: tiers are an explicit list" and t2 == nil and r2 == r1 and CVARS.RenderScale == "1", tostring(r1)
end)

test("B7-15 a slowdown that lasts past one setting makes the later rows inconclusive", function()
    local e, b = newRun()
    b.K.MIN_FRAMES = 5
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        local slow = (p and p.done >= 8) and 4 or 1       -- after the shadows setting the game runs four times slower
        return runCost(cv) * slow
    end, 120)[1]
    local ssao = entry and rowsOf(entry, "graphicsSSAO") or {}
    local shadows = entry and rowsOf(entry, "graphicsShadowQuality") or {}
    local allInconclusive = #ssao == 5
    for _, row in ipairs(ssao) do
        allInconclusive = allInconclusive and row.status == "inconclusive" and row.deltaMs == nil
            and row.reason:find("since the start", 1, true) ~= nil
    end
    return entry ~= nil and #shadows == 5 and shadows[1].deltaMs ~= nil and allInconclusive, outText()
end)

test("B7-16 the starting-tier row carries the flags of its two baselines", function()
    local e, b = newRun()
    b.guard.backgroundCap = function() return true end
    local entry = doRun(e, b)[1]
    local reused
    for _, row in ipairs(entry and rowsOf(entry, "graphicsShadowQuality") or {}) do
        if row.value == "2" then reused = row end
    end
    local flagged = false
    for _, f in ipairs(reused and reused.flags or {}) do
        if f == "possible background-window cap" then flagged = true end
    end
    return reused ~= nil and flagged
end)

test("B7-17 one step change of 8% is measured conclusively on the rerun, which compares with the bracket just taken", function()
    local e, b = newRun()
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        return runCost(cv) * ((p and p.done >= 4) and 1.08 or 1)
    end, 120)[1]
    local shadows = entry and rowsOf(entry, "graphicsShadowQuality") or {}
    local conclusive = #shadows == 5
    for _, row in ipairs(shadows) do conclusive = conclusive and row.status == nil and row.deltaMs ~= nil end
    return entry ~= nil and entry.reruns >= 1 and conclusive, outText()
end)

test("B7-18 each bracket puts back the whole snapshot, so a CVar an earlier sweep moved is not left moved", function()
    local e, b = newRun()
    DERIVED.graphicsSSAO = function(v, cv) cv.vsync = "1" end
    local seen
    doRun(e, b, function(cv)
        local p = b.progress()
        if p and seen == nil and p.label:find("Ground clutter (raw)", 1, true) == 1 then seen = CVARS.vsync end
        return runCost(cv)
    end)
    return seen == "0", tostring(seen)
end)

test("B7-19 an error in the run's final callback does not conclude the run twice", function()
    local e, b = newRun()
    b.run(function() error("boom") end)
    local ok = pcall(e.pump, 60, runCost)
    return ok and #b.history() == 1 and e.ns.suspended == false and b.active() == false, outText()
end)

test("B7-20 the snapshot includes the settings under test even when both CVar lists omit them", function()
    local e, b = newRun()
    _G.C_Console = { GetAllCommands = function() return { { command = "vsync" } } end }
    for i = #e.ns.knownCVars, 1, -1 do table.remove(e.ns.knownCVars, i) end
    local before = copyOf(CVARS)
    local fired = false
    b.run()
    e.pump(60, function(cv)
        local p = b.progress()
        if p and not fired and p.label == "Shadows 3" then
            fired = true
            b.stop()
        end
        return runCost(cv)
    end)
    local h = b.history()
    return fired and #h == 1 and h[1].valid == false and restoredTo(before), outText()
end)

test("T-P8-1 a full run and a mark each record the profile that was active", function()
    local e, b = newRun()
    local first = doRun(e, b)[1]
    e.ns.profiles.switch("crowded")
    local second = doRun(e, b)[1]
    b.mark("m")
    e.pump(15, runCost)
    local h = b.history()
    local marked = h[#h]
    return first ~= nil and first.profile == "everyday" and second ~= nil and second.profile == "crowded"
        and marked.label == "m" and marked.profile == "crowded", tostring(first and first.profile) .. " / " .. tostring(second and second.profile)
end)

test("B8-9 /fset reset during a run is refused and the saved originals survive", function()
    local e, b = newRun()
    CVARS.groundEffectDensity = "128"
    e.fire("PLAYER_ENTERING_WORLD")                       -- enforcement forces 64 and records 128 as the original
    local fired = false
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if p and not fired and p.label == "Shadows 3" then
            fired = true
            e.slash("reset")
        end
        return runCost(cv)
    end)[1]
    local db = e.ns.db()
    return fired and entry ~= nil and entry.valid and db.want.groundEffectDensity == "64" and db.original.values.groundEffectDensity == "64"
        and CVARS.groundEffectDensity == "64" and has("benchmark running"), outText()
end)

-- Task 12: the client has no console list (the real Forever client failed the C_Console.GetAllCommands probe),
-- so the snapshot comes from the built-in list of names.
test("T12-1 a full run with no console list puts back every guarded CVar, including raw ones a write rewrites", function()
    local cv = runCvars()
    cv.shadowTextureSize = "2048"
    local e, b = newRun(cv, { console = "none" })
    DERIVED.graphicsShadowQuality = function(_, all) all.shadowTextureSize = "512" end
    local before = copyOf(CVARS)
    local entry = doRun(e, b)[1]
    return entry ~= nil and entry.valid == true and restoredTo(before) and CVARS.shadowTextureSize == "2048", outText()
end)

test("T12-2 the built-in list has unique guarded names and covers every CVar the settings table measures", function()
    local e, b = newBench({})
    local seen, problems = {}, {}
    for _, name in ipairs(e.ns.knownCVars) do
        local key = name:lower()
        if seen[key] then problems[#problems + 1] = "duplicate " .. name end
        seen[key] = true
        if not b.restore.isGuarded(name) then problems[#problems + 1] = "not guarded " .. name end
    end
    for _, row in ipairs(b.SETTINGS) do
        for _, cvar in ipairs(row.cvars) do
            if not seen[cvar:lower()] then problems[#problems + 1] = "missing " .. cvar end
        end
    end
    for _, extra in ipairs({ "graphicsQuality", "RAIDgraphicsQuality", "useMaxFPS", "maxFPS", "vsync", "RenderScale" }) do
        if not seen[extra:lower()] then problems[#problems + 1] = "missing " .. extra end
    end
    return #problems == 0 and #e.ns.knownCVars >= 100, table.concat(problems, "; ") .. " (" .. #e.ns.knownCVars .. " names)"
end)

test("T12-3 check works when the client has no console list, and its output names the built-in list", function()
    local e, b = newBench(checkCvars(), { console = "none" })
    local before = copyOf(CVARS)
    local r = runCheck(e, b)[1]
    return r ~= nil and r.ok == true and has("PASS CVar list") and has("built-in") and not has("FAIL") and restoredTo(before)
        and pendingOf(b) == nil, outText()
end)

test("T12-4 probe with no console list still puts back a raw CVar that the write rewrote", function()
    local _, b = newBench({ graphicsShadowQuality = "2", shadowTextureSize = "2048", vsync = "0" }, { console = "none" })
    DERIVED.graphicsShadowQuality = function(_, all) all.shadowTextureSize = "512" end
    local tiers = b.probe("graphicsShadowQuality")
    return tiers ~= nil and CVARS.graphicsShadowQuality == "2" and CVARS.shadowTextureSize == "2048", outText()
end)

-- Task 13: the owner's first real `check` (flagged by the screenshot): PASS lines carried the text meant for a
-- failure, and a failed check gave no evidence of why (spread 38%, control 4 times slower).
test("T13-1 a PASS line shows no explanation unless the check has a note, and a FAIL line shows its own", function()
    local e, b = newBench(checkCvars())
    runCheck(e, b)
    local passWithText
    for _, l in ipairs(OUT) do
        if l:find("environment: PASS", 1, true) and l:find("(", 1, true) then passWithText = l end
    end
    OUT = {}
    local e2, b2 = newBench(checkCvars(), { nounitspeed = true })
    b2.check()
    return passWithText == nil and has("environment: FAIL GetUnitSpeed (the movement guard needs it)"), tostring(passWithText) .. " / " .. outText()
end)

test("T13-2 perSecond: mean frame time of each whole second, a frame counting in the second it starts", function()
    local _, b = newBench({})
    local s = b.stats
    local a = s.perSecond({ 0.25, 0.25, 0.25, 0.25, 0.5, 0.5, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1 })
    local c = s.perSecond({ 0.5, 0.5, 0.5, 0.5 })
    local empty = s.perSecond({})
    return #a == 3 and near(a[1], 250, 1e-6) and near(a[2], 500, 1e-6) and near(a[3], 100, 1e-6)
        and #c == 2 and near(c[1], 500, 1e-6) and near(c[2], 500, 1e-6) and #empty == 0,
        #a .. " / " .. #c .. " / " .. #empty
end)

-- A frame time that is slow for the first `slowSeconds` of frame time, then fast.
local function slowThenFast(slow, fast, slowSeconds)
    local acc = 0
    return function()
        local dt = acc < slowSeconds and slow or fast
        acc = acc + dt
        return dt
    end
end

test("T13-3 a window result carries the mean of its settle period and the per-second means of its measure period", function()
    local e, b = newBench({})
    local results = startWindow(b)
    e.pump(11.5, slowThenFast(0.020, 0.010, 3.0))
    local r = results[1]
    local okSeconds = r ~= nil and #r.seconds == 8
    if okSeconds then
        for _, ms in ipairs(r.seconds) do okSeconds = okSeconds and near(ms, 10.0, 0.05) end
    end
    return r ~= nil and r.ok and okSeconds and near(r.settleMs, 20.0, 0.2), r and tostring(r.settleMs) or "no result"
end)

test("T13-4 a stall restarts the settle period, so the settle mean comes only from the second attempt", function()
    local e, b = newBench({})
    local results = startWindow(b)
    local acc, stalled = 0, false
    e.pump(25, function()
        local dt
        if acc < 3.0 then dt = 0.020
        elseif not stalled then stalled = true dt = 1.5
        else dt = 0.010 end
        acc = acc + dt
        return dt
    end)
    local r = results[1]
    return r ~= nil and r.ok and r.retried == true and near(r.settleMs, 10.0, 0.2), r and tostring(r.settleMs) or "no result"
end)

test("T13-5 check prints each window's evidence: frames, slowest frame, hitches, settle mean, per-second means", function()
    local e, b = newBench(checkCvars())
    runCheck(e, b)
    local same8 = "by second: 8.0 8.0 8.0 8.0 8.0 8.0 8.0 8.0"
    local same7 = "by second: 7.0 7.0 7.0 7.0 7.0 7.0 7.0 7.0"
    return has("baseline window 1: 8.00 ms over") and has("baseline window 3: ") and has(same8)
        and has("control window: 7.00 ms over") and has(same7) and has("slowest 8 ms, 0 over 50 ms") and has("settle 8.0 ms"),
        outText()
end)

-- Guide (Task 4): the optional watch hook in the movement poll
test("BW-1 a watch hook that names a reason ends the run with it, and everything is put back", function()
    local e, b = newRun()
    local before = copyOf(CVARS)
    local on = false
    b.watch = function() return on and "panel:menu" or nil end
    local entry = doRun(e, b, function(cv)
        local p = b.progress()
        if p and not on and p.label == "Shadows 3" then on = true end
        return runCost(cv)
    end)[1]
    return entry ~= nil and entry.valid == false and entry.reason == "panel:menu" and restoredTo(before)
        and e.ns.suspended == false and b.active() == false, outText()
end)

test("BW-2 with no watch hook a run completes as before", function()
    local e, b = newRun()
    local entry = doRun(e, b)[1]
    return b.watch == nil and entry ~= nil and entry.valid == true
end)

test("BW-3 a watch hook that raises an error does not stop the run and nothing escapes", function()
    local e, b = newRun()
    b.watch = function() error("boom") end
    local ok, results = pcall(doRun, e, b)
    return ok and results[1] ~= nil and results[1].valid == true, tostring(results)
end)

test("BW-4 the hook also stops a window during its settle phase", function()
    local e, b = newRun()
    b.K.SETTLE = 3.0                         -- long enough that the first poll (0.25 s) falls inside the settle period
    local acc, firstAt = 0, nil
    b.watch = function()
        firstAt = firstAt or acc
        return "panel:map"
    end
    local entry = doRun(e, b, function(cv)
        local dt = runCost(cv)
        acc = acc + dt
        return dt
    end, 60)[1]
    return entry ~= nil and entry.valid == false and entry.reason == "panel:map" and entry.windows == 0
        and firstAt ~= nil and firstAt < 3.0, tostring(firstAt) .. " / " .. outText()
end)

-- Adaptive settle (owner's first live run: the first baseline read 4.75 ms against 3.4 to 3.8 ms for every later one, and
-- Ground clutter and Render scale were still reloading when their closing baselines were taken). A window keeps settling
-- while the frame time still moves, up to a cap, instead of always stopping after K.SETTLE.
local function settleRun(costFor, tune)
    local e, b = newBench({ vsync = "0" })
    b.K.SETTLE, b.K.SETTLE_SLICE, b.K.SETTLE_MAX, b.K.SETTLE_STEADY = 0.4, 0.1, 3.0, 0.10
    b.K.MEASURE, b.K.MIN_FRAMES = 0.4, 20
    if tune then tune(b.K) end
    local t, result = 0, nil
    b.runWindow(function(r) result = r end)
    local function cost()
        local dt = costFor(t)
        t = t + dt
        return dt
    end
    local rounds = 0
    while result == nil and rounds < 400 do
        e.pump(0.05, cost)
        rounds = rounds + 1
    end
    return result, t
end

test("BS-1 a window that starts slow and settles is measured only once the frame time has stopped moving", function()
    -- the frame time falls from 220 ms to 20 ms over the first 0.8 s, then holds at 5 ms
    local r, took = settleRun(function(t)
        if t < 0.8 then return 0.02 + 0.2 * (0.8 - t) / 0.8 end
        return 0.005
    end)
    -- Settled about 0.2 s after the slow part, then 0.4 s of measuring: well short of the 3 s cap.
    return r ~= nil and r.ok == true and near(r.summary.meanMs, 5.0, 0.3) and took <= 2.0,
        (r and r.ok and tostring(r.summary.meanMs) or tostring(r and r.reason)) .. " took " .. tostring(took)
end)

test("BS-2 a window whose frame time never settles stops settling at the cap and is measured anyway", function()
    -- the frame time grows 15% every slice for ever: never steady
    local r, took = settleRun(function(t) return 0.004 * 1.15 ^ (t / 0.1) end, function(K) K.MIN_FRAMES = 1 end)
    -- frames are about 0.3 s long by the cap, so the boundaries can overshoot by a frame each
    return r ~= nil and took >= 3.0 and took <= 4.5, tostring(took) .. " " .. tostring(r and r.reason)
end)

test("BS-3 a window that is steady from the start settles in K.SETTLE and no longer", function()
    local r, took = settleRun(function() return 0.005 end)
    return r ~= nil and r.ok == true and took >= 0.79 and took <= 0.86 and near(r.settleMs, 5.0, 0.3),
        tostring(took) .. " " .. tostring(r and r.settleMs)
end)

-- Recommender, Task 4 (plan 2026-10-29-recommender.md): the current-level flag, learning levels, the setup estimate
test("BL-1 the row of the player's own level carries current = true, one per setting, and no measured row does", function()
    local e, b = newRun()
    local start = copyOf(CVARS)
    local entry = doRun(e, b)[1]
    -- One flagged row per setting, and it is the one at the starting value: a measured row that was flagged too would
    -- raise a count above one or show a different value.
    local count, wrongValue = {}, {}
    for _, row in ipairs(entry and entry.rows or {}) do
        if row.current then
            count[row.cvar] = (count[row.cvar] or 0) + 1
            if not b.sameValue(row.value, start[row.cvar]) then wrongValue[#wrongValue + 1] = row.cvar end
        end
    end
    local settings, allOne = 0, true
    for _, n in pairs(count) do
        settings = settings + 1
        if n ~= 1 then allOne = false end
    end
    return entry ~= nil and settings == 4 and allOne and #wrongValue == 0
        and count.graphicsShadowQuality == 1 and count.RenderScale == 1, tostring(settings) .. " " .. table.concat(wrongValue, ",")
end)

test("BL-7 a run records every setting's starting value, also one that is not a measured level, and flags no row for it", function()
    local cv = runCvars()
    cv.RenderScale = "0.75"
    local e, b = newRun(cv)
    local entry = doRun(e, b)[1]
    local scale, flagged = 0, 0
    for _, row in ipairs(entry and entry.rows or {}) do
        if row.cvar == "RenderScale" then
            scale = scale + 1
            if row.current then flagged = flagged + 1 end
        end
    end
    return entry ~= nil and entry.valid == true and entry.starts ~= nil and entry.starts.RenderScale == "0.75"
        and entry.starts.graphicsShadowQuality == "2" and entry.starts.graphicsSSAO == "1"
        and entry.starts.groundEffectDensity == "64" and scale == 6 and flagged == 0,
        tostring(entry and entry.starts and entry.starts.RenderScale) .. " " .. scale .. " " .. flagged
end)

test("BL-2 learn probes the settings whose levels are unknown, in table order, and never the raw ones or absent ones", function()
    local _, b = newBench({ graphicsSSAO = "2", graphicsShadowQuality = "4", graphicsLiquidDetail = "1", RenderScale = "1",
        groundEffectDensity = "64" })
    DERIVED.graphicsSSAO = function(v, cv) if tonumber(v) > 3 then cv.graphicsSSAO = "3" end end
    SETLOG = {}
    local result, why = b.learn()
    local allowed = { graphicsShadowQuality = true, graphicsSSAO = true, graphicsLiquidDetail = true }
    local stray = {}
    for _, name in ipairs(SETLOG) do
        if not allowed[name] then stray[#stray + 1] = name end
    end
    return result ~= nil and table.concat(result.learned, ",") == "graphicsShadowQuality,graphicsSSAO,graphicsLiquidDetail"
        and #result.failed == 0 and table.concat(b.state().tiers.graphicsSSAO, ",") == "0,1,2,3" and #stray == 0,
        tostring(why) .. " stray " .. table.concat(stray, ",")
end)

test("BL-3 a setting that cannot be learned is reported and the rest are still learned; known levels are not probed again", function()
    local _, b = newBench({ graphicsSSAO = "99", graphicsShadowQuality = "4", graphicsLiquidDetail = "1" })
    SETFAIL.graphicsSSAO = "clamp"
    b.state().tiers.graphicsLiquidDetail = { "0", "1", "2" }
    SETLOG = {}
    local result = b.learn()
    local probedLiquid = false
    for _, name in ipairs(SETLOG) do
        if name == "graphicsLiquidDetail" then probedLiquid = true end
    end
    return result ~= nil and table.concat(result.learned, ",") == "graphicsShadowQuality"
        and #result.failed == 1 and result.failed[1].cvar == "graphicsSSAO" and result.failed[1].reason == "no value read back"
        and not probedLiquid and table.concat(b.state().tiers.graphicsLiquidDetail, ",") == "0,1,2",
        tostring(result and #result.failed)
end)

test("BL-4 learn is refused in combat and while a benchmark is active, and changes nothing", function()
    local _, b = newBench({ graphicsSSAO = "2", graphicsShadowQuality = "4" })
    COMBAT = true
    SETLOG = {}
    local r1, why1 = b.learn()
    local quiet1 = #SETLOG == 0
    COMBAT = false
    local e2, b2 = newRun()
    b2.run()
    e2.pump(0.3, runCost)
    SETLOG = {}
    local r2, why2 = b2.learn()
    return r1 == nil and why1 == "in combat" and quiet1 and r2 == nil and why2 == "a benchmark is running" and #SETLOG == 0,
        tostring(why1) .. " / " .. tostring(why2)
end)

test("BL-5 every CVar holds its starting value after learn", function()
    local _, b = newBench({ graphicsSSAO = "2", graphicsShadowQuality = "4", graphicsLiquidDetail = "1", RenderScale = "1" })
    local before = copyOf(CVARS)
    b.learn()
    local bad = {}
    for k, v in pairs(before) do
        if CVARS[k] ~= v then bad[#bad + 1] = k .. "=" .. tostring(CVARS[k]) end
    end
    return #bad == 0, table.concat(bad, ",")
end)

test("BL-6 the setup estimate counts a setting that is not learned yet as five windows", function()
    local _, b = newBench({ graphicsShadowQuality = "2", graphicsSSAO = "2", graphicsLiquidDetail = "1" })
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    local resolved, currents = b.resolve(), { graphicsShadowQuality = "2", graphicsSSAO = "2" }
    local known = b.countWindows(resolved, currents)
    return known == 13 and b.estimateSetupWindows() == 18, tostring(b.estimateSetupWindows())
end)

-- Crowd test, Task 2: the quick levels of the quiet-spot test (spec 2026-10-29-crowd-test-design.md section 4.1)
local function listOf(b, tiers, current, mode)
    return table.concat(b.tiersToMeasure({ tiers = tiers }, current, mode), ",")
end

test("BQ-1 a quick sweep measures the lowest level and one middle level, never the current one; small settings are measured fully", function()
    local _, b = newBench({ RenderScale = "1" })
    local five = { "0", "1", "2", "3", "4" }
    return listOf(b, five, "2", "quick") == "0,1" and listOf(b, five, "4", "quick") == "0,2"
        and listOf(b, five, "0", "quick") == "2" and listOf(b, five, "1", "quick") == "0,2"
        and listOf(b, { "48", "64", "128" }, "64", "quick") == "48,128" and listOf(b, { "0", "1" }, "1", "quick") == "0"
        and listOf(b, { "0", "1", "2", "3" }, "1", "quick") == "0,2"
        and listOf(b, five, "2", "all") == "0,1,3,4" and listOf(b, five, "2") == "0,1,3,4",
        listOf(b, five, "2", "quick") .. " / " .. listOf(b, five, "4", "quick") .. " / " .. listOf(b, five, "0", "quick")
end)

test("BQ-2 the window count follows the mode: sweep windows, one baseline more than settings, two control windows", function()
    local _, b = newBench({ RenderScale = "1" })
    local resolved, currents = {}, {}
    for i = 1, 7 do
        resolved[i] = { cvar = "c" .. i, tiers = { "0", "1", "2", "3", "4" } }
        currents["c" .. i] = "2"
    end
    return b.countWindows(resolved, currents) == 38 and b.countWindows(resolved, currents, "all") == 38
        and b.countWindows(resolved, currents, "quick") == 24, tostring(b.countWindows(resolved, currents, "quick"))
end)

test("BQ-3 the setup estimate follows the mode, and an unlearned setting counts three windows in quick", function()
    local _, b = newBench({ graphicsShadowQuality = "2", graphicsSSAO = "2", graphicsLiquidDetail = "1" })
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    return b.K.ASSUMED_QUICK == 3 and b.estimateSetupWindows("quick") == 12 and b.estimateSetupWindows("all") == 18
        and b.estimateSetupWindows() == 18, tostring(b.estimateSetupWindows("quick"))
end)

local function doRunWith(e, b, opts, costFn, seconds)
    local results = {}
    b.run(function(r) results[#results + 1] = r end, opts)
    e.pump(seconds or 60, costFn or runCost)
    return results
end
local function valuesOf(entry, cvar)
    local list = {}
    for _, row in ipairs(rowsOf(entry, cvar)) do list[#list + 1] = row.value end
    return table.concat(list, ",")
end

test("BQ-4 a quick run measures only the quick levels and the current one, in fewer windows, and records its kind and mode", function()
    local e, b = newRun()
    local quick = doRunWith(e, b, { levels = "quick", kind = "setup" })[1]
    local e2, b2 = newRun()
    local full = doRunWith(e2, b2, nil)[1]
    local resolved = b.resolve()
    local currents = {}
    for _, entry in ipairs(resolved) do currents[entry.cvar] = GetCVar(entry.cvar) end
    return quick and quick.valid and quick.mode == "quick" and quick.kind == "setup" and quick.reruns == 0
        and valuesOf(quick, "graphicsShadowQuality") == "0,1,2" and valuesOf(quick, "graphicsSSAO") == "0,1,2"
        and quick.windows == b.countWindows(resolved, currents, "quick") and quick.windows < full.windows
        and valuesOf(full, "graphicsShadowQuality") == "0,1,2,3,4",
        tostring(quick and quick.windows) .. " vs " .. tostring(full and full.windows) .. " " .. valuesOf(quick, "graphicsShadowQuality")
end)

test("BQ-6 the progress total of a quick run is the quick window count, not the full one", function()
    local e, b = newRun()
    b.run(nil, { levels = "quick" })
    e.pump(0.3, runCost)
    local p = b.progress()
    local resolved = b.resolve()
    local currents = {}
    for _, entry in ipairs(resolved) do currents[entry.cvar] = GetCVar(entry.cvar) end
    local quick, full = b.countWindows(resolved, currents, "quick"), b.countWindows(resolved, currents, "all")
    e.pump(60, runCost)
    return p ~= nil and p.total == quick and quick < full, tostring(p and p.total) .. " / " .. quick .. " / " .. full
end)

test("BQ-5 an ordinary run records the full mode and the run kind", function()
    local e, b = newRun()
    local entry = doRunWith(e, b, nil)[1]
    return entry and entry.valid and entry.mode == "all" and entry.kind == "run", tostring(entry and entry.mode) .. tostring(entry and entry.kind)
end)

-- A quiet guided test (results window, Task 1): spec 2026-10-30-results-window-design.md section 3.1
local function contains(text, sub) return text:find(sub, 1, true) ~= nil end
local VSYNC = "Vsync is on, so your frame rate is capped at your screen's refresh rate and the test cannot see what settings cost. "
    .. "Turn vsync off in the game's graphics options and run the test again."
local FPSCAP = "A frame-rate limit is set in the game, so the test cannot see what settings cost above that limit. "
    .. "Raise or remove the limit and run the test again."
local RECOVERED = "Settings from an interrupted test were put back first."

test("QT-1 a silent run prints nothing at all; the same run not silent prints the environment, the tip and the report", function()
    local e, b = newRun()
    local quiet = doRunWith(e, b, { levels = "quick", kind = "setup", silent = true })[1]
    local quietText = outText()
    local e2, b2 = newRun()
    local loud = doRunWith(e2, b2, { levels = "quick", kind = "setup" })[1]
    local loudText = outText()
    return quiet and quiet.valid == true and quietText == "" and loud and loud.valid == true
        and contains(loudText, "environment: PASS") and contains(loudText, "close browsers, streaming and VR software before measuring")
        and contains(loudText, "Benchmark at") and contains(loudText, "graphicsShadowQuality"), quietText
end)

test("QT-2 a refusal of a silent run still reaches its caller as a reason and problems, and prints nothing; not silent it prints", function()
    local e, b = newRun()
    COMBAT = true
    local r = doRunWith(e, b, { silent = true })[1]
    local quietText = outText()
    local e2, b2 = newRun()
    COMBAT = true
    local r2 = doRunWith(e2, b2, nil)[1]
    local loudText = outText()
    local e3, b3 = newBench({ vsync = "0", graphicsSSAO = "3" })            -- no resolvable setting: nothing to measure
    shrink(b3)
    local flat = function() return 0.008 end
    local r3 = doRunWith(e3, b3, { silent = true }, flat, 2)[1]
    local noneText = outText()
    local e4, b4 = newBench({ vsync = "0", graphicsSSAO = "3" })
    shrink(b4)
    local r4 = doRunWith(e4, b4, nil, flat, 2)[1]
    return r and r.ok == false and r.reason == "preflight" and #r.problems > 0 and quietText == ""
        and r2 and r2.reason == "preflight" and contains(loudText, "cannot run")
        and r3 and r3.reason == "nothing to measure" and noneText == "" and r4 and contains(outText(), "nothing to measure"),
        tostring(r and r.reason) .. "/" .. tostring(r2 and r2.reason) .. "/" .. tostring(r3 and r3.reason) .. "/" .. tostring(r4 and r4.reason)
            .. " [" .. quietText .. "] [" .. noneText .. "]"
end)

test("QT-3 a silent run stopped by movement prints no 'run stopped' and keeps its reason; not silent it prints it", function()
    local function stopped(opts)
        local e, b = newRun()
        b.K.POLL = 0.05
        local entry = doRunWith(e, b, opts, function(cv)
            local p = b.progress()
            if p and p.done >= 6 then SPEED = 7 end
            return runCost(cv)
        end)[1]
        return entry, outText()
    end
    local quietEntry, quietText = stopped({ silent = true })
    local loudEntry, loudText = stopped(nil)
    return quietEntry and quietEntry.valid == false and quietEntry.reason == "movement" and not contains(quietText, "run stopped")
        and loudEntry and loudEntry.reason == "movement" and contains(loudText, "run stopped: movement"), quietText
end)

test("QT-4 combat during a silent run still says the restore waits for combat to end", function()
    local e, b = newRun()
    LOCKED.graphicsShadowQuality = true
    local fired = false
    local entry = doRunWith(e, b, { silent = true }, function(cv)
        local p = b.progress()
        if not fired and p and p.done >= 5 then
            fired = true
            COMBAT = true
            e.fire("PLAYER_REGEN_DISABLED")
        end
        return runCost(cv)
    end)[1]
    local text = outText()
    COMBAT = false
    e.fire("PLAYER_REGEN_ENABLED")
    return entry and entry.valid == false and entry.reason == "combat"
        and contains(text, "in combat: your settings will be restored when combat ends") and not contains(text, "run stopped"), text
end)

test("QT-5 the three warnings are in plain words, reach the player even in a silent run, and name no setting", function()
    local function warned(change, setup)
        local cv = runCvars()
        for k, v in pairs(change) do cv[k] = v end
        local e, b = newRun(cv)
        if setup then setup(b) end
        local entry = doRunWith(e, b, { levels = "quick", kind = "setup", silent = true })[1]
        return entry, outText()
    end
    local _, vsync = warned({ vsync = "1" })
    local _, cap = warned({ useMaxFPS = "1" })
    local _, recovered = warned({}, function(b)
        b.state().pending = { time = 1, originals = { graphicsSSAO = "1" } }
    end)
    local _, none = warned({})
    local clean = true
    for _, text in ipairs({ vsync, cap, recovered }) do
        clean = clean and not contains(text, "useMaxFPS") and not contains(text, "maxFPS") and not contains(text, "vsync is on:")
            and not contains(text, "FPS cap")
    end
    return contains(vsync, VSYNC) and contains(cap, FPSCAP) and contains(recovered, RECOVERED) and clean and none == "",
        vsync .. " / " .. cap .. " / " .. recovered
end)

test("QT-6 the words of the warnings are the ones in the list preflight returns", function()
    local function warningsFor(extra)
        local cv = runCvars()
        for k, v in pairs(extra) do cv[k] = v end
        local _, b = newBench(cv)
        local ok, _, warnings = b.preflight()
        return ok, warnings
    end
    local okV, wV = warningsFor({ vsync = "1" })
    local okM, wM = warningsFor({ maxFPS = "200" })
    return okV and wV[1] == VSYNC and okM and wM[1] == FPSCAP
end)

return H.results()
