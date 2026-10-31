-- Guide.lua: the guided benchmark window (spec 2026-10-29-guided-benchmark-window-design.md). Loaded after UI.lua.
-- A pure part (the words for each stop reason, flag and view) and, later in this file, a thin frame adapter, in the
-- same shape as the minimap menu.
local _, ns = ...

local guide = {}
ns.guide = guide

-- reason -> {headline, advice}: spec section 4. The reasons are the strings Bench.lua emits.
local TEXT = {
    ["a run is already active"] = { "A test is already running.", "Wait for it to finish, or press Stop." },
    ["you are in combat"] = { "You are in combat.", "Leave combat, then try again." },
    ["combat"] = { "You entered combat, so the test stopped.", "Leave combat, then try again." },
    ["you are moving or falling: stand still"] = { "You are moving.", "Stand still the whole time, then try again." },
    ["movement"] = { "You moved, so the test stopped.", "Stand still the whole time, then try again." },
    ["zoning"] = { "The game changed zone or reloaded, so the test stopped.", "Stay where you are and do not reload, then try again." },
    ["stall"] = { "The game froze for a moment, so the test stopped.", "Close other programs and try again." },
    ["few"] = { "The game ran too slowly to measure.", "Close other programs and try again." },
    ["no frames"] = { "The game stopped drawing frames, so the test stopped.", "Keep the game window in front, then try again." },
    ["stopped"] = { "You stopped the test.", "You can start again any time." },
    ["control did not respond"] = { "The test could not tell the settings apart here.",
        "This usually means the game window was not in front (alt-tab), or the frame rate is capped. Try again without switching windows." },
    ["control rejected"] = { "The game would not accept a settings change.", "Close the graphics settings and try again." },
    ["window busy"] = { "Another measurement was already running.", "Wait a moment and try again." },
    ["no snapshot"] = { "The addon could not take a copy of your settings, so it did not start.", "Nothing was changed. Tell the person who gave you this addon." },
    ["no control"] = { "This game has no setting the test can use to check itself.", "Tell the person who gave you this addon." },
    ["nothing to measure"] = { "There is nothing to measure yet.", "Some settings still need to be learned first: type /fset bench list to see which." },
    ["no quiet result"] = { "The crowd test needs a finished quiet-spot test first.", "Run Find my best settings in a quiet spot, then try again." },
}

-- What each forbidden window is called in a sentence.
local PANEL = { ["panel:settings"] = "the game's settings", ["panel:menu"] = "the game menu", ["panel:map"] = "the map" }

-- The words for a stop reason: headline, advice. A reason with the prefix `baseline ` is its inner reason said at the
-- start; an unknown reason still gets words and shows the raw reason.
function guide.explain(reason)
    reason = tostring(reason)
    local row = TEXT[reason]
    if row then return row[1], row[2] end
    local inner = reason:match("^baseline (.+)$")
    if inner then
        local headline, advice = guide.explain(inner)
        return "The test stopped at the start: " .. headline, advice
    end
    local detail = reason:match("^environment check failed: (.+)$")
    if detail then
        return "The game is missing something this test needs.", "Tell the person who gave you this addon: " .. detail .. "."
    end
    detail = reason:match("^error: (.*)$")
    if detail then
        return "Something went wrong inside the addon.", "Your settings were put back. Tell the person who gave you this addon: " .. detail .. "."
    end
    local what = PANEL[reason]
    if what then
        return "You opened " .. what .. ", so the test stopped.", "Leave it closed while the test runs, then try again."
    end
    return "The test stopped (reason: " .. reason .. ").", "Your settings were put back. Try again."
end

-- Seconds one measurement window takes: the settle period then the measured period.
local function windowSeconds()
    local K = ns.bench and ns.bench.K
    return (K and K.SETTLE or 3.0) + (K and K.MEASURE or 8.0)
end

-- Whole minutes for the intro text: the windows' seconds rounded up, never below one.
function guide.introMinutes(windows)
    local minutes = math.ceil((windows or 0) * windowSeconds() / 60)
    if minutes < 1 then minutes = 1 end
    return minutes
end

-- "less than a minute to go" under 60 seconds, else "roughly N minutes to go" ("roughly 1 minute to go" for exactly one).
function guide.timeLeft(done, total)
    local seconds = ((total or 0) - (done or 0)) * windowSeconds()
    if seconds < 60 then return "less than a minute to go" end
    local minutes = math.ceil(seconds / 60)
    return "roughly " .. minutes .. " minute" .. (minutes == 1 and "" or "s") .. " to go"
end

-- What the saved state says about putting the settings back: {pending = a restore is still due, issues = the
-- differences a restore could not fix}. Always read, never assumed.
function guide.restoreInfo()
    local st = ns.bench and ns.bench.state()
    local issues = {}
    if st and st.lastRestoreIssues then
        for _, issue in ipairs(st.lastRestoreIssues) do issues[#issues + 1] = issue end
    end
    return { pending = st ~= nil and st.pending ~= nil, issues = issues }
end

-- The sentence about the player's settings after a stop or a finish (spec section 6).
function guide.restoreLine(info)
    if info.issues and #info.issues > 0 then
        local names = {}
        for _, issue in ipairs(info.issues) do names[#names + 1] = issue:match("^([^:]+):") or issue end
        return "These settings could not be put back: " .. table.concat(names, ", ") .. ". Check them in the game's graphics menu."
    end
    if info.pending then return "Your settings will be put back when combat ends, or at your next login." end
    return "Your graphics settings have been put back as they were."
end

-- The model of the four views (spec section 3): what the window says and which buttons work, with no frames.
-- state = {view = "intro" | "running" | "stopped" | "done", kind = "run" | "check", ticked, reason, problems, entry,
-- result}; ctx = {progress = {phase, label, done, total} | nil, windows, restore = {pending, issues}}.
local RULES = {
    "", "Before you start:", "- Stand still somewhere quiet, not a busy city.",
    "- Pick a view with some trees, water or buildings in it, and leave the camera there.",
    "- Close browsers, video, recording and streaming programs.", "- Make sure you are not in combat.",
    "", "While it runs, please don't:", "- Move, jump or turn the camera.", "- Open the game menu, the settings or the map.",
    "- Switch to another window (alt-tab).", "- Change any graphics setting.", "- Log out or reload.",
}
local BOX_TEXT = "I have closed other programs and will stay still, camera included, until it finishes"
-- The crowd test is run in a busy place: the first two rules say that instead of "somewhere quiet".
local CROWD_RULES = {}
for i, line in ipairs(RULES) do CROWD_RULES[i] = line end
CROWD_RULES[3] = "- Stand still somewhere busy, such as a city's main square."
CROWD_RULES[4] = "- Pick a busy view, with plenty of people and buildings in it, and leave the camera there."
local MISSING_QUIET = "The crowd test builds on the quiet-spot test. Run Find my best settings in a quiet spot first, then come back here."

function guide.model(state, ctx)
    ctx = ctx or {}
    local restore = ctx.restore or { pending = false, issues = {} }
    local check = state.kind == "check"
    local setup = state.kind == "setup"
    local crowd = state.kind == "crowd"
    local view = { title = "", lines = {}, buttons = {}, escapeCloses = true }
    local function add(line) view.lines[#view.lines + 1] = line end
    local function button(key, text, enabled)
        view.buttons[#view.buttons + 1] = { key = key, text = text, enabled = enabled and true or false }
    end

    if state.view == "intro" then
        view.title = crowd and "Find your crowded settings"
            or (setup and "Find your best settings" or (check and "Check this spot" or "Test your graphics settings"))
        if crowd and state.missing then
            -- No finished quiet-spot test to build on: say so, and offer only Close.
            view.missing = true
            add(MISSING_QUIET)
            button("close", "Close", true)
            return view
        end
        if check then
            add("This takes about a minute. It checks that this is a good place to run the full test.")
        else
            local minutes = guide.introMinutes(ctx.windows)
            local howLong = "This takes about " .. minutes .. " minute" .. (minutes == 1 and "" or "s")
            if crowd then
                add(howLong .. ". Stand somewhere busy, such as a city's main square, and leave the camera on a busy view. "
                    .. "The game will change your graphics settings briefly to measure each one, then put everything back exactly as it was.")
            elseif setup then
                add(howLong .. ", so it's a good time to grab a drink. The game will change your graphics settings many times "
                    .. "to measure each one, then put everything back exactly as it was.")
            else
                add(howLong .. ". The game will change your graphics settings many times to measure each one, then put everything back.")
            end
        end
        for _, line in ipairs(crowd and CROWD_RULES or RULES) do add(line) end
        if crowd then
            view.targets = {
                prompt = "How smooth do you want it in crowds? Pick the frame rate you're aiming for.",
                list = ns.recommend and ns.recommend.TARGETS or {},
                selected = state.target,
            }
        end
        if setup then
            view.targets = {
                prompt = "How smooth do you want it? Pick your monitor's refresh rate, or the frame rate you're aiming for.",
                list = ns.recommend and ns.recommend.TARGETS or {},
                selected = state.target,
            }
            -- Quick (the lowest and a middle level of each setting) or Thorough (every level), each with its own minutes.
            local by = ctx.windowsByMode or {}
            local function label(name, windows)
                local minutes = guide.introMinutes(windows)
                return name .. " (about " .. minutes .. " minute" .. (minutes == 1 and "" or "s") .. ")"
            end
            view.modes = {
                selected = state.mode == "thorough" and "thorough" or "quick",
                list = {
                    { key = "quick", text = label("Quick", by.quick or ctx.windows) },
                    { key = "thorough", text = label("Thorough", by.thorough or ctx.windows) },
                },
            }
        end
        view.checkbox = { text = BOX_TEXT, checked = state.ticked == true }
        button("start", "Start", state.ticked == true and ((not setup and not crowd) or state.target ~= nil))
        button("cancel", "Cancel", true)
    elseif state.view == "running" then
        view.title = check and "Checking this spot" or "Testing your settings"
        view.banner = "PLEASE DON'T MOVE, TURN THE CAMERA OR OPEN ANY WINDOW"
        local p = ctx.progress
        if state.checking then
            -- The recommendation is being measured once before it is shown.
            view.progress = { "Checking the result..." }
        elseif p then
            view.progress = { "Step " .. p.done .. " of about " .. p.total .. ", " .. guide.timeLeft(p.done, p.total),
                ns.names and ns.names.progress(p) or ("Now testing: " .. tostring(p.label)) }
            -- A reading the test takes again adds steps; say so, or the count looks like it is running away.
            if (p.repeats or 0) > 0 then
                view.progress[#view.progress + 1] = "The step count has grown: when the frame rate isn't steady, the test measures "
                    .. "that setting again so the result can be trusted."
            end
            if not check then
                view.progress[#view.progress + 1] = "It runs on its own, so feel free to step away from the keyboard."
            end
        else
            view.progress = { "Starting..." }
        end
        button("stop", "Stop", true)
        view.escapeCloses = false
    elseif state.view == "stopped" then
        view.title = "The test stopped"
        if state.reason == "preflight" and state.problems and #state.problems > 0 then
            for _, problem in ipairs(state.problems) do
                local headline, advice = guide.explain(problem)
                add(headline)
                add(advice)
            end
        else
            local headline, advice = guide.explain(state.reason)
            add(headline)
            add(advice)
        end
        add("")
        add(guide.restoreLine(restore))
        button("again", "Try again", true)
        button("close", "Close", true)
    elseif state.view == "done" then
        if check then
            view.title = "Check finished"
            local result = state.result or {}
            if result.ok then
                add("This spot is good for testing.")
            else
                add("This spot is not good for testing right now.")
                local headline, advice = guide.explain(result.reason)
                add(headline)
                add(advice)
            end
            local K = ns.bench and ns.bench.K
            if result.spread and K and result.spread > K.NOISE then
                add("The frame rate was uneven here; a quieter spot gives better results.")
            end
            add(guide.restoreLine(restore))
            if result.ok then button("full", "Run the full test", true) end
            button("close", "Close", true)
        else
            view.title = "Finished"
            add("The test is finished.")
            add(guide.restoreLine(restore))
            local seen, inconclusive = {}, 0
            local entry = state.entry
            for _, row in ipairs(entry and entry.rows or {}) do
                for _, flag in ipairs(row.flags or {}) do
                    if not seen[flag] then seen[flag] = true; add(guide.flagLine(flag)) end
                end
                if row.status == "inconclusive" then inconclusive = inconclusive + 1 end
            end
            if inconclusive == 1 then
                add("1 setting could not be measured reliably; it is marked in the report.")
            elseif inconclusive > 1 then
                add(inconclusive .. " settings could not be measured reliably; they are marked in the report.")
            end
            button("report", "Show report", entry ~= nil)
            button("close", "Close", true)
        end
    end
    return view
end

-- The windows that may not be open during a run, in the order they are reported (spec section 5). A global that does
-- not exist in this client is skipped.
local PANELS = {
    { "SettingsPanel", "panel:settings" },
    { "GameMenuFrame", "panel:menu" },
    { "WorldMapFrame", "panel:map" },
}

-- The reason string of the first forbidden window that is open, or nil.
function guide.panelReason()
    for _, panel in ipairs(PANELS) do
        local frame = _G[panel[1]]
        local ok, shown = pcall(function() return frame and frame.IsShown and frame:IsShown() end)
        if ok and shown then return panel[2] end
    end
    return nil
end

-- The sentence for a flag on a measured row; any other flag is shown as written.
function guide.flagLine(flag)
    if flag == "possible background-window cap" then
        return "The game may have lost focus at some point (alt-tab?), so some results may be unreliable."
    elseif flag == "lighting may have changed" then
        return "The time of day in the game changed during the test, which can affect lighting results."
    elseif flag == "no measurable effect or not applied" then
        return "Some settings made no measurable difference in this spot; the report lists them."
    end
    return flag
end

-- The flow (spec section 6) ---------------------------------------------------------------------------------------
-- One state table decides what the window says; the frame adapter at the end of this file draws it.
local state = nil

-- Drawing never raises into the caller: a window that cannot be drawn says why, once per distinct error, and the
-- state (and anything already running) carries on. Nothing is started because of a failed draw.
local lastError
local function guarded(fn)
    local ok, err = pcall(fn)
    if not ok and err ~= lastError then
        lastError = err
        ns.say("the guide window could not be drawn: " .. tostring(err) .. " (tell the person who gave you this addon)")
    end
end

local function draw()
    guarded(guide.render)
end

local function present()
    guarded(function()
        guide.render()
        guide.show()
    end)
end

local function dismiss()
    guarded(guide.hide)
end

-- The current state: {view, kind, ticked, reason, problems, entry, result}; nil before the first open.
function guide.state()
    return state
end

-- True while a run that this window started is still going: its report is offered on the Finished view's button, so
-- it does not open by itself on top of the window (ui.runFinished asks).
function guide.handlesReport()
    return state ~= nil and state.view == "running" and state.started == true
        and (state.kind == "run" or state.kind == "setup" or state.kind == "crowd")
end

-- The newest finished quiet-spot test the crowd test can build on: valid, with rows of its own, and neither a crowd entry
-- nor a mark. nil when there is none.
function guide.findQuiet()
    local history = ns.bench and ns.bench.history() or {}
    for i = #history, 1, -1 do
        local entry = history[i]
        if entry.valid == true and not entry.label and entry.kind ~= "crowd" and type(entry.rows) == "table" and #entry.rows > 0 then
            return entry
        end
    end
    return nil
end

local function listedTarget(n)
    for _, target in ipairs(ns.recommend and ns.recommend.TARGETS or {}) do
        if target == n then return true end
    end
    return false
end

-- Shows the window for `kind` ("run" or "check"): Running when a check, run or mark is already active, else a fresh,
-- unticked Intro. Opening never starts anything.
function guide.open(kind)
    if ns.bench and ns.bench.active() then
        -- A run started from this window keeps its own state: its kind is the truth, not the command typed now.
        if not (state and state.view == "running") then state = { view = "running", kind = kind } end
    else
        state = { view = "intro", kind = kind, ticked = false }
        if kind == "setup" then
            local saved = ns.ui and ns.ui.state() and ns.ui.state().target
            if listedTarget(saved) then state.target = saved end
            local mode = ns.ui and ns.ui.state() and ns.ui.state().mode
            state.mode = mode == "thorough" and "thorough" or "quick"
        elseif kind == "crowd" then
            -- The crowd has its own target, 60 until the player picks another; with no quiet-spot test to build on the
            -- window only says so.
            local saved = ns.ui and ns.ui.state() and ns.ui.state().crowdTarget
            state.target = listedTarget(saved) and saved or 60
            state.missing = guide.findQuiet() == nil
        end
    end
    present()
end

-- Chooses Quick or Thorough in the setup Intro (anything else is ignored). It is saved only when Start is pressed.
function guide.setMode(mode)
    if state and state.view == "intro" and state.kind == "setup" and (mode == "quick" or mode == "thorough") then
        state.mode = mode
        draw()
    end
end

-- Chooses the frame-rate target in the setup Intro (a number from recommend.TARGETS; anything else is ignored). It is
-- saved only when Start is pressed.
function guide.setTarget(n)
    if state and state.view == "intro" and (state.kind == "setup" or (state.kind == "crowd" and not state.missing))
        and listedTarget(n) then
        state.target = n
        draw()
    end
end

function guide.setTicked(on)
    if state and state.view == "intro" then
        state.ticked = on and true or false
        draw()
    end
end

-- A finished or refused run or check becomes the Done or Stopped view (rules in the plan, Task 5).
local function finished(kind, result)
    result = result or {}
    if kind == "check" then
        if result.ok or result.reason == "control did not respond" then
            return { view = "done", kind = kind, result = result }
        end
    elseif result.valid == true then
        return { view = "done", kind = kind, entry = result }
    end
    return { view = "stopped", kind = kind, reason = result.reason, problems = result.problems, entry = result.rows and result or nil }
end

local function start()
    local kind, target, mode = state.kind, state.target, state.mode
    local reason = guide.panelReason()
    if reason then
        state = { view = "stopped", kind = kind, reason = reason, target = target, mode = mode }
        return draw()
    end
    -- The crowd test builds on the newest finished quiet-spot test; without one it does not start.
    local quiet
    if kind == "crowd" then
        quiet = guide.findQuiet()
        if not quiet then
            state = { view = "stopped", kind = kind, reason = "no quiet result", target = target }
            return draw()
        end
    end
    state = { view = "running", kind = kind, started = true, target = target, mode = mode }
    local saved = ns.ui and ns.ui.state()
    if kind == "setup" then
        -- A setup run learns the levels of every setting it does not know yet, then runs like `/fset bench`. The
        -- target and the mode are kept for next time only now that the run is really starting.
        if saved then
            saved.target = target
            saved.mode = mode == "thorough" and "thorough" or "quick"
        end
        ns.bench.learn()
    elseif kind == "crowd" and saved then
        saved.crowdTarget = target
    end
    ns.bench.watch = guide.panelReason
    local function showResults(shown, verify)
        dismiss()
        local ok, err = pcall(ns.results.show, shown, target, verify)
        if not ok then
            ns.say("the results window could not be shown: " .. tostring(err))
            present()
        end
    end
    local function onDone(result)
        ns.bench.watch = nil
        state = finished(kind, result)
        state.target = target
        state.mode = mode
        if (kind == "setup" or kind == "crowd") and state.view == "done" and ns.results then
            -- A finished setup or crowd run goes straight to the results window; the two never overlap. A crowd result
            -- is the crowd's measurement laid over the quiet-spot curves.
            local measurement = state.entry
            local prepared, shown, choice = pcall(function()
                local entry = measurement
                if kind == "crowd" then entry = ns.recommend.crowdEntry(quiet, measurement) end
                return entry, ns.recommend.choose(entry, target)
            end)
            if not prepared then
                -- Never leave a Running view behind a test that has ended: show the Finished view instead.
                ns.say("the results could not be prepared: " .. tostring(shown))
                present()
                return
            end
            if choice.status == "change" and ns.bench.verify then
                -- A recommendation is measured once before it is shown. Whatever happens to the check, the results
                -- come next, with the measurement when there is one.
                local values = {}
                for _, change in ipairs(choice.changes) do values[change.cvar] = change.to end
                state = { view = "running", kind = kind, started = true, checking = true, target = target, mode = mode }
                ns.bench.watch = guide.panelReason
                draw()
                ns.bench.verify(values, function(check)
                    ns.bench.watch = nil
                    local verify
                    if check and check.ok == true then
                        verify = check
                        measurement.verify = { predictedMs = choice.afterMs,
                            measuredMs = choice.nowMs * check.appliedMs / check.baselineMs }
                    end
                    state = { view = "done", kind = kind, entry = measurement, target = target, mode = mode }
                    showResults(shown, verify)
                end, { silent = true })
                return
            end
            showResults(shown, nil)
        else
            draw()
        end
    end
    if kind == "check" then
        ns.bench.check(onDone)
    elseif kind == "setup" then
        ns.bench.run(onDone, { levels = mode == "thorough" and "all" or "quick", kind = "setup", silent = true })
    elseif kind == "crowd" then
        ns.bench.crowd(quiet, onDone, { silent = true })
    else
        ns.bench.run(onDone)
    end
    draw()
end

-- A button of the window, by the keys of guide.model.
function guide.click(key)
    if not state then return end
    if key == "start" then
        if state.view == "intro" and state.ticked and (state.kind ~= "setup" or state.target) then start() end
    elseif key == "stop" then
        ns.bench.stop()
    elseif key == "again" then
        local kind, target, mode = state.kind, state.target, state.mode
        guide.open(kind)
        if (kind == "setup" or kind == "crowd") and state.view == "intro" then
            if target then state.target = target end
            if mode then state.mode = mode end
            draw()
        end
    elseif key:sub(1, 7) == "target:" then
        guide.setTarget(tonumber(key:sub(8)))
    elseif key:sub(1, 5) == "mode:" then
        guide.setMode(key:sub(6))
    elseif key == "full" then
        guide.open("run")
    elseif key == "report" then
        dismiss()   -- the report takes the stage; the two windows are the same size class and would overlap
        ns.ui.showReport(state.entry)
    elseif key == "cancel" or key == "close" then
        dismiss()
    end
end

-- The window (spec sections 3, 5 and 9): the thin adapter that draws guide.model. Everything it shows comes from the
-- model; it holds no rules of its own except where Escape may close it and when to redraw.
local WINDOW_NAME = "ForeverSettingsGuide"
local WIDTH = 480
local REFRESH = 0.5      -- seconds of frame time between redraws while Running (spec section 6)
local frame, parts       -- built on first use
local sinceRefresh = 0

-- A frame from a template; a client without that template gets the plain frame of `fallbackKind` (default: the same
-- kind) and the second result says it is not the templated one.
local function make(kind, name, parent, template, fallbackKind)
    local ok, made = pcall(CreateFrame, kind, name, parent, template)
    if ok and made then return made, true end
    return CreateFrame(fallbackKind or kind, name, parent), false
end

-- A plain button has no text of its own: it is given a font string to carry the label.
local function giveLabel(button)
    local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button:SetFontString(fs)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)
end

local function text(parent, font, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetWidth(width or (WIDTH - 36))
    fs:SetJustifyH("LEFT")
    return fs
end

local function makeButton(f)
    local button, templated = make("Button", nil, f, "UIPanelButtonTemplate")
    if not templated then giveLabel(button) end
    button:SetSize(120, 24)
    button:SetScript("OnClick", function(self) guide.click(self.key) end)
    return button
end

local function build()
    local f, templated = make("Frame", WINDOW_NAME, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if templated then
        if f.SetTitle then f:SetTitle("ForeverSettings") end
    else
        local background = f:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.85)
    end
    local p = { buttons = {} }
    p.title = text(f, "GameFontNormalLarge")
    p.banner = text(f, "GameFontNormalLarge")
    p.banner:SetTextColor(1, 0.2, 0.2)
    p.progress = text(f, "GameFontNormal")
    p.body = text(f, "GameFontHighlight")
    p.prompt = text(f, "GameFontHighlight")
    p.targets = {}
    for i, n in ipairs(ns.recommend and ns.recommend.TARGETS or {}) do
        local button = makeButton(f)
        button:SetSize(56, 24)
        button.key = "target:" .. n
        button:SetText(tostring(n))
        p.targets[i] = button
    end
    p.modes = {}
    for i, key in ipairs({ "quick", "thorough" }) do
        local button = makeButton(f)
        button:SetSize(210, 24)
        button.key = "mode:" .. key
        p.modes[i] = button
    end
    local box, boxTemplated = make("CheckButton", nil, f, "UICheckButtonTemplate", "Button")
    box:SetSize(26, 26)
    if boxTemplated then
        p.boxLabel = text(f, "GameFontHighlight", WIDTH - 70)
        p.boxLabel:SetPoint("LEFT", box, "RIGHT", 4, 0)
        box:SetScript("OnClick", function(self) guide.setTicked(self:GetChecked() and true or false) end)
    else
        giveLabel(box)
        box:SetSize(WIDTH - 36, 26)
        box:SetScript("OnClick", function() guide.setTicked(not (state and state.ticked)) end)
    end
    p.box, p.boxTemplated = box, boxTemplated
    p.buttons[1], p.buttons[2] = makeButton(f), makeButton(f)
    f:SetScript("OnUpdate", function(_, elapsed)
        if not state or state.view ~= "running" then return end
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh < REFRESH then return end
        sinceRefresh = 0
        if ns.bench and not ns.bench.active() then
            -- The test this view showed is over and nothing here will end the view (a `mark`, or a run started
            -- elsewhere): the window goes away.
            state = { view = "intro", kind = state.kind, ticked = false }
            guide.hide()
            return
        end
        draw()
    end)
    -- The title bar's X, and Escape if the client ignores the list change, hide the frame like any other. While a test
    -- runs the banner has to stay, so it comes straight back; Stop is the way out.
    f:SetScript("OnHide", function(self)
        if state and state.view == "running" then self:Show() end
    end)
    frame, parts = f, p
    return f
end

local function ensure()
    return frame or build()
end

-- The window may be closed with Escape in every view except Running; the list is rebuilt, so the name is in it once
-- or not at all.
local function syncEscape(allowed)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == WINDOW_NAME then tremove(UISpecialFrames, i) end
    end
    if allowed then tinsert(UISpecialFrames, WINDOW_NAME) end
end

-- The height a font string needs for its text: the client's answer, else a line count.
local function heightOf(fs, str)
    local h = fs:GetStringHeight()
    if type(h) == "number" and h > 0 then return h end
    local _, breaks = str:gsub("\n", "\n")
    return 14 * (breaks + 1)
end

local function windowCount()
    local resolved = ns.bench.resolve()
    local currents = {}
    for _, entry in ipairs(resolved) do currents[entry.cvar] = GetCVar(entry.cvar) end
    return ns.bench.countWindows(resolved, currents)
end

-- Draws the current state: the model's title, lines, banner, progress, tick box and buttons, stacked from the top.
function guide.render()
    if not state then return end
    local f = ensure()
    local p = parts
    local ctx = { progress = ns.bench.progress(), restore = guide.restoreInfo() }
    if state.view == "intro" and state.kind == "run" then
        ctx.windows = windowCount()
    elseif state.view == "intro" and state.kind == "setup" then
        ctx.windowsByMode = { quick = ns.bench.estimateSetupWindows("quick"), thorough = ns.bench.estimateSetupWindows("all") }
        ctx.windows = ctx.windowsByMode[state.mode == "thorough" and "thorough" or "quick"]
    elseif state.view == "intro" and state.kind == "crowd" and not state.missing then
        ctx.windows = ns.bench.estimateCrowdWindows(guide.findQuiet())
    end
    local view = guide.model(state, ctx)

    local y = 34
    local function place(fs, str, gap)
        fs:SetText(str)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -y)
        fs:Show()
        y = y + heightOf(fs, str) + gap
    end
    place(p.title, view.title, 10)
    if view.banner then place(p.banner, view.banner, 8) else p.banner:SetText(""); p.banner:Hide() end
    if view.progress then
        place(p.progress, table.concat(view.progress, "\n"), 10)
    else
        p.progress:SetText("")
        p.progress:Hide()
    end
    if #view.lines > 0 then place(p.body, table.concat(view.lines, "\n"), 12) else p.body:SetText(""); p.body:Hide() end
    if view.targets then
        place(p.prompt, view.targets.prompt, 6)
        for i, button in ipairs(p.targets) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", f, "TOPLEFT", 18 + (i - 1) * 62, -y)
            if view.targets.selected == view.targets.list[i] then button:LockHighlight() else button:UnlockHighlight() end
            button:Show()
        end
        y = y + 34
    else
        p.prompt:SetText("")
        p.prompt:Hide()
        for _, button in ipairs(p.targets) do button:Hide() end
    end
    if view.modes then
        for i, button in ipairs(p.modes) do
            local spec = view.modes.list[i]
            button:SetText(spec.text)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", f, "TOPLEFT", 18 + (i - 1) * 222, -y)
            if view.modes.selected == spec.key then button:LockHighlight() else button:UnlockHighlight() end
            button:Show()
        end
        y = y + 34
    else
        for _, button in ipairs(p.modes) do button:Hide() end
    end

    local box = p.box
    if view.checkbox then
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -y)
        box:Show()
        if p.boxTemplated then
            box:SetChecked(view.checkbox.checked)
            p.boxLabel:SetText(view.checkbox.text)
            p.boxLabel:Show()
        else
            box:SetText((view.checkbox.checked and "[x] " or "[ ] ") .. view.checkbox.text)
        end
        y = y + 34
    else
        box:Hide()
        if p.boxLabel then p.boxLabel:Hide() end
    end

    local count = #view.buttons
    for i, button in ipairs(p.buttons) do
        local spec = view.buttons[i]
        if spec then
            button.key = spec.key
            button:SetText(spec.text)
            button:SetEnabled(spec.enabled)
            button:ClearAllPoints()
            button:SetPoint("BOTTOM", f, "BOTTOM", count == 1 and 0 or (i == 1 and -66 or 66), 14)
            button:Show()
        else
            button:Hide()
        end
    end
    f:SetHeight(math.max(y + 52, 150))
    syncEscape(view.escapeCloses)
end

function guide.show()
    ensure()
    sinceRefresh = 0
    frame:Show()
end

function guide.hide()
    if frame then frame:Hide() end
end

function guide.frame()
    return frame
end
