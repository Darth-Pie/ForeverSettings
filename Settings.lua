-- Settings.lua: the My settings window (spec 2026-10-30-words-and-menu-design.md section 3.4). A pure model and a thin
-- frame adapter, in the same shape as Guide.lua and Results.lua. Loaded after UI.lua.
local _, ns = ...

local settings = {}
ns.settings = settings

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar

local FRAME_NAME = "ForeverSettingsSettings"
local WIDTH, HEIGHT = 580, 540
local CONTENT_WIDTH = 520
local REFRESH = 0.5            -- seconds of frame time between looks at what changed outside the window
local BUTTON_WIDTH, BUTTON_GAP = 100, 4
local COST_HEIGHT = 14             -- the second line under a level button: a line of level buttons is this much taller
local FOOTER_WIDTH = { use = 230, maximum = 160, close = 100 }
local FOOTER_GAP = 12

local INTRO = "Choose how the game looks. Settings you tick are kept: the addon puts them back at every loading screen."
local ORIGINAL_NOTE = "You're using your Original settings (hands off). Switch to Everyday or Crowded in the menu to turn these on."
local MAXIMUM_NOTE = "You're using Maximum (everything at its highest). It includes the sharpest textures, which need plenty of "
    .. "graphics memory. Switch to Everyday or Crowded in the menu to change these."
local COST_NONE = "Run Find my best settings to see what each level costs."
local MATTERS_NOTE = [["Matters to the picture" is the addon's own judgement, not something it measured.]]
local NOTHING_TEXT = "Maximum has nothing to set yet: run Find my best settings once so the addon learns what each setting can do."
local USE_TEXT = "Use what I have in the game now"
local MAXIMUM_TEXT = "Switch to Maximum"
local LOCKED_TEXT = {
    combat = "You are in combat; try again afterwards.",
    busy = "A test is running; try again afterwards.",
}
local TABS = { "everyday", "crowded" }
local TAB_TEXT = { everyday = "Everyday", crowded = "Crowded" }

local state = { tab = "everyday" }

local function sameValue(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and y ~= nil and x == y
end

-- The measured settings in the order of the names table; one the table does not know goes last.
local function ordered(resolved)
    local rank = {}
    for i, cvar in ipairs(ns.names.ORDER) do rank[cvar:lower()] = i end
    local list = {}
    for i, entry in ipairs(resolved or {}) do list[i] = entry end
    table.sort(list, function(a, b)
        local ra, rb = rank[a.cvar:lower()] or 1000, rank[b.cvar:lower()] or 1000
        if ra ~= rb then return ra < rb end
        return a.cvar < b.cvar
    end)
    return list
end

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

-- "+8 fps", "-12 fps" or "same" (the difference rounds to nothing): a level's frame rate against the held level's.
local function costText(fps, heldFps)
    local diff = fps - heldFps
    local whole = math.floor(math.abs(diff) + 0.5)
    if whole == 0 then return "same" end
    return (diff > 0 and "+" or "-") .. whole .. " fps"
end

-- The frame rate the test measured for `value` in a setting's list of {value, fps}, or nil when it did not measure it.
local function fpsOf(list, value)
    for _, item in ipairs(list or {}) do
        if sameValue(item.value, value) then return item.fps end
    end
    return nil
end

local function leftOutSentence(n)
    if n == 1 then return "1 setting stays as it is: the addon has not learned its levels yet." end
    return n .. " settings stay as they are: the addon has not learned their levels yet."
end

-- Levels learned since Maximum was switched on: known now, not applied until a loading screen or another click on Maximum.
local function pendingSentence(n)
    local tail = " at the next loading screen, or when you choose Maximum in the menu again."
    if n == 1 then return "1 setting will go to its highest level" .. tail end
    return n .. " settings will go to their highest level" .. tail
end

-- The settings the game would not put at the highest level, by their plain names (a setting with no plain name is left out).
local function refusedNames(mismatched)
    local list = {}
    for _, m in ipairs(mismatched) do
        local name = ns.names.label(m.cvar, "")
        if name ~= "" then list[#list + 1] = name end
    end
    return list
end

-- What the window shows, with no frames (spec 3.4 and 2026-10-30-maximum-and-costs-design.md section 3.2).
-- state = {tab, notice}; ctx = {active, saved = {everyday, crowded}, live(cvar), resolved, locked = nil | "combat" | "busy",
-- costs = {kind = "quiet" | "crowd", measuredLine, fps = recommend.levelFps(entry)}, maximum = {fps, skipped, leftOut}}; the
-- last two are missing when no test can be read.
function settings.model(st, ctx)
    local names = ns.names
    local locked = ctx.locked
    local view = { title = "My settings", intro = INTRO, tabs = {}, rows = {}, buttons = {} }
    for _, key in ipairs(TABS) do
        local inUse = ctx.active == key
        view.tabs[#view.tabs + 1] = {
            key = key, text = TAB_TEXT[key] .. (inUse and " (in use)" or ""), inUse = inUse, selected = st.tab == key,
            note = names.PROFILE_NOTE[key], enabled = locked == nil,
        }
    end
    local max = ctx.maximum
    if ctx.active == "original" then
        view.notice = ORIGINAL_NOTE
    elseif ctx.active == "maximum" then
        view.notice = MAXIMUM_NOTE
        if max and (max.leftOut or 0) > 0 then view.notice = view.notice .. " " .. leftOutSentence(max.leftOut) end
        if max and (max.pending or 0) > 0 then view.notice = view.notice .. " " .. pendingSentence(max.pending) end
    end
    if locked then view.locked = LOCKED_TEXT[locked] end
    view.refusal = st.notice
    -- A test whose costs there is nothing to read from (a run that measured nothing) is no test here.
    local costs = ctx.costs
    if costs and not (costs.fps and next(costs.fps.byCvar or {}) ~= nil) then costs = nil end
    if costs then
        view.costNote = "Costs from your " .. (costs.kind == "crowd" and "crowd" or "quiet-spot") .. " test."
            .. (costs.measuredLine and (" " .. costs.measuredLine) or "")
    else
        view.costNote = COST_NONE
    end
    local onTabInUse = st.tab == ctx.active
    local saved = (ctx.saved or {})[st.tab] or {}
    local ranking = ns.recommend and ns.recommend.RANKING or {}
    for _, entry in ipairs(ordered(ctx.resolved)) do
        local cvar = entry.cvar
        local _, line = names.get(cvar)
        local row = { cvar = cvar, name = names.label(cvar, entry.label), line = line, kept = saved[cvar] ~= nil,
            levels = {}, enabled = locked == nil }
        local words = ranking[cvar] and names.matters(ranking[cvar].weight)
        if words then
            row.matters = "Matters to the picture: " .. words .. "."
            view.mattersNote = MATTERS_NOTE
        end
        local chosen = saved[cvar]
        if onTabInUse then chosen = ctx.live(cvar) end
        -- Costs are measured against the level this tab holds; a setting it holds no level for, or whose held level the
        -- test did not measure, shows none.
        local list = costs and costs.fps.byCvar[cvar]
        local heldFps = list and chosen ~= nil and fpsOf(list, chosen) or nil
        for i, value in ipairs(entry.tiers) do
            local position
            if i == 1 then position = "lowest" elseif i == #entry.tiers then position = "highest" end
            local level = { value = value, text = names.level(cvar, value, position),
                selected = chosen ~= nil and sameValue(chosen, value) }
            if heldFps then
                if sameValue(chosen, value) then
                    level.cost = "now"
                else
                    local fps = fpsOf(list, value)
                    level.cost = fps and costText(fps, heldFps) or "?"
                end
            end
            row.levels[#row.levels + 1] = level
        end
        view.rows[#view.rows + 1] = row
    end
    if costs and max then
        if type(max.fps) == "number" then
            view.totalLine = string.format("Everything at the highest: about %.0f fps.", max.fps)
        elseif (max.skipped or 0) > 0 then
            view.totalLine = "The test skipped the highest levels of " .. plural(max.skipped, "setting")
                .. ", so there is no total yet. Run Find my best settings and choose Thorough."
        end
    end
    view.buttons[#view.buttons + 1] = { key = "use", text = USE_TEXT, enabled = locked == nil }
    if ctx.active ~= "maximum" then
        view.buttons[#view.buttons + 1] = { key = "maximum", text = MAXIMUM_TEXT, enabled = locked == nil }
    end
    view.buttons[#view.buttons + 1] = { key = "close", text = "Close", enabled = true }
    return view
end

-- The flow --------------------------------------------------------------------------------------------------------

local lastError
local function guarded(fn)
    local ok, err = pcall(fn)
    if not ok and err ~= lastError then
        lastError = err
        ns.say("the My settings window could not be drawn: " .. tostring(err) .. " (tell the person who gave you this addon)")
    end
end

local function lockReason()
    if InCombatLockdown() then return "combat" end
    if ns.suspended or (ns.bench and ns.bench.active and ns.bench.active()) then return "busy" end
    return nil
end

-- The test a tab's costs are read from: the Crowded tab takes the saved crowd result's rebuilt entry when there is one, else
-- (and always for Everyday) the newest quiet-spot test. {kind, entry, measuredLine}, or nil when there is none.
local function costSource(tab)
    if not (ns.guide and ns.recommend) then return nil end
    if tab == "crowded" and ns.ui then
        local ok, saved = pcall(ns.ui.savedResult, "crowded")
        if ok and saved then return { kind = "crowd", entry = saved.entry, measuredLine = saved.measuredLine } end
    end
    local quiet = ns.guide.findQuiet()
    if not quiet then return nil end
    local line
    if type(quiet.time) == "number" then line = ns.names.measured(quiet.zone, ns.bench.now() - quiet.time) end
    return { kind = "quiet", entry = quiet, measuredLine = line }
end

-- ctx.costs and ctx.maximum for a tab: what each level costs against the test, and what everything at the highest would give
-- ({fps, skipped, leftOut}: fps only when the test measured the highest level of every setting Maximum would set). A test the
-- recommender cannot read is no test: the window must still draw.
local function costsAndMaximum(tab)
    local values, leftOut = {}, {}
    if ns.profiles then values, leftOut = ns.profiles.maxValues() end
    local maximum = { skipped = 0, leftOut = #leftOut, pending = 0 }
    local db = ns.profiles and ns.profiles.state()
    for cvar, value in pairs(values) do
        if not (db and db.want[cvar] ~= nil and sameValue(db.want[cvar], value)) then maximum.pending = maximum.pending + 1 end
    end
    local source = costSource(tab)
    if not source then return nil, maximum end
    local ok, fps = pcall(ns.recommend.levelFps, source.entry)
    if not ok or not fps then return nil, maximum end
    if next(values) ~= nil then
        local estimate = ns.recommend.estimateFps(source.entry, values)        -- the entry was read just above: this cannot raise
        if estimate then
            if #estimate.missing > 0 then maximum.skipped = #estimate.missing else maximum.fps = estimate.fps end
        end
    end
    return { kind = source.kind, measuredLine = source.measuredLine, fps = fps }, maximum
end

-- The live facts the model needs; the costs only for a draw (they are not part of what the refresh looks at).
local function context(withCosts)
    local db = ns.profiles and ns.profiles.state()
    local saved = { everyday = {}, crowded = {} }
    if db then
        for _, key in ipairs(TABS) do saved[key] = db.profiles[key].values end
    end
    local ctx = {
        active = db and db.active or "original", saved = saved, live = function(cvar) return GetCVar(cvar) end,
        resolved = ns.bench and ns.bench.resolve() or {}, locked = lockReason(),
    }
    if withCosts then ctx.costs, ctx.maximum = costsAndMaximum(state.tab) end
    return ctx
end

local function defaultTab()
    return ns.profiles and ns.profiles.active() == "crowded" and "crowded" or "everyday"
end

local function draw()
    guarded(settings.render)
end

function settings.state()
    return state
end

-- Shows the window on `tab` (Everyday or Crowded), else on the profile in use.
function settings.open(tab)
    if tab == "everyday" or tab == "crowded" then state.tab = tab else state.tab = defaultTab() end
    guarded(function()
        settings.render()
        settings.show()
    end)
end

-- A button or tick of the window, by the keys of the model: tab:<tab>, keep:<cvar>, level:<cvar>:<value>, use, maximum,
-- close. A refusal Maximum gives is shown in the window until the next click or redraw.
function settings.click(key)
    if key == "close" then
        settings.hide()
        return
    end
    local ctx = context()
    if ctx.locked then
        if key == "maximum" then draw() end          -- the draw says why (the window may not have caught up yet)
        return
    end
    local tab = key:match("^tab:(.+)$")
    if tab then
        if tab == "everyday" or tab == "crowded" then
            state.tab = tab
            draw()
        end
        return
    end
    if not ns.profiles then return end
    if key == "maximum" then
        local ok, info = ns.profiles.switch("maximum", true)
        if not ok and info == "nothing" then
            state.notice = NOTHING_TEXT
        elseif ok then
            -- The switch stands, but a level the game would not take is said here, since nothing is said in chat.
            local refused = refusedNames(info.mismatched)
            if #refused > 0 then
                state.notice = "The game would not take the highest level for: " .. table.concat(refused, ", ") .. "."
            end
        end
        draw()
        return
    end
    local profile = state.tab
    if key == "use" then
        ns.profiles.save(profile, true)
        draw()
        return
    end
    local cvar = key:match("^keep:(.+)$")
    if cvar then
        if ctx.saved[profile][cvar] ~= nil then
            ns.profiles.unsetProfileValue(profile, cvar, true)
        else
            local now = GetCVar(cvar)
            if now ~= nil then ns.profiles.setProfileValue(profile, cvar, now, true) end
        end
        draw()
        return
    end
    local pickedCvar, value = key:match("^level:([^:]+):(.+)$")
    if pickedCvar then
        ns.profiles.setProfileValue(profile, pickedCvar, value, true)
        draw()
    end
end

-- The window (frame adapter) ----------------------------------------------------------------------------------------

local frame, parts
local sinceRefresh = 0
local lastSignature

local function make(kind, name, parent, template, fallbackKind)
    local ok, made = pcall(CreateFrame, kind, name, parent, template)
    if ok and made then return made, true end
    return CreateFrame(fallbackKind or kind, name, parent), false
end

local function giveLabel(button)
    local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button:SetFontString(fs)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)
end

local function text(parent, font, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    return fs
end

local function heightOf(fs, str)
    local h = fs:GetStringHeight()
    if type(h) == "number" and h > 0 then return h end
    local _, breaks = str:gsub("\n", "\n")
    return 14 * (breaks + 1)
end

local function newPool(parent, create)
    return { parent = parent, create = create, items = {}, used = 0 }
end
local function take(pool)
    pool.used = pool.used + 1
    local item = pool.items[pool.used]
    if not item then
        item = pool.create(pool.parent)
        pool.items[pool.used] = item
    end
    item:Show()
    return item
end
-- What a draw did not use is hidden; a font string is also emptied.
local function release(pool, hasText)
    for i = pool.used + 1, #pool.items do
        pool.items[i]:Hide()
        if hasText then pool.items[i]:SetText("") end
    end
    pool.used = 0
end

local function clicked(self) settings.click(self.key) end

local function makeButton(parent, width)
    local button, templated = make("Button", nil, parent, "UIPanelButtonTemplate")
    if not templated then giveLabel(button) end
    button:SetSize(width, 24)
    button:SetScript("OnClick", clicked)
    return button
end

local function makeCheck(parent)
    local box = make("CheckButton", nil, parent, "UICheckButtonTemplate", "Button")
    box:SetSize(26, 26)
    box:SetScript("OnClick", clicked)
    return box
end

-- A signature of everything the window shows that can change outside it.
local function signature(ctx)
    local list = { tostring(ctx.active), tostring(ctx.locked), state.tab }
    for _, entry in ipairs(ctx.resolved) do
        local cvar = entry.cvar
        list[#list + 1] = cvar .. "=" .. tostring(ctx.live(cvar)) .. "/" .. tostring(ctx.saved.everyday[cvar]) .. "/"
            .. tostring(ctx.saved.crowded[cvar])
    end
    return table.concat(list, "|")
end

local function build()
    local f, templated = make("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, HEIGHT)
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
    local p = {}
    p.title = text(f, "GameFontNormalLarge", WIDTH - 40)
    p.intro = text(f, "GameFontHighlight", WIDTH - 40)
    p.note = text(f, "GameFontNormal", WIDTH - 40)
    p.costNote = text(f, "GameFontHighlightSmall", WIDTH - 40)
    p.notice = text(f, "GameFontNormal", WIDTH - 40)
    p.notice:SetTextColor(1, 0.2, 0.2)
    p.mattersNote = text(f, "GameFontDisableSmall", WIDTH - 40)
    p.total = text(f, "GameFontNormal", WIDTH - 40)
    p.tabs = {}
    for i, key in ipairs(TABS) do
        local button = makeButton(f, 180)
        button.key = "tab:" .. key
        p.tabs[i] = button
    end
    p.scroll = make("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    p.content = CreateFrame("Frame", nil, p.scroll)
    p.scroll:SetScrollChild(p.content)
    p.scroll:EnableMouseWheel(true)
    p.scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local now = self:GetVerticalScroll()
        if type(range) ~= "number" or type(now) ~= "number" then return end
        self:SetVerticalScroll(math.max(0, math.min(range, now - delta * 32)))
    end)
    p.names = newPool(p.content, function(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetJustifyH("LEFT")
        return fs
    end)
    p.lines = newPool(p.content, function(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetJustifyH("LEFT")
        return fs
    end)
    p.matters = newPool(p.content, function(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        return fs
    end)
    p.checks = newPool(p.content, makeCheck)
    p.levels = newPool(p.content, function(parent) return makeButton(parent, BUTTON_WIDTH) end)
    -- The second line under a level button: what that level costs against the level held.
    p.costs = newPool(p.content, function(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetWidth(BUTTON_WIDTH)
        fs:SetJustifyH("CENTER")
        return fs
    end)
    p.use = makeButton(f, FOOTER_WIDTH.use)
    p.use.key = "use"
    p.maximum = makeButton(f, FOOTER_WIDTH.maximum)
    p.maximum.key = "maximum"
    p.close = makeButton(f, FOOTER_WIDTH.close)
    p.close.key = "close"
    f:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh < REFRESH then return end
        sinceRefresh = 0
        if signature(context()) ~= lastSignature then draw() end
    end)
    local listed = false
    for _, name in ipairs(UISpecialFrames) do
        if name == FRAME_NAME then listed = true end
    end
    if not listed then tinsert(UISpecialFrames, FRAME_NAME) end
    frame, parts = f, p
    return f
end

local function ensure()
    return frame or build()
end

-- Draws the model: title, intro, tabs, the tab's note, the note on where the costs come from, any notice, one row per
-- setting (with what each level costs and what the setting is worth), the total and the notes above the footer, the footer.
function settings.render()
    local f = ensure()
    local p = parts
    local ctx = context(true)
    local view = settings.model(state, ctx)
    state.notice = nil                       -- a refusal is shown once: until the next click or redraw
    lastSignature = signature(ctx)

    local y = 34
    local function place(fs, str, gap)
        fs:SetText(str)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -y)
        fs:Show()
        y = y + heightOf(fs, str) + gap
    end
    place(p.title, view.title, 6)
    place(p.intro, view.intro, 8)
    local selectedNote = ""
    for i, tab in ipairs(view.tabs) do
        local button = p.tabs[i]
        button:SetText(tab.text)
        button:SetEnabled(tab.enabled)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", f, "TOPLEFT", 20 + (i - 1) * 186, -y)
        if tab.selected then
            button:LockHighlight()
            selectedNote = tab.note or ""
        else
            button:UnlockHighlight()
        end
        button:Show()
    end
    y = y + 32
    place(p.note, selectedNote, 6)
    place(p.costNote, view.costNote, 6)
    local notices = {}
    if view.notice then notices[#notices + 1] = view.notice end
    if view.locked then notices[#notices + 1] = view.locked end
    if view.refusal then notices[#notices + 1] = view.refusal end
    if #notices > 0 then place(p.notice, table.concat(notices, "\n"), 6) else p.notice:SetText(""); p.notice:Hide() end

    -- Above the footer buttons, stacked up from them: the total, then the note on "matters to the picture".
    local bottom = 44
    local function stack(fs, str)
        if not str then
            fs:SetText("")
            fs:Hide()
            return
        end
        fs:SetText(str)
        fs:ClearAllPoints()
        fs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, bottom)
        fs:Show()
        bottom = bottom + heightOf(fs, str) + 4
    end
    stack(p.total, view.totalLine)
    stack(p.mattersNote, view.mattersNote)

    p.scroll:ClearAllPoints()
    p.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -y)
    p.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, math.max(56, bottom + 2))
    local perLine = math.max(1, math.floor((CONTENT_WIDTH - 40) / (BUTTON_WIDTH + BUTTON_GAP)))
    local cy = 0
    for _, row in ipairs(view.rows) do
        local box = take(p.checks)
        box.key = "keep:" .. row.cvar
        box:SetChecked(row.kept)
        box:SetEnabled(row.enabled)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -cy)
        local name = take(p.names)
        name:SetText(row.name)
        name:SetWidth(CONTENT_WIDTH - 40)
        name:ClearAllPoints()
        name:SetPoint("TOPLEFT", p.content, "TOPLEFT", 36, -(cy + 4))
        local line = take(p.lines)
        line:SetText(row.line or "")
        line:SetWidth(CONTENT_WIDTH - 40)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", p.content, "TOPLEFT", 36, -(cy + 22))
        local lineHeight = heightOf(line, row.line or "")
        local by = cy + 22 + lineHeight + 4
        if row.matters then
            local worth = take(p.matters)
            worth:SetText(row.matters)
            worth:SetWidth(CONTENT_WIDTH - 40)
            worth:ClearAllPoints()
            worth:SetPoint("TOPLEFT", p.content, "TOPLEFT", 36, -(by - 2))
            by = by + heightOf(worth, row.matters)
        end
        -- Every line of level buttons of a row with costs is taller by the second line under each button.
        local pitch = 28
        for _, level in ipairs(row.levels) do
            if level.cost then pitch = 28 + COST_HEIGHT end
        end
        for i, level in ipairs(row.levels) do
            local button = take(p.levels)
            button.key = "level:" .. row.cvar .. ":" .. level.value
            button:SetText(level.text)
            button:SetEnabled(row.enabled)
            local col, rowNo = (i - 1) % perLine, math.floor((i - 1) / perLine)
            local x, top = 36 + col * (BUTTON_WIDTH + BUTTON_GAP), by + rowNo * pitch
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -top)
            if level.selected then button:LockHighlight() else button:UnlockHighlight() end
            if level.cost then
                local cost = take(p.costs)
                cost:SetText(level.cost)
                cost:ClearAllPoints()
                cost:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -(top + 25))
            end
        end
        cy = by + math.ceil(#row.levels / perLine) * pitch + 12
    end
    p.content:SetSize(CONTENT_WIDTH, math.max(cy, 1))
    release(p.checks)
    release(p.names, true)
    release(p.lines, true)
    release(p.matters, true)
    release(p.levels)
    release(p.costs, true)

    -- The footer buttons the model lists, in a row centred on the window.
    local width = FOOTER_GAP * (#view.buttons - 1)
    for _, button in ipairs(view.buttons) do width = width + FOOTER_WIDTH[button.key] end
    local x = -width / 2
    p.maximum:Hide()
    for _, button in ipairs(view.buttons) do
        local part, w = p[button.key], FOOTER_WIDTH[button.key]
        part:SetText(button.text)
        part:SetEnabled(button.enabled)
        part:ClearAllPoints()
        part:SetPoint("BOTTOM", f, "BOTTOM", x + w / 2, 14)
        part:Show()
        x = x + w + FOOTER_GAP
    end
end

function settings.show()
    ensure()
    sinceRefresh = 0
    frame:Show()
end

function settings.hide()
    if frame then frame:Hide() end
end

function settings.frame()
    return frame
end
