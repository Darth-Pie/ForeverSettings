-- Tests for Settings.lua, the My settings window (spec 2026-10-30-words-and-menu-design.md section 3.4), driven through
-- the shared harness. The model is tested directly; the frame is read the way a player sees it.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function outText() return table.concat(OUT, " | ") end
local function copyOf(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local function sameTable(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- The shared fixture: Everyday in use with {Shadows 2}, Crowded holding {Shadows 0}; four settings exist in the client.
local function boot(over)
    over = over or {}
    local e = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64", RenderScale = "1", vsync = "0" },
        { fresh = true, settings = over.settings })
    local b, p = e.ns.bench, e.ns.profiles
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    local db = p.state()
    db.profiles.everyday.values = { graphicsShadowQuality = "2" }
    db.profiles.crowded.values = { graphicsShadowQuality = "0" }
    db.active = over.active or "everyday"
    db.want = p.plan(db.active).want
    db.original.values = p.live(p.originalNames())
    OUT, SETLOG = {}, {}
    return e, e.ns.settings, db, p
end

local function window()
    for _, f in ipairs(H.frames()) do
        if f.name == "ForeverSettingsSettings" then return f end
    end
end
local function walk(f, fn)
    fn(f)
    for _, c in ipairs(f.children) do walk(c, fn) end
end
local function byKey(f, key)
    local found
    walk(f, function(frame)
        if not found and frame.key == key and frame.shown then found = frame end
    end)
    return found
end
local function shownTexts(f)
    local list = {}
    walk(f, function(frame)
        if frame.shown then
            for _, fs in ipairs(frame.fontStrings) do
                if fs.shown and fs._text and fs._text ~= "" then list[#list + 1] = fs._text end
            end
            if frame.kind == "Button" and frame._text and frame._text ~= "" then list[#list + 1] = frame._text end
        end
    end)
    return list
end
local function allText(f) return table.concat(shownTexts(f), "\n") end
local function hasText(f, part) return allText(f):find(part, 1, true) ~= nil end
local function ctxOf(e, over)
    local ctx = { active = "everyday",
        saved = { everyday = { graphicsShadowQuality = "2" }, crowded = { graphicsShadowQuality = "0" } },
        live = function(cvar) return CVARS[cvar] end, resolved = e.ns.bench.resolve(), locked = nil }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return ctx
end
local function levelTexts(row)
    local list = {}
    for _, level in ipairs(row.levels) do list[#list + 1] = level.text end
    return table.concat(list, "|")
end
local function selectedOf(row)
    local list = {}
    for _, level in ipairs(row.levels) do
        if level.selected then list[#list + 1] = level.value end
    end
    return table.concat(list, ",")
end

local INTRO = "Choose how the game looks. Settings you tick are kept: the addon puts them back at every loading screen."
local COMBAT_TEXT = "You are in combat; try again afterwards."
local BUSY_TEXT = "A test is running; try again afterwards."
local RAW = { "graphicsShadowQuality", "graphicsSSAO", "groundEffectDensity", "RenderScale", "graphicsComputeEffects" }

test("S1-1 the title and the intro; no tabs and no footer buttons; the notice is quiet on Everyday", function()
    local e, s = boot()
    local view = s.model({ page = "light" }, ctxOf(e))
    return view.title == "My settings" and view.intro == INTRO and view.tabs == nil and view.buttons == nil and view.notice == nil,
        tostring(view.tabs)
end)

test("S1-2 with Original in use the rows are read-only, the line offers Everyday and Crowded, and a stray click writes nothing", function()
    local e, s, db = boot({ active = "original" })
    local view = s.model({ page = "light" }, ctxOf(e, { active = "original" }))
    s.open("light")
    local before = copyOf(db.profiles.everyday.values)
    s.click("level:graphicsShadowQuality:3")
    s.click("keep:graphicsSSAO")
    local stored = sameTable(db.profiles.everyday.values, before) and db.active == "original" and #SETLOG == 0
        and CVARS.graphicsShadowQuality == "2" and next(db.want) == nil and #OUT == 0
    return view.readOnly ~= nil and view.readOnly.text == "Original can't be changed. To change settings, edit:" and view.rows[1].enabled == false
        and stored, outText()
end)

test("S1-3 one row per setting the client has, in the table's order, with the plain name, line and level words", function()
    local e, s = boot()
    local view = s.model({ page = "light" }, ctxOf(e))
    local order = {}
    for _, row in ipairs(view.rows) do order[#order + 1] = row.cvar end
    local r = view.rows
    return table.concat(order, ",") == "graphicsShadowQuality,graphicsSSAO,groundEffectDensity,RenderScale"
        and r[1].name == "Shadow detail"
        and r[1].line == "How sharp and detailed shadows look. Higher looks better and costs a lot of speed."
        and levelTexts(r[1]) == "0 (lowest)|1|2|3|4 (highest)" and r[2].name == "Soft corner shadows"
        and r[3].name == "Grass and plants (exact amount)" and levelTexts(r[3]) == "48 (lowest)|64|128 (highest)"
        and r[4].name == "Picture sharpness" and levelTexts(r[4]) == "50%|60%|70%|80%|90%|100%|125%|150%|175%|200%", order[3] .. " " .. levelTexts(r[4])
end)

test("S1-4 the rows highlight the game's live levels and the ticks follow what the profile in use holds", function()
    local e, s = boot()
    CVARS.graphicsShadowQuality = "3"
    local mine = s.model({ page = "light" }, ctxOf(e))
    local crowd = s.model({ page = "light" }, ctxOf(e, { active = "crowded" }))
    return selectedOf(mine.rows[1]) == "3" and mine.rows[1].kept and selectedOf(mine.rows[2]) == "1" and not mine.rows[2].kept
        and selectedOf(crowd.rows[1]) == "3" and crowd.rows[1].kept and not crowd.rows[2].kept and selectedOf(crowd.rows[4]) == "1",
        selectedOf(mine.rows[1]) .. selectedOf(crowd.rows[1])
end)

test("S1-5 a level click is applied and kept in the profile in use through setValue, silently", function()
    local e, s, db, p = boot()
    local calls = {}
    local real = p.setValue
    p.setValue = function(cvar, value, silent) calls[#calls + 1] = { cvar, value, silent } return real(cvar, value, silent) end
    s.open("light")
    s.click("level:graphicsShadowQuality:3")
    return #calls == 1 and calls[1][1] == "graphicsShadowQuality" and calls[1][2] == "3" and calls[1][3] == true
        and CVARS.graphicsShadowQuality == "3" and db.profiles.everyday.values.graphicsShadowQuality == "3"
        and db.want.graphicsShadowQuality == "3" and #OUT == 0, outText()
end)

test("S1-7 unticking stops keeping a setting: the game keeps its value", function()
    local e, s, db = boot()
    s.open("light")
    s.click("keep:graphicsShadowQuality")
    return db.profiles.everyday.values.graphicsShadowQuality == nil and db.want.graphicsShadowQuality == nil
        and CVARS.graphicsShadowQuality == "2" and #OUT == 0, outText()
end)

test("S1-8 ticking an unticked row keeps the game's current value in the profile in use", function()
    local e, s, db = boot()
    CVARS.graphicsSSAO = "3"
    s.open("light")
    s.click("keep:graphicsSSAO")
    return db.profiles.everyday.values.graphicsSSAO == "3" and db.want.graphicsSSAO == "3" and db.profiles.crowded.values.graphicsSSAO == nil
        and #OUT == 0, outText()
end)

test("S1-9 in combat or during a test every control is greyed with its reason, and clicks that still arrive write nothing", function()
    local e, s, db = boot()
    local combat = s.model({ page = "light" }, ctxOf(e, { locked = "combat" }))
    local busy = s.model({ page = "light" }, ctxOf(e, { locked = "busy" }))
    local greyed = true
    for _, view in ipairs({ combat, busy }) do
        for _, row in ipairs(view.rows) do greyed = greyed and row.enabled == false end
    end
    s.open("light")
    local function nothingWrites(setup, undo)
        setup()
        local before = { copyOf(db.profiles.everyday.values), copyOf(db.profiles.crowded.values), copyOf(db.want), db.active }
        SETLOG = {}
        s.click("level:graphicsShadowQuality:4")
        s.click("keep:graphicsSSAO")
        s.click("keep:graphicsShadowQuality")
        s.click("profile:crowded")
        s.click("save:everyday")
        local same = sameTable(db.profiles.everyday.values, before[1]) and sameTable(db.profiles.crowded.values, before[2])
            and sameTable(db.want, before[3]) and db.active == before[4] and #SETLOG == 0 and CVARS.graphicsShadowQuality == "2"
        undo()
        return same
    end
    local inCombat = nothingWrites(function() COMBAT = true end, function() COMBAT = false end)
    local running = nothingWrites(function() e.ns.suspended = true end, function() e.ns.suspended = false end)
    return combat.locked == COMBAT_TEXT and busy.locked == BUSY_TEXT and greyed and inCombat and running, outText()
end)

test("S1-11 a profile switched from outside moves the pill and the highlight within the refresh interval", function()
    local e, s, db, p = boot()
    s.open("light")
    local f = window()
    local before = byKey(f, "pill").label._text == "Everyday"
    p.switch("crowded")
    e.pump(1, function() return 0.05 end)
    local after = byKey(f, "pill").label._text == "Crowded"
    local highlighted = byKey(f, "level:graphicsShadowQuality:0").skinState.selected == true
        and byKey(f, "level:graphicsShadowQuality:2").skinState.selected == false
    return before and after and highlighted, tostring(byKey(f, "pill").label._text)
end)

test("S1-12 the window's pages: a tick and level buttons per setting on each page, 13 levels wrap onto three lines of six, the X closes it, Escape is listed once, no raw names", function()
    local e, s, db = boot()
    local b = e.ns.bench
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" }
    s.open("light")
    s.open("light")
    local f = window()
    if not f then return false, "no window: " .. outText() end
    local function count(prefix)
        local n = 0
        walk(f, function(frame)
            if frame.shown and frame.key and frame.key:sub(1, #prefix) == prefix then n = n + 1 end
        end)
        return n
    end
    local function rawIn(frame)
        for _, text in ipairs(shownTexts(frame)) do
            for _, name in ipairs(RAW) do if text:find(name, 1, true) then return true end end
        end
        return false
    end
    local raw = rawIn(f)
    local lightKeeps, lightLevels = count("keep:"), count("level:")
    local lines = {}
    walk(f, function(frame)
        if frame.shown and frame.key and frame.key:find("^level:graphicsSSAO:") then lines[frame._point[5]] = true end
    end)
    local ssaoLines = 0
    for _ in pairs(lines) do ssaoLines = ssaoLines + 1 end
    local keepBox, live = byKey(f, "keep:graphicsShadowQuality"), byKey(f, "level:graphicsShadowQuality:2")
    local keptNow = keepBox ~= nil and keepBox:GetChecked() == true
    local liveSelected = live ~= nil and live.skinState.selected == true
    local titled = hasText(f, "Light and shadows") and hasText(f, "Shadow detail") and byKey(f, "pill").label._text == "Everyday"
    s.click("page:world")
    local worldKeeps, worldLevels = count("keep:"), count("level:")
    raw = raw or rawIn(f)
    s.click("page:size")
    local sizeKeeps, sizeLevels = count("keep:"), count("level:")
    raw = raw or rawIn(f)
    local listed = 0
    for _, name in ipairs(UISpecialFrames) do if name == "ForeverSettingsSettings" then listed = listed + 1 end end
    f.close:Click()
    return titled and keptNow and liveSelected and not f:IsShown() and listed == 1 and not raw
        and lightKeeps == 2 and lightLevels == 5 + 13 and ssaoLines == 3 and worldKeeps == 1 and worldLevels == 3
        and sizeKeeps == 1 and sizeLevels == 10,
        tostring(lightKeeps) .. " " .. tostring(lightLevels) .. " " .. tostring(ssaoLines) .. " " .. tostring(worldKeeps) .. " "
            .. tostring(worldLevels) .. " " .. tostring(sizeKeeps) .. " " .. tostring(sizeLevels) .. " " .. tostring(listed) .. " " .. tostring(raw)
end)

test("S1-13 no action of the window prints to chat", function()
    local e, s = boot()
    s.open("light")
    s.click("level:graphicsShadowQuality:3")
    s.click("keep:graphicsSSAO")
    s.click("keep:graphicsSSAO")
    s.click("profile:crowded")
    s.click("level:graphicsShadowQuality:1")
    s.click("keep:graphicsShadowQuality")
    s.click("save:everyday")
    s.click("profile:everyday")
    return #OUT == 0, outText()
end)

-- Maximum and costs, Task 4: what a level costs, what a setting is worth, the total and the Maximum button
-- (spec 2026-10-30-maximum-and-costs-design.md section 3.2)
local NOW = 1000000
local COST_QUIET = "Costs from your quiet-spot test. Measured in Highmountain, 3 days ago."
local COST_CROWD = "Costs from your crowd test. Measured in Stormwind City, 2 hours ago."
local COST_NONE = "Run Find my best settings to see what each level costs."
local MATTERS_NOTE = [["Matters to the picture" is the addon's own judgement, not something it measured.]]
local MAX_ON = "You're using Maximum (everything at its highest). It includes the sharpest textures, which need plenty of "
    .. "graphics memory."
local LEFT_OUT_1 = "1 setting stays as it is: the addon has not learned its levels yet."
local NOTHING = "Maximum has nothing to set yet: run Find my best settings once so the addon learns what each setting can do."
local SKIPPED_3 = "The test skipped the highest levels of 3 settings, so there is no total yet. Run Find my best settings and choose Thorough."
local SKIPPED_1 = "The test skipped the highest levels of 1 setting, so there is no total yet. Run Find my best settings and choose Thorough."

local function lv(cvar, setting, value, deltaMs, current)
    return { setting = setting, cvar = cvar, value = value, meanMs = 4.0 + deltaMs, deltaMs = deltaMs, flags = {}, current = current }
end
-- T1: Shadows 0:-1.0, 1:-0.4, 2:0 (now) and SSAO 0:-0.6, 1:-0.3, 2:0 (now) on a 4.0 ms baseline. Shadows read 333.33, 277.78
-- and 250 fps; SSAO 294.12, 270.27 and 250.
local function quietEntry()
    return { valid = true, kind = "setup", mode = "thorough", zone = "Highmountain", time = NOW - 259200, baselineMs = 4.0,
        starts = { graphicsShadowQuality = "2", graphicsSSAO = "2" }, rows = {
            lv("graphicsShadowQuality", "Shadows", "0", -1.0), lv("graphicsShadowQuality", "Shadows", "1", -0.4),
            lv("graphicsShadowQuality", "Shadows", "2", 0, true),
            lv("graphicsSSAO", "SSAO", "0", -0.6), lv("graphicsSSAO", "SSAO", "1", -0.3), lv("graphicsSSAO", "SSAO", "2", 0, true),
        } }
end
-- T1 plus the highest level of every setting of the fixture client: Shadows 4 costs 1.2 ms, SSAO 4 0.8, clutter (raw) 128
-- 0.6 and render scale 1 is where it is, so everything at the highest is 6.6 ms, 151.5 fps.
local function fullEntry()
    local entry = quietEntry()
    local function add(...) entry.rows[#entry.rows + 1] = lv(...) end
    add("graphicsShadowQuality", "Shadows", "3", 0.5)
    add("graphicsShadowQuality", "Shadows", "4", 1.2)
    add("graphicsSSAO", "SSAO", "3", 0.4)
    add("graphicsSSAO", "SSAO", "4", 0.8)
    add("groundEffectDensity", "Ground clutter (raw)", "48", -0.3)
    add("groundEffectDensity", "Ground clutter (raw)", "64", 0, true)
    add("groundEffectDensity", "Ground clutter (raw)", "128", 0.6)
    add("RenderScale", "Render scale", "0.5", -2.0)
    add("RenderScale", "Render scale", "1", 0, true)
    return entry
end
-- A crowd measurement on a 10 ms baseline: Shadows' lowest level saves 3 ms there, SSAO's 0.6 ms.
local function crowdFixture()
    return { kind = "crowd", valid = true, baselineMs = 10.0, zone = "Stormwind City", time = NOW - 7200,
        starts = { graphicsShadowQuality = "2", graphicsSSAO = "2" }, settings = {
            { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", lowDelta = -3.0 },
            { cvar = "graphicsSSAO", setting = "SSAO", lowValue = "0", lowDelta = -0.6 },
        } }
end
local function costsOf(e, entry, kind, line)
    if line == nil then line = "Measured in Highmountain, 3 days ago." elseif line == false then line = nil end
    return { kind = kind or "quiet", measuredLine = line, fps = e.ns.recommend.levelFps(entry) }
end
local function costTexts(row)
    local list = {}
    for _, level in ipairs(row.levels) do list[#list + 1] = level.cost or "-" end
    return table.concat(list, "|")
end
local function rowOf(view, cvar)
    for _, row in ipairs(view.rows) do
        if row.cvar == cvar then return row end
    end
end
-- The second line the window drew under a level button (a font string a little below the button, in its column), or nil.
local function costFor(f, cvar, value)
    local button = byKey(f, "level:" .. cvar .. ":" .. value)
    if not button or not button._point then return nil end
    local x, y = button._point[4], -button._point[5]
    local found
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text and fs._text ~= "" and fs._point and fs._point[4] == x - 4
                and -fs._point[5] > y + 23 and -fs._point[5] < y + 30 then
                found = fs
            end
        end
    end)
    return found and found._text, found
end
local function fontStringWith(f, str)
    local found
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text == str then found = fs end
        end
    end)
    return found
end
-- How many shown font strings say exactly `str` (a page's name is in the page list and, on its chooser, in the title too).
local function countText(f, str)
    local n = 0
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text == str then n = n + 1 end
        end
    end)
    return n
end
-- The fixture client with a quiet-spot test in the bench history (newest), so context() reads it.
local function bootWith(entry, over)
    local e, s, db, p = boot(over)
    e.ns.bench.now = function() return NOW end
    if entry then e.ns.bench.state().history[1] = entry end
    OUT, SETLOG = {}, {}
    return e, s, db, p
end

test("S2-1 each level's cost is its frame rate minus the held level's, in whole numbers, with now, same and ?; no line without a held level", function()
    local e, s = boot()
    local entry = quietEntry()
    local mine = s.model({ page = "light" }, ctxOf(e, { costs = costsOf(e, entry) }))                   -- Shadows 2, SSAO 1 in the game
    CVARS.graphicsShadowQuality = "1"                                                                      -- Crowded in use holds Shadows 1
    local crowd = s.model({ page = "light" }, ctxOf(e, { active = "crowded", costs = costsOf(e, entry) }))
    CVARS.graphicsShadowQuality = "3"                                                                      -- a level the test never measured
    local unmeasured = s.model({ page = "light" }, ctxOf(e, { costs = costsOf(e, entry) }))
    CVARS.graphicsShadowQuality = "2"
    local noTest = s.model({ page = "light" }, ctxOf(e, {}))
    local near = quietEntry()
    near.rows[2].deltaMs, near.rows[2].meanMs = -0.001, 3.999           -- Shadows 1: 0.06 fps faster than the held level 2
    near.rows[4].deltaMs, near.rows[4].meanMs = -0.31, 3.69             -- SSAO 0: 0.73 fps faster than the held level 1
    local rounded = s.model({ page = "light" }, ctxOf(e, { costs = costsOf(e, near) }))
    local none = "-|-|-|-|-"
    return costTexts(rowOf(mine, "graphicsShadowQuality")) == "+83 fps|+28 fps|now|?|?"
        and costTexts(rowOf(mine, "graphicsSSAO")) == "+24 fps|now|-20 fps|?|?"
        and costTexts(rowOf(mine, "groundEffectDensity")) == "-|-|-" and costTexts(rowOf(mine, "RenderScale")) == "-|-|-|-|-|-|-|-|-|-"
        and costTexts(rowOf(crowd, "graphicsShadowQuality")) == "+56 fps|now|-28 fps|?|?"
        and costTexts(rowOf(crowd, "graphicsSSAO")) == "+24 fps|now|-20 fps|?|?"
        and costTexts(rowOf(unmeasured, "graphicsShadowQuality")) == none
        and costTexts(rowOf(noTest, "graphicsShadowQuality")) == none and costTexts(rowOf(noTest, "graphicsSSAO")) == none
        and costTexts(rowOf(rounded, "graphicsShadowQuality")) == "+83 fps|same|now|?|?"
        and costTexts(rowOf(rounded, "graphicsSSAO")) == "+1 fps|now|-20 fps|?|?",
        costTexts(rowOf(mine, "graphicsShadowQuality")) .. " / " .. costTexts(rowOf(crowd, "graphicsShadowQuality")) .. " / "
            .. costTexts(rowOf(rounded, "graphicsShadowQuality"))
end)

test("S2-2 the note under the intro names the test the costs come from or says to run one; with Crowded in use the crowd result comes first", function()
    local e, s = boot()
    local entry = quietEntry()
    local quiet = s.model({ page = "light" }, ctxOf(e, { costs = costsOf(e, entry) }))
    local crowd = s.model({ page = "light" }, ctxOf(e, { costs = costsOf(e, entry, "crowd", "Measured in Stormwind City, 2 hours ago.") }))
    local noLine = s.model({ page = "light" }, ctxOf(e, { costs = costsOf(e, entry, "quiet", false) }))
    local noTest = s.model({ page = "light" }, ctxOf(e, {}))
    local empty = s.model({ page = "light" }, ctxOf(e, { costs = { kind = "quiet", fps = { nowFps = 250, byCvar = {} } } }))
    local forms = quiet.costNote == COST_QUIET and crowd.costNote == COST_CROWD and noLine.costNote == "Costs from your quiet-spot test."
        and noTest.costNote == COST_NONE and empty.costNote == COST_NONE
    -- through context(): with Crowded in use the window reads the rebuilt crowd entry, with Everyday the quiet-spot test
    local e2, s2 = bootWith(quietEntry())
    local asked = {}
    e2.ns.ui.savedResult = function(kind)
        asked[#asked + 1] = kind
        if kind == "crowded" then
            return { entry = e2.ns.recommend.crowdEntry(quietEntry(), crowdFixture()), measuredLine = "Measured in Stormwind City, 2 hours ago." }
        end
    end
    s2.open("light")
    local f = window()
    local everyday = hasText(f, COST_QUIET) and costFor(f, "graphicsShadowQuality", "0") == "+83 fps"
    s2.click("profile:crowded")                    -- Crowded holds Shadows 0
    local crowded = hasText(f, COST_CROWD) and not hasText(f, COST_QUIET) and costFor(f, "graphicsShadowQuality", "0") == "now"
        and costFor(f, "graphicsShadowQuality", "1") == "-29 fps" and costFor(f, "graphicsShadowQuality", "2") == "-43 fps"
    -- without a saved crowd result Crowded reads the quiet-spot test
    e2.ns.ui.savedResult = function() return nil end
    s2.click("profile:everyday")
    s2.click("profile:crowded")
    local fallback = hasText(f, COST_QUIET) and not hasText(f, COST_CROWD)
    return forms and everyday and crowded and fallback and #OUT == 0, tostring(forms) .. tostring(everyday) .. tostring(crowded)
        .. tostring(fallback) .. outText()
end)

test("S2-3 each setting says how much it matters to the picture, from the ranking; one the ranking does not know says nothing", function()
    local e, s = boot()
    local resolved = e.ns.bench.resolve()
    resolved[#resolved + 1] = { cvar = "someUnknownSetting", label = "Something", tiers = { "0", "1" } }
    local view = s.model({ page = "light" }, ctxOf(e, { resolved = resolved }))
    local words = {}
    for _, row in ipairs(view.rows) do words[#words + 1] = row.cvar .. "=" .. tostring(row.matters) end
    local bare = s.model({ page = "light" }, ctxOf(e, { resolved = { { cvar = "someUnknownSetting", label = "Something", tiers = { "0", "1" } } } }))
    return table.concat(words, ",") == "graphicsShadowQuality=Matters to the picture: some.,graphicsSSAO=Matters to the picture: a little.,"
        .. "groundEffectDensity=Matters to the picture: a little.,RenderScale=Matters to the picture: a lot.,someUnknownSetting=nil"
        and view.mattersNote == MATTERS_NOTE and bare.mattersNote == nil and bare.rows[1].matters == nil, table.concat(words, ",")
end)

test("S2-4 the total line: the estimate, the skipped count in the plural and the singular, and nothing without a test", function()
    local e, s = boot()
    local costs = costsOf(e, quietEntry())
    local function total(max, withCosts)
        return s.model({ page = "light" }, ctxOf(e, { costs = withCosts, maximum = max })).totalLine
    end
    local forms = total({ fps = 92.4, skipped = 0, leftOut = 0 }, costs) == "Everything at the highest: about 92 fps."
        and total({ skipped = 3, leftOut = 0 }, costs) == SKIPPED_3 and total({ skipped = 1, leftOut = 0 }, costs) == SKIPPED_1
        and total({ skipped = 0, leftOut = 2 }, costs) == nil and total({ fps = 92.4, skipped = 0, leftOut = 0 }, nil) == nil
        and total({ skipped = 3, leftOut = 0 }, nil) == nil and total(nil, costs) == nil
    -- through context(): the estimate is recommend's for the highest level of every setting, the count what it could not read
    local e2, s2 = bootWith(fullEntry())
    s2.open("everyday")
    local want = e2.ns.recommend.estimateFps(fullEntry(), e2.ns.profiles.maxValues())
    local f = window()
    local measured = want ~= nil and #want.missing == 0 and hasText(f, "Everything at the highest: about 152 fps.")
    local e3, s3 = bootWith(quietEntry())          -- T1 measured only levels 0 to 2: every highest level is missing
    s3.open("everyday")
    local skipped = hasText(window(), "The test skipped the highest levels of 4 settings, so there is no total yet.")
    local e4, s4 = bootWith(nil)
    s4.open("everyday")
    local noTest = not hasText(window(), "Everything at the highest") and not hasText(window(), "The test skipped")
    -- a test, but a client where nothing can be set: no total (the estimate of nothing is today's frame rate)
    local e5 = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1", vsync = "0" }, { fresh = true })
    e5.ns.bench.now = function() return NOW end
    e5.ns.bench.state().history[1] = quietEntry()
    e5.ns.settings.open("everyday")
    local nothing = hasText(window(), COST_QUIET) and not hasText(window(), "Everything at the highest")
        and not hasText(window(), "The test skipped")
    return forms and measured and skipped and noTest and nothing,
        tostring(forms) .. tostring(measured) .. tostring(skipped) .. tostring(noTest) .. tostring(nothing)
end)

test("S2-5b a click that is refused for combat or a test says why in the window until the next click", function()
    local e, s, db = bootWith(nil)
    s.open("everyday")
    local f = window()
    COMBAT = true
    s.click("profile:maximum")
    local inCombat = hasText(f, COMBAT_TEXT)
    COMBAT = false
    s.click("page:world")
    local cleared = not hasText(f, COMBAT_TEXT)
    e.ns.suspended = true
    s.click("profile:maximum")
    local running = hasText(f, BUSY_TEXT)
    e.ns.suspended = false
    s.click("page:light")
    return inCombat and cleared and running and db.active == "everyday" and #SETLOG == 0 and #OUT == 0, outText()
end)

test("S2-6 a Quick test, an old test, a crowd test and a held level never measured give ? or no costs and a total that says what is missing", function()
    local quick = quietEntry()
    quick.mode = "quick"
    local old = quietEntry()
    old.starts = nil
    for i = #old.rows, 1, -1 do
        if old.rows[i].current then table.remove(old.rows, i) end          -- an old result: no current level, no starts
    end
    local function drawn(entry, arrange)
        local e, s = bootWith(entry)
        if arrange then arrange(e) end
        s.open("everyday")
        local ok = #OUT == 0
        return window(), ok, e, s
    end
    local fQuick, okQuick = drawn(quick)
    local quickRow = costFor(fQuick, "graphicsShadowQuality", "3")
    local quickNote = hasText(fQuick, "The test skipped the highest levels of 4 settings")
    local fOld, okOld = drawn(old)
    local oldBare = costFor(fOld, "graphicsShadowQuality", "0") == nil and costFor(fOld, "graphicsShadowQuality", "1") == nil
    local fCrowd, okCrowd = drawn(quietEntry(), function(e)
        e.ns.ui.savedResult = function() return { entry = e.ns.recommend.crowdEntry(quietEntry(), crowdFixture()),
            measuredLine = "Measured in Stormwind City, 2 hours ago." } end
    end)
    local fUnmeasured = drawn(quietEntry(), function() CVARS.graphicsShadowQuality = "3" end)
    local heldNever = costFor(fUnmeasured, "graphicsShadowQuality", "0") == nil and costFor(fUnmeasured, "graphicsSSAO", "0") == "+24 fps"
    local fBroken, okBroken = drawn({ valid = true, kind = "setup", zone = "Highmountain", time = NOW - 100,
        rows = { lv("graphicsShadowQuality", "Shadows", "1", 0.5) } })             -- no baseline: the recommender cannot read it
    -- a saved crowd result that cannot be rebuilt: with Crowded in use the window falls back to the quiet-spot test and still draws
    local e7, s7 = bootWith(quietEntry())
    e7.ns.ui.savedResult = function() error("no crowd result") end
    e7.ns.profiles.switch("crowded", true)
    OUT = {}
    s7.open("light")
    local okSaved = #OUT == 0 and hasText(window(), COST_QUIET)
    return okQuick and okOld and okCrowd and okBroken and okSaved and quickRow == "?" and quickNote and oldBare and heldNever
        and hasText(fBroken, COST_NONE), tostring(quickRow) .. tostring(quickNote) .. tostring(oldBare) .. tostring(heldNever) .. outText()
end)

test("S2-8 a click on the Maximum card with nothing to set shows the plain reason in the window, writes nothing and prints nothing", function()
    local e = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1", vsync = "0" }, { fresh = true })     -- no levels learned here
    local s, p = e.ns.settings, e.ns.profiles
    local db = p.state()
    local before = db.active
    s.open("everyday")
    OUT, SETLOG = {}, {}
    s.click("profile:maximum")
    local f = window()
    local shown = hasText(f, NOTHING)
    -- a redraw the window makes by itself (a test started elsewhere) drops it
    e.ns.suspended = true
    e.pump(1, function() return 0.05 end)
    local droppedOnRedraw = not hasText(f, NOTHING) and hasText(f, BUSY_TEXT)
    e.ns.suspended = false
    e.pump(1, function() return 0.05 end)
    s.click("profile:maximum")
    local again = hasText(f, NOTHING)
    s.click("page:world")
    local cleared = not hasText(f, NOTHING)
    return db.active == before and #SETLOG == 0 and #OUT == 0 and shown and droppedOnRedraw and again and cleared,
        tostring(db.active == before) .. tostring(#SETLOG) .. tostring(#OUT) .. tostring(shown) .. tostring(droppedOnRedraw)
            .. tostring(again) .. tostring(cleared) .. outText()
end)

test("S2-9 the window draws the costs under the level buttons, the matters words and the notes, and takes them away again without a test", function()
    local e, s, db, p = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    local view = s.model(s.state(), ctxOf(e, { costs = costsOf(e, fullEntry()),
        maximum = { fps = 151.5, skipped = 0, leftOut = 0 } }))
    local match, drawnCosts = true, 0
    for _, row in ipairs(view.rows) do
        if row.page == "light" then
            for _, level in ipairs(row.levels) do
                local text, fs = costFor(f, row.cvar, level.value)
                if level.cost then
                    drawnCosts = drawnCosts + 1
                    if text ~= level.cost or fs._width ~= 58 or fs._wordWrap ~= false then match = false end
                elseif text ~= nil then
                    match = false
                end
            end
        end
    end
    local matters = hasText(f, "matters: some") and hasText(f, "matters: a little")
    local notes = hasText(f, COST_QUIET) and hasText(f, MATTERS_NOTE) and hasText(f, "Everything at the highest: about 152 fps.")
        and byKey(f, "maximum") == nil
    -- a draw with no test: the second lines, the cost note and the total go away, the matters words and their note stay
    e.ns.bench.state().history[1] = nil
    s.open("everyday")
    local gone = costFor(f, "graphicsShadowQuality", "0") == nil and not hasText(f, "Everything at the highest")
        and hasText(f, COST_NONE) and not hasText(f, COST_QUIET) and hasText(f, MATTERS_NOTE) and hasText(f, "matters: some")
    -- with Maximum in use the pill says so and the page is read-only
    p.switch("maximum", true)
    s.open("everyday")
    local noButton = byKey(f, "pill").label._text == "Maximum" and hasText(f, "Maximum can't be changed. To change settings, edit:")
    return match and drawnCosts > 0 and matters and notes and gone and noButton,
        tostring(match) .. tostring(drawnCosts) .. tostring(matters) .. tostring(notes) .. tostring(gone) .. tostring(noButton)
end)

test("S2-13 a level the game will not take when Maximum is switched on from the window is named in the window, in plain words", function()
    local e, s, db = bootWith(nil)
    SETFAIL.graphicsShadowQuality = "clamp"
    s.open("everyday")
    OUT = {}
    s.click("profile:maximum")
    local f = window()
    local one = db.active == "maximum" and hasText(f, "The game would not take the highest level for: Shadow detail.")
        and hasText(f, MAX_ON) and #OUT == 0
    s.click("page:world")                                    -- a redraw by itself drops it, as the other refusal
    local gone = not hasText(f, "would not take")
    s.click("page:light")
    local e2, s2 = bootWith(nil)
    SETFAIL.graphicsShadowQuality = "clamp"
    SETFAIL.graphicsSSAO = "clamp"
    s2.open("everyday")
    s2.click("profile:maximum")
    local f2 = window()
    local two = hasText(f2, "The game would not take the highest level for: ") and hasText(f2, "Shadow detail")
        and hasText(f2, "Soft corner shadows")
    local e3, s3, db3 = bootWith(nil)                        -- nothing refused: no such line
    s3.open("everyday")
    s3.click("profile:maximum")
    local none = not hasText(window(), "would not take")
    local e4, s4, db4 = bootWith(nil)                        -- a setting with no plain name that the game also refuses is not listed
    db4.original.values.maxFPS = "60"
    CVARS.maxFPS = "30"
    SETFAIL.maxFPS = "clamp"
    SETFAIL.graphicsShadowQuality = "clamp"
    s4.open("everyday")
    s4.click("profile:maximum")
    local unnamed = hasText(window(), "The game would not take the highest level for: Shadow detail.") and not hasText(window(), "maxFPS")
    return one and gone and two and none and unnamed, outText()
end)

test("S2-14 while Maximum is in use the note says levels learned since are not applied yet, until a loading screen applies them", function()
    local e, s, db, p = bootWith(nil)
    CVARS.graphicsComputeEffects = "1"                       -- in the client, its levels not learned yet
    p.switch("maximum", true)
    s.open("everyday")
    local before = hasText(window(), LEFT_OUT_1) and not hasText(window(), "highest level at the next loading screen")
    e.ns.bench.state().tiers.graphicsComputeEffects = { "0", "1", "2", "3" }
    s.click("page:world")
    local pending1 = "1 setting will go to its highest level at the next loading screen, or when you choose Maximum in the menu again."
    local learned = hasText(window(), pending1) and not hasText(window(), LEFT_OUT_1)
    e.ns.bench.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4", "5" }      -- a higher level than the one set
    s.click("page:light")
    local pending2 = "2 settings will go to their highest level at the next loading screen, or when you choose Maximum in the menu again."
    local higher = hasText(window(), pending2)
    e.fire("PLAYER_ENTERING_WORLD")
    s.click("page:world")
    local applied = not hasText(window(), "highest level at the next loading screen") and not hasText(window(), LEFT_OUT_1)
        and CVARS.graphicsComputeEffects == "3" and CVARS.graphicsShadowQuality == "5"
    local function note(left, pending)
        return s.model({ page = "light" }, ctxOf(e, { active = "maximum", maximum = { skipped = 0, leftOut = left, pending = pending } })).notice
    end
    local two = "2 settings will go to their highest level at the next loading screen, or when you choose Maximum in the menu again."
    local both = note(1, 2) == MAX_ON .. " " .. LEFT_OUT_1 .. " " .. two
    return before and learned and higher and applied and note(0, 0) == MAX_ON and note(0, 1) == MAX_ON .. " " .. pending1
        and note(0, 2) == MAX_ON .. " " .. two and both, outText()
end)

test("S2-12 without the recommender, the guide or the interface module, or with a test that has no time, the window still draws", function()
    local function opened(opts, entry, tab)
        local e = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1", groundEffectDensity = "64", RenderScale = "1", vsync = "0" },
            { fresh = true, recommend = opts.recommend, guide = opts.guide, ui = opts.ui })
        e.ns.bench.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
        e.ns.bench.now = function() return NOW end
        if entry then e.ns.bench.state().history[1] = entry end
        OUT = {}
        e.ns.settings.open(tab or "everyday")
        return window(), #OUT == 0
    end
    local bad = {}
    for _, off in ipairs({ "recommend", "guide" }) do
        local f, quiet = opened({ [off] = false }, quietEntry())
        if not quiet or f == nil or not hasText(f, COST_NONE) then bad[#bad + 1] = off end
    end
    local fUi, okUi = opened({ ui = false }, quietEntry(), "crowded")
    if not okUi or not hasText(fUi, COST_QUIET) then bad[#bad + 1] = "ui" end
    local timeless = quietEntry()
    timeless.time = nil
    local fTime, okTime = opened({}, timeless)
    if not okTime or not hasText(fTime, "Costs from your quiet-spot test.") or hasText(fTime, "Measured in") then bad[#bad + 1] = "time" end
    return #bad == 0, table.concat(bad, ",") .. outText()
end)

test("S2-11 the note while Maximum is in use counts the settings it left as they were, in the singular and the plural", function()
    local e, s = boot()
    local function note(left) return s.model({ page = "light" }, ctxOf(e, { active = "maximum", maximum = { skipped = 0, leftOut = left } })).notice end
    local plural = "2 settings stay as they are: the addon has not learned their levels yet."
    return note(0) == MAX_ON and note(1) == MAX_ON .. " " .. LEFT_OUT_1 and note(2) == MAX_ON .. " " .. plural
        and s.model({ page = "light" }, ctxOf(e, { active = "maximum" })).notice == MAX_ON, tostring(note(2))
end)

test("S2-10 no raw setting name in any text this change adds", function()
    local e, s = bootWith(fullEntry())
    CVARS.graphicsComputeEffects = "1"
    local function names(view)
        local list = { view.costNote or "", view.mattersNote or "", view.totalLine or "", view.yourLine or "", view.notice or "",
            view.locked or "" }
        for _, row in ipairs(view.rows) do
            list[#list + 1] = row.matters or ""
            for _, level in ipairs(row.levels) do list[#list + 1] = level.cost or "" end
        end
        if view.readOnly then
            list[#list + 1] = view.readOnly.text
            for _, button in ipairs(view.readOnly.buttons) do list[#list + 1] = button.text end
        end
        list[#list + 1] = view.profile.text
        return table.concat(list, "\n")
    end
    local costs = costsOf(e, fullEntry())
    local text = names(s.model({ page = "light" }, ctxOf(e, { costs = costs, maximum = { fps = 151.5, skipped = 0, leftOut = 2 },
        estimate = { fps = 94.4, counted = 2, notCounted = 2 } })))
        .. names(s.model({ page = "light" }, ctxOf(e, { active = "maximum", costs = costs, maximum = { skipped = 3, leftOut = 1 } })))
        .. names(s.model({ notice = NOTHING }, ctxOf(e, {})))
    local raw
    for _, name in ipairs(RAW) do
        if text:find(name, 1, true) then raw = name end
    end
    return raw == nil, tostring(raw)
end)

-- The live total (agreed 2026-11-02): "Your <tab> settings: about N fps", the estimate for the levels the tab holds.
local YOUR_TAIL = " (an estimate; settings affect each other)."
local NOT_COUNTED = "the test didn't measure the level you chose."
local function yourFS(f)
    local found
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text and fs._text:find("^Your %a+ settings: about") then found = fs end
        end
    end)
    return found
end
local function yourText(f)
    local fs = f and yourFS(f)
    return fs and fs._text
end

test("S3-1 the live total line: the tab's name, a whole number, the not-counted note in the singular and the plural; nothing without a test or a counted setting", function()
    local e, s = boot()
    local costs = costsOf(e, quietEntry())
    local function line(tab, estimate, withCosts)
        return s.model({ page = "light" }, ctxOf(e, { active = tab, costs = withCosts, estimate = estimate })).yourLine
    end
    local ok = line("everyday", { fps = 94.4, counted = 3, notCounted = 0 }, costs) == "Your Everyday settings: about 94 fps" .. YOUR_TAIL
        and line("crowded", { fps = 94.6, counted = 1, notCounted = 0 }, costs) == "Your Crowded settings: about 95 fps" .. YOUR_TAIL
        and line("everyday", { fps = 94.4, counted = 2, notCounted = 1 }, costs) == "Your Everyday settings: about 94 fps" .. YOUR_TAIL
            .. " 1 setting not counted: " .. NOT_COUNTED
        and line("everyday", { fps = 94.4, counted = 1, notCounted = 3 }, costs) == "Your Everyday settings: about 94 fps" .. YOUR_TAIL
            .. " 3 settings not counted: " .. NOT_COUNTED
    local none = line("everyday", { fps = 94.4, counted = 3, notCounted = 0 }, nil) == nil          -- no test to read
        and line("everyday", { fps = 94.4, counted = 0, notCounted = 2 }, costs) == nil               -- the tab holds nothing the test measured
        and line("everyday", nil, costs) == nil
        and line("everyday", { fps = 94.4, counted = 3, notCounted = 0 }, { kind = "quiet", fps = { nowFps = 250, byCvar = {} } }) == nil
    return ok and none, tostring(line("everyday", { fps = 94.4, counted = 2, notCounted = 1 }, costs))
end)

test("S3-2 through the window the estimate is recommend's for the levels the profile in use holds, and it follows every click and every switch", function()
    local e, s = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    -- in the game: Shadows 2 (now), SSAO 1 (-0.3 ms), clutter 64 (now), render scale 1 (now): 3.7 ms on a 4.0 ms baseline
    local start = yourText(f) == "Your Everyday settings: about 270 fps" .. YOUR_TAIL
    s.click("level:graphicsShadowQuality:4")                  -- +1.2 ms: 4.9 ms
    local one = yourText(f) == "Your Everyday settings: about 204 fps" .. YOUR_TAIL
    s.click("level:graphicsSSAO:4")                           -- +0.8 ms with the Shadows above: 6.0 ms
    local two = yourText(f) == "Your Everyday settings: about 167 fps" .. YOUR_TAIL
    s.click("profile:crowded")                                -- Crowded keeps Shadows 0; SSAO goes back to Original's 1: 2.7 ms
    local other = yourText(f) == "Your Crowded settings: about 370 fps" .. YOUR_TAIL
    s.click("level:graphicsSSAO:0")                           -- kept in Crowded and applied: -0.6 ms more, 2.4 ms
    local stored = yourText(f) == "Your Crowded settings: about 417 fps" .. YOUR_TAIL and CVARS.graphicsSSAO == "0"
    return start and one and two and other and stored and #OUT == 0,
        tostring(start) .. tostring(one) .. tostring(two) .. tostring(other) .. tostring(stored) .. tostring(yourText(f)) .. outText()
end)

test("S3-3 a setting the test did not measure at the held level is left out of the estimate and counted in the note", function()
    local e, s = bootWith(fullEntry())
    CVARS.RenderScale = "0.75"                                -- the test has 0.5 and 1 only
    s.open("everyday")
    local one = yourText(window()) == "Your Everyday settings: about 270 fps" .. YOUR_TAIL .. " 1 setting not counted: " .. NOT_COUNTED
    local e2, s2 = bootWith(quietEntry())                     -- clutter and render scale are not in this test at all
    s2.open("everyday")
    local two = yourText(window()) == "Your Everyday settings: about 270 fps" .. YOUR_TAIL .. " 2 settings not counted: " .. NOT_COUNTED
    return one and two, tostring(one) .. tostring(two) .. tostring(yourText(window()))
end)

test("S3-4 no line without a test or for a profile that keeps nothing, and the rest of the window still draws", function()
    local e, s = bootWith(nil)
    s.open("everyday")
    local noTest = not hasText(window(), "Your Everyday settings") and hasText(window(), COST_NONE)
    local e2, s2, db2 = bootWith(fullEntry())
    db2.profiles.crowded.values = {}
    s2.open("light")
    s2.click("profile:crowded")
    local f = window()
    local empty = not hasText(f, "Your Crowded settings") and hasText(f, COST_QUIET) and hasText(f, "Everything at the highest")
    s2.click("profile:everyday")
    local back = yourText(f) == "Your Everyday settings: about 270 fps" .. YOUR_TAIL
    local model = s2.model({ page = "light" }, ctxOf(e2, { active = "crowded", saved = { everyday = {}, crowded = {} },
        costs = costsOf(e2, fullEntry()), estimate = { fps = 250, counted = 3, notCounted = 0 } }))
    local keepsNothing = model.yourLine == nil
    -- the game holds only levels the test never measured: no line, it would only repeat today's frame rate (spec P8)
    local e3, s3, db3 = bootWith(quietEntry())
    db3.profiles.everyday.values = { graphicsShadowQuality = "4" }
    CVARS.graphicsShadowQuality, CVARS.graphicsSSAO = "4", "4"
    s3.open("light")
    local unmeasured = not hasText(window(), "Your Everyday settings") and hasText(window(), COST_QUIET)
    return noTest and empty and back and keepsNothing and unmeasured and #OUT == 0,
        tostring(noTest) .. tostring(empty) .. tostring(back) .. tostring(keepsNothing) .. tostring(unmeasured) .. outText()
end)

test("S3-5 an estimate that cannot be made leaves the window drawn, without the line and without a message", function()
    local e, s = bootWith(fullEntry())
    local real = e.ns.recommend.estimateFps
    e.ns.recommend.estimateFps = function(entry, values)
        if values.graphicsSSAO == "1" then error("boom") end          -- the held levels only: the Maximum estimate still works
        return real(entry, values)
    end
    s.open("everyday")
    local f = window()
    return f ~= nil and yourText(f) == nil and hasText(f, "Everything at the highest: about 152 fps.") and hasText(f, COST_QUIET)
        and #OUT == 0, tostring(yourText(f)) .. outText()
end)

-- The picture size block (spec 2026-11-02-one-saved-picture-size-design.md): the slider and the level buttons are two controls
-- for one saved setting, the picture sharpness of the tab shown.
local SIZE_WARNING = "Above 100% the game draws more pixels than your screen has. That can cost a lot of frame rate and graphics memory, "
    .. "and some graphics cards crash at high values."
local SIZE_SAFE = "If a size above 100% crashes the game when you enter the world, hold Shift while you enter: the addon then skips it for that session."
local NOTE_NONE = "Not kept in Everyday yet: drag the slider or click a size to keep it."
local NOTE_KEPT = "Kept in Everyday: the addon puts it back at every loading screen."
local SIZE_LEVELS = { "0.5", "0.6", "0.7", "0.8", "0.9", "1", "1.25", "1.5", "1.75", "2" }
local function drag(f, value)                       -- plays a drag to `value` and the release of the mouse button
    local slider = byKey(f, "size")
    slider._value = value
    slider.scripts.OnValueChanged(slider, value, true)
    slider.scripts.OnMouseUp(slider)
end
local function lit(f)                               -- the one size button highlighted, nil for none, "many" for more than one
    local found
    for _, value in ipairs(SIZE_LEVELS) do
        local button = byKey(f, "level:RenderScale:" .. value)
        if button and button.skinState.selected then
            if found then return "many" end
            found = value
        end
    end
    return found
end

test("S4-1 the picture size block shows the game's size: label, range, whether the profile in use keeps it, the warning and the Shift line above 100%, Back to 100% only off 100%, greyed when locked or read-only", function()
    local e, s = boot()
    local function size(over) return s.model({ page = "size" }, ctxOf(e, over)).size end
    local keeps = function(everyday, crowded) return { everyday = everyday or {}, crowded = crowded or {} } end
    local none = size({ size = { live = 100 } })
    local usedKept = size({ size = { live = 150 }, saved = keeps({ RenderScale = "1.5" }) })
    local locked = size({ size = { live = 150 }, saved = keeps({ RenderScale = "1.5" }), locked = "combat" })
    local crowdKept = size({ active = "crowded", size = { live = 80 }, saved = keeps(nil, { RenderScale = "0.8" }) })
    local maxi = size({ active = "maximum", size = { live = 100 }, want = { RenderScale = "1" } })
    local inUseDrift = size({ size = { live = 150 }, saved = keeps({ RenderScale = "0.8" }) })
    local skipped = size({ size = { live = 100 }, saved = keeps({ RenderScale = "1.5" }) })
    local settled = size({ size = { live = 100 }, saved = keeps({ RenderScale = "1" }) })
    local rounded = size({ size = { live = 115 } })
    local roundKept = size({ size = { live = 115 }, saved = keeps({ RenderScale = "1.15" }) })
    local maxiBig = size({ active = "maximum", size = { live = 150 }, want = {} })
    local low, high, near105 = size({ size = { live = 30 } }), size({ size = { live = 250 } }), size({ size = { live = 105 } })
    return none ~= nil and none.percent == 100 and none.label == "Picture sharpness right now: 100%" and none.min == 50 and none.max == 200
        and none.step == 5 and none.value == 100 and none.note == NOTE_NONE and none.warning == nil and none.safe == nil
        and none.canPutBack == false and none.enabled == true
        and usedKept.label == "Picture sharpness right now: 150%" and usedKept.note == NOTE_KEPT and usedKept.warning == SIZE_WARNING
        and usedKept.safe == SIZE_SAFE and usedKept.canPutBack == true and usedKept.value == 150
        and locked.enabled == false and locked.canPutBack == false
        and crowdKept.label == "Picture sharpness right now: 80%" and crowdKept.note == "Kept in Crowded: the addon puts it back at every loading screen."
        and crowdKept.value == 80 and crowdKept.canPutBack == true and crowdKept.warning == nil
        and maxi.enabled == false and maxi.canPutBack == false and maxi.note == nil and maxi.label == "Picture sharpness right now: 100%"
        and inUseDrift.note == "Kept in Everyday at 80%: the game has 150% now." and inUseDrift.canPutBack == true and inUseDrift.value == 150
        and skipped.note == "Kept in Everyday at 150%: the game has 100% now." and skipped.warning == SIZE_WARNING and skipped.safe == SIZE_SAFE
        and skipped.canPutBack == true and skipped.label == "Picture sharpness right now: 100%"
        and roundKept.note == NOTE_KEPT and roundKept.canPutBack == true
        and maxiBig.enabled == false and maxiBig.canPutBack == false and maxiBig.note == nil and maxiBig.warning == SIZE_WARNING
        and settled.note == NOTE_KEPT and settled.canPutBack == false and settled.warning == nil and settled.safe == nil
        and rounded.label == "Picture sharpness right now: 115%" and rounded.value == 115
        and low.value == 50 and low.label == "Picture sharpness right now: 30%" and high.value == 200 and high.warning == SIZE_WARNING
        and near105.warning == SIZE_WARNING
        and s.model({ page = "size" }, ctxOf(e, {})).size == nil, tostring(usedKept and usedKept.label) .. tostring(crowdKept and crowdKept.note)
end)

test("S4-2 the window draws the block; letting go of the slider keeps and applies the size like a button does, Back to 100% sets 100%, and nothing prints", function()
    local e, s, db = bootWith(fullEntry())
    s.open("size")
    local f = window()
    local slider = byKey(f, "size")
    local back = byKey(f, "sizeback")
    local first = slider ~= nil and slider.kind == "Slider" and slider._min == 50 and slider._max == 200 and slider._step == 5
        and slider._value == 100 and hasText(f, "Picture sharpness right now: 100%") and hasText(f, NOTE_NONE)
        and not hasText(f, SIZE_WARNING) and not hasText(f, SIZE_SAFE) and back ~= nil and back.enabled == false and back._text == "Back to 100%"
        and byKey(f, "keep:RenderScale"):GetChecked() == false
    SETLOG = {}
    drag(f, 150)
    local up = CVARS.RenderScale == "1.5" and db.profiles.everyday.values.RenderScale == "1.5" and db.want.RenderScale == "1.5"
        and hasText(f, "Picture sharpness right now: 150%") and hasText(f, SIZE_WARNING) and hasText(f, SIZE_SAFE) and hasText(f, NOTE_KEPT)
        and byKey(f, "sizeback").enabled == true and byKey(f, "size")._value == 150 and #SETLOG == 1 and SETLOG[1] == "RenderScale"
        and byKey(f, "keep:RenderScale"):GetChecked() == true and lit(f) == "1.5"
    byKey(f, "sizeback"):Click()
    local down = CVARS.RenderScale == "1" and db.profiles.everyday.values.RenderScale == "1" and hasText(f, "Picture sharpness right now: 100%")
        and not hasText(f, SIZE_WARNING) and not hasText(f, SIZE_SAFE) and byKey(f, "sizeback").enabled == false
        and byKey(f, "size")._value == 100 and lit(f) == "1"
    return first and up and down and #OUT == 0, tostring(first) .. tostring(up) .. tostring(down) .. outText()
end)

test("S4-3 the buttons and the slider always show the same size: a button moves the slider, the slider lights the button with its value, and no button is lit between two", function()
    local e, s, db = bootWith(fullEntry())
    s.open("size")
    local f = window()
    byKey(f, "level:RenderScale:0.8"):Click()
    local a = byKey(f, "size")._value == 80 and hasText(f, "Picture sharpness right now: 80%") and lit(f) == "0.8" and CVARS.RenderScale == "0.8"
    byKey(f, "level:RenderScale:1.75"):Click()
    local b = byKey(f, "size")._value == 175 and lit(f) == "1.75" and CVARS.RenderScale == "1.75" and hasText(f, SIZE_WARNING)
    drag(f, 90)
    local c = lit(f) == "0.9" and CVARS.RenderScale == "0.9" and byKey(f, "size")._value == 90
    drag(f, 165)
    local d = lit(f) == nil and CVARS.RenderScale == "1.65" and byKey(f, "keep:RenderScale"):GetChecked() == true
        and db.profiles.everyday.values.RenderScale == "1.65"
    drag(f, 125)
    local g = lit(f) == "1.25" and CVARS.RenderScale == "1.25"
    drag(f, 200)
    local h = lit(f) == "2" and CVARS.RenderScale == "2" and byKey(f, "size")._value == 200
    return a and b and c and d and g and h, tostring(a) .. tostring(b) .. tostring(c) .. tostring(d) .. tostring(g) .. tostring(h)
end)

test("S4-5 dragging only moves the label; nothing is written until the mouse button is released", function()
    local e, s, db = bootWith(fullEntry())
    s.open("size")
    local f = window()
    local slider = byKey(f, "size")
    SETLOG = {}
    slider._value = 175
    slider.scripts.OnValueChanged(slider, 175, true)
    local dragging = hasText(f, "Picture sharpness right now: 175%") and #SETLOG == 0 and CVARS.RenderScale == "1"
        and db.profiles.everyday.values.RenderScale == nil
    slider.scripts.OnMouseUp(slider)
    return dragging and CVARS.RenderScale == "1.75" and #SETLOG == 1 and db.profiles.everyday.values.RenderScale == "1.75",
        tostring(dragging) .. tostring(CVARS.RenderScale)
end)

test("S4-6 drawing the window never writes: a size between steps, or out of the slider's range, only moves the slider", function()
    local e, s, db = bootWith(fullEntry())
    CVARS.RenderScale = "1.3"
    SETLOG = {}
    s.open("size")
    local f = window()
    local mid = byKey(f, "size")._value == 130 and hasText(f, "Picture sharpness right now: 130%")
    CVARS.RenderScale = "0.3"
    s.open("size")
    local under = byKey(f, "size")._value == 50 and hasText(f, "Picture sharpness right now: 30%")
    CVARS.RenderScale = "1.15"
    s.open("size")
    local odd = byKey(f, "size")._value == 115 and hasText(f, "Picture sharpness right now: 115%")
    return mid and under and odd and #SETLOG == 0 and #OUT == 0 and db.profiles.everyday.values.RenderScale == nil,
        tostring(mid) .. tostring(under) .. tostring(odd) .. #SETLOG
end)

test("S4-7 the release rounds to the nearest step of 5 and keeps that", function()
    local e, s, db = bootWith(fullEntry())
    s.open("size")
    local f = window()
    drag(f, 152)
    local a = CVARS.RenderScale == "1.5" and db.profiles.everyday.values.RenderScale == "1.5"
    drag(f, 153)
    local b = CVARS.RenderScale == "1.55" and db.profiles.everyday.values.RenderScale == "1.55"
    s.click("size:46")
    s.click("size:205")
    local stray = CVARS.RenderScale == "1.55"
    return a and b and stray, tostring(CVARS.RenderScale)
end)

test("S4-8 in combat or during a test the slider and Back to 100% are greyed, and a stray click writes nothing", function()
    local e, s, db = bootWith(fullEntry())
    s.open("size")
    local f = window()
    drag(f, 150)
    COMBAT = true
    s.open("size")
    local greyed = byKey(f, "size").enabled == false and byKey(f, "sizeback").enabled == false
    SETLOG = {}
    s.click("size:200")
    s.click("sizeback")
    local still = #SETLOG == 0 and CVARS.RenderScale == "1.5" and db.profiles.everyday.values.RenderScale == "1.5"
    COMBAT = false
    return greyed and still, tostring(greyed) .. tostring(still) .. tostring(CVARS.RenderScale)
end)

test("S4-9 a client with no picture sharpness setting has no block", function()
    local e5 = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1", vsync = "0" }, { fresh = true })
    e5.ns.bench.now = function() return NOW end
    e5.ns.bench.state().history[1] = quietEntry()
    e5.ns.settings.open("size")
    local f = window()
    return f ~= nil and byKey(f, "size") == nil and byKey(f, "sizeback") == nil and not hasText(f, "Picture sharpness right now")
        and not hasText(f, NOTE_NONE)
end)

test("S4-10 a size the game will not take is said in the window, in plain words, and the slider shows what the game holds", function()
    local e, s = bootWith(fullEntry())
    s.open("size")
    local f = window()
    SETFAIL.RenderScale = "clamp"
    drag(f, 150)
    return hasText(f, "The game kept picture sharpness at 100% (you asked for 150%).") and CVARS.RenderScale == "1"
        and byKey(f, "size")._value == 100 and #OUT == 0, outText()
end)

test("S4-11 the keep tick and Save as Everyday keep the size the game has, above 100% too", function()
    local e, s, db = bootWith(fullEntry())
    s.open("size")
    drag(window(), 150)
    s.click("keep:RenderScale")                           -- untick: no longer kept, the size stays in the game
    local off = db.profiles.everyday.values.RenderScale == nil and db.want.RenderScale == nil and CVARS.RenderScale == "1.5"
        and hasText(window(), NOTE_NONE)
    s.click("keep:RenderScale")                           -- tick: the size the game has now is kept
    local on = db.profiles.everyday.values.RenderScale == "1.5" and db.want.RenderScale == "1.5" and CVARS.RenderScale == "1.5"
    CVARS.RenderScale = "1.75"
    s.click("save:everyday")
    local used = db.profiles.everyday.values.RenderScale == "1.75" and db.want.RenderScale == "1.75"
    return off and on and used, tostring(off) .. tostring(on) .. tostring(used)
end)

test("S4-12 the size card has the six levels the test measures and four above 100% it never measured; only the test's levels are measured, and the test's own list is untouched", function()
    local e, s = boot()
    local view = s.model({ page = "light" }, ctxOf(e, { costs = costsOf(e, fullEntry()) }))
    local row = rowOf(view, "RenderScale")
    local values, shorts, costs = {}, {}, {}
    for _, level in ipairs(row.levels) do
        values[#values + 1] = level.value
        shorts[#shorts + 1] = level.short
        costs[#costs + 1] = level.cost or "-"
    end
    local tiers
    for _, entry in ipairs(e.ns.bench.resolve()) do
        if entry.cvar == "RenderScale" then tiers = entry.tiers end
    end
    return table.concat(values, ",") == "0.5,0.6,0.7,0.8,0.9,1,1.25,1.5,1.75,2"
        and table.concat(shorts, ",") == "50%,60%,70%,80%,90%,100%,125%,150%,175%,200%"
        and row.levels[1].text == "50%" and row.levels[6].text == "100%" and row.levels[7].text == "125%"
        and costs[7] == "?" and costs[10] == "?" and costs[6] == "now"
        and tiers ~= nil and #tiers == 6 and tiers[6] == "1", table.concat(values, ",") .. " " .. table.concat(costs, ",")
end)

test("S4-13 the Picture size page is one full-width card: all ten size buttons share one line", function()
    local e, s = bootWith(fullEntry())
    s.open("size")
    local f = window()
    local ys, xs = {}, {}
    for _, value in ipairs(SIZE_LEVELS) do
        local button = byKey(f, "level:RenderScale:" .. value)
        if button then
            xs[#xs + 1] = button._point[4]
            ys[button._point[5]] = true
        end
    end
    local one = next(ys, next(ys)) == nil
    local last = byKey(f, "level:RenderScale:2")
    return #xs == 10 and one and xs[1] == 0 and last ~= nil and last._point[4] + last._width <= 675 and s.columnsFor(1) == 2,
        tostring(#xs) .. tostring(one) .. tostring(last and last._point[4])
end)

test("S4-14 on the Picture size page the block stands under the card: the label over the slider over the warning over the Shift line over the note, Back to 100% beside the slider, all above the summary", function()
    local e, s = bootWith(fullEntry())
    s.open("size")
    drag(window(), 150)
    STRINGHEIGHT = function(fs)
        local text = fs._text or ""
        local perLine = math.max(1, math.floor((fs._width or 520) / 9))
        return 14 * math.max(1, math.ceil(#text / perLine))
    end
    s.open("size")
    local f = window()
    local function textHas(part)
        local found
        walk(f, function(frame)
            for _, fs in ipairs(frame.fontStrings) do
                if fs.shown and fs._text and fs._text:find(part, 1, true) then found = fs end
            end
        end)
        return found
    end
    local label, warn, safe, note = fontStringWith(f, "Picture sharpness right now: 150%"), fontStringWith(f, SIZE_WARNING),
        fontStringWith(f, SIZE_SAFE), fontStringWith(f, NOTE_KEPT)
    local slider, back, card = byKey(f, "size"), byKey(f, "sizeback"), byKey(f, "level:RenderScale:1")
    local your = textHas("Your Everyday settings")
    local function top(item) return -item._point[5] end
    local ok = label ~= nil and warn ~= nil and safe ~= nil and note ~= nil and slider ~= nil and back ~= nil and card ~= nil
        and top(label) >= top(card) + 22 + 16 and top(slider) >= top(label) + STRINGHEIGHT(label)
        and top(warn) >= top(slider) + 16 and top(safe) >= top(warn) + STRINGHEIGHT(warn) and top(note) >= top(safe) + STRINGHEIGHT(safe)
        and back._point[4] >= slider._point[4] + slider._width and back._point[4] + back._width <= 675
    local fits = your == nil or 8 + top(note) + STRINGHEIGHT(note) <= 522 - (your._point[5] + STRINGHEIGHT(your))
    STRINGHEIGHT = nil
    return ok and fits, tostring(ok) .. tostring(fits)
end)

test("S6-12 a card's name that wraps pushes its help line and levels down: the help never sits on the name", function()
    local e, s = bootWith(fullEntry())
    STRINGHEIGHT = function(fs)
        local text = fs._text or ""
        local perLine = math.max(1, math.floor((fs._width or 520) / 9))
        return 14 * math.max(1, math.ceil(#text / perLine))
    end
    s.open("world")
    local f = window()
    local name = fontStringWith(f, "Grass and plants (exact amount)")
    local help = fontStringWith(f, "The same thing with a finer dial: 48 is sparse, 128 is lush.")
    local button = byKey(f, "level:groundEffectDensity:48")
    local ok = name ~= nil and help ~= nil and button ~= nil and STRINGHEIGHT(name) == 28 and -help._point[5] == -name._point[5] + 30
        and -button._point[5] >= -help._point[5] + STRINGHEIGHT(help)
    s.open("light")
    f = window()
    local plain = fontStringWith(f, "Shadow detail")                  -- one line: the help stays where it was
    local helpOne = fontStringWith(f, "How sharp and detailed shadows look. Higher looks better and costs a lot of speed.")
    local tight = plain ~= nil and helpOne ~= nil and -helpOne._point[5] == -plain._point[5] + 18
    STRINGHEIGHT = nil
    return ok and tight, tostring(ok) .. tostring(tight)
end)

test("S6-13 a level button and its cost have room: 50 pixels for the label, 58 for the cost, centred under it; six levels share one line in two columns", function()
    local e, s = bootWith(fullEntry())
    s.open("size")
    local f = window()
    local xs, ys = {}, {}
    for _, value in ipairs({ "0.5", "0.6", "0.7", "0.8", "0.9", "1" }) do
        local button = byKey(f, "level:RenderScale:" .. value)
        if button then
            xs[#xs + 1] = button._point[4]
            ys[button._point[5]] = true
        end
    end
    local oneLine = #xs == 6 and next(ys, next(ys)) == nil
    local button = byKey(f, "level:RenderScale:1")
    local text, cost = costFor(f, "RenderScale", "1")
    local roomy = button._width == 50 and button.label._width == 42 and text == "now" and cost._width == 58 and cost._wordWrap == false
        and cost._point[4] == button._point[4] - 4 and button._text == "100%" and #button._text * 6.5 <= button.label._width
    local widest = costFor(f, "RenderScale", "0.5")
    return oneLine and roomy and widest ~= nil and #widest * 6 <= 58, tostring(oneLine) .. tostring(roomy) .. tostring(widest)
end)

test("S8-6 a test or result button opens its page inside the window, which stays open; in combat nothing opens", function()
    local e, s = bootWith(fullEntry())
    local opened = {}
    e.ns.ui.openSaved = function(kind) opened[#opened + 1] = kind end
    e.ns.ui.buildContext = function() return { saved = { best = true, crowded = true } } end
    e.ns.ui.savedResult = function() return { measuredLine = "Measured in Elwynn Forest, 2 days ago." } end
    s.open("home")
    local f = window()
    byKey(f, "test:best"):Click()
    local test = table.concat(opened, ",") == "best" and f:IsShown()
    s.open("results")
    byKey(f, "show:crowded"):Click()
    local show = table.concat(opened, ",") == "best,crowded" and f:IsShown()
    COMBAT = true
    s.open("home")
    s.click("test:best")
    COMBAT = false
    local stays = #opened == 2 and f:IsShown()
    return test and show and stays, tostring(test) .. tostring(show) .. tostring(stays)
end)

-- Save as Everyday and Save as Crowded at the bottom of the page list (owner request 2026-11-02, spec H12).
local SAVE_CAPTION = "Save the game's current settings as:"
local function managedPresent(e)
    local n = 0
    for _, cvar in ipairs(e.ns.profiles.MANAGED) do
        if CVARS[cvar] ~= nil then n = n + 1 end
    end
    return n
end
local function savedLine(n, name) return "Saved " .. n .. (n == 1 and " setting" or " settings") .. " as " .. name .. "." end

test("S10-1 the page list ends with a caption and two buttons, Save as Everyday over Save as Crowded, on every page", function()
    local e, s = bootWith(fullEntry())
    local bad = {}
    for _, page in ipairs({ "home", "light", "world", "size", "tests", "about" }) do
        s.open(page)
        local f = window()
        local everyday, crowded = byKey(f, "save:everyday"), byKey(f, "save:crowded")
        local good = everyday ~= nil and crowded ~= nil and everyday._text == "Save as Everyday" and crowded._text == "Save as Crowded"
            and everyday._width == 126 and crowded._width == 126 and everyday._height == 28 and crowded._height == 28
            and crowded._point[1] == "BOTTOMLEFT" and crowded._point[4] == 12 and crowded._point[5] == 12
            and everyday._point[1] == "BOTTOMLEFT" and everyday._point[4] == 12 and everyday._point[5] == 46
            and everyday.label._justifyH == "CENTER" and everyday.label._justifyV == "MIDDLE"
            and crowded.label._justifyH == "CENTER" and crowded.label._justifyV == "MIDDLE" and hasText(f, SAVE_CAPTION)
        if not good then bad[#bad + 1] = page end
    end
    local caption = fontStringWith(window(), SAVE_CAPTION)
    local above = caption ~= nil and caption._point[1] == "BOTTOMLEFT" and caption._point[4] == 12 and caption._point[5] >= 46 + 28
    return #bad == 0 and above, table.concat(bad, ",") .. tostring(above)
end)

test("S10-2 a save button keeps the game's current settings in that profile and says so beside the buttons, silently; a size above 100% is saved as it is", function()
    local e, s, db = bootWith(fullEntry())
    local n = managedPresent(e)
    s.open("home")
    CVARS.graphicsShadowQuality = "3"
    OUT = {}
    byKey(window(), "save:everyday"):Click()
    local everyday = db.profiles.everyday.values.graphicsShadowQuality == "3" and hasText(window(), savedLine(n, "Everyday"))
        and not hasText(window(), SAVE_CAPTION) and #OUT == 0
    CVARS.graphicsShadowQuality = "1"
    byKey(window(), "save:crowded"):Click()
    local crowded = db.profiles.crowded.values.graphicsShadowQuality == "1" and hasText(window(), savedLine(n, "Crowded"))
        and not hasText(window(), "as Everyday.") and db.profiles.everyday.values.graphicsShadowQuality == "3" and #OUT == 0
    s.open("size")
    drag(window(), 150)
    byKey(window(), "save:crowded"):Click()
    local boosted = db.profiles.crowded.values.RenderScale == "1.5" and CVARS.RenderScale == "1.5"
    s.click("page:light")
    local gone = not hasText(window(), "Saved " .. n) and hasText(window(), SAVE_CAPTION)
    return everyday and crowded and boosted and gone, tostring(everyday) .. tostring(crowded) .. tostring(boosted) .. tostring(gone)
end)

test("S10-3 in combat the save buttons are greyed and a click saves nothing; an unknown save key does nothing", function()
    local e, s, db = bootWith(fullEntry())
    s.open("light")
    local beforeE, beforeC = db.profiles.everyday.values.graphicsShadowQuality, db.profiles.crowded.values.graphicsShadowQuality
    COMBAT = true
    CVARS.graphicsShadowQuality = "4"
    s.open("light")
    local f = window()
    local greyed = byKey(f, "save:everyday").enabled == false and byKey(f, "save:crowded").enabled == false
    s.click("save:everyday")
    s.click("save:crowded")
    COMBAT = false
    local quiet = db.profiles.everyday.values.graphicsShadowQuality == beforeE and db.profiles.crowded.values.graphicsShadowQuality == beforeC
        and not hasText(window(), "Saved ")
    s.click("save:maximum")
    s.click("save:nosuchprofile")
    local unknown = not hasText(window(), "Saved ") and db.profiles.maximum == nil and db.profiles.nosuchprofile == nil
    return greyed and quiet and unknown, tostring(greyed) .. tostring(quiet) .. tostring(unknown)
end)

test("S10-4 the model offers the two save buttons on every page, greyed when locked, with the confirmation the last click left", function()
    local e, s = boot()
    local function bar(st, locked) return s.model(st, ctxOf(e, { locked = locked })).saveBar end
    local plain = bar({ page = "home" })
    local locked = bar({ page = "about" }, "combat")
    local busy = bar({ page = "size" }, "busy")
    local said = bar({ page = "light", saved = "Saved 3 settings as Crowded." })
    return plain ~= nil and plain.caption == SAVE_CAPTION and #plain.buttons == 2 and plain.note == nil
        and plain.buttons[1].key == "save:everyday" and plain.buttons[1].text == "Save as Everyday" and plain.buttons[1].enabled == true
        and plain.buttons[2].key == "save:crowded" and plain.buttons[2].text == "Save as Crowded" and plain.buttons[2].enabled == true
        and locked.buttons[1].enabled == false and locked.buttons[2].enabled == false
        and busy.buttons[1].enabled == false and busy.buttons[2].enabled == false
        and said.note == "Saved 3 settings as Crowded." and said.buttons[1].enabled == true, tostring(plain and plain.caption)
end)

-- A save copies the game over what the profile held (the owner's report, 2026-11-02: Maximum in use, Save as Everyday copied the
-- game's 100% over an Everyday kept at 150%): the window says what it replaced.
test("S11-4 Save as says what it replaces: the setting, what the profile held and what it holds now; nothing when they were the same", function()
    local e, s, db = bootWith(fullEntry(), { active = "maximum" })
    local n = managedPresent(e)
    db.profiles.everyday.values.RenderScale = "1.5"
    s.open("size")
    byKey(window(), "save:everyday"):Click()
    local a = hasText(window(), savedLine(n, "Everyday")) and hasText(window(), "Picture sharpness was 150%, now 100%.")
        and db.profiles.everyday.values.RenderScale == "1" and db.active == "maximum" and #OUT == 0
    local e2, s2, db2 = bootWith(fullEntry())
    s2.open("size")
    drag(window(), 150)
    byKey(window(), "save:everyday"):Click()
    local quiet = hasText(window(), savedLine(managedPresent(e2), "Everyday")) and not hasText(window(), "was ")
    local e3, s3, db3 = bootWith(fullEntry(), { active = "maximum" })
    db3.profiles.everyday.values = { graphicsShadowQuality = "0", graphicsSSAO = "0", groundEffectDensity = "48", RenderScale = "0.5" }
    s3.open("light")
    byKey(window(), "save:everyday"):Click()
    local capped = hasText(window(), "Shadow detail was 0, now 2; Soft corner shadows was 0, now 1; Grass and plants (exact amount) was 48, now 64; and 1 more.")
    return a and quiet and capped, tostring(a) .. tostring(quiet) .. tostring(capped)
end)

-- My settings edits the profile in use (spec 2026-11-02-edit-the-profile-in-use-design.md): no tabs, no footer, a profile pill in
-- the header, and Original and Maximum shown read-only with a way out.
local READ_ONLY_MAX = "Maximum can't be changed. To change settings, edit:"
local function keysShown(f, prefix)
    local list = {}
    walk(f, function(frame)
        if frame.shown and frame.key and frame.key:sub(1, #prefix) == prefix then list[#list + 1] = frame.key end
    end)
    table.sort(list)
    return table.concat(list, ",")
end

test("ED-1 the model edits the profile in use: no tabs, no footer buttons, rows editable, the pill names the profile and its colour", function()
    local e, s = boot()
    local every = s.model({ page = "light" }, ctxOf(e, {}))
    local crowd = s.model({ page = "light" }, ctxOf(e, { active = "crowded" }))
    local orig = s.model({ page = "light" }, ctxOf(e, { active = "original" }))
    local maxi = s.model({ page = "light" }, ctxOf(e, { active = "maximum" }))
    local ok = every.tabs == nil and every.buttons == nil and every.readOnly == nil and rowOf(every, "graphicsShadowQuality").enabled == true
        and rowOf(every, "graphicsShadowQuality").kept == true
        and every.profile.key == "everyday" and every.profile.text == "Everyday" and every.profile.color == "profileEveryday"
        and crowd.profile.text == "Crowded" and crowd.profile.color == "profileCrowded" and rowOf(crowd, "graphicsShadowQuality").kept == true
        and orig.profile.text == "Original" and orig.profile.color == "profileOriginal"
        and maxi.profile.text == "Maximum" and maxi.profile.color == "profileMaximum"
    return ok, tostring(every.tabs) .. tostring(every.buttons) .. tostring(every.profile and every.profile.text)
end)

test("ED-2 with Maximum or Original in use the rows show the game's levels greyed, ticks follow what the profile holds, and a line offers Everyday and Crowded", function()
    local e, s = boot()
    CVARS.graphicsShadowQuality = "3"
    local maxi = s.model({ page = "light" }, ctxOf(e, { active = "maximum", want = { graphicsShadowQuality = "4" } }))
    local orig = s.model({ page = "light" }, ctxOf(e, { active = "original" }))
    local locked = s.model({ page = "light" }, ctxOf(e, { active = "maximum", locked = "combat" }))
    local row = rowOf(maxi, "graphicsShadowQuality")
    local ro = maxi.readOnly
    local ok = row.enabled == false and selectedOf(row) == "3" and row.kept == true and rowOf(maxi, "graphicsSSAO").kept == false
        and ro ~= nil and ro.text == READ_ONLY_MAX and #ro.buttons == 2
        and ro.buttons[1].key == "edit:everyday" and ro.buttons[1].text == "Everyday" and ro.buttons[1].color == "profileEveryday" and ro.buttons[1].enabled == true
        and ro.buttons[2].key == "edit:crowded" and ro.buttons[2].text == "Crowded" and ro.buttons[2].color == "profileCrowded"
        and orig.readOnly.text == "Original can't be changed. To change settings, edit:" and rowOf(orig, "graphicsShadowQuality").enabled == false
        and rowOf(orig, "graphicsShadowQuality").kept == false
        and locked.readOnly.buttons[1].enabled == false and locked.readOnly.buttons[2].enabled == false
        and (maxi.notice or ""):find("Switch to Everyday or Crowded", 1, true) == nil and orig.notice == nil
    return ok, tostring(ro and ro.text) .. " / " .. tostring(maxi.notice) .. " / " .. tostring(orig.notice)
end)

test("ED-3 the estimate line is for the profile in use, and only for Everyday or Crowded; the size block follows the same rule", function()
    local e, s = boot()
    local entry = quietEntry()
    local est = { fps = 240, counted = 1, notCounted = 0 }
    local crowd = s.model({ page = "size" }, ctxOf(e, { active = "crowded", costs = costsOf(e, entry), estimate = est, size = { live = 100 } }))
    local maxi = s.model({ page = "size" }, ctxOf(e, { active = "maximum", costs = costsOf(e, entry), estimate = est, size = { live = 100 },
        want = { graphicsShadowQuality = "4" } }))
    local orig = s.model({ page = "size" }, ctxOf(e, { active = "original", costs = costsOf(e, entry), estimate = est, size = { live = 100 } }))
    return (crowd.yourLine or ""):find("Your Crowded settings: about 240 fps", 1, true) ~= nil and maxi.yourLine == nil and orig.yourLine == nil
        and crowd.size.enabled == true and crowd.size.label == "Picture sharpness right now: 100%"
        and maxi.size.enabled == false and maxi.size.canPutBack == false and maxi.size.note == nil and maxi.size.label == "Picture sharpness right now: 100%"
        and maxi.size.where == nil and crowd.size.where == nil, tostring(crowd.yourLine) .. " / " .. tostring(maxi.size and maxi.size.note)
end)

test("ED-4 the window has no tabs and no footer; the header pill shows the profile in use in its colour and opens Home, in combat too", function()
    local e, s, db = bootWith(fullEntry())
    s.open("light")
    local f = window()
    local pill = byKey(f, "pill")
    local function dotColour(frame)
        for _, tex in ipairs(frame.dot.textures) do
            if tex._texture then return tex._vertex end
        end
    end
    local bare = keysShown(f, "tab:") == "" and byKey(f, "use") == nil and byKey(f, "maximum") == nil and byKey(f, "switch") == nil
    local shown = pill ~= nil and pill.label._text == "Everyday" and pill.dot ~= nil
        and pill._point[1] == "RIGHT" and pill._point[2] == f.close and pill._point[3] == "LEFT" and pill._point[4] == -8
    local r, g, b = e.ns.skin.color("profileEveryday")
    local c = dotColour(pill)
    local coloured = c ~= nil and c[1] == r and c[2] == g and c[3] == b
    COMBAT = true
    pill:Click()
    local home = s.state().page == "home" and hasText(window(), "In use now: Everyday")
    COMBAT = false
    s.click("profile:crowded")
    pill = byKey(window(), "pill")
    local r2 = e.ns.skin.color("profileCrowded")
    local follows = pill.label._text == "Crowded" and dotColour(pill)[1] == r2
    return bare and shown and coloured and home and follows, tostring(bare) .. tostring(shown) .. tostring(coloured) .. tostring(home) .. tostring(follows)
end)

test("ED-5 a level click, a tick and the slider change the profile in use and the game at once; with Crowded in use, Crowded", function()
    local e, s, db = bootWith(fullEntry())
    db.active = "crowded"
    db.want = e.ns.profiles.plan("crowded").want
    s.open("light")
    byKey(window(), "level:graphicsShadowQuality:3"):Click()
    local level = db.profiles.crowded.values.graphicsShadowQuality == "3" and CVARS.graphicsShadowQuality == "3"
        and db.profiles.everyday.values.graphicsShadowQuality == "2"
    s.click("page:size")
    drag(window(), 150)
    local size = db.profiles.crowded.values.RenderScale == "1.5" and CVARS.RenderScale == "1.5" and db.profiles.everyday.values.RenderScale == nil
    return level and size and #OUT == 0, tostring(level) .. tostring(size)
end)

test("ED-6 with Maximum in use the page says so with Everyday and Crowded buttons, nothing on it can be changed, and Crowded switches to Crowded", function()
    local e, s, db = bootWith(fullEntry(), { active = "maximum" })
    s.open("light")
    local f = window()
    local every, crowd = byKey(f, "edit:everyday"), byKey(f, "edit:crowded")
    local shown = hasText(f, READ_ONLY_MAX) and every ~= nil and crowd ~= nil and every._text == "Everyday" and crowd._text == "Crowded"
        and every.dot ~= nil and crowd.dot ~= nil and byKey(f, "level:graphicsShadowQuality:3").enabled == false
        and byKey(f, "keep:graphicsShadowQuality").enabled == false
    -- the game's level still shows, greyed (the fresh review of 2026-11-02, finding 1)
    local held = byKey(f, "level:graphicsShadowQuality:" .. CVARS.graphicsShadowQuality)
    local other = byKey(f, "level:graphicsShadowQuality:" .. (CVARS.graphicsShadowQuality == "0" and "1" or "0"))
    local selR = e.ns.skin.color("selected")
    local fillR = e.ns.skin.color("fill")
    shown = shown and held.bg._color[1] == selR and other.bg._color[1] == fillR
    local before = CVARS.graphicsShadowQuality
    s.click("level:graphicsShadowQuality:0")
    s.click("keep:graphicsSSAO")
    s.click("page:size")
    local sized = byKey(window(), "size").enabled == false and byKey(window(), "sizeback").enabled == false
        and not hasText(window(), "Kept in") and not hasText(window(), "Not kept")
    s.click("page:home")
    sized = sized and not hasText(window(), READ_ONLY_MAX) and byKey(window(), "edit:everyday") == nil
    s.click("page:size")
    s.click("size:150")
    s.click("sizeback")
    local untouched = CVARS.graphicsShadowQuality == before and CVARS.RenderScale == "1" and db.profiles.everyday.values.graphicsShadowQuality == "2"
        and db.profiles.everyday.values.RenderScale == nil and db.active == "maximum"
    COMBAT = true
    s.click("page:light")
    local greyed = byKey(window(), "edit:crowded").enabled == false
    s.click("edit:crowded")
    local stays = db.active == "maximum"
    COMBAT = false
    s.click("page:light")
    byKey(window(), "edit:crowded"):Click()
    f = window()
    local switched = db.active == "crowded" and not hasText(f, READ_ONLY_MAX) and byKey(f, "edit:crowded") == nil
        and byKey(f, "pill").label._text == "Crowded" and byKey(f, "level:graphicsShadowQuality:3").enabled == true and #OUT == 0
    return shown and sized and untouched and greyed and stays and switched,
        tostring(shown) .. tostring(sized) .. tostring(untouched) .. tostring(greyed) .. tostring(stays) .. tostring(switched)
end)

test("ED-7 the Home cards carry the profile dots; the old tab, Use, Switch and Maximum keys do nothing", function()
    local e, s, db = bootWith(fullEntry())
    s.open("home")
    local f = window()
    local ok = true
    for key, colour in pairs({ original = "profileOriginal", everyday = "profileEveryday", crowded = "profileCrowded", maximum = "profileMaximum" }) do
        local card = byKey(f, "profile:" .. key)
        local r = e.ns.skin.color(colour)
        local found
        for _, tex in ipairs(card and card.dot and card.dot.textures or {}) do
            if tex._texture then found = tex._vertex end
        end
        ok = ok and found ~= nil and found[1] == r
    end
    local before = copyOf(db.profiles.everyday.values)
    CVARS.graphicsShadowQuality = "4"
    for _, key in ipairs({ "tab:crowded", "use", "switch", "maximum" }) do s.click(key) end
    local inert = db.active == "everyday" and sameTable(before, db.profiles.everyday.values)
    return ok and inert, tostring(ok) .. tostring(inert)
end)

test("ED-8 without the footer the summary block sits at the bottom of the page", function()
    local e, s = bootWith(fullEntry())
    s.open("light")
    local f = window()
    local matters = fontStringWith(f, MATTERS_NOTE)
    return matters ~= nil and matters._point[1] == "BOTTOMLEFT" and matters._point[5] == 12, tostring(matters and matters._point[5])
end)

-- The Home page (spec 2026-11-02-flat-hub-window-design.md section 5).
test("S8-5 a Home profile click says what the game refused, or that the profile holds nothing, in the banner and not in chat", function()
    local e, s, db = bootWith(fullEntry())
    db.profiles.crowded.values = { graphicsShadowQuality = "0" }
    s.open("home")
    SETFAIL.graphicsShadowQuality = "clamp"
    OUT = {}
    byKey(window(), "profile:crowded"):Click()
    local refused = hasText(window(), "The game would not take the level you saved for: Shadow detail.") and #OUT == 0
    SETFAIL.graphicsShadowQuality = nil
    db.profiles.everyday.values = {}
    byKey(window(), "profile:everyday"):Click()
    local empty = hasText(window(), "Everyday has no saved settings yet: pick some on the settings pages.") and #OUT == 0
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    byKey(window(), "profile:crowded"):Click()
    local quiet = not hasText(window(), "no saved settings") and not hasText(window(), "would not take") and #OUT == 0
    return refused and empty and quiet, tostring(refused) .. tostring(empty) .. tostring(quiet)
end)
test("S8-1 Home names the profile in use and shows four profile cards with their notes, centred, the one in use marked, and the test the costs come from", function()
    local e, s = bootWith(fullEntry())
    s.open("home")
    local f = window()
    local want = { original = { "Original", "my own settings, hands off" }, everyday = { "Everyday", "normal play" },
        crowded = { "Crowded", "raids and busy cities" }, maximum = { "Maximum", "everything at its highest" } }
    local ok = hasText(f, "In use now: Everyday") and hasText(f, COST_QUIET)
    local bad = {}
    for key, pair in pairs(want) do
        local card = byKey(f, "profile:" .. key)
        local good = card ~= nil and card._text == pair[1] and card.note ~= nil and card.note._text:find(pair[2], 1, true) ~= nil
            and card._width == 328 and card.label._point[1] == "CENTER" and card.label._justifyH == "CENTER" and card.note._justifyH == "CENTER"
        if not good then bad[#bad + 1] = key end
    end
    ok = ok and #bad == 0 and byKey(f, "profile:everyday").skinState.selected == true and byKey(f, "profile:crowded").skinState.selected == false
        and byKey(f, "tab:everyday") == nil and byKey(f, "use") == nil and not hasText(f, "Everything at the highest")
    -- two by two: 306 pixels between the columns, 64 between the rows, each 56 tall
    local original, everyday, crowded = byKey(f, "profile:original"), byKey(f, "profile:everyday"), byKey(f, "profile:crowded")
    local grid = everyday._point[4] - original._point[4] == 346 and everyday._point[5] == original._point[5]
        and -crowded._point[5] - -original._point[5] == 64 and crowded._point[4] == original._point[4] and original._height == 56
    s.click("page:light")
    local elsewhere = byKey(f, "profile:original") == nil and byKey(f, "test:best") == nil and not hasText(f, "In use now")
    return ok and grid and elsewhere, table.concat(bad, ",") .. tostring(ok) .. tostring(grid) .. tostring(elsewhere)
end)

test("S8-2 Maximum shows about N fps only when the test measured it; with nothing to set a click says why in the banner", function()
    local e, s = bootWith(fullEntry())
    e.ns.ui.buildContext = function() return { saved = {}, maxFps = 151.5 } end
    s.open("home")
    local fps = byKey(window(), "profile:maximum").note._text == "everything at its highest (about 152 fps)"
    e.ns.ui.buildContext = function() return { saved = {} } end
    s.open("home")
    local none = byKey(window(), "profile:maximum").note._text == "everything at its highest"
    e.ns.ui.buildContext = function() error("boom") end        -- the menu's facts cannot be read: the page still draws, silently
    OUT = {}
    s.open("home")
    local guarded = byKey(window(), "profile:maximum") ~= nil and byKey(window(), "profile:maximum").note._text == "everything at its highest"
        and #OUT == 0
    local e2 = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1", vsync = "0" }, { fresh = true })     -- no levels learned here
    local s2, db2 = e2.ns.settings, e2.ns.profiles.state()
    local before = db2.active
    s2.open("home")
    SETLOG, OUT = {}, {}
    s2.click("profile:maximum")
    local refused = hasText(window(), NOTHING) and db2.active == before and #SETLOG == 0 and #OUT == 0
    return fps and none and guarded and refused, tostring(fps) .. tostring(none) .. tostring(guarded) .. tostring(refused)
end)

test("S8-3 a profile click switches silently and the page follows; in combat the cards are greyed and a click does nothing", function()
    local e, s, db = bootWith(fullEntry())
    s.open("home")
    local f = window()
    OUT = {}
    byKey(f, "profile:crowded"):Click()
    local switched = db.active == "crowded" and byKey(f, "profile:crowded").skinState.selected == true
        and byKey(f, "profile:everyday").skinState.selected == false and hasText(f, "In use now: Crowded") and #OUT == 0
    byKey(f, "profile:original"):Click()
    local original = db.active == "original" and hasText(f, "In use now: Original") and byKey(f, "pill").label._text == "Original"
    COMBAT = true
    s.open("home")
    local greyed = byKey(f, "profile:everyday").enabled == false and byKey(f, "profile:maximum").enabled == false
    SETLOG = {}
    s.click("profile:everyday")
    local still = db.active == "original" and #SETLOG == 0
    COMBAT = false
    return switched and original and greyed and still, tostring(switched) .. tostring(original) .. tostring(greyed) .. tostring(still)
end)

test("S8-4 the test buttons open the existing windows, are marked when a result is saved, and are greyed in combat or during a test", function()
    local e, s = bootWith(fullEntry())
    local opened = {}
    e.ns.ui.openSaved = function(kind) opened[#opened + 1] = kind end
    e.ns.ui.buildContext = function() return { saved = { best = true, crowded = false } } end
    s.open("home")
    local f = window()
    local best, crowded = byKey(f, "test:best"), byKey(f, "test:crowded")
    local drawn = best ~= nil and crowded ~= nil and best._text == "Find my best settings" and crowded._text == "Find my crowded settings"
        and best._width == 230 and best._height == 26 and best.skinState.selected == true and crowded.skinState.selected == false
        and best.enabled == true and crowded.enabled == true
    local noted = hasText(f, "A highlighted button has a saved result.")
    best:Click()
    crowded:Click()
    s.click("test:nosuch")
    local routed = table.concat(opened, ",") == "best,crowded"
    COMBAT = true
    s.open("home")
    local greyed = byKey(f, "test:best").enabled == false and byKey(f, "test:crowded").enabled == false
    s.click("test:best")
    COMBAT = false
    return drawn and noted and routed and greyed and #opened == 2, tostring(drawn) .. tostring(noted) .. tostring(routed) .. tostring(greyed) .. #opened
end)

-- Find my settings and My results (spec 2026-11-03-tests-and-results-in-my-settings-design.md M1-M3) and the About page.
local TESTS_INTRO = "The test measures what each graphics setting costs on this PC. Run it in a quiet spot first, then in a busy place."
local RESULTS_INTRO = "The results of your tests. Show one to see what each setting costs and to save its settings."
local NO_RESULTS = "No results yet: run Find my best settings first."

test("S9-1 My results with no result open: a line and a Show results button for each saved result, and the progress line while a test runs", function()
    local e, s = bootWith(fullEntry())
    local opened = {}
    e.ns.ui.openSaved = function(kind) opened[#opened + 1] = kind end
    e.ns.ui.buildContext = function() return { saved = { best = true, crowded = false } } end
    e.ns.ui.savedResult = function(kind)
        if kind == "best" then return { measuredLine = "Measured in Highmountain, 3 days ago." } end
    end
    s.open("results")
    local f = window()
    local drawn = hasText(f, RESULTS_INTRO) and countText(f, "My results") == 1
        and hasText(f, "Quiet-spot test: Measured in Highmountain, 3 days ago.") and hasText(f, "Crowd test: not done yet.")
        and byKey(f, "show:best") ~= nil and byKey(f, "show:best")._text == "Show results" and byKey(f, "show:crowded") == nil
        and not hasText(f, "A test is running") and not hasText(f, NO_RESULTS)
    byKey(f, "show:best"):Click()
    s.click("show:crowded")                                 -- nothing saved: nothing opens
    local routed = table.concat(opened, ",") == "best"
    e.ns.ui.savedResult = function() return { measuredLine = "Measured in Stormwind City, 2 hours ago." } end
    s.open("results")
    byKey(f, "show:crowded"):Click()
    routed = routed and table.concat(opened, ",") == "best,crowded" and hasText(f, "Crowd test: Measured in Stormwind City, 2 hours ago.")
    e.ns.ui.buildContext = function()
        return { saved = {}, active = true, progress = { phase = "sweep", label = "Shadows 3", cvar = "graphicsShadowQuality", value = "3", done = 12, total = 45 } }
    end
    s.open("results")
    local running = hasText(f, "A test is running: step 12 of 45 (Now testing: Shadow detail, level 3)")
    e.ns.ui.savedResult = function() error("boom") end        -- the saved results cannot be read: the page still draws, silently
    OUT = {}
    s.open("results")
    local go
    walk(f, function(frame) if frame.shown and frame._text == "Go to Find my settings" then go = frame end end)
    local guarded = hasText(f, "Quiet-spot test: not done yet.") and #OUT == 0 and hasText(f, NO_RESULTS) and go ~= nil and go.key == "page:test"
    s.click("page:light")
    local elsewhere = byKey(f, "show:best") == nil and not hasText(f, RESULTS_INTRO) and not hasText(f, "A test is running")
    return drawn and routed and running and guarded and elsewhere,
        tostring(drawn) .. tostring(routed) .. tostring(running) .. tostring(guarded) .. tostring(elsewhere)
end)

test("P-2 Find my settings with no test open: the intro and the two test buttons, which open that test's start; greyed in combat", function()
    local e, s = bootWith(fullEntry())
    local opened = {}
    e.ns.guide.open = function(kind) opened[#opened + 1] = kind end
    s.open("test")
    local f = window()
    local best, crowd = byKey(f, "run:setup"), byKey(f, "run:crowd")
    local drawn = countText(f, "Find my settings") == 1 and hasText(f, TESTS_INTRO) and best ~= nil and crowd ~= nil
        and best._text == "Find my best settings" and crowd._text == "Find my crowded settings" and byKey(f, "test:best") == nil
    best:Click()
    crowd:Click()
    COMBAT = true
    s.open("test")
    local greyed = byKey(f, "run:setup").enabled == false
    s.click("run:setup")
    COMBAT = false
    return drawn and table.concat(opened, ",") == "setup,crowd" and greyed and f:IsShown(), table.concat(opened, ",")
end)

test("P-7 a page with a test or a result open hands its host to the guide or the results, hides the choosers and the banner there", function()
    local e, s = bootWith(fullEntry())
    local drawnInto = {}
    e.ns.guide.hasView = function() return true end
    e.ns.guide.renderPage = function(host) drawnInto.test = host end
    e.ns.results.hasOffer = function() return true end
    e.ns.results.renderPage = function(host) drawnInto.results = host end
    COMBAT = true                                           -- the combat line would stand in the banner on another page
    s.open("test")
    local f = window()
    local testHost = s.host("test")
    local onTest = drawnInto.test == testHost and testHost.shown and byKey(f, "run:setup") == nil and not hasText(f, TESTS_INTRO)
        and not hasText(f, "You are in combat") and countText(f, "Find my settings") == 0
    s.open("results")
    local resultsHost = s.host("results")
    local onResults = drawnInto.results == resultsHost and resultsHost.shown and not testHost.shown and byKey(f, "show:best") == nil
        and not hasText(f, RESULTS_INTRO)
    s.open("home")
    COMBAT = false
    local away = not testHost.shown and not resultsHost.shown
    return onTest and onResults and away, tostring(onTest) .. tostring(onResults) .. tostring(away)
end)

test("P-8 each page host is one frame in the page area, under the window, the width of the area, the same frame every time", function()
    local e, s = bootWith(fullEntry())
    s.open("test")
    local a, b = s.host("test"), s.host("test")
    local c = s.host("results")
    return a ~= nil and a == b and c ~= nil and c ~= a and a._width == 675 and a._point ~= nil and a._point[1] == "TOPLEFT"
        and a._point[4] == 0 and a._point[5] == 0 and s.host("light") == nil, tostring(a and a._width)
end)

test("P-RUN-1 while a test runs the window stays on Find my settings: the other pages, the pill and the save bar are greyed and do nothing", function()
    local e, s, db = bootWith(fullEntry())
    local running = false
    e.ns.guide.running = function() return running end
    s.open("light")
    running = true                                         -- a test starts while the window shows Light and shadows
    s.redraw()
    local f = window()
    local pages = {}
    for _, item in ipairs(s.PAGES) do pages[#pages + 1] = item.key .. "=" .. tostring(byKey(f, "page:" .. item.key).enabled) end
    local onTest = byKey(f, "page:test").skinState.selected == true
    s.open("about")
    s.click("page:home")
    s.click("pill")
    local stayed = byKey(f, "page:test").skinState.selected == true
    local greyed = byKey(f, "pill").enabled == false and byKey(f, "save:everyday").enabled == false
    running = false
    s.open()                                               -- the run is over: the window is still on its page, not on About
    stayed = stayed and byKey(f, "page:test").skinState.selected == true
    s.open("about")
    local free = byKey(f, "page:about").skinState.selected == true and byKey(f, "page:home").enabled == true and byKey(f, "pill").enabled == true
    return onTest and stayed and greyed and free and table.concat(pages, ",") == "home=false,light=false,world=false,size=false,test=true,results=false,about=false",
        table.concat(pages, ",") .. " " .. tostring(onTest) .. tostring(stayed) .. tostring(greyed) .. tostring(free)
end)

-- The fresh review of 2026-11-03, finding 3: the greyed pill has to look greyed.
test("P-RUN-3 while a test runs the pill's name and dot are in the disabled colour; afterwards they are back", function()
    local e, s = bootWith(fullEntry())
    local running = true
    e.ns.guide.running = function() return running end
    s.open("test")
    local pill = byKey(window(), "pill")
    local dr = e.ns.skin.color("textDisabled")
    local function dotRed()
        for _, tex in ipairs(pill.dot.textures) do
            if tex._texture then return tex._vertex[1] end
        end
    end
    local greyed = pill.label._textColor[1] == dr and dotRed() == dr
    running = false
    s.open("test")
    local br = e.ns.skin.color("bright")
    local back = pill.label._textColor[1] == br and dotRed() == e.ns.skin.color("profileEveryday")
    return greyed and back, tostring(greyed) .. tostring(back)
end)

test("P-RUN-2 while a test runs the close button, Escape and closing from code do nothing; afterwards they close the window again", function()
    local e, s = bootWith(fullEntry())
    local running = true
    e.ns.guide.running = function() return running end
    s.open("test")
    local f = window()
    local function listed()
        for _, name in ipairs(UISpecialFrames) do if name == "ForeverSettingsSettings" then return true end end
        return false
    end
    local escapeOff = not listed()
    f.close:Click()
    local afterX = f:IsShown()
    s.click("close")
    s.hide()
    local afterCode = f:IsShown()
    running = false
    s.open("test")
    local escapeOn = listed()
    f.close:Click()
    return escapeOff and afterX and afterCode and escapeOn and not f:IsShown(),
        tostring(escapeOff) .. tostring(afterX) .. tostring(afterCode) .. tostring(escapeOn)
end)

test("P-6 closing the window ends the results' offer; a page switch keeps it", function()
    local e, s = bootWith(fullEntry())
    local ended = 0
    e.ns.results.endOffer = function() ended = ended + 1 end
    s.open("results")
    s.click("page:light")
    local kept = ended == 0
    window().close:Click()
    return kept and ended == 1, tostring(ended)
end)

test("S9-2 About shows the version, what the addon does, the chat commands and the no-data sentence; the header carries the version", function()
    GetAddOnMetadata = function() return "0.9.1" end
    local e, s = bootWith(fullEntry())
    s.open("about")
    local f = window()
    local drawn = hasText(f, "Version 0.9.1") and hasText(f, "ForeverSettings finds the graphics settings that fit your PC")
        and hasText(f, "/fset settings") and hasText(f, "/fset profile") and hasText(f, "/fset size") and hasText(f, "/fset probe")
        and hasText(f, "/fset reset") and hasText(f, "It doesn't collect or send anything.") and hasText(f, "open an issue on GitHub")
        and f.versionText._text == "Version 0.9.1"
    GetAddOnMetadata = nil
    local e2, s2 = bootWith(fullEntry())
    s2.open("about")
    local f2 = window()
    local unknown = hasText(f2, "Version unknown") and f2.versionText._text == ""
    s2.click("page:light")
    local elsewhere = not hasText(f2, "It doesn't collect or send anything.")
    return drawn and unknown and elsewhere, tostring(drawn) .. tostring(unknown) .. tostring(elsewhere)
end)

-- The Picture size page and dynamic render scale (spec 2026-11-02-flat-hub-window-design.md section 5).
local DYNAMIC_OFF = "Dynamic render scale is off."
local DYNAMIC_ON = "Dynamic render scale is on. It changes the picture size by itself, which spoils a test. Turn it off in the game's graphics menu."

test("S7-1 the model words the dynamic render scale line for both states and says nothing without the setting", function()
    local e, s = boot()
    local function line(dynamic) return s.model({ page = "light" }, ctxOf(e, { dynamicScale = dynamic })).dynamicLine end
    return line({ on = false }) == DYNAMIC_OFF and line({ on = true }) == DYNAMIC_ON and line(nil) == nil, tostring(line({ on = true }))
end)

test("S7-2 the Picture size page has the sharpness card, the slider block and the dynamic render scale line, read from the game; other pages do not show it", function()
    local e, s = bootWith(fullEntry())
    CVARS.dynamicRenderScale = "0"
    s.open("size")
    local f = window()
    local page = byKey(f, "level:RenderScale:1") ~= nil and byKey(f, "size") ~= nil and byKey(f, "sizeback") ~= nil
        and hasText(f, "Picture sharpness") and hasText(f, "Picture sharpness right now: 100%")
    local warnR, warnG, warnB = e.ns.skin.color("warning")
    local dimR, dimG, dimB = e.ns.skin.color("dim")
    local offFs = fontStringWith(f, DYNAMIC_OFF)
    local off = hasText(f, DYNAMIC_OFF) and not hasText(f, DYNAMIC_ON) and offFs._textColor[1] == dimR and offFs._textColor[2] == dimG
        and offFs._textColor[3] == dimB
    CVARS.dynamicRenderScale = "1"
    s.open("size")
    local onFs = fontStringWith(f, DYNAMIC_ON)
    local on = hasText(f, DYNAMIC_ON) and not hasText(f, DYNAMIC_OFF) and onFs._textColor[1] == warnR and onFs._textColor[2] == warnG
        and onFs._textColor[3] == warnB
    CVARS.dynamicRenderScale = "2"
    s.open("size")
    local anyNumber = hasText(f, DYNAMIC_ON)
    s.open("light")
    local elsewhere = not hasText(f, DYNAMIC_ON) and not hasText(f, DYNAMIC_OFF)
    local e2, s2 = bootWith(fullEntry())                        -- a client without the setting
    s2.open("size")
    local absent = not hasText(window(), "Dynamic render scale")
    return page and off and on and anyNumber and elsewhere and absent, tostring(page) .. tostring(off) .. tostring(on) .. tostring(anyNumber)
        .. tostring(elsewhere) .. tostring(absent)
end)

-- The pages of the hub window (spec 2026-11-02-flat-hub-window-design.md H5 and section 6).
test("S5-1 the pages and their order; the model lists them with the current one selected, Home when none is chosen", function()
    local e, s = boot()
    local keys, texts = {}, {}
    for _, p in ipairs(s.PAGES) do keys[#keys + 1] = p.key texts[#texts + 1] = p.text end
    local function selected(view)
        local list = {}
        for _, p in ipairs(view.pages) do if p.selected then list[#list + 1] = p.key end end
        return table.concat(list, ",")
    end
    local none = s.model({}, ctxOf(e, {}))
    local size = s.model({ page = "size" }, ctxOf(e, {}))
    local bogus = s.model({ page = "nosuchpage" }, ctxOf(e, {}))
    local listed = {}
    for _, p in ipairs(size.pages) do listed[#listed + 1] = p.key .. ":" .. p.text end
    return table.concat(keys, ",") == "home,light,world,size,test,results,about"
        and table.concat(texts, "|") == "Home|Light and shadows|World detail|Picture size|Find my settings|My results|About"
        and table.concat(listed, "|") == "home:Home|light:Light and shadows|world:World detail|size:Picture size|test:Find my settings|results:My results|about:About"
        and none.page == "home" and selected(none) == "home" and size.page == "size" and selected(size) == "size"
        and bogus.page == "home" and selected(bogus) == "home", table.concat(listed, "|")
end)

test("S5-2 every known setting sits on exactly one page by the table, and a setting the table does not know sits on World detail", function()
    local e, s = boot()
    local want = { graphicsShadowQuality = "light", graphicsSSAO = "light", graphicsComputeEffects = "light", giQuality = "light",
        graphicsLightMode = "light", graphicsGroundClutter = "world", groundEffectDensity = "world", graphicsLiquidDetail = "world",
        graphicsTextureResolution = "world", RenderScale = "size" }
    local wrong = {}
    for cvar, page in pairs(want) do
        if s.PAGE_OF[cvar:lower()] ~= page then wrong[#wrong + 1] = cvar end
    end
    local resolved = e.ns.bench.resolve()
    resolved[#resolved + 1] = { cvar = "someUnknownSetting", label = "Something", tiers = { "0", "1" } }
    local view = s.model({ page = "light" }, ctxOf(e, { resolved = resolved }))
    local pages = {}
    for _, row in ipairs(view.rows) do pages[row.cvar] = row.page end
    return #wrong == 0 and pages.graphicsShadowQuality == "light" and pages.graphicsSSAO == "light" and pages.groundEffectDensity == "world"
        and pages.RenderScale == "size" and pages.someUnknownSetting == "world", table.concat(wrong, ",")
end)

test("S5-3 open takes a page, a profile name, or nothing: a profile name opens the first settings page without switching, nothing keeps the last page (Home the first time)", function()
    local e, s, db = boot()
    s.open()
    local first = s.state().page == "home"
    s.open("size")
    local sized = s.state().page == "size"
    s.open()
    local kept = s.state().page == "size"
    s.open("crowded")
    local crowded = s.state().tab == nil and s.state().page == "light" and db.active == "everyday"
    s.open("home")
    s.open("everyday")
    local everyday = s.state().page == "light" and db.active == "everyday"
    s.open("nosuchpage")
    local bogus = s.state().page == "light"
    return first and sized and kept and crowded and everyday and bogus and #OUT == 0, tostring(first) .. tostring(sized) .. tostring(kept)
        .. tostring(crowded) .. tostring(everyday) .. tostring(bogus)
end)

-- The flat hub window: the shell and the settings pages (spec 2026-11-02-flat-hub-window-design.md H1, H6-H8, H11, sections 4-5).
local PAGE_H = 522                         -- the page area under the 36 pixel header of the 560 pixel window
local NONE_TEXT = "None of these settings are in this client."
local function injectSettings(e, n)        -- n more settings the page table does not know (they land on World detail)
    local real = e.ns.bench.resolve
    e.ns.bench.resolve = function()
        local list = real()
        for i = 1, n do list[#list + 1] = { key = "extra" .. i, cvar = "extraSetting" .. i, label = "Extra " .. i, tiers = { "0", "1", "2" } } end
        return list
    end
end
local function onlyRenderScale(e)
    local real = e.ns.bench.resolve
    e.ns.bench.resolve = function()
        local list = {}
        for _, entry in ipairs(real()) do if entry.cvar == "RenderScale" then list[#list + 1] = entry end end
        return list
    end
end
local function shownButtons(f)
    local list = {}
    walk(f, function(frame) if frame.kind == "Button" and frame.shown and frame.label then list[#list + 1] = frame end end)
    return list
end

test("S6-0 the model gives each level its short label and each row its matters words; columns are two, three above six cards", function()
    local e, s = boot()
    local view = s.model({ page = "light" }, ctxOf(e, { costs = costsOf(e, quietEntry()) }))
    local shadows, clutter = rowOf(view, "graphicsShadowQuality"), rowOf(view, "groundEffectDensity")
    return shadows.mattersWords == "some" and shadows.levels[1].short == "0" and shadows.levels[1].text == "0 (lowest)"
        and shadows.levels[5].short == "4" and shadows.levels[5].text == "4 (highest)" and clutter.levels[1].short == "48"
        and clutter.levels[3].short == "128" and rowOf(view, "RenderScale").levels[1].short == "50%"
        and s.columnsFor(0) == 2 and s.columnsFor(6) == 2 and s.columnsFor(7) == 3 and s.columnsFor(9) == 3,
        tostring(shadows.mattersWords) .. tostring(shadows.levels[1].short)
end)

test("S6-1 the window is flat and 860 by 560, with the header, seven page rows and no scroll frame", function()
    local e, s = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    local scrolls = 0
    walk(f, function(frame) if frame.kind == "ScrollFrame" then scrolls = scrolls + 1 end end)
    local rows = {}
    for _, page in ipairs(s.PAGES) do
        local b = byKey(f, "page:" .. page.key)
        rows[#rows + 1] = b and b._text or "?"
    end
    return f ~= nil and f.name == "ForeverSettingsSettings" and f.template == nil and f._width == 860 and f._height == 560
        and f.titleText._text == "ForeverSettings" and f.close ~= nil and scrolls == 0
        and table.concat(rows, "|") == "Home|Light and shadows|World detail|Picture size|Find my settings|My results|About", table.concat(rows, "|")
end)

test("S6-2 the page list marks the current page, a click changes it, and the page's title follows", function()
    local e, s = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    local start = byKey(f, "page:light").skinState.selected == true and byKey(f, "page:home").skinState.selected == false
        and hasText(f, "Light and shadows")
    byKey(f, "page:world"):Click()
    local moved = s.state().page == "world" and byKey(f, "page:world").skinState.selected == true
        and byKey(f, "page:light").skinState.selected == false and fontStringWith(f, "World detail") ~= nil
    local function rowY(key) return -byKey(f, "page:" .. key)._point[5] end
    local spaced = rowY("size") - rowY("world") == 30 and rowY("test") - rowY("size") == 44           -- a gap before Find my settings
        and rowY("results") - rowY("test") == 30
    byKey(f, "page:about"):Click()
    local bare = byKey(f, "tab:everyday") == nil and byKey(f, "use") == nil and byKey(f, "maximum") == nil
        and not hasText(f, "Everything at the highest") and not hasText(f, "Your Everyday settings")
    return start and moved and spaced and bare and #OUT == 0, tostring(start) .. tostring(moved) .. tostring(spaced) .. tostring(bare)
end)

test("S6-3 Light and shadows draws a card per setting of the page: tick, name, matters words, help, small level buttons with costs, and the lowest and highest words in the tooltip", function()
    local e, s = bootWith(fullEntry())
    local tip
    GameTooltip = { SetOwner = function() end, SetText = function(_, text) tip = text end, Show = function() end, Hide = function() tip = nil end }
    s.open("everyday")
    local f = window()
    local shadowsTick, ssaoTick = byKey(f, "keep:graphicsShadowQuality"), byKey(f, "keep:graphicsSSAO")
    local onPage = shadowsTick ~= nil and ssaoTick ~= nil and byKey(f, "keep:groundEffectDensity") == nil and byKey(f, "keep:RenderScale") == nil
        and shadowsTick:GetChecked() == true and ssaoTick:GetChecked() == false
    local texts = hasText(f, "Shadow detail") and hasText(f, "matters: some") and hasText(f, "How sharp and detailed shadows look.")
    local first, last, now = byKey(f, "level:graphicsShadowQuality:0"), byKey(f, "level:graphicsShadowQuality:4"), byKey(f, "level:graphicsShadowQuality:2")
    local levels = first ~= nil and last ~= nil and now ~= nil and first._text == "0" and last._text == "4" and first._width == 50
        and first._height == 22 and now.skinState.selected == true and first.skinState.selected == false
    local nowText, nowFs = costFor(f, "graphicsShadowQuality", "2")
    local costs = costFor(f, "graphicsShadowQuality", "0") == "+83 fps" and nowText == "now"
    local lightR, lightG, lightB = e.ns.skin.color("accentLight")
    costs = costs and nowFs._textColor[1] == lightR and nowFs._textColor[2] == lightG and nowFs._textColor[3] == lightB
    first.scripts.OnEnter(first)
    local lowTip = tip == "0 (lowest)"
    last.scripts.OnEnter(last)
    local highTip = tip == "4 (highest)"
    GameTooltip = nil
    return onPage and texts and levels and costs and lowTip and highTip,
        tostring(onPage) .. tostring(texts) .. tostring(levels) .. tostring(costs) .. tostring(lowTip) .. tostring(highTip)
end)

test("S6-4 a page is two columns of cards, three above six cards; a page with none says so in one line", function()
    local e, s = bootWith(fullEntry())
    injectSettings(e, 4)                                    -- World detail: clutter (raw) and four more: five cards
    s.open("world")
    local f = window()
    local function xs()
        local seen = {}
        for _, key in ipairs({ "keep:groundEffectDensity", "keep:extraSetting1", "keep:extraSetting2", "keep:extraSetting3", "keep:extraSetting4" }) do
            local tick = byKey(f, key)
            if tick then seen[tick._point[4]] = true end
        end
        local list = {}
        for x in pairs(seen) do list[#list + 1] = x end
        table.sort(list)
        return list
    end
    local two = xs()
    local twoOk = #two == 2 and two[2] - two[1] == 346
    local e2, s2 = bootWith(fullEntry())
    injectSettings(e2, 6)                                   -- seven cards
    s2.open("world")
    local f2 = window()
    local seen = {}
    for _, key in ipairs({ "keep:groundEffectDensity", "keep:extraSetting1", "keep:extraSetting2", "keep:extraSetting3", "keep:extraSetting4",
        "keep:extraSetting5", "keep:extraSetting6" }) do
        local tick = byKey(f2, key)
        if tick then seen[tick._point[4]] = true end
    end
    local three = {}
    for x in pairs(seen) do three[#three + 1] = x end
    table.sort(three)
    local threeOk = #three == 3 and three[2] - three[1] == 231 and three[3] - three[2] == 231
    local e3, s3 = bootWith(fullEntry())
    onlyRenderScale(e3)
    s3.open("light")
    local f3 = window()
    local empty = hasText(f3, NONE_TEXT) and byKey(f3, "keep:graphicsShadowQuality") == nil
    return twoOk and threeOk and empty, tostring(twoOk) .. tostring(threeOk) .. tostring(empty)
end)

test("S6-5 every page fits inside the page area with a 9-pixel wrap and a long notice, and no two buttons overlap", function()
    local e, s = bootWith(fullEntry(), { active = "maximum" })
    injectSettings(e, 5)                                    -- six cards on World detail
    STRINGHEIGHT = function(fs)
        local text = fs._text or ""
        local perLine = math.max(1, math.floor((fs._width or 520) / 9))
        return 14 * math.max(1, math.ceil(#text / perLine))
    end
    s.open("world")
    local f = window()
    local lowest = 0
    local buttons = {}
    walk(f, function(frame)
        if frame.shown and frame.key and frame.key:find("^level:") then
            buttons[#buttons + 1] = frame
            local bottom = -frame._point[5] + frame._height + 16
            if bottom > lowest then lowest = bottom end
        end
    end)
    local summaryTop = PAGE_H
    for _, text in ipairs({ "Your Everyday settings: about", "Everything at the highest" }) do
        local fs
        walk(f, function(frame)
            for _, candidate in ipairs(frame.fontStrings) do
                if candidate.shown and candidate._text and candidate._text:find(text, 1, true) then fs = candidate end
            end
        end)
        if fs and PAGE_H - fs._point[5] - STRINGHEIGHT(fs) < summaryTop then summaryTop = PAGE_H - fs._point[5] - STRINGHEIGHT(fs) end
    end
    local fits = #buttons == 18 and 8 + lowest + 4 <= summaryTop
    local clear = true
    for i = 1, #buttons do
        for j = i + 1, #buttons do
            local a, b = buttons[i], buttons[j]
            local ax, ay, bx, by = a._point[4], -a._point[5], b._point[4], -b._point[5]
            if ax < bx + b._width and bx < ax + a._width and ay < by + b._height and by < ay + a._height then clear = false end
        end
    end
    STRINGHEIGHT = nil
    return fits and clear, tostring(#buttons) .. " " .. tostring(8 + lowest) .. " < " .. tostring(summaryTop)
end)

test("S6-6 every button label is centred both ways on one line at its width; the page rows keep theirs at the left, the pill its name beside the dot", function()
    local bad = {}
    local count = 0
    local function check(f)
        for _, b in ipairs(shownButtons(f)) do
            count = count + 1
            local label = b.label
            if b.navItem then
                if not (label._justifyH == "LEFT" and label._justifyV == "MIDDLE") then bad[#bad + 1] = "nav:" .. tostring(b._text) end
            elseif b.key == "pill" then
                if not (label._point and label._point[1] == "LEFT" and label._point[4] == 24) then bad[#bad + 1] = "pill" end
                if #(label._text or "") * 6.5 > b._width - 28 then bad[#bad + 1] = "wide:pill" end
            else
                if not (label._point and label._point[1] == "CENTER" and label._justifyH == "CENTER" and label._justifyV == "MIDDLE"
                    and label._wordWrap == false) then bad[#bad + 1] = "centre:" .. tostring(b._text) end
                if #(b._text or "") * 6.5 > b._width - 8 then bad[#bad + 1] = "wide:" .. tostring(b._text) end
            end
        end
    end
    local e, s = bootWith(fullEntry())
    s.open("light")
    check(window())
    local pill = byKey(window(), "pill")
    local e2, s2 = bootWith(fullEntry(), { active = "maximum" })
    s2.open("light")
    check(window())
    local edit = byKey(window(), "edit:everyday")
    return count >= 30 and #bad == 0 and pill._width == 104 and pill._height == 22 and edit._width == 112 and edit._height == 24,
        table.concat(bad, ",") .. " " .. count
end)

test("S6-8 the summary block stands at the bottom of the page: the live line, the total and the matters note, bottom-up", function()
    local e, s = bootWith(fullEntry())
    s.open("light")
    local f = window()
    local your = fontStringWith(f, "Your Everyday settings: about 270 fps (an estimate; settings affect each other).")
    local total = fontStringWith(f, "Everything at the highest: about 152 fps.")
    local note = fontStringWith(f, MATTERS_NOTE)
    STRINGHEIGHT = function() return 14 end
    local ok = your ~= nil and total ~= nil and note ~= nil and your._point[1] == "BOTTOMLEFT" and your._point[4] == 167
        and note._point[5] == 12 and total._point[5] >= note._point[5] + 14 and your._point[5] >= total._point[5] + 14
    STRINGHEIGHT = nil
    local e2, s2 = bootWith(nil)
    s2.open("light")
    local none = not hasText(window(), "Your Everyday settings") and not hasText(window(), "Everything at the highest")
    return ok and none, tostring(ok) .. tostring(none) .. " " .. tostring(note and note._point[5])
end)

test("S6-9 with Maximum in use the notices stand as one banner, then the read-only line, then Everyday and Crowded side by side, then the cards", function()
    local e, s = bootWith(fullEntry(), { active = "maximum" })
    COMBAT = true
    s.open("light")
    COMBAT = false
    local f = window()
    local banner
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text and fs._text:find(MAX_ON, 1, true) then banner = fs end
        end
    end)
    local line = fontStringWith(f, READ_ONLY_MAX)
    local every, crowd, card = byKey(f, "edit:everyday"), byKey(f, "edit:crowded"), byKey(f, "keep:graphicsShadowQuality")
    local function top(item) return -item._point[5] end
    local one = banner ~= nil and banner._text:find(COMBAT_TEXT, 1, true) ~= nil
    local ok = one and line ~= nil and every ~= nil and crowd ~= nil and card ~= nil
        and top(line) > top(banner) and top(every) > top(line) and top(crowd) == top(every)
        and every._point[4] == 0 and crowd._point[4] == 112 + 8 and top(card) >= top(every) + 24 + 8
    return ok, tostring(one) .. " " .. tostring(line and top(line)) .. " " .. tostring(every and top(every)) .. " " .. tostring(card and top(card))
end)

test("S6-10 in combat every control is greyed with the reason shown, clicks write nothing, and the pages still switch", function()
    local e, s = bootWith(fullEntry())
    COMBAT = true
    s.open("light")
    local f = window()
    local greyed = byKey(f, "level:graphicsShadowQuality:3").enabled == false and byKey(f, "keep:graphicsShadowQuality").enabled == false
        and byKey(f, "save:crowded").enabled == false and hasText(f, COMBAT_TEXT)
    SETLOG = {}
    s.click("level:graphicsShadowQuality:3")
    s.click("keep:graphicsSSAO")
    local quiet = #SETLOG == 0 and CVARS.graphicsShadowQuality == "2"
    byKey(f, "page:world"):Click()
    local pages = s.state().page == "world" and byKey(f, "page:world").enabled == true
    COMBAT = false
    return greyed and quiet and pages, tostring(greyed) .. tostring(quiet) .. tostring(pages)
end)

test("S6-11 Escape closes the window once, and no raw setting name appears in any text of any page", function()
    local e, s = bootWith(fullEntry())
    CVARS.graphicsComputeEffects = "1"
    local listed = 0
    local raw
    for _, key in ipairs({ "light", "world", "size" }) do
        s.open(key)
        local f = window()
        for _, name in ipairs(RAW) do
            if allText(f):find(name, 1, true) then raw = name end
        end
    end
    for _, name in ipairs(UISpecialFrames) do if name == "ForeverSettingsSettings" then listed = listed + 1 end end
    return listed == 1 and raw == nil, tostring(listed) .. tostring(raw)
end)

test("S5-4 a click on a page changes the page and writes nothing, even in combat; an unknown page is ignored", function()
    local e, s = boot()
    s.open()
    SETLOG, OUT = {}, {}
    s.click("page:world")
    local moved = s.state().page == "world"
    COMBAT = true
    s.click("page:about")
    local locked = s.state().page == "about"
    COMBAT = false
    s.click("page:nosuchpage")
    local ignored = s.state().page == "about"
    return moved and locked and ignored and #SETLOG == 0 and #OUT == 0, tostring(moved) .. tostring(locked) .. tostring(ignored)
end)

return H.results()
