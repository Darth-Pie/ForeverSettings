-- Tests for the crowd test and the check of a recommendation (bench.crowd, bench.verify in Bench.lua;
-- spec 2026-10-29-crowd-test-design.md sections 4.2 and 4.3), driven through the shared harness.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function near(x, y, tol) return math.abs(x - y) <= (tol or 1e-6) end
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
local function copyOf(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

-- The fake game's frame time is 2 ms + 4 ms x RenderScale + 0.5 ms x shadow tier, so every delta has a known answer:
-- with runCvars() the baseline is 7.0 ms, Shadows at 0 saves 1.0 ms, RenderScale at 0.5 saves 2.0 ms, and neither SSAO
-- nor ground effect density change anything.
local function shrink(b)
    b.K.SETTLE, b.K.MEASURE, b.K.MIN_FRAMES = 0.05, 0.2, 20
end
local function runCvars()
    return { RenderScale = "1", graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64", vsync = "0" }
end
local function newRun(cvars)
    local e, b = newBench(cvars or runCvars())
    shrink(b)
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    return e, b
end
local function runCost(cv)
    return 0.002 + 0.004 * tonumber(cv.RenderScale) + 0.0005 * tonumber(cv.graphicsShadowQuality)
end

-- A finished quiet-spot entry for the fixture above: each setting has its lowest level and its current level.
local function qrow(cvar, label, value, delta, current)
    return { setting = label, cvar = cvar, value = value, meanMs = 7.0 + delta, deltaMs = delta, flags = {}, current = current or nil }
end
local function quietEntry(skipRenderScale)
    local rows = {}
    local function add(r) rows[#rows + 1] = r end
    if not skipRenderScale then
        add(qrow("RenderScale", "Render scale", "0.5", -2.0))
        add(qrow("RenderScale", "Render scale", "1", 0, true))
    else
        add(qrow("RenderScale", "Render scale", "1", 0, true))
    end
    add(qrow("graphicsShadowQuality", "Shadows", "0", -1.0))
    add(qrow("graphicsShadowQuality", "Shadows", "1", -0.4))
    add(qrow("graphicsShadowQuality", "Shadows", "2", 0, true))
    add(qrow("graphicsSSAO", "SSAO", "0", -0.1))
    add(qrow("graphicsSSAO", "SSAO", "1", 0, true))
    add(qrow("groundEffectDensity", "Ground effect density", "48", -0.1))
    add(qrow("groundEffectDensity", "Ground effect density", "64", 0, true))
    return { valid = true, baselineMs = 7.0, rows = rows, kind = "setup", mode = "quick",
        starts = { RenderScale = "1", graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64" } }
end
local function doCrowd(e, b, quiet, costFn, seconds)
    local results = {}
    b.crowd(quiet, function(r) results[#results + 1] = r end)
    e.pump(seconds or 60, costFn or runCost)
    return results
end
local function byCvar(entry)
    local map = {}
    for _, s in ipairs(entry.settings or {}) do map[s.cvar] = s end
    return map
end
local FOUR = { RenderScale = true, graphicsShadowQuality = true, graphicsSSAO = true, groundEffectDensity = true }
local function orderOf(b, wanted)
    local order = {}
    for _, entry in ipairs(b.resolve()) do
        if wanted[entry.cvar] then order[#order + 1] = entry.cvar end
    end
    return order
end
local function cvarsOf(entry)
    local list = {}
    for i, s in ipairs(entry.settings) do list[i] = s.cvar end
    return table.concat(list, ",")
end

test("CB-1 the crowd test measures a baseline and then a pair for each setting the quiet test measured, in table order", function()
    local e, b = newRun()
    local quiet = quietEntry()
    local entry = doCrowd(e, b, quiet)[1]
    local want = orderOf(b, FOUR)
    local lows = byCvar(entry or { settings = {} })
    return entry and entry.valid == true and entry.kind == "crowd" and #entry.rows == 0 and #entry.settings == 4
        and cvarsOf(entry) == table.concat(want, ",") and entry.windows == 9 and b.estimateCrowdWindows(quiet) == 9
        and lows.RenderScale.lowValue == "0.5" and lows.graphicsShadowQuality.lowValue == "0" and lows.graphicsSSAO.lowValue == "0"
        and lows.groundEffectDensity.lowValue == "48" and near(entry.baselineMs, 7.0, 0.1)
        and entry.starts.graphicsShadowQuality == "2", outText()
end)

test("CB-1b a setting whose quiet rows hold nothing below its live level is not measured, and a quiet entry with none is refused", function()
    local e, b = newRun()
    local quiet = quietEntry(true)
    local entry = doCrowd(e, b, quiet)[1]
    local e2, b2 = newRun()
    local bare = { valid = true, baselineMs = 7.0, rows = { qrow("RenderScale", "Render scale", "1", 0, true) } }
    SETLOG = {}
    local refused = doCrowd(e2, b2, bare)[1]
    return entry and entry.valid and #entry.settings == 3 and entry.windows == 7 and b.estimateCrowdWindows(quiet) == 7
        and byCvar(entry).RenderScale == nil
        and refused and refused.ok == false and refused.reason == "nothing to measure" and #SETLOG == 0 and b2.estimateCrowdWindows(bare) == 0,
        outText()
end)

test("CB-2 each setting's saving is its lowest-level window against the mean of the baselines around it", function()
    local e, b = newRun()
    local entry = doCrowd(e, b, quietEntry())[1]
    local by = byCvar(entry)
    return entry.valid and near(by.graphicsShadowQuality.lowDelta, -1.0, 0.1) and near(by.RenderScale.lowDelta, -2.0, 0.1)
        and near(by.graphicsSSAO.lowDelta, 0, 0.1) and near(by.groundEffectDensity.lowDelta, 0, 0.1)
        and near(by.RenderScale.baseMs, 7.0, 0.1) and by.RenderScale.status == nil and by.RenderScale.drift < 0.05,
        tostring(by.graphicsShadowQuality.lowDelta) .. " " .. tostring(by.RenderScale.lowDelta)
end)

test("CB-2b the saving is taken against the mean of the baselines before and after, not either one alone", function()
    local e, b = newRun()
    -- the second window after the first baseline (the baseline after the first setting) reads 12% slow, then normal
    local entry = doCrowd(e, b, quietEntry(), function(cv)
        local p = b.progress()
        return runCost(cv) * ((p and p.done == 2) and 1.12 or 1)
    end)[1]
    local saving = { RenderScale = 2.0, graphicsShadowQuality = 1.0, graphicsSSAO = 0, groundEffectDensity = 0 }
    local first, second = entry.settings[1], entry.settings[2]
    return entry.valid and entry.reruns == 0 and near(first.lowDelta, -saving[first.cvar] - 0.42, 0.06)
        and near(second.lowDelta, -saving[second.cvar] - 0.42, 0.06) and near(first.drift, 0.12, 0.01),
        tostring(first.lowDelta) .. " " .. tostring(second.lowDelta) .. " " .. tostring(first.drift)
end)

test("CB-3 every setting is put back before the next baseline, and everything holds its starting value at the end", function()
    local e, b = newRun()
    local before = copyOf(CVARS)
    SETLOG = {}
    local entry = doCrowd(e, b, quietEntry())[1]
    local want = {}
    for _, cvar in ipairs(orderOf(b, FOUR)) do want[#want + 1] = cvar .. "," .. cvar end
    local same = true
    for k, v in pairs(before) do if CVARS[k] ~= v then same = false end end
    return entry.valid and table.concat(SETLOG, ",") == table.concat(want, ",") and same and e.ns.suspended == false
        and b.active() == false and b.state().pending == nil, table.concat(SETLOG, ",")
end)

test("CB-4 a ten per cent step is accepted in a crowd and makes the quiet-spot test repeat a setting", function()
    local e, b = newRun()
    local entry = doCrowd(e, b, quietEntry(), function(cv)
        local p = b.progress()
        return runCost(cv) * ((p and p.done >= 3) and 1.10 or 1)
    end)[1]
    local statuses = 0
    for _, s in ipairs(entry.settings) do if s.status then statuses = statuses + 1 end end
    local e2, b2 = newRun()
    local quiet = {}
    b2.run(function(r) quiet[#quiet + 1] = r end)
    e2.pump(60, function(cv)
        local p = b2.progress()
        return runCost(cv) * ((p and p.done >= 3) and 1.10 or 1)
    end)
    return entry.valid and entry.reruns == 0 and statuses == 0 and entry.windows == 9 and quiet[1] and quiet[1].reruns >= 1,
        tostring(entry.reruns) .. " / " .. tostring(quiet[1] and quiet[1].reruns)
end)

test("CB-5 a twenty per cent step repeats that pair once; a baseline that never settles leaves its settings inconclusive", function()
    local e, b = newRun()
    local entry = doCrowd(e, b, quietEntry(), function(cv)
        local p = b.progress()
        return runCost(cv) * ((p and p.done >= 3) and 1.20 or 1)
    end)[1]
    local statuses = 0
    for _, s in ipairs(entry.settings) do if s.status then statuses = statuses + 1 end end
    local e2, b2 = newRun()
    b2.K.MIN_FRAMES = 2
    local bad = doCrowd(e2, b2, quietEntry(), function(cv)
        local p = b2.progress()
        return runCost(cv) * (1.3 ^ math.min(p and p.done or 0, 5))
    end, 120)[1]
    local first = bad and bad.settings[1]
    return entry.valid and entry.reruns == 1 and entry.windows == 11 and statuses == 0
        and bad and bad.valid == true and bad.reruns >= 1 and first.status == "inconclusive" and first.lowDelta == nil
        and first.reason:find("inconclusive", 1, true) ~= nil, tostring(entry.reruns) .. " " .. tostring(entry.windows) .. " / " .. tostring(first and first.status)
end)

test("CB-11 a repeated pair adds its two windows to the progress total, so the count never passes the total and ends equal to it", function()
    local e, b = newRun()
    local startTotal, lastTotal, over, firstRepeats, lastRepeats
    local entry = doCrowd(e, b, quietEntry(), function(cv)
        local p = b.progress()
        if p then
            startTotal = startTotal or p.total
            lastTotal = p.total
            firstRepeats = firstRepeats or p.repeats
            lastRepeats = p.repeats
            if p.done > p.total then over = "done " .. p.done .. " of " .. p.total end
        end
        return runCost(cv) * ((p and p.done >= 3) and 1.20 or 1)
    end)[1]
    return entry.valid and entry.reruns == 1 and over == nil and startTotal == 9 and lastTotal == 11 and entry.windows == 11
        and firstRepeats == 0 and lastRepeats == 1,
        tostring(over) .. " start " .. tostring(startTotal) .. " last " .. tostring(lastTotal) .. " repeats " .. tostring(firstRepeats)
            .. " to " .. tostring(lastRepeats)
end)

test("CB-6 a crowd where the processor is the limit completes with savings near zero and never stops on the control", function()
    local e, b = newRun()
    local entry = doCrowd(e, b, quietEntry(), function() return 0.008 end)[1]
    local small = entry.valid == true
    for _, s in ipairs(entry.settings) do small = small and s.lowDelta ~= nil and near(s.lowDelta, 0, 0.1) end
    return small and entry.reason ~= "control did not respond" and entry.windows == 9, tostring(entry.reason) .. " " .. outText()
end)

test("CB-7 moving mid-run ends it as invalid with everything put back", function()
    local e, b = newRun()
    b.K.POLL = 0.05
    local before = copyOf(CVARS)
    local entry = doCrowd(e, b, quietEntry(), function(cv)
        local p = b.progress()
        if p and p.done >= 3 then SPEED = 7 end
        return runCost(cv)
    end)[1]
    local same = true
    for k, v in pairs(before) do if CVARS[k] ~= v then same = false end end
    return entry and entry.valid == false and entry.reason == "movement" and same and e.ns.suspended == false
        and b.active() == false and b.state().pending == nil and #b.history() == 1 and b.history()[1].valid == false
        and entry.kind == "crowd", outText()
end)

test("CB-8 a refused crowd test writes nothing: no quiet result, an invalid one, one naming nothing known, combat, a run already active", function()
    local e, b = newRun()
    SETLOG = {}
    local none = doCrowd(e, b, nil)[1]
    local invalid = quietEntry()
    invalid.valid = false
    local bad = doCrowd(e, b, invalid)[1]
    local unknown = { valid = true, baselineMs = 7.0, rows = { qrow("noSuchCVar", "Nothing", "0", -1.0), qrow("noSuchCVar", "Nothing", "1", 0, true) } }
    local nothing = doCrowd(e, b, unknown)[1]
    local quiet = #SETLOG == 0
    COMBAT = true
    local combat = doCrowd(e, b, quietEntry())[1]
    COMBAT = false
    local results = {}
    b.crowd(quietEntry(), function(r) results[#results + 1] = r end)
    e.pump(0.1, runCost)
    local again
    b.crowd(quietEntry(), function(r) again = r end)
    e.pump(60, runCost)
    return none.ok == false and none.reason == "no quiet result" and bad.ok == false and bad.reason == "no quiet result"
        and nothing.ok == false and nothing.reason == "nothing to measure" and quiet
        and combat.ok == false and combat.reason == "preflight"
        and again and again.ok == false and again.reason == "preflight" and results[1] and results[1].valid == true, outText()
end)

test("CB-9 a crowd entry joins the history with its profile, and the oldest entry goes when the history is full", function()
    local e, b = newRun()
    b.K.HISTORY = 3
    local h = b.history()
    h[1], h[2], h[3] = { marker = 1 }, { marker = 2 }, { marker = 3 }
    local entry = doCrowd(e, b, quietEntry())[1]
    local list = b.history()
    return #list == 3 and list[1].marker == 2 and list[3] == entry and entry.profile == e.ns.db().active, tostring(#list)
end)

test("CB-10 the report prints the crowd entry: baseline, then for each setting its saving and its baselines' difference", function()
    local e, b = newRun()
    local entry = doCrowd(e, b, quietEntry())[1]
    local lines = b.report(entry)
    local text = table.concat(lines, "\n")
    local shadowsAt
    for i, line in ipairs(lines) do
        if line == "Shadows (graphicsShadowQuality)   lowest level 0" then shadowsAt = i end
    end
    local detail = shadowsAt and lines[shadowsAt + 1] or ""
    local drifted = { kind = "crowd", valid = true, zone = "Z", instanceType = "none", baselineMs = 7.0, rows = {},
        settings = { { cvar = "RenderScale", setting = "Render scale", lowValue = "0.5", status = "inconclusive",
            reason = "inconclusive (baseline drifted 22.0%)" } } }
    local stopped = { kind = "crowd", valid = false, reason = "movement", zone = "Z", instanceType = "none", rows = {}, settings = {} }
    local d, s = b.report(drifted), b.report(stopped)
    local chat = true
    for _, line in ipairs(lines) do chat = chat and has(line) end
    return lines[1] == string.format("Crowd test at %s (%s): baseline 7.00 ms, 143 fps", entry.zone, entry.instanceType)
        and detail:match("^  saved [01]%.%d%d ms  %(baselines differed by %d+%%%)$") ~= nil
        and d[#d] == "  inconclusive (baseline drifted 22.0%)" and not table.concat(d, "\n"):find("saved", 1, true)
        and s[1] == "Crowd test stopped (movement) at Z (none)" and chat and text:find("Render scale (RenderScale)", 1, true) ~= nil,
        text
end)

-- Words and menu, Task 4: the newest finished results survive the history cap, and progress names its setting
local function sampleProgress(b, samples)
    return function(cv)
        local p = b.progress()
        if p then samples[#samples + 1] = { phase = p.phase, label = p.label, cvar = p.cvar, value = p.value } end
        return runCost(cv)
    end
end
local function sampleOf(samples, phase, label)
    for _, s in ipairs(samples) do
        if s.phase == phase and (label == nil or s.label == label) then return s end
    end
end

test("BH-1 the newest finished quiet-spot result and the newest finished crowd result are never trimmed away", function()
    local e, b = newRun()
    b.K.HISTORY = 3
    local quiet = quietEntry()
    quiet.time = 1000
    b.history()[1] = quiet
    local crowds = {}
    for i = 1, 5 do
        crowds[i] = doCrowd(e, b, quiet)[1]
    end
    local h = b.history()
    local crowdCount = 0
    for _, entry in ipairs(h) do if entry.kind == "crowd" then crowdCount = crowdCount + 1 end end
    return #h == 3 and h[1] == quiet and h[3] == crowds[5] and h[2] == crowds[4] and crowdCount == 2, tostring(#h) .. " " .. crowdCount
end)

test("BH-2 an invalid or labelled entry is never protected, and with only protected entries the oldest still goes", function()
    local e, b = newRun()
    b.K.HISTORY = 2
    local invalid = quietEntry()
    invalid.valid = false
    local mark = quietEntry()
    mark.label = "mark"
    b.history()[1], b.history()[2] = invalid, mark
    local quiet = quietEntry()
    local crowd = doCrowd(e, b, quiet)[1]
    local h = b.history()
    local first = #h == 2 and h[1] == mark and h[2] == crowd and crowd.valid
    -- only protected entries: one finished quiet-spot entry and a new crowd entry with room for one
    local e2, b2 = newRun()
    b2.K.HISTORY = 1
    local kept = quietEntry()
    b2.history()[1] = kept
    local crowd2 = doCrowd(e2, b2, kept)[1]
    local h2 = b2.history()
    return first and #h2 == 1 and h2[1] == crowd2, tostring(#h) .. " " .. tostring(#h2)
end)

test("BH-5 the newest finished crowd result survives later attempts that were stopped (Review Focus 5)", function()
    local e, b = newRun()
    b.K.HISTORY = 2
    b.K.POLL = 0.05
    local good = doCrowd(e, b, quietEntry())[1]
    local function stopped()
        SPEED = 0
        local r = doCrowd(e, b, quietEntry(), function(cv)
            local p = b.progress()
            if p and p.done >= 1 then SPEED = 7 end
            return runCost(cv)
        end)[1]
        SPEED = 0
        return r
    end
    local s1, s2, s3 = stopped(), stopped(), stopped()
    local h = b.history()
    return good.valid and s1.valid == false and s2.valid == false and s3.valid == false and #h == 2 and h[1] == good and h[2] == s3,
        tostring(#h)
end)

test("BH-3 a crowd entry records the time of the quiet-spot entry it was built on", function()
    local e, b = newRun()
    local quiet = quietEntry()
    quiet.time = 424242
    local crowd = doCrowd(e, b, quiet)[1]
    return crowd.valid and crowd.quietTime == 424242, tostring(crowd.quietTime)
end)

test("BH-4 progress carries the setting and level of a sweep window, the setting after it, and nothing at the start", function()
    local e, b = newRun()
    local samples = {}
    local entry
    b.run(function(r) entry = r end)
    e.pump(60, sampleProgress(b, samples))
    local sweep = sampleOf(samples, "sweep")
    local after = sampleOf(samples, "baseline", "after " .. (sweep and sweep.label:match("^(.-) %S+$") or "?"))
    local start = sampleOf(samples, "baseline", "start")
    local control = sampleOf(samples, "control")
    local e2, b2 = newRun()
    local crowdSamples = {}
    b2.crowd(quietEntry(), function() end)
    e2.pump(60, sampleProgress(b2, crowdSamples))
    local crowdSweep = sampleOf(crowdSamples, "sweep")
    local crowdAfter, crowdStart = sampleOf(crowdSamples, "baseline", crowdSweep and ("after " .. crowdSweep.label:match("^(.-) %S+$")) or "?"),
        sampleOf(crowdSamples, "baseline", "start")
    return entry and entry.valid and sweep and sweep.cvar ~= nil and sweep.value ~= nil and sweep.label == sweep.label
        and after and after.cvar == sweep.cvar and after.value == nil and start and start.cvar == nil and start.value == nil
        and control and control.cvar == "RenderScale" and control.value == nil
        and crowdSweep and crowdSweep.cvar ~= nil and crowdSweep.value ~= nil and crowdAfter and crowdAfter.cvar == crowdSweep.cvar
        and crowdAfter.value == nil and crowdStart and crowdStart.cvar == nil,
        tostring(sweep and sweep.cvar) .. " " .. tostring(after and after.cvar) .. " " .. tostring(control and control.cvar)
end)

-- The check of a recommendation (spec section 4.3): write the values, measure, put everything back, measure again
local function doVerify(e, b, values, costFn, seconds, opts)
    local results = {}
    b.verify(values, function(r) results[#results + 1] = r end, opts)
    e.pump(seconds or 30, costFn or runCost)
    return results
end
local function unchanged(before)
    for k, v in pairs(before) do
        if CVARS[k] ~= v then return false end
    end
    return true
end
local function countOf(list, name)
    local n = 0
    for _, v in ipairs(list) do if v == name then n = n + 1 end end
    return n
end

test("VF-1 the check writes only the given values, measures with them, puts them back and measures a closing baseline", function()
    local e, b = newRun()
    local before = copyOf(CVARS)
    SETLOG = {}
    local r = doVerify(e, b, { graphicsShadowQuality = "0" })[1]
    return r and r.ok == true and near(r.appliedMs, 6.0, 0.1) and near(r.baselineMs, 7.0, 0.1)
        and table.concat(SETLOG, ",") == "graphicsShadowQuality,graphicsShadowQuality" and unchanged(before)
        and e.ns.suspended == false and b.active() == false and b.state().pending == nil and b.progress() == nil,
        outText() .. " " .. tostring(r and r.appliedMs) .. " " .. table.concat(SETLOG, ",")
end)

test("VF-2 two values are both written and both put back", function()
    local e, b = newRun()
    local before = copyOf(CVARS)
    SETLOG = {}
    local r = doVerify(e, b, { graphicsShadowQuality = "0", RenderScale = "0.5" })[1]
    return r and r.ok == true and near(r.appliedMs, 4.0, 0.1) and countOf(SETLOG, "graphicsShadowQuality") == 2
        and countOf(SETLOG, "RenderScale") == 2 and #SETLOG == 4 and unchanged(before), table.concat(SETLOG, ",")
end)

test("VF-3 moving during either window ends the check with everything put back", function()
    local e, b = newRun()
    b.K.POLL = 0.05
    local before = copyOf(CVARS)
    local first = doVerify(e, b, { graphicsShadowQuality = "0" }, function(cv)
        SPEED = 7
        return runCost(cv)
    end)[1]
    local ok1 = first and first.ok == false and first.reason == "movement" and unchanged(before) and e.ns.suspended == false
        and b.active() == false and b.state().pending == nil
    SPEED = 0
    local second = doVerify(e, b, { graphicsShadowQuality = "0" }, function(cv)
        local p = b.progress()
        if p and p.done >= 1 then SPEED = 7 end
        return runCost(cv)
    end)[1]
    return ok1 and second and second.ok == false and second.reason == "baseline movement" and unchanged(before)
        and e.ns.suspended == false and b.active() == false and b.state().pending == nil,
        tostring(first and first.reason) .. " / " .. tostring(second and second.reason)
end)

test("VF-4 a refused check writes nothing: combat, a run already active, no values", function()
    local e, b = newRun()
    SETLOG = {}
    COMBAT = true
    local combat = doVerify(e, b, { graphicsShadowQuality = "0" })[1]
    COMBAT = false
    local none = doVerify(e, b, {})[1]
    local nothing = doVerify(e, b, nil)[1]
    local quiet = #SETLOG == 0 and b.measuring() == false
    local first
    b.verify({ graphicsShadowQuality = "0" }, function(r) first = r end)
    e.pump(0.1, runCost)
    local again = doVerify(e, b, { graphicsSSAO = "0" }, nil, 0.1)[1]
    e.pump(30, runCost)
    return combat.ok == false and combat.reason == "preflight" and none.ok == false and none.reason == "nothing to check"
        and nothing.reason == "nothing to check" and quiet and again.reason == "preflight" and first and first.ok == true,
        tostring(combat.reason) .. " " .. tostring(none.reason) .. " " .. tostring(again and again.reason)
end)

test("VF-5 a value the game does not accept, or a stop, ends the check with everything put back", function()
    local e, b = newRun()
    local before = copyOf(CVARS)
    SETFAIL.graphicsShadowQuality = "clamp"
    local rejected = doVerify(e, b, { graphicsShadowQuality = "0" })[1]
    SETFAIL.graphicsShadowQuality = nil
    local result
    b.verify({ graphicsShadowQuality = "0" }, function(r) result = r end)
    e.pump(0.1, runCost)
    local stopped = b.stop()
    e.pump(5, runCost)
    return rejected and rejected.ok == false and rejected.reason == "rejected" and stopped == true
        and result and result.ok == false and result.reason == "stopped" and unchanged(before) and e.ns.suspended == false
        and b.active() == false and b.state().pending == nil, tostring(rejected and rejected.reason) .. " " .. tostring(result and result.reason)
end)

-- A quiet guided test (results window, Task 1): spec 2026-10-30-results-window-design.md section 3.1
local function crowdWith(e, b, quiet, opts)
    local results = {}
    b.crowd(quiet, function(r) results[#results + 1] = r end, opts)
    e.pump(60, runCost)
    return results
end

test("QT-7 a silent crowd run prints nothing; not silent it prints the environment and the crowd report", function()
    local e, b = newRun()
    local quiet = crowdWith(e, b, quietEntry(), { silent = true })[1]
    local quietText = outText()
    local e2, b2 = newRun()
    local loud = crowdWith(e2, b2, quietEntry(), nil)[1]
    local loudText = outText()
    return quiet and quiet.valid == true and quietText == "" and loud and loud.valid == true
        and loudText:find("environment: PASS", 1, true) ~= nil and loudText:find("Crowd test at", 1, true) ~= nil, quietText
end)

test("QT-8 a silent crowd run that is refused or has nothing to measure still returns the reason and prints nothing", function()
    local e, b = newRun()
    COMBAT = true
    local refused = crowdWith(e, b, quietEntry(), { silent = true })[1]
    local refusedText = outText()
    local e2, b2 = newRun()
    local missing = crowdWith(e2, b2, nil, { silent = true })[1]
    local missingText = outText()
    local e3, b3 = newRun()
    local loud = crowdWith(e3, b3, nil, nil)[1]
    return refused and refused.reason == "preflight" and refusedText == "" and missing and missing.reason == "no quiet result"
        and missingText == "" and loud and loud.reason == "no quiet result" and has("the crowd test needs a finished quiet-spot test first"),
        refusedText .. " / " .. missingText
end)

test("QT-9 a silent check of a recommendation prints nothing on success and on a refusal; not silent a refusal is printed", function()
    local e, b = newRun()
    local ok = doVerify(e, b, { graphicsShadowQuality = "0" }, nil, nil, { silent = true })[1]
    local okText = outText()
    local e2, b2 = newRun()
    COMBAT = true
    local refused = doVerify(e2, b2, { graphicsShadowQuality = "0" }, nil, nil, { silent = true })[1]
    local refusedText = outText()
    local e3, b3 = newRun()
    COMBAT = true
    local loud = doVerify(e3, b3, { graphicsShadowQuality = "0" })[1]
    return ok and ok.ok == true and okText == "" and refused and refused.ok == false and refused.reason == "preflight"
        and refusedText == "" and loud and loud.reason == "preflight" and has("cannot check: "), okText .. " / " .. refusedText
end)

return H.results()
