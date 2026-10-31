-- Tests for Recommend.lua (spec 2026-10-29-recommender-design.md), driven through the shared harness.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function boot(opts)
    opts = opts or {}
    opts.fresh = true
    local e = H.boot({ graphicsShadowQuality = "4", RenderScale = "1" }, opts)
    return e, e.ns.recommend
end
local function near(a, b, eps) return a ~= nil and math.abs(a - b) <= (eps or 1e-6) end

-- Shared fixture (plan section "Shared test fixture"): rows grouped by cvar, levels in ascending order.
local LABEL = {
    graphicsShadowQuality = "Shadows", graphicsSSAO = "SSAO", graphicsComputeEffects = "Compute effects",
    graphicsLiquidDetail = "Liquid detail", graphicsTextureResolution = "Texture resolution",
    graphicsGroundClutter = "Ground clutter", RenderScale = "Render scale",
}
-- levels: { {value, delta, current = true, flags = {...}, status = "inconclusive"} ... }
local function rows(cvar, baseline, levels)
    local list = {}
    for _, l in ipairs(levels) do
        local r = { setting = LABEL[cvar] or cvar, cvar = cvar, value = l[1], flags = l.flags or {} }
        if l.status then
            r.status, r.reason = l.status, "x"
        else
            r.deltaMs = l[2]
            r.meanMs = baseline + l[2]
            if l.current then r.current = true end
        end
        list[#list + 1] = r
    end
    return list
end
local function entry(baseline, ...)
    local all = {}
    for _, group in ipairs({ ... }) do
        for _, r in ipairs(group) do all[#all + 1] = r end
    end
    return { valid = true, baselineMs = baseline, rows = all }
end
-- T1 (baseline 4.0 ms): Shadows and SSAO, each at its top level now.
local function T1()
    return entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "0", -0.6 }, { "1", -0.3 }, { "2", 0, current = true } }))
end
local function names(list)
    local out = {}
    for _, item in ipairs(list or {}) do out[#out + 1] = item.setting end
    table.sort(out)
    return table.concat(out, ",")
end

-- Task 1: the inputs of choose (spec section 4)
test("R1-0 Recommend.lua runs with no game function available", function()
    local env = { ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, tonumber = tonumber,
        math = math, string = string, table = table, select = select }
    local ns = {}
    local chunk = assert(load(RECOMMEND_SRC, "=Recommend.lua", "t", env))
    chunk("ForeverSettings", ns)
    local r = ns.recommend.choose(T1(), 100)
    return r.status == "nochange", tostring(r.status)
end)

local WANT = {
    graphicsShadowQuality = { 6, true }, graphicsSSAO = { 3, true }, graphicsComputeEffects = { 2, true },
    giQuality = { 5, true }, graphicsLightMode = { 5, true }, graphicsLiquidDetail = { 2, true },
    graphicsTextureResolution = { 9, false }, graphicsGroundClutter = { 3, false },
    groundEffectDensity = { 3, false }, RenderScale = { 10, true },
}
test("R1-1 the target list and the ranking table are exactly the spec's", function()
    local _, r = boot()
    local targets = table.concat(r.TARGETS, ",")
    local bad, count = {}, 0
    for cvar, row in pairs(r.RANKING) do
        count = count + 1
        local want = WANT[cvar]
        if not want or row.weight ~= want[1] or row.raise ~= want[2] then bad[#bad + 1] = cvar end
    end
    for cvar in pairs(WANT) do
        if not r.RANKING[cvar] then bad[#bad + 1] = cvar .. " missing" end
    end
    return targets == "60,90,120,144,165,240" and r.MARGIN == 0.20 and count == 10 and #bad == 0, table.concat(bad, ",")
end)

test("R1-2 the budget is the target's frame time less the margin", function()
    local _, r = boot()
    return near(r.choose(T1(), 165).budgetMs, 4.8485, 0.001) and near(r.choose(T1(), 60).budgetMs, 13.3333, 0.001)
        and near(r.choose(T1(), 165, { margin = 0 }).budgetMs, 6.0606, 0.001)
end)

test("R1-3 a setting already at its best level is left alone: nochange, with the estimate at today's frame time", function()
    local _, r = boot()
    local res = r.choose(T1(), 100)
    return res.status == "nochange" and res.target == 100 and near(res.nowMs, 4.0) and near(res.afterMs, 4.0)
        and near(res.nowFps, 250) and near(res.afterFps, 250) and #res.changes == 0 and #res.unchanged == 2
        and res.summary == "Good news: your settings already hold 100 fps with room to spare. Nothing to change.", tostring(res.summary)
end)

test("R1-4 a setting that may be raised starts at its top counted level", function()
    local _, r = boot()
    local e = entry(4.0, rows("graphicsShadowQuality", 4.0,
        { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true }, { "3", 0.2 } }))
    local res = r.choose(e, 100)
    local c = res.changes[1]
    return res.status == "change" and #res.changes == 1 and c.cvar == "graphicsShadowQuality" and c.setting == "Shadows"
        and c.from == "2" and c.to == "3" and near(c.toDelta, 0.2) and near(res.afterMs, 4.2), tostring(res.status)
end)

test("R1-5 a setting that may not be raised stays at its current level (texture resolution)", function()
    local _, r = boot()
    local e = entry(4.0, rows("graphicsTextureResolution", 4.0,
        { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true }, { "3", 0.2 } }))
    local res = r.choose(e, 100)
    return res.status == "nochange" and #res.changes == 0 and near(res.afterMs, 4.0), tostring(res.status)
end)

test("R1-6 rows without a usable measurement are never chosen; the no-effect flag does not exclude", function()
    local _, r = boot()
    local function top(level)
        local e = entry(4.0, rows("graphicsShadowQuality", 4.0,
            { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true }, level }))
        return r.choose(e, 100)
    end
    local a = top({ "3", status = "inconclusive" })
    local b = top({ "3", 0.2, flags = { "lighting may have changed" } })
    local c = top({ "3", 0.2, flags = { "possible background-window cap" } })
    local d = top({ "3", 0.2, flags = { "no measurable effect or not applied" } })
    return a.status == "nochange" and b.status == "nochange" and c.status == "nochange"
        and d.status == "change" and d.changes[1].to == "3", a.status .. b.status .. c.status .. d.status
end)

test("R1-7 a setting with nothing usable beyond its own level, with no usable row, or with no current row is not measured", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } }),
        rows("RenderScale", 4.0, { { "0.5", status = "inconclusive" }, { "0.9", status = "inconclusive" } }),
        rows("graphicsLiquidDetail", 4.0, { { "0", -0.2 }, { "1", -0.1 } }))
    local res = r.choose(e, 100)
    local inChanges = names(res.changes) .. "|" .. names(res.unchanged)
    return names(res.notMeasured) == "Liquid detail,Render scale,SSAO"
        and res.notMeasured[1].reason == "no usable measurement"
        and not inChanges:find("SSAO", 1, true) and not inChanges:find("Render scale", 1, true)
        and not inChanges:find("Liquid", 1, true) and names(res.unchanged) == "Shadows", names(res.notMeasured)
end)

test("R1-8 a CVar that is not in the ranking is left as it is and adds nothing to the estimate", function()
    local _, r = boot()
    local e = T1()
    for _, row in ipairs(rows("someOtherCvar", 4.0, { { "0", -2.0 }, { "1", 0, current = true }, { "2", 0.5 } })) do
        e.rows[#e.rows + 1] = row
    end
    local res = r.choose(e, 100)
    return res.status == "nochange" and names(res.unchanged):find("someOtherCvar", 1, true) ~= nil
        and near(res.afterMs, 4.0) and #res.changes == 0, names(res.unchanged)
end)

local NODATA = "The test couldn't get a steady reading here, so there is nothing to recommend. "
    .. "The frame rate kept changing between checks. Try again somewhere quiet, keep the camera still, and close other programs."
-- The owner's first live run: every setting's rows were status rows (the baseline had drifted), so nothing was measured.
local function unmeasured()
    return entry(4.75,
        rows("graphicsShadowQuality", 3.44, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }),
        rows("graphicsSSAO", 3.8, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }))
end
test("R1-11 when no setting could be measured the answer is nodata, never nochange", function()
    local _, r = boot()
    local res = r.choose(unmeasured(), 165)
    local empty = r.choose(entry(4.0), 165)
    return res.status == "nodata" and #res.changes == 0 and #res.notMeasured == 2 and near(res.nowMs, 4.75) and res.summary == NODATA
        and empty.status == "nodata" and empty.summary == NODATA, tostring(res.status) .. " " .. tostring(res.summary)
end)

local function scale()
    return entry(4.0, rows("RenderScale", 4.0, { { "0.5", -1.0 }, { "0.7", -0.5 }, { "0.9", 0.3 }, { "1", 0.6 } }))
end
test("R1-10 a setting whose live value is between the measured levels gets a level of its own at its numeric place", function()
    local _, r = boot()
    local e = scale()
    e.starts = { RenderScale = "0.800000" }
    local res = r.choose(e, 100)       -- budget 8 ms: raised to the top level
    local values = {}
    for i, l in ipairs(res.settings[1] and res.settings[1].levels or {}) do values[i] = l.value .. (l.current and "*" or "") end
    local c = res.changes[1]
    local off = scale()
    off.starts = { RenderScale = "abc" }
    local noStart = scale()
    local exact = entry(4.0, rows("RenderScale", 4.0, { { "0.5", -1.0 }, { "0.7", 0, current = true }, { "0.9", 0.3 } }))
    exact.starts = { RenderScale = "0.7" }
    return res.status == "change" and table.concat(values, ",") == "0.5,0.7,0.8*,0.9,1" and c ~= nil and c.from == "0.8" and c.to == "1"
        and near(c.fromDelta, 0) and near(c.toDelta, 0.6) and near(res.afterMs, 4.6) and #res.notMeasured == 0
        and #r.choose(off, 100).notMeasured == 1 and #r.choose(noStart, 100).notMeasured == 1
        and #r.choose(exact, 100).settings[1].levels == 3, table.concat(values, ",")
end)

test("R1-9 an entry that did not finish gives no recommendation", function()
    local _, r = boot()
    local e = T1()
    e.valid = false
    local res = r.choose(e, 100)
    return res.status == "invalid" and #res.changes == 0
        and res.summary == "That test did not finish, so there is nothing to recommend.", tostring(res.summary)
end)

-- Task 2: the greedy lowering and the two dead ends (spec section 4, procedure steps 3 to 5)
local function byCvar(list)
    local by = {}
    for _, item in ipairs(list or {}) do by[item.cvar] = item end
    return by
end

test("R2-1 over budget, the setting that loses the least looks per millisecond is lowered first, until the estimate fits", function()
    local _, r = boot()
    local res = r.choose(T1(), 250)
    local by = byCvar(res.changes)
    return res.status == "change" and #res.changes == 2
        and by.graphicsSSAO and by.graphicsSSAO.from == "2" and by.graphicsSSAO.to == "0"
        and by.graphicsShadowQuality and by.graphicsShadowQuality.from == "2" and by.graphicsShadowQuality.to == "1"
        and near(res.afterMs, 3.0) and near(res.afterFps, 333.33, 0.01), tostring(res.status) .. " " .. tostring(res.afterMs)
end)

test("R2-2 a tie goes to the lower weight", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "0", -0.5 }, { "1", 0, current = true } }))
    local res = r.choose(e, 220)       -- budget 3.636: one move suffices; both moves rate 6.0
    return res.status == "change" and #res.changes == 1 and res.changes[1].cvar == "graphicsSSAO"
        and res.changes[1].from == "1" and res.changes[1].to == "0" and near(res.afterMs, 3.5), tostring(res.changes[1] and res.changes[1].cvar)
end)

test("R2-3 a lower level that is not cheaper is skipped", function()
    local _, r = boot()
    local e = entry(4.0, rows("graphicsLiquidDetail", 4.0, { { "0", -0.5 }, { "1", 0.1 }, { "2", 0, current = true } }))
    local res = r.choose(e, 216)       -- budget 3.7037
    -- With the cheaper level unusable, the not-cheaper level in between is no way down: nothing is lowered at all.
    local stuck = entry(4.0, rows("graphicsLiquidDetail", 4.0, { { "0", status = "inconclusive" }, { "1", 0.1 }, { "2", 0, current = true } }))
    local none = r.choose(stuck, 216)
    return res.status == "change" and #res.changes == 1 and res.changes[1].from == "2" and res.changes[1].to == "0"
        and near(res.afterMs, 3.5) and none.status == "unreachable" and near(none.afterMs, 4.0),
        tostring(res.changes[1] and res.changes[1].to) .. " " .. tostring(none.status) .. " " .. tostring(none.afterMs)
end)

test("R2-4 the places a move gives up count, not only the weight and the milliseconds", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsSSAO", 4.0, { { "0", -0.3 }, { "1", 0, current = true } }),
        rows("graphicsGroundClutter", 4.0, { { "0", -0.5 }, { "1", 0.1 }, { "2", 0, current = true } }))
    local res = r.choose(e, 215)       -- budget 3.721: SSAO rates 10, Ground clutter 3 x 2 places / 0.5 = 12
    return res.status == "change" and #res.changes == 1 and res.changes[1].cvar == "graphicsSSAO"
        and near(res.afterMs, 3.7), tostring(res.changes[1] and res.changes[1].cvar)
end)

test("R2-5 when even the lowest levels miss the target there is no recommendation, and the first sentence says so", function()
    local _, r = boot()
    local res = r.choose(T1(), 500)    -- budget 1.6 ms; the lowest levels give 2.4 ms = 417 fps
    return res.status == "unreachable" and #res.changes == 0 and near(res.afterMs, 2.4) and near(res.afterFps, 416.67, 0.01)
        and res.summary == "Even the lowest settings are estimated at about 417 fps, short of your 500. "
            .. "The game is probably limited by something other than graphics settings, usually the processor.", tostring(res.summary)
end)

test("R2-6 when the lowest levels reach the target but not the margin, the second sentence says so", function()
    local _, r = boot()
    local res = r.choose(T1(), 400)    -- budget 2.0 ms; the lowest levels give 416.7 fps, above 400
    return res.status == "unreachable" and #res.changes == 0
        and res.summary == "Even the lowest settings are estimated at about 417 fps, which is not enough above your 400 "
            .. "to leave room for busier places. Try a lower target.", tostring(res.summary)
end)

test("R2-7 the ranking and the margin can be overridden", function()
    local _, r = boot()
    local ranking = { graphicsShadowQuality = { weight = 1, raise = true }, graphicsSSAO = { weight = 20, raise = true } }
    local res = r.choose(T1(), 250, { ranking = ranking })      -- Shadows is now the cheap one to give up
    local by = byCvar(res.changes)
    local tie = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "0", -0.5 }, { "1", 0, current = true } }))
    local strict = r.choose(tie, 220, { margin = 0.5 })          -- budget 2.27: not reachable with a bigger margin
    return res.status == "change" and #res.changes == 1 and by.graphicsShadowQuality and by.graphicsShadowQuality.to == "0"
        and strict.status == "unreachable" and r.choose(tie, 220).status == "change", tostring(res.status) .. tostring(strict.status)
end)

test("R2-9 a setting that is not in the ranking is never lowered, however much it would save", function()
    local _, r = boot()
    local e = T1()
    for _, row in ipairs(rows("someOtherCvar", 4.0, { { "0", -2.0 }, { "1", 0, current = true } })) do
        e.rows[#e.rows + 1] = row
    end
    local res = r.choose(e, 250)
    local by = byCvar(res.changes)
    return res.status == "change" and by.someOtherCvar == nil and by.graphicsSSAO ~= nil and by.graphicsShadowQuality ~= nil
        and near(res.afterMs, 3.0), tostring(res.status) .. " " .. tostring(res.afterMs)
end)

-- The owner's real run in an empty spot (spec section 2): baseline 2.98 ms.
local function owner()
    return entry(2.98,
        rows("graphicsShadowQuality", 2.98, { { "0", -0.87 }, { "1", -0.26 }, { "2", -0.27 }, { "3", -0.19 },
            { "4", 0, current = true }, { "5", 0.07 } }),
        rows("graphicsSSAO", 2.98, { { "0", -0.50 }, { "1", -0.32 }, { "2", -0.24 }, { "3", -0.12 }, { "4", 0, current = true } }),
        rows("graphicsComputeEffects", 2.98, { { "0", -0.23 }, { "1", 0.01 }, { "2", 0.01 }, { "3", 0, current = true }, { "4", 0.02 } }),
        rows("graphicsLiquidDetail", 2.98, { { "0", -0.21 }, { "1", -0.21 }, { "2", 0, current = true }, { "3", 0.12 } }))
end
test("R2-8 the owner's real run: everything with room is raised at 165, and one move frees just enough at 258", function()
    local _, r = boot()
    local a = r.choose(owner(), 165)
    local by = byCvar(a.changes)
    local first = by.graphicsShadowQuality and by.graphicsShadowQuality.from == "4" and by.graphicsShadowQuality.to == "5"
        and by.graphicsComputeEffects and by.graphicsComputeEffects.from == "3" and by.graphicsComputeEffects.to == "4"
        and by.graphicsLiquidDetail and by.graphicsLiquidDetail.from == "2" and by.graphicsLiquidDetail.to == "3"
        and by.graphicsSSAO == nil and #a.changes == 3 and near(a.afterMs, 3.19, 1e-9) and near(a.afterFps, 313.48, 0.01)
    local b = r.choose(owner(), 258)      -- budget 3.1008: lowering Liquid detail (rate 16.7) is the cheapest single move
    local byB = byCvar(b.changes)
    local second = b.status == "change" and #b.changes == 2 and byB.graphicsLiquidDetail == nil
        and byB.graphicsShadowQuality ~= nil and byB.graphicsComputeEffects ~= nil and near(b.afterMs, 3.07, 1e-9)
    local c = r.choose(owner(), 330)      -- budget 2.4242: reached by lowering further
    return first and second and c.status == "change" and c.afterMs <= c.budgetMs, tostring(a.status) .. " " .. tostring(b.afterMs) .. " " .. tostring(c.status)
end)

test("R2-11 lowering walks down through the level the player's own value made", function()
    local _, r = boot()
    local e = scale()
    e.starts = { RenderScale = "0.800000" }
    local res = r.choose(e, 250)       -- budget 3.2 ms: 4.6 -> 4.3 -> 4.0 (the player's own 0.8) -> 3.5 -> 3.0
    local c = res.changes[1]
    return res.status == "change" and #res.changes == 1 and c.from == "0.8" and c.to == "0.5" and near(res.afterMs, 3.0),
        tostring(c and c.to) .. " " .. tostring(res.afterMs)
end)

test("R2-10 the estimate never claims more than a four-fold speed-up, however far two overlapping savings add up", function()
    local _, r = boot()
    local e = entry(10.0,
        rows("graphicsLiquidDetail", 10.0, { { "0", -3.0 }, { "1", 0, current = true } }),
        rows("graphicsShadowQuality", 10.0, { { "0", -8.0 }, { "1", 0, current = true } }))
    local res = r.choose(e, 240)       -- budget 3.33: the two savings add up to 11 ms, more than the frame itself
    local far = r.choose(e, 2000)      -- a budget (0.4 ms) below that floor cannot be promised either
    return r.MAX_SPEEDUP == 4 and res.status == "change" and #res.changes == 2 and near(res.afterMs, 2.5)
        and near(res.afterFps, 400, 1e-9) and far.status == "unreachable" and far.summary:find("about 400 fps", 1, true) ~= nil
        and far.summary:find("short of your 2000", 1, true) ~= nil, tostring(res.afterMs) .. " " .. tostring(far.status)
end)

-- Task 3: chartModel and the sentences (spec section 5)
local FOOTER = "Bars show speed on your PC in an empty spot, not how the picture looks."
local OVERLAP = " Each fps figure is that setting on its own; together they overlap, so the total is the number in the bars."
local function graphOf(model, cvar)
    for _, g in ipairs(model.graphs) do
        if g.cvar == cvar then return g end
    end
end

test("C3-1 the before and after chart: one frame-rate scale that includes the target; no after bar without a change", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(T1(), 250))
    local h = m.headline
    local okChange = near(h.scaleFps, 400, 1e-9) and near(h.now.fraction, 0.625, 1e-9) and near(h.after.fraction, 0.83333, 1e-4)
        and near(h.target.fraction, 0.625, 1e-9) and h.now.label == "Now: about 250 fps"
        and h.after.label == "With these changes: about 333 fps" and h.target.label == "Your target: 250 fps"
    local u = r.chartModel(r.choose(T1(), 600)).headline          -- the target is the largest number on the scale
    local n = r.chartModel(r.choose(T1(), 100)).headline
    return okChange and near(u.scaleFps, 720, 1e-9) and u.after == nil and near(u.target.fraction, 0.83333, 1e-4)
        and u.now.label == "Now: about 250 fps" and near(n.scaleFps, 300, 1e-9) and n.after == nil,
        tostring(h.scaleFps) .. " " .. tostring(u.scaleFps) .. " " .. tostring(n.scaleFps)
end)

test("C3-2 the change sentences, in frames per second and each setting on its own", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(T1(), 250))
    local o = r.chartModel(r.choose(owner(), 165)).lines
    local seen = table.concat(o, "|")
    return m.lines[1] == "Shadow detail: 2 to 1, saves about 28 fps." and m.lines[2] == "Soft corner shadows: 2 to 0, saves about 44 fps."
        and #m.lines == 2
        and seen:find("Shadow detail: 4 to 5, costs about 8 fps.", 1, true) ~= nil
        and seen:find("Extra effects detail: 3 to 4, costs about 2 fps.", 1, true) ~= nil
        and seen:find("Water detail: 2 to 3, costs about 13 fps.", 1, true) ~= nil, table.concat(m.lines, "|") .. " // " .. seen
end)

-- Where each point of a graph stands in the shared axis, and what is marked on it ("now", "recommended" or nothing)
local function inAxis(model)
    for _, g in ipairs(model.graphs) do
        for _, p in ipairs(g.points) do
            if p.fps < model.axis.min or p.fps > model.axis.max then return false end
        end
    end
    return true
end
local function marksOf(g)
    local out = {}
    for i, p in ipairs(g.points) do out[i] = p.current and "now" or (p.recommended and "recommended" or "") end
    return table.concat(out, ",")
end

test("C3-3 every graph shares the one axis, and a faster level stands higher than a slower one", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(T1(), 250))
    local o = r.chartModel(r.choose(owner(), 165))
    local shadows = graphOf(m, "graphicsShadowQuality").points
    local ownerShadows = graphOf(o, "graphicsShadowQuality").points
    return inAxis(m) and inAxis(o) and shadows[1].fps > shadows[2].fps and shadows[2].fps > shadows[3].fps
        and ownerShadows[6].fps < ownerShadows[5].fps and ownerShadows[5].current == true, tostring(shadows[1].fps)
end)

test("C3-4 the current level is marked now and the chosen one recommended, and only when there is a recommendation", function()
    local _, r = boot()
    local c = r.chartModel(r.choose(T1(), 250))
    local n = r.chartModel(r.choose(T1(), 100))
    local u = r.chartModel(r.choose(T1(), 500))
    return marksOf(graphOf(c, "graphicsShadowQuality")) == ",recommended,now" and marksOf(graphOf(c, "graphicsSSAO")) == "recommended,,now"
        and marksOf(graphOf(n, "graphicsShadowQuality")) == ",,now" and marksOf(graphOf(u, "graphicsShadowQuality")) == ",,now"
        and marksOf(graphOf(u, "graphicsSSAO")) == ",,now", marksOf(graphOf(c, "graphicsShadowQuality"))
end)

test("C3-5 a level without a usable measurement has no point and stays out of the axis; a setting with none is listed", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", status = "inconclusive" }, { "2", 0, current = true },
            { "3", 5.0, flags = { "lighting may have changed" } } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } }))
    local m = r.chartModel(r.choose(e, 100))
    local points = graphOf(m, "graphicsShadowQuality").points
    return #points == 2 and points[1].value == "0" and points[2].value == "2" and near(points[1].fps, 333.33, 0.01) and inAxis(m)
        and m.axis.max < 1000 / (4.0 + 5.0) + 300
        and #m.notMeasured == 1 and m.notMeasured[1].setting == "SSAO" and m.notMeasured[1].reason == "no usable measurement"
        and graphOf(m, "graphicsSSAO") == nil, tostring(#points)
end)

test("C3-6 only a change can be applied; the other outcomes carry their sentence; the footer is fixed", function()
    local _, r = boot()
    local c = r.chartModel(r.choose(T1(), 250))
    local n = r.chartModel(r.choose(T1(), 100))
    local u = r.chartModel(r.choose(T1(), 500))
    local bad = T1()
    bad.valid = false
    local i = r.chartModel(r.choose(bad, 250))
    return c.canApply == true and c.summary == nil and n.canApply == false and u.canApply == false and i.canApply == false
        and n.summary == "Good news: your settings already hold 100 fps with room to spare. Nothing to change."
        and u.summary:find("short of your 500", 1, true) ~= nil
        and i.summary == "That test did not finish, so there is nothing to recommend." and i.headline == nil
        and c.footer == FOOTER .. OVERLAP and n.footer == FOOTER .. OVERLAP, tostring(c.canApply)
end)

test("C3-8 a run that measured nothing shows the Now bar and the target, the nodata sentence, and cannot be applied", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(unmeasured(), 165))
    return m.status == "nodata" and m.canApply == false and m.summary == NODATA and m.headline ~= nil and m.headline.after == nil
        and m.headline.now.label == "Now: about 211 fps" and m.headline.target.label == "Your target: 165 fps"
        and #m.graphs == 0 and #m.notMeasured == 2 and #m.lines == 0, tostring(m.status) .. " " .. tostring(m.summary)
end)

test("C3-7 a run where nothing differs from the baseline draws level points and does not fail", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", 0 }, { "1", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "0", 0 }, { "1", 0, current = true } }))
    local m = r.chartModel(r.choose(e, 100))
    local a, b = graphOf(m, "graphicsShadowQuality"), graphOf(m, "graphicsSSAO")
    return #a.points == 2 and near(a.points[1].fps, 250) and near(a.points[2].fps, 250) and near(a.swing, 0)
        and #b.points == 2 and near(b.points[1].fps, 250) and near(b.swing, 0) and inAxis(m), tostring(a.swing)
end)

-- Task 1 of the crowd test (spec 2026-10-29-crowd-test-design.md section 5): the quiet-spot curves rebased and scaled.
-- Q: T1 with the values each setting held when the quiet test began.
local function Q()
    local e = T1()
    e.starts = { graphicsShadowQuality = "2", graphicsSSAO = "2" }
    return e
end
-- C1: a crowd measurement (10 ms baseline); Shadows' lowest level saves 3 ms there, SSAO's 0.6 ms.
local function C1(shadowsLow, ssaoLow, starts)
    return { valid = true, baselineMs = 10.0, starts = starts or { graphicsShadowQuality = "2", graphicsSSAO = "2" },
        settings = {
            { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", lowDelta = shadowsLow or -3.0 },
            { cvar = "graphicsSSAO", setting = "SSAO", lowValue = "0", lowDelta = ssaoLow or -0.6 },
        } }
end
local function levelsOfCvar(e, cvar)
    local list = {}
    for _, row in ipairs(e.rows) do
        if row.cvar == cvar then list[#list + 1] = row end
    end
    return list
end
-- "0=-3.00|1=-1.20|2=0.00": a setting's rows as value=delta, in order.
local function curve(e, cvar)
    local out = {}
    for _, row in ipairs(levelsOfCvar(e, cvar)) do
        out[#out + 1] = row.value .. "=" .. (row.deltaMs and string.format("%.2f", row.deltaMs) or tostring(row.status))
    end
    return table.concat(out, "|")
end
local function currentValue(e, cvar)
    for _, row in ipairs(levelsOfCvar(e, cvar)) do
        if row.current then return row.value end
    end
end
local function renderScaleQuiet()
    local e = entry(4.0, rows("RenderScale", 4.0, { { "0.5", -1.0 }, { "0.7", -0.5 }, { "0.9", 0, current = true }, { "1", 0.3 } }))
    e.starts = { RenderScale = "0.9" }
    return e
end
local function renderScaleQuietOffList()
    local e = entry(4.0, rows("RenderScale", 4.0, { { "0.5", -1.0 }, { "0.7", -0.5 }, { "0.9", 0.3 }, { "1", 0.6 } }))
    e.starts = { RenderScale = "0.8" }
    return e
end
local function renderCrowd(starts, low)
    return { valid = true, baselineMs = 10.0, starts = { RenderScale = starts },
        settings = { { cvar = "RenderScale", setting = "Render scale", lowValue = "0.5", lowDelta = low } } }
end
local CROWD_FOOTER = "Each setting's lowest level was measured in this crowd; the levels in between are estimated from your quiet-spot test."
local HINT = "Next, in a busy place: Find my crowded settings (minimap menu or /fset crowd)."

test("CE-1 each quiet-spot curve is scaled by how much the crowd saves at its lowest level, on the crowd's baseline", function()
    local _, r = boot()
    local ce = r.crowdEntry(Q(), C1())
    local shadows = levelsOfCvar(ce, "graphicsShadowQuality")
    return ce.kind == "crowd" and ce.valid == true and near(ce.baselineMs, 10.0)
        and curve(ce, "graphicsShadowQuality") == "0=-3.00|1=-1.20|2=0.00"
        and curve(ce, "graphicsSSAO") == "0=-0.60|1=-0.30|2=0.00"
        and near(shadows[1].meanMs, 7.0) and near(shadows[2].meanMs, 8.8) and near(shadows[3].meanMs, 10.0)
        and currentValue(ce, "graphicsShadowQuality") == "2" and currentValue(ce, "graphicsSSAO") == "2"
        and ce.starts.graphicsShadowQuality == "2", curve(ce, "graphicsShadowQuality")
end)

test("CE-2 when the live level is not the one the quiet test began at, every delta is re-expressed against it", function()
    local _, r = boot()
    local ce = r.crowdEntry(Q(), C1(-1.8, -0.6, { graphicsShadowQuality = "1", graphicsSSAO = "2" }))
    return curve(ce, "graphicsShadowQuality") == "0=-1.80|1=0.00|2=1.20" and currentValue(ce, "graphicsShadowQuality") == "1"
        and curve(ce, "graphicsSSAO") == "0=-0.60|1=-0.30|2=0.00", curve(ce, "graphicsShadowQuality")
end)

test("CE-3 a live level between two measured levels gets a level of its own with an interpolated delta", function()
    local _, r = boot()
    local ce = r.crowdEntry(renderScaleQuiet(), renderCrowd("0.800000", -2.25))
    return curve(ce, "RenderScale") == "0.5=-2.25|0.7=-0.75|0.8=0.00|0.9=0.75|1=1.65" and currentValue(ce, "RenderScale") == "0.8",
        curve(ce, "RenderScale")
end)

test("CE-8 a live level equal to a quiet start that was not a level needs no interpolation", function()
    local _, r = boot()
    local ce = r.crowdEntry(renderScaleQuietOffList(), renderCrowd("0.8", -2.0))
    return curve(ce, "RenderScale") == "0.5=-2.00|0.7=-1.00|0.8=0.00|0.9=0.60|1=1.20" and currentValue(ce, "RenderScale") == "0.8",
        curve(ce, "RenderScale")
end)

test("CE-4 the scale factor is limited to four, and a crowd that saves nothing flattens the curve", function()
    local _, r = boot()
    local big = r.crowdEntry(Q(), C1(-10, -0.6))
    local none = r.crowdEntry(Q(), C1(0.5, -0.6))
    -- the limit bounds the levels in between, which are estimated; the level the crowd measured keeps its measured saving
    return r.CROWD_FACTOR_MAX == 4 and curve(big, "graphicsShadowQuality") == "0=-10.00|1=-1.60|2=0.00"
        and curve(none, "graphicsShadowQuality") == "0=0.00|1=0.00|2=0.00", curve(big, "graphicsShadowQuality")
end)

test("CE-10 a saving the crowd measured is never cut down to the limit: a setting that matters far more in the crowd can be lowered", function()
    local _, r = boot()
    local q = entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", -0.3 }, { "1", -0.15 }, { "2", 0, current = true } }))
    q.starts = { graphicsShadowQuality = "2" }
    local c = { valid = true, baselineMs = 10.0, starts = { graphicsShadowQuality = "2" },
        settings = { { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", lowDelta = -3.0 } } }
    local ce = r.crowdEntry(q, c)
    local res = r.choose(ce, 120)
    return curve(ce, "graphicsShadowQuality") == "0=-3.00|1=-0.60|2=0.00" and res.status == "change" and #res.changes == 1
        and res.changes[1].from == "2" and res.changes[1].to == "0" and near(res.afterMs, 7.0), tostring(res.status) .. " " .. curve(ce, "graphicsShadowQuality")
end)

test("CE-5 a flat quiet-spot curve cannot be scaled: the crowd's saving runs in a straight line by position", function()
    local _, r = boot()
    local q = entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", -0.02 }, { "1", -0.01 }, { "2", 0, current = true } }))
    q.starts = { graphicsShadowQuality = "2" }
    local c = { valid = true, baselineMs = 10.0, starts = { graphicsShadowQuality = "2" },
        settings = { { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", lowDelta = -2.0 } } }
    return r.FLAT_MS == 0.05 and curve(r.crowdEntry(q, c), "graphicsShadowQuality") == "0=-2.00|1=-1.00|2=0.00",
        curve(r.crowdEntry(q, c), "graphicsShadowQuality")
end)

test("CE-6 a setting only the crowd measured has two levels: its live level and its lowest, after the quiet-spot settings", function()
    local _, r = boot()
    local c = C1()
    c.starts.graphicsComputeEffects = "3"
    c.settings[#c.settings + 1] = { cvar = "graphicsComputeEffects", setting = "Compute effects", lowValue = "0", lowDelta = -0.8 }
    local ce = r.crowdEntry(Q(), c)
    local order = {}
    for _, row in ipairs(ce.rows) do
        if order[#order] ~= row.cvar then order[#order + 1] = row.cvar end
    end
    return curve(ce, "graphicsComputeEffects") == "0=-0.80|3=0.00" and currentValue(ce, "graphicsComputeEffects") == "3"
        and table.concat(order, ",") == "graphicsShadowQuality,graphicsSSAO,graphicsComputeEffects", table.concat(order, ",")
end)

test("CE-7 a setting that could not be measured, or whose live level the quiet test does not cover, is listed as not measured", function()
    local _, r = boot()
    local drifted = C1()
    drifted.settings[1] = { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", status = "inconclusive",
        reason = "inconclusive (baseline drifted 22%)" }
    local a = r.choose(r.crowdEntry(Q(), drifted), 100)
    local noStart = C1()
    noStart.starts.graphicsSSAO = nil
    local b = r.choose(r.crowdEntry(Q(), noStart), 100)
    local outside = C1(-3.0, -0.6, { graphicsShadowQuality = "7", graphicsSSAO = "2" })
    local c = r.choose(r.crowdEntry(Q(), outside), 100)
    local bad = C1()
    bad.valid = false
    local ce = r.crowdEntry(Q(), bad)
    return a.notMeasured[1].setting == "Shadows" and a.notMeasured[1].reason == "inconclusive (baseline drifted 22%)"
        and b.notMeasured[1].setting == "SSAO" and b.notMeasured[1].reason == "live level not covered by the quiet-spot test"
        and c.notMeasured[1].setting == "Shadows" and c.notMeasured[1].reason == "live level not covered by the quiet-spot test"
        and ce.valid == false and r.choose(ce, 100).status == "invalid",
        tostring(a.notMeasured[1] and a.notMeasured[1].reason) .. " / " .. tostring(b.notMeasured[1] and b.notMeasured[1].reason)
end)

test("CE-9 a crowd that does not agree with the quiet-spot curve, or saves nothing on a flat curve, changes no level", function()
    local _, r = boot()
    -- the quiet test says the lowest level costs more than the live one, the crowd says it saves: no scaling
    local dearer = entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", 0.5 }, { "1", 0.2 }, { "2", 0, current = true } }))
    dearer.starts = { graphicsShadowQuality = "2" }
    local c = { valid = true, baselineMs = 10.0, starts = { graphicsShadowQuality = "2" },
        settings = { { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", lowDelta = -1.0 } } }
    local flat = entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", -0.02 }, { "1", -0.01 }, { "2", 0, current = true } }))
    flat.starts = { graphicsShadowQuality = "2" }
    local c2 = { valid = true, baselineMs = 10.0, starts = { graphicsShadowQuality = "2" },
        settings = { { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", lowDelta = 0.5 } } }
    -- the level the crowd measured keeps its saving; nothing is scaled from a curve that points the other way
    return curve(r.crowdEntry(dearer, c), "graphicsShadowQuality") == "0=-1.00|1=0.00|2=0.00"
        and curve(r.crowdEntry(flat, c2), "graphicsShadowQuality") == "0=0.00|1=0.00|2=0.00",
        curve(r.crowdEntry(dearer, c), "graphicsShadowQuality") .. " / " .. curve(r.crowdEntry(flat, c2), "graphicsShadowQuality")
end)

test("CR-1 a crowd result uses a ten per cent margin and lowers the cheapest-looking setting first", function()
    local _, r = boot()
    local res = r.choose(r.crowdEntry(Q(), C1()), 100)
    local c = res.changes[1]
    return res.kind == "crowd" and res.status == "change" and near(res.budgetMs, 9.0) and #res.changes == 1
        and c.cvar == "graphicsShadowQuality" and c.from == "2" and c.to == "1" and near(res.afterMs, 8.8)
        and r.CROWD_MARGIN == 0.10, tostring(res.status) .. " " .. tostring(res.afterMs)
end)

test("CR-2 a crowd that already holds the target says so in crowd words, and a crowd result never raises a setting", function()
    local _, r = boot()
    local res = r.choose(r.crowdEntry(Q(), C1()), 60)
    local q = entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true }, { "3", 0.2 } }))
    q.starts = { graphicsShadowQuality = "2" }
    local c = { valid = true, baselineMs = 10.0, starts = { graphicsShadowQuality = "2" },
        settings = { { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", lowDelta = -3.0 } } }
    local ce = r.crowdEntry(q, c)
    local raised = r.choose(ce, 60)
    return res.status == "nochange"
        and res.summary == "Good news: your settings already hold 60 fps in crowds with room to spare. Nothing to change."
        and curve(ce, "graphicsShadowQuality") == "0=-3.00|1=-1.20|2=0.00|3=0.60"
        and raised.status == "nochange" and #raised.changes == 0, tostring(res.summary) .. " / " .. tostring(raised.status)
end)

test("CR-3 a quick quiet-spot result never raises a setting above its current level; a full one still does", function()
    local _, r = boot()
    local function lifted(mode)
        local e = entry(4.0, rows("graphicsShadowQuality", 4.0,
            { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true }, { "3", 0.2 } }))
        e.mode = mode
        return r.choose(e, 100)
    end
    local quick, full = lifted("quick"), lifted("all")
    local plain = lifted(nil)
    return quick.status == "nochange" and #quick.changes == 0 and quick.kind == "quiet"
        and full.status == "change" and full.changes[1].to == "3" and plain.status == "change", quick.status .. full.status
end)

test("CR-4 the chart model carries the title, the footer and the Everyday hint for its kind and outcome", function()
    local _, r = boot()
    local crowd = r.chartModel(r.choose(r.crowdEntry(Q(), C1()), 100))
    local change = r.chartModel(r.choose(T1(), 250))
    local nochange = r.chartModel(r.choose(T1(), 100))
    local unreachable = r.chartModel(r.choose(T1(), 500))
    local nodata = r.chartModel(r.choose(unmeasured(), 165))
    local broken = T1()
    broken.valid = false
    local invalid = r.chartModel(r.choose(broken, 250))
    return crowd.title == "Your crowded settings" and crowd.footer == CROWD_FOOTER .. OVERLAP and crowd.hint == nil
        and change.title == "Your best settings" and change.footer == FOOTER .. OVERLAP and change.hint == HINT
        and nochange.hint == HINT and unreachable.hint == HINT and nodata.hint == nil and invalid.hint == nil
        and nodata.title == "Your best settings", tostring(change.hint)
end)

-- Task 5: the check of a recommendation (spec section 4.3 and 6). choose(T1, 250): by hand SSAO goes down to 0 and Shadows
-- to 1, so nowMs 4.0, afterMs 3.0, afterFps 333.33.
test("CK-1 a check measured near the estimate adds the check line and shows the measured bar", function()
    local _, r = boot()
    local res = r.choose(T1(), 250)
    local m = r.chartModel(res, { ok = true, appliedMs = 3.1, baselineMs = 4.0 })
    local a = m.headline.after
    return near(res.afterMs, 3.0) and #m.checkLines == 1
        and m.checkLines[1] == "Checked: expected about 333 fps, measured about 323 fps."
        and a.label == "With these changes: about 323 fps (measured)" and near(a.fps, 322.58, 0.01)
        and near(a.fraction, a.fps / m.headline.scaleFps, 1e-9), tostring(m.checkLines[1]) .. " " .. tostring(a.label)
end)

test("CK-2 a check below three quarters of the estimate says the estimate was optimistic", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(T1(), 250), { ok = true, appliedMs = 4.4, baselineMs = 4.0 })
    return #m.checkLines == 2 and m.checkLines[1] == "Checked: expected about 333 fps, measured about 227 fps."
        and m.checkLines[2] == "The estimate was optimistic: about 227 fps is what to expect."
        and m.headline.after.label == "With these changes: about 227 fps (measured)", tostring(m.checkLines[2])
end)

test("CK-3 the scale includes a measured rate above the estimate and leaves the estimate out once it is replaced", function()
    local _, r = boot()
    local high = r.chartModel(r.choose(T1(), 250), { ok = true, appliedMs = 2.0, baselineMs = 4.0 })
    local low = r.chartModel(r.choose(T1(), 250), { ok = true, appliedMs = 4.4, baselineMs = 4.0 })
    return near(high.headline.after.fps, 500, 0.01) and near(high.headline.scaleFps, 600, 0.01)
        and near(low.headline.scaleFps, 300, 0.01), tostring(high.headline.scaleFps) .. " " .. tostring(low.headline.scaleFps)
end)

test("CK-4 a baseline that grew between the test and the check is scaled out", function()
    local _, r = boot()
    local plain = r.chartModel(r.choose(T1(), 250), { ok = true, appliedMs = 3.0, baselineMs = 4.0 })
    local grown = r.chartModel(r.choose(T1(), 250), { ok = true, appliedMs = 4.8, baselineMs = 6.4 })
    return plain.checkLines[1] == "Checked: expected about 333 fps, measured about 333 fps."
        and grown.checkLines[1] == plain.checkLines[1] and near(grown.headline.after.fps, plain.headline.after.fps, 1e-6),
        tostring(grown.checkLines[1])
end)

test("CK-5 without a usable check, or without a change to check, nothing is added", function()
    local _, r = boot()
    local good = { ok = true, appliedMs = 3.1, baselineMs = 4.0 }
    local none = r.chartModel(r.choose(T1(), 250))
    local failed = r.chartModel(r.choose(T1(), 250), { ok = false, reason = "movement" })
    local broken = r.chartModel(r.choose(T1(), 250), { ok = true, appliedMs = 3.1, baselineMs = 0 })
    local nochange = r.chartModel(r.choose(T1(), 100), good)
    local unreachable = r.chartModel(r.choose(T1(), 500), good)
    local nodata = r.chartModel(r.choose(unmeasured(), 165), good)
    return #none.checkLines == 0 and none.headline.after.label == "With these changes: about 333 fps"
        and #failed.checkLines == 0 and failed.headline.after.label == "With these changes: about 333 fps"
        and #broken.checkLines == 0 and broken.headline.after.label == "With these changes: about 333 fps"
        and #nochange.checkLines == 0 and nochange.headline.after == nil
        and #unreachable.checkLines == 0 and unreachable.headline.after == nil
        and #nodata.checkLines == 0 and nodata.headline.after == nil, tostring(none.headline.after.label)
end)

test("CR-6 a crowd that never held steady says so in its own words, not 'try again somewhere quiet'", function()
    local _, r = boot()
    local unsteady = C1()
    for _, s in ipairs(unsteady.settings) do
        s.lowDelta, s.status, s.reason = nil, "inconclusive", "inconclusive (baseline drifted 22.0%)"
    end
    local res = r.choose(r.crowdEntry(Q(), unsteady), 100)
    local quiet = r.choose(unmeasured(), 165)
    return res.status == "nodata" and #res.changes == 0
        and res.summary == "The test couldn't get a steady reading in this crowd, so there is nothing to recommend. "
            .. "The frame rate kept changing between checks. Try again in a moment, or in another busy place; keep the camera still "
            .. "and close other programs."
        and quiet.summary:find("Try again somewhere quiet", 1, true) ~= nil, tostring(res.summary)
end)

test("CR-5 a crowd where every saving is tiny is a processor-limited crowd: unreachable, nothing to apply", function()
    local _, r = boot()
    local res = r.choose(r.crowdEntry(Q(), C1(-0.05, -0.02)), 144)
    return res.status == "unreachable" and #res.changes == 0
        and res.summary:find("limited by something other than graphics settings", 1, true) ~= nil
        and r.chartModel(res).canApply == false, tostring(res.status)
end)

-- Words and menu, Task 6: the chart model speaks in plain names and levels (spec section 3.1). Rows saved by an older
-- version carry the old labels ("Shadows"); the names come from the setting's cvar.
local function renderScaleEntry()
    return entry(5.5, rows("RenderScale", 5.5, { { "0.5", -1.8 }, { "0.7", -1.0 }, { "1", 0, current = true } }))
end

test("CN-1 the change sentences use the plain setting names and levels", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(T1(), 250))
    local p = r.chartModel(r.choose(renderScaleEntry(), 165))
    return m.lines[1] == "Shadow detail: 2 to 1, saves about 28 fps." and m.lines[2] == "Soft corner shadows: 2 to 0, saves about 44 fps."
        and p.lines[1] == "Picture sharpness: 100% to 70%, saves about 40 fps.", tostring(m.lines[1]) .. " / " .. tostring(p.lines[1])
end)

test("CN-2 each graph and point gains a plain name and level text while the raw value stays", function()
    local _, r = boot()
    local p = r.chartModel(r.choose(renderScaleEntry(), 165))
    local s = graphOf(p, "RenderScale")
    local t = graphOf(r.chartModel(r.choose(T1(), 250)), "graphicsShadowQuality")
    local recommended
    for _, point in ipairs(s.points) do
        if point.value == "0.7" and point.recommended then recommended = point.text end
    end
    return s.name == "Picture sharpness" and s.points[1].text == "50%" and s.points[1].value == "0.5"
        and s.points[2].text == "70%" and s.points[3].text == "100%" and s.points[3].value == "1" and recommended == "70%"
        and t.name == "Shadow detail" and t.points[1].text == "0" and t.points[3].text == "2", tostring(s.name) .. " " .. tostring(recommended)
end)

test("CN-3 a setting that could not be measured is listed under its plain name", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } }))
    local m = r.chartModel(r.choose(e, 100))
    return #m.notMeasured == 1 and m.notMeasured[1].name == "Soft corner shadows" and m.notMeasured[1].setting == "SSAO"
        and m.notMeasured[1].reason == "no usable measurement", tostring(m.notMeasured[1] and m.notMeasured[1].name)
end)

test("CN-4 an entry saved with old labels, and a setting the names table does not know, both come out right", function()
    local _, r = boot()
    local old = entry(4.0, rows("groundEffectDensity", 4.0, { { "48", -0.9 }, { "64", -0.5 }, { "128", 0, current = true } }))
    for _, row in ipairs(old.rows) do row.setting = "Ground clutter (raw)" end
    local custom = entry(4.0, rows("customCvar", 4.0, { { "0", -1.0 }, { "2", 0, current = true } }))
    local a = r.chartModel(r.choose(old, 100))
    local b = r.chartModel(r.choose(custom, 100))
    return graphOf(a, "groundEffectDensity").name == "Grass and plants (exact amount)"
        and graphOf(b, "customCvar").name == "customCvar" and graphOf(b, "customCvar").points[1].text == "0",
        tostring(graphOf(a, "groundEffectDensity").name)
end)

test("CN-5 loaded with no names table the model falls back to the row labels and raw levels", function()
    local env = { ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, tonumber = tonumber,
        math = math, string = string, table = table, select = select }
    local ns = {}
    local chunk = assert(load(RECOMMEND_SRC, "=Recommend.lua", "t", env))
    chunk("ForeverSettings", ns)
    local m = ns.recommend.chartModel(ns.recommend.choose(T1(), 250))
    local s = graphOf(m, "graphicsShadowQuality")
    return m.lines[1] == "Shadows: 2 to 1, saves about 28 fps." and s.name == "Shadows" and s.points[1].text == "0", tostring(m.lines[1])
end)

-- Results window, Task 2: the graph model (spec 2026-10-30-results-window-design.md sections 3.2 and 3.4, amendments A2 to A8)
local function dms(fps, baseline) return 1000 / fps - (baseline or 4.0) end
local function fpsList(g)
    local out = {}
    for i, p in ipairs(g.points) do out[i] = string.format("%.2f", p.fps) end
    return table.concat(out, ",")
end
local function lineList(g) return table.concat(g.lines, " | ") end
local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

test("GM-1 the verdict says how many changes and where they take you, measured when the check ran", function()
    local _, r = boot()
    local two = r.chartModel(r.choose(T1(), 250))
    local one = r.chartModel(r.choose(T1(), 210))
    local checked = r.chartModel(r.choose(T1(), 210), { ok = true, appliedMs = 3.5, baselineMs = 4.0 })
    local none = r.chartModel(r.choose(T1(), 100))
    return two.verdict == "These 2 changes should take you from about 250 fps to about 333 fps."
        and one.verdict == "This change should take you from about 250 fps to about 270 fps." and #one.lines == 1
        and checked.verdict == "This change should take you from about 250 fps to about 286 fps."
        and none.verdict == none.summary and none.summary ~= nil, two.verdict .. " / " .. one.verdict .. " / " .. checked.verdict
end)

test("GM-2 a change line carries what that setting does on its own: saves, costs, or less than one frame", function()
    local _, r = boot()
    local tiny = r.chartModel({ status = "change", kind = "quiet", nowMs = 4.0, nowFps = 250, afterMs = 3.99, afterFps = 250.6, target = 250,
        changes = { { cvar = "graphicsShadowQuality", setting = "Shadows", from = "2", to = "1", fromDelta = 0, toDelta = -0.003 } },
        unchanged = {}, settings = {}, notMeasured = {} })
    local tinyCost = r.chartModel({ status = "change", kind = "quiet", nowMs = 4.0, nowFps = 250, afterMs = 4.003, afterFps = 249.8, target = 250,
        changes = { { cvar = "graphicsShadowQuality", setting = "Shadows", from = "2", to = "3", fromDelta = 0, toDelta = 0.003 } },
        unchanged = {}, settings = {}, notMeasured = {} })
    local rebased = r.chartModel({ status = "change", kind = "quiet", nowMs = 4.0, nowFps = 250, afterMs = 3.6, afterFps = 277.8, target = 250,
        changes = { { cvar = "graphicsShadowQuality", setting = "Shadows", from = "3", to = "1", fromDelta = 0.5, toDelta = -0.4 } },
        unchanged = {}, settings = {}, notMeasured = {} })
    return tiny.lines[1] == "Shadow detail: 2 to 1, saves less than 1 fps." and tinyCost.lines[1] == "Shadow detail: 2 to 3, costs less than 1 fps."
        and rebased.lines[1] == "Shadow detail: 3 to 1, saves about 73 fps.", tiny.lines[1] .. " / " .. tinyCost.lines[1] .. " / " .. rebased.lines[1]
end)

-- A setting the recommendation leaves where it is: its current point is ringed, never also "recommended".
local function unchangedStaysUnmarked(r)
    local o = r.chartModel(r.choose(owner(), 165))
    local ssao = graphOf(o, "graphicsSSAO")
    if not ssao or ssao.changed then return false end
    for _, p in ipairs(ssao.points) do
        if p.recommended then return false end
    end
    return true
end

test("GM-3 a graph has one point per measured level at the frame rate that level would give, the current one and the recommended one marked", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(T1(), 250))
    local g = graphOf(m, "graphicsShadowQuality")
    local ssao = graphOf(m, "graphicsSSAO")
    local p = g.points
    local gappy = r.chartModel(r.choose(entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", status = "inconclusive" }, { "2", 0, current = true },
            { "3", 5.0, flags = { "lighting may have changed" } } }),
        rows("graphicsSSAO", 4.0, { { "0", -0.6 }, { "2", 0, current = true } })), 100))
    local clamped = r.chartModel(r.choose(entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", -3.9 }, { "1", 0, current = true } })), 100))
    return g.name == "Shadow detail" and fpsList(g) == "333.33,277.78,250.00" and p[3].current == true and p[1].current == false
        and p[2].recommended == true and p[1].recommended == false and p[3].recommended == false
        and p[1].text == "0" and p[1].value == "0" and fpsList(ssao) == "294.12,270.27,250.00" and ssao.points[1].recommended == true
        and #graphOf(gappy, "graphicsShadowQuality").points == 2 and graphOf(gappy, "graphicsShadowQuality").points[1].value == "0"
        and near(graphOf(clamped, "graphicsShadowQuality").points[1].fps, 1000, 1e-6)
        and unchangedStaysUnmarked(r),
        fpsList(g) .. " " .. fpsList(clamped.graphs[1])
end)

test("GM-4 the shared axis uses round steps, spans every point, and is widened to three ticks", function()
    local _, r = boot()
    local a = r.axisFor(250, 333.33)
    local b = r.axisFor(450, 800)
    local c = r.axisFor(250, 250)
    local d = r.axisFor(100, 900)
    local e = r.axisFor(3, 3)
    local zero = r.axisFor(0, 0)
    local m = r.chartModel(r.choose(T1(), 250))
    local function ticks(x) return table.concat(x.ticks, ",") end
    return ticks(a) == "250,275,300,325,350" and a.step == 25 and a.min == 250 and a.max == 350
        and ticks(b) == "400,500,600,700,800" and b.step == 100
        and ticks(c) == "245,250,255" and c.step == 5
        and ticks(d) == "0,250,500,750,1000" and d.step == 250
        and ticks(e) == "0,5,10" and ticks(zero) == "0,5,10"
        and ticks(m.axis) == "250,275,300,325,350" and m.axis.min == 250 and m.axis.max == 350,
        ticks(a) .. " / " .. ticks(b) .. " / " .. ticks(c) .. " / " .. ticks(d) .. " / " .. ticks(e)
end)

test("GM-5 graphs are ordered by swing, the first changed one is selected, else the first; no graphs, nothing selected", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(T1(), 250))
    local ranking = { graphicsShadowQuality = { weight = 6, raise = false }, graphicsSSAO = { weight = 3, raise = true } }
    local raised = r.chartModel(r.choose(entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "0", -0.1 }, { "1", 0, current = true }, { "2", 0.05 } })), 100, { ranking = ranking }))
    local nothing = r.chartModel(r.choose(T1(), 100))
    local nodata = r.chartModel(r.choose(unmeasured(), 165))
    local backwards = r.chartModel(r.choose(entry(4.0,          -- the small swing comes first in the entry, the large one second
        rows("graphicsSSAO", 4.0, { { "0", -0.1 }, { "1", 0, current = true } }),
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", 0, current = true } })), 100))
    return m.graphs[1].cvar == "graphicsShadowQuality" and m.graphs[2].cvar == "graphicsSSAO" and near(m.graphs[1].swing, 83.33, 0.01)
        and backwards.graphs[1].cvar == "graphicsShadowQuality" and backwards.graphs[2].cvar == "graphicsSSAO"
        and near(m.graphs[2].swing, 44.12, 0.01) and m.graphs[1].changed == true and m.selected == "graphicsShadowQuality"
        and raised.graphs[1].cvar == "graphicsShadowQuality" and raised.graphs[1].changed == false and raised.graphs[2].changed == true
        and raised.selected == "graphicsSSAO"
        and nothing.selected == "graphicsShadowQuality" and nothing.graphs[1].changed == false
        and #nodata.graphs == 0 and nodata.selected == nil and nodata.axis == nil,
        tostring(m.selected) .. " " .. tostring(raised.selected)
end)

test("GM-6 under a graph: the two biggest costs between neighbouring levels in level order, or that nothing made a difference", function()
    local _, r = boot()
    local m = r.chartModel(r.choose(T1(), 250))
    local function fourLevels(f0, f1, f2)
        return entry(4.0, rows("graphicsShadowQuality", 4.0,
            { { "0", dms(f0) }, { "1", dms(f1) }, { "2", dms(f2) }, { "3", 0, current = true } }))
    end
    local three = r.chartModel(r.choose(fourLevels(310, 305, 285), 100))        -- steps 5, 20, 35
    local flat = r.chartModel(r.choose(entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", 0 }, { "1", 0, current = true } })), 100))
    local nearlyFlat = r.chartModel(r.choose(entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", dms(250.9) }, { "1", 0, current = true } })), 100))
    local justOver = r.chartModel(r.choose(entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", dms(251.2) }, { "1", 0, current = true } })), 100))
    return sameList(graphOf(m, "graphicsShadowQuality").lines, { "0 to 1 costs about 56 fps.", "1 to 2 costs about 28 fps." })
        and sameList(three.graphs[1].lines, { "1 to 2 costs about 20 fps.", "2 to 3 costs about 35 fps." })
        and sameList(flat.graphs[1].lines, { "This setting made no measurable difference here." })
        and sameList(nearlyFlat.graphs[1].lines, { "This setting made no measurable difference here." })
        and sameList(justOver.graphs[1].lines, { "0 to 1 costs about 1 fps." }),
        lineList(graphOf(m, "graphicsShadowQuality")) .. " // " .. lineList(three.graphs[1])
end)

test("GM-7 a level that measured faster than the one below it by more than three per cent of the frame time marks both as doubtful", function()
    local _, r = boot()
    local function curve(d2)
        return r.chartModel(r.choose(entry(4.0, rows("graphicsShadowQuality", 4.0,
            { { "0", -1.5 }, { "1", -0.30 }, { "2", d2 }, { "3", 0, current = true } })), 100))
    end
    local odd = curve(-0.9)
    local within = curve(-0.40)             -- 0.10 ms faster than the level below: under 0.03 * 4.0
    local beyond = curve(-0.44)             -- 0.14 ms faster: over it
    local function flags(m)
        local out = {}
        for i, p in ipairs(m.graphs[1].points) do out[i] = p.doubtful and "d" or "-" end
        return table.concat(out)
    end
    local LOOK = "Some readings look off; run the test again to confirm."
    local lastOdd = odd.graphs[1].lines[#odd.graphs[1].lines]
    return flags(odd) == "-dd-" and flags(within) == "----" and flags(beyond) == "-dd-" and lastOdd == LOOK
        and within.graphs[1].lines[#within.graphs[1].lines] ~= LOOK and r.DOUBTFUL == 0.03, flags(odd) .. " " .. flags(within) .. " " .. flags(beyond)
end)

test("GM-8 what can be saved: changes, or the current settings when nothing needs changing, otherwise nothing", function()
    local _, r = boot()
    local change = r.chartModel(r.choose(T1(), 250))
    local nochange = r.chartModel(r.choose(T1(), 100))
    local unreachable = r.chartModel(r.choose(T1(), 500))
    local nodata = r.chartModel(r.choose(unmeasured(), 165))
    local bad = T1()
    bad.valid = false
    local invalid = r.chartModel(r.choose(bad, 250))
    local anyRecommended = false
    for _, g in ipairs(unreachable.graphs) do
        anyRecommended = anyRecommended or g.changed
        for _, p in ipairs(g.points) do anyRecommended = anyRecommended or p.recommended end
    end
    return change.saveKind == "changes" and nochange.saveKind == "current" and unreachable.saveKind == nil and nodata.saveKind == nil
        and invalid.saveKind == nil and #unreachable.graphs == 2 and anyRecommended == false
        and #nodata.graphs == 0 and #invalid.graphs == 0 and invalid.axis == nil and invalid.verdict == invalid.summary
        and unreachable.verdict == unreachable.summary and nodata.verdict == nodata.summary, tostring(change.saveKind)
end)

test("GM-9 an entry saved before this version, and a crowd result, build their graphs with no error", function()
    local _, r = boot()
    local old = T1()
    for _, row in ipairs(old.rows) do row.flags, row.hitches, row.time = nil, nil, nil end
    local a = r.chartModel(r.choose(old, 250))
    local b = r.chartModel(r.choose(T1(), 250))
    local crowd = r.chartModel(r.choose(r.crowdEntry(Q(), C1()), 100))
    return fpsList(graphOf(a, "graphicsShadowQuality")) == fpsList(graphOf(b, "graphicsShadowQuality")) and a.saveKind == "changes"
        and #crowd.graphs >= 1 and crowd.saveKind == "changes" and graphOf(crowd, "graphicsShadowQuality") ~= nil
        and near(graphOf(crowd, "graphicsShadowQuality").points[1].fps, 1000 / (10.0 - 3.0), 1e-6), fpsList(graphOf(crowd, "graphicsShadowQuality"))
end)

test("GM-10 a setting with equal points, and one measured only at its current level, give a graph or a not-measured entry and no error", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", 0 }, { "1", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } }))
    local m = r.chartModel(r.choose(e, 100))
    return #m.graphs == 1 and fpsList(m.graphs[1]) == "250.00,250.00" and m.axis.min == 245 and m.axis.max == 255
        and #m.notMeasured == 1 and m.notMeasured[1].cvar == "graphicsSSAO" and m.notMeasured[1].name == "Soft corner shadows",
        tostring(m.axis and m.axis.min)
end)

test("GM-11 loaded with no names table the graphs fall back to the row labels and raw levels", function()
    local env = { ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, tonumber = tonumber,
        math = math, string = string, table = table, select = select }
    local ns = {}
    local chunk = assert(load(RECOMMEND_SRC, "=Recommend.lua", "t", env))
    chunk("ForeverSettings", ns)
    local m = ns.recommend.chartModel(ns.recommend.choose(T1(), 250))
    local g = graphOf(m, "graphicsShadowQuality")
    return g.name == "Shadows" and g.points[1].text == "0" and m.lines[1] == "Shadows: 2 to 1, saves about 28 fps.", tostring(g and g.name)
end)

test("GM-12 both footers keep their old sentence and end with the one about overlapping figures", function()
    local _, r = boot()
    local everyday = r.chartModel(r.choose(T1(), 250)).footer
    local crowd = r.chartModel(r.choose(r.crowdEntry(Q(), C1()), 100)).footer
    return everyday:sub(1, #FOOTER) == FOOTER and everyday:sub(-#OVERLAP) == OVERLAP and #everyday == #FOOTER + #OVERLAP
        and crowd:sub(1, #CROWD_FOOTER) == CROWD_FOOTER and crowd:sub(-#OVERLAP) == OVERLAP and #crowd == #CROWD_FOOTER + #OVERLAP, crowd
end)

test("GM-13 a setting that could not be measured says why in plain words, for every kind of reason the tests produce", function()
    local _, r = boot()
    local cases = {
        { "no usable measurement", "the test couldn't measure it" },
        { "rejected, clamped to 3", "the game wouldn't take that level" },
        { "inconclusive (stall)", "the game froze for a moment while testing it" },
        { "inconclusive (few)", "the game ran too slowly to measure it" },
        { "inconclusive (baseline drifted 5.0%)", "the frame rate kept changing while testing it" },
        { "inconclusive (baseline moved 7.5% since the start)", "the frame rate kept changing while testing it" },
        { "inconclusive (movement)", "the test couldn't get a steady reading for it" },
        { "live level not covered by the quiet-spot test", "the level you use now wasn't part of your quiet-spot test" },
        { "something nobody planned", "the test couldn't measure it" },
        { nil, "the test couldn't measure it" },
    }
    local bad = {}
    for _, c in ipairs(cases) do
        if r.plainReason(c[1]) ~= c[2] then bad[#bad + 1] = tostring(c[1]) .. " -> " .. tostring(r.plainReason(c[1])) end
    end
    -- and it reaches the chart model: the raw reason stays, a plain one is added
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } }))
    local m = r.chartModel(r.choose(e, 100))
    return #bad == 0 and m.notMeasured[1].reason == "no usable measurement" and m.notMeasured[1].plain == "the test couldn't measure it",
        table.concat(bad, "; ")
end)

-- Maximum and costs (W3, Task 1): spec 2026-10-30-maximum-and-costs-design.md sections 3.2 and 4
local function fpsFrom(r, e, cvar, value)
    local info = r.levelFps(e)
    for _, level in ipairs(info and info.byCvar[cvar] or {}) do
        if level.value == value then return level.fps end
    end
    return nil
end

test("LC-1 every counted level has the frame rate it would give if only that setting changed", function()
    local _, r = boot()
    local info = r.levelFps(T1())
    local function list(cvar)
        local out = {}
        for i, level in ipairs(info.byCvar[cvar]) do out[i] = level.value .. "=" .. string.format("%.2f", level.fps) end
        return table.concat(out, ",")
    end
    return near(info.nowFps, 250) and list("graphicsShadowQuality") == "0=333.33,1=277.78,2=250.00"
        and list("graphicsSSAO") == "0=294.12,1=270.27,2=250.00", list("graphicsShadowQuality")
end)

test("LC-2 a level without a usable measurement, and a setting with nothing but its current level, are absent", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", status = "inconclusive" }, { "2", 0, current = true },
            { "3", 5.0, flags = { "lighting may have changed" } } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } }))
    local info = r.levelFps(e)
    local values = {}
    for i, level in ipairs(info.byCvar.graphicsShadowQuality) do values[i] = level.value end
    return table.concat(values, ",") == "0,2" and info.byCvar.graphicsSSAO == nil, table.concat(values, ",")
end)

test("LC-3 a level that would be faster than the speed-up cap allows is clamped, as in the graph", function()
    local _, r = boot()
    local e = entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", -3.9 }, { "1", 0, current = true } }))
    return near(fpsFrom(r, e, "graphicsShadowQuality", "0"), 1000, 1e-6), tostring(fpsFrom(r, e, "graphicsShadowQuality", "0"))
end)

test("LC-4 an invalid entry gives nothing, and a run that measured nothing gives an empty list", function()
    local _, r = boot()
    local bad = T1()
    bad.valid = false
    local info = r.levelFps(entry(4.75,
        rows("graphicsShadowQuality", 3.44, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } })))
    return r.levelFps(bad) == nil and r.levelFps(nil) == nil and info ~= nil and next(info.byCvar) == nil, tostring(info)
end)

test("LC-5 the frame rates are the very points of the results window's graphs", function()
    local _, r = boot()
    local model = r.chartModel(r.choose(T1(), 250))
    local info = r.levelFps(T1())
    local same = true
    for _, g in ipairs(model.graphs) do
        for i, point in ipairs(g.points) do
            local level = info.byCvar[g.cvar][i]
            same = same and level ~= nil and level.value == point.value and near(level.fps, point.fps, 1e-9)
        end
    end
    return same and #model.graphs == 2, tostring(same)
end)

test("EF-1 the estimate of a set of levels is today's frame time plus each setting's measured difference", function()
    local _, r = boot()
    local est = r.estimateFps(T1(), { graphicsShadowQuality = "0", graphicsSSAO = "0" })
    return near(est.ms, 2.4, 1e-9) and near(est.fps, 416.67, 0.01) and #est.missing == 0, tostring(est.fps)
end)

test("EF-2 a setting that is not in the set adds nothing", function()
    local _, r = boot()
    local est = r.estimateFps(T1(), { graphicsSSAO = "0" })
    return near(est.ms, 3.4, 1e-9) and near(est.fps, 294.12, 0.01) and #est.missing == 0, tostring(est.ms)
end)

test("EF-3 a level that was not measured, and a setting that is not in the entry, are listed in order and the rest still adds up", function()
    local _, r = boot()
    local est = r.estimateFps(T1(), { graphicsSSAO = "0", graphicsShadowQuality = "4", RenderScale = "1", zz = "1", aa = "1", mm = "1" })
    return #est.missing == 5 and table.concat(est.missing, ",") == "RenderScale,aa,graphicsShadowQuality,mm,zz"
        and near(est.ms, 3.4, 1e-9), table.concat(est.missing, ",")
end)

test("EF-8 a level the test measured but threw out (a flagged window) is missing, not counted", function()
    local _, r = boot()
    local e = entry(4.0, rows("graphicsShadowQuality", 4.0,
        { { "0", -1.0 }, { "2", 0, current = true }, { "3", 5.0, flags = { "lighting may have changed" } } }))
    local est = r.estimateFps(e, { graphicsShadowQuality = "3" })
    return est ~= nil and #est.missing == 1 and est.missing[1] == "graphicsShadowQuality" and near(est.ms, 4.0, 1e-9), tostring(est and est.ms)
end)

test("EF-4 levels equal as numbers match however they are written", function()
    local _, r = boot()
    local e = entry(4.0, rows("RenderScale", 4.0, { { "0.5", -1.0 }, { "0.75", -0.5 }, { "1", 0, current = true } }))
    local est = r.estimateFps(e, { RenderScale = "0.750000" })
    local whole = r.estimateFps(e, { RenderScale = "1.000000" })
    return #est.missing == 0 and near(est.ms, 3.5, 1e-9) and #whole.missing == 0 and near(whole.ms, 4.0, 1e-9), tostring(est.ms)
end)

test("EF-5 the estimate never claims more than the speed-up cap", function()
    local _, r = boot()
    local e = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -2.5 }, { "1", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "0", -2.0 }, { "1", 0, current = true } }))
    local est = r.estimateFps(e, { graphicsShadowQuality = "0", graphicsSSAO = "0" })
    return near(est.ms, 4.0 / r.MAX_SPEEDUP, 1e-9) and near(est.fps, 1000, 1e-6), tostring(est.ms)
end)

test("EF-6 an invalid entry and a run that measured nothing give no estimate", function()
    local _, r = boot()
    local bad = T1()
    bad.valid = false
    local nodata = entry(4.75,
        rows("graphicsShadowQuality", 3.44, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }))
    return r.estimateFps(bad, { graphicsSSAO = "0" }) == nil and r.estimateFps(nodata, { graphicsSSAO = "0" }) == nil
        and r.estimateFps(nil, {}) == nil
end)

test("EF-7 a crowd entry gives an estimate on the crowd's numbers", function()
    local _, r = boot()
    local ce = r.crowdEntry(Q(), C1())
    local est = r.estimateFps(ce, { graphicsShadowQuality = "0" })
    return est ~= nil and #est.missing == 0 and near(est.ms, 7.0, 1e-9) and near(est.fps, 1000 / 7.0, 1e-6), tostring(est and est.ms)
end)

return H.results()
