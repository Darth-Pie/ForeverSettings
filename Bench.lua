-- Bench.lua: an in-game benchmark for the graphics settings (spec 2026-10-28-forever-bench-design.md).
-- Sections: constants, stats, guard.
local _, ns = ...

local bench = {}
ns.bench = bench

-- Constants. The values are assumptions until `/fset bench check` measures this PC (spec section 5).
-- The table is mutable so tests can shrink the windows.
bench.K = {
    SETTLE = 3.0,         -- seconds of frame time discarded after each change (at least; see SETTLE_MAX)
    SETTLE_SLICE = 1.0,   -- seconds of frame time per slice when judging whether the frame time has settled
    SETTLE_MAX = 15,      -- most seconds a window keeps settling while the frame time still moves
    SETTLE_STEADY = 0.10, -- the last two slices settled when their mean frame times differ by no more than this
    MEASURE = 8.0,        -- seconds of frame time measured
    MIN_FRAMES = 200,     -- fewest frames for a valid window
    STALL = 1.0,          -- one frame this long invalidates the window
    NOISE = 0.05,         -- largest baseline drift before a setting's rows are suspect
    SENSITIVITY = 0.10,   -- smallest frame-time drop the control must show
    HITCH = 0.050,        -- a frame over this many seconds counts as a hitch
    PROBE_CEILING = 12,   -- highest integer tried when probing a CVar's tiers
    ASSUMED_LEVELS = 5,   -- levels assumed for a setting not learned yet, in the setup window estimate
    ASSUMED_QUICK = 3,    -- the same in a quick estimate: two measured levels and a baseline
    HISTORY = 10,         -- runs kept in the saved history
    POLL = 0.25,          -- seconds of frame time between movement checks
    GAME_MINUTES = 10,    -- game-time shift that flags "lighting may have changed"
    CONTROL_FACTOR = 0.75, -- render-scale control value is current x this
    CHECK_WINDOWS = 3,    -- baseline windows in `check`
    WATCHDOG = 5,         -- seconds without a single OnUpdate before a window gives up
    DRIFT = 0.10,         -- largest drift of a baseline bracket from the first baseline before a setting's rows are suspect
    CROWD_NOISE = 0.15,   -- the same two limits in a crowd, which never holds still: guesses until measured in a real one
    CROWD_DRIFT = 0.30,
}
local K = bench.K

-- A median this close to 33 ms with this little spread looks like a background-window frame cap.
local BG_MIN_SECONDS, BG_MAX_SECONDS, BG_SPREAD = 0.030, 0.036, 0.15

-- stats ----------------------------------------------------------------------------------------

local stats = {}
bench.stats = stats

-- The p-th percentile (0 < p <= 1) of an ascending-sorted array: the element at index ceil(p * n).
function stats.percentile(sorted, p)
    local n = #sorted
    local i = math.ceil(p * n - 1e-9)
    if i < 1 then i = 1 end
    if i > n then i = n end
    return sorted[i]
end

-- dts: frame times in seconds. Returns {n, meanMs, fps, low1Fps, maxMs, hitches}; the caller's array is untouched.
function stats.summarize(dts)
    local n = #dts
    if n == 0 then return { n = 0 } end
    local sum, max, hitches = 0, 0, 0
    local sorted = {}
    for i = 1, n do
        local dt = dts[i]
        sum = sum + dt
        if dt > max then max = dt end
        if dt > K.HITCH then hitches = hitches + 1 end
        sorted[i] = dt
    end
    table.sort(sorted)
    return {
        n = n,
        meanMs = sum / n * 1000,
        fps = n / sum,
        low1Fps = 1 / stats.percentile(sorted, 0.99),
        maxMs = max * 1000,
        hitches = hitches,
    }
end

-- Mean frame time in ms of each whole second of a window, in order: a frame counts in the second it starts in.
-- It shows whether a slow window was slow throughout or only at its start.
function stats.perSecond(dts)
    local sums, counts, last = {}, {}, 0
    local t = 0
    for i = 1, #dts do
        local bucket = math.floor(t) + 1
        sums[bucket] = (sums[bucket] or 0) + dts[i]
        counts[bucket] = (counts[bucket] or 0) + 1
        if bucket > last then last = bucket end
        t = t + dts[i]
    end
    local out = {}
    for bucket = 1, last do
        if sums[bucket] then out[#out + 1] = sums[bucket] / counts[bucket] * 1000 end
    end
    return out
end

-- guard ----------------------------------------------------------------------------------------

local guard = {}
bench.guard = guard

-- How far b has moved from a, as a fraction of a.
function guard.drift(a, b)
    return math.abs(b - a) / a
end

function guard.noisy(a, b)
    return guard.drift(a, b) > K.NOISE
end

-- True when the control (a cheaper setting) cut the frame time by at least K.SENSITIVITY.
function guard.responds(baseMs, controlMs)
    return (baseMs - controlMs) / baseMs >= K.SENSITIVITY
end

-- A median frame time near 33 ms with a narrow 1st-to-99th percentile spread: the window may be capped.
function guard.backgroundCap(dts)
    local n = #dts
    if n == 0 then return false end
    local sorted = {}
    for i = 1, n do sorted[i] = dts[i] end
    table.sort(sorted)
    local median = stats.percentile(sorted, 0.5)
    if median < BG_MIN_SECONDS or median > BG_MAX_SECONDS then return false end
    local spread = (stats.percentile(sorted, 0.99) - stats.percentile(sorted, 0.01)) / median
    return spread < BG_SPREAD
end

-- True when every tier is within K.NOISE x baseline of the baseline (and there is at least one tier).
function guard.noEffect(baseMs, tierMs)
    if #tierMs == 0 then return false end
    for _, ms in ipairs(tierMs) do
        if math.abs(ms - baseMs) >= K.NOISE * baseMs then return false end
    end
    return true
end

-- True when game time moved by at least K.GAME_MINUTES between two readings, across midnight too.
function guard.timeShifted(h0, m0, h1, m1)
    local diff = math.abs((h1 * 60 + m1) - (h0 * 60 + m0))
    diff = math.min(diff, 1440 - diff)
    return diff >= K.GAME_MINUTES
end

-- state and settings ---------------------------------------------------------------------------

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or _G.SetCVar

-- The bench's own part of the saved variables, created on first use; nil before they have loaded.
function bench.state()
    local db = ns.db()
    if not db then return nil end
    local st = db.bench
    if not st then
        st = {}
        db.bench = st
    end
    st.tiers = st.tiers or {}
    st.history = st.history or {}
    return st
end

-- Numeric when both values parse as numbers (so "0.750000" equals "0.75"), else plain equality.
function bench.sameValue(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and y ~= nil and x == y
end
local sameValue = bench.sameValue

-- The settings under test (spec section 9). `cvars` lists candidates in order; a row with `tiers` is a raw
-- CVar with an explicit list (never probed). `confirmed = false`: which CVar the menu slider drives is unknown.
bench.SETTINGS = {
    { key = "shadows", label = "Shadows", cvars = { "graphicsShadowQuality" }, confirmed = true },
    { key = "ssao", label = "SSAO", cvars = { "graphicsSSAO" }, confirmed = true },
    { key = "compute", label = "Compute effects", cvars = { "graphicsComputeEffects" }, confirmed = true },
    { key = "lighting", label = "Secondary lighting", cvars = { "giQuality", "graphicsLightMode" }, confirmed = false },
    { key = "liquid", label = "Liquid detail", cvars = { "graphicsLiquidDetail" }, confirmed = true },
    { key = "texture", label = "Texture resolution", cvars = { "graphicsTextureResolution" }, confirmed = true },
    { key = "clutter", label = "Ground clutter", cvars = { "graphicsGroundClutter" }, confirmed = true },
    { key = "clutterraw", label = "Ground clutter (raw)", cvars = { "groundEffectDensity" },
      tiers = { "48", "64", "128" }, confirmed = true },
    { key = "renderscale", label = "Render scale", cvars = { "RenderScale" },
      tiers = { "0.5", "0.6", "0.7", "0.8", "0.9", "1" }, confirmed = false },
}

local function firstExisting(row)
    for _, name in ipairs(row.cvars) do
        if GetCVar(name) ~= nil then return name end
    end
    return nil
end

local function tiersFor(row, cvar)
    if row.tiers then return row.tiers end
    local st = bench.state()
    return st and st.tiers[cvar]
end

-- Returns resolved, skipped. resolved entries: {key, label, cvar, tiers}; skipped entries: {key, reason}.
function bench.resolve()
    local resolved, skipped = {}, {}
    for _, row in ipairs(bench.SETTINGS) do
        local cvar = firstExisting(row)
        if not cvar then
            skipped[#skipped + 1] = { key = row.key, reason = "CVar not found (tried " .. table.concat(row.cvars, ", ") .. ")" }
        else
            local tiers = tiersFor(row, cvar)
            if not tiers or #tiers == 0 then
                skipped[#skipped + 1] = { key = row.key,
                    reason = "no tiers known for " .. cvar .. ": run /fset bench probe " .. cvar }
            else
                resolved[#resolved + 1] = { key = row.key, label = row.label, cvar = cvar, tiers = tiers }
            end
        end
    end
    return resolved, skipped
end

-- The tiers to measure for an entry whose CVar currently holds `current`: every tier but the current one. In "quick"
-- mode a setting with more than three tiers gets its lowest tier and one middle tier instead (the tier at the middle
-- position, or the nearest other one, the lower first, when that is the current one); the lowest is left out when it
-- is the current one.
function bench.tiersToMeasure(entry, current, mode)
    local tiers = entry.tiers
    local list = {}
    if mode == "quick" and #tiers > 3 then
        local n = #tiers
        local function isCurrent(i) return sameValue(tiers[i], current) end
        local middle = math.floor((n + 1) / 2)
        if isCurrent(middle) then
            local found
            for distance = 1, n do
                for _, i in ipairs({ middle - distance, middle + distance }) do
                    if not found and i >= 2 and i <= n and not isCurrent(i) then found = i end
                end
                if found then break end
            end
            middle = found
        end
        if not isCurrent(1) then list[#list + 1] = tiers[1] end
        if middle then list[#list + 1] = tiers[middle] end
        return list
    end
    for _, tier in ipairs(tiers) do
        if not sameValue(tier, current) then list[#list + 1] = tier end
    end
    return list
end

-- Windows in a full run: sweep windows + one baseline before and after each setting + two control windows.
-- `currents` maps a CVar name to its current value; `mode` is "quick" or "all" (the default).
function bench.countWindows(resolved, currents, mode)
    local sweep = 0
    for _, entry in ipairs(resolved) do
        sweep = sweep + #bench.tiersToMeasure(entry, currents[entry.cvar], mode)
    end
    return sweep + (1 + #resolved) + 2
end

local function isRaw(cvar)
    for _, row in ipairs(bench.SETTINGS) do
        if row.tiers then
            for _, name in ipairs(row.cvars) do
                if name:lower() == cvar:lower() then return true end
            end
        end
    end
    return false
end

-- Finds the integer tiers a CVar accepts: sets 0 up to K.PROBE_CEILING, keeps the values that read back equal,
-- stops at the first mismatch after at least one success, then restores the original value.
-- Returns tiers, or nil and a reason.
function bench.probe(cvar)
    if GetCVar(cvar) == nil then return nil, "unknown CVar" end
    if isRaw(cvar) then return nil, "raw CVar: tiers are an explicit list" end
    if InCombatLockdown() then return nil, "in combat" end
    if bench.active() or bench.measuring() then return nil, "a benchmark is running" end
    local originals = bench.restore.capture()
    local original = GetCVar(cvar)
    originals[cvar] = original
    local tiers = {}
    for value = 0, K.PROBE_CEILING do
        pcall(SetCVar, cvar, value)
        if sameValue(GetCVar(cvar), value) then
            tiers[#tiers + 1] = string.format("%d", value)
        elseif #tiers > 0 then
            break
        end
    end
    -- Putting back only this CVar would leave the raw CVars it rewrote at preset values: put back the whole snapshot.
    bench.restore.putBack(originals)
    for _, issue in ipairs(bench.restore.verify(originals)) do ns.say("could not restore " .. issue) end
    if #tiers == 0 then return nil, "no value read back" end
    if #tiers == 1 then return nil, "fewer than two values read back" end
    local st = bench.state()
    if st then st.tiers[cvar] = tiers end
    return tiers
end

-- Learns the levels of every setting that exists in this client and has none known (raw settings have explicit lists
-- and are skipped), by probing each in table order. Returns {learned = {cvar...}, failed = {{cvar, reason}...}}, or
-- nil and the reason when it may not run. A setting that cannot be learned does not stop the others.
function bench.learn()
    if InCombatLockdown() then
        return nil, "in combat"
    end
    if bench.active() or bench.measuring() then return nil, "a benchmark is running" end
    local learned, failed = {}, {}
    for _, row in ipairs(bench.SETTINGS) do
        local cvar = firstExisting(row)
        if cvar then
            local known = tiersFor(row, cvar)      -- a raw setting's explicit list counts as known
            if not known or #known == 0 then
                local tiers, reason = bench.probe(cvar)
                if tiers then learned[#learned + 1] = cvar else failed[#failed + 1] = { cvar = cvar, reason = reason } end
            end
        end
    end
    return { learned = learned, failed = failed }
end

-- The windows a setup run will take, for a player who may not have learned every setting yet: the windows of the
-- settings with known levels, plus K.ASSUMED_LEVELS for each setting that exists but is not learned.
function bench.estimateSetupWindows(mode)
    local resolved = bench.resolve()
    local currents = {}
    for _, entry in ipairs(resolved) do currents[entry.cvar] = GetCVar(entry.cvar) end
    local windows = bench.countWindows(resolved, currents, mode)
    local assumed = mode == "quick" and K.ASSUMED_QUICK or K.ASSUMED_LEVELS
    for _, row in ipairs(bench.SETTINGS) do
        local cvar = firstExisting(row)
        if cvar then
            local known = tiersFor(row, cvar)
            if not known or #known == 0 then windows = windows + assumed end
        end
    end
    return windows
end

-- restore: the guarded set -----------------------------------------------------------------------

-- Wall-clock time for saved records; tests replace this.
function bench.now()
    return time()
end

local restore = {}
bench.restore = restore

-- A CVar whose lower-cased name contains any of these is in the guarded set (spec section 8). The set is wide
-- on purpose: changing a graphics* CVar can rewrite raw CVars derived from it, and the end state is only
-- trustworthy if everything that can move is captured.
local GUARDED = {
    "graphics", "raidgraphics", "ground", "shadow", "ssao", "giquality", "light", "liquid", "water", "texture",
    "view", "lod", "horizon", "farclip", "sun", "particle", "weather", "spell", "render", "fps", "vsync", "bloom",
    "depth", "compute", "outline", "projected", "refraction", "ripple", "reflection", "pbr",
}

function restore.isGuarded(name)
    local lower = name:lower()
    for _, part in ipairs(GUARDED) do
        if lower:find(part, 1, true) then return true end
    end
    return false
end

local MASTERS = { graphicsquality = true, raidgraphicsquality = true }

-- 0 for a master preset, 1 for another menu-level graphics CVar, 2 for the rest.
local function rank(name)
    local lower = name:lower()
    if MASTERS[lower] then return 0 end
    if lower:sub(1, 8) == "graphics" or lower:sub(1, 12) == "raidgraphics" then return 1 end
    return 2
end

-- Master presets first (writing one may re-apply the sub-settings under it), then the other menu-level graphics
-- CVars, then the raw CVars they derive; each group alphabetical ignoring case.
function restore.order(names)
    local list = {}
    for i, name in ipairs(names) do list[i] = name end
    table.sort(list, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        local la, lb = a:lower(), b:lower()
        if la ~= lb then return la < lb end
        return a < b
    end)
    return list
end

-- {name = value} for every guarded CVar that exists, from the client's list of commands plus the built-in list
-- (ns.cvarNames). The second value is "client" or "built-in": where the names came from. Callers refuse to run on an
-- empty set.
function restore.capture()
    local got = {}
    local all, source = ns.cvarNames()
    for _, name in ipairs(all) do
        if restore.isGuarded(name) then
            local value = GetCVar(name)
            if value ~= nil then got[name] = value end
        end
    end
    return got, source
end

-- Written before the first change of a run so that a crash can be undone at the next login.
function restore.writePending(originals)
    local st = bench.state()
    if not st then return false end
    st.pending = { time = bench.now(), originals = originals }
    return true
end

-- Writes `originals` back in order, but only the CVars whose value differs at the moment of the write (a write can
-- rewrite others). Unchanged CVars are not touched, which also keeps a master preset from being re-applied for nothing.
function restore.putBack(originals)
    local names = {}
    for name in pairs(originals) do names[#names + 1] = name end
    for _, name in ipairs(restore.order(names)) do
        if not sameValue(GetCVar(name), originals[name]) then pcall(SetCVar, name, originals[name]) end
    end
end

-- The differences between the CVars now and `originals`, as "name: was A, now B".
function restore.verify(originals)
    local names = {}
    for name in pairs(originals) do names[#names + 1] = name end
    local issues = {}
    for _, name in ipairs(restore.order(names)) do
        local now = GetCVar(name)
        if not sameValue(now, originals[name]) then
            issues[#issues + 1] = name .. ": was " .. tostring(originals[name]) .. ", now " .. tostring(now)
        end
    end
    return issues
end

local deferred = nil

-- Puts every CVar in `originals` back, in order, then reads each one back. Returns "done" and the list of
-- differences ("name: was A, now B"), or "deferred" when in combat: the restore then waits for combat to end.
-- `pending` is cleared only once a restore has been read back.
function restore.apply(originals)
    if InCombatLockdown() then
        deferred = originals
        ns.say("in combat: your settings will be restored when combat ends")
        return "deferred", {}
    end
    restore.putBack(originals)
    local issues = restore.verify(originals)
    local st = bench.state()
    if st then
        st.lastRestoreIssues = issues
        st.pending = nil
    end
    for _, issue in ipairs(issues) do ns.say("could not restore " .. issue) end
    return "done", issues
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if deferred then
        local originals = deferred
        deferred = nil
        restore.apply(originals)
    end
end)

-- Called once at the first loading screen after login: undoes a run that was interrupted (a crash, a reload).
-- Returns true when a saved record was found.
function bench.recover()
    local st = bench.state()
    if not st or not st.pending then return false end
    local originals = st.pending.originals
    if type(originals) ~= "table" then
        st.pending = nil
        return false
    end
    if restore.apply(originals) == "done" then
        ns.say("restored settings from an interrupted benchmark")
    end
    return true
end

-- window: one measurement window -------------------------------------------------------------------

local win = nil            -- the window in progress, or nil
local timingFrame = nil    -- created on first use, without a parent so hiding the UI cannot stop its OnUpdate

local EVENT_REASONS = {
    PLAYER_REGEN_DISABLED = "combat",
    PLAYER_LEAVING_WORLD = "zoning",
    PLAYER_ENTERING_WORLD = "zoning",
}

local function moving()
    if GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0 then return true end
    return IsFalling ~= nil and IsFalling() == true
end

local function finish(result)
    local w = win
    if not w then return end
    win = nil
    w.onDone(result)
end

-- Starts or restarts a window's settle period: nothing measured yet, no slices judged yet.
local function beginSettle(w)
    w.phase, w.t, w.dts, w.settleN = "settle", 0, {}, 0
    w.slices, w.sliceT, w.sliceN = {}, 0, 0
end

-- Has the frame time stopped moving? The last two slices of frame time have nearly the same mean; with fewer than two
-- slices (a window shorter than a slice) there is nothing to judge and it counts as settled.
local function steady(slices)
    local n = #slices
    if n < 2 then return true end
    local a, b = slices[n - 1], slices[n]
    return math.abs(a - b) <= K.SETTLE_STEADY * math.min(a, b)
end

local function complete(w)
    if #w.dts < K.MIN_FRAMES then
        return finish({ ok = false, reason = "few" })
    end
    local flags = {}
    if guard.backgroundCap(w.dts) then flags[#flags + 1] = "possible background-window cap" end
    finish({
        ok = true,
        summary = stats.summarize(w.dts),
        seconds = stats.perSecond(w.dts),
        settleMs = w.settleMs,
        flags = flags,
        gameTime = { w.gameH, w.gameM },
        retried = w.attempt > 1,
    })
end

-- Window time is the sum of `elapsed`, never a wall clock: a settle period, then a measurement period.
local function onUpdate(_, elapsed)
    local w = win
    if not w then return end
    w.sawFrame = true
    w.poll = w.poll + elapsed
    if w.poll >= K.POLL then
        w.poll = 0
        if moving() then return finish({ ok = false, reason = "movement" }) end
        -- An optional outside rule (the guided window's "no settings, menu or map open"): a reason string stops the
        -- window like movement does; an error in it counts as no reason.
        if bench.watch then
            local ok, why = pcall(bench.watch)
            if ok and why then return finish({ ok = false, reason = why }) end
        end
    end
    if w.phase == "settle" then
        w.t = w.t + elapsed
        w.settleN = w.settleN + 1
        -- One mean per slice of frame time, to see whether a reload or a streaming hitch has finished.
        w.sliceT, w.sliceN = w.sliceT + elapsed, w.sliceN + 1
        if w.sliceT >= K.SETTLE_SLICE then
            w.slices[#w.slices + 1] = w.sliceT / w.sliceN
            w.sliceT, w.sliceN = 0, 0
        end
        if w.t >= K.SETTLE and (w.t >= K.SETTLE_MAX or steady(w.slices)) then
            w.settleMs = w.t / w.settleN * 1000
            w.phase = "measure"
            w.t = 0
            w.dts = {}
            w.gameH, w.gameM = GetGameTime()
        end
        return
    end
    if elapsed >= K.STALL then
        if w.attempt == 1 then
            w.attempt = 2
            beginSettle(w)
        else
            finish({ ok = false, reason = "stall" })
        end
        return
    end
    w.dts[#w.dts + 1] = elapsed
    w.t = w.t + elapsed
    if w.t >= K.MEASURE then complete(w) end
end

local function onEvent(_, event)
    local reason = EVENT_REASONS[event]
    if reason and win then finish({ ok = false, reason = reason }) end
end

local function ensureFrame()
    if timingFrame then return end
    timingFrame = CreateFrame("Frame", nil, nil)
    for event in pairs(EVENT_REASONS) do timingFrame:RegisterEvent(event) end
    timingFrame:SetScript("OnEvent", onEvent)
    timingFrame:SetScript("OnUpdate", onUpdate)
end

-- Starts one window. onDone receives {ok = true, summary, flags, gameTime = {h, m}, retried} or
-- {ok = false, reason} with reason one of "stall", "few", "combat", "zoning", "movement", "no frames" or whatever
-- abortWindow was given. Returns false, and does nothing, when a window is already running.
function bench.runWindow(onDone)
    if win then return false end
    ensureFrame()
    local w = { onDone = onDone, poll = 0, attempt = 1, sawFrame = false }
    beginSettle(w)
    win = w
    -- Watchdog: if no frame arrives at all, give up. It is tied to this window, so an old one never ends a new one.
    C_Timer.After(K.WATCHDOG, function()
        if win == w and not w.sawFrame then finish({ ok = false, reason = "no frames" }) end
    end)
    return true
end

function bench.abortWindow(reason)
    if not win then return false end
    finish({ ok = false, reason = reason })
    return true
end

function bench.measuring()
    return win ~= nil
end

-- preflight, control, check ------------------------------------------------------------------------

local activeRun = false    -- set by check and run, cleared on every exit path

function bench.active()
    return activeRun
end

-- `detail` says why a check matters (shown when it fails); `note` is shown with a pass.
local function addCheck(list, name, ok, detail, note)
    list[#list + 1] = { name = name, ok = ok and true or false, detail = detail, note = note }
end

-- The platform facts this module assumes, observed on the real client. `check` prints each as PASS or FAIL.
function bench.environment()
    local list = {}
    addCheck(list, "GetUnitSpeed", type(GetUnitSpeed) == "function" and type(GetUnitSpeed("player")) == "number",
        "the movement guard needs it")
    addCheck(list, "IsFalling", type(IsFalling) == "function", "the movement guard needs it")
    local hours, minutes
    if type(GetGameTime) == "function" then hours, minutes = GetGameTime() end
    addCheck(list, "GetGameTime", type(hours) == "number" and type(minutes) == "number", "the lighting flag needs it")
    local found, source = restore.capture()
    addCheck(list, "CVar list", next(found) ~= nil, "no known graphics CVar exists in this client; the snapshot of your settings needs one",
        source == "built-in" and "the client has no list of its CVars; using the built-in list" or nil)
    addCheck(list, "GetCVar of an unknown name is nil", GetCVar("ForeverSettingsNoSuchCVar") == nil)
    return list
end

-- Returns ok, problems, warnings, environment. A leftover pending record from an earlier run is restored first.
function bench.preflight()
    local problems, warnings = {}, {}
    local env = bench.environment()
    local st = bench.state()
    if st and st.pending and not activeRun then
        bench.recover()
        warnings[#warnings + 1] = "Settings from an interrupted test were put back first."
    end
    if activeRun then problems[#problems + 1] = "a run is already active" end
    if InCombatLockdown() then problems[#problems + 1] = "you are in combat" end
    if moving() then problems[#problems + 1] = "you are moving or falling: stand still" end
    for _, c in ipairs(env) do
        if not c.ok then problems[#problems + 1] = "environment check failed: " .. c.name end
    end
    if GetCVar("vsync") == "1" then
        warnings[#warnings + 1] = "Vsync is on, so your frame rate is capped at your screen's refresh rate and the test cannot see "
            .. "what settings cost. Turn vsync off in the game's graphics options and run the test again."
    end
    local useMax, maxFps = GetCVar("useMaxFPS"), tonumber(GetCVar("maxFPS") or "")
    if useMax == "1" or (maxFps and maxFps > 0 and useMax ~= "0") then
        warnings[#warnings + 1] = "A frame-rate limit is set in the game, so the test cannot see what settings cost above that limit. "
            .. "Raise or remove the limit and run the test again."
    end
    return #problems == 0, problems, warnings, env
end

-- The lowest numeric tier of an entry that is cheaper (lower) than its current value, or nil.
local function cheaperTier(entry, currentValue)
    local current = tonumber(currentValue)
    if not current then return nil end
    local best
    for _, tier in ipairs(entry.tiers) do
        local n = tonumber(tier)
        if n and n < current and (not best or n < tonumber(best)) then best = tier end
    end
    return best
end

-- The setting whose change must visibly cut the frame time: render scale at current x K.CONTROL_FACTOR, else the
-- cheapest tier of shadows, else of lighting. `current` maps a CVar name to its value. Returns {cvar, value, label}.
function bench.pickControl(resolved, current)
    local byKey = {}
    for _, entry in ipairs(resolved) do byKey[entry.key] = entry end
    local scale = byKey.renderscale
    if scale then
        local now = tonumber(current[scale.cvar])
        if now then
            return { cvar = scale.cvar, value = string.format("%.4g", now * K.CONTROL_FACTOR), label = scale.label }
        end
    end
    for _, key in ipairs({ "shadows", "lighting" }) do
        local entry = byKey[key]
        if entry then
            local value = cheaperTier(entry, current[entry.cvar])
            if value then return { cvar = entry.cvar, value = value, label = entry.label } end
        end
    end
    return nil
end

local function currentsOf(resolved)
    local current = {}
    for _, entry in ipairs(resolved) do current[entry.cvar] = GetCVar(entry.cvar) end
    return current
end

local function sayEnvironment(env, silent)
    if silent then return end
    local all = {}
    for _, c in ipairs(env) do all[#all + 1] = c end
    if ns.ui and ns.ui.environment then
        for _, c in ipairs(ns.ui.environment()) do all[#all + 1] = c end
    end
    for _, c in ipairs(all) do
        -- Not `c.ok and c.note or c.detail`: a pass with no note would then show the failure text.
        local why = c.note
        if not c.ok then why = c.detail end
        ns.say("environment: " .. (c.ok and "PASS " or "FAIL ") .. c.name .. (why and (" (" .. why .. ")") or ""))
    end
end

-- Snapshots the guarded set, writes the pending record, and marks a run active. Returns the originals, or nil
-- after saying why (nothing has been changed then).
local function snapshotNames(resolved, control)
    local names = {}
    for _, entry in ipairs(resolved) do names[#names + 1] = entry.cvar end
    if control then names[#names + 1] = control.cvar end
    return names
end

local function beginRun(extraNames)
    local originals = restore.capture()
    if next(originals) == nil then
        ns.say("cannot snapshot your settings: no known graphics CVar exists in this client")
        return nil
    end
    -- The settings under test and the control belong in the snapshot even if the console list left them out.
    for _, name in ipairs(extraNames or {}) do
        if originals[name] == nil then
            local value = GetCVar(name)
            if value ~= nil then originals[name] = value end
        end
    end
    restore.writePending(originals)
    ns.suspended = true
    activeRun = true
    return originals
end

-- Ends a check or run: puts everything back, releases the suspension, then hands over the result.
local function finishRun(originals, result, onDone)
    local ok, err = pcall(restore.apply, originals)
    if not ok then ns.say("restore failed: " .. tostring(err) .. " (it will be retried at the next login)") end
    ns.suspended = false
    activeRun = false
    if onDone then onDone(result) end
end

-- Preflight, then three baseline windows and one control window; prints the baseline, its spread, and whether
-- the control cut the frame time. onDone receives {ok, reason, baselineMs, spread, drop}.
function bench.check(onDone)
    onDone = onDone or function() end
    local ok, problems, warnings, env = bench.preflight()
    sayEnvironment(env)
    for _, w in ipairs(warnings) do ns.say("warning: " .. w) end
    if not ok then
        for _, p in ipairs(problems) do ns.say("cannot check: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    ns.say("close browsers, streaming and VR software before measuring")
    local resolved = bench.resolve()
    local control = bench.pickControl(resolved, currentsOf(resolved))
    if not control then
        ns.say("no control setting is available: run /fset bench probe <cvar> for the shadows or lighting CVar first")
        return onDone({ ok = false, reason = "no control" })
    end
    local originals = beginRun(snapshotNames(resolved, control))
    if not originals then return onDone({ ok = false, reason = "no snapshot" }) end

    local means, wins = {}, {}
    local finished = false
    local function stop(r)
        if finished then return end
        finished = true
        ns.say("check stopped: " .. tostring(r.reason))
        finishRun(originals, { ok = false, reason = r.reason }, onDone)
    end
    -- A failure inside a step ends the check like any other stop, with everything put back.
    local function safe(fn)
        return function(r)
            local ok, err = pcall(fn, r)
            if not ok then stop({ reason = "error: " .. tostring(err) }) end
        end
    end
    -- One line of evidence per window, so a failed check shows whether the frame time was slow throughout, slow
    -- only at the start (a change that needs longer than the settle period), or hitching.
    local function windowLine(label, r)
        local parts = {}
        for i, ms in ipairs(r.seconds or {}) do parts[i] = string.format("%.1f", ms) end
        local s = r.summary
        return string.format("%s: %.2f ms over %d frames, slowest %.0f ms, %d over %.0f ms; settle %.1f ms; by second: %s",
            label, s.meanMs, s.n, s.maxMs, s.hitches, K.HITCH * 1000, r.settleMs or 0, table.concat(parts, " "))
    end
    local function conclude(controlResult)
        if finished then return end
        finished = true
        local controlMs = controlResult.summary.meanMs
        for i, r in ipairs(wins) do ns.say(windowLine("baseline window " .. i, r)) end
        ns.say(windowLine("control window", controlResult))
        local sum, lo, hi = 0, math.huge, 0
        for _, ms in ipairs(means) do
            sum = sum + ms
            if ms < lo then lo = ms end
            if ms > hi then hi = ms end
        end
        local baseMs = sum / #means
        local spread = (hi - lo) / baseMs
        local drop = (baseMs - controlMs) / baseMs
        local responded = guard.responds(baseMs, controlMs)
        ns.say(string.format("baseline %.2f ms (%.0f fps), spread %.1f%% over %d windows", baseMs, 1000 / baseMs, spread * 100, #means))
        if spread > K.NOISE then
            ns.say(string.format("the spread is above the %.0f%% noise limit, so a sweep here would mark settings inconclusive: "
                .. "try a quieter spot or raise MEASURE in Bench.lua", K.NOISE * 100))
        end
        if responded then
            ns.say(string.format("control %s = %s: frame time dropped %.1f%%: ok", control.label, control.value, drop * 100))
            ns.say("check passed: this spot is valid for benchmarking")
        else
            ns.say(string.format("control %s = %s: frame time dropped only %.1f%%: did not respond, so you are capped or CPU-bound here",
                control.label, control.value, drop * 100))
            ns.say("check failed")
        end
        finishRun(originals, {
            ok = responded, reason = (not responded) and "control did not respond" or nil,
            baselineMs = baseMs, spread = spread, drop = drop,
        }, onDone)
    end
    local function controlWindow()
        pcall(SetCVar, control.cvar, control.value)
        local now = GetCVar(control.cvar)
        if not sameValue(now, control.value) then
            ns.say("the game did not accept the control " .. control.cvar .. " = " .. control.value .. " (it kept " .. tostring(now) .. ")")
            return stop({ reason = "control rejected" })
        end
        bench.runWindow(safe(function(r)
            if not r.ok then return stop(r) end
            conclude(r)
        end))
    end
    local function baseline(i)
        bench.runWindow(safe(function(r)
            if not r.ok then return stop(r) end
            means[#means + 1] = r.summary.meanMs
            wins[#wins + 1] = r
            if i < K.CHECK_WINDOWS then return baseline(i + 1) end
            controlWindow()
        end))
    end
    baseline(1)
end

-- run: the full benchmark, its report, history and `mark` ------------------------------------------

local progressState = nil   -- {phase, label, done, total, repeats} during a run, else nil

-- `repeats` is how many readings the run has taken again because the frame rate was not steady: each adds steps to `total`.
function bench.progress()
    if not progressState then return nil end
    return { phase = progressState.phase, label = progressState.label, done = progressState.done, total = progressState.total,
        cvar = progressState.cvar, value = progressState.value, repeats = progressState.repeats or 0 }
end

function bench.history()
    local st = bench.state()
    return st and st.history or {}
end

local function pushHistory(entry)
    local st = bench.state()
    if not st then return end
    entry.profile = entry.profile or (ns.db() and ns.db().active)
    local h = st.history
    h[#h + 1] = entry
    -- The newest finished quiet-spot result and the newest finished crowd result are what the menu's green checks reopen:
    -- trimming to the cap removes the oldest entry that is neither (the oldest of all only when every entry is one).
    while #h > K.HISTORY do
        local keepQuiet, keepCrowd
        for i = #h, 1, -1 do
            local e = h[i]
            if e.valid == true and e.kind == "crowd" then
                keepCrowd = keepCrowd or e
            elseif e.valid == true and not e.label and type(e.rows) == "table" and #e.rows > 0 then
                keepQuiet = keepQuiet or e
            end
        end
        local drop = 1
        for i = 1, #h do
            if h[i] ~= keepQuiet and h[i] ~= keepCrowd then
                drop = i
                break
            end
        end
        table.remove(h, drop)
    end
end

local function copyList(list)
    local copy = {}
    for i, v in ipairs(list or {}) do copy[i] = v end
    return copy
end

-- Where the run happens. Each call is guarded: a missing API leaves a placeholder, it never stops a run.
local function describeSpot()
    local spot = { zone = "unknown", instanceType = "unknown", groupSize = 0, resolution = "unknown",
        renderScale = GetCVar("RenderScale") }
    if GetRealZoneText then
        local ok, zone = pcall(GetRealZoneText)
        if ok and zone and zone ~= "" then spot.zone = zone end
    end
    if IsInInstance then
        local ok, _, kind = pcall(IsInInstance)
        if ok and kind then spot.instanceType = kind end
    end
    if GetNumGroupMembers then
        local ok, n = pcall(GetNumGroupMembers)
        if ok and type(n) == "number" then spot.groupSize = n end
    end
    if GetPhysicalScreenSize then
        local ok, w, h = pcall(GetPhysicalScreenSize)
        if ok and w and h then spot.resolution = string.format("%dx%d", w, h) end
    end
    return spot
end

local function measuredRow(setting, value, r, baseMs)
    local s = r.summary
    return {
        setting = setting.label, cvar = setting.cvar, value = value, baseMs = baseMs,
        meanMs = s.meanMs, fps = s.fps, low1Fps = s.low1Fps, maxMs = s.maxMs, hitches = s.hitches,
        flags = copyList(r.flags), gameTime = r.gameTime,
    }
end

local function statusRow(setting, value, status, reason, baseMs)
    return { setting = setting.label, cvar = setting.cvar, value = value, baseMs = baseMs,
        status = status, reason = reason, flags = {} }
end

local function mergeFlags(a, b)
    local merged, seen = {}, {}
    for _, list in ipairs({ a or {}, b or {} }) do
        for _, f in ipairs(list) do
            if not seen[f] then
                seen[f] = true
                merged[#merged + 1] = f
            end
        end
    end
    return merged
end

-- The row for the tier the setting started at: the mean of the two baselines around its sweep, delta 0.
local function reusedRow(setting, value, a, b, baseMs)
    local sa, sb = a.summary, b.summary
    local mean = (sa.meanMs + sb.meanMs) / 2
    return {
        setting = setting.label, cvar = setting.cvar, value = value, baseMs = baseMs,
        meanMs = mean, fps = 1000 / mean, low1Fps = (sa.low1Fps + sb.low1Fps) / 2,
        maxMs = math.max(sa.maxMs, sb.maxMs), hitches = sa.hitches + sb.hitches,
        flags = mergeFlags(a.flags, b.flags), deltaMs = 0, current = true,
    }
end

local function flagText(flags)
    if not flags or #flags == 0 then return "" end
    return "  [" .. table.concat(flags, "; ") .. "]"
end

-- The lines to print for a history entry. A row without a valid measurement prints its reason and no number.
function bench.report(entry)
    local lines = {}
    if entry.label then
        if entry.valid then
            local row = entry.rows[1]
            lines[1] = string.format("%s: %.2f ms  %.0f fps  1%% low %.0f  %d hitches%s",
                entry.label, row.meanMs, row.fps, row.low1Fps, row.hitches, flagText(row.flags))
        else
            lines[1] = entry.label .. ": not measured (" .. tostring(entry.reason) .. ")"
        end
        return lines
    end
    if entry.kind == "crowd" then
        if entry.valid then
            lines[1] = string.format("Crowd test at %s (%s): baseline %.2f ms, %.0f fps",
                entry.zone, entry.instanceType, entry.baselineMs, 1000 / entry.baselineMs)
        else
            lines[1] = string.format("Crowd test stopped (%s) at %s (%s)", tostring(entry.reason), entry.zone, entry.instanceType)
        end
        for _, s in ipairs(entry.settings or {}) do
            lines[#lines + 1] = string.format("%s (%s)   lowest level %s", s.setting, s.cvar, tostring(s.lowValue))
            if s.status then
                lines[#lines + 1] = "  " .. tostring(s.reason)
            else
                lines[#lines + 1] = string.format("  saved %.2f ms  (baselines differed by %.0f%%)", -s.lowDelta, s.drift * 100)
            end
        end
        return lines
    end
    if entry.valid then
        lines[1] = string.format("Benchmark at %s (%s): baseline %.2f ms, %.0f fps",
            entry.zone, entry.instanceType, entry.baselineMs, 1000 / entry.baselineMs)
    else
        lines[1] = string.format("Benchmark stopped (%s) at %s (%s)", tostring(entry.reason), entry.zone, entry.instanceType)
    end
    local last
    for _, row in ipairs(entry.rows) do
        if row.setting ~= last then
            last = row.setting
            local heading = string.format("%s (%s)   baseline %.2f ms", row.setting, row.cvar, row.baseMs)
            for _, f in ipairs(row.flags) do
                if f == "no measurable effect or not applied" then heading = heading .. "  " .. f end
            end
            lines[#lines + 1] = heading
        end
        if row.status then
            lines[#lines + 1] = string.format("  %s  %s%s", row.value, row.reason, flagText(row.flags))
        else
            lines[#lines + 1] = string.format("  %s  %.2f ms  %+.2f ms  %.0f fps  1%% low %.0f%s",
                row.value, row.meanMs, row.deltaMs, row.fps, row.low1Fps, flagText(row.flags))
        end
    end
    return lines
end

-- The full run (spec section 6). onDone receives the history entry, or {ok = false, reason} when it refuses.
-- `opts.levels` is "quick" (each setting's lowest level and one middle level only) or "all"; `opts.kind` is recorded on
-- the entry ("run" by default, "setup" from the guided window).
function bench.run(onDone, opts)
    onDone = onDone or function() end
    opts = opts or {}
    -- A silent run (the guided window's) says nothing in chat but the warnings and the restore messages: the window shows
    -- everything else in plain words.
    local say = opts.silent and function() end or ns.say
    local mode = opts.levels == "quick" and "quick" or "all"
    local ok, problems, warnings, env = bench.preflight()
    sayEnvironment(env, opts.silent)
    for _, w in ipairs(warnings) do ns.say("warning: " .. w) end
    if not ok then
        for _, p in ipairs(problems) do say("cannot run: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    local resolved, skipped = bench.resolve()
    for _, sk in ipairs(skipped) do say("skipping " .. sk.key .. ": " .. sk.reason) end
    if #resolved == 0 then
        say("nothing to measure: no setting has both a CVar in this client and known tiers")
        return onDone({ ok = false, reason = "nothing to measure" })
    end
    local currents = currentsOf(resolved)
    local control = bench.pickControl(resolved, currents)
    if not control then
        say("no control setting is available: run /fset bench probe <cvar> for the shadows or lighting CVar first")
        return onDone({ ok = false, reason = "no control" })
    end
    say("close browsers, streaming and VR software before measuring")
    local spot = describeSpot()
    local originals = beginRun(snapshotNames(resolved, control))
    if not originals then return onDone({ ok = false, reason = "no snapshot" }) end

    local rows, done, reruns, b0 = {}, 0, 0, nil
    local concluded = false
    progressState = { phase = "control", label = control.label, done = 0, total = bench.countWindows(resolved, currents, mode) }

    local function conclude(valid, reason)
        if concluded then return end
        concluded = true
        local entry = {
            ok = valid, time = bench.now(), zone = spot.zone, instanceType = spot.instanceType, groupSize = spot.groupSize,
            resolution = spot.resolution, renderScale = spot.renderScale, baselineMs = b0 and b0.summary.meanMs or nil,
            valid = valid, reason = reason, rows = rows, windows = done, reruns = reruns,
            kind = opts.kind or "run", mode = mode,
            -- Each setting's value when the run began: one that is not a measured level has no `current` row.
            starts = currents,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)
            if not opts.silent then
                for _, line in ipairs(bench.report(e)) do ns.say(line) end
            end
            if ns.ui and ns.ui.runFinished then pcall(ns.ui.runFinished, e) end
            onDone(e)
        end)
    end
    local function abort(reason)
        say("run stopped: " .. tostring(reason))
        conclude(false, reason)
    end
    -- Set just before a window starts: the setting (and level) the window is about, for the guided window's wording.
    local nextInfo
    local function window(phase, label, cb)
        progressState.phase, progressState.label = phase, label
        progressState.cvar, progressState.value = nextInfo and nextInfo.cvar, nextInfo and nextInfo.value
        nextInfo = nil
        local started = bench.runWindow(function(r)
            if r.ok then
                done = done + 1
                if progressState then progressState.done = done end
            end
            -- A failure inside a step ends the run like any other stop, with everything put back.
            local ok, err = pcall(cb, r)
            if not ok then abort("error: " .. tostring(err)) end
        end)
        if not started then abort("window busy") end
    end
    local function baselineWindow(label, cb)
        window("baseline", label, function(r)
            if not r.ok then return abort("baseline " .. tostring(r.reason)) end
            cb(r)
        end)
    end

    -- The control: a window at the starting settings, then one with the control cheaper. If frame time does not
    -- follow, the run is capped or CPU-bound and stops.
    local function controlStage(after)
        nextInfo = { cvar = control.cvar }
        window("control", control.label, function(c0)
            if not c0.ok then return abort(c0.reason) end
            local before = GetCVar(control.cvar)
            pcall(SetCVar, control.cvar, control.value)
            if not sameValue(GetCVar(control.cvar), control.value) then
                pcall(SetCVar, control.cvar, before)
                say("the game did not accept the control " .. control.cvar .. " = " .. control.value)
                return abort("control rejected")
            end
            nextInfo = { cvar = control.cvar }
            window("control", control.label, function(c1)
                pcall(SetCVar, control.cvar, before)
                if not c1.ok then return abort(c1.reason) end
                if not guard.responds(c0.summary.meanMs, c1.summary.meanMs) then
                    say("the control did not cut the frame time: you are capped or CPU-bound here")
                    return abort("control did not respond")
                end
                after()
            end)
        end)
    end

    -- Rows for one setting once its bracketing baselines are known. `drift` is set when they disagree too much.
    local function addRows(setting, current, measured, reference, after, drift, sinceStart)
        local baseMean = (reference.summary.meanMs + after.summary.meanMs) / 2
        if drift then
            local reason = string.format(
                sinceStart and "inconclusive (baseline moved %.1f%% since the start)" or "inconclusive (baseline drifted %.1f%%)",
                drift * 100)
            for _, tier in ipairs(setting.tiers) do
                local m = measured[tier]
                if m and m.status == "rejected" then
                    rows[#rows + 1] = statusRow(setting, tier, "rejected", m.reason, baseMean)
                elseif m or sameValue(tier, current) then
                    rows[#rows + 1] = statusRow(setting, tier, "inconclusive", reason, baseMean)
                end
            end
            return
        end
        local first = #rows + 1
        local tierMs = {}
        for _, tier in ipairs(setting.tiers) do
            if sameValue(tier, current) then
                rows[#rows + 1] = reusedRow(setting, tier, reference, after, baseMean)
            elseif measured[tier] then
                local m = measured[tier]
                if m.result then
                    local row = measuredRow(setting, tier, m.result, baseMean)
                    row.deltaMs = row.meanMs - baseMean
                    local g0, g1 = b0.gameTime, m.result.gameTime
                    if g0 and g1 and guard.timeShifted(g0[1], g0[2], g1[1], g1[2]) then
                        row.flags[#row.flags + 1] = "lighting may have changed"
                    end
                    tierMs[#tierMs + 1] = row.meanMs
                    rows[#rows + 1] = row
                else
                    rows[#rows + 1] = statusRow(setting, tier, m.status, m.reason, baseMean)
                end
            end
        end
        if guard.noEffect(baseMean, tierMs) then
            for i = first, #rows do rows[i].flags[#rows[i].flags + 1] = "no measurable effect or not applied" end
        end
    end

    local sweep
    local function sweepSetting(i, prev)
        local setting = resolved[i]
        local current = currents[setting.cvar]
        local rerun = false
        local reference = prev
        local attempt
        attempt = function()
            local tiers = bench.tiersToMeasure(setting, current, mode)
            local measured, k = {}, 0
            local nextTier
            local function bracket()
                pcall(restore.putBack, originals)
                nextInfo = { cvar = setting.cvar }
                baselineWindow("after " .. setting.label, function(b)
                    if guard.noisy(reference.summary.meanMs, b.summary.meanMs) then
                        if not rerun then
                            rerun = true
                            reruns = reruns + 1
                            -- The rerun measures every tier again and takes one more closing baseline.
                            if progressState then
                                progressState.total = progressState.total + #tiers + 1
                                progressState.repeats = (progressState.repeats or 0) + 1
                            end
                            reference = b
                            return attempt()
                        end
                        addRows(setting, current, measured, reference, b, guard.drift(reference.summary.meanMs, b.summary.meanMs))
                    else
                        -- Also compare with the first baseline: a change that lasts past one setting moves every
                        -- bracket after it together, so neighbours alone would accept it.
                        local fromStart = math.max(guard.drift(b0.summary.meanMs, reference.summary.meanMs),
                            guard.drift(b0.summary.meanMs, b.summary.meanMs))
                        if fromStart > K.DRIFT then
                            addRows(setting, current, measured, reference, b, fromStart, true)
                        else
                            addRows(setting, current, measured, reference, b, nil)
                        end
                    end
                    sweep(i + 1, b)
                end)
            end
            nextTier = function()
                k = k + 1
                local value = tiers[k]
                if value == nil then return bracket() end
                pcall(SetCVar, setting.cvar, value)
                local now = GetCVar(setting.cvar)
                if not sameValue(now, value) then
                    measured[value] = { status = "rejected", reason = "rejected, clamped to " .. tostring(now) }
                    return nextTier()
                end
                nextInfo = { cvar = setting.cvar, value = value }
                window("sweep", setting.label .. " " .. value, function(r)
                    if r.ok then
                        measured[value] = { result = r }
                    elseif r.reason == "stall" or r.reason == "few" then
                        measured[value] = { status = "inconclusive", reason = "inconclusive (" .. r.reason .. ")" }
                    else
                        return abort(r.reason)
                    end
                    nextTier()
                end)
            end
            nextTier()
        end
        attempt()
    end
    sweep = function(i, prev)
        if i > #resolved then return conclude(true) end
        sweepSetting(i, prev)
    end

    controlStage(function()
        baselineWindow("start", function(r)
            b0 = r
            sweep(1, r)
        end)
    end)
end

-- The crowd test (spec 2026-10-29-crowd-test-design.md section 4.2) ---------------------------------------------------

local UNUSABLE_FLAGS = { ["possible background-window cap"] = true, ["lighting may have changed"] = true }

-- A quiet-spot row the crowd test can rely on: measured, with a delta, and no flag that throws it out.
local function usableRow(row)
    if row.status ~= nil or type(row.meanMs) ~= "number" or type(row.deltaMs) ~= "number" then return false end
    for _, flag in ipairs(row.flags or {}) do
        if UNUSABLE_FLAGS[flag] then return false end
    end
    return true
end

-- The settings the crowd test measures, in table order: each one the quiet-spot entry measured below the level the player
-- holds now, with that lowest measured level.
local function crowdPlan(quiet)
    local plan = {}
    for _, entry in ipairs(bench.resolve()) do
        local live = tonumber(GetCVar(entry.cvar))
        if live then
            local lowest
            for _, row in ipairs(quiet.rows or {}) do
                if row.cvar == entry.cvar and usableRow(row) then
                    local v = tonumber(row.value)
                    if v and v < live and (not lowest or v < tonumber(lowest)) then lowest = row.value end
                end
            end
            if lowest then plan[#plan + 1] = { cvar = entry.cvar, label = entry.label, lowValue = lowest } end
        end
    end
    return plan
end

-- The windows the crowd test takes for this quiet-spot entry: a first baseline, then a window and a baseline for each
-- setting. 0 when there is nothing to measure.
function bench.estimateCrowdWindows(quiet)
    if type(quiet) ~= "table" then return 0 end
    local n = #crowdPlan(quiet)
    return n == 0 and 0 or 2 * n + 1
end

-- Measures how much each setting saves in a busy place: it is put at its lowest level for one window, put back, and
-- a baseline is taken; each baseline is the "before" of the next pair. onDone receives the history entry (kind "crowd",
-- `settings` in place of `rows`), or {ok = false, reason} when it refuses.
function bench.crowd(quiet, onDone, opts)
    onDone = onDone or function() end
    opts = opts or {}
    local say = opts.silent and function() end or ns.say     -- see bench.run
    local ok, problems, warnings, env = bench.preflight()
    sayEnvironment(env, opts.silent)
    for _, w in ipairs(warnings) do ns.say("warning: " .. w) end
    if not ok then
        for _, p in ipairs(problems) do say("cannot run: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    if type(quiet) ~= "table" or quiet.valid ~= true then
        say("the crowd test needs a finished quiet-spot test first")
        return onDone({ ok = false, reason = "no quiet result" })
    end
    local plan = crowdPlan(quiet)
    if #plan == 0 then
        say("nothing to measure: the quiet-spot test holds no setting that can be lowered further")
        return onDone({ ok = false, reason = "nothing to measure" })
    end
    local currents = currentsOf(bench.resolve())
    local names = {}
    for _, item in ipairs(plan) do names[#names + 1] = item.cvar end
    local spot = describeSpot()
    local originals = beginRun(names)
    if not originals then return onDone({ ok = false, reason = "no snapshot" }) end

    local settings, done, reruns, b0 = {}, 0, 0, nil
    local concluded = false
    progressState = { phase = "baseline", label = "start", done = 0, total = 2 * #plan + 1 }

    local function conclude(valid, reason)
        if concluded then return end
        concluded = true
        local entry = {
            ok = valid, time = bench.now(), zone = spot.zone, instanceType = spot.instanceType, groupSize = spot.groupSize,
            resolution = spot.resolution, renderScale = spot.renderScale, baselineMs = b0 and b0.summary.meanMs or nil,
            valid = valid, reason = reason, rows = {}, windows = done, reruns = reruns,
            kind = "crowd", settings = settings, starts = currents, quietTime = quiet.time,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)
            if not opts.silent then
                for _, line in ipairs(bench.report(e)) do ns.say(line) end
            end
            if ns.ui and ns.ui.runFinished then pcall(ns.ui.runFinished, e) end
            onDone(e)
        end)
    end
    local function abort(reason)
        say("run stopped: " .. tostring(reason))
        conclude(false, reason)
    end
    local nextInfo
    local function window(phase, label, cb)
        progressState.phase, progressState.label = phase, label
        progressState.cvar, progressState.value = nextInfo and nextInfo.cvar, nextInfo and nextInfo.value
        nextInfo = nil
        local started = bench.runWindow(function(r)
            if r.ok then
                done = done + 1
                if progressState then progressState.done = done end
            end
            -- A failure inside a step ends the run like any other stop, with everything put back.
            local okStep, err = pcall(cb, r)
            if not okStep then abort("error: " .. tostring(err)) end
        end)
        if not started then abort("window busy") end
    end
    local function baselineWindow(label, cb)
        window("baseline", label, function(r)
            if not r.ok then return abort("baseline " .. tostring(r.reason)) end
            cb(r)
        end)
    end
    local function record(item, fields)
        local r = { cvar = item.cvar, setting = item.label, lowValue = item.lowValue, flags = {} }
        for k, v in pairs(fields) do r[k] = v end
        settings[#settings + 1] = r
    end

    local pair
    pair = function(i, before)
        local item = plan[i]
        if not item then return conclude(true) end
        local reference, rerun = before, false
        local attempt
        attempt = function()
            pcall(SetCVar, item.cvar, item.lowValue)
            local now = GetCVar(item.cvar)
            if not sameValue(now, item.lowValue) then
                pcall(restore.putBack, originals)
                record(item, { status = "rejected", reason = "rejected, clamped to " .. tostring(now) })
                return pair(i + 1, reference)
            end
            nextInfo = { cvar = item.cvar, value = item.lowValue }
            window("sweep", item.label .. " " .. item.lowValue, function(low)
                local lowFailed
                if not low.ok then
                    -- A window that never steadied makes this setting inconclusive; anything else stops the run.
                    if low.reason == "stall" or low.reason == "few" then
                        lowFailed = "inconclusive (" .. low.reason .. ")"
                    else
                        return abort(low.reason)
                    end
                end
                pcall(restore.putBack, originals)
                nextInfo = { cvar = item.cvar }
                baselineWindow("after " .. item.label, function(b)
                    if lowFailed then
                        record(item, { status = "inconclusive", reason = lowFailed })
                        return pair(i + 1, b)
                    end
                    local drift = guard.drift(reference.summary.meanMs, b.summary.meanMs)
                    local fromStart = math.max(guard.drift(b0.summary.meanMs, reference.summary.meanMs),
                        guard.drift(b0.summary.meanMs, b.summary.meanMs))
                    if drift > K.CROWD_NOISE or fromStart > K.CROWD_DRIFT then
                        if not rerun then
                            rerun = true
                            reruns = reruns + 1
                            -- The repeat takes one more window and one more baseline.
                            if progressState then
                                progressState.total = progressState.total + 2
                                progressState.repeats = (progressState.repeats or 0) + 1
                            end
                            reference = b
                            return attempt()
                        end
                        local reason
                        if drift > K.CROWD_NOISE then
                            reason = string.format("inconclusive (baseline drifted %.1f%%)", drift * 100)
                        else
                            reason = string.format("inconclusive (baseline moved %.1f%% since the start)", fromStart * 100)
                        end
                        record(item, { status = "inconclusive", reason = reason, drift = drift })
                        return pair(i + 1, b)
                    end
                    local baseMs = (reference.summary.meanMs + b.summary.meanMs) / 2
                    record(item, { lowDelta = low.summary.meanMs - baseMs, baseMs = baseMs, drift = drift,
                        flags = copyList(low.flags) })
                    pair(i + 1, b)
                end)
            end)
        end
        attempt()
    end

    baselineWindow("start", function(r)
        b0 = r
        pair(1, r)
    end)
end

-- The check of a recommendation (spec 2026-10-29-crowd-test-design.md section 4.3): writes `values` ({cvar = value}),
-- measures one window with them, puts everything back, then measures one closing baseline. onDone receives
-- {ok = true, appliedMs, baselineMs} or {ok = false, reason}; every exit puts everything back first.
function bench.verify(values, onDone, opts)
    onDone = onDone or function() end
    local say = opts and opts.silent and function() end or ns.say     -- see bench.run
    local ok, problems, warnings = bench.preflight()
    for _, w in ipairs(warnings) do ns.say("warning: " .. w) end
    if not ok then
        for _, p in ipairs(problems) do say("cannot check: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    local names = {}
    for cvar in pairs(values or {}) do names[#names + 1] = cvar end
    if #names == 0 then return onDone({ ok = false, reason = "nothing to check" }) end
    local originals = beginRun(names)
    if not originals then return onDone({ ok = false, reason = "no snapshot" }) end

    local finished = false
    local function finishWith(result)
        if finished then return end
        finished = true
        progressState = nil
        finishRun(originals, result, onDone)
    end
    local function stop(reason) finishWith({ ok = false, reason = reason }) end
    -- A failure inside a step ends the check like any other stop, with everything put back.
    local function guarded(fn)
        return function(r)
            local okStep, err = pcall(fn, r)
            if not okStep then stop("error: " .. tostring(err)) end
        end
    end

    for _, cvar in ipairs(restore.order(names)) do
        pcall(SetCVar, cvar, values[cvar])
        if not sameValue(GetCVar(cvar), values[cvar]) then return stop("rejected") end
    end
    progressState = { phase = "check", label = "your recommendation", done = 0, total = 2 }
    local started = bench.runWindow(guarded(function(applied)
        if not applied.ok then return stop(applied.reason) end
        progressState.done = 1
        pcall(restore.putBack, originals)
        local startedBaseline = bench.runWindow(guarded(function(baseline)
            if not baseline.ok then return stop("baseline " .. tostring(baseline.reason)) end
            finishWith({ ok = true, appliedMs = applied.summary.meanMs, baselineMs = baseline.summary.meanMs })
        end))
        if not startedBaseline then stop("window busy") end
    end))
    if not started then stop("window busy") end
end

-- One window at the current settings, saved as a labelled history entry: lets a setting changed by hand in the
-- menu be compared with the runner's number for the same tier.
function bench.mark(label, onDone)
    onDone = onDone or function() end
    local ok, problems, warnings = bench.preflight()
    for _, w in ipairs(warnings) do ns.say("warning: " .. w) end
    if not ok then
        for _, p in ipairs(problems) do ns.say("cannot mark: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    local spot = describeSpot()
    activeRun = true
    local started = bench.runWindow(function(r)
        activeRun = false
        local entry = {
            ok = r.ok and true or false, time = bench.now(), label = label, zone = spot.zone,
            instanceType = spot.instanceType, groupSize = spot.groupSize, resolution = spot.resolution,
            renderScale = spot.renderScale, rows = {},
        }
        if r.ok then
            local s = r.summary
            entry.valid = true
            entry.baselineMs = s.meanMs
            entry.rows[1] = { setting = label, value = "current", meanMs = s.meanMs, fps = s.fps, low1Fps = s.low1Fps,
                maxMs = s.maxMs, hitches = s.hitches, flags = copyList(r.flags), gameTime = r.gameTime }
        else
            entry.valid = false
            entry.reason = r.reason
        end
        pushHistory(entry)
        ns.say(bench.report(entry)[1])
        onDone(entry)
    end)
    if not started then
        activeRun = false
        ns.say("cannot mark: a window is already running")
        onDone({ ok = false, reason = "window busy" })
    end
end

-- One line per setting: current value and tiers, or why it is missing.
function bench.list()
    for _, row in ipairs(bench.SETTINGS) do
        local cvar = firstExisting(row)
        local mark = (row.confirmed == false) and " (unconfirmed)" or ""
        if not cvar then
            ns.say(row.label .. ": CVar not found (tried " .. table.concat(row.cvars, ", ") .. ")" .. mark)
        else
            local tiers = tiersFor(row, cvar)
            local text = (tiers and #tiers > 0) and table.concat(tiers, " ") or ("unknown, run /fset bench probe " .. cvar)
            ns.say(row.label .. " (" .. cvar .. ") = " .. tostring(GetCVar(cvar)) .. "  tiers: " .. text .. mark)
        end
    end
end

-- commands -----------------------------------------------------------------------------------------

-- Stops the active check, run or mark at its next frame; everything is put back.
function bench.stop()
    if not activeRun or not bench.measuring() then
        ns.say("no benchmark is running")
        return false
    end
    ns.say("stopping the benchmark")
    bench.abortWindow("stopped")
    return true
end

local HELP = "usage: /fset bench [check | stop | list | probe <cvar> | mark <label> | report [n]]"

-- `/fset bench <rest>`: no word runs the full benchmark.
function bench.handle(rest)
    local cmd, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then
        if ns.guide then ns.guide.open("run") else bench.run() end
    elseif cmd == "check" then
        if ns.guide then ns.guide.open("check") else bench.check() end
    elseif cmd == "stop" then
        bench.stop()
    elseif cmd == "list" then
        bench.list()
    elseif cmd == "probe" then
        if arg == "" then ns.say("usage: /fset bench probe <cvar>") return end
        local tiers, reason = bench.probe(arg)
        if tiers then
            ns.say(arg .. ": tiers " .. table.concat(tiers, " "))
        else
            ns.say("cannot probe " .. arg .. ": " .. tostring(reason))
        end
    elseif cmd == "mark" then
        if arg == "" then ns.say("usage: /fset bench mark <label>") return end
        bench.mark(arg)
    elseif cmd == "report" then
        local n = math.floor(tonumber(arg) or 1)
        local h = bench.history()
        local entry = (n >= 1) and h[#h - n + 1] or nil
        if not entry then
            ns.say("no saved benchmark" .. (n > 1 and (" number " .. string.format("%d", n)) or ""))
            return
        end
        for _, line in ipairs(bench.report(entry)) do ns.say(line) end
    else
        ns.say(HELP)
    end
end
