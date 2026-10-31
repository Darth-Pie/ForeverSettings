-- Tests for Results.lua (spec 2026-10-29-recommender-design.md section 5), driven through the shared harness. They read
-- what a player can see: the shown texts, the buttons' labels and the colour, size and position of each bar.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function boot(cvars, opts)
    opts = opts or {}
    opts.fresh = true
    local e = H.boot(cvars or { graphicsShadowQuality = "4", graphicsSSAO = "3", RenderScale = "1" }, opts)
    return e, e.ns.results
end
local function outText() return table.concat(OUT, " | ") end
local function near(a, b, eps) return a ~= nil and math.abs(a - b) <= (eps or 1e-6) end

-- The recommender's shared fixture (see test_recommend.lua): T1 is Shadows and SSAO at their best levels, baseline 4.0 ms.
local LABEL = { graphicsShadowQuality = "Shadows", graphicsSSAO = "SSAO" }
local function rows(cvar, baseline, levels)
    local list = {}
    for _, l in ipairs(levels) do
        local r = { setting = LABEL[cvar] or cvar, cvar = cvar, value = l[1], flags = {} }
        if l.status then
            r.status, r.reason = l.status, "x"
        else
            r.deltaMs, r.meanMs = l[2], baseline + l[2]
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
local function T1()
    return entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "0", -0.6 }, { "1", -0.3 }, { "2", 0, current = true } }))
end

-- Finding things on the window
local function window()
    for _, f in ipairs(H.frames()) do
        if f.name == "ForeverSettingsResults" then return f end
    end
end
local function walk(f, fn)
    fn(f)
    for _, c in ipairs(f.children) do walk(c, fn) end
end
local function texts(f)
    local list = {}
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text and fs._text ~= "" then list[#list + 1] = fs._text end
        end
    end)
    return list
end
local function allText(f) return table.concat(texts(f), "\n") end
local function hasText(f, part) return allText(f):find(part, 1, true) ~= nil end
local function countContaining(f, part)
    local n = 0
    for _, t in ipairs(texts(f)) do
        if t:find(part, 1, true) then n = n + 1 end
    end
    return n
end
local function countExact(f, text)
    local n = 0
    for _, t in ipairs(texts(f)) do
        if t == text then n = n + 1 end
    end
    return n
end
local function sameColor(a, b)
    if not a then return false end
    for i = 1, 4 do
        if math.abs(a[i] - b[i]) > 1e-9 then return false end
    end
    return true
end
local function texturesOf(f, color)
    local list = {}
    walk(f, function(frame)
        for _, tex in ipairs(frame.textures) do
            if tex.shown and sameColor(tex._color, color) then list[#list + 1] = tex end
        end
    end)
    return list
end
local function findButton(f, label)
    local found
    walk(f, function(frame)
        if not found and frame.kind == "Button" and frame.shown and frame._text == label then found = frame end
    end)
    return found
end
local function listed()
    local n = 0
    for _, name in ipairs(UISpecialFrames) do
        if name == "ForeverSettingsResults" then n = n + 1 end
    end
    return n
end
local function emptyEveryday(e)
    e.ns.db().profiles.everyday.values = {}
end
local APPLIED = "Saved as your Everyday settings and switched on. Your original settings are kept: choose Original in the minimap menu to go back."
local SAVE_E, SAVE_C = "Save these as my Everyday settings", "Save these as my Crowded settings"
local REPL_E, REPL_C = "Replace my Everyday settings with these", "Replace my Crowded settings with these"

-- The setting list and the graph, as the window draws them
local GOLD = { 1.00, 0.82, 0.00, 1 }
local function rowsOf(f)       -- the setting list: one button per setting, key "setting:<cvar>", in the order drawn
    local list = {}
    walk(f, function(frame)
        if frame.kind == "Button" and frame.shown and type(frame.key) == "string" and frame.key:sub(1, 8) == "setting:" then
            list[#list + 1] = frame
        end
    end)
    return list
end
local function rowNames(f)
    local out = {}
    for i, row in ipairs(rowsOf(f)) do out[i] = row.label._text end
    return table.concat(out, "|")
end
local function pointButtons(f)  -- the buttons over the graph's points: buttons with no key
    local list = {}
    walk(f, function(frame)
        if frame ~= f and frame.kind == "Button" and frame.shown and frame.key == nil then list[#list + 1] = frame end
    end)
    return list
end
local function dotsIn(f)       -- the small marks beside the settings the test changes
    local n = 0
    for _, tex in ipairs(texturesOf(f, GOLD)) do
        if tex._width == 6 and tex._height == 6 then n = n + 1 end
    end
    return n
end

test("RW-1 show opens a window with the headline, the changes and the footer, listed for Escape once", function()
    local e, r = boot()
    r.show(T1(), 250)
    r.show(T1(), 250)
    local f = window()
    if not f then return false, "no window: " .. outText() end
    return f:IsShown() and listed() == 1 and hasText(f, "Now: about 250 fps") and hasText(f, "With these changes: about 333 fps")
        and hasText(f, "Your target: 250 fps") and hasText(f, "Shadow detail: 2 to 1, saves about 28 fps.")
        and hasText(f, "Soft corner shadows: 2 to 0, saves about 44 fps.")
        and hasText(f, "Bars show speed on your PC in an empty spot, not how the picture looks."), allText(f)
end)

test("RW-2 chart A: the now and after bars are in the proportion of their frame rates and the target line stands at its fraction", function()
    local e, r = boot()
    r.show(T1(), 300)         -- now 250 fps, after 416.7 fps, target 300: the scale is 500, so the fractions are 0.5, 0.833, 0.6
    local f = window()
    local now, after, line = texturesOf(f, r.COLORS.now)[1], texturesOf(f, r.COLORS.after)[1], texturesOf(f, r.COLORS.target)[1]
    if not (now and after and line) then return false, "missing bar or line" end
    return near(after._width / now._width, 0.83333 / 0.5, 0.01) and near(after._point[4], now._point[4])
        and near(line._point[4] - now._point[4], 1.2 * now._width, 1e-6), tostring(now._width) .. " " .. tostring(after._width)
end)

test("RW-4 Save hands the changed values to Everyday once, says so in the window and not in chat, and stays open", function()
    local e, r = boot()
    emptyEveryday(e)
    local calls = {}
    e.ns.profiles.adopt = function(name, values, silent) calls[#calls + 1] = { name, values, silent } return true, { changed = 2, mismatched = {} } end
    -- A third setting that stays where it is: only what changes is handed over.
    local en = T1()
    for _, row in ipairs(rows("graphicsComputeEffects", 4.0, { { "0", -0.1 }, { "1", 0, current = true } })) do
        en.rows[#en.rows + 1] = row
    end
    r.show(en, 250)
    local f = window()
    local button = findButton(f, SAVE_E)
    if not button then return false, "no button: " .. allText(f) end
    button:Click()
    local first = #calls == 1 and calls[1][1] == "everyday" and calls[1][2].graphicsShadowQuality == "1"
        and calls[1][2].graphicsSSAO == "0" and calls[1][2].graphicsComputeEffects == nil and calls[1][3] == true
    local said = countExact(f, APPLIED) == 1 and outText() == ""
    r.click("apply")      -- a second click after it has saved does nothing more
    return first and said and f:IsShown() and #calls == 1 and findButton(f, SAVE_E) == nil, tostring(#calls) .. " " .. outText()
end)

test("RW-5 the button says Replace when Everyday holds values; Close closes and writes nothing", function()
    local e, r = boot()
    emptyEveryday(e)
    local calls = 0
    e.ns.profiles.adopt = function() calls = calls + 1 return true, {} end
    r.show(T1(), 250)
    local f = window()
    local plain = findButton(f, SAVE_E) ~= nil and findButton(f, REPL_E) == nil
    e.ns.db().profiles.everyday.values = { graphicsShadowQuality = "3" }
    r.show(T1(), 250)
    local replace = findButton(f, REPL_E) ~= nil and findButton(f, SAVE_E) == nil
    local before = e.ns.db().profiles.everyday.values.graphicsShadowQuality
    findButton(f, "Close"):Click()
    return plain and replace and calls == 0 and not f:IsShown() and e.ns.db().profiles.everyday.values.graphicsShadowQuality == before,
        tostring(plain) .. tostring(replace) .. calls
end)

test("RW-6 with nothing to change the Save button still shows, with the sentence; with the target out of reach only Close does", function()
    local e, r = boot()
    emptyEveryday(e)
    r.show(T1(), 100)
    local f = window()
    local none = findButton(f, SAVE_E) ~= nil
        and hasText(f, "Good news: your settings already hold 100 fps with room to spare. Nothing to change.")
        and findButton(f, "Close") ~= nil
    r.show(T1(), 500)
    local unreachable = findButton(f, SAVE_E) == nil and findButton(f, REPL_E) == nil and hasText(f, "short of your 500")
    findButton(f, "Close"):Click()
    return none and unreachable and not f:IsShown(), allText(f)
end)

test("RW-7 in combat the apply button is greyed with the reason and comes back when combat ends", function()
    local e, r = boot()
    emptyEveryday(e)
    COMBAT = true
    r.show(T1(), 250)
    local f = window()
    local button = findButton(f, SAVE_E)
    local greyed = button ~= nil and button:IsEnabled() == false and hasText(f, "You are in combat; try again afterwards.")
    COMBAT = false
    f.scripts.OnUpdate(f, 0.6)
    return greyed and button:IsEnabled() == true and not hasText(f, "You are in combat"), allText(f)
end)

test("RW-8 when the switch is refused the window stays open and says why; the next click saves", function()
    local e, r = boot()
    emptyEveryday(e)
    local answer = { false, "busy" }
    e.ns.profiles.adopt = function() return answer[1], answer[2] end
    r.show(T1(), 250)
    local f = window()
    findButton(f, SAVE_E):Click()
    local stayed = f:IsShown() and hasText(f, "A test is running; try again afterwards.") and findButton(f, SAVE_E) ~= nil
    answer = { true, {} }
    findButton(f, SAVE_E):Click()
    return stayed and f:IsShown() and countExact(f, APPLIED) == 1 and not hasText(f, "A test is running") and outText() == "", allText(f)
end)

test("RW-11 once the window has been closed by its title bar nothing can be applied from it", function()
    local e, r = boot()
    emptyEveryday(e)
    local calls = 0
    e.ns.profiles.adopt = function() calls = calls + 1 return true, {} end
    r.show(T1(), 250)
    local f = window()
    f:Hide()
    r.click("apply")
    return calls == 0 and not f:IsShown(), tostring(calls)
end)

test("RW-12 a redraw that needs fewer bars than the one before leaves nothing of it behind and raises nothing", function()
    local e, r = boot()
    emptyEveryday(e)
    r.show(T1(), 250, nil, { again = "setup" })   -- a change: three headline bars, three buttons, a graph with a recommended point
    r.show(T1(), 100)                    -- nothing to change: two headline bars, Save and Close, no recommended point
    local f = window()
    local second = not outText():find("could not be drawn", 1, true) and not hasText(f, "With these changes")
        and not hasText(f, "saves about") and findButton(f, SAVE_E) ~= nil and findButton(f, "Run it again") == nil
        and findButton(f, "Not now") == nil and findButton(f, "Close") ~= nil
        and hasText(f, "Good news: your settings already hold 100 fps with room to spare. Nothing to change.")
        and countExact(f, "now") == 1 and countExact(f, "recommended") == 0
    r.show(T1(), 500)                    -- out of reach: only Close is left
    local third = findButton(f, SAVE_E) == nil and findButton(f, "Run it again") == nil and findButton(f, "Close") ~= nil
        and hasText(f, "short of your 500")
    r.show(T1(), 250)                    -- and a change again: everything comes back, once
    return second and third and countContaining(f, "Now: about") == 1 and countExact(f, "now") == 1 and countExact(f, "recommended") == 1
        and findButton(f, SAVE_E) ~= nil and findButton(f, "Close") ~= nil
        and not outText():find("could not be drawn", 1, true), outText()
end)

test("RW-13 a run that measured nothing says so, never that the settings hold, and offers only Close", function()
    local e, r = boot()
    local en = entry(4.75,
        rows("graphicsShadowQuality", 3.44, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }),
        rows("graphicsSSAO", 3.8, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }))
    r.show(en, 165)
    local f = window()
    return hasText(f, "couldn't get a steady reading") and not hasText(f, "already hold") and not hasText(f, "room to spare")
        and findButton(f, SAVE_E) == nil and findButton(f, "Close") ~= nil
        and rowNames(f) == "Shadow detail|Soft corner shadows"
        and countExact(f, "Shadow detail: not measured (the test couldn't measure it)") == 1
        and hasText(f, "Now: about 211 fps"), allText(f)
end)

-- Crowd test, Task 9: the crowd's results (spec 2026-10-29-crowd-test-design.md sections 5 and 6)
local function Q()
    local e = T1()
    e.starts = { graphicsShadowQuality = "2", graphicsSSAO = "2" }
    return e
end
local function C1(shadowsLow, ssaoLow)
    return { valid = true, baselineMs = 10.0, starts = { graphicsShadowQuality = "2", graphicsSSAO = "2" },
        settings = {
            { cvar = "graphicsShadowQuality", setting = "Shadows", lowValue = "0", lowDelta = shadowsLow or -3.0 },
            { cvar = "graphicsSSAO", setting = "SSAO", lowValue = "0", lowDelta = ssaoLow or -0.6 },
        } }
end
local function crowdFor(e, shadowsLow, ssaoLow) return e.ns.recommend.crowdEntry(Q(), C1(shadowsLow, ssaoLow)) end
local function emptyCrowded(e) e.ns.db().profiles.crowded.values = {} end
local CROWD_APPLIED = "Saved as your Crowded settings and switched on. Your original settings are kept: choose Everyday or Original in the minimap menu "
    .. "to go back, or use the key you bound to toggle Everyday and Crowded."
local CROWD_FOOTER = "Each setting's lowest level was measured in this crowd; the levels in between are estimated from your quiet-spot test."
local HINT = "Next, in a busy place: Find my crowded settings (minimap menu or /fset crowd)."

test("RW-14 a crowd result has its own title and footer, the crowd's changes, and a Save button for Crowded", function()
    local e, r = boot()
    emptyCrowded(e)
    r.show(crowdFor(e), 100)
    local f = window()
    if not f then return false, "no window: " .. outText() end
    local crowdText = allText(f)
    local function has(str) return crowdText:find(str, 1, true) ~= nil end
    local crowdOk = has("Your crowded settings") and not has("Your best settings") and has(CROWD_FOOTER)
        and has("Shadow detail: 2 to 1, saves about 14 fps.") and has("Your target: 100 fps") and findButton(f, SAVE_C) ~= nil
    r.show(T1(), 250)
    local everydayOk = f:IsShown() and hasText(f, "Your best settings") and not hasText(f, "Your crowded settings")
    return crowdOk and everydayOk, tostring(crowdOk) .. " " .. tostring(everydayOk) .. "\n" .. crowdText
end)

test("RW-15 Save writes the changed values to Crowded, says so in the window, and the labels never mix Crowded with Everyday", function()
    local e, r = boot()
    emptyCrowded(e)
    emptyEveryday(e)
    local calls = {}
    e.ns.profiles.adopt = function(name, values, silent) calls[#calls + 1] = { name, values, silent } return true, { changed = 1, mismatched = {} } end
    r.show(crowdFor(e), 100)
    local f = window()
    local plain = findButton(f, SAVE_C) ~= nil and findButton(f, REPL_C) == nil
    findButton(f, SAVE_C):Click()
    local applied = #calls == 1 and calls[1][1] == "crowded" and calls[1][2].graphicsShadowQuality == "1"
        and next(calls[1][2], next(calls[1][2])) == nil and calls[1][3] == true and f:IsShown()
    local said = countExact(f, CROWD_APPLIED) == 1 and outText() == ""
    e.ns.db().profiles.crowded.values = { graphicsShadowQuality = "3" }
    r.show(crowdFor(e), 100)
    local replaceCrowd = findButton(f, REPL_C) ~= nil and findButton(f, SAVE_C) == nil
    e.ns.db().profiles.crowded.values = {}
    e.ns.db().profiles.everyday.values = { graphicsShadowQuality = "3" }
    r.show(crowdFor(e), 100)
    local crowdIgnoresEveryday = findButton(f, SAVE_C) ~= nil and findButton(f, REPL_C) == nil
    r.show(T1(), 250)
    local everydayOwn = findButton(f, REPL_E) ~= nil
    e.ns.db().profiles.everyday.values = {}
    e.ns.db().profiles.crowded.values = { graphicsShadowQuality = "3" }
    r.show(T1(), 250)
    local everydayIgnoresCrowd = findButton(f, SAVE_E) ~= nil and findButton(f, REPL_E) == nil
    return plain and applied and said and replaceCrowd and crowdIgnoresEveryday and everydayOwn and everydayIgnoresCrowd, outText()
end)

test("RW-16 the check shows under the changes and replaces the estimate in the after bar; no check, no line", function()
    local e, r = boot()
    r.show(crowdFor(e), 100, { ok = true, appliedMs = 8.5, baselineMs = 10.0 })
    local f = window()
    local now, after = texturesOf(f, r.COLORS.now)[1], texturesOf(f, r.COLORS.after)[1]
    local measured = hasText(f, "Checked: expected about 114 fps, measured about 118 fps.")
        and hasText(f, "With these changes: about 118 fps (measured)") and not hasText(f, "The estimate was optimistic")
        and now and after and near(after._width / now._width, 117.647 / 100, 0.01)
    r.show(crowdFor(e), 100, { ok = true, appliedMs = 12.0, baselineMs = 10.0 })
    local optimistic = hasText(f, "Checked: expected about 114 fps, measured about 83 fps.")
        and hasText(f, "The estimate was optimistic: about 83 fps is what to expect.")
    r.show(crowdFor(e), 100)
    local none = not hasText(f, "Checked:") and hasText(f, "With these changes: about 114 fps") and not hasText(f, "(measured)")
    r.show(crowdFor(e), 100, { ok = false, reason = "movement" })
    local failed = not hasText(f, "Checked:") and not hasText(f, "(measured)")
    return measured and optimistic and none and failed, allText(f)
end)

test("RW-17 the Everyday window ends with the pointer to the crowd test unless there was no reading; the crowd window never shows it", function()
    local e, r = boot()
    r.show(T1(), 250)
    local f = window()
    local change = hasText(f, HINT)
    r.show(T1(), 100)
    local nochange = hasText(f, HINT)
    r.show(T1(), 500)
    local unreachable = hasText(f, HINT)
    r.show(entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", status = "inconclusive" }, { "2", status = "inconclusive" } })), 165)
    local nodata = hasText(f, HINT)
    r.show(crowdFor(e), 100)
    local crowd = hasText(f, HINT)
    return change and nochange and unreachable and not nodata and not crowd, allText(f)
end)

test("RW-18 Save for Crowded is refused in combat before anything is written", function()
    local e, r = boot()
    emptyCrowded(e)
    local db = e.ns.db()
    local activeBefore = db.active
    COMBAT = true
    r.show(crowdFor(e), 100)
    local f = window()
    local greyed = findButton(f, SAVE_C):IsEnabled() == false and hasText(f, "You are in combat; try again afterwards.")
    r.click("apply")
    COMBAT = false
    return greyed and next(db.profiles.crowded.values) == nil and db.active == activeBefore and f:IsShown() and outText() == "", allText(f)
end)

test("RW-19 drawing a crowd window over an Everyday one, and back, leaves nothing of the other behind and raises nothing", function()
    local e, r = boot()
    r.show(crowdFor(e), 100, { ok = true, appliedMs = 8.5, baselineMs = 10.0 })
    local f = window()
    r.show(T1(), 250)
    local everyday = countContaining(f, "Your best settings") == 1 and countContaining(f, "Your crowded settings") == 0
        and countContaining(f, "Checked:") == 0 and countContaining(f, CROWD_FOOTER) == 0 and countContaining(f, HINT) == 1
    r.show(crowdFor(e), 100)
    local crowd = countContaining(f, "Your crowded settings") == 1 and countContaining(f, "Your best settings") == 0
        and countContaining(f, HINT) == 0 and countContaining(f, "Bars show speed on your PC in an empty spot") == 0
    return everyday and crowd and not hasText(f, "could not be drawn") and not outText():find("could not be drawn", 1, true), outText()
end)

test("RW-20 a crowd where nothing saves much is shown with its sentence and only a Close button", function()
    local e, r = boot()
    emptyCrowded(e)
    r.show(crowdFor(e, -0.05, -0.02), 144)
    local f = window()
    return hasText(f, "Your crowded settings") and hasText(f, "limited by something other than graphics settings")
        and findButton(f, "Close") ~= nil and findButton(f, SAVE_C) == nil
        and findButton(f, REPL_C) == nil, allText(f)
end)

test("RW-9 a window that cannot be drawn prints the changes and says so once", function()
    local e, r = boot()
    local real = _G.CreateFrame
    _G.CreateFrame = function() error("no frames today") end
    local ok1 = pcall(r.show, T1(), 250)
    local ok2 = pcall(r.show, T1(), 250)
    _G.CreateFrame = real
    local said = 0
    for _, line in ipairs(OUT) do
        if line:find("the results window could not be drawn", 1, true) then said = said + 1 end
    end
    return ok1 and ok2 and said == 1 and outText():find("no frames today", 1, true) ~= nil
        and outText():find("Shadow detail: 2 to 1, saves about 28 fps.", 1, true) ~= nil
        and outText():find("Soft corner shadows: 2 to 0, saves about 44 fps.", 1, true) ~= nil, tostring(said) .. " " .. outText()
end)

test("RW-10 a setting with no usable measurement is listed greyed with its reason and has no graph or heading", function()
    local e, r = boot()
    local en = entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } }))
    r.show(en, 250)
    local f = window()
    local listed = rowsOf(f)[2] ~= nil and rowsOf(f)[2].label._text == "Soft corner shadows" and rowsOf(f)[2].label._textColor[1] < 0.7
        and countExact(f, "Soft corner shadows: fps if only this setting changes") == 0
    rowsOf(f)[2]:Click()
    return listed and countExact(f, "Soft corner shadows: not measured (the test couldn't measure it)") == 1 and countExact(f, "Shadow detail") == 1,
        allText(f)
end)

-- Words and menu, Task 6: plain words, and the extras of a result opened from the menu
local function renderScaleEntry()
    return entry(5.5, rows("RenderScale", 5.5, { { "0.5", -1.8 }, { "0.7", -1.0 }, { "1", 0, current = true } }))
end

test("RW-21 the window draws plain setting names and level words, never the raw ones", function()
    local e, r = boot()
    r.show(T1(), 250)
    local f = window()
    local first = hasText(f, "Shadow detail") and hasText(f, "Soft corner shadows") and countExact(f, "Shadows") == 0
        and countExact(f, "SSAO") == 0
    r.show(renderScaleEntry(), 165)
    return first and hasText(f, "Picture sharpness: 100% to 70%, saves about 40 fps.") and countExact(f, "Picture sharpness") == 1
        and countExact(f, "50%") == 1 and countExact(f, "70%") == 1 and countExact(f, "100%") == 1 and countExact(f, "0.7") == 0
        and not hasText(f, "RenderScale") and not hasText(f, "Render scale"), allText(f)
end)

test("RW-22 a result opened from the menu says where and when it was measured; without extras the line is absent", function()
    local e, r = boot()
    r.show(T1(), 250, nil, { measuredLine = "Measured in Highmountain, 3 days ago." })
    local f = window()
    local shown = hasText(f, "Measured in Highmountain, 3 days ago.")
    r.show(T1(), 250)
    return shown and not hasText(f, "Measured"), allText(f)
end)

test("RW-23 Run it again shows only for a result opened from the menu, and it closes the window and opens that test", function()
    local e, r = boot()
    emptyEveryday(e)
    local opened = {}
    e.ns.guide.open = function(kind) opened[#opened + 1] = kind end
    r.show(T1(), 250, nil, { again = "setup" })
    local f = window()
    local three = findButton(f, SAVE_E) ~= nil and findButton(f, "Run it again") ~= nil and findButton(f, "Close") ~= nil
    findButton(f, "Run it again"):Click()
    local closed = not f:IsShown() and #opened == 1 and opened[1] == "setup"
    r.show(T1(), 100, nil, { again = "crowd" })
    local noChange = findButton(f, "Run it again") ~= nil and findButton(f, "Close") ~= nil and findButton(f, SAVE_E) ~= nil
    findButton(f, "Run it again"):Click()
    r.show(T1(), 250)
    local none = findButton(f, "Run it again") == nil and findButton(f, SAVE_E) ~= nil
    return three and closed and noChange and #opened == 2 and opened[2] == "crowd" and none, allText(f)
end)

-- The rebuilt window (results window, Task 4): spec 2026-10-30-results-window-design.md sections 3.2 and 3.4
local function sevenChanges()
    local groups = {}
    for _, cvar in ipairs({ "graphicsShadowQuality", "graphicsSSAO", "graphicsComputeEffects", "graphicsLiquidDetail", "RenderScale",
        "giQuality", "graphicsLightMode" }) do
        groups[#groups + 1] = rows(cvar, 4.0, { { "0", -0.1 }, { "1", 0, current = true }, { "2", 0.05 } })
    end
    return entry(4.0, table.unpack(groups))
end

test("RW-30 the window is 760 by 540, has no scroll box, and opens at the top with nothing printed to chat", function()
    local e, r = boot()
    r.show(T1(), 250)
    local f = window()
    local scrolls = 0
    for _, fr in ipairs(H.frames()) do
        if fr.kind == "ScrollFrame" then scrolls = scrolls + 1 end
    end
    return f ~= nil and f._width == 760 and f._height == 540 and scrolls == 0 and f:IsShown() and outText() == "",
        tostring(f and f._width) .. "x" .. tostring(f and f._height) .. " scroll boxes " .. scrolls
end)

test("RW-31 the verdict, the bars and the changes in fps are drawn, each once", function()
    local e, r = boot()
    r.show(T1(), 250)
    local f = window()
    local verdict = "These 2 changes should take you from about 250 fps to about 333 fps."
    return countExact(f, verdict) == 1 and hasText(f, "Now: about 250 fps") and hasText(f, "With these changes: about 333 fps")
        and countExact(f, "Shadow detail: 2 to 1, saves about 28 fps.") == 1 and countExact(f, "Soft corner shadows: 2 to 0, saves about 44 fps.") == 1
        and #texturesOf(f, r.COLORS.now) == 1 and #texturesOf(f, r.COLORS.after) == 1, allText(f)
end)

test("RW-32 more than six changes: five lines and a pointer to the list for the rest", function()
    local e, r = boot()
    r.show(sevenChanges(), 100)
    local f = window()
    return countContaining(f, ", costs ") == 5 and countExact(f, "and 2 more changes: pick them in the list below.") == 1
        and countContaining(f, "These 7 changes") == 1, allText(f)
end)

test("RW-33 the list has a row per setting in order of swing, a dot on the ones that change, the unmeasured ones greyed after", function()
    local e, r = boot()
    r.show(T1(), 250)
    local f = window()
    local rows1 = rowsOf(f)
    local changed = rowNames(f) == "Shadow detail|Soft corner shadows" and dotsIn(f) == 2 and rows1[1].key == "setting:graphicsShadowQuality"
    r.show(T1(), 100)
    local nochange = rowNames(f) == "Shadow detail|Soft corner shadows" and dotsIn(f) == 0
    r.show(entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } })), 250)
    local rows3 = rowsOf(f)
    local greyed = rowNames(f) == "Shadow detail|Soft corner shadows" and rows3[2].label._textColor[1] < 0.7
        and rows3[1].label._textColor[1] == 1 and dotsIn(f) == 1
    return changed and nochange and greyed, rowNames(f)
end)

test("RW-34 the first changed setting is open; a click or select shows another, its row highlighted; a new result starts again", function()
    local e, r = boot()
    r.show(T1(), 250)
    local f = window()
    local rows1 = rowsOf(f)
    local first = r.selected() == "graphicsShadowQuality" and rows1[1].locked == true and rows1[2].locked == false
        and countExact(f, "Shadow detail: fps if only this setting changes") == 1 and #pointButtons(f) == 3
        and countExact(f, "0 to 1 costs about 56 fps.") == 1 and countExact(f, "now") == 1 and countExact(f, "recommended") == 1
    rows1[2]:Click()
    local second = r.selected() == "graphicsSSAO" and rowsOf(f)[2].locked == true and rowsOf(f)[1].locked == false
        and countExact(f, "Soft corner shadows: fps if only this setting changes") == 1 and countExact(f, "Shadow detail: fps if only this setting changes") == 0
        and countExact(f, "0 to 1 costs about 24 fps.") == 1 and countExact(f, "0 to 1 costs about 56 fps.") == 0 and #pointButtons(f) == 3
    r.select("nonsense")
    local keeps = r.selected() == "graphicsSSAO"
    f.scripts.OnUpdate(f, 0.6)
    local kept = r.selected() == "graphicsSSAO"
    r.select("graphicsShadowQuality")
    local selectCall = r.selected() == "graphicsShadowQuality" and rowsOf(f)[1].locked == true
    r.select("graphicsSSAO")
    r.show(T1(), 250)
    return first and second and keeps and kept and selectCall and r.selected() == "graphicsShadowQuality", tostring(r.selected())
end)

test("RW-35 an unmeasured setting that is opened shows its reason and no graph", function()
    local e, r = boot()
    r.show(entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "2", 0, current = true } })), 250)
    local f = window()
    rowsOf(f)[2]:Click()
    return r.selected() == "graphicsSSAO" and countExact(f, "Soft corner shadows: not measured (the test couldn't measure it)") == 1
        and #pointButtons(f) == 0 and countExact(f, "now") == 0 and rowsOf(f)[2].locked == true
        and countContaining(f, " costs about ") == 0, allText(f)
end)

test("RW-36 a result saved before this version, and a crowd result, draw their graphs with no error and nothing in chat", function()
    local e, r = boot()
    local old = T1()
    for _, row in ipairs(old.rows) do row.flags, row.hitches, row.time = nil, nil, nil end
    r.show(old, 250, nil, { again = "setup", measuredLine = "Measured in Highmountain, 3 days ago." })
    local f = window()
    local oldOk = rowNames(f) == "Shadow detail|Soft corner shadows" and #pointButtons(f) == 3 and hasText(f, "Measured in Highmountain")
    r.show(crowdFor(e), 100)
    local crowdOk = hasText(f, "Your crowded settings") and #pointButtons(f) >= 2 and r.selected() == "graphicsShadowQuality"
    return oldOk and crowdOk and outText() == "", outText()
end)

test("RW-37 a result with nothing to recommend still draws: the verdict, the unmeasured settings listed, no graph, no error", function()
    local e, r = boot()
    local en = entry(4.75,
        rows("graphicsShadowQuality", 3.44, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }),
        rows("graphicsSSAO", 3.8, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }))
    r.show(en, 165)
    local f = window()
    return outText() == "" and rowNames(f) == "Shadow detail|Soft corner shadows" and #pointButtons(f) == 0
        and countExact(f, "Shadow detail: not measured (the test couldn't measure it)") == 1 and hasText(f, "couldn't get a steady reading"), allText(f)
end)

test("RW-38 a smaller result drawn after a larger one leaves none of the larger one's rows, points or lines behind", function()
    local e, r = boot()
    r.show(sevenChanges(), 100)
    local f = window()
    local big = #rowsOf(f) == 7
    r.show(entry(4.0, rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", 0, current = true } })), 100)
    return big and #rowsOf(f) == 1 and #pointButtons(f) == 2 and countContaining(f, "and 2 more changes") == 0
        and countContaining(f, ", costs ") == 0 and countContaining(f, "These 7 changes") == 0, rowNames(f)
end)

-- The Save button (results window, Task 5): spec 2026-10-30-results-window-design.md section 3.3
local function stringWith(f, text)      -- the shown font string with exactly this text
    local found
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text == text then found = fs end
        end
    end)
    return found
end
local function green(fs) return fs ~= nil and fs._textColor ~= nil and fs._textColor[2] > 0.7 and fs._textColor[1] < 0.5 end
local function liveCvars() return { graphicsShadowQuality = "4", graphicsSSAO = "3", RenderScale = "1" } end

test("SV-1 the buttons are Save, Run it again and Close in that order, with the profile's own words", function()
    local e, r = boot()
    emptyEveryday(e)
    emptyCrowded(e)
    r.show(T1(), 250, nil, { again = "setup" })
    local f = window()
    local save, again, close = findButton(f, SAVE_E), findButton(f, "Run it again"), findButton(f, "Close")
    local ordered = save and again and close and save._point[4] < again._point[4] and again._point[4] < close._point[4]
    -- spec 3.3: widths 250, 150 and 150 with 12 pixels between, centred, so the longest label fits its button
    local function gap(a, b) return (b._point[4] - b._width / 2) - (a._point[4] + a._width / 2) end
    local sized = save._width == 250 and again._width == 150 and close._width == 150 and near(gap(save, again), 12)
        and near(gap(again, close), 12) and near((save._point[4] - save._width / 2) + (close._point[4] + close._width / 2), 0)
    r.show(crowdFor(e), 100, nil, { again = "crowd" })
    local crowd = findButton(f, SAVE_C) ~= nil and findButton(f, SAVE_E) == nil and findButton(f, "Run it again") ~= nil
    e.ns.db().profiles.crowded.values = { graphicsShadowQuality = "3" }
    r.show(crowdFor(e), 100)
    local replaceCrowd = findButton(f, REPL_C) ~= nil and findButton(f, SAVE_C) == nil
    return ordered and sized and crowd and replaceCrowd, allText(f)
end)

test("SV-2 Save stores the recommended values and switches Everyday on, says so only in the window, and cannot be repeated", function()
    local e, r = boot(liveCvars())
    emptyEveryday(e)
    r.show(T1(), 250)
    local f = window()
    local db = e.ns.db()
    findButton(f, SAVE_E):Click()
    local stored = db.profiles.everyday.values.graphicsShadowQuality == "1" and db.profiles.everyday.values.graphicsSSAO == "0"
        and db.profiles.everyday.values.RenderScale == "1" and db.active == "everyday" and CVARS.graphicsShadowQuality == "1"
        and CVARS.graphicsSSAO == "0"
    local line = stringWith(f, APPLIED)
    local shown = line ~= nil and green(line) and outText() == "" and findButton(f, SAVE_E) == nil and findButton(f, REPL_E) == nil
        and findButton(f, "Close") ~= nil
    local writes = #SETLOG
    r.click("apply")
    local once = #SETLOG == writes and outText() == ""
    r.show(T1(), 250)             -- a new result starts again: no green line, and the profile now holds values
    local fresh = countExact(f, APPLIED) == 0 and findButton(f, REPL_E) ~= nil
    return stored and shown and once and fresh, outText()
end)

test("SV-3 with nothing to change Save stores what the game has now and switches the profile on, Everyday or Crowded", function()
    local e, r = boot(liveCvars())
    emptyEveryday(e)
    emptyCrowded(e)
    r.show(T1(), 100)
    local f = window()
    local db = e.ns.db()
    local writes = #SETLOG
    findButton(f, SAVE_E):Click()
    local everyday = db.profiles.everyday.values.graphicsShadowQuality == "4" and db.profiles.everyday.values.graphicsSSAO == "3"
        and db.profiles.everyday.values.RenderScale == "1" and db.active == "everyday" and #SETLOG == writes
        and countExact(f, APPLIED) == 1 and outText() == ""
    r.show(crowdFor(e), 60)
    local crowdAtRest = hasText(f, "Your crowded settings") and findButton(f, SAVE_C) ~= nil
    findButton(f, SAVE_C):Click()
    local crowded = db.profiles.crowded.values.graphicsShadowQuality == "4" and db.profiles.crowded.values.RenderScale == "1"
        and db.active == "crowded" and countExact(f, CROWD_APPLIED) == 1 and outText() == ""
    return everyday and crowdAtRest and crowded, outText()
end)

test("SV-4 with the target out of reach, no steady reading or an invalid result there is nothing to save and only Close", function()
    local e, r = boot()
    local nodata = entry(4.75,
        rows("graphicsShadowQuality", 3.44, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }),
        rows("graphicsSSAO", 3.8, { { "0", status = "inconclusive" }, { "1", status = "inconclusive" } }))
    local bad = T1()
    bad.valid = false
    local out = {}
    for i, case in ipairs({ { T1(), 500 }, { nodata, 165 }, { bad, 250 }, { crowdFor(e, -0.05, -0.02), 144 } }) do
        r.show(case[1], case[2])
        local f = window()
        out[i] = findButton(f, SAVE_E) == nil and findButton(f, REPL_E) == nil and findButton(f, SAVE_C) == nil
            and findButton(f, REPL_C) == nil and findButton(f, "Close") ~= nil
    end
    return out[1] and out[2] and out[3] and out[4] and outText() == "", tostring(out[1]) .. tostring(out[2]) .. tostring(out[3]) .. tostring(out[4])
end)

test("SV-5 in combat or while a test runs Save is greyed with its reason, and a click that still arrives writes and prints nothing", function()
    local function refused(arrange, reason, target)
        local e, r = boot(liveCvars())
        emptyEveryday(e)
        arrange(e)
        local db = e.ns.db()
        local activeBefore = db.active
        r.show(T1(), target)
        local f = window()
        local writes = #SETLOG
        local button = findButton(f, SAVE_E)
        local grey = button ~= nil and button:IsEnabled() == false and hasText(f, reason)
        r.click("apply")
        return grey and next(db.profiles.everyday.values) == nil and db.active == activeBefore and #SETLOG == writes and outText() == ""
            and f:IsShown() and findButton(f, SAVE_E) ~= nil
    end
    local combatChange = refused(function() COMBAT = true end, "You are in combat; try again afterwards.", 250)
    local combatRest = refused(function() COMBAT = true end, "You are in combat; try again afterwards.", 100)
    local busyChange = refused(function(e) e.ns.bench.active = function() return true end end, "A test is running; try again afterwards.", 250)
    local busyRest = refused(function(e) e.ns.bench.active = function() return true end end, "A test is running; try again afterwards.", 100)
    return combatChange and combatRest and busyChange and busyRest, tostring(combatChange) .. tostring(combatRest) .. tostring(busyChange) .. tostring(busyRest)
end)

test("SV-6 a save that Profiles refuses shows why in red, leaves Save on offer, and prints nothing", function()
    local e, r = boot()
    emptyEveryday(e)
    e.ns.profiles.adopt = function() return false, "nope" end
    r.show(T1(), 250)
    local f = window()
    findButton(f, SAVE_E):Click()
    local line = stringWith(f, "Could not save: nope")
    return line ~= nil and not green(line) and findButton(f, SAVE_E) ~= nil and f:IsShown() and outText() == "", allText(f)
end)

test("SV-7 when the game keeps a setting at another level the green line says how many", function()
    local function savedWith(mismatches)
        local e, r = boot()
        emptyEveryday(e)
        e.ns.profiles.adopt = function() return true, { changed = 1, mismatched = mismatches } end
        r.show(T1(), 250)
        local f = window()
        findButton(f, SAVE_E):Click()
        return f
    end
    local one = savedWith({ { cvar = "graphicsSSAO", wanted = "0", now = "1" } })
    local two = savedWith({ { cvar = "graphicsSSAO", wanted = "0", now = "1" }, { cvar = "RenderScale", wanted = "0.7", now = "1" } })
    local none = savedWith({})
    return stringWith(one, APPLIED .. " The game kept 1 setting at a different level than saved.") ~= nil
        and stringWith(two, APPLIED .. " The game kept 2 settings at a different level than saved.") ~= nil
        and stringWith(none, APPLIED) ~= nil and stringWith(none, APPLIED .. " The game kept") == nil, allText(one)
end)

test("RW-41 change lines that wrap in the client are cut to what fits above the list, the last one giving way to the pointer", function()
    local e, r = boot()
    -- a client that wraps at 9 pixels a letter: a change line is two lines high in the 320-pixel column
    STRINGHEIGHT = function(fs)
        return 14 * math.max(1, math.ceil(#(fs._text or "") * 9 / (fs._width or 720)))
    end
    r.show(sevenChanges(), 100)
    local f = window()
    local bottoms = {}
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text and fs._text ~= "" and fs._point and fs._point[4] == 420 then
                bottoms[#bottoms + 1] = -fs._point[5] + STRINGHEIGHT(fs)
            end
        end
    end)
    STRINGHEIGHT = nil
    local worst = 0
    for _, b in ipairs(bottoms) do worst = math.max(worst, b) end
    return #bottoms >= 2 and worst <= 246 and countExact(f, "and 3 more changes: pick them in the list below.") == 1
        and countContaining(f, ", costs ") == 4, tostring(worst) .. " [" .. table.concat(bottoms, ",") .. "] " .. allText(f):gsub("\n", " | ")
end)

test("RW-42 the footer stands above the saved line, so one that wraps does not run over it, and both stay clear of the buttons", function()
    local e, r = boot(liveCvars())
    emptyEveryday(e)
    r.show(T1(), 250)
    local f = window()
    findButton(f, SAVE_E):Click()
    local notice = stringWith(f, APPLIED)
    local footer
    walk(f, function(frame)
        for _, fs in ipairs(frame.fontStrings) do
            if fs.shown and fs._text and fs._text:find("Bars show speed", 1, true) then footer = fs end
        end
    end)
    return notice ~= nil and footer ~= nil and footer._point[1] == "BOTTOMLEFT" and footer._point[2] == notice
        and footer._point[3] == "TOPLEFT" and notice._point[1] == "BOTTOMLEFT" and notice._point[5] >= 40, allText(f)
end)

test("RW-39 the list shows at most ten settings, and an open setting that is not listed can still be selected by name", function()
    local e, r = boot()
    local groups = {}
    for i = 1, 11 do
        groups[#groups + 1] = rows("customCvar" .. i, 4.0, { { "0", -0.1 * i }, { "1", 0, current = true } })
    end
    r.show(entry(4.0, table.unpack(groups)), 100)
    local f = window()
    r.select("customCvar11")
    return #rowsOf(f) == 10 and outText() == "" and r.selected() == "customCvar11", #rowsOf(f)
end)

test("RW-40 a paragraph that would run into the list is left out and the ones above it stay", function()
    local e, r = boot()
    -- seven changes, an optimistic check (two lines), where and when it was measured, and the pointer to the next test
    r.show(sevenChanges(), 100, { ok = true, appliedMs = 7.0, baselineMs = 4.0 }, { measuredLine = "Measured in Highmountain, 3 days ago." })
    local f = window()
    local crowded = hasText(f, "Checked: expected about") and hasText(f, "The estimate was optimistic") and hasText(f, "Measured in Highmountain")
        and not hasText(f, "Next, in a busy place")
    r.show(T1(), 250)
    local roomy = hasText(f, "Next, in a busy place")
    return crowded and roomy and outText() == "", allText(f)
end)

return H.results()
