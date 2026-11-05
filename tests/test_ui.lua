-- Tests for UI.lua (spec section 15): the pure menu model is tested directly; the two client-menu adapters, the
-- minimap button and the report window are tested against the harness's stubs (their real behaviour is checked in the game).
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function newUi(cvars, opts)
    opts = opts or {}
    opts.fresh = true
    local e = H.boot(cvars or { graphicsShadowQuality = "2", RenderScale = "1", groundEffectDensity = "64", vsync = "0" }, opts)
    return e, e.ns.ui, e.ns.bench
end
local function outText() return table.concat(OUT, " | ") end
local function has(sub)
    for _, l in ipairs(OUT) do
        if l:find(sub, 1, true) then return true end
    end
    return false
end
local function findFrame(name)
    for _, f in ipairs(H.frames()) do
        if f.name == name then return f end
    end
    return nil
end
local function find(items, text)         -- the first item with exactly this text, searching submenus too
    for _, item in ipairs(items) do
        if item.text == text then return item end
        if item.children then
            local hit = find(item.children, text)
            if hit then return hit end
        end
    end
    return nil
end
local function titlesOf(items)
    local list = {}
    for _, item in ipairs(items) do
        if item.kind == "title" then list[#list + 1] = item.text end
    end
    return table.concat(list, ",")
end
local function near(x, y, tol) return math.abs(x - y) <= (tol or 1e-6) end
local function baseCtx(over)
    local ctx = { profile = "everyday", active = false, inCombat = false, progress = nil, saved = { best = false, crowded = false }, last = nil }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return ctx
end
-- The plain texts of the menu since 0.11 (spec 2026-11-03-advanced-page-title-switch-and-menu-design.md A5): the profiles by name,
-- their descriptions as hints, Settings at the top and Return to Original at the bottom.
local P_EVERYDAY, P_CROWDED, P_MAXIMUM = "Everyday", "Crowded", "Maximum"
local H_EVERYDAY, H_CROWDED, H_MAXIMUM = "Normal play", "Raids and busy cities", "Everything at its highest"
local SETTINGS, PROMINENT = "Settings", "|cffffd100Settings|r"
local RETURN, H_RETURN = "Return to Original", "Your own settings, from before the addon changed anything."
local CHECK = "|TInterface/RaidFrame/ReadyCheck-Ready:14|t "
local RAW_NAMES = { "graphicsShadowQuality", "graphicsSSAO", "groundEffectDensity", "RenderScale", "graphicsComputeEffects",
    "Ground clutter (raw)", "Render scale", "Compute effects", "Tiers", "Forced settings" }
local function topTexts(items)
    local list = {}
    for _, item in ipairs(items) do list[#list + 1] = item.text or "-" end
    return table.concat(list, "|")
end
local function rawIn(items)
    local found
    local function scan(list)
        for _, item in ipairs(list) do
            for _, raw in ipairs(RAW_NAMES) do
                if item.text and item.text:find(raw, 1, true) then found = found or (raw .. " in " .. item.text) end
            end
            if item.children then scan(item.children) end
        end
    end
    scan(items)
    return found
end

-- The menu model (pure)
test("B10-1 the idle model: Settings, the three profiles, the two tests and Return to Original, with dividers between and no titles", function()
    local _, ui = newUi()
    local model = ui.menuModel(baseCtx({}))
    local want = table.concat({ SETTINGS, "-", P_EVERYDAY, P_CROWDED, P_MAXIMUM, "-", "Find my best settings", "Find my crowded settings",
        "-", RETURN }, "|")
    local settings = find(model, SETTINGS)
    return topTexts(model) == want and titlesOf(model) == "" and settings.kind == "button" and settings.prominent == true
        and find(model, RETURN).kind == "button" and find(model, RETURN).hint == H_RETURN, topTexts(model)
end)

test("B10-3 the Find items follow combat and a running test; Stop comes only with a running test; the old Advanced items are gone", function()
    local _, ui = newUi()
    local idle, combat, active = ui.menuModel(baseCtx({})), ui.menuModel(baseCtx({ inCombat = true })), ui.menuModel(baseCtx({ active = true }))
    local gone = true
    for _, text in ipairs({ "Advanced", "Check this spot", "Run benchmark", "Show last report", "Apply all now",
        "Put back everything this addon changed", "My settings...", "Profile", "Original: my own settings, hands off",
        "Save my game's current settings as...", "Also use the Crowded settings in raids and battlegrounds" }) do
        if find(idle, text) or find(active, text) then gone = false end
    end
    return find(idle, "Find my best settings").disabled == false and find(idle, "Find my crowded settings").disabled == false
        and find(idle, "Stop") == nil and find(combat, "Find my best settings").disabled == true
        and find(combat, "Find my crowded settings").disabled == true and find(active, "Find my best settings").disabled == true
        and find(active, "Stop") ~= nil and find(active, "Stop").disabled == false and gone, topTexts(active)
end)

test("B10-4 the status line says a test is running, with its step and what it is doing, and is absent otherwise", function()
    local _, ui = newUi()
    local running = ui.menuModel(baseCtx({ active = true,
        progress = { phase = "sweep", label = "Shadows 3", cvar = "graphicsShadowQuality", value = "3", done = 12, total = 38 } }))
    local idle = ui.menuModel(baseCtx({}))
    local line
    for _, item in ipairs(running) do
        if item.kind == "info" and item.text:find("A test is running", 1, true) then line = item.text end
    end
    local idleInfo
    for _, item in ipairs(idle) do
        if item.kind == "info" then idleInfo = item.text end
    end
    return line == "A test is running: step 12 of 38 (Now testing: Shadow detail, level 3)" and idleInfo == nil
        and find(idle, "Idle") == nil, tostring(line)
end)

test("B10-6 every item's action reaches the function its slash command uses", function()
    local e, ui, b = newUi()
    local calls = {}
    e.ns.command = function(msg) calls[#calls + 1] = "cmd:" .. msg end
    e.ns.guide.open = function(kind) calls[#calls + 1] = "guide:" .. kind end      -- every test opens the guided window
    e.ns.settings.open = function() calls[#calls + 1] = "settings" end
    b.stop = function() calls[#calls + 1] = "stop" end
    ui.showReport = function(entry) calls[#calls + 1] = "report:" .. tostring(entry.label) end
    local model = ui.menuModel(baseCtx({ active = true, last = { label = "last", valid = true, rows = {} } }))
    for _, text in ipairs({ SETTINGS, P_EVERYDAY, P_CROWDED, P_MAXIMUM, "Find my best settings", "Find my crowded settings", "Stop", RETURN }) do
        find(model, text).run()
    end
    return table.concat(calls, ",")
        == "settings,cmd:profile everyday,cmd:profile crowded,cmd:profile maximum,guide:setup,guide:crowd,stop,cmd:profile original",
        table.concat(calls, ",")
end)

test("B10-7b the model copes with a context with fields missing", function()
    local _, ui = newUi()
    local ok, model = pcall(ui.menuModel, {})
    return ok and #model > 0, tostring(model)
end)

-- buildContext reads the live state
test("B10-16 buildContext reads the profile, the raid option, progress, the last report and which tests have a saved result", function()
    local e, ui, b = newUi()
    b.state().history[1] = { valid = true, rows = { { cvar = "graphicsShadowQuality", value = "1", deltaMs = 9 } } }
    b.state().history[2] = { label = "mark", valid = true, rows = { { setting = "mark", value = "current", meanMs = 7 } } }
    local ctx = ui.buildContext()
    return ctx.profile == "everyday" and ctx.raidToo == false and ctx.active == false and ctx.inCombat == false and ctx.progress == nil
        and ctx.last == b.state().history[2] and ctx.saved.best == false and ctx.saved.crowded == false
        and ctx.want == nil and ctx.current == nil and ctx.resolved == nil and ctx.tierCost == nil and ctx.read == nil, outText()
end)

test("UC-1 a crowd entry is never the last report", function()
    local e, ui, b = newUi()
    local quiet = { valid = true, rows = { { cvar = "graphicsShadowQuality", value = "1", deltaMs = 0.5, flags = {} } } }
    local crowd = { kind = "crowd", valid = true, rows = {}, settings = {}, baselineMs = 9.0 }
    b.state().history[1] = quiet
    b.state().history[2] = crowd
    local both = ui.buildContext()
    b.state().history[1] = nil
    b.state().history[1] = crowd
    local onlyCrowd = ui.buildContext()
    return both.last == quiet and onlyCrowd.last == nil, tostring(both.last == quiet) .. " " .. tostring(onlyCrowd.last)
end)

-- The client-menu adapters
-- The tooltip an item of the new menu shows: the lines its tooltip function writes.
local function tooltipOf(item)
    GameTooltip.lines = {}
    if item and item.tooltip then item.tooltip(GameTooltip) end
    return table.concat(GameTooltip.lines, "|")
end

test("B10-8 the new menu API gets dividers, buttons and checkboxes, Settings first and brighter, and each hint as its item's tooltip", function()
    local e, ui, b = newUi(nil, { menu = "new" })
    local opened = 0
    e.ns.settings.open = function() opened = opened + 1 end
    local owner = {}
    ui.openMenu(owner)
    local items = MENUCALLS.items
    local settings, everyday, back = items[1], find(items, P_EVERYDAY), find(items, RETURN)
    settings.fn()
    return MENUCALLS.owner == owner and titlesOf(items) == "" and settings.kind == "button" and settings.text == PROMINENT and opened == 1
        and items[2].kind == "divider" and everyday.kind == "check" and everyday.isSelected() == true
        and tooltipOf(everyday) == P_EVERYDAY .. "|" .. H_EVERYDAY and tooltipOf(find(items, P_CROWDED)) == P_CROWDED .. "|" .. H_CROWDED
        and back.kind == "button" and tooltipOf(back) == RETURN .. "|" .. H_RETURN and tooltipOf(settings) == "",
        tooltipOf(everyday) .. " / " .. tooltipOf(back)
end)

test("B10-8c the Find items are disabled in the new menu while a run is active", function()
    local e, ui, b = newUi(nil, { menu = "new" })
    b.state().tiers.graphicsShadowQuality = { "1", "2", "3" }
    b.run()
    ui.openMenu({})
    local best, crowded = find(MENUCALLS.items, "Find my best settings"), find(MENUCALLS.items, "Find my crowded settings")
    local tick = find(MENUCALLS.items, P_EVERYDAY)       -- a check item is disabled too (the older assertion of this test)
    return b.active() == true and best ~= nil and best.disabled == true and crowded.disabled == true
        and tick ~= nil and tick.kind == "check" and tick.disabled == true, outText()
end)

test("B10-8b disabled items are disabled in the new menu", function()
    local e, ui = newUi(nil, { menu = "new" })
    COMBAT = true
    ui.openMenu({})
    return find(MENUCALLS.items, "Find my best settings").disabled == true and find(MENUCALLS.items, P_EVERYDAY).disabled == true
        and find(MENUCALLS.items, RETURN).disabled == true
end)

test("B10-9 the older dropdown functions get the same entries on one level, Settings brighter, and the hints as tooltips", function()
    local e, ui, b = newUi(nil, { menu = "old" })
    local opened = 0
    e.ns.settings.open = function() opened = opened + 1 end
    local owner = {}
    ui.openMenu(owner)
    local level1, level2 = MENUCALLS.levels[1], MENUCALLS.levels[2]
    local function infoByText(list, text)
        for _, info in ipairs(list) do if info.text == text then return info end end
    end
    local settings, everyday, back = level1[1], infoByText(level1, P_EVERYDAY), infoByText(level1, RETURN)
    settings.func()
    return MENUCALLS.anchor == owner and #level2 == 0 and settings.text == PROMINENT and opened == 1 and settings.tooltipText == nil
        and everyday.tooltipTitle == P_EVERYDAY and everyday.tooltipText == H_EVERYDAY and everyday.tooltipOnButton == true
        and back.tooltipText == H_RETURN and back.notCheckable == true and infoByText(level1, "Find my best settings") ~= nil, outText()
end)

test("B10-10 with no menu API the click prints a one-line help and nothing breaks", function()
    local _, ui = newUi(nil, { menu = "none" })
    OUT = {}
    local ok = pcall(ui.openMenu, {})
    return ok and has("menu is not available") and has("/fset"), outText()
end)

test("B10-10b a failing menu API is caught and reported", function()
    local _, ui = newUi(nil, { menu = "new" })
    MenuUtil.CreateContextMenu = function() error("boom") end
    OUT = {}
    local ok = pcall(ui.openMenu, {})
    return ok and has("menu failed"), outText()
end)

-- The minimap button
test("B10-11 the button is a child of the minimap, placed at the default angle on the rim", function()
    local e, ui = newUi()
    e.fire("PLAYER_LOGIN")
    local btn = findFrame("ForeverSettingsMinimapButton")
    local p = btn and btn._point
    local radius = 140 / 2 + 5
    local angle = math.rad(215)
    return btn ~= nil and btn.parent == Minimap and p ~= nil and p[1] == "CENTER" and p[2] == Minimap
        and near(p[4], math.cos(angle) * radius, 0.01) and near(p[5], math.sin(angle) * radius, 0.01), outText()
end)

test("B10-11b a saved angle is restored at login", function()
    local e = newUi()
    e.ns.db().ui = { angle = 90 }
    e.fire("PLAYER_LOGIN")
    local p = findFrame("ForeverSettingsMinimapButton")._point
    return near(p[4], 0, 0.01) and near(p[5], 75, 0.01)
end)

test("B10-11c dragging saves the angle under the cursor", function()
    local e, ui = newUi()
    e.fire("PLAYER_LOGIN")
    local btn = findFrame("ForeverSettingsMinimapButton")
    btn.scripts.OnDragStart(btn)
    CURSOR = { 1000, 900 }                   -- straight above the minimap's centre
    btn.scripts.OnUpdate(btn, 0.01)
    local during = e.ns.db().ui.angle
    btn.scripts.OnDragStop(btn)
    return near(during, 90, 0.01) and btn.scripts.OnUpdate == nil and near(findFrame("ForeverSettingsMinimapButton")._point[5], 75, 0.01)
end)

test("B10-11d a left click opens the menu", function()
    local e, ui = newUi()
    e.fire("PLAYER_LOGIN")
    local btn = findFrame("ForeverSettingsMinimapButton")
    local opened
    ui.openMenu = function(owner) opened = owner end
    btn.scripts.OnClick(btn, "LeftButton")
    return opened == btn
end)

test("B10-11e the tooltip shows the state and how many settings are kept, in plain words", function()
    local e, ui, b = newUi()
    e.fire("PLAYER_LOGIN")
    local btn = findFrame("ForeverSettingsMinimapButton")
    btn.scripts.OnEnter(btn)
    local idle = table.concat(GameTooltip.lines, " | ")
    btn.scripts.OnLeave(btn)
    local db = e.ns.db()
    local real = db.want
    db.want = { graphicsShadowQuality = "2", groundEffectDensity = "64" }
    btn.scripts.OnEnter(btn)
    local two = table.concat(GameTooltip.lines, " | ")
    btn.scripts.OnLeave(btn)
    db.want = real
    return GameTooltip.shown == false and idle:find("ForeverSettings", 1, true) ~= nil and idle:find("no test running", 1, true) ~= nil
        and idle:find("Keeping 1 setting for you", 1, true) ~= nil and two:find("Keeping 2 settings for you", 1, true) ~= nil
        and idle:lower():find("forced", 1, true) == nil and two:lower():find("forced", 1, true) == nil, idle .. " // " .. two
end)

-- The button's picture is the addon's own gauge, as on the Wago thumbnail (owner request 2026-11-03), inside the stock round border.
test("B10-11b the button shows the gauge icon from the addon's Media folder at 20 pixels, centred, under the round border", function()
    local e, ui = newUi()
    e.fire("PLAYER_LOGIN")
    local btn = findFrame("ForeverSettingsMinimapButton")
    local icon, ring
    for _, tex in ipairs(btn and btn.textures or {}) do
        if tex._texture == "Interface/AddOns/ForeverSettings/Media/icon.tga" then icon = tex end
        if tex._texture == "Interface/Minimap/MiniMap-TrackingBorder" then ring = tex end
    end
    return icon ~= nil and icon.layer == "ARTWORK" and icon._width == 20 and icon._height == 20 and icon._point ~= nil
        and icon._point[1] == "CENTER" and ring ~= nil and ring.layer == "OVERLAY",
        tostring(icon and icon._texture) .. " " .. tostring(btn and btn.textures[1] and btn.textures[1]._texture)
end)

test("B10-12 /fset minimap hides and shows the button, and the choice survives a login", function()
    local e = newUi()
    e.fire("PLAYER_LOGIN")
    local btn = findFrame("ForeverSettingsMinimapButton")
    e.slash("minimap")
    local hidden = btn.shown == false and e.ns.db().ui.hidden == true
    e.slash("minimap")
    local shown = btn.shown == true and e.ns.db().ui.hidden == false
    e.slash("minimap")
    local e2 = H.boot({ graphicsShadowQuality = "2" })        -- same saved variables, a new login
    e2.fire("PLAYER_LOGIN")
    return hidden and shown and findFrame("ForeverSettingsMinimapButton").shown == false
end)

test("B10-12b without the module /fset minimap says so", function()
    local e = newUi(nil, { ui = false })
    OUT = {}
    e.slash("minimap")
    return has("ui module not loaded"), outText()
end)

-- The report window
test("B10-13 showReport fills a movable window, shows it, and registers it for Escape exactly once", function()
    local e, ui, b = newUi()
    local entry = { label = "menu-high", valid = true, rows = { { setting = "menu-high", value = "current", meanMs = 7, fps = 142.9, low1Fps = 120, hitches = 0, flags = {} } } }
    ui.showReport(entry)
    ui.showReport(entry)
    local f = findFrame("ForeverSettingsReport")
    local box
    for _, fr in ipairs(H.frames()) do if fr.kind == "EditBox" then box = fr end end
    local registered = 0
    for _, name in ipairs(UISpecialFrames) do if name == "ForeverSettingsReport" then registered = registered + 1 end end
    return f ~= nil and f.shown == true and box ~= nil and box._text:find("menu-high: 7.00 ms", 1, true) ~= nil
        and registered == 1, tostring(box and box._text)
end)

-- Launch night on Forever (2026-11-04): "Show report brings up an old screen". It is now a flat window like My settings.
test("B10-13c the report window is a flat window titled Test report, with no stock frame, and a new report starts at the top", function()
    local e, ui = newUi()
    local entry = { label = "menu-high", valid = true, rows = { { setting = "menu-high", value = "current", meanMs = 7, fps = 142.9, low1Fps = 120, hitches = 0, flags = {} } } }
    ui.showReport(entry)
    local f = findFrame("ForeverSettingsReport")
    local stock, scroll, box = false, nil, nil
    for _, fr in ipairs(H.frames()) do
        if fr.template == "BasicFrameTemplateWithInset" or fr.template == "UIPanelScrollFrameTemplate" then stock = true end
        if fr.kind == "ScrollFrame" then scroll = fr end
        if fr.kind == "EditBox" then box = fr end
    end
    local flat = f ~= nil and f.box ~= nil and f.titleText ~= nil and f.titleText._text == "Test report" and not stock
        and scroll ~= nil and scroll.bar ~= nil and box ~= nil and box.parent == scroll
    if not flat then return false, "flat " .. tostring(f and f.titleText and f.titleText._text) .. " stock " .. tostring(stock) end
    scroll.SetVerticalScroll = function(self, v) self._v = v end
    scroll.scripts.OnScrollRangeChanged(scroll, 0, 500)
    scroll.scripts.OnMouseWheel(scroll, -1)
    local moved = scroll._v == 40
    box.scripts.OnEscapePressed(box)
    local closed = not f:IsShown()
    ui.showReport(entry)
    return moved and closed and scroll._v == 0 and f:IsShown(), tostring(moved) .. tostring(closed) .. " v=" .. tostring(scroll._v)
end)

test("B10-13b the report window opens by itself when a valid run ends, unless switched off", function()
    local e, ui = newUi()
    ui.runFinished({ label = "x", valid = true, rows = { { setting = "x", value = "current", meanMs = 7, fps = 142.9, low1Fps = 120, hitches = 0, flags = {} } } })
    local opened = findFrame("ForeverSettingsReport") ~= nil
    local e2, ui2 = newUi()
    ui2.runFinished({ label = "x", valid = false, reason = "stopped", rows = {} })
    local invalidOpened = findFrame("ForeverSettingsReport") ~= nil
    local e3, ui3 = newUi()
    e3.ns.db().ui = { autoReport = false }
    ui3.runFinished({ label = "x", valid = true, rows = { { setting = "x", value = "current", meanMs = 7, fps = 142.9, low1Fps = 120, hitches = 0, flags = {} } } })
    local offOpened = findFrame("ForeverSettingsReport") ~= nil
    return opened and (not invalidOpened) and (not offOpened)
end)

test("B10-14 a real run opens the report window with its report", function()
    local e, ui, b = newUi({ RenderScale = "1", graphicsShadowQuality = "2", vsync = "0" })
    b.K.SETTLE, b.K.MEASURE, b.K.MIN_FRAMES = 0.05, 0.2, 20
    b.state().tiers.graphicsShadowQuality = { "0", "2" }
    b.run()
    e.pump(30, function(cv) return 0.002 + 0.004 * tonumber(cv.RenderScale) + 0.0005 * tonumber(cv.graphicsShadowQuality) end)
    local box
    for _, fr in ipairs(H.frames()) do if fr.kind == "EditBox" then box = fr end end
    return box ~= nil and box._text:find("Benchmark at Test Zone", 1, true) ~= nil, tostring(box and box._text)
end)

-- Environment probes
test("B10-15 environment reports the menu API and the minimap, PASS or FAIL", function()
    -- The probes read the client's globals when they run, so each is asked straight after its own boot.
    local function status(ui)
        local s = {}
        for _, c in ipairs(ui.environment()) do s[c.name] = c.ok end
        return s
    end
    local _, ui1 = newUi(nil, { menu = "new" })
    local s1 = status(ui1)
    local _, ui2 = newUi(nil, { menu = "old" })
    local s2 = status(ui2)
    local _, ui3 = newUi(nil, { menu = "none" })
    local s3 = status(ui3)
    local _, ui4 = newUi(nil, { menu = "new" })
    _G.Minimap = nil          -- after the boot, which creates one
    local s4 = status(ui4)
    return s1["menu API"] == true and s2["menu API"] == true and s3["menu API"] == false
        and s1["Minimap"] == true and s4["Minimap"] == false
end)

test("B10-15b check prints the UI environment lines", function()
    local e, ui, b = newUi({ RenderScale = "1", graphicsShadowQuality = "2", vsync = "0" }, { menu = "none" })
    b.K.SETTLE, b.K.MEASURE, b.K.MIN_FRAMES = 0.05, 0.2, 20
    b.check()
    e.pump(5, function(cv) return 0.002 + 0.004 * tonumber(cv.RenderScale) end)
    return has("environment: FAIL menu API") and has("environment: PASS Minimap"), outText()
end)

-- Task 7: the Profile section and the tooltip line
test("P7-2 in the new menu the profile ticks follow a click without reopening the menu", function()
    local _, ui = newUi(nil, { menu = "new" })
    ui.openMenu({})
    local everyday, crowded = find(MENUCALLS.items, P_EVERYDAY), find(MENUCALLS.items, P_CROWDED)
    local before = everyday.isSelected() == true and crowded.isSelected() == false
    crowded.fn()
    return before and crowded.isSelected() == true and everyday.isSelected() == false, outText()
end)

test("P7-3 the profile items and Return to Original are disabled in combat and during a benchmark", function()
    local _, ui = newUi()
    local function states(over)
        local model = ui.menuModel(baseCtx(over))
        return { profile = find(model, P_CROWDED).disabled, back = find(model, RETURN).disabled }
    end
    local idle, combat, running = states({}), states({ inCombat = true }), states({ active = true })
    return idle.profile == false and idle.back == false and combat.profile == true and combat.back == true
        and running.profile == true and running.back == true
end)

test("P7-4 each profile item and Return to Original sends exactly its command", function()
    local e, ui = newUi()
    local sent = {}
    e.ns.command = function(msg) sent[#sent + 1] = msg end
    local model = ui.menuModel(baseCtx({}))
    find(model, P_EVERYDAY).run()
    find(model, P_CROWDED).run()
    find(model, P_MAXIMUM).run()
    find(model, RETURN).run()
    return table.concat(sent, "|") == "profile everyday|profile crowded|profile maximum|profile original", table.concat(sent, "|")
end)

test("P7-6 the tooltip names the active profile", function()
    local e = newUi()
    e.fire("PLAYER_LOGIN")
    local btn = findFrame("ForeverSettingsMinimapButton")
    btn.scripts.OnEnter(btn)
    local first = table.concat(GameTooltip.lines, " | ")
    btn.scripts.OnLeave(btn)
    e.slash("profile crowded")
    btn.scripts.OnEnter(btn)
    local second = table.concat(GameTooltip.lines, " | ")
    return first:find("Profile: Everyday", 1, true) ~= nil and second:find("Profile: Crowded", 1, true) ~= nil, first .. " // " .. second
end)

-- Recommender, Task 8: the menu item (plan 2026-10-29-recommender.md); Check this spot is on the Advanced page since 0.11.
test("T8-2 the menu's Find my best settings opens the guide in kind setup when there is no saved result, and Check this spot is not in the menu", function()
    local e, ui = newUi()
    local calls = {}
    e.ns.guide.open = function(kind) calls[#calls + 1] = kind end
    local model = ui.menuModel(baseCtx({}))
    local at = {}
    for i, item in ipairs(model) do at[item.text or ""] = i end
    local item = find(model, "Find my best settings")
    item.run()
    return item.kind == "button" and at["Find my best settings"] ~= nil and find(model, "Check this spot") == nil
        and table.concat(calls, ",") == "setup", table.concat(calls, ",")
end)

test("T41-1 the menu's Find my crowded settings comes right after Find my best settings and opens the guide in kind crowd", function()
    local e, ui = newUi()
    local calls = {}
    e.ns.guide.open = function(kind) calls[#calls + 1] = kind end
    local model = ui.menuModel(baseCtx({}))
    local at = {}
    for i, item in ipairs(model) do at[item.text or ""] = i end
    local item = find(model, "Find my crowded settings")
    item.run()
    return item.kind == "button" and at["Find my best settings"] ~= nil and at["Find my crowded settings"] == at["Find my best settings"] + 1
        and table.concat(calls, ",") == "crowd", table.concat(calls, ",")
end)

test("T41-2 the crowd menu item is disabled in combat and while a test runs, like the other test items", function()
    local _, ui = newUi()
    local function disabled(over) return find(ui.menuModel(baseCtx(over)), "Find my crowded settings").disabled end
    return disabled({}) == false and disabled({ inCombat = true }) == true and disabled({ active = true }) == true
end)

test("T41-3 without the guide the crowd menu item says so and starts nothing", function()
    local e, ui, b = newUi(nil, { guide = false })
    local started = 0
    b.run = function() started = started + 1 end
    b.crowd = function() started = started + 1 end
    local item = find(ui.menuModel(baseCtx({})), "Find my crowded settings")
    item.run()
    return started == 0 and has("guide module not loaded"), outText()
end)

-- Words and menu, Task 7: green checks and saved results (spec section 3.3)
local NOW = 1000000
local function saveFixtures(e, b)
    b.now = function() return NOW end
    local quiet = { valid = true, kind = "setup", mode = "quick", zone = "Highmountain", time = NOW - 259200, baselineMs = 4.0,
        rows = { { setting = "Shadows", cvar = "graphicsShadowQuality", value = "0", meanMs = 3.0, deltaMs = -1.0, flags = {} },
                 { setting = "Shadows", cvar = "graphicsShadowQuality", value = "2", meanMs = 4.0, deltaMs = 0, flags = {}, current = true } },
        verify = { predictedMs = 3.0, measuredMs = 3.1 } }
    local crowd = { kind = "crowd", valid = true, rows = {}, settings = {}, baselineMs = 9.0, zone = "Stormwind City", time = NOW - 7200,
        quietTime = quiet.time, verify = { predictedMs = 8.0, measuredMs = 8.5 } }
    return quiet, crowd
end

test("M1-3 the Find items carry a done mark exactly when a result is saved for them", function()
    local _, ui = newUi()
    local function marks(saved)
        local model = ui.menuModel(baseCtx({ saved = saved }))
        return find(model, "Find my best settings").done, find(model, "Find my crowded settings").done
    end
    local a1, a2 = marks({ best = true, crowded = false })
    local b1, b2 = marks({ best = false, crowded = true })
    local c1, c2 = marks({ best = true, crowded = true })
    local d1, d2 = marks({ best = false, crowded = false })
    return a1 == true and a2 ~= true and b1 ~= true and b2 == true and c1 == true and c2 == true and d1 ~= true and d2 ~= true
end)

test("M1-4 clicking a finished test opens its saved result with the target, the check and the measured line; otherwise it starts the test", function()
    local e, ui, b = newUi()
    local quiet = saveFixtures(e, b)
    b.state().history[1] = quiet
    ui.state().target = 165
    local shown, opened = {}, {}
    e.ns.results.show = function(entry, target, verify, extras) shown[#shown + 1] = { entry, target, verify, extras } end
    e.ns.guide.open = function(kind) opened[#opened + 1] = kind end
    local model = ui.menuModel(ui.buildContext())
    local item = find(model, "Find my best settings")
    item.run()
    local s = shown[1]
    local first = item.done == true and #shown == 1 and #opened == 0 and s[1] == quiet and s[2] == 165
        and s[3].ok == true and s[3].appliedMs == 3.1 and s[3].baselineMs == 4.0
        and s[4].again == "setup" and s[4].measuredLine == "Measured in Highmountain, 3 days ago."
    local e2, ui2 = newUi()
    local shown2, opened2 = 0, {}
    e2.ns.results.show = function() shown2 = shown2 + 1 end
    e2.ns.guide.open = function(kind) opened2[#opened2 + 1] = kind end
    local fresh = find(ui2.menuModel(ui2.buildContext()), "Find my best settings")
    fresh.run()
    find(ui2.menuModel(ui2.buildContext()), "Find my crowded settings").run()
    return first and fresh.done ~= true and shown2 == 0 and opened2[1] == "setup" and opened2[2] == "crowd",
        tostring(#shown) .. " " .. tostring(opened2[1]) .. " " .. tostring(opened2[2])
end)

test("M1-5 a result with nothing to show gets no check: no saved target, no quiet-spot entry, no valid crowd entry (Review Focus 3)", function()
    local e, ui, b = newUi()
    local quiet, crowd = saveFixtures(e, b)
    local function best() return ui.savedResult("best") ~= nil end
    local function crowded() return ui.savedResult("crowded") ~= nil end
    local none = not best() and not crowded()
    b.state().history[1] = quiet
    local noTarget = not best()
    ui.state().target = 100
    local unlisted = not best()
    ui.state().target = 165
    local ok = best()
    local noCrowd = not crowded()
    b.state().history[2] = crowd
    ui.state().crowdTarget = nil
    local noCrowdTarget = not crowded()
    ui.state().crowdTarget = 60
    local both = crowded()
    crowd.valid = false
    local invalid = not crowded()
    crowd.valid = true
    -- a result that vanishes after the menu was built: the click starts the test and nothing fails
    local model = ui.menuModel(ui.buildContext())
    local item = find(model, "Find my best settings")
    for i = #b.state().history, 1, -1 do b.state().history[i] = nil end
    local opened = {}
    e.ns.guide.open = function(kind) opened[#opened + 1] = kind end
    local okClick = pcall(item.run)
    return none and noTarget and unlisted and ok and noCrowd and noCrowdTarget and both and invalid and okClick and item.done == true
        and opened[1] == "setup", tostring(none) .. tostring(noTarget) .. tostring(unlisted) .. tostring(ok) .. tostring(noCrowd)
            .. tostring(noCrowdTarget) .. tostring(both) .. tostring(invalid) .. tostring(okClick)
end)

test("M1-6 a crowd result is rebuilt from the quiet-spot entry it was built on, else from the newest one", function()
    local e, ui, b = newUi()
    local quiet, crowd = saveFixtures(e, b)
    local older = quiet                 -- the one the crowd test was built on, neither the first nor the newest
    local decoy = { valid = true, kind = "setup", time = NOW - 500000, baselineMs = 6.0, rows = quiet.rows }
    local newer = { valid = true, kind = "setup", time = NOW - 1000, baselineMs = 5.0, rows = quiet.rows }
    b.state().history[1], b.state().history[2], b.state().history[3], b.state().history[4] = decoy, older, newer, crowd
    ui.state().target, ui.state().crowdTarget = 165, 60
    local bases = {}
    local real = e.ns.recommend.crowdEntry
    e.ns.recommend.crowdEntry = function(base, c) bases[#bases + 1] = base return real(base, c) end
    local saved = ui.savedResult("crowded")
    crowd.quietTime = 424242            -- that quiet-spot entry is gone
    ui.savedResult("crowded")
    return saved ~= nil and saved.again == "crowd" and saved.target == 60 and saved.entry.kind == "crowd" and bases[1] == older
        and bases[2] == newer and saved.measuredLine == "Measured in Stormwind City, 2 hours ago.", tostring(saved and saved.measuredLine)
end)

test("M1-7 the check stored with a result is handed back against the result's own baseline, and absent when there was none", function()
    local e, ui, b = newUi()
    local quiet = saveFixtures(e, b)
    b.state().history[1] = quiet
    ui.state().target = 165
    local with = ui.savedResult("best")
    quiet.verify = nil
    local without = ui.savedResult("best")
    return with.verify.ok == true and with.verify.appliedMs == 3.1 and with.verify.baselineMs == 4.0 and without.verify == nil
end)

test("M1-14 a saved result that cannot be shown says so and the click does not fail", function()
    local e, ui, b = newUi()
    local quiet = saveFixtures(e, b)
    b.state().history[1] = quiet
    ui.state().target = 165
    e.ns.results.show = function() error("window broke") end
    OUT = {}
    local ok = pcall(ui.openSaved, "best")
    return ok and has("the saved result could not be shown"), outText()
end)

test("M1-10 nothing in the menu, however deep, is a raw setting name", function()
    local _, ui = newUi()
    local model = ui.menuModel(baseCtx({ active = true, raidSwitchOff = true, last = { valid = true, rows = {} },
        saved = { best = true, crowded = true },
        progress = { phase = "sweep", label = "Ground clutter (raw) 48", cvar = "groundEffectDensity", value = "48", done = 3, total = 27 } }))
    return rawIn(model) == nil, tostring(rawIn(model))
end)

test("M1-11 Settings opens the window, and without the module says so", function()
    local e, ui = newUi()
    local opened = 0
    e.ns.settings.open = function() opened = opened + 1 end
    find(ui.menuModel(baseCtx({})), SETTINGS).run()
    local e2, ui2 = newUi(nil, { settings = false })
    OUT = {}
    find(ui2.menuModel(baseCtx({})), SETTINGS).run()
    return opened == 1 and has("settings module not loaded"), outText()
end)

test("M1-12 both menu adapters draw the green check before a finished test and before nothing else", function()
    local function arrange(opts)
        local e, ui, b = newUi(nil, opts)
        local quiet = saveFixtures(e, b)
        b.state().history[1] = quiet
        ui.state().target = 165
        return e, ui
    end
    local e, ui = arrange({ menu = "new" })
    ui.openMenu({})
    local done = find(MENUCALLS.items, CHECK .. "Find my best settings")
    local plain = find(MENUCALLS.items, "Find my crowded settings")
    local newOk = done ~= nil and done.kind == "button" and plain ~= nil and find(MENUCALLS.items, CHECK .. "Find my crowded settings") == nil
        and find(MENUCALLS.items, "Find my best settings") == nil
    local e2, ui2 = arrange({ menu = "old" })
    ui2.openMenu({})
    local function infoByText(list, text)
        for _, info in ipairs(list) do if info.text == text then return info end end
    end
    local level1 = MENUCALLS.levels[1]
    local oldOk = infoByText(level1, CHECK .. "Find my best settings") ~= nil and infoByText(level1, "Find my crowded settings") ~= nil
        and infoByText(level1, "Find my best settings") == nil and infoByText(level1, RETURN) ~= nil
    return newOk and oldOk, tostring(newOk) .. tostring(oldOk)
end)

test("M1-13 the tooltip says a test is running in plain words, with its step", function()
    local e, ui, b = newUi()
    b.progress = function() return { phase = "sweep", label = "x", cvar = "graphicsShadowQuality", value = "2", done = 3, total = 9 } end
    e.fire("PLAYER_LOGIN")
    local btn = findFrame("ForeverSettingsMinimapButton")
    btn.scripts.OnEnter(btn)
    local text = table.concat(GameTooltip.lines, " | ")
    return text:find("test running: step 3 of 9 (Now testing: Shadow detail, level 2)", 1, true) ~= nil, text
end)

test("T8-3 without the guide the menu item says so and starts nothing", function()
    local e, ui, b = newUi(nil, { guide = false })
    local started = 0
    b.run = function() started = started + 1 end
    b.check = function() started = started + 1 end
    local item = find(ui.menuModel(baseCtx({})), "Find my best settings")
    item.run()
    return started == 0 and has("guide module not loaded"), outText()
end)

-- Maximum and costs, Task 3: the Maximum tick (spec 2026-10-30-maximum-and-costs-design.md sections 3.1 and 3.3)
local function level(cvar, setting, value, deltaMs, current)
    return { setting = setting, cvar = cvar, value = value, meanMs = 4.0 + deltaMs, deltaMs = deltaMs, flags = {}, current = current }
end
-- A Thorough quiet-spot test (4.0 ms): Shadows 0 to 4 (now 2), ground clutter (raw) 48/64/128 (now 64) and render scale
-- (now 1). The highest level of each is measured: Shadows 4 costs 1.2 ms, clutter 128 costs 0.6 ms, scale 1 is where it is.
-- `shadows4` replaces the cost of Shadows 4; `without` names a setting whose rows are left out (a setting the test skipped).
local function thoroughQuiet(shadows4, without)
    local rows = {
        level("graphicsShadowQuality", "Shadows", "0", -1.0), level("graphicsShadowQuality", "Shadows", "1", -0.4),
        level("graphicsShadowQuality", "Shadows", "2", 0, true), level("graphicsShadowQuality", "Shadows", "3", 0.5),
        level("graphicsShadowQuality", "Shadows", "4", shadows4 or 1.2),
        level("groundEffectDensity", "Ground clutter (raw)", "48", -0.3), level("groundEffectDensity", "Ground clutter (raw)", "64", 0, true),
        level("groundEffectDensity", "Ground clutter (raw)", "128", 0.6),
        level("groundEffectDensity", "Ground clutter (raw)", "256", 0.6),     -- 256 since 0.11, at 128's cost
        level("RenderScale", "Render scale", "0.5", -2.0), level("RenderScale", "Render scale", "0.75", -0.8),
        level("RenderScale", "Render scale", "1", 0, true),
    }
    local kept = {}
    for _, row in ipairs(rows) do
        if row.cvar ~= without then kept[#kept + 1] = row end
    end
    return { valid = true, kind = "setup", mode = "thorough", zone = "Highmountain", time = NOW - 259200, baselineMs = 4.0, rows = kept }
end
-- A Quick test of the same game: only the lowest level and the current one of each setting were measured.
local function quickQuiet()
    return { valid = true, kind = "setup", mode = "quick", zone = "Highmountain", time = NOW - 259200, baselineMs = 4.0, rows = {
        level("graphicsShadowQuality", "Shadows", "0", -1.0), level("graphicsShadowQuality", "Shadows", "2", 0, true),
        level("groundEffectDensity", "Ground clutter (raw)", "48", -0.3), level("groundEffectDensity", "Ground clutter (raw)", "64", 0, true),
        level("RenderScale", "Render scale", "0.5", -2.0), level("RenderScale", "Render scale", "1", 0, true),
    } }
end
-- A game whose Shadows levels (0 to 4) are learned, with the given test as its newest quiet-spot test.
local function maxMenu(entry, opts, cvars)
    local e, ui, b = newUi(cvars, opts)
    b.now = function() return NOW end
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    if entry then b.state().history[1] = entry end
    return e, ui, b
end

test("UM-1 the profile items are Everyday, Crowded and Maximum by name, right after Settings, ticked and live; Original is not one of them", function()
    local e, ui = maxMenu(nil)
    local model = ui.menuModel(baseCtx({ profile = "maximum" }))
    local list = {}
    for i = 3, 5 do list[#list + 1] = model[i].text .. ":" .. model[i].kind .. ":" .. tostring(model[i].checked) end
    local everyday = find(ui.menuModel(baseCtx({ profile = "everyday" })), P_MAXIMUM)
    local first = find(model, P_MAXIMUM)
    e.slash("profile maximum")
    return table.concat(list, "|") == "Everyday:check:false|Crowded:check:false|Maximum:check:true" and everyday.checked == false
        and first.isChecked() == true and find(model, P_EVERYDAY).isChecked() == false and find(model, "Original") == nil,
        table.concat(list, "|") .. " " .. outText()
end)

test("UM-2 the Maximum hint carries the estimate when there is one; every profile has its hint, and no name carries a number", function()
    local _, ui = newUi()
    local with = ui.menuModel(baseCtx({ maxFps = 92 }))
    local without = ui.menuModel(baseCtx({}))
    return find(with, P_MAXIMUM).hint == H_MAXIMUM .. " (about 92 fps)" and find(without, P_MAXIMUM).hint == H_MAXIMUM
        and find(with, P_EVERYDAY).hint == H_EVERYDAY and find(with, P_CROWDED).hint == H_CROWDED
        and topTexts(with):find("about", 1, true) == nil, tostring(find(with, P_MAXIMUM).hint)
end)

test("UM-3 buildContext estimates Maximum from a Thorough quiet-spot test and from nothing else", function()
    local _, ui = maxMenu(thoroughQuiet())
    local thorough = ui.buildContext().maxFps
    local _, uiQuick = maxMenu(quickQuiet())
    local quick = uiQuick.buildContext().maxFps
    local _, uiNone = maxMenu(nil)
    local none = uiNone.buildContext().maxFps
    local _, uiSkipped = maxMenu(thoroughQuiet(nil, "RenderScale"))
    local skipped = uiSkipped.buildContext().maxFps
    local e5, ui5, b5 = newUi({ graphicsShadowQuality = "2", vsync = "0" })          -- nothing in this client has levels learned
    b5.now = function() return NOW end
    b5.state().history[1] = thoroughQuiet()
    local unlearned = ui5.buildContext().maxFps
    local _, uiRound = maxMenu(thoroughQuiet(1.194))
    local rounded = uiRound.buildContext().maxFps
    return thorough == 172 and quick == nil and none == nil and skipped == nil and unlearned == nil and rounded == 173,
        tostring(thorough) .. " " .. tostring(quick) .. " " .. tostring(none) .. " " .. tostring(skipped) .. " "
            .. tostring(unlearned) .. " " .. tostring(rounded)
end)

test("UM-3b a saved test the recommender cannot read gives no estimate, and the menu still builds", function()
    local _, ui = maxMenu({ valid = true, rows = { level("graphicsShadowQuality", "Shadows", "1", 0.5) } })     -- no baseline
    local ok, ctx = pcall(ui.buildContext)
    local built = ok and pcall(ui.menuModel, ctx)
    return ok and built and ctx.maxFps == nil, tostring(ctx)
end)

test("UM-3c without the recommender, the guide or the profiles module the menu still builds, with no estimate", function()
    local bad = {}
    for _, off in ipairs({ "recommend", "guide", "profiles" }) do
        local opts = { menu = "new" }
        opts[off] = false
        local _, ui = maxMenu(thoroughQuiet(), opts)
        local ok, ctx = pcall(ui.buildContext)
        if not ok or ctx.maxFps ~= nil then bad[#bad + 1] = off .. ": " .. tostring(ctx) end
    end
    return #bad == 0, table.concat(bad, " // ")
end)

test("UM-4 the Maximum tick is disabled in combat and while a test runs, enabled otherwise, and its click is /fset profile maximum", function()
    local e, ui = newUi()
    local sent = {}
    e.ns.command = function(msg) sent[#sent + 1] = msg end
    local function disabled(over) return find(ui.menuModel(baseCtx(over)), P_MAXIMUM).disabled end
    local idle, combat, running = disabled({}), disabled({ inCombat = true }), disabled({ active = true })
    find(ui.menuModel(baseCtx({})), P_MAXIMUM).run()
    return idle == false and combat == true and running == true and table.concat(sent, "|") == "profile maximum", table.concat(sent, "|")
end)

test("UM-5 both menu adapters draw Maximum as a check item that follows the live profile, with its estimate in the hint", function()
    local hint = H_MAXIMUM .. " (about 172 fps)"
    local e, ui = maxMenu(thoroughQuiet(), { menu = "new" })
    ui.openMenu({})
    local item = find(MENUCALLS.items, P_MAXIMUM)
    local before = item ~= nil and item.kind == "check" and item.isSelected() == false and tooltipOf(item) == P_MAXIMUM .. "|" .. hint
    item.fn()
    local newOk = before and item.isSelected() == true and e.ns.profiles.active() == "maximum"
    local e2, ui2 = maxMenu(thoroughQuiet(), { menu = "old" })
    ui2.openMenu({})
    local function infoByText(list, t)
        for _, info in ipairs(list) do if info.text == t then return info end end
    end
    local info = infoByText(MENUCALLS.levels[1], P_MAXIMUM)
    local oldOk = info ~= nil and info.notCheckable == false and info.checked == false and info.disabled == false and info.tooltipText == hint
    info.func()
    return newOk and oldOk and e2.ns.profiles.active() == "maximum", tostring(newOk) .. tostring(oldOk)
end)

test("UM-6 nothing in the menu is a raw setting name while Maximum is in use with its estimate", function()
    local _, ui = newUi()
    local model = ui.menuModel(baseCtx({ profile = "maximum", maxFps = 92, saved = { best = true, crowded = true } }))
    return rawIn(model) == nil, tostring(rawIn(model))
end)

return H.results()
