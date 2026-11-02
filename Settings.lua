-- Settings.lua: the My settings window (spec 2026-10-30-words-and-menu-design.md section 3.4). A pure model and a thin
-- frame adapter, in the same shape as Guide.lua and Results.lua. Loaded after UI.lua.
local _, ns = ...

local settings = {}
ns.settings = settings

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar

local FRAME_NAME = "ForeverSettingsSettings"
local WIDTH, HEIGHT = 780, 560
local REFRESH = 0.5            -- seconds of frame time between looks at what changed outside the window
local NONE_TEXT = "None of these settings are in this client."

local INTRO = "Choose how the game looks. Settings you tick are kept: the addon puts them back at every loading screen."
local ORIGINAL_NOTE = "You're using your Original settings (hands off). Switch to Everyday or Crowded in the menu to turn these on."
local MAXIMUM_NOTE = "You're using Maximum (everything at its highest). It includes the sharpest textures, which need plenty of "
    .. "graphics memory. Switch to Everyday or Crowded in the menu to change these."
local COST_NONE = "Run Find my best settings to see what each level costs."
local MATTERS_NOTE = [["Matters to the picture" is the addon's own judgement, not something it measured.]]
local NOTHING_TEXT = "Maximum has nothing to set yet: run Find my best settings once so the addon learns what each setting can do."
local USE_TEXT = "Use what I have in the game now"
local MAXIMUM_TEXT = "Switch to Maximum"
local SIZE_MIN, SIZE_MAX, SIZE_STEP = 50, 200, 5          -- percent: the picture sharpness slider (this session only)
local SIZE_SLIDER_WIDTH, SIZE_BACK_WIDTH = 360, 140      -- pixels: the slider and its Back to normal button
local SIZE_NOTE = "Not saved: the game goes back to your normal setting when you log out."
local SIZE_WARNING = "Above 100% the game draws more pixels than your screen has. That can cost a lot of frame rate and graphics memory, "
    .. "and some graphics cards crash at high values."
local DYNAMIC_OFF = "Dynamic render scale is off."
local DYNAMIC_ON = "Dynamic render scale is on. It changes the picture size by itself, which spoils a test. Turn it off in the game's graphics menu."
local YOUR_TAIL = " (an estimate; settings affect each other)."
local NOT_COUNTED = "the test didn't measure the level you chose."
local LOCKED_TEXT = {
    combat = "You are in combat; try again afterwards.",
    busy = "A test is running; try again afterwards.",
}
local TABS = { "everyday", "crowded" }
local TAB_TEXT = { everyday = "Everyday", crowded = "Crowded" }

-- The pages of the window (spec 2026-11-02-flat-hub-window-design.md H5) and the page each setting sits on; a setting this
-- table does not know sits on World detail.
settings.PAGES = {
    { key = "home", text = "Home" }, { key = "light", text = "Light and shadows" }, { key = "world", text = "World detail" },
    { key = "size", text = "Picture size" }, { key = "tests", text = "Tests and results" }, { key = "about", text = "About" },
}
local PAGE_KEYS = {}
for _, page in ipairs(settings.PAGES) do PAGE_KEYS[page.key] = true end
settings.PAGE_OF = {
    graphicsshadowquality = "light", graphicsssao = "light", graphicscomputeeffects = "light", giquality = "light",
    graphicslightmode = "light", graphicsgroundclutter = "world", groundeffectdensity = "world", graphicsliquiddetail = "world",
    graphicstextureresolution = "world", renderscale = "size",
}

local state = { tab = "everyday", page = "home" }

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

-- Columns of cards on a settings page: two, three above six cards (spec H7).
function settings.columnsFor(count)
    return count > 6 and 3 or 2
end

-- "Picture sharpness right now: 150%".
function settings.sizeLabel(percent)
    return "Picture sharpness right now: " .. percent .. "%"
end

-- What the window shows, with no frames (spec 3.4 and 2026-10-30-maximum-and-costs-design.md section 3.2).
-- state = {tab, notice}; ctx = {active, saved = {everyday, crowded}, live(cvar), resolved, locked = nil | "combat" | "busy",
-- costs = {kind = "quiet" | "crowd", measuredLine, fps = recommend.levelFps(entry)}, maximum = {fps, skipped, leftOut},
-- estimate = {fps, counted, notCounted}}; the last three are missing when no test can be read.
function settings.model(st, ctx)
    local names = ns.names
    local locked = ctx.locked
    local view = { title = "My settings", intro = INTRO, tabs = {}, rows = {}, buttons = {} }
    view.page = PAGE_KEYS[st.page] and st.page or "home"
    view.pages = {}
    for _, page in ipairs(settings.PAGES) do
        view.pages[#view.pages + 1] = { key = page.key, text = page.text, selected = page.key == view.page, enabled = true }
    end
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
            levels = {}, enabled = locked == nil, page = settings.PAGE_OF[cvar:lower()] or "world" }
        local words = ranking[cvar] and names.matters(ranking[cvar].weight)
        if words then
            row.matters = "Matters to the picture: " .. words .. "."
            row.mattersWords = words
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
            local level = { value = value, text = names.level(cvar, value, position), short = names.level(cvar, value),
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
    -- The estimate for the levels this tab holds (live total, 2026-11-02): none without a test to read, and none for a tab that
    -- holds no level the test measured, where it would only repeat today's frame rate.
    local est = ctx.estimate
    if costs and est and type(est.fps) == "number" and (est.counted or 0) > 0 then
        view.yourLine = string.format("Your %s settings: about %.0f fps", TAB_TEXT[st.tab] or "", est.fps) .. YOUR_TAIL
        if (est.notCounted or 0) > 0 then
            view.yourLine = view.yourLine .. " " .. plural(est.notCounted, "setting") .. " not counted: " .. NOT_COUNTED
        end
    end
    -- The picture sharpness block (spec 2026-11-02-picture-sharpness-slider-design.md); ctx.size = {percent, boosted, before}.
    local size = ctx.size
    if size then
        local label = settings.sizeLabel(size.percent)
        if size.boosted and size.before then label = label .. " (normal: " .. size.before .. "%)" end
        view.size = { percent = size.percent, value = math.max(SIZE_MIN, math.min(SIZE_MAX, size.percent)), min = SIZE_MIN,
            max = SIZE_MAX, step = SIZE_STEP, label = label, note = SIZE_NOTE,
            warning = size.percent > 100 and SIZE_WARNING or nil, enabled = locked == nil,
            canPutBack = (size.boosted and locked == nil) and true or false }
    end
    -- Whether the game's dynamic render scale is on (it resizes the picture by itself and spoils a test); nil when the client lacks it.
    if ctx.dynamicScale then view.dynamicLine = ctx.dynamicScale.on and DYNAMIC_ON or DYNAMIC_OFF end
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

-- The levels a tab holds, for the live total: the game's own values on the tab in use, the saved ones on the other.
local function heldValues(tab)
    local values = {}
    local db = ns.profiles and ns.profiles.state()
    if not db then return values end
    local live = db.active == tab
    for _, entry in ipairs(ns.bench and ns.bench.resolve() or {}) do
        local value
        if live then value = GetCVar(entry.cvar) else value = db.profiles[tab].values[entry.cvar] end
        if value ~= nil then values[entry.cvar] = value end
    end
    return values
end

-- ctx.costs, ctx.maximum and ctx.estimate for a tab: what each level costs against the test, what everything at the highest
-- would give ({fps, skipped, leftOut}: fps only when the test measured the highest level of every setting Maximum would set),
-- and what the levels the tab holds would give ({fps, counted, notCounted}). A test the recommender cannot read is no test:
-- the window must still draw, with or without the last.
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
    local held, heldCount = heldValues(tab), 0
    for _ in pairs(held) do heldCount = heldCount + 1 end
    local okHeld, yours = pcall(ns.recommend.estimateFps, source.entry, held)
    local mine
    if okHeld and yours then mine = { fps = yours.fps, counted = heldCount - #yours.missing, notCounted = #yours.missing } end
    return { kind = source.kind, measuredLine = source.measuredLine, fps = fps }, maximum, mine
end

-- The picture sharpness now and whether a session-only change holds it, for the slider; nil when the client has no such setting.
local function sizeContext()
    local live = tonumber(GetCVar("RenderScale"))
    if live == nil then return nil end
    local boost = ns.profiles and ns.profiles.boosted and ns.profiles.boosted()
    local before = boost and tonumber(boost.before)
    return { percent = math.floor(live * 100 + 0.5), boosted = boost ~= nil and boost ~= false,
        before = before and math.floor(before * 100 + 0.5) or nil }
end

-- Whether the game's dynamic render scale (CVar dynamicRenderScale) is on, for the Picture size page; nil when the client lacks it.
local function dynamicContext()
    local raw = GetCVar("dynamicRenderScale")
    if raw == nil then return nil end
    local n = tonumber(raw)
    return { on = n ~= nil and n ~= 0 }
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
        resolved = ns.bench and ns.bench.resolve() or {}, locked = lockReason(), size = sizeContext(),
        dynamicScale = dynamicContext(),
    }
    if withCosts then ctx.costs, ctx.maximum, ctx.estimate = costsAndMaximum(state.tab) end
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

-- Shows the window on a page (the page last shown when none is given, Home the first time). `everyday` or `crowded` picks that
-- tab and the first settings page; anything else shows the tab of the profile in use.
function settings.open(which)
    if which == "everyday" or which == "crowded" then
        state.tab = which
        state.page = "light"
    else
        state.tab = defaultTab()
        if PAGE_KEYS[which] then state.page = which end
    end
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
    local pageKey = key:match("^page:(.+)$")
    if pageKey then                          -- turning a page is not a change: it works in combat and during a test
        if PAGE_KEYS[pageKey] then
            state.page = pageKey
            draw()
        end
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
    -- The picture sharpness slider (this session only): size:<percent> when the mouse button is let go, sizeback.
    local percent = key:match("^size:(%d+)$")
    if percent then
        local ok, info = ns.profiles.boost(tonumber(percent) / 100, true)
        if ok and info.refused then
            state.notice = "The game kept picture sharpness at " .. string.format("%.0f%%", tonumber(info.held) * 100)
                .. " (you asked for " .. percent .. "%)."
        end
        draw()
        return
    end
    if key == "sizeback" then
        ns.profiles.unboost(true)
        draw()
        return
    end
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
-- Drawn from the flat widgets of Skin.lua (spec 2026-11-02-flat-hub-window-design.md): a header, the page list at the left, the
-- page area, and a footer strip. Nothing scrolls.

local skin = ns.skin
local frame, parts
local sinceRefresh = 0
local lastSignature

local NAV_WIDTH, PAD, TOP, TITLE_H, FOOTER_H = 150, 16, 8, 26, 44
local AREA_X = NAV_WIDTH + 1 + PAD                 -- where the page area starts inside the page frame
local AREA_W = WIDTH - 2 - AREA_X - PAD
local PAGE_H = HEIGHT - 38                         -- the page frame: under the 36 pixel header, inside the 1 pixel border
local CARD_GAP_X, CARD_GAP_Y = 18, 6
local LEVEL_W, LEVEL_H, LEVEL_GAP, COST_H = 36, 22, 3, 14
local FOOTER_USE_W, FOOTER_MAX_W, FOOTER_BTN_H = 230, 160, 26
local SUMMARY_GAP = 6
local TAB_W = 120
local SETTINGS_PAGE = { light = true, world = true, size = true }
local PLACEHOLDER = "This page is coming in the next step."

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

local function versionText()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    local version = get and get("ForeverSettings", "Version")
    if type(version) == "string" and version ~= "" then return "Version " .. version end
    return ""
end

-- The words of a level button that the button is too small for ("(lowest)" and "(highest)") show in a tooltip.
local function showTip(self)
    if GameTooltip and self.tip then
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tip)
        GameTooltip:Show()
    end
end
local function hideTip()
    if GameTooltip then GameTooltip:Hide() end
end

-- The picture sharpness slider: dragging moves the label, letting go applies the size (rebuilding the game's render targets at
-- every step of a drag would stutter), and a change made in code never applies anything (only the release does).
local function roundToStep(value)
    local stepped = math.floor((tonumber(value) or SIZE_MIN) / SIZE_STEP + 0.5) * SIZE_STEP
    return math.max(SIZE_MIN, math.min(SIZE_MAX, stepped))
end

local function makeSlider(parent, p)
    local slider = skin.slider(parent, FRAME_NAME .. "Size", SIZE_SLIDER_WIDTH, SIZE_MIN, SIZE_MAX, SIZE_STEP)
    slider.key = "size"
    slider:SetScript("OnValueChanged", function(_, value)
        p.sizeLabel:SetText(settings.sizeLabel(roundToStep(value)))        -- a draw sets the label right after moving the slider
    end)
    slider:SetScript("OnMouseUp", function(self)
        settings.click("size:" .. roundToStep(self:GetValue()))
    end)
    return slider
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
    local f = skin.window(FRAME_NAME, WIDTH, HEIGHT, "ForeverSettings")
    local page = f.page
    local p = {}
    f.close.key = "close"
    f.versionText:SetText(versionText())

    -- The page list at the left, with a rule between it and the page area.
    p.nav = {}
    for i, entry in ipairs(settings.PAGES) do
        local item = skin.navItem(page, entry.text, NAV_WIDTH, 28)
        item.key = "page:" .. entry.key
        item:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(10 + (i - 1) * 30 + (i > 4 and 14 or 0)))
        item:SetScript("OnClick", clicked)
        p.nav[i] = item
    end
    local rule = page:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(skin.color("divider"))
    rule:SetWidth(1)
    rule:SetPoint("TOPLEFT", page, "TOPLEFT", NAV_WIDTH, 0)
    rule:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", NAV_WIDTH, 0)

    -- The page area: the title, the Everyday/Crowded switch, the banner, the cards.
    local area = CreateFrame("Frame", nil, page)
    area:SetPoint("TOPLEFT", page, "TOPLEFT", AREA_X, -TOP)
    area:SetSize(AREA_W, PAGE_H - TOP - FOOTER_H)
    p.area = area
    p.title = skin.text(area, "large", "accent", AREA_W - 2 * TAB_W - 8)
    p.title:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -2)
    p.tabs = {}
    for i, key in ipairs(TABS) do
        local button = skin.button(area, TAB_TEXT[key], TAB_W, 24)
        button.key = "tab:" .. key
        button:SetScript("OnClick", clicked)
        button:SetPoint("TOPRIGHT", area, "TOPRIGHT", -(#TABS - i) * (TAB_W + 4), 0)
        p.tabs[i] = button
    end
    p.costNote = skin.text(area, "small", "dim", AREA_W)
    p.banner = skin.text(area, "small", "warning", AREA_W)
    p.note = skin.text(area, "normal", "dim", AREA_W)
    p.checks = newPool(area, function(parent)
        local box = skin.check(parent)
        box:SetScript("OnClick", clicked)
        return box
    end)
    p.names = newPool(area, function(parent) return skin.text(parent, "normal", "bright") end)
    p.matters = newPool(area, function(parent)
        local fs = skin.text(parent, "small", "dim")
        fs:SetJustifyH("RIGHT")
        return fs
    end)
    p.helps = newPool(area, function(parent) return skin.text(parent, "small", "dim") end)
    p.levels = newPool(area, function(parent)
        local button = skin.button(parent, "", LEVEL_W, LEVEL_H)
        button:SetScript("OnClick", clicked)
        local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
        button:SetScript("OnEnter", function(self) enter(self) showTip(self) end)
        button:SetScript("OnLeave", function(self) leave(self) hideTip() end)
        return button
    end)
    -- The second line under a level button: what that level costs against the level held.
    p.costs = newPool(area, function(parent)
        local fs = skin.text(parent, "small", "dim", LEVEL_W)
        fs:SetJustifyH("CENTER")
        return fs
    end)

    -- The picture sharpness block of the Picture size page.
    p.sizeLabel = skin.text(area, "normal", "bright", AREA_W)
    p.sizeSlider = makeSlider(area, p)
    p.sizeBack = skin.button(area, "Back to normal", SIZE_BACK_WIDTH, 24)
    p.sizeBack.key = "sizeback"
    p.sizeBack:SetScript("OnClick", clicked)
    p.sizeWarn = skin.text(area, "small", "warning", AREA_W)
    p.sizeNote = skin.text(area, "small", "dim", AREA_W)
    p.dynamicLine = skin.text(area, "small", "dim", AREA_W)

    -- The summary block above the footer, and the footer strip.
    p.your = skin.text(page, "small", "text", AREA_W)
    p.total = skin.text(page, "small", "text", AREA_W)
    p.mattersNote = skin.text(page, "small", "dim", AREA_W)
    p.footerRule = skin.divider(page)
    p.footerRule:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", NAV_WIDTH + 1, FOOTER_H)
    p.footerRule:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, FOOTER_H)
    p.use = skin.button(page, USE_TEXT, FOOTER_USE_W, FOOTER_BTN_H)
    p.use.key = "use"
    p.use:SetScript("OnClick", clicked)
    p.maximum = skin.button(page, MAXIMUM_TEXT, FOOTER_MAX_W, FOOTER_BTN_H)
    p.maximum.key = "maximum"
    p.maximum:SetScript("OnClick", clicked)

    f:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh < REFRESH then return end
        sinceRefresh = 0
        if signature(context()) ~= lastSignature then draw() end
    end)
    frame, parts = f, p
    return f
end

local function ensure()
    return frame or build()
end

-- Draws the model: the page list, the page's title and switch, the banner, then the page: cards for a settings page, the size
-- block on the Picture size page, the summary block and the footer.
function settings.render()
    local f = ensure()
    local p = parts
    local ctx = context(true)
    local view = settings.model(state, ctx)
    state.notice = nil                       -- a refusal is shown once: until the next click or redraw
    lastSignature = signature(ctx)
    local onSettings = SETTINGS_PAGE[view.page] == true

    local title = ""
    for i, entry in ipairs(view.pages) do
        p.nav[i]:SetSelected(entry.selected)
        p.nav[i]:SetEnabled(entry.enabled)
        if entry.selected then title = entry.text end
    end
    p.title:SetText(title)
    for i, tab in ipairs(view.tabs) do
        local button = p.tabs[i]
        button:SetLabel(tab.text)
        button:SetSelected(tab.selected)
        button:SetEnabled(tab.enabled)
        if onSettings then button:Show() else button:Hide() end
    end

    local y = TITLE_H
    local function placeText(fs, str, x)
        fs:SetText(str)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", p.area, "TOPLEFT", x or 0, -y)
        fs:Show()
        y = y + heightOf(fs, str) + 6
    end
    local function hideText(fs)
        fs:SetText("")
        fs:Hide()
    end
    -- Which test the costs come from (or that there is none), under the title of a settings page.
    if onSettings then placeText(p.costNote, view.costNote) else hideText(p.costNote) end
    local notices = {}
    if view.notice then notices[#notices + 1] = view.notice end
    if view.locked then notices[#notices + 1] = view.locked end
    if view.refusal then notices[#notices + 1] = view.refusal end
    if #notices > 0 then placeText(p.banner, table.concat(notices, "\n")) else hideText(p.banner) end

    -- One card per setting of the page: the tick, the name, how much it matters, the help, the small level buttons with their costs.
    local function placeCard(row, x, top, cardW, perRow)
        local box = take(p.checks)
        box.key = "keep:" .. row.cvar
        box:SetChecked(row.kept)
        box:SetEnabled(row.enabled)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", p.area, "TOPLEFT", x, -(top + 1))
        local name = take(p.names)
        name:SetText(row.name)
        name:SetWidth(cardW - 22 - 100)
        name:ClearAllPoints()
        name:SetPoint("TOPLEFT", p.area, "TOPLEFT", x + 22, -top)
        if row.mattersWords then
            local worth = take(p.matters)
            worth:SetText("matters: " .. row.mattersWords)
            worth:SetWidth(96)
            worth:ClearAllPoints()
            worth:SetPoint("TOPRIGHT", p.area, "TOPLEFT", x + cardW, -(top + 2))
        end
        local helpText = row.line or ""
        local help = take(p.helps)
        help:SetText(helpText)
        help:SetWidth(cardW)
        help:ClearAllPoints()
        help:SetPoint("TOPLEFT", p.area, "TOPLEFT", x, -(top + 18))
        local helpH = helpText == "" and 0 or heightOf(help, helpText)
        local levelsTop = top + 18 + helpH + 4
        local lineH = LEVEL_H + COST_H + 2
        for i, level in ipairs(row.levels) do
            local button = take(p.levels)
            button.key = "level:" .. row.cvar .. ":" .. level.value
            button.tip = level.text
            button:SetLabel(level.short or level.text)
            button:SetSelected(level.selected)
            button:SetEnabled(row.enabled)
            local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
            local bx, by = x + col * (LEVEL_W + LEVEL_GAP), levelsTop + line * lineH
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", p.area, "TOPLEFT", bx, -by)
            if level.cost then
                local cost = take(p.costs)
                cost:SetText(level.cost)
                cost:SetTextColor(skin.color(level.cost == "now" and "accentLight" or "dim"))
                cost:ClearAllPoints()
                cost:SetPoint("TOPLEFT", p.area, "TOPLEFT", bx, -(by + LEVEL_H + 2))
            end
        end
        return (levelsTop - top) + math.ceil(#row.levels / perRow) * lineH
    end

    local rows = {}
    if onSettings then
        for _, row in ipairs(view.rows) do
            if row.page == view.page then rows[#rows + 1] = row end
        end
    end
    if not onSettings then
        placeText(p.note, PLACEHOLDER)
    elseif #rows == 0 then
        placeText(p.note, NONE_TEXT)
    else
        hideText(p.note)
        local columns = settings.columnsFor(#rows)
        local cardW = math.floor((AREA_W - (columns - 1) * CARD_GAP_X) / columns)
        local perRow = math.max(1, math.floor((cardW + LEVEL_GAP) / (LEVEL_W + LEVEL_GAP)))
        local i = 1
        while i <= #rows do
            local rowH = 0
            for c = 0, columns - 1 do
                local row = rows[i + c]
                if row then
                    local h = placeCard(row, c * (cardW + CARD_GAP_X), y, cardW, perRow)
                    if h > rowH then rowH = h end
                end
            end
            y = y + rowH + CARD_GAP_Y
            i = i + columns
        end
    end
    release(p.checks)
    release(p.names, true)
    release(p.matters, true)
    release(p.helps, true)
    release(p.levels)
    release(p.costs, true)

    -- The picture sharpness block, under the card of the Picture size page.
    local size = view.size
    if view.page == "size" and size then
        y = y + 6
        p.sizeSlider:SetValue(size.value)             -- moving the slider in code rewrites the label: set the label after it
        placeText(p.sizeLabel, size.label)
        p.sizeSlider:ClearAllPoints()
        p.sizeSlider:SetPoint("TOPLEFT", p.area, "TOPLEFT", 6, -y)
        if p.sizeSlider.SetEnabled then p.sizeSlider:SetEnabled(size.enabled) end
        p.sizeSlider:Show()
        p.sizeBack:ClearAllPoints()
        p.sizeBack:SetPoint("TOPLEFT", p.area, "TOPLEFT", 6 + SIZE_SLIDER_WIDTH + 20, -(y - 4))
        p.sizeBack:SetEnabled(size.canPutBack)
        p.sizeBack:Show()
        y = y + 16 + 12
        if size.warning then placeText(p.sizeWarn, size.warning) else hideText(p.sizeWarn) end
        placeText(p.sizeNote, size.note)
    else
        p.sizeSlider:Hide()
        p.sizeBack:Hide()
        hideText(p.sizeLabel)
        hideText(p.sizeWarn)
        hideText(p.sizeNote)
    end
    if view.page == "size" and view.dynamicLine then
        p.dynamicLine:SetTextColor(skin.color(ctx.dynamicScale.on and "warning" or "dim"))
        placeText(p.dynamicLine, view.dynamicLine)
    else
        hideText(p.dynamicLine)
    end

    -- The summary block, stacked up from the footer: the matters note, the total, then the line on this tab's levels.
    local bottom = FOOTER_H + SUMMARY_GAP
    local function stack(fs, str)
        if not (onSettings and str) then
            hideText(fs)
            return
        end
        fs:SetText(str)
        fs:ClearAllPoints()
        fs:SetPoint("BOTTOMLEFT", f.page, "BOTTOMLEFT", AREA_X, bottom)
        fs:Show()
        bottom = bottom + heightOf(fs, str) + 2
    end
    stack(p.mattersNote, view.mattersNote)
    stack(p.total, view.totalLine)
    stack(p.your, view.yourLine)

    -- The footer: Use what I have in the game now and Switch to Maximum, right-aligned.
    local hasMaximum = false
    for _, button in ipairs(view.buttons) do
        if button.key == "use" then
            p.use:SetLabel(button.text)
            p.use:SetEnabled(button.enabled)
        elseif button.key == "maximum" then
            hasMaximum = true
            p.maximum:SetLabel(button.text)
            p.maximum:SetEnabled(button.enabled)
        end
    end
    if onSettings then
        p.use:ClearAllPoints()
        p.maximum:ClearAllPoints()
        p.maximum:SetPoint("BOTTOMRIGHT", f.page, "BOTTOMRIGHT", -PAD, 9)
        p.use:SetPoint("BOTTOMRIGHT", f.page, "BOTTOMRIGHT", -(PAD + (hasMaximum and (FOOTER_MAX_W + 8) or 0)), 9)
        p.use:Show()
        if hasMaximum then p.maximum:Show() else p.maximum:Hide() end
        p.footerRule:Show()
    else
        p.use:Hide()
        p.maximum:Hide()
        p.footerRule:Hide()
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
