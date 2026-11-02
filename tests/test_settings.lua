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
local ORIGINAL_NOTE = "You're using your Original settings (hands off). Switch to Everyday or Crowded in the menu to turn these on."
local COMBAT_TEXT = "You are in combat; try again afterwards."
local BUSY_TEXT = "A test is running; try again afterwards."
local RAW = { "graphicsShadowQuality", "graphicsSSAO", "groundEffectDensity", "RenderScale", "graphicsComputeEffects" }

test("S1-1 the tabs, their notes and marks, the title and the intro; the window opens on the profile in use", function()
    local e, s, db = boot()
    local view = s.model({ tab = "everyday" }, ctxOf(e))
    s.open()
    local onEveryday = s.state().tab
    db.active = "crowded"
    s.open()
    local onCrowded = s.state().tab
    db.active = "original"
    s.open()
    local onOriginal = s.state().tab
    return view.title == "My settings" and view.intro == INTRO and #view.tabs == 2
        and view.tabs[1].key == "everyday" and view.tabs[1].text == "Everyday (in use)" and view.tabs[1].inUse and view.tabs[1].selected
        and view.tabs[1].note == "Settings for normal play." and view.tabs[2].key == "crowded" and view.tabs[2].text == "Crowded"
        and not view.tabs[2].inUse and not view.tabs[2].selected and view.tabs[2].note == "Settings for raids and busy cities."
        and view.notice == nil and onEveryday == "everyday" and onCrowded == "crowded" and onOriginal == "everyday",
        view.tabs[1].text .. " " .. onEveryday .. onCrowded .. onOriginal
end)

test("S1-2 with Original in use the note shows, the tabs and rows stay editable, and an edit is only stored", function()
    local e, s, db = boot({ active = "original" })
    local view = s.model({ tab = "everyday" }, ctxOf(e, { active = "original" }))
    s.open("crowded")
    local before = copyOf(db.profiles.everyday.values)
    s.click("tab:everyday")
    s.click("level:graphicsShadowQuality:3")
    local stored = db.profiles.everyday.values.graphicsShadowQuality == "3" and db.active == "original" and #SETLOG == 0
        and CVARS.graphicsShadowQuality == "2" and next(db.want) == nil and #OUT == 0
    return view.notice == ORIGINAL_NOTE and view.tabs[1].enabled and view.tabs[2].enabled and view.rows[1].enabled
        and not view.tabs[1].inUse and not view.tabs[2].inUse and stored and before.graphicsShadowQuality == "2", outText()
end)

test("S1-3 one row per setting the client has, in the table's order, with the plain name, line and level words", function()
    local e, s = boot()
    local view = s.model({ tab = "everyday" }, ctxOf(e))
    local order = {}
    for _, row in ipairs(view.rows) do order[#order + 1] = row.cvar end
    local r = view.rows
    return table.concat(order, ",") == "graphicsShadowQuality,graphicsSSAO,groundEffectDensity,RenderScale"
        and r[1].name == "Shadow detail"
        and r[1].line == "How sharp and detailed shadows look. Higher looks better and costs a lot of speed."
        and levelTexts(r[1]) == "0 (lowest)|1|2|3|4 (highest)" and r[2].name == "Soft corner shadows"
        and r[3].name == "Grass and plants (exact amount)" and levelTexts(r[3]) == "48 (lowest)|64|128 (highest)"
        and r[4].name == "Picture sharpness" and levelTexts(r[4]) == "50%|60%|70%|80%|90%|100%", order[3] .. " " .. levelTexts(r[4])
end)

test("S1-4 the tab in use highlights the game's live value, the other tab its saved value, and ticks follow what is saved", function()
    local e, s = boot()
    CVARS.graphicsShadowQuality = "3"
    local mine = s.model({ tab = "everyday" }, ctxOf(e))
    local other = s.model({ tab = "crowded" }, ctxOf(e))
    return selectedOf(mine.rows[1]) == "3" and mine.rows[1].kept and selectedOf(mine.rows[2]) == "1" and not mine.rows[2].kept
        and selectedOf(other.rows[1]) == "0" and other.rows[1].kept and selectedOf(other.rows[2]) == "" and not other.rows[2].kept
        and selectedOf(other.rows[4]) == "", selectedOf(mine.rows[1]) .. selectedOf(other.rows[1])
end)

test("S1-5 a level clicked on the tab in use is applied and kept through setValue, silently", function()
    local e, s, db, p = boot()
    local calls = {}
    local real = p.setValue
    p.setValue = function(cvar, value, silent) calls[#calls + 1] = { cvar, value, silent } return real(cvar, value, silent) end
    s.open("everyday")
    s.click("level:graphicsShadowQuality:3")
    return #calls == 1 and calls[1][1] == "graphicsShadowQuality" and calls[1][2] == "3" and calls[1][3] == true
        and CVARS.graphicsShadowQuality == "3" and db.profiles.everyday.values.graphicsShadowQuality == "3"
        and db.want.graphicsShadowQuality == "3" and #OUT == 0, outText()
end)

test("S1-6 a level clicked on the other tab is only stored: nothing is written to the game or to the profile in use", function()
    local e, s, db = boot()
    s.open("crowded")
    local wantBefore, everydayBefore = copyOf(db.want), copyOf(db.profiles.everyday.values)
    s.click("level:graphicsShadowQuality:1")
    s.click("level:graphicsSSAO:3")
    return db.profiles.crowded.values.graphicsShadowQuality == "1" and db.profiles.crowded.values.graphicsSSAO == "3"
        and #SETLOG == 0 and CVARS.graphicsShadowQuality == "2" and CVARS.graphicsSSAO == "1" and sameTable(db.want, wantBefore)
        and sameTable(db.profiles.everyday.values, everydayBefore) and db.active == "everyday" and #OUT == 0, outText()
end)

test("S1-7 unticking stops keeping a setting: on the tab in use the game keeps its value, on the other it is forgotten", function()
    local e, s, db = boot()
    s.open("everyday")
    s.click("keep:graphicsShadowQuality")
    local mine = db.profiles.everyday.values.graphicsShadowQuality == nil and db.want.graphicsShadowQuality == nil
        and CVARS.graphicsShadowQuality == "2"
    s.click("tab:crowded")
    s.click("keep:graphicsShadowQuality")
    return mine and db.profiles.crowded.values.graphicsShadowQuality == nil and #OUT == 0, outText()
end)

test("S1-8 ticking an unticked row keeps the game's current value, on either tab", function()
    local e, s, db = boot()
    CVARS.graphicsSSAO = "3"
    s.open("everyday")
    s.click("keep:graphicsSSAO")
    local mine = db.profiles.everyday.values.graphicsSSAO == "3" and db.want.graphicsSSAO == "3"
    SETLOG = {}
    s.click("tab:crowded")
    s.click("keep:graphicsSSAO")
    return mine and db.profiles.crowded.values.graphicsSSAO == "3" and #SETLOG == 0 and #OUT == 0, outText()
end)

test("S1-9 in combat or during a test every control is greyed with its reason, and clicks that still arrive write nothing", function()
    local e, s, db = boot()
    local combat = s.model({ tab = "everyday" }, ctxOf(e, { locked = "combat" }))
    local busy = s.model({ tab = "everyday" }, ctxOf(e, { locked = "busy" }))
    local greyed = true
    for _, view in ipairs({ combat, busy }) do
        for _, tab in ipairs(view.tabs) do greyed = greyed and tab.enabled == false end
        for _, row in ipairs(view.rows) do greyed = greyed and row.enabled == false end
        local byButton = {}
        for _, button in ipairs(view.buttons) do byButton[button.key] = button end
        greyed = greyed and byButton.use.enabled == false and byButton.close.enabled == true and byButton.maximum.enabled == false
    end
    s.open("everyday")
    local function nothingWrites(setup, undo)
        setup()
        local before = { copyOf(db.profiles.everyday.values), copyOf(db.profiles.crowded.values), copyOf(db.want), s.state().tab }
        SETLOG = {}
        s.click("level:graphicsShadowQuality:4")
        s.click("keep:graphicsSSAO")
        s.click("keep:graphicsShadowQuality")
        s.click("tab:crowded")
        s.click("use")
        local same = sameTable(db.profiles.everyday.values, before[1]) and sameTable(db.profiles.crowded.values, before[2])
            and sameTable(db.want, before[3]) and s.state().tab == before[4] and #SETLOG == 0 and CVARS.graphicsShadowQuality == "2"
        undo()
        return same
    end
    local inCombat = nothingWrites(function() COMBAT = true end, function() COMBAT = false end)
    local running = nothingWrites(function() e.ns.suspended = true end, function() e.ns.suspended = false end)
    return combat.locked == COMBAT_TEXT and busy.locked == BUSY_TEXT and greyed and inCombat and running, outText()
end)

test("S1-10 Use what I have in the game now saves the game's settings into the tab's profile and the rows then show them kept", function()
    local e, s, db, p = boot()
    local calls = {}
    local real = p.save
    p.save = function(name, silent) calls[#calls + 1] = { name, silent } return real(name, silent) end
    s.open("crowded")
    s.click("use")
    local view = s.model(s.state(), ctxOf(e, { saved = { everyday = db.profiles.everyday.values, crowded = db.profiles.crowded.values } }))
    return #calls == 1 and calls[1][1] == "crowded" and calls[1][2] == true and db.profiles.crowded.values.graphicsShadowQuality == "2"
        and db.profiles.crowded.values.graphicsSSAO == "1" and view.rows[2].kept and selectedOf(view.rows[2]) == "1" and #OUT == 0, outText()
end)

test("S1-11 a profile switched from outside moves the in-use mark and the highlight within the refresh interval", function()
    local e, s, db, p = boot()
    s.open("crowded")
    local f = window()
    local before = byKey(f, "tab:crowded")._text == "Crowded" and byKey(f, "tab:everyday")._text == "Everyday (in use)"
    p.switch("crowded")
    e.pump(1, function() return 0.05 end)
    local after = byKey(f, "tab:crowded")._text == "Crowded (in use)" and byKey(f, "tab:everyday")._text == "Everyday"
    local highlighted = byKey(f, "level:graphicsShadowQuality:0").skinState.selected == true
        and byKey(f, "level:graphicsShadowQuality:2").skinState.selected == false
    return before and after and highlighted, tostring(byKey(f, "tab:crowded")._text)
end)

test("S1-12 the window's pages: a tick and level buttons per setting on each page, 13 levels wrap to two lines, the X closes it, Escape is listed once, no raw names", function()
    local e, s, db = boot()
    local b = e.ns.bench
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" }
    s.open("everyday")
    s.open("everyday")
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
    local titled = hasText(f, "Light and shadows") and hasText(f, "Shadow detail") and hasText(f, "Everyday (in use)")
    byKey(f, "tab:crowded"):Click()
    local switched = s.state().tab == "crowded"
    s.click("page:world")
    local worldKeeps, worldLevels = count("keep:"), count("level:")
    raw = raw or rawIn(f)
    s.click("page:size")
    local sizeKeeps, sizeLevels = count("keep:"), count("level:")
    raw = raw or rawIn(f)
    local listed = 0
    for _, name in ipairs(UISpecialFrames) do if name == "ForeverSettingsSettings" then listed = listed + 1 end end
    f.close:Click()
    return titled and keptNow and liveSelected and switched and not f:IsShown() and listed == 1 and not raw
        and lightKeeps == 2 and lightLevels == 5 + 13 and ssaoLines == 2 and worldKeeps == 1 and worldLevels == 3
        and sizeKeeps == 1 and sizeLevels == 6,
        tostring(lightKeeps) .. " " .. tostring(lightLevels) .. " " .. tostring(ssaoLines) .. " " .. tostring(worldKeeps) .. " "
            .. tostring(worldLevels) .. " " .. tostring(sizeKeeps) .. " " .. tostring(sizeLevels) .. " " .. tostring(listed) .. " " .. tostring(raw)
end)

test("S1-13 no action of the window prints to chat", function()
    local e, s = boot()
    s.open("everyday")
    s.click("level:graphicsShadowQuality:3")
    s.click("keep:graphicsSSAO")
    s.click("keep:graphicsSSAO")
    s.click("tab:crowded")
    s.click("level:graphicsShadowQuality:1")
    s.click("keep:graphicsShadowQuality")
    s.click("use")
    s.click("tab:everyday")
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
    .. "graphics memory. Switch to Everyday or Crowded in the menu to change these."
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
            if fs.shown and fs._text and fs._text ~= "" and fs._point and fs._point[4] == x
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
    local mine = s.model({ tab = "everyday" }, ctxOf(e, { costs = costsOf(e, entry) }))                   -- Shadows 2, SSAO 1 in the game
    local other = s.model({ tab = "crowded" }, ctxOf(e, { costs = costsOf(e, entry),
        saved = { everyday = { graphicsShadowQuality = "2" }, crowded = { graphicsShadowQuality = "1" } } }))
    CVARS.graphicsShadowQuality = "3"                                                                      -- a level the test never measured
    local unmeasured = s.model({ tab = "everyday" }, ctxOf(e, { costs = costsOf(e, entry) }))
    CVARS.graphicsShadowQuality = "2"
    local noTest = s.model({ tab = "everyday" }, ctxOf(e, {}))
    local near = quietEntry()
    near.rows[2].deltaMs, near.rows[2].meanMs = -0.001, 3.999           -- Shadows 1: 0.06 fps faster than the held level 2
    near.rows[4].deltaMs, near.rows[4].meanMs = -0.31, 3.69             -- SSAO 0: 0.73 fps faster than the held level 1
    local rounded = s.model({ tab = "everyday" }, ctxOf(e, { costs = costsOf(e, near) }))
    local none = "-|-|-|-|-"
    return costTexts(rowOf(mine, "graphicsShadowQuality")) == "+83 fps|+28 fps|now|?|?"
        and costTexts(rowOf(mine, "graphicsSSAO")) == "+24 fps|now|-20 fps|?|?"
        and costTexts(rowOf(mine, "groundEffectDensity")) == "-|-|-" and costTexts(rowOf(mine, "RenderScale")) == "-|-|-|-|-|-"
        and costTexts(rowOf(other, "graphicsShadowQuality")) == "+56 fps|now|-28 fps|?|?"
        and costTexts(rowOf(other, "graphicsSSAO")) == none
        and costTexts(rowOf(unmeasured, "graphicsShadowQuality")) == none
        and costTexts(rowOf(noTest, "graphicsShadowQuality")) == none and costTexts(rowOf(noTest, "graphicsSSAO")) == none
        and costTexts(rowOf(rounded, "graphicsShadowQuality")) == "+83 fps|same|now|?|?"
        and costTexts(rowOf(rounded, "graphicsSSAO")) == "+1 fps|now|-20 fps|?|?",
        costTexts(rowOf(mine, "graphicsShadowQuality")) .. " / " .. costTexts(rowOf(other, "graphicsShadowQuality")) .. " / "
            .. costTexts(rowOf(rounded, "graphicsShadowQuality"))
end)

test("S2-2 the note under the intro names the test the costs come from or says to run one; the Crowded tab prefers the crowd result", function()
    local e, s = boot()
    local entry = quietEntry()
    local quiet = s.model({ tab = "everyday" }, ctxOf(e, { costs = costsOf(e, entry) }))
    local crowd = s.model({ tab = "crowded" }, ctxOf(e, { costs = costsOf(e, entry, "crowd", "Measured in Stormwind City, 2 hours ago.") }))
    local noLine = s.model({ tab = "everyday" }, ctxOf(e, { costs = costsOf(e, entry, "quiet", false) }))
    local noTest = s.model({ tab = "everyday" }, ctxOf(e, {}))
    local empty = s.model({ tab = "everyday" }, ctxOf(e, { costs = { kind = "quiet", fps = { nowFps = 250, byCvar = {} } } }))
    local forms = quiet.costNote == COST_QUIET and crowd.costNote == COST_CROWD and noLine.costNote == "Costs from your quiet-spot test."
        and noTest.costNote == COST_NONE and empty.costNote == COST_NONE
    -- through context(): the Crowded tab reads the rebuilt crowd entry, the Everyday tab the quiet-spot test
    local e2, s2 = bootWith(quietEntry())
    local asked = {}
    e2.ns.ui.savedResult = function(kind)
        asked[#asked + 1] = kind
        if kind == "crowded" then
            return { entry = e2.ns.recommend.crowdEntry(quietEntry(), crowdFixture()), measuredLine = "Measured in Stormwind City, 2 hours ago." }
        end
    end
    s2.open("everyday")
    local f = window()
    local everyday = hasText(f, COST_QUIET) and costFor(f, "graphicsShadowQuality", "0") == "+83 fps"
    s2.click("tab:crowded")
    local crowded = hasText(f, COST_CROWD) and not hasText(f, COST_QUIET) and costFor(f, "graphicsShadowQuality", "0") == "now"
        and costFor(f, "graphicsShadowQuality", "1") == "-29 fps" and costFor(f, "graphicsShadowQuality", "2") == "-43 fps"
    -- without a saved crowd result the Crowded tab reads the quiet-spot test
    e2.ns.ui.savedResult = function() return nil end
    s2.click("tab:everyday")
    s2.click("tab:crowded")
    local fallback = hasText(f, COST_QUIET) and not hasText(f, COST_CROWD)
    return forms and everyday and crowded and fallback and #OUT == 0, tostring(forms) .. tostring(everyday) .. tostring(crowded)
        .. tostring(fallback) .. outText()
end)

test("S2-3 each setting says how much it matters to the picture, from the ranking; one the ranking does not know says nothing", function()
    local e, s = boot()
    local resolved = e.ns.bench.resolve()
    resolved[#resolved + 1] = { cvar = "someUnknownSetting", label = "Something", tiers = { "0", "1" } }
    local view = s.model({ tab = "everyday" }, ctxOf(e, { resolved = resolved }))
    local words = {}
    for _, row in ipairs(view.rows) do words[#words + 1] = row.cvar .. "=" .. tostring(row.matters) end
    local bare = s.model({ tab = "everyday" }, ctxOf(e, { resolved = { { cvar = "someUnknownSetting", label = "Something", tiers = { "0", "1" } } } }))
    return table.concat(words, ",") == "graphicsShadowQuality=Matters to the picture: some.,graphicsSSAO=Matters to the picture: a little.,"
        .. "groundEffectDensity=Matters to the picture: a little.,RenderScale=Matters to the picture: a lot.,someUnknownSetting=nil"
        and view.mattersNote == MATTERS_NOTE and bare.mattersNote == nil and bare.rows[1].matters == nil, table.concat(words, ",")
end)

test("S2-4 the total line: the estimate, the skipped count in the plural and the singular, and nothing without a test", function()
    local e, s = boot()
    local costs = costsOf(e, quietEntry())
    local function total(max, withCosts)
        return s.model({ tab = "everyday" }, ctxOf(e, { costs = withCosts, maximum = max })).totalLine
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

test("S2-5 Switch to Maximum sits between Use and Close, is greyed when locked, is absent while Maximum is in use, and switches silently", function()
    local e, s, db, p = bootWith(fullEntry())
    local function keys(view)
        local list = {}
        for _, button in ipairs(view.buttons) do list[#list + 1] = button.key .. ":" .. tostring(button.enabled) end
        return table.concat(list, ",")
    end
    local idle = s.model({ tab = "everyday" }, ctxOf(e))
    local combat = s.model({ tab = "everyday" }, ctxOf(e, { locked = "combat" }))
    local inUse = s.model({ tab = "everyday" }, ctxOf(e, { active = "maximum" }))
    local shape = keys(idle) == "use:true,maximum:true,close:true" and idle.buttons[2].text == "Switch to Maximum"
        and keys(combat) == "use:false,maximum:false,close:true" and keys(inUse) == "use:true,close:true"
    local calls = {}
    local real = p.switch
    p.switch = function(name, silent) calls[#calls + 1] = tostring(name) .. ":" .. tostring(silent) return real(name, silent) end
    s.open("everyday")
    COMBAT = true
    s.click("maximum")
    COMBAT = false
    e.ns.suspended = true
    s.click("maximum")
    e.ns.suspended = false
    local lockedWrites = #calls == 0 and #SETLOG == 0 and db.active == "everyday"
    s.click("maximum")
    local f = window()
    local switched = #calls == 1 and calls[1] == "maximum:true" and db.active == "maximum" and #OUT == 0
        and CVARS.graphicsShadowQuality == "4" and hasText(f, MAX_ON) and byKey(f, "maximum") == nil
    return shape and lockedWrites and switched, tostring(shape) .. tostring(lockedWrites) .. tostring(switched) .. " " .. table.concat(calls, ",") .. outText()
end)

test("S2-5b a click that is refused for combat or a test says why in the window until the next click", function()
    local e, s, db = bootWith(nil)
    s.open("everyday")
    local f = window()
    COMBAT = true
    s.click("maximum")
    local inCombat = hasText(f, COMBAT_TEXT)
    COMBAT = false
    s.click("tab:crowded")
    local cleared = not hasText(f, COMBAT_TEXT)
    e.ns.suspended = true
    s.click("maximum")
    local running = hasText(f, BUSY_TEXT)
    e.ns.suspended = false
    s.click("tab:everyday")
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
    -- a saved crowd result that cannot be rebuilt: the Crowded tab falls back to the quiet-spot test and still draws
    local e7, s7 = bootWith(quietEntry())
    e7.ns.ui.savedResult = function() error("no crowd result") end
    s7.open("crowded")
    local okSaved = #OUT == 0 and hasText(window(), COST_QUIET)
    return okQuick and okOld and okCrowd and okBroken and okSaved and quickRow == "?" and quickNote and oldBare and heldNever
        and hasText(fBroken, COST_NONE), tostring(quickRow) .. tostring(quickNote) .. tostring(oldBare) .. tostring(heldNever) .. outText()
end)

test("S2-7 with Maximum in use a level click and a keep tick still only store into the tab's profile, and the note shows", function()
    local e, s, db, p = bootWith(nil)
    CVARS.graphicsComputeEffects = "1"             -- in the client, levels not learned: Maximum leaves it as it is
    p.switch("maximum", true)
    OUT, SETLOG = {}, {}
    s.open("crowded")
    local wantBefore = copyOf(db.want)
    s.click("level:graphicsShadowQuality:3")
    s.click("keep:graphicsSSAO")
    local f = window()
    return db.active == "maximum" and db.profiles.crowded.values.graphicsShadowQuality == "3"
        and db.profiles.crowded.values.graphicsSSAO == CVARS.graphicsSSAO and #SETLOG == 0 and sameTable(db.want, wantBefore)
        and CVARS.graphicsShadowQuality == "4" and hasText(f, MAX_ON) and hasText(f, LEFT_OUT_1) and #OUT == 0, outText()
end)

test("S2-8 a click on Switch to Maximum with nothing to set shows the plain reason in the window, writes nothing and prints nothing", function()
    local e = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1", vsync = "0" }, { fresh = true })     -- no levels learned here
    local s, p = e.ns.settings, e.ns.profiles
    local db = p.state()
    local before = db.active
    s.open("everyday")
    OUT, SETLOG = {}, {}
    s.click("maximum")
    local f = window()
    local shown = hasText(f, NOTHING)
    -- a redraw the window makes by itself (a test started elsewhere) drops it
    e.ns.suspended = true
    e.pump(1, function() return 0.05 end)
    local droppedOnRedraw = not hasText(f, NOTHING) and hasText(f, BUSY_TEXT)
    e.ns.suspended = false
    e.pump(1, function() return 0.05 end)
    s.click("maximum")
    local again = hasText(f, NOTHING)
    s.click("tab:crowded")
    local cleared = not hasText(f, NOTHING)
    return db.active == before and #SETLOG == 0 and #OUT == 0 and shown and droppedOnRedraw and again and cleared,
        tostring(db.active == before) .. tostring(#SETLOG) .. tostring(#OUT) .. tostring(shown) .. tostring(droppedOnRedraw)
            .. tostring(again) .. tostring(cleared) .. outText()
end)

test("S2-9 the window draws the costs under the level buttons, the matters words, the notes and the footer buttons, and takes them away again without a test", function()
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
                    if text ~= level.cost or fs._width ~= 36 then match = false end
                elseif text ~= nil then
                    match = false
                end
            end
        end
    end
    local matters = hasText(f, "matters: some") and hasText(f, "matters: a little")
    local notes = hasText(f, COST_QUIET) and hasText(f, MATTERS_NOTE) and hasText(f, "Everything at the highest: about 152 fps.")
        and byKey(f, "maximum") ~= nil and byKey(f, "maximum")._text == "Switch to Maximum"
    -- a draw with no test: the second lines, the cost note and the total go away, the matters words and their note stay
    e.ns.bench.state().history[1] = nil
    s.open("everyday")
    local gone = costFor(f, "graphicsShadowQuality", "0") == nil and not hasText(f, "Everything at the highest")
        and hasText(f, COST_NONE) and not hasText(f, COST_QUIET) and hasText(f, MATTERS_NOTE) and hasText(f, "matters: some")
    -- with Maximum in use the third button goes
    p.switch("maximum", true)
    s.open("everyday")
    local noButton = byKey(f, "maximum") == nil
    return match and drawnCosts > 0 and matters and notes and gone and noButton,
        tostring(match) .. tostring(drawnCosts) .. tostring(matters) .. tostring(notes) .. tostring(gone) .. tostring(noButton)
end)

test("S2-13 a level the game will not take when Maximum is switched on from the window is named in the window, in plain words", function()
    local e, s, db = bootWith(nil)
    SETFAIL.graphicsShadowQuality = "clamp"
    s.open("everyday")
    OUT = {}
    s.click("maximum")
    local f = window()
    local one = db.active == "maximum" and hasText(f, "The game would not take the highest level for: Shadow detail.")
        and hasText(f, MAX_ON) and #OUT == 0
    s.click("tab:crowded")                                   -- a redraw by itself drops it, as the other refusal
    local gone = not hasText(f, "would not take")
    s.click("tab:everyday")
    local e2, s2 = bootWith(nil)
    SETFAIL.graphicsShadowQuality = "clamp"
    SETFAIL.graphicsSSAO = "clamp"
    s2.open("everyday")
    s2.click("maximum")
    local f2 = window()
    local two = hasText(f2, "The game would not take the highest level for: ") and hasText(f2, "Shadow detail")
        and hasText(f2, "Soft corner shadows")
    local e3, s3, db3 = bootWith(nil)                        -- nothing refused: no such line
    s3.open("everyday")
    s3.click("maximum")
    local none = not hasText(window(), "would not take")
    local e4, s4, db4 = bootWith(nil)                        -- a setting with no plain name that the game also refuses is not listed
    db4.original.values.maxFPS = "60"
    CVARS.maxFPS = "30"
    SETFAIL.maxFPS = "clamp"
    SETFAIL.graphicsShadowQuality = "clamp"
    s4.open("everyday")
    s4.click("maximum")
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
    s.click("tab:crowded")
    local pending1 = "1 setting will go to its highest level at the next loading screen, or when you choose Maximum in the menu again."
    local learned = hasText(window(), pending1) and not hasText(window(), LEFT_OUT_1)
    e.ns.bench.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4", "5" }      -- a higher level than the one set
    s.click("tab:everyday")
    local pending2 = "2 settings will go to their highest level at the next loading screen, or when you choose Maximum in the menu again."
    local higher = hasText(window(), pending2)
    e.fire("PLAYER_ENTERING_WORLD")
    s.click("tab:crowded")
    local applied = not hasText(window(), "highest level at the next loading screen") and not hasText(window(), LEFT_OUT_1)
        and CVARS.graphicsComputeEffects == "3" and CVARS.graphicsShadowQuality == "5"
    local function note(left, pending)
        return s.model({ tab = "everyday" }, ctxOf(e, { active = "maximum", maximum = { skipped = 0, leftOut = left, pending = pending } })).notice
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
    local function note(left) return s.model({ tab = "everyday" }, ctxOf(e, { active = "maximum", maximum = { skipped = 0, leftOut = left } })).notice end
    local plural = "2 settings stay as they are: the addon has not learned their levels yet."
    return note(0) == MAX_ON and note(1) == MAX_ON .. " " .. LEFT_OUT_1 and note(2) == MAX_ON .. " " .. plural
        and s.model({ tab = "everyday" }, ctxOf(e, { active = "maximum" })).notice == MAX_ON, tostring(note(2))
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
        for _, button in ipairs(view.buttons) do list[#list + 1] = button.text end
        return table.concat(list, "\n")
    end
    local costs = costsOf(e, fullEntry())
    local text = names(s.model({ tab = "everyday" }, ctxOf(e, { costs = costs, maximum = { fps = 151.5, skipped = 0, leftOut = 2 },
        estimate = { fps = 94.4, counted = 2, notCounted = 2 } })))
        .. names(s.model({ tab = "everyday" }, ctxOf(e, { active = "maximum", costs = costs, maximum = { skipped = 3, leftOut = 1 } })))
        .. names(s.model({ tab = "crowded", notice = NOTHING }, ctxOf(e, {})))
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
        return s.model({ tab = tab }, ctxOf(e, { costs = withCosts, estimate = estimate })).yourLine
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

test("S3-2 through the window the estimate is recommend's for the levels the tab holds: live ones on the tab in use, saved ones on the other, and it follows every click", function()
    local e, s = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    -- in the game: Shadows 2 (now), SSAO 1 (-0.3 ms), clutter 64 (now), render scale 1 (now): 3.7 ms on a 4.0 ms baseline
    local start = yourText(f) == "Your Everyday settings: about 270 fps" .. YOUR_TAIL
    s.click("level:graphicsShadowQuality:4")                  -- +1.2 ms: 4.9 ms
    local one = yourText(f) == "Your Everyday settings: about 204 fps" .. YOUR_TAIL
    s.click("level:graphicsSSAO:4")                           -- +0.8 ms with the Shadows above: 6.0 ms
    local two = yourText(f) == "Your Everyday settings: about 167 fps" .. YOUR_TAIL
    s.click("tab:crowded")                                    -- the Crowded profile keeps Shadows 0 only: 3.0 ms
    local other = yourText(f) == "Your Crowded settings: about 333 fps" .. YOUR_TAIL
    s.click("level:graphicsSSAO:0")                           -- stored only: -0.6 ms more, 2.4 ms
    local stored = yourText(f) == "Your Crowded settings: about 417 fps" .. YOUR_TAIL and CVARS.graphicsSSAO == "4"
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

test("S3-4 no line without a test or for a tab that keeps nothing, and the rest of the window still draws", function()
    local e, s = bootWith(nil)
    s.open("everyday")
    local noTest = not hasText(window(), "Your Everyday settings") and hasText(window(), COST_NONE)
    local e2, s2, db2 = bootWith(fullEntry())
    db2.profiles.crowded.values = {}
    s2.open("crowded")
    local f = window()
    local empty = not hasText(f, "Your Crowded settings") and hasText(f, COST_QUIET) and hasText(f, "Everything at the highest")
    s2.click("tab:everyday")
    local back = yourText(f) == "Your Everyday settings: about 270 fps" .. YOUR_TAIL
    db2.profiles.crowded.values = { RenderScale = "0.75" }               -- a level the test never measured: nothing to add up
    s2.click("tab:crowded")
    local unmeasured = not hasText(f, "Your Crowded settings") and hasText(f, COST_QUIET)
    return noTest and empty and back and unmeasured and #OUT == 0,
        tostring(noTest) .. tostring(empty) .. tostring(back) .. tostring(unmeasured) .. outText()
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

-- The picture sharpness block (spec 2026-11-02-picture-sharpness-slider-design.md): a slider for this session only.
local SIZE_NOTE = "Not saved: the game goes back to your normal setting when you log out."
local SIZE_WARNING = "Above 100% the game draws more pixels than your screen has. That can cost a lot of frame rate and graphics memory, "
    .. "and some graphics cards crash at high values."
local function drag(f, value)                       -- plays a drag to `value` and the release of the mouse button
    local slider = byKey(f, "size")
    slider._value = value
    slider.scripts.OnValueChanged(slider, value, true)
    slider.scripts.OnMouseUp(slider)
end

test("S4-1 the picture sharpness block: label, range, note, the warning above 100%, Back to normal only while changed, greyed when locked, absent without the setting", function()
    local e, s = boot()
    local function size(over, locked)
        return s.model({ tab = "everyday" }, ctxOf(e, { size = over, locked = locked })).size
    end
    local normal = size({ percent = 100, boosted = false })
    local up = size({ percent = 150, boosted = true, before = 100 })
    local down = size({ percent = 80, boosted = true, before = 100 })
    local near105 = size({ percent = 105, boosted = true, before = 100 })
    local locked = size({ percent = 150, boosted = true, before = 100 }, "combat")
    local low, high = size({ percent = 30, boosted = false }), size({ percent = 250, boosted = false })
    return normal ~= nil and normal.label == "Picture sharpness right now: 100%" and normal.min == 50 and normal.max == 200
        and normal.step == 5 and normal.value == 100 and normal.note == SIZE_NOTE and normal.warning == nil
        and normal.canPutBack == false and normal.enabled == true
        and up.label == "Picture sharpness right now: 150% (normal: 100%)" and up.warning == SIZE_WARNING and up.canPutBack == true
        and down.label == "Picture sharpness right now: 80% (normal: 100%)" and down.warning == nil
        and near105.warning == SIZE_WARNING and locked.enabled == false and locked.canPutBack == false
        and low.value == 50 and low.label == "Picture sharpness right now: 30%" and high.value == 200
        and s.model({ tab = "everyday" }, ctxOf(e, {})).size == nil, tostring(up and up.label)
end)

test("S4-2 the window draws the block; letting go of the slider applies the size, Back to normal puts it back, and nothing prints", function()
    local e, s = bootWith(fullEntry())
    s.open("size")
    local f = window()
    local slider = byKey(f, "size")
    local back = byKey(f, "sizeback")
    local first = slider ~= nil and slider.kind == "Slider" and slider._min == 50 and slider._max == 200 and slider._step == 5
        and slider._value == 100 and hasText(f, "Picture sharpness right now: 100%") and hasText(f, SIZE_NOTE)
        and not hasText(f, SIZE_WARNING) and back ~= nil and back.enabled == false and back._text == "Back to normal"
    SETLOG = {}
    drag(f, 150)
    local up = CVARS.RenderScale == "1.5" and hasText(f, "Picture sharpness right now: 150% (normal: 100%)") and hasText(f, SIZE_WARNING)
        and byKey(f, "sizeback").enabled == true and byKey(f, "size")._value == 150 and #SETLOG == 1 and SETLOG[1] == "RenderScale"
    byKey(f, "sizeback"):Click()
    local down = CVARS.RenderScale == "1" and hasText(f, "Picture sharpness right now: 100%") and not hasText(f, "(normal:")
        and not hasText(f, SIZE_WARNING) and byKey(f, "sizeback").enabled == false and byKey(f, "size")._value == 100
    return first and up and down and #OUT == 0, tostring(first) .. tostring(up) .. tostring(down) .. outText()
end)

test("S4-3 dragging only moves the label; nothing is written until the mouse button is released", function()
    local e, s = bootWith(fullEntry())
    s.open("size")
    local f = window()
    local slider = byKey(f, "size")
    SETLOG = {}
    slider._value = 175
    slider.scripts.OnValueChanged(slider, 175, true)
    local dragging = hasText(f, "Picture sharpness right now: 175%") and #SETLOG == 0 and CVARS.RenderScale == "1"
    slider.scripts.OnMouseUp(slider)
    return dragging and CVARS.RenderScale == "1.75" and #SETLOG == 1, tostring(dragging) .. tostring(CVARS.RenderScale)
end)

test("S4-4 drawing the window never writes: a size between steps, or out of the slider's range, only moves the slider", function()
    local e, s = bootWith(fullEntry())
    CVARS.RenderScale = "1.3"
    SETLOG = {}
    s.open("size")
    local f = window()
    local mid = byKey(f, "size")._value == 130 and hasText(f, "Picture sharpness right now: 130%")
    CVARS.RenderScale = "0.3"
    s.open("size")
    local under = byKey(f, "size")._value == 50 and hasText(f, "Picture sharpness right now: 30%")
    return mid and under and #SETLOG == 0 and #OUT == 0, tostring(mid) .. tostring(under) .. #SETLOG
end)

test("S4-5 the release rounds to the nearest step of 5", function()
    local e, s = bootWith(fullEntry())
    s.open("size")
    local f = window()
    drag(f, 152)
    local a = CVARS.RenderScale == "1.5"
    drag(f, 153)
    local b = CVARS.RenderScale == "1.55"
    return a and b, tostring(CVARS.RenderScale)
end)

test("S4-6 in combat or during a test the slider and Back to normal are greyed, and a stray click writes nothing", function()
    local e, s = bootWith(fullEntry())
    CVARS.RenderScale = "1"
    s.open("size")
    local f = window()
    drag(f, 150)
    COMBAT = true
    s.open("size")
    local greyed = byKey(f, "size").enabled == false and byKey(f, "sizeback").enabled == false
    SETLOG = {}
    s.click("size:200")
    s.click("sizeback")
    local still = #SETLOG == 0 and CVARS.RenderScale == "1.5"
    COMBAT = false
    return greyed and still, tostring(greyed) .. tostring(still) .. tostring(CVARS.RenderScale)
end)

test("S4-7 a client with no picture sharpness setting has no block", function()
    local e5 = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1", vsync = "0" }, { fresh = true })
    e5.ns.bench.now = function() return NOW end
    e5.ns.bench.state().history[1] = quietEntry()
    e5.ns.settings.open("size")
    local f = window()
    return f ~= nil and byKey(f, "size") == nil and byKey(f, "sizeback") == nil and not hasText(f, "Picture sharpness right now")
        and not hasText(f, SIZE_NOTE)
end)

test("S4-8 a size the game will not take is said in the window, in plain words, and the slider shows what the game holds", function()
    local e, s = bootWith(fullEntry())
    s.open("size")
    local f = window()
    SETFAIL.RenderScale = "clamp"
    drag(f, 150)
    return hasText(f, "The game kept picture sharpness at 100% (you asked for 150%).") and CVARS.RenderScale == "1"
        and byKey(f, "size")._value == 100 and #OUT == 0, outText()
end)

test("S4-9 on the Picture size page the block stands under the card: the label over the slider over the warning over the note, Back to normal beside the slider, all above the summary", function()
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
    local label, warn, note = fontStringWith(f, "Picture sharpness right now: 150% (normal: 100%)"), fontStringWith(f, SIZE_WARNING), fontStringWith(f, SIZE_NOTE)
    local slider, back, card = byKey(f, "size"), byKey(f, "sizeback"), byKey(f, "level:RenderScale:1")
    local your = textHas("Your Everyday settings")
    local function top(item) return -item._point[5] end
    local ok = label ~= nil and warn ~= nil and note ~= nil and slider ~= nil and back ~= nil and card ~= nil and your ~= nil
        and top(label) >= top(card) + 22 + 16 and top(slider) >= top(label) + STRINGHEIGHT(label)
        and top(warn) >= top(slider) + 16 and top(note) >= top(warn) + STRINGHEIGHT(warn)
        and back._point[4] >= slider._point[4] + slider._width and back._point[4] + back._width <= 595
        and 8 + top(note) + STRINGHEIGHT(note) <= 522 - (your._point[5] + STRINGHEIGHT(your))
    STRINGHEIGHT = nil
    return ok, tostring(ok)
end)

-- The Home page (spec 2026-11-02-flat-hub-window-design.md section 5).
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
            and card._width == 288 and card.label._point[1] == "CENTER" and card.label._justifyH == "CENTER" and card.note._justifyH == "CENTER"
        if not good then bad[#bad + 1] = key end
    end
    ok = ok and #bad == 0 and byKey(f, "profile:everyday").skinState.selected == true and byKey(f, "profile:crowded").skinState.selected == false
        and byKey(f, "tab:everyday") == nil and byKey(f, "use") == nil and not hasText(f, "Everything at the highest")
    -- two by two: 306 pixels between the columns, 64 between the rows, each 56 tall
    local original, everyday, crowded = byKey(f, "profile:original"), byKey(f, "profile:everyday"), byKey(f, "profile:crowded")
    local grid = everyday._point[4] - original._point[4] == 306 and everyday._point[5] == original._point[5]
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
    local original = db.active == "original" and hasText(f, "In use now: Original") and hasText(f, ORIGINAL_NOTE)
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

-- The Tests and results page and the About page (spec 2026-11-02-flat-hub-window-design.md section 5).
local TESTS_INTRO = "The test measures what each graphics setting costs on this PC. Run it in a quiet spot first, then in a busy place."

test("S9-1 Tests and results: the two test buttons, a line and a Show results button for each saved result, and the progress line while a test runs", function()
    local e, s = bootWith(fullEntry())
    local opened = {}
    e.ns.ui.openSaved = function(kind) opened[#opened + 1] = kind end
    e.ns.ui.buildContext = function() return { saved = { best = true, crowded = false } } end
    e.ns.ui.savedResult = function(kind)
        if kind == "best" then return { measuredLine = "Measured in Highmountain, 3 days ago." } end
    end
    s.open("tests")
    local f = window()
    local drawn = hasText(f, TESTS_INTRO) and byKey(f, "test:best") ~= nil and byKey(f, "test:crowded") ~= nil
        and hasText(f, "Quiet-spot test: Measured in Highmountain, 3 days ago.") and hasText(f, "Crowd test: not done yet.")
        and byKey(f, "show:best") ~= nil and byKey(f, "show:best")._text == "Show results" and byKey(f, "show:crowded") == nil
        and not hasText(f, "A test is running")
    byKey(f, "show:best"):Click()
    s.click("show:crowded")                                 -- nothing saved: nothing opens
    local routed = table.concat(opened, ",") == "best"
    e.ns.ui.savedResult = function() return { measuredLine = "Measured in Stormwind City, 2 hours ago." } end
    s.open("tests")
    byKey(f, "show:crowded"):Click()
    routed = routed and table.concat(opened, ",") == "best,crowded" and hasText(f, "Crowd test: Measured in Stormwind City, 2 hours ago.")
    e.ns.ui.buildContext = function()
        return { saved = {}, active = true, progress = { phase = "sweep", label = "Shadows 3", cvar = "graphicsShadowQuality", value = "3", done = 12, total = 45 } }
    end
    s.open("tests")
    local running = hasText(f, "A test is running: step 12 of 45 (Now testing: Shadow detail, level 3)")
    e.ns.ui.savedResult = function() error("boom") end        -- the saved results cannot be read: the page still draws, silently
    OUT = {}
    s.open("tests")
    local guarded = hasText(f, "Quiet-spot test: not done yet.") and #OUT == 0
    s.click("page:light")
    local elsewhere = byKey(f, "show:best") == nil and not hasText(f, TESTS_INTRO) and byKey(f, "test:best") == nil
        and not hasText(f, "A test is running")
    return drawn and routed and running and guarded and elsewhere,
        tostring(drawn) .. tostring(routed) .. tostring(running) .. tostring(guarded) .. tostring(elsewhere)
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
    local function line(dynamic) return s.model({ tab = "everyday" }, ctxOf(e, { dynamicScale = dynamic })).dynamicLine end
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
    local none = s.model({ tab = "everyday" }, ctxOf(e, {}))
    local size = s.model({ tab = "everyday", page = "size" }, ctxOf(e, {}))
    local bogus = s.model({ tab = "everyday", page = "nosuchpage" }, ctxOf(e, {}))
    local listed = {}
    for _, p in ipairs(size.pages) do listed[#listed + 1] = p.key .. ":" .. p.text end
    return table.concat(keys, ",") == "home,light,world,size,tests,about"
        and table.concat(texts, "|") == "Home|Light and shadows|World detail|Picture size|Tests and results|About"
        and table.concat(listed, "|") == "home:Home|light:Light and shadows|world:World detail|size:Picture size|tests:Tests and results|about:About"
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
    local view = s.model({ tab = "everyday" }, ctxOf(e, { resolved = resolved }))
    local pages = {}
    for _, row in ipairs(view.rows) do pages[row.cvar] = row.page end
    return #wrong == 0 and pages.graphicsShadowQuality == "light" and pages.graphicsSSAO == "light" and pages.groundEffectDensity == "world"
        and pages.RenderScale == "size" and pages.someUnknownSetting == "world", table.concat(wrong, ",")
end)

test("S5-3 open takes a page, a tab, or nothing: a tab picks its first settings page, nothing keeps the last page (Home the first time)", function()
    local e, s = boot()
    s.open()
    local first = s.state().page == "home"
    s.open("size")
    local sized = s.state().page == "size"
    s.open()
    local kept = s.state().page == "size"
    s.open("crowded")
    local crowded = s.state().tab == "crowded" and s.state().page == "light"
    s.open("everyday")
    local everyday = s.state().tab == "everyday" and s.state().page == "light"
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
    local view = s.model({ tab = "everyday" }, ctxOf(e, { costs = costsOf(e, quietEntry()) }))
    local shadows, clutter = rowOf(view, "graphicsShadowQuality"), rowOf(view, "groundEffectDensity")
    return shadows.mattersWords == "some" and shadows.levels[1].short == "0" and shadows.levels[1].text == "0 (lowest)"
        and shadows.levels[5].short == "4" and shadows.levels[5].text == "4 (highest)" and clutter.levels[1].short == "48"
        and clutter.levels[3].short == "128" and rowOf(view, "RenderScale").levels[1].short == "50%"
        and s.columnsFor(0) == 2 and s.columnsFor(6) == 2 and s.columnsFor(7) == 3 and s.columnsFor(9) == 3,
        tostring(shadows.mattersWords) .. tostring(shadows.levels[1].short)
end)

test("S6-1 the window is flat and 780 by 560, with the header, six page rows and no scroll frame", function()
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
    return f ~= nil and f.name == "ForeverSettingsSettings" and f.template == nil and f._width == 780 and f._height == 560
        and f.titleText._text == "ForeverSettings" and f.close ~= nil and scrolls == 0
        and table.concat(rows, "|") == "Home|Light and shadows|World detail|Picture size|Tests and results|About", table.concat(rows, "|")
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
    local spaced = rowY("size") - rowY("world") == 30 and rowY("tests") - rowY("size") == 44          -- a gap before Tests and results
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
    local levels = first ~= nil and last ~= nil and now ~= nil and first._text == "0" and last._text == "4" and first._width == 36
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
    local twoOk = #two == 2 and two[2] - two[1] == 306
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
    local threeOk = #three == 3 and three[2] - three[1] == 204 and three[3] - three[2] == 204
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

test("S6-6 every button label is centred both ways on one line at its width; the page rows keep theirs at the left", function()
    local e, s = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    local bad = {}
    local count = 0
    for _, b in ipairs(shownButtons(f)) do
        count = count + 1
        local label = b.label
        if b.navItem then
            if not (label._justifyH == "LEFT" and label._justifyV == "MIDDLE") then bad[#bad + 1] = "nav:" .. tostring(b._text) end
        else
            if not (label._point and label._point[1] == "CENTER" and label._justifyH == "CENTER" and label._justifyV == "MIDDLE"
                and label._wordWrap == false) then bad[#bad + 1] = "centre:" .. tostring(b._text) end
            if #(b._text or "") * 6.5 > b._width - 8 then bad[#bad + 1] = "wide:" .. tostring(b._text) end
        end
    end
    local use, maximum = byKey(f, "use"), byKey(f, "maximum")
    return count >= 14 and #bad == 0 and use._width == 230 and use._height == 26 and maximum._width == 160 and maximum._height == 26,
        table.concat(bad, ",") .. " " .. count
end)

test("S6-7 the footer holds Use what I have in the game now and Switch to Maximum, right-aligned; Maximum goes while it is in use; both grey when locked", function()
    local e, s = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    local use, maximum = byKey(f, "use"), byKey(f, "maximum")
    local placed = use ~= nil and maximum ~= nil and maximum._point[1] == "BOTTOMRIGHT" and maximum._point[4] == -16
        and use._point[1] == "BOTTOMRIGHT" and use._point[4] == -(16 + 160 + 8) and use._text == "Use what I have in the game now"
        and maximum._text == "Switch to Maximum" and use.enabled == true and maximum.enabled == true
    COMBAT = true
    s.open("everyday")
    local greyed = byKey(f, "use").enabled == false and byKey(f, "maximum").enabled == false
    COMBAT = false
    local e2, s2, _, p2 = bootWith(fullEntry())
    p2.switch("maximum", true)
    s2.open("everyday")
    local f2 = window()
    local inMaximum = byKey(f2, "maximum") == nil and byKey(f2, "use") ~= nil and byKey(f2, "use")._point[4] == -16
    return placed and greyed and inMaximum, tostring(placed) .. tostring(greyed) .. tostring(inMaximum)
end)

test("S6-8 the summary block stands above the footer: the live line, the total and the matters note, bottom-up", function()
    local e, s = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    local your = fontStringWith(f, "Your Everyday settings: about 270 fps (an estimate; settings affect each other).")
    local total = fontStringWith(f, "Everything at the highest: about 152 fps.")
    local note = fontStringWith(f, MATTERS_NOTE)
    STRINGHEIGHT = function() return 14 end
    local ok = your ~= nil and total ~= nil and note ~= nil and your._point[1] == "BOTTOMLEFT" and your._point[4] == 167
        and note._point[5] >= 44 and total._point[5] >= note._point[5] + 14 and your._point[5] >= total._point[5] + 14
    STRINGHEIGHT = nil
    local e2, s2 = bootWith(nil)
    s2.open("everyday")
    local none = not hasText(window(), "Your Everyday settings") and not hasText(window(), "Everything at the highest")
    return ok and none, tostring(ok) .. tostring(none)
end)

test("S6-9 the Everyday and Crowded switch changes the tab and marks it; the notices stand as one banner", function()
    local e, s = bootWith(fullEntry(), { active = "maximum" })
    s.open("everyday")
    local f = window()
    local everyday, crowded = byKey(f, "tab:everyday"), byKey(f, "tab:crowded")
    local start = everyday ~= nil and crowded ~= nil and everyday.skinState.selected == true and crowded.skinState.selected == false
        and everyday._width == 120 and hasText(f, MAX_ON)
    crowded:Click()
    local moved = s.state().tab == "crowded" and byKey(f, "tab:crowded").skinState.selected == true and byKey(f, "tab:everyday").skinState.selected == false
    return start and moved and #OUT == 0, tostring(start) .. tostring(moved)
end)

test("S6-10 in combat every control is greyed with the reason shown, clicks write nothing, and the pages still switch", function()
    local e, s = bootWith(fullEntry())
    COMBAT = true
    s.open("everyday")
    local f = window()
    local greyed = byKey(f, "level:graphicsShadowQuality:3").enabled == false and byKey(f, "keep:graphicsShadowQuality").enabled == false
        and byKey(f, "tab:crowded").enabled == false and byKey(f, "use").enabled == false and hasText(f, COMBAT_TEXT)
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
