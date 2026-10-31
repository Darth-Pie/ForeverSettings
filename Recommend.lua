-- Recommend.lua: the recommendation rules and the numbers behind the charts (spec 2026-10-29-recommender-design.md).
-- Pure: it reads nothing from the game, so every rule can be tested without one. Loaded after Profiles.lua and
-- before UI.lua.
local _, ns = ...

local recommend = {}
ns.recommend = recommend

recommend.TARGETS = { 60, 90, 120, 144, 165, 240 }
-- The share of the target's frame time kept free: the empty spot is the easy case (spec section 4).
recommend.MARGIN = 0.20
-- The estimate adds each setting's separately measured saving, and savings overlap on a game that is limited by the
-- graphics card; it never claims more than this speed-up over today's frame time (the sum could pass zero).
recommend.MAX_SPEEDUP = 4

-- weight: how much the setting matters to how the game looks (higher is cut last).
-- raise: may be raised above the player's current level (texture resolution costs memory, which the benchmark cannot
-- see; ground clutter is often a visibility preference).
recommend.RANKING = {
    RenderScale = { weight = 10, raise = true },
    graphicsTextureResolution = { weight = 9, raise = false },
    graphicsShadowQuality = { weight = 6, raise = true },
    giQuality = { weight = 5, raise = true },
    graphicsLightMode = { weight = 5, raise = true },
    graphicsSSAO = { weight = 3, raise = true },
    graphicsGroundClutter = { weight = 3, raise = false },
    groundEffectDensity = { weight = 3, raise = false },
    graphicsLiquidDetail = { weight = 2, raise = true },
    graphicsComputeEffects = { weight = 2, raise = true },
}

-- Flags that make a measurement unusable. `no measurable effect or not applied` does not: its deltas are real.
local UNUSABLE = { ["possible background-window cap"] = true, ["lighting may have changed"] = true }

-- A level counts when it was measured and no flag throws it out.
local function counted(row)
    if row.status ~= nil then return false end
    if type(row.meanMs) ~= "number" or type(row.deltaMs) ~= "number" then return false end
    for _, flag in ipairs(row.flags or {}) do
        if UNUSABLE[flag] then return false end
    end
    return true
end

-- A setting whose live value was not one of the measured levels has no `current` row. The value it had is a level of
-- its own, costing nothing against itself (every delta is measured against the setting's own baseline), and sits at
-- its numeric place among the levels. A start that is not a number is left out: the setting stays not measured.
local function addCurrent(g, start)
    for _, level in ipairs(g.levels) do
        if level.current then return end
    end
    local n = tonumber(start)
    if not n then return end
    local at = #g.levels + 1
    for i, level in ipairs(g.levels) do
        local v = tonumber(level.value)
        if v and v > n then
            at = i
            break
        end
    end
    table.insert(g.levels, at, { value = string.format("%g", n), deltaMs = 0, counted = true, current = true })
end

-- The entry's rows grouped by cvar in order of first appearance, each setting's levels in row order (ascending).
local function group(rows, starts)
    local order, by = {}, {}
    for _, row in ipairs(rows or {}) do
        local g = by[row.cvar]
        if not g then
            g = { cvar = row.cvar, setting = row.setting, levels = {} }
            by[row.cvar] = g
            order[#order + 1] = g
        end
        g.levels[#g.levels + 1] = {
            value = row.value, deltaMs = row.deltaMs, counted = counted(row), current = row.current == true,
            why = row.notMeasuredReason,
        }
    end
    for _, g in ipairs(order) do addCurrent(g, starts and starts[g.cvar]) end
    return order
end

local function whole(x)
    return string.format("%.0f", x)
end

local NODATA = "The test couldn't get a steady reading here, so there is nothing to recommend. "
    .. "The frame rate kept changing between checks. Try again somewhere quiet, keep the camera still, and close other programs."

-- A crowd that never held steady is not cured by a quiet spot, so it does not send the player to one.
local NODATA_CROWD = "The test couldn't get a steady reading in this crowd, so there is nothing to recommend. "
    .. "The frame rate kept changing between checks. Try again in a moment, or in another busy place; keep the camera still "
    .. "and close other programs."

-- Chooses a level for every setting measured in `entry` (a valid history entry) so the picture is as good as the
-- target frame rate allows. Returns the result table described in the plan, Task 1.
function recommend.choose(entry, target, options)
    options = options or {}
    -- A crowd entry (crowdEntry) keeps more headroom and never raises; so does a quick quiet-spot entry, whose top levels
    -- were not measured.
    local crowd = entry ~= nil and entry.kind == "crowd"
    local margin = options.margin or (crowd and recommend.CROWD_MARGIN or recommend.MARGIN)
    local ranking = options.ranking or recommend.RANKING
    local noRaise = crowd or (entry ~= nil and entry.mode == "quick")
    local result = { status = "nochange", changes = {}, unchanged = {}, notMeasured = {}, settings = {}, target = target,
        kind = crowd and "crowd" or "quiet" }
    if not entry or entry.valid ~= true then
        result.status = "invalid"
        result.summary = "That test did not finish, so there is nothing to recommend."
        return result
    end
    result.budgetMs = 1000 / target * (1 - margin)
    result.nowMs = entry.baselineMs
    result.nowFps = 1000 / result.nowMs

    -- Which settings can be reasoned about, and where each starts.
    local work = {}
    for _, g in ipairs(group(entry.rows, entry.starts)) do
        local current, others, top = nil, 0, nil
        for i, level in ipairs(g.levels) do
            if level.counted then
                if level.current then current = i else others = others + 1 end
                top = i
            end
        end
        if not current or others == 0 then
            local why = "no usable measurement"
            for _, level in ipairs(g.levels) do
                if level.why then why = level.why break end
            end
            result.notMeasured[#result.notMeasured + 1] = { cvar = g.cvar, setting = g.setting, reason = why }
        else
            local rule = ranking[g.cvar]
            local chosen = current
            if rule and rule.raise and not noRaise then chosen = top end
            work[#work + 1] = { g = g, current = current, chosen = chosen }
        end
    end

    -- Nothing could be measured (every setting's baseline drifted, or the entry holds no rows): say so. Never say the
    -- settings already hold the target, which nothing has shown.
    if #work == 0 then
        result.status = "nodata"
        result.afterMs, result.afterFps = result.nowMs, result.nowFps
        result.summary = crowd and NODATA_CROWD or NODATA
        return result
    end

    -- Lower settings until the estimate fits the budget (spec section 4, step 3). A setting that is not in the ranking
    -- is never lowered.
    local function estimate()
        local sum = result.nowMs
        for _, w in ipairs(work) do sum = sum + w.g.levels[w.chosen].deltaMs end
        return sum
    end
    while estimate() > result.budgetMs do
        local best
        for _, w in ipairs(work) do
            local rule = ranking[w.g.cvar]
            if rule then
                local levels = w.g.levels
                local here = levels[w.chosen].deltaMs
                -- The nearest counted lower level that is cheaper; a lower level that is not cheaper is skipped.
                local to
                for i = w.chosen - 1, 1, -1 do
                    if levels[i].counted and levels[i].deltaMs < here then
                        to = i
                        break
                    end
                end
                if to then
                    local lost = 0
                    for i = to, w.chosen - 1 do
                        if levels[i].counted then lost = lost + 1 end
                    end
                    local ratio = rule.weight * lost / (here - levels[to].deltaMs)
                    if not best or ratio < best.ratio or (ratio == best.ratio and rule.weight < best.weight) then
                        best = { w = w, to = to, ratio = ratio, weight = rule.weight }
                    end
                end
            end
        end
        if not best then break end
        best.w.chosen = best.to
    end

    local total = 0
    for _, w in ipairs(work) do
        local levels = w.g.levels
        total = total + levels[w.chosen].deltaMs
        local setting = {
            cvar = w.g.cvar, setting = w.g.setting, levels = {},
            current = levels[w.current].value, chosen = levels[w.chosen].value,
        }
        for i, level in ipairs(levels) do
            setting.levels[i] = { value = level.value, deltaMs = level.deltaMs, counted = level.counted, current = level.current }
        end
        result.settings[#result.settings + 1] = setting
        if w.chosen ~= w.current then
            result.changes[#result.changes + 1] = {
                cvar = w.g.cvar, setting = w.g.setting, from = levels[w.current].value, to = levels[w.chosen].value,
                fromDelta = levels[w.current].deltaMs, toDelta = levels[w.chosen].deltaMs,
            }
        else
            result.unchanged[#result.unchanged + 1] = { cvar = w.g.cvar, setting = w.g.setting }
        end
    end
    result.afterMs = math.max(result.nowMs + total, result.nowMs / recommend.MAX_SPEEDUP)
    result.afterFps = 1000 / result.afterMs
    if result.afterMs > result.budgetMs then
        -- Even the lowest levels do not fit: nothing is recommended (spec section 4, step 4).
        result.status = "unreachable"
        result.changes, result.unchanged = {}, {}
        for _, s in ipairs(result.settings) do
            result.unchanged[#result.unchanged + 1] = { cvar = s.cvar, setting = s.setting }
        end
        local fps = result.afterFps
        local lowest = "Even the lowest settings are estimated at about " .. whole(fps) .. " fps, "
        if fps < target then
            result.summary = lowest .. "short of your " .. whole(target) .. ". "
                .. "The game is probably limited by something other than graphics settings, usually the processor."
        else
            result.summary = lowest .. "which is not enough above your " .. whole(target)
                .. " to leave room for busier places. Try a lower target."
        end
    elseif #result.changes == 0 then
        result.status = "nochange"
        result.summary = "Good news: your settings already hold " .. whole(target) .. " fps" .. (crowd and " in crowds" or "")
            .. " with room to spare. Nothing to change."
    else
        result.status = "change"
    end
    return result
end

-- The crowd recommendation (spec 2026-10-29-crowd-test-design.md section 5) -------------------------------------------

-- Crowded keeps less headroom than Everyday (the check shows what the player really gets), the crowd's saving may scale
-- a quiet-spot curve by at most this factor, and a curve flatter than FLAT_MS at its lowest level cannot be scaled.
recommend.CROWD_MARGIN = 0.10
recommend.CROWD_FACTOR_MAX = 4
recommend.FLAT_MS = 0.05

local UNCOVERED = "live level not covered by the quiet-spot test"

-- The delta a setting's quiet-spot curve has at the level the player holds now: that level's own delta when it is a
-- measured one, else linear between its two neighbours; nil when it is not a number or lies outside the measured levels.
-- `levels` ascend and carry `counted`, `value` and `deltaMs`, as `group` makes them.
local function liveDelta(levels, live)
    local n = tonumber(live)
    if not n then return nil end
    local lo, hi
    for _, level in ipairs(levels) do
        local v = tonumber(level.value)
        if level.counted and v then
            if v == n then return level.deltaMs end
            if v < n then lo = level elseif not hi then hi = level end
        end
    end
    if not lo or not hi then return nil end
    local a, b = tonumber(lo.value), tonumber(hi.value)
    return lo.deltaMs + (hi.deltaMs - lo.deltaMs) * (n - a) / (b - a)
end

local function statusRow(setting, cvar, value, status, reason)
    return { setting = setting, cvar = cvar, value = value or "?", status = status, reason = reason,
        notMeasuredReason = reason, flags = {} }
end

local function valueRow(setting, cvar, value, delta, baseline, current)
    return { setting = setting, cvar = cvar, value = value, deltaMs = delta, meanMs = baseline + delta, flags = {},
        current = current or nil }
end

-- One quiet-spot setting's rows in the crowd: its counted levels rebased to the live level, each delta scaled by how
-- much the crowd saved at the lowest level (or a straight line when the curve is flat). No rows when nothing is below
-- the live level.
local function scaledRows(g, c, live, baseline)
    local d0 = liveDelta(g.levels, live)
    if not d0 then return { statusRow(g.setting, g.cvar, c.lowValue, "unmeasured", UNCOVERED) } end
    local n = tonumber(live)
    local list, liveAt = {}, nil
    local function addLive()
        list[#list + 1] = { value = string.format("%g", n), delta = d0, live = true }
        liveAt = #list
    end
    for _, level in ipairs(g.levels) do
        local v = tonumber(level.value)
        if level.counted and v then
            if not liveAt and v > n then addLive() end
            list[#list + 1] = { value = level.value, delta = level.deltaMs, live = v == n }
            if v == n then liveAt = #list end
        end
    end
    if not liveAt then addLive() end
    if liveAt == 1 then return {} end
    for _, item in ipairs(list) do item.rebased = item.delta - d0 end
    local saved = type(c.lowDelta) == "number" and c.lowDelta < 0 and c.lowDelta or nil
    local lowest = list[1].rebased
    local flat = math.abs(lowest) < recommend.FLAT_MS
    local factor = 0
    if saved and not flat then
        factor = math.min(math.max(saved / lowest, 0), recommend.CROWD_FACTOR_MAX)
    end
    local out = {}
    for i, item in ipairs(list) do
        local delta
        if item.live or not saved then
            delta = 0
        elseif flat then
            delta = saved * (liveAt - i) / (liveAt - 1)
        elseif factor == 0 then
            delta = 0
        else
            delta = factor * item.rebased
        end
        -- The level the crowd measured keeps what was measured; the limit only bounds the levels in between, which are
        -- estimates (a setting can matter far more in a crowd than in an empty place).
        if saved and tonumber(item.value) == tonumber(c.lowValue) then delta = saved end
        out[#out + 1] = valueRow(g.setting, g.cvar, item.value, delta, baseline, item.live)
    end
    return out
end

-- A setting only the crowd measured has two levels: where the player is (nothing saved) and its lowest.
local function crowdOnlyRows(c, live, baseline)
    local n, low = tonumber(live), tonumber(c.lowValue)
    if not n or not low then return { statusRow(c.setting or c.cvar, c.cvar, c.lowValue, "unmeasured", UNCOVERED) } end
    if low >= n or type(c.lowDelta) ~= "number" then return {} end
    return {
        valueRow(c.setting or c.cvar, c.cvar, c.lowValue, c.lowDelta, baseline, false),
        valueRow(c.setting or c.cvar, c.cvar, string.format("%g", n), 0, baseline, true),
    }
end

-- Builds an entry in the shape `choose` reads from a quiet-spot entry and a crowd measurement (Bench.lua, bench.crowd):
-- for every setting the crowd measured, the quiet-spot curve rebased to the live level and scaled to the crowd's saving.
function recommend.crowdEntry(quiet, crowd)
    crowd = crowd or {}
    local entry = {
        kind = "crowd", valid = crowd.valid == true and type(crowd.baselineMs) == "number" and quiet ~= nil and quiet.valid == true,
        reason = crowd.reason, baselineMs = crowd.baselineMs, starts = crowd.starts or {}, rows = {},
    }
    if not entry.valid then return entry end
    local byCvar, used = {}, {}
    for _, c in ipairs(crowd.settings or {}) do byCvar[c.cvar] = c end
    local function add(list)
        for _, row in ipairs(list) do entry.rows[#entry.rows + 1] = row end
    end
    for _, g in ipairs(group(quiet.rows, quiet.starts)) do
        local c = byCvar[g.cvar]
        if c then
            used[g.cvar] = true
            if c.status then
                add({ statusRow(g.setting, g.cvar, c.lowValue, c.status, c.reason or c.status) })
            else
                add(scaledRows(g, c, entry.starts[g.cvar], entry.baselineMs))
            end
        end
    end
    for _, c in ipairs(crowd.settings or {}) do
        if not used[c.cvar] then
            if c.status then
                add({ statusRow(c.setting or c.cvar, c.cvar, c.lowValue, c.status, c.reason or c.status) })
            else
                add(crowdOnlyRows(c, entry.starts[c.cvar], entry.baselineMs))
            end
        end
    end
    return entry
end

-- The charts (spec section 5) -----------------------------------------------------------------------------------

-- The sentence about the fps figures of the changes and the graphs: each is one setting on its own, and they overlap.
local OVERLAP = " Each fps figure is that setting on its own; together they overlap, so the total is the number in the bars."
local FOOTER = "Bars show speed on your PC in an empty spot, not how the picture looks." .. OVERLAP
local CROWD_FOOTER = "Each setting's lowest level was measured in this crowd; the levels in between are estimated from your quiet-spot test."
    .. OVERLAP
-- The line that points an Everyday result at the next test (spec 2026-10-29-crowd-test-design.md section 3).
local HINT = "Next, in a busy place: Find my crowded settings (minimap menu or /fset crowd)."

-- The plain name of a setting and the plain text of one of its levels (Names.lua); without that table, the row's own label
-- and the raw level.
local function nameOf(cvar, fallback)
    if ns.names then return ns.names.label(cvar, fallback) end
    return fallback
end
local function levelText(cvar, value)
    if ns.names then return ns.names.level(cvar, value) end
    return value
end

-- Why a setting could not be measured, in a phrase a friend can read after "not measured (": the benchmark's own reasons
-- ("rejected, clamped to 3", "inconclusive (stall)") name its internals. An unknown reason gets the general phrase, never
-- the raw text.
function recommend.plainReason(reason)
    reason = tostring(reason or "")
    if reason == UNCOVERED then return "the level you use now wasn't part of your quiet-spot test" end
    if reason:find("^rejected") then return "the game wouldn't take that level" end
    if reason:find("^inconclusive %(stall%)") then return "the game froze for a moment while testing it" end
    if reason:find("^inconclusive %(few%)") then return "the game ran too slowly to measure it" end
    if reason:find("^inconclusive %(baseline") then return "the frame rate kept changing while testing it" end
    if reason:find("^inconclusive") then return "the test couldn't get a steady reading for it" end
    return "the test couldn't measure it"
end

-- Frame rate at a frame time `deltaMs` above or below `nowMs`, never past the speed-up the estimate allows. The graphs, the
-- change lines and the cost of a level (levelFps) all read levels this way.
local function fpsFor(nowMs, deltaMs)
    return 1000 / math.max(nowMs + deltaMs, nowMs / recommend.MAX_SPEEDUP)
end

-- Numeric when both values parse as numbers (so "0.750000" equals "0.75"), else plain equality.
local function sameValue(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and y ~= nil and x == y
end

-- The cost of the levels (spec 2026-10-30-maximum-and-costs-design.md section 4): for every setting the test measured, the
-- frame rate of each counted level if only that setting changed, in level order, as the graph's points have it. nil for an
-- invalid entry; a run that measured nothing gives an empty list. The target never matters to what is read here.
function recommend.levelFps(entry)
    local result = recommend.choose(entry, 60)
    if result.status == "invalid" then return nil end
    local info = { nowFps = result.nowFps, byCvar = {} }
    for _, s in ipairs(result.settings) do
        local list = {}
        for _, level in ipairs(s.levels) do
            if level.counted then list[#list + 1] = { value = level.value, fps = fpsFor(result.nowMs, level.deltaMs) } end
        end
        info.byCvar[s.cvar] = list
    end
    return info
end

-- The frame rate with `values` ({cvar = level}) in force: today's frame time plus each of those settings' measured
-- difference at its level, never past the speed-up cap. A setting not in `values` adds nothing; one whose level the test did
-- not measure (or that the test did not measure at all) is listed in `missing`, sorted. nil for an invalid entry or a run
-- that measured nothing.
function recommend.estimateFps(entry, values)
    local result = recommend.choose(entry, 60)
    if result.status == "invalid" or result.status == "nodata" then return nil end
    local byCvar = {}
    for _, s in ipairs(result.settings) do byCvar[s.cvar] = s.levels end
    local sum, missing = 0, {}
    for cvar, value in pairs(values or {}) do
        local found
        for _, level in ipairs(byCvar[cvar] or {}) do
            if level.counted and sameValue(level.value, value) then
                found = level
                break
            end
        end
        if found then sum = sum + found.deltaMs else missing[#missing + 1] = cvar end
    end
    table.sort(missing)
    local ms = math.max(result.nowMs + sum, result.nowMs / recommend.MAX_SPEEDUP)
    return { fps = 1000 / ms, ms = ms, missing = missing }
end

-- The graphs (spec 2026-10-30-results-window-design.md section 3.4) -------------------------------------------------------

-- A level that measured faster than the level below it by more than this share of today's frame time looks off.
recommend.DOUBTFUL = 0.03

local AXIS_STEPS = { 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000 }

-- The fps axis shared by every graph: round numbers from `lowest` rounded down to `highest` rounded up, in the smallest
-- step that gives at most five of them, widened to three: one step above, then one below (never below zero), alternately.
function recommend.axisFor(lowest, highest)
    local step = AXIS_STEPS[#AXIS_STEPS]
    for _, s in ipairs(AXIS_STEPS) do
        if math.ceil(highest / s) - math.floor(lowest / s) <= 4 then
            step = s
            break
        end
    end
    local lo, hi = math.floor(lowest / step) * step, math.ceil(highest / step) * step
    local above = true
    while (hi - lo) / step + 1 < 3 do
        if above or lo - step < 0 then hi = hi + step else lo = lo - step end
        above = not above
    end
    local ticks = {}
    for t = lo, hi, step do ticks[#ticks + 1] = t end
    return { min = lo, max = hi, step = step, ticks = ticks }
end

-- Every number and sentence the results window draws, from a result of `choose`. No game calls.
-- `verify` is the check of the recommendation (Bench.lua, bench.verify): {ok, appliedMs, baselineMs}. The frame time
-- measured with the changes is scaled to the test's own baseline, so a place that grew busier since the test does not
-- count against the recommendation; it replaces the estimate in the "With these changes" bar.
function recommend.chartModel(result, verify)
    local crowd = result.kind == "crowd"
    local model = {
        status = result.status, canApply = result.status == "change", summary = result.summary, verdict = result.summary,
        saveKind = result.status == "change" and "changes" or (result.status == "nochange" and "current" or nil),
        lines = {}, checkLines = {}, graphs = {}, notMeasured = {}, footer = crowd and CROWD_FOOTER or FOOTER,
        title = crowd and "Your crowded settings" or "Your best settings",
    }
    local measuredFps
    if result.status == "change" and type(verify) == "table" and verify.ok == true
        and type(verify.appliedMs) == "number" and verify.appliedMs > 0
        and type(verify.baselineMs) == "number" and verify.baselineMs > 0 then
        measuredFps = 1000 / (result.nowMs * verify.appliedMs / verify.baselineMs)
    end
    if not crowd and (result.status == "change" or result.status == "nochange" or result.status == "unreachable") then
        model.hint = HINT
    end
    if result.status == "invalid" then return model end

    -- Chart A: one frame-rate scale that includes the target; the after bar only exists for a recommendation.
    local biggest = math.max(result.nowFps, result.target)
    if result.status == "change" then biggest = math.max(biggest, measuredFps or result.afterFps) end
    local scaleFps = 1.2 * biggest
    model.headline = {
        scaleFps = scaleFps,
        now = { label = "Now: about " .. whole(result.nowFps) .. " fps", fps = result.nowFps, fraction = result.nowFps / scaleFps },
        target = { label = "Your target: " .. whole(result.target) .. " fps", fps = result.target, fraction = result.target / scaleFps },
    }
    if measuredFps then
        model.headline.after = {
            label = "With these changes: about " .. whole(measuredFps) .. " fps (measured)",
            fps = measuredFps, fraction = measuredFps / scaleFps,
        }
        model.checkLines[1] = "Checked: expected about " .. whole(result.afterFps) .. " fps, measured about "
            .. whole(measuredFps) .. " fps."
        if measuredFps < 0.75 * result.afterFps then
            model.checkLines[2] = "The estimate was optimistic: about " .. whole(measuredFps) .. " fps is what to expect."
        end
    elseif result.status == "change" then
        model.headline.after = {
            label = "With these changes: about " .. whole(result.afterFps) .. " fps",
            fps = result.afterFps, fraction = result.afterFps / scaleFps,
        }
    end

    if result.status == "change" then
        local n = #result.changes
        model.verdict = (n == 1 and "This change" or ("These " .. n .. " changes")) .. " should take you from about "
            .. whole(result.nowFps) .. " fps to about " .. whole(measuredFps or result.afterFps) .. " fps."
    end

    local function fpsAt(deltaMs) return fpsFor(result.nowMs, deltaMs) end
    for _, c in ipairs(result.changes) do
        -- What this setting does on its own: the other changes are left as they are.
        local single = fpsAt(c.toDelta - c.fromDelta) - result.nowFps
        local amount = math.abs(single) < 0.5 and "less than 1 fps" or ("about " .. whole(math.abs(single)) .. " fps")
        model.lines[#model.lines + 1] = nameOf(c.cvar, c.setting) .. ": " .. levelText(c.cvar, c.from) .. " to "
            .. levelText(c.cvar, c.to) .. ", " .. (single >= 0 and "saves " or "costs ") .. amount .. "."
    end

    for _, n in ipairs(result.notMeasured) do
        model.notMeasured[#model.notMeasured + 1] = { setting = n.setting, name = nameOf(n.cvar, n.setting), cvar = n.cvar, reason = n.reason,
            plain = recommend.plainReason(n.reason) }
    end

    -- One graph per measured setting: a point for every level that counted, at the frame rate that level would give.
    local changing = result.status == "change"
    local lowest, highest
    for position, s in ipairs(result.settings) do
        local points, deltas = {}, {}
        for _, level in ipairs(s.levels) do
            if level.counted then
                local fps = fpsAt(level.deltaMs)
                points[#points + 1] = {
                    value = level.value, text = levelText(s.cvar, level.value), fps = fps, current = level.current == true,
                    recommended = changing and level.value == s.chosen and not level.current, doubtful = false,
                }
                deltas[#deltas + 1] = level.deltaMs
                if not lowest or fps < lowest then lowest = fps end
                if not highest or fps > highest then highest = fps end
            end
        end
        -- A level faster than the one below it by more than DOUBTFUL of today's frame time: both are doubtful.
        local doubtful = false
        for i = 2, #points do
            if deltas[i] < deltas[i - 1] - recommend.DOUBTFUL * result.nowMs then
                points[i].doubtful, points[i - 1].doubtful, doubtful = true, true, true
            end
        end
        -- The two biggest costs between neighbouring points (1 fps or more), shown in level order.
        local steps = {}
        for i = 1, #points - 1 do
            local cost = points[i].fps - points[i + 1].fps
            if cost >= 1 then steps[#steps + 1] = { at = i, cost = cost } end
        end
        table.sort(steps, function(a, b)
            if a.cost ~= b.cost then return a.cost > b.cost end
            return a.at < b.at
        end)
        while #steps > 2 do steps[#steps] = nil end
        table.sort(steps, function(a, b) return a.at < b.at end)
        local lines = {}
        for _, step in ipairs(steps) do
            lines[#lines + 1] = points[step.at].text .. " to " .. points[step.at + 1].text .. " costs about " .. whole(step.cost) .. " fps."
        end
        if #lines == 0 then lines[1] = "This setting made no measurable difference here." end
        if doubtful then lines[#lines + 1] = "Some readings look off; run the test again to confirm." end
        local swing = 0
        for _, p in ipairs(points) do
            for _, q in ipairs(points) do swing = math.max(swing, p.fps - q.fps) end
        end
        model.graphs[#model.graphs + 1] = {
            cvar = s.cvar, name = nameOf(s.cvar, s.setting), changed = changing and s.chosen ~= s.current, swing = swing,
            points = points, lines = lines, position = position,
        }
    end
    table.sort(model.graphs, function(a, b)
        if a.swing ~= b.swing then return a.swing > b.swing end
        return a.position < b.position
    end)
    for _, g in ipairs(model.graphs) do
        g.position = nil
        if g.changed and not model.selected then model.selected = g.cvar end
    end
    if not model.selected and model.graphs[1] then model.selected = model.graphs[1].cvar end
    if lowest then model.axis = recommend.axisFor(lowest, highest) end
    return model
end
