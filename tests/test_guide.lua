-- Tests for Guide.lua (spec 2026-10-29-guided-benchmark-window-design.md), driven through the shared harness.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function boot(cvars, opts)
    opts = opts or {}
    opts.fresh = true
    local e = H.boot(cvars or { graphicsShadowQuality = "4", RenderScale = "1", groundEffectDensity = "64", vsync = "0" }, opts)
    return e, e.ns.guide, e.ns.bench
end
local function outText() return table.concat(OUT, " | ") end

-- Task 1: the explanation texts (spec section 4)
local function same(a, b) return a == b end
local ROWS = {
    { "a run is already active", "A test is already running.", "Wait for it to finish, or press Stop." },
    { "you are in combat", "You are in combat.", "Leave combat, then try again." },
    { "combat", "You entered combat, so the test stopped.", "Leave combat, then try again." },
    { "you are moving or falling: stand still", "You are moving.", "Stand still the whole time, then try again." },
    { "movement", "You moved, so the test stopped.", "Stand still the whole time, then try again." },
    { "environment check failed: GetUnitSpeed", "The game is missing something this test needs.", "Tell the person who gave you this addon: GetUnitSpeed." },
    { "zoning", "The game changed zone or reloaded, so the test stopped.", "Stay where you are and do not reload, then try again." },
    { "stall", "The game froze for a moment, so the test stopped.", "Close other programs and try again." },
    { "few", "The game ran too slowly to measure.", "Close other programs and try again." },
    { "no frames", "The game stopped drawing frames, so the test stopped.", "Keep the game window in front, then try again." },
    { "stopped", "You stopped the test.", "You can start again any time." },
    { "control did not respond", "The test could not tell the settings apart here.",
        "This usually means the game window was not in front (alt-tab), or the frame rate is capped. Try again without switching windows." },
    { "control rejected", "The game would not accept a settings change.", "Close the graphics settings and try again." },
    { "panel:settings", "You opened the game's settings, so the test stopped.", "Leave it closed while the test runs, then try again." },
    { "panel:menu", "You opened the game menu, so the test stopped.", "Leave it closed while the test runs, then try again." },
    { "panel:map", "You opened the map, so the test stopped.", "Leave it closed while the test runs, then try again." },
    { "window busy", "Another measurement was already running.", "Wait a moment and try again." },
    { "no snapshot", "The addon could not take a copy of your settings, so it did not start.", "Nothing was changed. Tell the person who gave you this addon." },
    { "no control", "This game has no setting the test can use to check itself.", "Tell the person who gave you this addon." },
    { "nothing to measure", "There is nothing to measure yet.", "Some settings still need to be learned first: type /fset bench list to see which." },
    { "error: boom", "Something went wrong inside the addon.", "Your settings were put back. Tell the person who gave you this addon: boom." },
}

test("G1-1 every reason of the spec's table gets exactly its headline and advice", function()
    local _, g = boot()
    local bad = {}
    for _, row in ipairs(ROWS) do
        local headline, advice = g.explain(row[1])
        if not (same(headline, row[2]) and same(advice, row[3])) then bad[#bad + 1] = row[1] .. " -> " .. tostring(headline) end
    end
    return #bad == 0, table.concat(bad, "; ")
end)

test("G1-2 a baseline failure is explained as its inner reason, prefixed", function()
    local _, g = boot()
    local headline, advice = g.explain("baseline movement")
    local h2 = g.explain("baseline panel:menu")
    return headline == "The test stopped at the start: You moved, so the test stopped."
        and advice == "Stand still the whole time, then try again."
        and h2 == "The test stopped at the start: You opened the game menu, so the test stopped.", tostring(headline)
end)

test("G1-3 an unknown reason still gets a headline and advice, never nothing", function()
    local _, g = boot()
    local headline, advice = g.explain("zorp")
    return headline == "The test stopped (reason: zorp)." and advice == "Your settings were put back. Try again."
end)

test("G1-6 the 'no measurable effect' flag gets a plain sentence, not the code's own wording", function()
    local _, g = boot()
    return g.flagLine("no measurable effect or not applied") == "Some settings made no measurable difference in this spot; the report lists them."
end)

test("G1-4 the flag sentences, and any other flag as written", function()
    local _, g = boot()
    return g.flagLine("possible background-window cap") == "The game may have lost focus at some point (alt-tab?), so some results may be unreliable."
        and g.flagLine("lighting may have changed") == "The time of day in the game changed during the test, which can affect lighting results."
        and g.flagLine("something else") == "something else"
end)

test("G1-5 a second boot sees none of the first boot's guide state", function()
    local _, g1 = boot()
    g1.marker = 1
    local _, g2 = boot()
    return g2.marker == nil
end)

-- Task 2: the small pure helpers
test("G2-1 introMinutes rounds the windows' seconds up to whole minutes, never below one", function()
    local _, g = boot()
    return g.introMinutes(45) == 9 and g.introMinutes(1) == 1 and g.introMinutes(0) == 1 and g.introMinutes(5) == 1
        and g.introMinutes(6) == 2
end)

test("G2-2 timeLeft says less than a minute under 60 seconds, else about N minutes (one minute in the singular)", function()
    local _, g, b = boot()
    local a = g.timeLeft(40, 45)            -- 5 windows x 11 s = 55 s
    local c = g.timeLeft(39, 45)            -- 66 s
    local d = g.timeLeft(45, 45)
    local e2 = g.timeLeft(0, 45)            -- 495 s
    b.K.SETTLE, b.K.MEASURE = 4, 8          -- 12 s a window: 5 windows left is exactly 60 s
    local f = g.timeLeft(40, 45)
    return a == "less than a minute to go" and c == "roughly 2 minutes to go" and d == "less than a minute to go"
        and e2 == "roughly 9 minutes to go" and f == "roughly 1 minute to go", a .. " / " .. c .. " / " .. f
end)

test("G2-3 the restore line: put back, will be put back, or which settings could not be", function()
    local _, g = boot()
    local clean = g.restoreLine({ pending = false, issues = {} })
    local waiting = g.restoreLine({ pending = true, issues = {} })
    local bad = g.restoreLine({ pending = false, issues = { "graphicsSSAO: was 3, now 1", "RenderScale: was 1, now 0.5" } })
    local both = g.restoreLine({ pending = true, issues = { "graphicsSSAO: was 3, now 1" } })
    return clean == "Your graphics settings have been put back as they were."
        and waiting == "Your settings will be put back when combat ends, or at your next login."
        and bad == "These settings could not be put back: graphicsSSAO, RenderScale. Check them in the game's graphics menu."
        and both:find("These settings could not be put back: graphicsSSAO.", 1, true) == 1, bad
end)

test("G2-4 restoreInfo reads the live saved state each time it is asked", function()
    local _, g, b = boot()
    local st = b.state()
    local first = g.restoreInfo()
    st.pending = { time = 1, originals = {} }
    local second = g.restoreInfo()
    st.pending = nil
    st.lastRestoreIssues = { "graphicsSSAO: was 3, now 1" }
    local third = g.restoreInfo()
    return first.pending == false and #first.issues == 0 and second.pending == true
        and third.pending == false and #third.issues == 1 and third.issues[1] == "graphicsSSAO: was 3, now 1"
end)

-- Task 3: the model of the four views (spec section 3)
local CLEAN = { pending = false, issues = {} }
local PUT_BACK = "Your graphics settings have been put back as they were."
local RULES = {
    "", "Before you start:", "- Stand still somewhere quiet, not a busy city.",
    "- Pick a view with some trees, water or buildings in it, and leave the camera there.",
    "- Close browsers, video, recording and streaming programs.", "- Make sure you are not in combat.",
    "", "While it runs, please don't:", "- Move, jump or turn the camera.", "- Open the game menu, the settings or the map.",
    "- Switch to another window (alt-tab).", "- Change any graphics setting.", "- Log out or reload.",
}
local BOX = "I have closed other programs and will stay still, camera included, until it finishes"
local function linesEqual(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
local function button(view, key)
    for _, b in ipairs(view.buttons) do if b.key == key then return b end end
end
local function keysOf(view)
    local keys = {}
    for _, b in ipairs(view.buttons) do keys[#keys + 1] = b.key end
    return table.concat(keys, ",")
end

test("G3-1 Intro for a run: the exact title, lines and box, Start disabled, Escape allowed", function()
    local _, g = boot()
    local v = g.model({ view = "intro", kind = "run", ticked = false }, { windows = 45 })
    local want = { "This takes about 9 minutes. The game will change your graphics settings many times to measure each one, then put everything back." }
    for _, l in ipairs(RULES) do want[#want + 1] = l end
    local one = g.model({ view = "intro", kind = "run", ticked = false }, { windows = 5 })
    return v.title == "Test your graphics settings" and linesEqual(v.lines, want)
        and v.checkbox.text == BOX and v.checkbox.checked == false
        and keysOf(v) == "start,cancel" and button(v, "start").enabled == false and button(v, "cancel").enabled == true
        and v.escapeCloses == true and v.banner == nil and v.progress == nil
        and one.lines[1]:find("takes about 1 minute.", 1, true) ~= nil, tostring(v.lines[1])
end)

test("G3-1b Intro for a check: its own title and first line, the same rules", function()
    local _, g = boot()
    local v = g.model({ view = "intro", kind = "check", ticked = false }, { windows = 45 })
    local want = { "This takes about a minute. It checks that this is a good place to run the full test." }
    for _, l in ipairs(RULES) do want[#want + 1] = l end
    return v.title == "Check this spot" and linesEqual(v.lines, want), tostring(v.title)
end)

test("G3-2 ticking the box enables Start", function()
    local _, g = boot()
    local v = g.model({ view = "intro", kind = "run", ticked = true }, { windows = 45 })
    return v.checkbox.checked == true and button(v, "start").enabled == true
end)

test("G3-3 Running: the banner, the progress lines (a step-away line for a run, not for a check), only Stop, Escape does not close it", function()
    local _, g = boot()
    local v = g.model({ view = "running", kind = "run" }, { progress = { phase = "sweep", label = "Shadows 3", done = 12, total = 45 } })
    local starting = g.model({ view = "running", kind = "run" }, {})
    local c = g.model({ view = "running", kind = "check" }, {})
    local cp = g.model({ view = "running", kind = "check" }, { progress = { phase = "odd", label = "Control", done = 1, total = 4 } })
    return v.title == "Testing your settings" and v.banner == "PLEASE DON'T MOVE, TURN THE CAMERA OR OPEN ANY WINDOW"
        and linesEqual(v.progress, { "Step 12 of about 45, roughly 7 minutes to go", "Now testing: Shadows 3",
            "It runs on its own, so feel free to step away from the keyboard." })
        and linesEqual(cp.progress, { "Step 1 of about 4, less than a minute to go", "Control" })
        and keysOf(v) == "stop" and button(v, "stop").enabled == true and v.escapeCloses == false
        and linesEqual(starting.progress, { "Starting..." }) and c.title == "Checking this spot", tostring(v.progress and v.progress[1])
end)

test("G3-3b a run that repeats readings says why the step count grows, once a repeat has happened", function()
    local _, g = boot()
    local SENTENCE = "The step count has grown: when the frame rate isn't steady, the test measures that setting again so the result can be trusted."
    local STEP, NOW, AWAY = "Step 12 of about 45, roughly 7 minutes to go", "Now testing: Shadows 3",
        "It runs on its own, so feel free to step away from the keyboard."
    local function lines(kind, repeats, phase, label, done, total)
        return g.model({ view = "running", kind = kind },
            { progress = { phase = phase or "sweep", label = label or "Shadows 3", done = done or 12, total = total or 45, repeats = repeats } }).progress
    end
    local checked = lines("check", 1, "odd", "Control", 1, 4)
    return linesEqual(lines("run", nil), { STEP, NOW, AWAY }) and linesEqual(lines("run", 0), { STEP, NOW, AWAY })
        and linesEqual(lines("run", 2), { STEP, NOW, SENTENCE, AWAY })
        and linesEqual(checked, { "Step 1 of about 4, less than a minute to go", "Control", SENTENCE }), tostring(lines("run", 2)[3])
end)

test("G3-4 Stopped: headline, advice, the restore line, Try again and Close; a refused start lists every problem", function()
    local _, g = boot()
    local v = g.model({ view = "stopped", kind = "run", reason = "movement" }, { restore = CLEAN })
    local bad = g.model({ view = "stopped", kind = "run", reason = "movement" },
        { restore = { pending = false, issues = { "graphicsSSAO: was 3, now 1" } } })
    local pre = g.model({ view = "stopped", kind = "run", reason = "preflight",
        problems = { "you are in combat", "you are moving or falling: stand still" } }, { restore = CLEAN })
    return v.title == "The test stopped"
        and linesEqual(v.lines, { "You moved, so the test stopped.", "Stand still the whole time, then try again.", "", PUT_BACK })
        and keysOf(v) == "again,close" and v.escapeCloses == true
        and bad.lines[4] == "These settings could not be put back: graphicsSSAO. Check them in the game's graphics menu."
        and linesEqual(pre.lines, { "You are in combat.", "Leave combat, then try again.", "You are moving.",
            "Stand still the whole time, then try again.", "", PUT_BACK }), tostring(v.lines[1])
end)

test("G3-5 Done for a run: finished, the restore line, each flag once, the inconclusive count, Show report only with an entry", function()
    local _, g = boot()
    local entry = { valid = true, rows = {
        { flags = { "possible background-window cap" } },
        { flags = { "possible background-window cap", "lighting may have changed" } },
        { status = "inconclusive", flags = {} }, { status = "inconclusive", flags = {} },
    } }
    local v = g.model({ view = "done", kind = "run", entry = entry }, { restore = CLEAN })
    local single = g.model({ view = "done", kind = "run", entry = { valid = true, rows = { { status = "inconclusive", flags = {} } } } }, { restore = CLEAN })
    local none = g.model({ view = "done", kind = "run" }, { restore = CLEAN })
    return v.title == "Finished"
        and linesEqual(v.lines, { "The test is finished.", PUT_BACK,
            "The game may have lost focus at some point (alt-tab?), so some results may be unreliable.",
            "The time of day in the game changed during the test, which can affect lighting results.",
            "2 settings could not be measured reliably; they are marked in the report." })
        and keysOf(v) == "report,close" and button(v, "report").enabled == true and button(none, "report").enabled == false
        and single.lines[3] == "1 setting could not be measured reliably; it is marked in the report.", tostring(v.lines[5])
end)

test("G3-6 Done for a check: good or not good with the reason, the uneven-frame-rate line, Run the full test only when good", function()
    local _, g = boot()
    local good = g.model({ view = "done", kind = "check", result = { ok = true, spread = 0.01 } }, { restore = CLEAN })
    local bad = g.model({ view = "done", kind = "check", result = { ok = false, reason = "control did not respond", spread = 0.01 } }, { restore = CLEAN })
    local uneven = g.model({ view = "done", kind = "check", result = { ok = true, spread = 0.3 } }, { restore = CLEAN })
    local h, a = g.explain("control did not respond")
    return good.title == "Check finished" and linesEqual(good.lines, { "This spot is good for testing.", PUT_BACK })
        and keysOf(good) == "full,close" and button(good, "full").enabled == true
        and linesEqual(bad.lines, { "This spot is not good for testing right now.", h, a, PUT_BACK }) and keysOf(bad) == "close"
        and linesEqual(uneven.lines, { "This spot is good for testing.", "The frame rate was uneven here; a quieter spot gives better results.", PUT_BACK }),
        tostring(good.lines[1])
end)

-- Task 4: the forbidden windows (spec section 5). true = shown, false = hidden, absent = the global does not exist.
local function setFrames(t)
    for _, name in ipairs({ "SettingsPanel", "GameMenuFrame", "WorldMapFrame" }) do
        local state = t[name]
        if state == nil then
            _G[name] = nil
        else
            _G[name] = { IsShown = function() return state end }
        end
    end
end

test("G4-1 each forbidden window is named when shown, in the order settings, menu, map", function()
    local _, g = boot()
    setFrames({ SettingsPanel = true, GameMenuFrame = false, WorldMapFrame = false })
    local a = g.panelReason()
    setFrames({ SettingsPanel = false, GameMenuFrame = true, WorldMapFrame = false })
    local b2 = g.panelReason()
    setFrames({ SettingsPanel = false, GameMenuFrame = false, WorldMapFrame = true })
    local c = g.panelReason()
    setFrames({ SettingsPanel = false, GameMenuFrame = true, WorldMapFrame = true })
    local both = g.panelReason()
    setFrames({ SettingsPanel = true, GameMenuFrame = true, WorldMapFrame = true })
    local all = g.panelReason()
    setFrames({ SettingsPanel = false, GameMenuFrame = false, WorldMapFrame = false })
    local none = g.panelReason()
    setFrames({})
    return a == "panel:settings" and b2 == "panel:menu" and c == "panel:map" and both == "panel:menu"
        and all == "panel:settings" and none == nil, tostring(a) .. tostring(b2) .. tostring(c) .. tostring(both) .. tostring(all)
end)

test("G4-2 a missing global, or one that cannot say whether it is shown, is skipped without an error", function()
    local _, g = boot()
    setFrames({})
    local ok1, none = pcall(g.panelReason)
    _G.SettingsPanel = {}                    -- no IsShown
    _G.GameMenuFrame = 5                     -- not a frame at all
    _G.WorldMapFrame = { IsShown = function() return true end }
    local ok2, map = pcall(g.panelReason)
    setFrames({})
    return ok1 and none == nil and ok2 and map == "panel:map", tostring(ok1) .. tostring(ok2)
end)

-- Task 5: the flow, the routes (spec section 6)
local function runCvars() return { RenderScale = "1", graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64", vsync = "0" } end
local function newRun()
    local e, g, b = boot(runCvars())
    b.K.SETTLE, b.K.MEASURE, b.K.MIN_FRAMES = 0.05, 0.2, 20
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    setFrames({})
    return e, g, b
end
local function runCost(cv) return 0.002 + 0.004 * tonumber(cv.RenderScale) + 0.0005 * tonumber(cv.graphicsShadowQuality) end
local function renderCost(cv) return 0.004 + 0.004 * tonumber(cv.RenderScale) end
local function startVia(g, kind) g.open(kind); g.setTicked(true); g.click("start") end
local function findItem(items, text)
    for _, item in ipairs(items) do
        if item.text == text then return item end
        if item.children then
            local hit = findItem(item.children, text)
            if hit then return hit end
        end
    end
end

test("G5-1 /fset bench, /fset bench check and the menu items open the Intro and start nothing", function()
    local e, g, b = newRun()
    e.slash("bench")
    local run = g.state().view == "intro" and g.state().kind == "run" and not b.active() and b.watch == nil
    e.slash("bench check")
    local check = g.state().view == "intro" and g.state().kind == "check" and not b.active()
    local model = e.ns.ui.menuModel(e.ns.ui.buildContext())
    findItem(model, "Run benchmark").run()
    local menuRun = g.state().kind == "run" and g.state().view == "intro" and not b.active()
    findItem(model, "Check this spot").run()
    return run and check and menuRun and g.state().kind == "check" and g.state().view == "intro" and not b.active()
        and #b.history() == 0, outText()
end)

test("G5-2 opening the window during a run shows Running and starts no second run", function()
    local e, g, b = newRun()
    b.run()
    e.pump(0.3, runCost)
    local pend = b.state().pending
    e.slash("bench")
    local showing = g.state().view == "running"
    e.pump(60, runCost)
    local h = b.history()
    return pend ~= nil and showing and #h == 1 and h[1].valid == true and b.state().pending == nil and b.active() == false, outText()
end)

test("G5-2b opening the window during a check started from it keeps the Running view of that check", function()
    local e, g, b = newRun()
    startVia(g, "check")
    e.pump(0.3, renderCost)
    local running = g.state()
    e.slash("bench")
    local same = g.state() == running and g.state().kind == "check" and g.state().view == "running"
    e.pump(60, renderCost)
    return same and g.state().view == "done" and g.state().kind == "check" and #b.history() == 0, outText()
end)

test("G5-3 Start does nothing until the box is ticked; with a forbidden window open it starts nothing and explains", function()
    local e, g, b = newRun()
    g.open("run")
    g.click("start")
    local ignored = g.state().view == "intro" and not b.active()
    g.setTicked(true)
    setFrames({ SettingsPanel = true })
    g.click("start")
    local blocked = g.state().view == "stopped" and g.state().reason == "panel:settings" and not b.active() and b.watch == nil
    setFrames({})
    g.click("again")
    g.setTicked(true)
    g.click("start")
    local started = g.state().view == "running" and b.active() == true and b.watch == g.panelReason
    e.pump(60, runCost)
    return ignored and blocked and started and g.state().view == "done", outText()
end)

test("G5-4 a run started through Start completes: the watch is set while it runs and cleared after, Done shows, Show report reaches the report", function()
    local e, g, b = newRun()
    -- The window offers the report on its button; a run it started does not open the report on top of itself.
    local shown = {}
    e.ns.ui.showReport = function(entry) shown[#shown + 1] = entry end
    startVia(g, "run")
    local during = b.watch == g.panelReason and g.state().view == "running"
    e.pump(60, runCost)
    local st = g.state()
    local before = #shown
    g.click("report")
    return during and st.view == "done" and st.entry ~= nil and st.entry.valid == true and b.watch == nil
        and before == 0 and #shown == 1 and shown[1] == st.entry, outText()
end)

test("G5-4b a run the window did not start still opens its report by itself, with or without the window showing it", function()
    local e = newRun()
    local shown = {}
    e.ns.ui.showReport = function(entry) shown[#shown + 1] = entry end
    e.ns.bench.run()
    e.pump(60, runCost)
    local alone = #shown == 1
    local e2 = newRun()
    local shown2 = {}
    e2.ns.ui.showReport = function(entry) shown2[#shown2 + 1] = entry end
    e2.ns.bench.run()
    e2.pump(0.3, runCost)
    e2.slash("bench")
    e2.pump(60, runCost)
    return alone and #shown2 == 1, #shown .. "/" .. #shown2
end)

test("G5-5 a refused start shows its problem and leaves no watch hook or suspension; a plain run still works afterwards", function()
    local e, g, b = newRun()
    COMBAT = true
    startVia(g, "run")
    local st = g.state()
    local combat = st.view == "stopped" and st.reason == "preflight" and st.problems[1] == "you are in combat"
        and g.model(st, {}).lines[1] == "You are in combat."
    COMBAT = false
    SPEED = 1
    startVia(g, "run")
    local moving = g.state().view == "stopped" and g.state().problems[1] == "you are moving or falling: stand still"
    SPEED = 0
    local clean = e.ns.suspended == false and b.watch == nil and not b.active()
    local entry
    b.run(function(r) entry = r end)
    e.pump(60, runCost)
    return combat and moving and clean and entry ~= nil and entry.valid == true, outText()
end)

test("G5-6 Close then /fset bench gives a fresh unticked Intro; Try again needs a fresh tick", function()
    local e, g, b = newRun()
    g.open("run")
    g.setTicked(true)
    g.click("close")
    e.slash("bench")
    local fresh = g.state().view == "intro" and g.state().ticked == false
    COMBAT = true
    g.setTicked(true)
    g.click("start")
    COMBAT = false
    g.click("again")
    return fresh and g.state().view == "intro" and g.state().ticked == false and g.state().kind == "run", outText()
end)

test("G5-7 a check: good gives Done, 'control did not respond' gives Done (not good), a movement stop gives Stopped", function()
    local e, g = newRun()
    startVia(g, "check")
    e.pump(60, renderCost)
    local good = g.state().view == "done" and g.state().result.ok == true
    local e2, g2 = newRun()
    startVia(g2, "check")
    e2.pump(60, function() return 0.008 end)
    local notGood = g2.state().view == "done" and g2.state().result.ok == false and g2.state().result.reason == "control did not respond"
    local e3, g3 = newRun()
    startVia(g3, "check")
    e3.pump(0.3, renderCost)
    SPEED = 1
    e3.pump(5, renderCost)
    local moved = g3.state().view == "stopped" and g3.state().reason == "movement"
    SPEED = 0
    return good and notGood and moved, tostring(good) .. tostring(notGood) .. tostring(moved)
end)

-- Each real stop, driven through the Start button: the stored reason is the literal the code emits, the window says
-- the words for it, and nothing is left behind (no hook, no suspension, no active run).
local REAL = {
    { "movement", nil, function(e) e.pump(0.3, runCost); SPEED = 1; e.pump(5, runCost); SPEED = 0 end },
    { "combat", nil, function(e) e.pump(0.3, runCost); e.fire("PLAYER_REGEN_DISABLED"); e.pump(2, runCost) end },
    { "zoning", nil, function(e) e.pump(0.3, runCost); e.fire("PLAYER_LEAVING_WORLD"); e.pump(2, runCost) end },
    { "stall", nil, function(e) e.pump(30, function() return 1.5 end) end },
    { "few", function(e, g, b) b.K.MIN_FRAMES = 100000 end, function(e) e.pump(60, runCost) end },
    { "no frames", nil, function(e) e.advance(6) end },
    { "stopped", nil, function(e, g) e.pump(0.3, runCost); g.click("stop"); e.pump(2, runCost) end },
    { "control did not respond", nil, function(e) e.pump(60, function() return 0.008 end) end },
    { "control rejected", function() SETFAIL.RenderScale = "clamp" end, function(e) e.pump(60, runCost) end },
    { "panel:map", nil, function(e) e.pump(0.3, runCost); setFrames({ WorldMapFrame = true }); e.pump(5, runCost); setFrames({}) end },
}
test("G5-8 every real stop reaches the window with its literal reason and its words, and leaves nothing behind", function()
    local bad = {}
    for _, row in ipairs(REAL) do
        local reason, pre, drive = row[1], row[2], row[3]
        local e, g, b = newRun()
        if pre then pre(e, g, b) end
        startVia(g, "run")
        drive(e, g, b)
        local st = g.state()
        local headline = g.explain(reason)
        local shown = g.model(st, { restore = g.restoreInfo() }).lines[1]
        if not (st.view == "stopped" and st.reason == reason and shown == headline and b.watch == nil
            and e.ns.suspended == false and b.active() == false) then
            bad[#bad + 1] = reason .. " (view " .. tostring(st.view) .. ", reason " .. tostring(st.reason) .. ")"
        end
    end
    return #bad == 0, table.concat(bad, "; ")
end)

-- Task 6: the frame adapter (spec sections 3, 5, 6, 9). The tests read what the player can read: the texts shown on
-- the window's font strings and the labels of its buttons.
local WINDOW = "ForeverSettingsGuide"
local BOX_LABEL = "I have closed other programs and will stay still, camera included, until it finishes"
local function guideFrame()
    for _, f in ipairs(H.frames()) do
        if f.name == WINDOW then return f end
    end
end
local function shownText(f)
    local list = {}
    for _, fs in ipairs(f.fontStrings) do
        if fs.shown and fs._text and fs._text ~= "" then list[#list + 1] = fs._text end
    end
    return table.concat(list, "\n")
end
local function hasText(f, part) return shownText(f):find(part, 1, true) ~= nil end
local function findButton(f, label)
    for _, c in ipairs(f.children) do
        if c.kind == "Button" and c.shown and c._text == label then return c end
    end
end
local function boxOf(f)
    for _, c in ipairs(f.children) do
        if c.kind == "CheckButton" or (c.kind == "Button" and c._text and c._text:find(BOX_LABEL, 1, true)) then return c end
    end
end
local function listed()
    local n = 0
    for _, name in ipairs(UISpecialFrames) do
        if name == WINDOW then n = n + 1 end
    end
    return n
end

test("G6-1 /fset bench draws the Intro: shown, with its title and lines, a disabled Start and an enabled Cancel", function()
    local e, g = newRun()
    e.slash("bench")
    local f = guideFrame()
    if not f then return false, "no frame: " .. outText() end
    local start, cancel = findButton(f, "Start"), findButton(f, "Cancel")
    return f:IsShown() and hasText(f, "Test your graphics settings") and hasText(f, "While it runs, please don't:")
        and hasText(f, "- Log out or reload.") and hasText(f, BOX_LABEL) and not hasText(f, "TURN THE CAMERA OR OPEN ANY WINDOW")
        and start ~= nil and start:IsEnabled() == false and cancel ~= nil and cancel:IsEnabled() == true, shownText(f)
end)

test("G6-2 ticking the box enables Start, Start draws Running, and the Done view's buttons work", function()
    local e, g, b = newRun()
    local reported = {}
    e.ns.ui.showReport = function(entry) reported[#reported + 1] = entry end
    e.slash("bench")
    local f = guideFrame()
    boxOf(f):Click()
    local enabled = g.state().ticked == true and findButton(f, "Start"):IsEnabled() == true
    boxOf(f):Click()
    local disabled = g.state().ticked == false and findButton(f, "Start"):IsEnabled() == false
    boxOf(f):Click()
    findButton(f, "Start"):Click()
    local running = g.state().view == "running" and b.active() == true and hasText(f, "Testing your settings")
        and hasText(f, "PLEASE DON'T MOVE, TURN THE CAMERA OR OPEN ANY WINDOW") and findButton(f, "Stop") ~= nil and findButton(f, "Start") == nil
    e.pump(60, runCost)
    local done = g.state().view == "done" and hasText(f, "The test is finished.") and findButton(f, "Show report") ~= nil
    local before = #reported
    findButton(f, "Show report"):Click()
    local shown = #reported == before + 1 and reported[#reported] == g.state().entry
    findButton(f, "Close"):Click()
    return enabled and disabled and running and done and shown and not f:IsShown(), shownText(f)
end)

test("G6-3 Escape may close the window in Intro, Stopped and Done but never while Running, and its name is listed once", function()
    local e, g, b = newRun()
    g.open("run")
    g.render()
    g.render()
    local intro = listed() == 1
    g.setTicked(true)
    COMBAT = true
    g.click("start")
    COMBAT = false
    local stopped = g.state().view == "stopped" and listed() == 1
    g.click("again")
    g.setTicked(true)
    g.click("start")
    local running = g.state().view == "running" and listed() == 0
    g.render()
    local still = listed() == 0
    e.pump(60, runCost)
    local done = g.state().view == "done" and listed() == 1
    g.render()
    g.render()
    return intro and stopped and running and still and done and listed() == 1,
        tostring(intro) .. tostring(stopped) .. tostring(running) .. tostring(still) .. tostring(done) .. listed()
end)

test("G6-4 while Running the progress is redrawn every 0.5 s of frame time and not sooner", function()
    local e, g, b = newRun()
    startVia(g, "run")
    local f = guideFrame()
    b.progress = function() return { phase = "sweep", label = "Shadows", done = 2, total = 9 } end
    f.scripts.OnUpdate(f, 0.2)
    local early = not hasText(f, "Now testing: Shadows")
    f.scripts.OnUpdate(f, 0.6)
    return early and hasText(f, "Now testing: Shadows") and hasText(f, "Step 2 of about 9"), shownText(f)
end)

test("G6-5 a client without the window templates still gets a usable window", function()
    local e, g, b = newRun()
    local real = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
        if template then error("no template " .. tostring(template)) end
        return real(kind, name, parent)
    end
    e.slash("bench")
    local f = guideFrame()
    if not f then _G.CreateFrame = real; return false, "no frame: " .. outText() end
    local box, start = boxOf(f), findButton(f, "Start")
    local usable = f:IsShown() and box ~= nil and start ~= nil and start:IsEnabled() == false
    if box then box:Click() end
    local ticked = g.state().ticked == true and start ~= nil and start:IsEnabled() == true
    if start then start:Click() end
    local running = g.state().view == "running" and b.active() == true
    e.pump(60, runCost)
    local view = g.state().view
    _G.CreateFrame = real
    return usable and ticked and running and view == "done", outText()
end)

test("G6-6 the Intro's minutes come from the real window count", function()
    local e, g, b = boot(runCvars())
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    local resolved = b.resolve()
    local currents = {}
    for _, r in ipairs(resolved) do currents[r.cvar] = GetCVar(r.cvar) end
    local count = b.countWindows(resolved, currents)
    local want = math.ceil(count * (b.K.SETTLE + b.K.MEASURE) / 60)
    e.slash("bench")
    local f = guideFrame()
    return want >= 2 and f ~= nil and hasText(f, "This takes about " .. want .. " minutes."),
        "want " .. want .. " from " .. count .. " windows: " .. (f and shownText(f) or "no frame")
end)

test("G6-7 a window that cannot be drawn says so and starts nothing", function()
    local e, g, b = newRun()
    local real = _G.CreateFrame
    _G.CreateFrame = function() error("no frames today") end
    local ok, err = pcall(e.slash, "bench")
    _G.CreateFrame = real
    local said = outText()
    return ok and said:find("could not be drawn", 1, true) ~= nil and said:find("no frames today", 1, true) ~= nil
        and not b.active() and g.state().view == "intro", tostring(err) .. " / " .. said
end)

test("G6-8 a Running view for a test the window did not start ends with that test", function()
    local e, g, b = newRun()
    b.run()
    e.pump(0.3, runCost)
    e.slash("bench")
    local f = guideFrame()
    local showing = f ~= nil and f:IsShown() and g.state().view == "running"
    e.pump(60, runCost)
    return showing and b.active() == false and not f:IsShown() and g.state().view == "intro" and g.state().ticked == false,
        tostring(g.state().view)
end)

test("G6-10 hiding the window while a test runs (the title bar's X) shows it again, and a finished test's result is on screen", function()
    local e, g, b = newRun()
    startVia(g, "run")
    local f = guideFrame()
    f:Hide()
    local back = f:IsShown() and g.state().view == "running" and b.active() == true
    e.pump(0.3, runCost)
    SPEED = 1
    e.pump(5, runCost)
    SPEED = 0
    local stopped = g.state().view == "stopped" and g.state().reason == "movement" and f:IsShown() and hasText(f, "You moved")
    f:Hide()
    return back and stopped and not f:IsShown(), shownText(f)
end)

local function reportFrame()
    for _, f in ipairs(H.frames()) do
        if f.name == "ForeverSettingsReport" then return f end
    end
end

test("G6-11 Show report opens the report window and closes the Finished window, so the two never overlap", function()
    local e, g, b = newRun()
    startVia(g, "run")
    e.pump(60, runCost)
    local f = guideFrame()
    local onItsOwn = reportFrame() ~= nil and reportFrame():IsShown()
    findButton(f, "Show report"):Click()
    local r = reportFrame()
    return g.state().view == "done" and not onItsOwn and r ~= nil and r:IsShown() and not f:IsShown(), tostring(r and r:IsShown())
end)

-- Recommender, Task 6: the setup kind (plan 2026-10-29-recommender.md)
local function newSetup(cvars)
    local cv = cvars or runCvars()
    if not cvars then cv.graphicsLiquidDetail = "1" end      -- present in the client, levels not learned yet
    local e, g, b = boot(cv)
    b.K.SETTLE, b.K.MEASURE, b.K.MIN_FRAMES = 0.05, 0.2, 20
    if not cvars then       -- the default client already knows the levels of two settings; a custom one knows none
        b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
        b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    end
    setFrames({})
    return e, g, b
end
local function startSetup(g, target)
    g.open("setup")
    g.click("target:" .. tostring(target))
    g.setTicked(true)
    g.click("start")
end
local function copyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end
local function sameTable(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

test("G7-1 opening the setup window shows the Intro of kind setup and starts nothing", function()
    local e, g, b = newSetup()
    g.open("setup")
    local view = g.model(g.state(), { windows = 13 })
    return g.state().view == "intro" and g.state().kind == "setup" and g.state().ticked == false
        and view.title == "Find your best settings" and not b.active() and #SETLOG == 0 and b.watch == nil, tostring(g.state().view)
end)

test("G7-2 Start is enabled only with the box ticked and a target chosen; the first line counts the minutes; Start without a target is inert", function()
    local _, g = boot()
    local function startEnabled(ticked, target)
        local view = g.model({ view = "intro", kind = "setup", ticked = ticked, target = target }, { windows = 13 })
        for _, button in ipairs(view.buttons) do
            if button.key == "start" then return button.enabled end
        end
    end
    local sentence = " The game will change your graphics settings many times to measure each one, then put everything back exactly as it was."
    local drink = ", so it's a good time to grab a drink."
    local view = g.model({ view = "intro", kind = "setup", ticked = true, target = 165 }, { windows = 13 })
    local one = g.model({ view = "intro", kind = "setup", ticked = false }, { windows = 5 })
    local e2, g2, b2 = newSetup()
    g2.open("setup")
    g2.setTicked(true)
    g2.click("start")
    local inert = g2.state().view == "intro" and not b2.active() and #SETLOG == 0
    return startEnabled(false, nil) == false and startEnabled(true, nil) == false and startEnabled(false, 165) == false
        and startEnabled(true, 165) == true and view.lines[1] == "This takes about 3 minutes" .. drink .. sentence
        and one.lines[1] == "This takes about 1 minute" .. drink .. sentence
        and view.targets.prompt == "How smooth do you want it? Pick your monitor's refresh rate, or the frame rate you're aiming for."
        and table.concat(view.targets.list, ",") == "60,90,120,144,165,240" and view.targets.selected == 165 and inert,
        tostring(startEnabled(true, 165)) .. " / " .. view.lines[1]
end)

test("G7-3 a saved target is pre-selected; choosing one does not save it until Start; a target that is not listed is ignored", function()
    local e, g = newSetup()
    e.ns.ui.state().target = 144
    g.open("setup")
    local preselected = g.state().target == 144
    g.click("target:165")
    local chosen = g.state().target == 165 and e.ns.ui.state().target == 144
    g.click("target:100")
    local ignored = g.state().target == 165
    e.ns.ui.state().target = 100
    g.open("setup")
    return preselected and chosen and ignored and g.state().target == nil, tostring(g.state().target)
end)

test("G7-4 Start learns the unlearned settings before the run begins, saves the target and sets the watch", function()
    local e, g, b = newSetup()
    startSetup(g, 165)
    local others = {}
    for _, name in ipairs(SETLOG) do
        if name ~= "graphicsLiquidDetail" then others[#others + 1] = name end
    end
    return g.state().view == "running" and g.state().started == true and b.active() == true and b.watch == g.panelReason
        and #SETLOG > 0 and #others == 0 and b.state().tiers.graphicsLiquidDetail ~= nil
        and #b.state().tiers.graphicsLiquidDetail == 13 and e.ns.ui.state().target == 165, table.concat(others, ",")
end)

test("G7-5 with a forbidden window open nothing is learned, nothing starts and the target is not saved", function()
    local e, g, b = newSetup()
    setFrames({ SettingsPanel = true })
    startSetup(g, 165)
    setFrames({})
    return g.state().view == "stopped" and g.state().reason == "panel:settings" and not b.active() and #SETLOG == 0
        and b.state().tiers.graphicsLiquidDetail == nil and e.ns.ui.state().target == nil, tostring(g.state().reason)
end)

test("G7-6 a valid setup run closes the guided window and hands its entry and target to the results window, with no report of its own", function()
    local e, g, b = newSetup()
    local calls, shown = {}, {}
    e.ns.results = { show = function(entry, target) calls[#calls + 1] = { entry, target } end }
    e.ns.ui.showReport = function(entry) shown[#shown + 1] = entry end
    startSetup(g, 165)
    e.pump(120, runCost)
    local f = guideFrame()
    return #calls == 1 and calls[1][1] ~= nil and calls[1][1].valid == true and calls[1][2] == 165 and f ~= nil and not f:IsShown()
        and g.state().view == "done" and g.state().kind == "setup" and #shown == 0 and not b.active(),
        tostring(#calls) .. " " .. tostring(g.state().view) .. " " .. outText()
end)

test("G7-7 an invalid setup run shows Stopped, never the results, writes no profile and puts every setting back", function()
    local e, g, b = newSetup()
    local calls = 0
    e.ns.results = { show = function() calls = calls + 1 end }
    local before = copyTable(CVARS)
    -- The test build's default forced setting is migrated into Everyday at boot, so "nothing written" means unchanged.
    local db = e.ns.db()
    local everydayBefore, activeBefore = copyTable(db.profiles.everyday.values), db.active
    startSetup(g, 165)
    e.pump(0.3, runCost)
    SPEED = 1
    e.pump(5, runCost)
    SPEED = 0
    local bad = {}
    for k, v in pairs(before) do
        if CVARS[k] ~= v then bad[#bad + 1] = k end
    end
    return g.state().view == "stopped" and g.state().reason == "movement" and calls == 0
        and sameTable(db.profiles.everyday.values, everydayBefore) and db.active == activeBefore
        and #bad == 0 and e.ns.suspended == false,
        "view " .. tostring(g.state().view) .. " reason " .. tostring(g.state().reason) .. " calls " .. calls
            .. " bad " .. table.concat(bad, ",") .. " suspended " .. tostring(e.ns.suspended)
end)

test("G7-8 without a results window a valid setup run shows the ordinary Done view", function()
    local e, g, b = newSetup()
    e.ns.results = nil
    startSetup(g, 165)
    e.pump(120, runCost)
    local f = guideFrame()
    return g.state().view == "done" and f:IsShown() and hasText(f, "The test is finished."), tostring(g.state().view)
end)

test("G7-9 the six target buttons are drawn only in the setup Intro, and choosing one highlights it", function()
    local e, g = newSetup()
    g.open("setup")
    local f = guideFrame()
    local found = true
    for _, label in ipairs({ "60", "90", "120", "144", "165", "240" }) do
        if not findButton(f, label) then found = false end
    end
    findButton(f, "165"):Click()
    local picked = g.state().target == 165 and findButton(f, "165").locked == true and findButton(f, "60").locked ~= true
    boxOf(f):Click()
    local ready = findButton(f, "Start"):IsEnabled() == true and hasText(f, "How smooth do you want it?")
    g.open("run")
    return found and picked and ready and findButton(f, "165") == nil and not hasText(f, "How smooth do you want it?"), shownText(f)
end)

test("G7-10 the Intro's minutes for a first-time player come from the setup estimate, which counts the unlearned settings", function()
    local e, g, b = newSetup({ graphicsShadowQuality = "2", graphicsSSAO = "2", graphicsLiquidDetail = "1" })
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    b.K.SETTLE, b.K.MEASURE = 3.0, 8.0
    g.open("setup")
    g.click("mode:thorough")      -- the Intro counts the selected mode; the thorough test is the full sweep
    local f = guideFrame()
    local estimate = b.estimateSetupWindows()
    local want = math.ceil(estimate * 11 / 60)
    return estimate == 18 and want == 4 and hasText(f, "This takes about 4 minutes, so it's a good time to grab a drink."), shownText(f)
end)

test("G7-11 when nothing can be learned or measured the setup run stops with the nothing-to-measure words and no results", function()
    local e, g, b = newSetup({ vsync = "0", graphicsSSAO = "3" })
    SETFAIL.graphicsSSAO = "clamp"
    local calls = 0
    e.ns.results = { show = function() calls = calls + 1 end }
    local db = e.ns.db()
    local everydayBefore, activeBefore = copyTable(db.profiles.everyday.values), db.active
    startSetup(g, 165)
    local f = guideFrame()
    return g.state().view == "stopped" and g.state().reason == "nothing to measure" and calls == 0
        and hasText(f, "There is nothing to measure yet.") and sameTable(db.profiles.everyday.values, everydayBefore)
        and db.active == activeBefore,
        "view " .. tostring(g.state().view) .. " reason " .. tostring(g.state().reason) .. " calls " .. calls
end)

test("G7-12 Try again after a refused setup start keeps the chosen target but needs a fresh tick", function()
    local e, g = newSetup()
    g.open("setup")
    g.click("target:144")
    g.setTicked(true)
    setFrames({ SettingsPanel = true })
    g.click("start")
    setFrames({})
    local stopped = g.state().view == "stopped"
    g.click("again")
    return stopped and g.state().view == "intro" and g.state().kind == "setup" and g.state().target == 144
        and g.state().ticked == false and e.ns.ui.state().target == nil, tostring(g.state().target)
end)

test("G7-13 a real setup run for a Render scale of 0.75 (not one of the measured levels) is recommended, not dropped as not measured", function()
    local e, g, b = newSetup({ RenderScale = "0.75", graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64", vsync = "0" })
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    local seen
    e.ns.results = { show = function(entry, target) seen = { entry = entry, target = target } end }
    startSetup(g, 165)
    e.pump(120, runCost)
    if not seen then return false, "no hand-off: " .. tostring(g.state().view) .. " " .. tostring(g.state().reason) end
    local res = e.ns.recommend.choose(seen.entry, seen.target)
    local scaleSetting
    for _, s in ipairs(res.settings) do
        if s.cvar == "RenderScale" then scaleSetting = s end
    end
    local listed = false
    for _, n in ipairs(res.notMeasured) do
        if n.cvar == "RenderScale" then listed = true end
    end
    return scaleSetting ~= nil and not listed and scaleSetting.current == "0.75", tostring(res.status) .. " " .. tostring(listed)
end)

test("G6-9 every button does what its label says in every view", function()
    local e, g, b = newRun()
    e.slash("bench")
    local f = guideFrame()
    findButton(f, "Cancel"):Click()
    local cancelled = not f:IsShown()
    e.slash("bench")
    boxOf(f):Click()
    COMBAT = true
    findButton(f, "Start"):Click()
    COMBAT = false
    local stopped = g.state().view == "stopped" and findButton(f, "Try again") ~= nil and findButton(f, "Close") ~= nil
    findButton(f, "Try again"):Click()
    local fresh = g.state().view == "intro" and g.state().ticked == false and boxOf(f).checked == false
        and findButton(f, "Start"):IsEnabled() == false
    boxOf(f):Click()
    COMBAT = true
    findButton(f, "Start"):Click()
    COMBAT = false
    findButton(f, "Close"):Click()
    return cancelled and stopped and fresh and not f:IsShown(), shownText(f)
end)

-- Crowd test, Task 6: Quick or Thorough at the first screen of the quiet-spot test (spec section 3)
test("G8-1 the setup Intro offers Quick and Thorough with each mode's minutes, and its first line counts the selected one", function()
    local _, g = boot()
    local counts = { quick = 24, thorough = 38 }
    local quick = g.model({ view = "intro", kind = "setup", ticked = false, mode = "quick" }, { windows = 24, windowsByMode = counts })
    local thorough = g.model({ view = "intro", kind = "setup", ticked = false, mode = "thorough" }, { windows = 38, windowsByMode = counts })
    local one = g.model({ view = "intro", kind = "setup", ticked = false, mode = "quick" },
        { windows = 3, windowsByMode = { quick = 3, thorough = 38 } })
    local run = g.model({ view = "intro", kind = "run", ticked = false }, { windows = 24 })
    local e, g2, b = newSetup()
    local asked = {}
    b.estimateSetupWindows = function(mode) asked[#asked + 1] = tostring(mode) return mode == "quick" and 24 or 38 end
    b.K.SETTLE, b.K.MEASURE = 3.0, 8.0
    g2.open("setup")
    local f = guideFrame()
    local drawn = hasText(f, "This takes about 5 minutes,") and findButton(f, "Quick (about 5 minutes)") ~= nil
        and findButton(f, "Thorough (about 7 minutes)") ~= nil
    return quick.modes.selected == "quick" and quick.modes.list[1].key == "quick" and quick.modes.list[1].text == "Quick (about 5 minutes)"
        and quick.modes.list[2].key == "thorough" and quick.modes.list[2].text == "Thorough (about 7 minutes)"
        and quick.lines[1]:find("This takes about 5 minutes,", 1, true) == 1
        and thorough.modes.selected == "thorough" and thorough.lines[1]:find("This takes about 7 minutes,", 1, true) == 1
        and one.modes.list[1].text == "Quick (about 1 minute)" and run.modes == nil and drawn
        and table.concat(asked, ",") == "quick,all", shownText(f)
end)

test("G8-2 Quick is pre-selected, a saved choice wins, an unknown one is ignored, and the choice is saved only at Start", function()
    local e, g = newSetup()
    g.open("setup")
    local fresh = g.state().mode == "quick"
    e.ns.ui.state().mode = "thorough"
    g.open("setup")
    local saved = g.state().mode == "thorough"
    e.ns.ui.state().mode = "bogus"
    g.open("setup")
    local unknown = g.state().mode == "quick"
    e.ns.ui.state().mode = "quick"
    g.open("setup")
    g.click("mode:thorough")
    local chosen = g.state().mode == "thorough" and e.ns.ui.state().mode == "quick"
    g.setMode("bogus")
    g.click("mode:")
    return fresh and saved and unknown and chosen and g.state().mode == "thorough", tostring(g.state().mode)
end)

test("G8-3 Start runs the quick test or the full sweep as chosen, saves the choice, and the entry records its mode", function()
    local function runWith(mode)
        local e, g, b = newSetup()
        local calls, entries = {}, {}
        local real = b.run
        b.run = function(cb, opts) calls[#calls + 1] = opts return real(cb, opts) end
        e.ns.results = { show = function(entry) entries[#entries + 1] = entry end }
        g.open("setup")
        g.click("mode:" .. mode)
        g.click("target:165")
        g.setTicked(true)
        g.click("start")
        local savedAtStart = e.ns.ui.state().mode
        e.pump(120, runCost)
        return calls[1], entries[1], savedAtStart
    end
    local quickOpts, quickEntry, quickSaved = runWith("quick")
    local fullOpts, fullEntry, fullSaved = runWith("thorough")
    return quickOpts and quickOpts.levels == "quick" and quickOpts.kind == "setup" and quickSaved == "quick"
        and quickEntry and quickEntry.mode == "quick" and quickEntry.kind == "setup"
        and fullOpts and fullOpts.levels == "all" and fullOpts.kind == "setup" and fullSaved == "thorough"
        and fullEntry and fullEntry.mode == "all", tostring(quickOpts and quickOpts.levels) .. " " .. tostring(fullOpts and fullOpts.levels)
end)

test("G8-4 the two mode buttons are drawn only in the setup Intro, the selected one is highlighted, and choosing one redraws the minutes", function()
    local e, g, b = newSetup()
    b.estimateSetupWindows = function(mode) return mode == "quick" and 24 or 38 end
    b.K.SETTLE, b.K.MEASURE = 3.0, 8.0
    g.open("setup")
    local f = guideFrame()
    local quick, thorough = findButton(f, "Quick (about 5 minutes)"), findButton(f, "Thorough (about 7 minutes)")
    local first = quick.locked == true and thorough.locked ~= true
    thorough:Click()
    local second = g.state().mode == "thorough" and findButton(f, "Thorough (about 7 minutes)").locked == true
        and findButton(f, "Quick (about 5 minutes)").locked ~= true and hasText(f, "This takes about 7 minutes,")
    g.open("run")
    local hiddenInRun = findButton(f, "Quick (about 5 minutes)") == nil and findButton(f, "Thorough (about 7 minutes)") == nil
    g.open("setup")
    g.click("target:165")
    g.setTicked(true)
    g.click("start")
    local hiddenWhileRunning = g.state().view == "running" and findButton(f, "Quick (about 5 minutes)") == nil
        and findButton(f, "Thorough (about 7 minutes)") == nil
    return first and second and hiddenInRun and hiddenWhileRunning, shownText(f)
end)

-- Crowd test, Task 7: the crowd kind of the guided window (spec section 3)
local function crow(cvar, label, value, delta, current)
    return { setting = label, cvar = cvar, value = value, meanMs = 7.0 + delta, deltaMs = delta, flags = {}, current = current or nil }
end
-- A finished quiet-spot entry for the fixture client: each setting's lowest level and its current level.
local function quietFor()
    return { valid = true, baselineMs = 7.0, kind = "setup", mode = "quick",
        starts = { RenderScale = "1", graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64" },
        rows = {
            crow("RenderScale", "Render scale", "0.5", -2.0), crow("RenderScale", "Render scale", "1", 0, true),
            crow("graphicsShadowQuality", "Shadows", "0", -1.0), crow("graphicsShadowQuality", "Shadows", "2", 0, true),
            crow("graphicsSSAO", "SSAO", "0", -0.1), crow("graphicsSSAO", "SSAO", "1", 0, true),
            crow("groundEffectDensity", "Ground effect density", "48", -0.1), crow("groundEffectDensity", "Ground effect density", "64", 0, true),
        } }
end
local function newCrowd(withQuiet)
    local e, g, b = newSetup()
    if withQuiet ~= false then b.state().history[#b.state().history + 1] = quietFor() end
    return e, g, b
end
local function startCrowd(g, target)
    g.open("crowd")
    if target then g.click("target:" .. tostring(target)) end
    g.setTicked(true)
    g.click("start")
end
local MISSING = "The crowd test builds on the quiet-spot test. Run Find my best settings in a quiet spot first, then come back here."

test("G9-1 with no finished quiet-spot test the crowd window says so and offers only Close; nothing is written or started", function()
    local e, g, b = newCrowd(false)
    local h = b.state().history
    h[#h + 1] = { label = "mark", valid = true, rows = { { setting = "mark", value = "current", meanMs = 7 } } }
    local crowdEntry = quietFor()
    crowdEntry.kind = "crowd"
    h[#h + 1] = crowdEntry
    h[#h + 1] = { kind = "setup", valid = true, rows = {}, baselineMs = 7.0 }
    local bad = quietFor()
    bad.valid = false
    h[#h + 1] = bad
    g.open("crowd")
    local view = g.model(g.state(), { windows = 9 })
    local f = guideFrame()
    g.click("start")
    return g.state().view == "intro" and g.state().missing == true and view.title == "Find your crowded settings"
        and #view.lines == 1 and view.lines[1] == MISSING and #view.buttons == 1 and view.buttons[1].key == "close"
        and view.checkbox == nil and view.targets == nil and hasText(f, MISSING) and findButton(f, "Close") ~= nil
        and findButton(f, "Start") == nil and not b.active() and #SETLOG == 0 and b.watch == nil, shownText(f)
end)

test("G9-2 the crowd Intro has its title, first line, target prompt and rules, and Start waits for the tick", function()
    local _, g = boot()
    local state = { view = "intro", kind = "crowd", ticked = false, target = 60 }
    local first = "This takes about 2 minutes. Stand somewhere busy, such as a city's main square, and leave the camera on a busy view. "
        .. "The game will change your graphics settings briefly to measure each one, then put everything back exactly as it was."
    local small = g.model(state, { windows = 7 })
    local large = g.model(state, { windows = 17 })
    local function startEnabled(ticked, target)
        local view = g.model({ view = "intro", kind = "crowd", ticked = ticked, target = target }, { windows = 7 })
        for _, button in ipairs(view.buttons) do
            if button.key == "start" then return button.enabled end
        end
    end
    local text = table.concat(small.lines, "\n")
    local e2, g2, b2 = newCrowd()
    b2.K.SETTLE, b2.K.MEASURE = 3.0, 8.0
    g2.open("crowd")
    local f = guideFrame()
    return small.title == "Find your crowded settings" and small.lines[1] == first
        and large.lines[1]:find("This takes about 4 minutes. Stand somewhere busy", 1, true) == 1
        and small.targets.prompt == "How smooth do you want it in crowds? Pick the frame rate you're aiming for."
        and table.concat(small.targets.list, ",") == "60,90,120,144,165,240" and small.targets.selected == 60
        and text:find("Before you start:", 1, true) ~= nil and text:find("While it runs, please don't:", 1, true) ~= nil
        and text:find("somewhere quiet", 1, true) == nil and text:find("Stand still somewhere busy", 1, true) ~= nil
        and startEnabled(false, 60) == false and startEnabled(true, nil) == false and startEnabled(true, 60) == true
        and hasText(f, "This takes about 2 minutes. Stand somewhere busy"), shownText(f)
end)

test("G9-3 the crowd target is 60 by default, a saved crowd target wins, an unlisted one is ignored, and nothing is saved until Start", function()
    local e, g = newCrowd()
    g.open("crowd")
    local default = g.state().target == 60
    e.ns.ui.state().crowdTarget = 90
    g.open("crowd")
    local saved = g.state().target == 90
    e.ns.ui.state().crowdTarget = 100
    g.open("crowd")
    local unlisted = g.state().target == 60
    e.ns.ui.state().crowdTarget = nil
    g.open("crowd")
    g.click("target:120")
    local chosen = g.state().target == 120 and e.ns.ui.state().crowdTarget == nil
    g.click("target:100")
    return default and saved and unlisted and chosen and g.state().target == 120 and e.ns.ui.state().target == nil, tostring(g.state().target)
end)

test("G9-4 Start measures the crowd with the quiet-spot entry, saves the crowd target, sets the watch and learns nothing", function()
    local e, g, b = newCrowd()
    local calls, learned = {}, 0
    local realCrowd, realLearn = b.crowd, b.learn
    b.crowd = function(quiet, cb) calls[#calls + 1] = quiet return realCrowd(quiet, cb) end
    b.learn = function() learned = learned + 1 return realLearn() end
    startCrowd(g, 144)
    local ok = #calls == 1 and calls[1].kind == "setup" and g.state().view == "running" and g.state().started == true
        and b.active() == true and b.watch == g.panelReason and learned == 0 and e.ns.ui.state().crowdTarget == 144
        and e.ns.ui.state().target == nil
    e.pump(120, runCost)
    local e2, g2, b2 = newCrowd()
    setFrames({ SettingsPanel = true })
    startCrowd(g2, 144)
    setFrames({})
    return ok and g2.state().view == "stopped" and g2.state().reason == "panel:settings" and not b2.active()
        and #SETLOG == 0 and e2.ns.ui.state().crowdTarget == nil, tostring(#calls) .. " " .. tostring(g.state().view)
end)

test("G9-5 a valid crowd run closes the guided window and hands the crowd recommendation and the target to the results window", function()
    local e, g, b = newCrowd()
    local calls, shown = {}, {}
    e.ns.results = { show = function(entry, target) calls[#calls + 1] = { entry, target } end }
    e.ns.ui.showReport = function(entry) shown[#shown + 1] = entry end
    startCrowd(g, 90)
    e.pump(120, runCost)
    local f = guideFrame()
    local entry = calls[1] and calls[1][1]
    return #calls == 1 and entry and entry.kind == "crowd" and entry.valid == true and #entry.rows > 0
        and math.abs(entry.baselineMs - 7.0) < 0.1 and calls[1][2] == 90 and f ~= nil and not f:IsShown()
        and g.state().view == "done" and g.state().kind == "crowd" and #shown == 0 and not b.active(), outText()
end)

test("G9-6 an invalid crowd run shows Stopped, never the results, and puts every setting back", function()
    local e, g, b = newCrowd()
    local calls = 0
    e.ns.results = { show = function() calls = calls + 1 end }
    b.K.POLL = 0.05
    local before = copyTable(CVARS)
    startCrowd(g, 60)
    e.pump(120, function(cv)
        local p = b.progress()
        if p and p.done >= 3 then SPEED = 7 end
        return runCost(cv)
    end)
    local f = guideFrame()
    local same_ = true
    for k, v in pairs(before) do if CVARS[k] ~= v then same_ = false end end
    local h = b.history()
    return g.state().view == "stopped" and g.state().reason == "movement" and calls == 0 and same_ and f:IsShown()
        and hasText(f, "You moved, so the test stopped.") and not b.active() and h[#h].kind == "crowd" and h[#h].valid == false,
        shownText(f)
end)

test("G9-7 while a crowd run this window started is going, its report is left to the window", function()
    local e, g = newCrowd()
    local idle = g.handlesReport()
    startCrowd(g, 60)
    local during = g.handlesReport()
    e.pump(120, runCost)
    return idle == false and during == true, tostring(during)
end)

test("G9-8 the target buttons and their prompt are drawn in the crowd Intro, with the crowd's words, and nowhere else", function()
    local e, g = newCrowd()
    g.open("crowd")
    local f = guideFrame()
    local found = true
    for _, label in ipairs({ "60", "90", "120", "144", "165", "240" }) do
        if not findButton(f, label) then found = false end
    end
    local crowdWords = hasText(f, "How smooth do you want it in crowds?") and findButton(f, "60").locked == true
    g.open("run")
    local gone = findButton(f, "60") == nil and not hasText(f, "How smooth do you want it in crowds?")
    g.open("setup")
    local setupWords = findButton(f, "60") ~= nil and hasText(f, "How smooth do you want it?")
        and not hasText(f, "in crowds?")
    return found and crowdWords and gone and setupWords, shownText(f)
end)

test("G9-10 if the quiet-spot result is gone by the time Start is pressed, nothing starts and nothing is saved", function()
    local e, g, b = newCrowd()
    g.open("crowd")
    g.click("target:144")
    g.setTicked(true)
    local h = b.state().history
    for i = #h, 1, -1 do h[i] = nil end
    local calls = 0
    local real = b.crowd
    b.crowd = function(quiet, cb) calls = calls + 1 return real(quiet, cb) end
    g.click("start")
    return g.state().view == "stopped" and g.state().reason == "no quiet result" and calls == 0 and not b.active()
        and b.watch == nil and e.ns.ui.state().crowdTarget == nil and #SETLOG == 0, tostring(g.state().reason)
end)

test("G9-9 a crowd that never calms hands over an entry whose answer is no data, never a wrong recommendation", function()
    local e, g, b = newCrowd()
    b.K.MIN_FRAMES = 2
    local calls = {}
    e.ns.results = { show = function(entry, target) calls[#calls + 1] = { entry, target } end }
    local before = copyTable(CVARS)
    startCrowd(g, 60)
    e.pump(240, function(cv)
        local p = b.progress()
        return runCost(cv) * (1.3 ^ math.min(p and p.done or 0, 5))
    end)
    local entry = calls[1] and calls[1][1]
    local result = entry and e.ns.recommend.choose(entry, 60)
    local same_ = true
    for k, v in pairs(before) do if CVARS[k] ~= v then same_ = false end end
    return #calls == 1 and result and result.status == "nodata" and #result.changes == 0 and same_ and not b.active(),
        tostring(result and result.status) .. " " .. outText()
end)

-- Crowd test, Task 8: the check of the recommendation before the results are shown (spec section 4.3)
-- Pumps the game in small steps until the window reaches its "Checking the result..." step (or the run ends without one).
local function pumpUntilChecking(e, g, costFn)
    for _ = 1, 3000 do
        e.pump(0.05, costFn or runCost)
        if g.state().checking then return true end
        if g.state().view ~= "running" then return false end
    end
    return false
end
-- A setup run for target 165 that needs changes, with spies on bench.verify and results.show.
local function newChecked()
    local e, g, b = newSetup()
    local watch = { verify = {}, shown = {}, runs = 0 }
    local realVerify, realRun = b.verify, b.run
    b.verify = function(values, cb)
        watch.verify[#watch.verify + 1] = copyTable(values)
        if watch.before then watch.before(values) end
        return realVerify(values, cb)
    end
    b.run = function(cb, opts) watch.runs = watch.runs + 1 return realRun(cb, opts) end
    e.ns.results = { show = function(entry, target, verify) watch.shown[#watch.shown + 1] = { entry, target, verify } end }
    return e, g, b, watch
end
local function changesOf(e, entry, target)
    local want = {}
    for _, c in ipairs(e.ns.recommend.choose(entry, target).changes) do want[c.cvar] = c.to end
    return want
end

test("G10-1 a recommendation is checked before the results appear: the window says so, then the results get the measurement", function()
    local e, g, b, watch = newChecked()
    startSetup(g, 165)
    local sawChecking = pumpUntilChecking(e, g)
    local f = guideFrame()
    local during = sawChecking and #watch.shown == 0 and g.state().view == "running" and hasText(f, "Checking the result...")
        and hasText(f, "PLEASE DON'T MOVE") and findButton(f, "Stop") ~= nil and b.watch == g.panelReason and b.active()
        and g.handlesReport() == true
    e.pump(10, runCost)
    local entry = watch.shown[1] and watch.shown[1][1]
    local want = entry and changesOf(e, entry, 165) or {}
    local v = watch.shown[1] and watch.shown[1][3]
    return during and #watch.verify == 1 and sameTable(watch.verify[1], want) and next(want) ~= nil and #watch.shown == 1
        and watch.shown[1][2] == 165 and v and v.ok == true and v.appliedMs > 0 and v.baselineMs > 0 and b.watch == nil
        and not b.active() and g.state().view == "done", tostring(sawChecking) .. " " .. shownText(f)
end)

test("G10-2 a result with nothing to apply, or no way to reach the target, is shown at once, with no check", function()
    local function outcome(target)
        local e, g, b, watch = newChecked()
        startSetup(g, target)
        e.pump(120, runCost)
        return #watch.verify, #watch.shown, watch.shown[1] and watch.shown[1][3], e.ns.recommend.choose(watch.shown[1][1], target).status
    end
    local v60, s60, check60, status60 = outcome(60)
    local v240, s240, check240, status240 = outcome(240)
    return status60 == "nochange" and v60 == 0 and s60 == 1 and check60 == nil
        and status240 == "unreachable" and v240 == 0 and s240 == 1 and check240 == nil, status60 .. " " .. status240
end)

test("G10-3 a check that fails still shows the results, with no check and nothing applied, and every setting is back", function()
    local function failing(setup)
        local e, g, b, watch = newChecked()
        local before = copyTable(CVARS)
        local everyday = copyTable(e.ns.db().profiles.everyday.values)
        b.K.POLL = 0.05
        setup(e, b, watch)
        startSetup(g, 165)
        e.pump(120, function(cv)
            local p = b.progress()
            if p and p.phase == "check" and watch.moves then SPEED = 7 end
            return runCost(cv)
        end)
        COMBAT = false
        local same_ = true
        for k, v in pairs(before) do if CVARS[k] ~= v then same_ = false end end
        local shown = watch.shown[1]
        return #watch.shown == 1 and shown[3] == nil and same_ and sameTable(e.ns.db().profiles.everyday.values, everyday)
            and g.state().view == "done" and not b.active() and e.ns.suspended == false and b.state().pending == nil
            and #watch.verify == 1
    end
    local moved = failing(function(e, b, watch) watch.moves = true end)
    local rejected = failing(function(e, b, watch)
        watch.before = function(values) for cvar in pairs(values) do SETFAIL[cvar] = "clamp" end end
    end)
    local combat = failing(function(e, b, watch) watch.before = function() COMBAT = true end end)
    return moved and rejected and combat, tostring(moved) .. " " .. tostring(rejected) .. " " .. tostring(combat)
end)

test("G10-4 Stop while checking ends the check, puts everything back and shows the results without it", function()
    local e, g, b, watch = newChecked()
    local before = copyTable(CVARS)
    startSetup(g, 165)
    local checking = pumpUntilChecking(e, g)
    g.click("stop")
    e.pump(5, runCost)
    local same_ = true
    for k, v in pairs(before) do if CVARS[k] ~= v then same_ = false end end
    return checking and #watch.shown == 1 and watch.shown[1][3] == nil and same_ and not b.active() and b.watch == nil
        and e.ns.suspended == false, tostring(checking)
end)

test("G10-5 the forbidden-window rule applies while checking: opening one stops the check and the results still show", function()
    local e, g, b, watch = newChecked()
    startSetup(g, 165)
    local checking = pumpUntilChecking(e, g)
    local watching = b.watch == g.panelReason
    setFrames({ SettingsPanel = true })
    e.pump(5, runCost)
    setFrames({})
    return checking and watching and #watch.shown == 1 and watch.shown[1][3] == nil and b.watch == nil and not b.active(),
        tostring(checking) .. " " .. tostring(#watch.shown)
end)

test("G10-6 a crowd result is checked too, with its own changed values", function()
    local e, g, b = newCrowd()
    local verifyCalls, shown = {}, {}
    local realVerify = b.verify
    b.verify = function(values, cb) verifyCalls[#verifyCalls + 1] = copyTable(values) return realVerify(values, cb) end
    e.ns.results = { show = function(entry, target, verify) shown[#shown + 1] = { entry, target, verify } end }
    startCrowd(g, 165)
    local checking = pumpUntilChecking(e, g)
    e.pump(10, runCost)
    local entry = shown[1] and shown[1][1]
    local want = entry and changesOf(e, entry, 165) or {}
    local v = shown[1] and shown[1][3]
    return checking and entry and entry.kind == "crowd" and #verifyCalls == 1 and sameTable(verifyCalls[1], want) and next(want) ~= nil
        and #shown == 1 and v and v.ok == true and not b.active(), tostring(checking) .. " " .. tostring(next(want))
end)

test("G10-7 starting another test or opening another window while checking keeps the one check going", function()
    local e, g, b, watch = newChecked()
    startSetup(g, 165)
    local checking = pumpUntilChecking(e, g)
    g.open("run")
    g.open("setup")
    g.open("crowd")
    b.handle("")
    local kept = g.state().view == "running" and g.state().checking == true and g.state().kind == "setup" and b.active()
    e.pump(10, runCost)
    return checking and kept and watch.runs == 1 and #watch.verify == 1 and #watch.shown == 1, tostring(watch.runs)
end)

test("G10-8 a successful check is recorded on the run's history entry; a failed check or a result with nothing to check records none", function()
    local e, g, b, watch = newChecked()
    startSetup(g, 165)
    e.pump(120, runCost)
    local entry = watch.shown[1][1]
    local v = watch.shown[1][3]
    local choice = e.ns.recommend.choose(entry, 165)
    local recorded = entry.verify and entry.verify.predictedMs == choice.afterMs
        and math.abs(entry.verify.measuredMs - choice.nowMs * v.appliedMs / v.baselineMs) < 1e-9
    local e2, g2, b2, w2 = newChecked()
    w2.before = function() COMBAT = true end
    startSetup(g2, 165)
    e2.pump(120, runCost)
    COMBAT = false
    local failed = w2.shown[1][1].verify == nil
    local e3, g3, b3, w3 = newChecked()
    startSetup(g3, 60)
    e3.pump(120, runCost)
    return recorded and failed and w3.shown[1][1].verify == nil, tostring(entry.verify and entry.verify.measuredMs)
end)

test("G10-9 if the results cannot be prepared the window shows the Finished view with a way to close it, never a dead Running view", function()
    local function broken(patch, run)
        local e, g, b
        if run == "crowd" then e, g, b = newCrowd() else e, g, b = newSetup() end
        local shown = 0
        e.ns.results = { show = function() shown = shown + 1 end }
        patch(e.ns.recommend)
        if run == "crowd" then startCrowd(g, 165) else startSetup(g, 165) end
        e.pump(120, runCost)
        local f = guideFrame()
        return g.state().view == "done" and g.state().checking == nil and shown == 0 and not b.active() and b.watch == nil
            and f:IsShown() and findButton(f, "Close") ~= nil and findButton(f, "Show report") ~= nil and findButton(f, "Stop") == nil
            and outText():find("could not be prepared", 1, true) ~= nil
    end
    local crowd = broken(function(r) r.crowdEntry = function() error("boom") end end, "crowd")
    local setup = broken(function(r) r.choose = function() error("boom") end end, "setup")
    return crowd and setup, tostring(crowd) .. " " .. tostring(setup)
end)

test("G8-5 Try again after a refused setup start keeps the chosen mode", function()
    local e, g = newSetup()
    g.open("setup")
    g.click("mode:thorough")
    g.click("target:144")
    g.setTicked(true)
    setFrames({ SettingsPanel = true })
    g.click("start")
    setFrames({})
    local stopped = g.state().view == "stopped"
    g.click("again")
    return stopped and g.state().view == "intro" and g.state().mode == "thorough" and g.state().target == 144
        and e.ns.ui.state().mode == nil, tostring(g.state().mode)
end)

-- Words and menu, Task 5: the progress lines say what is happening in plain words (spec section 3.1)
local RAW_WORDS = { "groundEffectDensity", "graphicsShadowQuality", "graphicsSSAO", "RenderScale", "Ground clutter (raw)",
    "Render scale", "Compute effects", "level 0.", "level 1," }
local function rawIn(text)
    for _, word in ipairs(RAW_WORDS) do
        if text:find(word, 1, true) then return word end
    end
end
-- Pumps the game in small steps and gathers what the guided window shows while its Running view is on.
local function watchRunning(e, g, startFn)
    local seen = {}
    startFn()
    for _ = 1, 2500 do
        e.pump(0.05, runCost)
        local f = guideFrame()
        if g.state().view == "running" and f and f:IsShown() then seen[#seen + 1] = shownText(f) end
        if g.state().view ~= "running" then break end
    end
    return seen
end

test("G11-1 the Running view says what a window is about, in plain words, for each kind of window", function()
    local _, g = boot()
    local function line(p)
        local v = g.model({ view = "running", kind = "setup" }, { progress = p })
        return v.progress[2], v.progress[3]
    end
    local sweep = line({ phase = "sweep", label = "Ground clutter (raw) 48", cvar = "groundEffectDensity", value = "48", done = 3, total = 27 })
    local percent = line({ phase = "sweep", label = "Render scale 0.5", cvar = "RenderScale", value = "0.5", done = 4, total = 27 })
    local start = line({ phase = "baseline", label = "start", done = 0, total = 27 })
    local after, step = line({ phase = "baseline", label = "after Shadows", cvar = "graphicsShadowQuality", done = 5, total = 27 })
    local control = line({ phase = "control", label = "Render scale", cvar = "RenderScale", done = 1, total = 27 })
    return sweep == "Now testing: Grass and plants (exact amount), level 48" and percent == "Now testing: Picture sharpness, level 50%"
        and start == "Getting a steady starting speed" and after == "Checking the speed again after Shadow detail"
        and control == "Checking that the test works here"
        and step == "It runs on its own, so feel free to step away from the keyboard.", tostring(sweep) .. " / " .. tostring(after)
end)

test("G11-2 a real setup run shows plain sentences and no raw setting name or raw level while it runs", function()
    local e, g, b = newSetup()
    b.K.SETTLE, b.K.MEASURE = 0.3, 0.6      -- windows longer than the window's half-second redraw, so every sentence is on screen
    e.ns.results = { show = function() end }
    local seen = watchRunning(e, g, function() startSetup(g, 165) end)
    local joined = table.concat(seen, "\n")
    local bad
    for _, text in ipairs(seen) do bad = bad or rawIn(text) end
    local missing = {}
    for _, phrase in ipairs({ "Now testing: ", "Getting a steady starting speed", "Checking the speed again after ",
        "Checking that the test works here", "Picture sharpness, level 50%" }) do
        if not joined:find(phrase, 1, true) then missing[#missing + 1] = phrase end
    end
    return #seen > 10 and bad == nil and #missing == 0, tostring(bad) .. " " .. tostring(#seen) .. " missing: " .. table.concat(missing, "; ")
end)

test("G11-3 a real crowd run shows the same plain sentences", function()
    local e, g, b = newCrowd()
    b.K.SETTLE, b.K.MEASURE = 0.3, 0.6
    e.ns.results = { show = function() end }
    local seen = watchRunning(e, g, function() startCrowd(g, 60) end)
    local joined = table.concat(seen, "\n")
    local bad
    for _, text in ipairs(seen) do bad = bad or rawIn(text) end
    return #seen > 5 and bad == nil and joined:find("Now testing: ", 1, true) ~= nil
        and joined:find("Getting a steady starting speed", 1, true) ~= nil
        and joined:find("Checking the speed again after ", 1, true) ~= nil
        and joined:find("Picture sharpness, level 50%", 1, true) ~= nil, tostring(bad) .. " " .. tostring(#seen)
end)

-- A quiet guided test (results window, Task 1): spec 2026-10-30-results-window-design.md section 3.1
test("QT-10 the guided window starts the quiet-spot test, the crowd test and the check of a recommendation silent, and the Advanced items not", function()
    local e, g, b = newSetup()
    local seen = {}
    local realRun, realVerify = b.run, b.verify
    b.run = function(cb, opts) seen.setup = opts or false return realRun(cb, opts) end
    b.verify = function(values, cb, opts) seen.verify = opts or false return realVerify(values, cb, opts) end
    e.ns.results = { show = function() end }
    startSetup(g, 165)
    e.pump(400, runCost)
    local e2, g2, b2 = newCrowd()
    local realCrowd = b2.crowd
    b2.crowd = function(quiet, cb, opts) seen.crowd = opts or false return realCrowd(quiet, cb, opts) end
    startCrowd(g2, 90)
    local e3, g3, b3 = newSetup()
    local realRun3, realCheck3 = b3.run, b3.check
    b3.run = function(cb, opts) seen.run = opts or false return realRun3(cb, opts) end
    b3.check = function(cb, opts) seen.check = opts or false return realCheck3(cb) end
    startVia(g3, "run")
    local e4, g4, b4 = newSetup()
    b4.check = function(cb, opts) seen.check = opts or false return false end
    startVia(g4, "check")
    return seen.setup and seen.setup.silent == true and seen.setup.kind == "setup" and seen.crowd and seen.crowd.silent == true
        and seen.verify and seen.verify.silent == true and (seen.run == false or (seen.run and seen.run.silent ~= true))
        and (seen.check == false or (seen.check and seen.check.silent ~= true)), tostring(seen.setup) .. " " .. tostring(seen.crowd)
            .. " " .. tostring(seen.verify) .. " " .. tostring(seen.run) .. " " .. tostring(seen.check)
end)

test("QT-11 a whole guided quiet-spot test, check included, leaves chat empty of the removed lines and opens the results", function()
    local e, g, b, watch = newChecked()
    startSetup(g, 165)
    e.pump(400, runCost)
    local text = outText()
    local gone = true
    for _, sub in ipairs({ "environment:", "close browsers", "Benchmark at", "run stopped", "cannot run", "(graphicsShadowQuality)" }) do
        gone = gone and text:find(sub, 1, true) == nil
    end
    return #watch.shown == 1 and #watch.verify == 1 and gone, text
end)

test("QT-12 a guided test that is refused prints no 'cannot run' line, and the window shows the reason in plain words", function()
    local e, g = newSetup()
    COMBAT = true
    startSetup(g, 165)
    local f = guideFrame()
    return g.state().view == "stopped" and not outText():find("cannot run", 1, true) and hasText(f, "You are in combat."), outText()
end)

return H.results()
