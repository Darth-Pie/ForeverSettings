-- UI.lua: a minimap button with a dropdown menu, and a small report window (spec section 15).
-- The menu is built from a pure model (ui.menuModel); every action calls the same function as its slash command,
-- so the menu holds no logic of its own. The two adapters to the client's menu system are thin and carry no logic.
local _, ns = ...

local ui = {}
ns.ui = ui

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar
local ATAN2 = math.atan2 or math.atan
local DEFAULT_ANGLE = 215
local REPORT_NAME = "ForeverSettingsReport"

-- saved state ----------------------------------------------------------------------------------------

-- The UI's part of the saved variables: {angle, hidden, autoReport}. nil before they have loaded.
function ui.state()
    local db = ns.db()
    if not db then return nil end
    db.ui = db.ui or {}
    return db.ui
end

-- The green check before the text of a finished test: a stock game texture, because the menu fonts have no check mark.
local CHECK = "|TInterface/RaidFrame/ReadyCheck-Ready:14|t "

local function listedTarget(n)
    for _, target in ipairs(ns.recommend and ns.recommend.TARGETS or {}) do
        if target == n then return true end
    end
    return false
end

-- saved results ----------------------------------------------------------------------------------------------

-- The check made of a recommendation when the test ran, as the results window wants it: the measured frame time is
-- stored scaled to the test's own baseline, so it is handed back against that baseline.
local function verifyOf(measurement)
    local v = measurement.verify
    if type(v) == "table" and type(v.measuredMs) == "number" and type(measurement.baselineMs) == "number" then
        return { ok = true, appliedMs = v.measuredMs, baselineMs = measurement.baselineMs }
    end
    return nil
end

-- "Measured in Highmountain, 3 days ago." for a finished test.
local function measuredLine(measurement)
    local seconds
    if type(measurement.time) == "number" and ns.bench and ns.bench.now then seconds = ns.bench.now() - measurement.time end
    return ns.names and ns.names.measured(measurement.zone, seconds) or nil
end

-- What a green check reopens (spec 2026-10-30-words-and-menu-design.md section 3.3): kind "best" (the newest finished
-- quiet-spot test) or "crowded" (the newest finished crowd test, laid over the quiet-spot test it was built on). Returns
-- {kind, entry, target, verify, again, measuredLine} for the results window, or nil when there is nothing it can show.
function ui.savedResult(kind)
    local st = ui.state()
    if not st or not ns.bench or not ns.guide or not ns.guide.findQuiet or not ns.recommend then return nil end
    local quiet = ns.guide.findQuiet()
    if not quiet then return nil end
    if kind == "best" then
        if not listedTarget(st.target) then return nil end
        return { kind = "best", entry = quiet, target = st.target, verify = verifyOf(quiet), again = "setup",
            measuredLine = measuredLine(quiet) }
    elseif kind == "crowded" then
        if not listedTarget(st.crowdTarget) then return nil end
        local history = ns.bench.history()
        local crowd
        for i = #history, 1, -1 do
            if history[i].kind == "crowd" and history[i].valid == true then
                crowd = history[i]
                break
            end
        end
        if not crowd then return nil end
        local base = quiet
        if crowd.quietTime then
            for _, entry in ipairs(history) do
                if entry.time == crowd.quietTime and entry.kind ~= "crowd" and entry.valid == true and not entry.label
                    and type(entry.rows) == "table" and #entry.rows > 0 then
                    base = entry
                    break
                end
            end
        end
        return { kind = "crowded", entry = ns.recommend.crowdEntry(base, crowd), target = st.crowdTarget,
            verify = verifyOf(crowd), again = "crowd", measuredLine = measuredLine(crowd) }
    end
    return nil
end

-- A click on "Find my best settings" or "Find my crowded settings": the saved result when there is one, else the test.
function ui.openSaved(kind)
    local saved = ui.savedResult(kind)
    if saved and ns.results and ns.results.show then
        local ok, err = pcall(ns.results.show, saved.entry, saved.target, saved.verify,
            { again = saved.again, measuredLine = saved.measuredLine })
        if not ok then ns.say("the saved result could not be shown: " .. tostring(err)) end
        return
    end
    if not ns.bench then
        ns.say("bench module not loaded")
    elseif ns.guide and ns.guide.open then
        ns.guide.open(kind == "best" and "setup" or "crowd")
    else
        ns.say("guide module not loaded")
    end
end

-- the menu model (pure) -------------------------------------------------------------------------------

-- ctx = {profile, raidToo, raidSwitchOff, active, inCombat, progress, saved = {best, crowded}, last, maxFps}; every field
-- may be missing. Returns a list of items {text, kind, disabled, checked, isChecked, done, run, children}; kind is title, button,
-- check, submenu, separator or info. `checked` is the value when the menu was built; a check item's `isChecked()` asks
-- again, because the client keeps its menu open after a click and re-asks which item is selected. `done` marks a finished
-- test (the adapters draw the green check).
function ui.menuModel(ctx)
    local items = {}
    local function add(item) items[#items + 1] = item end
    -- While a run is active it owns the settings: nothing that changes the list or a setting may be clicked.
    local locked = ctx.active and true or false
    local function command(msg) return function() ns.command(msg) end end
    local function bench(name)
        return function()
            if not ns.bench then
                ns.say("bench module not loaded")
            elseif ns.guide and (name == "run" or name == "check") then
                ns.guide.open(name)
            elseif name == "run" or name == "check" then
                ns.say("guide module not loaded")
            else
                ns.bench[name]()
            end
        end
    end

    add({ text = "ForeverSettings", kind = "title" })
    add({ kind = "separator" })

    -- Profiles (spec 2026-10-29-profiles-design.md section 5). The ticks ask again, like the tier ticks: the client
    -- keeps its menu open after a click.
    add({ text = "Profile", kind = "title" })
    local function profileItem(key)
        local text = ns.names and ns.names.PROFILE[key] or key
        -- Maximum says what the newest quiet-spot test makes of it, when the test measured the highest level of everything.
        if key == "maximum" and type(ctx.maxFps) == "number" then text = text .. string.format(" (about %.0f fps)", ctx.maxFps) end
        return { text = text, kind = "check", checked = ((ctx.profile or "original") == key),
            isChecked = function() return ns.profiles ~= nil and ns.profiles.active() == key end,
            disabled = locked or (ctx.inCombat and true or false), run = command("profile " .. key) }
    end
    add(profileItem("original"))
    add(profileItem("everyday"))
    add(profileItem("crowded"))
    add(profileItem("maximum"))
    add({ text = "Save my game's current settings as...", kind = "submenu", children = {
        { text = "Everyday", kind = "button", disabled = locked, run = command("profile save everyday") },
        { text = "Crowded", kind = "button", disabled = locked, run = command("profile save crowded") },
    } })
    local function raidOn()
        local db = ns.db()
        return db ~= nil and db.raidToo == true
    end
    add({ text = "Also use the Crowded settings in raids and battlegrounds", kind = "check", checked = ctx.raidToo == true,
        isChecked = raidOn, disabled = locked or (ctx.inCombat and true or false),
        run = function() ns.command("profile raid " .. (raidOn() and "off" or "on")) end })
    if ctx.raidSwitchOff then
        add({ text = "Needs the game's raid graphics turned on.",
            kind = "info", disabled = true })
    end
    add({ kind = "separator" })

    add({ text = "Find my settings", kind = "title" })
    local busy = (ctx.inCombat or ctx.active) and true or false
    local saved = ctx.saved or {}
    add({ text = "Find my best settings", kind = "button", disabled = busy, done = saved.best == true,
        run = function() ui.openSaved("best") end })
    add({ text = "Find my crowded settings", kind = "button", disabled = busy, done = saved.crowded == true,
        run = function() ui.openSaved("crowded") end })
    add({ text = "Stop", kind = "button", disabled = not ctx.active, run = bench("stop") })
    local progress = ctx.progress
    if progress then
        add({ text = string.format("A test is running: step %d of %d (%s)", progress.done, progress.total,
            ns.names and ns.names.progress(progress) or tostring(progress.label)), kind = "info", disabled = true })
    end
    add({ kind = "separator" })

    add({ text = "My settings...", kind = "button", run = function()
        if ns.settings and ns.settings.open then ns.settings.open() else ns.say("settings module not loaded") end
    end })
    add({ text = "Advanced", kind = "submenu", children = {
        { text = "Check this spot", kind = "button", disabled = busy, run = bench("check") },
        { text = "Run benchmark", kind = "button", disabled = busy, run = bench("run") },
        { text = "Show last report", kind = "button", disabled = ctx.last == nil, run = function() ui.showReport(ctx.last) end },
        { text = "Apply all now", kind = "button", disabled = locked, run = command("apply") },
        { text = "Put back everything this addon changed", kind = "button", disabled = locked, run = command("reset") },
    } })
    return items
end

-- What the newest quiet-spot test makes of Maximum (spec 2026-10-30-maximum-and-costs-design.md section 3.3): a whole
-- number of frames per second, or nil when there is nothing to set, no test, or the test did not measure the highest level
-- of every setting Maximum would set (a Quick test, a setting it skipped): a number that was not measured is never shown.
local function maxFps()
    if not (ns.profiles and ns.guide and ns.recommend) then return nil end
    local values = ns.profiles.maxValues()
    if next(values) == nil then return nil end
    -- A saved test the recommender cannot read must not keep the menu from opening.
    local ok, estimate = pcall(ns.recommend.estimateFps, ns.guide.findQuiet(), values)
    if not ok or not estimate or #estimate.missing > 0 then return nil end
    return math.floor(estimate.fps + 0.5)
end

-- Reads the live state the model needs.
function ui.buildContext()
    local db = ns.db()
    local ctx = { active = false, inCombat = InCombatLockdown() and true or false,
        profile = ns.profiles and ns.profiles.active() or "original", raidToo = db ~= nil and db.raidToo == true,
        raidSwitchOff = GetCVar("RAIDsettingsEnabled") == "0", saved = { best = false, crowded = false } }
    local bench = ns.bench
    if bench then
        ctx.active = bench.active()
        ctx.progress = bench.progress()
        local history = bench.history()
        -- A crowd entry has no rows of its own: it is not the last report.
        for i = #history, 1, -1 do
            if history[i].kind ~= "crowd" then
                ctx.last = history[i]
                break
            end
        end
    end
    ctx.saved = { best = ui.savedResult("best") ~= nil, crowded = ui.savedResult("crowded") ~= nil }
    ctx.maxFps = maxFps()
    return ctx
end

-- the two adapters to the client's menu system ----------------------------------------------------------

local function disable(element)
    if element and element.SetEnabled then pcall(element.SetEnabled, element, false) end
end

local function openNew(owner, model)
    local function build(parent, items)
        for _, item in ipairs(items) do
            local kind = item.kind
            if kind == "title" then
                parent:CreateTitle(item.text)
            elseif kind == "separator" then
                parent:CreateDivider()
            elseif kind == "info" then
                disable(parent:CreateButton(item.text, function() end))
            elseif kind == "check" then
                local element = parent:CreateCheckbox(item.text, item.isChecked or function() return item.checked end, item.run)
                if item.disabled then disable(element) end
            elseif kind == "submenu" then
                build(parent:CreateButton(item.text), item.children)
            else
                local element = parent:CreateButton(item.done and (CHECK .. item.text) or item.text, item.run)
                if item.disabled then disable(element) end
            end
        end
    end
    MenuUtil.CreateContextMenu(owner, function(_, root) build(root, model) end)
end

local menuFrame

local function openOld(owner, model)
    menuFrame = menuFrame or CreateFrame("Frame", "ForeverSettingsMenuFrame", UIParent, "UIDropDownMenuTemplate")
    local function addItems(items, level)
        for _, item in ipairs(items) do
            if item.kind == "separator" then
                if UIDropDownMenu_AddSeparator then UIDropDownMenu_AddSeparator(level) end
            else
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.done and (CHECK .. item.text) or item.text
                info.notCheckable = item.kind ~= "check"
                info.isTitle = item.kind == "title"
                info.disabled = (item.disabled or item.kind == "title" or item.kind == "info") and true or false
                if item.kind == "check" then
                    info.checked = item.checked
                    info.func = function() item.run() end
                elseif item.kind == "submenu" then
                    info.hasArrow = true
                    info.menuList = item.children
                elseif item.kind == "button" then
                    info.func = function() item.run() end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end
    UIDropDownMenu_Initialize(menuFrame, function(_, level, menuList)
        addItems(menuList or model, level or 1)
    end, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, owner, 0, 0)
end

-- Opens the menu: the client's newer menu system if it has one, else the older dropdown functions, else a help line.
function ui.openMenu(owner)
    local model = ui.menuModel(ui.buildContext())
    local ok, err
    if MenuUtil and MenuUtil.CreateContextMenu then
        ok, err = pcall(openNew, owner, model)
    elseif UIDropDownMenu_Initialize and ToggleDropDownMenu and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
        ok, err = pcall(openOld, owner, model)
    else
        ns.say("the menu is not available in this client; commands: /fset, /fset bench")
        return
    end
    if not ok then ns.say("menu failed: " .. tostring(err) .. "; commands: /fset, /fset bench") end
end

-- the report window --------------------------------------------------------------------------------------

local reportFrame, reportBox

local function ensureReport()
    if reportFrame then return end
    local ok, f = pcall(CreateFrame, "Frame", REPORT_NAME, UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then f = CreateFrame("Frame", REPORT_NAME, UIParent) end
    f:SetSize(620, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(570)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(box)
    if f.SetTitle then f:SetTitle("ForeverSettings report") end
    tinsert(UISpecialFrames, REPORT_NAME)
    reportFrame, reportBox = f, box
end

-- Shows a history entry's report in a small movable window; the text is selectable, so it can be copied.
function ui.showReport(entry)
    if not entry then
        ns.say("no saved benchmark to show")
        return
    end
    ensureReport()
    reportBox:SetText(table.concat(ns.bench.report(entry), "\n"))
    reportFrame:Show()
end

-- Called by Bench.lua when a full run has ended: valid runs open the window unless db.ui.autoReport is false.
function ui.runFinished(entry)
    if ns.guide and ns.guide.handlesReport and ns.guide.handlesReport() then return end
    local st = ui.state()
    if entry.valid and not (st and st.autoReport == false) then ui.showReport(entry) end
end

-- the minimap button ------------------------------------------------------------------------------------------

local button

local function positionButton()
    if not button then return end
    local st = ui.state()
    local angle = math.rad((st and st.angle) or DEFAULT_ANGLE)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local st = ui.state()
    if st then st.angle = math.deg(ATAN2(cy / scale - my, cx / scale - mx)) end
    positionButton()
end

local function showTooltip(self)
    local db = ns.db()
    local forced = 0
    if db and db.want then
        for _ in pairs(db.want) do forced = forced + 1 end
    end
    local p = ns.bench and ns.bench.progress()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ForeverSettings")
    local key = ns.profiles and ns.profiles.active() or "original"
    GameTooltip:AddLine("Profile: " .. ((ns.profiles and ns.profiles.LABEL[key]) or key))
    GameTooltip:AddLine(p and string.format("test running: step %d of %d (%s)", p.done, p.total,
        ns.names and ns.names.progress(p) or tostring(p.label)) or "no test running")
    GameTooltip:AddLine(string.format("Keeping %d setting%s for you", forced, forced == 1 and "" or "s"))
    GameTooltip:Show()
end

local function createButton()
    if button or not Minimap then return end
    button = CreateFrame("Button", "ForeverSettingsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface/Icons/INV_Misc_Gear_01")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self) ui.openMenu(self) end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    positionButton()
    local st = ui.state()
    if st and st.hidden then button:Hide() end
end

-- `/fset minimap`: shows or hides the button; the choice is saved.
function ui.toggleButton()
    local st = ui.state()
    if not st then return end
    st.hidden = not st.hidden
    createButton()
    if button then
        if st.hidden then button:Hide() else button:Show() end
    end
    ns.say("minimap button " .. (st.hidden and "hidden" or "shown"))
end

-- The client facts this file assumes; `check` prints each as PASS or FAIL.
function ui.environment()
    local newApi = MenuUtil ~= nil and type(MenuUtil.CreateContextMenu) == "function"
    local oldApi = type(UIDropDownMenu_Initialize) == "function" and type(ToggleDropDownMenu) == "function"
    return {
        { name = "menu API", ok = newApi or oldApi, detail = "the minimap menu needs MenuUtil or the UIDropDownMenu functions" },
        { name = "Minimap", ok = Minimap ~= nil, detail = "the minimap button needs it" },
    }
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then createButton() end
end)
