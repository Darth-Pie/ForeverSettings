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
    local highlighted = byKey(f, "level:graphicsShadowQuality:0").locked == true and byKey(f, "level:graphicsShadowQuality:2").locked ~= true
    return before and after and highlighted, tostring(byKey(f, "tab:crowded")._text)
end)

test("S1-12 the window: title, tabs, a tick and level buttons per row, footer buttons, Escape once, wrapped levels, no raw names", function()
    local e, s, db = boot()
    local b = e.ns.bench
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" }
    s.open("everyday")
    s.open("everyday")
    local f = window()
    if not f then return false, "no window: " .. outText() end
    local keeps, levels = 0, 0
    walk(f, function(frame)
        if frame.shown and frame.key and frame.key:sub(1, 5) == "keep:" then keeps = keeps + 1 end
        if frame.shown and frame.key and frame.key:sub(1, 6) == "level:" then levels = levels + 1 end
    end)
    local listed = 0
    for _, name in ipairs(UISpecialFrames) do if name == "ForeverSettingsSettings" then listed = listed + 1 end end
    local raw = false
    for _, text in ipairs(shownTexts(f)) do
        for _, name in ipairs(RAW) do if text:find(name, 1, true) then raw = true end end
    end
    local keepBox = byKey(f, "keep:graphicsShadowQuality")
    local live = byKey(f, "level:graphicsShadowQuality:2")
    local keptNow, liveHighlighted = keepBox ~= nil and keepBox.checked == true, live ~= nil and live.locked == true
    local titled = hasText(f, "My settings") and hasText(f, INTRO) and hasText(f, "Shadow detail") and hasText(f, "Everyday (in use)")
    byKey(f, "tab:crowded"):Click()
    local switched = s.state().tab == "crowded"
    local closeButton, useButton
    walk(f, function(frame)
        if frame.kind == "Button" and frame.shown and frame._text == "Close" then closeButton = frame end
        if frame.kind == "Button" and frame.shown and frame._text == "Use what I have in the game now" then useButton = frame end
    end)
    local footer = closeButton ~= nil and useButton ~= nil
    if closeButton then closeButton:Click() end
    return titled and keptNow and liveHighlighted and switched and footer and not f:IsShown() and listed == 1 and keeps == 4
        and levels == 5 + 13 + 3 + 6 and not raw,
        tostring(keeps) .. " " .. tostring(levels) .. " " .. tostring(listed) .. " " .. tostring(raw)
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

test("S2-9 the window draws the costs under the level buttons, the matters lines, the notes, the total and the third button, and hides them again", function()
    local e, s, db, p = bootWith(fullEntry())
    s.open("everyday")
    local f = window()
    local view = s.model(s.state(), ctxOf(e, { costs = costsOf(e, fullEntry()),
        maximum = { fps = 151.5, skipped = 0, leftOut = 0 } }))
    local match, drawnCosts = true, 0
    for _, row in ipairs(view.rows) do
        for _, level in ipairs(row.levels) do
            local text, fs = costFor(f, row.cvar, level.value)
            if level.cost then
                drawnCosts = drawnCosts + 1
                if text ~= level.cost or fs._width ~= 100 then match = false end
            elseif text ~= nil then
                match = false
            end
        end
    end
    local matters = fontStringWith(f, "Matters to the picture: some.") ~= nil and fontStringWith(f, "Matters to the picture: a lot.") ~= nil
    local line = fontStringWith(f, "Matters to the picture: some.")
    local shadowsName = fontStringWith(f, "Shadow detail")
    local mattersBelowName = line ~= nil and shadowsName ~= nil and -line._point[5] > -shadowsName._point[5]
    local notes = hasText(f, COST_QUIET) and hasText(f, MATTERS_NOTE) and hasText(f, "Everything at the highest: about 152 fps.")
        and byKey(f, "maximum") ~= nil and byKey(f, "maximum")._text == "Switch to Maximum"
    -- the footer buttons stand side by side, a gap apart, inside the window's 580 pixels
    local function footerFits(count)
        local last, shown = -290, 0
        for _, key in ipairs({ "use", "maximum", "close" }) do
            local b = byKey(f, key)
            if b then
                shown = shown + 1
                local left, right = b._point[4] - b._width / 2, b._point[4] + b._width / 2
                if left - last < 8 and shown > 1 or left < -270 or right > 270 then return false end
                last = right
            end
        end
        return shown == count
    end
    local footer3 = footerFits(3)
    local withCosts = {
        shadows = -byKey(f, "keep:graphicsSSAO")._point[5] + byKey(f, "keep:graphicsShadowQuality")._point[5],
        clutter = -byKey(f, "keep:RenderScale")._point[5] + byKey(f, "keep:groundEffectDensity")._point[5],
    }
    -- a draw with no test: the second lines, the note and the total go away, the rows are shorter, the matters lines stay
    e.ns.bench.state().history[1] = nil
    s.open("everyday")
    local gone = costFor(f, "graphicsShadowQuality", "0") == nil and not hasText(f, "Everything at the highest")
        and hasText(f, COST_NONE) and not hasText(f, COST_QUIET) and hasText(f, MATTERS_NOTE) and hasText(f, "Matters to the picture: some.")
    local without = {
        shadows = -byKey(f, "keep:graphicsSSAO")._point[5] + byKey(f, "keep:graphicsShadowQuality")._point[5],
        clutter = -byKey(f, "keep:RenderScale")._point[5] + byKey(f, "keep:groundEffectDensity")._point[5],
    }
    -- a row with costs is 14 pixels taller for every line of level buttons it has: Shadows has two (5 levels, 4 to a line)
    local taller = withCosts.shadows - without.shadows == 28 and withCosts.clutter - without.clutter == 14
    -- with Maximum in use the third button goes
    p.switch("maximum", true)
    s.open("everyday")
    local noButton = byKey(f, "maximum") == nil and footerFits(2)
    return match and drawnCosts > 0 and matters and mattersBelowName and notes and footer3 and gone and taller and noButton,
        tostring(match) .. tostring(drawnCosts) .. tostring(matters) .. tostring(mattersBelowName) .. tostring(notes) .. tostring(footer3)
            .. tostring(gone) .. tostring(taller) .. tostring(noButton) .. " " .. tostring(withCosts.shadows - without.shadows) .. "/"
            .. tostring(withCosts.clutter - without.clutter)
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

test("S2-9b a client that wraps at 9 pixels a letter still has every note above the buttons and clear of the rows", function()
    local e, s, db, p = bootWith(quietEntry())
    CVARS.graphicsComputeEffects = "1"
    p.switch("maximum", true)
    STRINGHEIGHT = function(fs)
        local text = fs._text or ""
        local perLine = math.max(1, math.floor((fs._width or 520) / 9))
        return 14 * math.max(1, math.ceil(#text / perLine))
    end
    s.open("everyday")
    local f = window()
    local function top(fs) return -fs._point[5] end
    local function bottom(fs) return top(fs) + STRINGHEIGHT(fs) end
    local header = { fontStringWith(f, "My settings"), fontStringWith(f, "Choose how the game looks. Settings you tick are kept: the addon puts them back at every loading screen."),
        fontStringWith(f, "Settings for normal play."), fontStringWith(f, "Costs from your quiet-spot test. Measured in Highmountain, 3 days ago.") }
    local notice
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text and fs._text:find(MAX_ON, 1, true) then notice = fs end
        end
    end)
    header[#header + 1] = notice
    local ordered = true
    for i = 1, #header - 1 do
        if not header[i] or not header[i + 1] or bottom(header[i]) > top(header[i + 1]) then ordered = false end
    end
    local total = fontStringWith(f, "The test skipped the highest levels of 4 settings, so there is no total yet. Run Find my best settings and choose Thorough.")
    local mattersNote = fontStringWith(f, MATTERS_NOTE)
    local buttons = byKey(f, "use")
    -- the bottom block is stacked up from the buttons: total, then the matters note, each clear of the one below it
    local bottomUp = total ~= nil and mattersNote ~= nil and total._point[1] == "BOTTOMLEFT" and mattersNote._point[1] == "BOTTOMLEFT"
        and total._point[5] >= 38 and mattersNote._point[5] >= total._point[5] + STRINGHEIGHT(total)
    local headerBottom = header[#header] and bottom(header[#header]) or 9999
    -- the rows' scroll area ends above the stacked block and still has room: from the last header line down to it
    local scroll
    walk(f, function(frame) if frame.kind == "ScrollFrame" then scroll = frame end end)
    local scrollBottom = scroll and scroll._point and scroll._point[5] or 0
    local clear = mattersNote ~= nil and scrollBottom >= mattersNote._point[5] + STRINGHEIGHT(mattersNote)
    local room = 540 - scrollBottom - headerBottom
    STRINGHEIGHT = nil
    return ordered and bottomUp and clear and room >= 120 and buttons ~= nil,
        tostring(ordered) .. tostring(bottomUp) .. tostring(clear) .. " header " .. tostring(headerBottom) .. " room " .. tostring(room)
end)

test("S2-10 no raw setting name in any text this change adds", function()
    local e, s = bootWith(fullEntry())
    CVARS.graphicsComputeEffects = "1"
    local function names(view)
        local list = { view.costNote or "", view.mattersNote or "", view.totalLine or "", view.notice or "", view.locked or "" }
        for _, row in ipairs(view.rows) do
            list[#list + 1] = row.matters or ""
            for _, level in ipairs(row.levels) do list[#list + 1] = level.cost or "" end
        end
        for _, button in ipairs(view.buttons) do list[#list + 1] = button.text end
        return table.concat(list, "\n")
    end
    local costs = costsOf(e, fullEntry())
    local text = names(s.model({ tab = "everyday" }, ctxOf(e, { costs = costs, maximum = { fps = 151.5, skipped = 0, leftOut = 2 } })))
        .. names(s.model({ tab = "everyday" }, ctxOf(e, { active = "maximum", costs = costs, maximum = { skipped = 3, leftOut = 1 } })))
        .. names(s.model({ tab = "crowded", notice = NOTHING }, ctxOf(e, {})))
    local raw
    for _, name in ipairs(RAW) do
        if text:find(name, 1, true) then raw = name end
    end
    return raw == nil, tostring(raw)
end)

return H.results()
