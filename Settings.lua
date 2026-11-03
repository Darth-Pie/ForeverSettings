-- Settings.lua: the My settings window (spec 2026-10-30-words-and-menu-design.md section 3.4). A pure model and a thin
-- frame adapter, in the same shape as Guide.lua and Results.lua. Loaded after UI.lua.
local _, ns = ...

local settings = {}
ns.settings = settings

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar

local FRAME_NAME = "ForeverSettingsSettings"
local WIDTH, HEIGHT = 860, 560
local REFRESH = 0.5            -- seconds of frame time between looks at what changed outside the window
local NONE_TEXT = "None of these settings are in this client."

local INTRO = "Choose how the game looks. Settings you tick are kept: the addon puts them back at every loading screen."
local MAXIMUM_NOTE = "You're using Maximum (everything at its highest). It includes the sharpest textures, which need plenty of "
    .. "graphics memory."
local READ_ONLY_TAIL = " can't be changed. To change settings, edit:"
local PROFILE_COLOR = { original = "profileOriginal", everyday = "profileEveryday", crowded = "profileCrowded", maximum = "profileMaximum" }
local COST_NONE = "Run Find my best settings to see what each level costs."
local MATTERS_NOTE = [["Matters to the picture" is the addon's own judgement, not something it measured.]]
local NOTHING_TEXT = "Maximum has nothing to set yet: run Find my best settings once so the addon learns what each setting can do."
local SIZE_MIN, SIZE_MAX, SIZE_STEP = 50, 200, 5          -- percent: the picture sharpness slider
local SIZE_SLIDER_WIDTH, SIZE_BACK_WIDTH = 360, 140      -- pixels: the slider and its Back to 100% button
local SIZE_EXTRA = { "1.25", "1.5", "1.75", "2" }          -- the sizes above 100% the size card offers, which the test never measures
local SIZE_SAFE = "If a size above 100% crashes the game when you enter the world, hold Shift while you enter: the addon then skips it for that session."
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
local SAVE_CAPTION = "Save the game's current settings as:"
local PROFILE_KEYS = { "original", "everyday", "crowded", "maximum" }
local TESTS_INTRO = "The test measures what each graphics setting costs on this PC. Run it in a quiet spot first, then in a busy place."
local ABOUT_LINES = {
    "ForeverSettings finds the graphics settings that fit your PC: it measures what each one costs, keeps the levels you choose in "
        .. "profiles, and puts them back at every loading screen.",
    "",
    "Chat commands",
    "/fset settings: open this window",
    "/fset profile everyday, crowded, maximum or original: switch profile",
    "/fset size 50 to 200, or off: set the picture sharpness and keep it",
    "/fset probe: ask the game which settings it has",
    "/fset reset: put back everything the addon changed",
    "",
    "It doesn't collect or send anything.",
    "Problems or ideas: open an issue on GitHub (Darth-Pie/ForeverSettings).",
}

-- The addon's version from its TOC, or "unknown".
local function addonVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    local version = get and get("ForeverSettings", "Version")
    if type(version) == "string" and version ~= "" then return version end
    return "unknown"
end

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

local state = { page = "home" }

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

-- Columns of cards on a settings page: two, three above six cards (spec H7). The Picture size page is one column: its card has ten size
-- buttons.
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
    local view = { title = "My settings", intro = INTRO, rows = {} }
    view.page = PAGE_KEYS[st.page] and st.page or "home"
    view.pages = {}
    for _, page in ipairs(settings.PAGES) do
        view.pages[#view.pages + 1] = { key = page.key, text = page.text, selected = page.key == view.page, enabled = true }
    end
    -- The settings pages edit the profile in use (spec 2026-11-02-edit-the-profile-in-use-design.md P1). Original and Maximum cannot
    -- be edited: their pages are read-only and offer Everyday and Crowded (P2). The header pill names the profile in use (P4).
    local editing = TAB_TEXT[ctx.active] and ctx.active or nil
    local labels = ns.profiles and ns.profiles.LABEL or {}
    view.profile = { key = ctx.active, text = labels[ctx.active] or tostring(ctx.active), color = PROFILE_COLOR[ctx.active] or "dim" }
    if not editing then
        view.readOnly = { text = view.profile.text .. READ_ONLY_TAIL, buttons = {} }
        for _, key in ipairs(TABS) do
            view.readOnly.buttons[#view.readOnly.buttons + 1] = { key = "edit:" .. key, text = TAB_TEXT[key], color = PROFILE_COLOR[key],
                enabled = locked == nil }
        end
    end
    local max = ctx.maximum
    if ctx.active == "maximum" then
        view.notice = MAXIMUM_NOTE
        if max and (max.leftOut or 0) > 0 then view.notice = view.notice .. " " .. leftOutSentence(max.leftOut) end
        if max and (max.pending or 0) > 0 then view.notice = view.notice .. " " .. pendingSentence(max.pending) end
    end
    if locked then view.locked = LOCKED_TEXT[locked] end
    view.refusal = st.notice
    -- The two save buttons at the bottom of the page list, on every page; `st.saved` is what the last click said, shown once.
    view.saveBar = { caption = SAVE_CAPTION, note = st.saved, buttons = {} }
    for _, key in ipairs(TABS) do
        view.saveBar.buttons[#view.saveBar.buttons + 1] = { key = "save:" .. key, text = "Save as " .. TAB_TEXT[key], enabled = locked == nil }
    end
    -- A test whose costs there is nothing to read from (a run that measured nothing) is no test here.
    local costs = ctx.costs
    if costs and not (costs.fps and next(costs.fps.byCvar or {}) ~= nil) then costs = nil end
    if costs then
        view.costNote = "Costs from your " .. (costs.kind == "crowd" and "crowd" or "quiet-spot") .. " test."
            .. (costs.measuredLine and (" " .. costs.measuredLine) or "")
    else
        view.costNote = COST_NONE
    end
    -- What the profile in use holds: its own values when it can be edited, else what the addon keeps for it (Maximum's levels; none
    -- for Original).
    local saved = editing and ((ctx.saved or {})[editing] or {}) or (ctx.want or {})
    local ranking = ns.recommend and ns.recommend.RANKING or {}
    for _, entry in ipairs(ordered(ctx.resolved)) do
        local cvar = entry.cvar
        local _, line = names.get(cvar)
        local row = { cvar = cvar, name = names.label(cvar, entry.label), line = line, kept = saved[cvar] ~= nil,
            levels = {}, enabled = locked == nil and editing ~= nil, page = settings.PAGE_OF[cvar:lower()] or "world" }
        local words = ranking[cvar] and names.matters(ranking[cvar].weight)
        if words then
            row.matters = "Matters to the picture: " .. words .. "."
            row.mattersWords = words
            view.mattersNote = MATTERS_NOTE
        end
        local chosen = ctx.live(cvar)
        -- Costs are measured against the level the game holds; a setting whose level the test did not measure shows none.
        local list = costs and costs.fps.byCvar[cvar]
        local heldFps = list and chosen ~= nil and fpsOf(list, chosen) or nil
        -- Picture sharpness also offers sizes above 100%: levels the test never measured (a copy: the test's own list stays as it is).
        local tiers = entry.tiers
        if cvar:lower() == "renderscale" then
            tiers = {}
            for _, value in ipairs(entry.tiers) do tiers[#tiers + 1] = value end
            for _, value in ipairs(SIZE_EXTRA) do tiers[#tiers + 1] = value end
        end
        for i, value in ipairs(tiers) do
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
    -- The estimate for the levels the profile in use holds (P8): none without a test to read, none for Original or Maximum, and none
    -- for a profile that holds no level the test measured, where it would only repeat today's frame rate.
    local est = ctx.estimate
    if editing and next(saved) ~= nil and costs and est and type(est.fps) == "number" and (est.counted or 0) > 0 then
        view.yourLine = string.format("Your %s settings: about %.0f fps", TAB_TEXT[editing], est.fps) .. YOUR_TAIL
        if (est.notCounted or 0) > 0 then
            view.yourLine = view.yourLine .. " " .. plural(est.notCounted, "setting") .. " not counted: " .. NOT_COUNTED
        end
    end
    -- The picture size block (spec 2026-11-02-one-saved-picture-size-design.md S1, S2 and the edit-the-profile-in-use spec P7): the
    -- slider shows the game's size, the same one the level buttons light; ctx.size = {live = the game's percent}.
    local size = ctx.size
    if size then
        local keptSize = saved.RenderScale
        local percent = size.live
        -- What the profile keeps can differ from what the game holds (a Shift session skips a saved size above 100%, the game may
        -- refuse a size): the note then says both, and the warning and Back to 100% follow the larger of the two.
        local keptPercent = keptSize ~= nil and tonumber(keptSize) and math.floor(tonumber(keptSize) * 100 + 0.5) or nil
        local differs = keptPercent ~= nil and keptPercent ~= percent
        local note
        if editing then
            local tab = TAB_TEXT[editing]
            if keptSize == nil then
                note = "Not kept in " .. tab .. " yet: drag the slider or click a size to keep it."
            elseif differs then
                note = "Kept in " .. tab .. " at " .. keptPercent .. "%: the game has " .. percent .. "% now."
            else
                note = "Kept in " .. tab .. ": the addon puts it back at every loading screen."
            end
        end
        local risky = percent > 100 or (keptPercent ~= nil and keptPercent > 100)
        view.size = { percent = percent, value = math.max(SIZE_MIN, math.min(SIZE_MAX, percent)), min = SIZE_MIN, max = SIZE_MAX,
            step = SIZE_STEP, label = settings.sizeLabel(percent), note = note, warning = risky and SIZE_WARNING or nil,
            safe = risky and SIZE_SAFE or nil, enabled = locked == nil and editing ~= nil,
            canPutBack = editing ~= nil and (percent ~= 100 or differs) and locked == nil }
    end
    -- Whether the game's dynamic render scale is on (it resizes the picture by itself and spoils a test); nil when the client lacks it.
    if ctx.dynamicScale then view.dynamicLine = ctx.dynamicScale.on and DYNAMIC_ON or DYNAMIC_OFF end
    -- The Home page: the profile in use, the four profile cards, the two test buttons. ctx.home = the minimap menu's facts
    -- ({saved = {best, crowded}, maxFps}); missing when the interface module is not there.
    local home = ctx.home or {}
    view.home = { inUse = labels[ctx.active] or tostring(ctx.active), profiles = {}, tests = {} }
    for _, key in ipairs(PROFILE_KEYS) do
        local full = (names.PROFILE and names.PROFILE[key]) or key
        local title, note = full:match("^([^:]+):%s*(.+)$")
        title, note = title or full, note or ""
        if key == "maximum" and type(home.maxFps) == "number" then note = note .. string.format(" (about %.0f fps)", home.maxFps) end
        view.home.profiles[#view.home.profiles + 1] = { key = key, title = title, note = note, selected = ctx.active == key,
            enabled = locked == nil, color = PROFILE_COLOR[key] }
    end
    -- The Tests and results page: a line for each saved result with a Show results button, and the progress of a running test.
    local tests = ctx.tests or {}
    view.testsPage = { intro = TESTS_INTRO, results = {}, progress = tests.progress }
    for _, kind in ipairs({ "best", "crowded" }) do
        local label = kind == "best" and "Quiet-spot test" or "Crowd test"
        local saved = tests.results and tests.results[kind]
        view.testsPage.results[#view.testsPage.results + 1] = { kind = kind, label = label, canShow = saved ~= nil,
            text = label .. ": " .. (saved and saved.line or "not done yet.") }
    end
    view.about = { version = addonVersion(), lines = ABOUT_LINES }
    local saved = home.saved or {}
    view.home.tests = {
        { key = "best", text = "Find my best settings", enabled = locked == nil, done = saved.best == true },
        { key = "crowded", text = "Find my crowded settings", enabled = locked == nil, done = saved.crowded == true },
    }
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

-- The levels the game holds now, for the live total of the profile in use (the pages edit only that one: spec
-- 2026-11-02-edit-the-profile-in-use-design.md P8).
local function heldValues()
    local values = {}
    for _, entry in ipairs(ns.bench and ns.bench.resolve() or {}) do
        local value = GetCVar(entry.cvar)
        if value ~= nil then values[entry.cvar] = value end
    end
    return values
end

-- ctx.costs, ctx.maximum and ctx.estimate for a profile: what each level costs against the test, what everything at the highest
-- would give ({fps, skipped, leftOut}: fps only when the test measured the highest level of every setting Maximum would set),
-- and what the levels the profile holds would give ({fps, counted, notCounted}). A test the recommender cannot read is no test:
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
    local held, heldCount = heldValues(), 0
    for _ in pairs(held) do heldCount = heldCount + 1 end
    local okHeld, yours = pcall(ns.recommend.estimateFps, source.entry, held)
    local mine
    if okHeld and yours then mine = { fps = yours.fps, counted = heldCount - #yours.missing, notCounted = #yours.missing } end
    return { kind = source.kind, measuredLine = source.measuredLine, fps = fps }, maximum, mine
end

-- The game's picture sharpness now, in percent, for the slider; nil when the client has no such setting.
local function sizeContext()
    local live = tonumber(GetCVar("RenderScale"))
    if live == nil then return nil end
    return { live = math.floor(live * 100 + 0.5) }
end

-- Whether the game's dynamic render scale (CVar dynamicRenderScale) is on, for the Picture size page; nil when the client lacks it.
local function dynamicContext()
    local raw = GetCVar("dynamicRenderScale")
    if raw == nil then return nil end
    local n = tonumber(raw)
    return { on = n ~= nil and n ~= 0 }
end

-- The minimap menu's facts for the Home page ({saved = {best, crowded}, maxFps, ...}); nil when the interface module is missing.
local function homeContext()
    if not (ns.ui and ns.ui.buildContext) then return nil end
    local ok, home = pcall(ns.ui.buildContext)
    return ok and home or nil
end

-- The saved results and the progress of a running test, for the Tests and results page: {results = {best = {line}, crowded = {line}},
-- progress = "A test is running: step N of M (...)"}. Whatever cannot be read is left out.
local function testsContext(home)
    local info = { results = {} }
    if ns.ui and ns.ui.savedResult then
        for _, kind in ipairs({ "best", "crowded" }) do
            local ok, saved = pcall(ns.ui.savedResult, kind)
            if ok and saved then info.results[kind] = { line = saved.measuredLine or "" } end
        end
    end
    local progress = home and home.progress
    if progress then
        info.progress = string.format("A test is running: step %d of %d (%s)", progress.done, progress.total,
            ns.names and ns.names.progress(progress) or tostring(progress.label))
    end
    return info
end

-- The live facts the model needs; the costs only for a draw (they are not part of what the refresh looks at).
local function context(withCosts)
    local db = ns.profiles and ns.profiles.state()
    local saved = { everyday = {}, crowded = {} }
    if db then
        for _, key in ipairs(TABS) do saved[key] = db.profiles[key].values end
    end
    local ctx = {
        active = db and db.active or "original", saved = saved, want = db and db.want or {}, live = function(cvar) return GetCVar(cvar) end,
        resolved = ns.bench and ns.bench.resolve() or {}, locked = lockReason(), size = sizeContext(),
        dynamicScale = dynamicContext(),
    }
    if withCosts then
        -- The costs of the profile in use (Crowded prefers the crowd test); Original and Maximum read the quiet-spot test.
        ctx.costs, ctx.maximum, ctx.estimate = costsAndMaximum(TAB_TEXT[ctx.active] and ctx.active or "everyday")
        ctx.home = homeContext()
        ctx.tests = testsContext(ctx.home)
    end
    return ctx
end

local function draw()
    guarded(settings.render)
end

function settings.state()
    return state
end

-- Switches to a profile from the window, silently: a refusal Maximum gives, or a level the game would not take, shows in the banner.
local REFUSED_WORDS = { maximum = "the highest level", original = "the level you had", everyday = "the level you saved",
    crowded = "the level you saved" }
local function switchProfile(name)
    local ok, info = ns.profiles.switch(name, true)
    if not ok and info == "nothing" then
        state.notice = NOTHING_TEXT
    elseif ok then
        -- The switch stands, but a level the game would not take is said here, since nothing is said in chat; so is a profile
        -- that holds nothing yet.
        local refused = refusedNames(info.mismatched)
        if #refused > 0 then
            state.notice = "The game would not take " .. (REFUSED_WORDS[name] or "the level") .. " for: " .. table.concat(refused, ", ") .. "."
        elseif (name == "everyday" or name == "crowded") and ns.profiles.hasValues and not ns.profiles.hasValues(name) then
            state.notice = TAB_TEXT[name] .. " has no saved settings yet: pick some on the settings pages."
        end
    end
    draw()
end

-- Shows the window on a page (the page last shown when none is given, Home the first time); `everyday` or `crowded` opens the first
-- settings page, which edits the profile in use.
function settings.open(which)
    if which == "everyday" or which == "crowded" then
        state.page = "light"
    elseif PAGE_KEYS[which] then
        state.page = which
    end
    guarded(function()
        settings.render()
        settings.show()
    end)
end

-- Keeps a picture size in the profile in use exactly as a level button does, and applies it at once; Original and Maximum cannot be
-- edited. When the game keeps another size, the window says so.
local function saveSize(percent)
    if percent < SIZE_MIN or percent > SIZE_MAX then return end
    local profile = ns.profiles.active()
    if not TAB_TEXT[profile] then return end
    local value = string.format("%.4g", percent / 100)
    local ok = ns.profiles.setProfileValue(profile, "RenderScale", value, true)
    if ok then
        local held = GetCVar("RenderScale")
        if held ~= nil and not sameValue(held, value) then
            state.notice = "The game kept picture sharpness at " .. string.format("%.0f%%", tonumber(held) * 100)
                .. " (you asked for " .. percent .. "%)."
        end
    end
    draw()
end

-- Which settings a save replaced, in words: "Picture sharpness was 150%, now 100%; ...", at most three and then "and N more", or ""
-- when the profile held nothing that differs (what it held before, what it holds now).
local function replacedText(before, after)
    local lines = {}
    for _, cvar in ipairs(ns.profiles.MANAGED) do
        local was, now = before[cvar], after[cvar]
        if was ~= nil and now ~= nil and not sameValue(was, now) then
            lines[#lines + 1] = ns.names.label(cvar, cvar) .. " was " .. ns.names.level(cvar, was) .. ", now " .. ns.names.level(cvar, now)
        end
    end
    if #lines == 0 then return "" end
    local shown = {}
    for i = 1, math.min(3, #lines) do shown[i] = lines[i] end
    local text = table.concat(shown, "; ")
    if #lines > 3 then text = text .. "; and " .. (#lines - 3) .. " more" end
    return text .. "."
end

-- Save as Everyday / Save as Crowded: keeps the game's current settings in a profile, and says what that replaced (a profile not
-- in use can hold values the game does not have).
local function keepCurrent(name)
    local db = ns.profiles.state()
    local before = {}
    for cvar, value in pairs(db and db.profiles[name] and db.profiles[name].values or {}) do before[cvar] = value end
    local count = ns.profiles.save(name, true)
    if count then
        local text = "Saved " .. plural(count, "setting") .. " as " .. TAB_TEXT[name] .. "."
        local replaced = replacedText(before, db.profiles[name].values)
        if replaced ~= "" then text = text .. " " .. replaced end
        state.saved = text
    end
    draw()
end

-- A button or tick of the window, by the keys of the model: page:<page>, pill, profile:<name>, edit:<name>, keep:<cvar>,
-- level:<cvar>:<value>, size:<percent>, sizeback, save:<name>, test:<kind>, show:<kind>, close. A refusal is shown in the window
-- until the next click or redraw.
function settings.click(key)
    if key == "close" then
        settings.hide()
        return
    end
    local pageKey = key:match("^page:(.+)$")
    if key == "pill" then pageKey = "home" end      -- the profile pill opens Home, where the profile is switched
    if pageKey then                          -- turning a page is not a change: it works in combat and during a test
        if PAGE_KEYS[pageKey] then
            state.page = pageKey
            draw()
        end
        return
    end
    local ctx = context()
    if ctx.locked then
        -- a profile switch says why it was refused (the window may not have caught up with the lock yet)
        if key:find("^profile:") or key:find("^edit:") then draw() end
        return
    end
    if not ns.profiles then return end
    -- The picture size slider: size:<percent> when the mouse button is let go, and Back to 100%; both keep the size like a level button.
    local percent = key:match("^size:(%d+)$")
    if percent then
        saveSize(tonumber(percent))
        return
    end
    if key == "sizeback" then
        saveSize(100)
        return
    end
    -- The Home page: a profile card switches profile (as the minimap menu does), a test button opens the guided test or its saved result.
    local profileKey = key:match("^profile:(.+)$")
    if profileKey then
        switchProfile(profileKey)
        return
    end
    -- The read-only pages of Original and Maximum: Everyday or Crowded switches to that profile so it can be edited.
    local editKey = key:match("^edit:(.+)$")
    if editKey then
        if TAB_TEXT[editKey] then switchProfile(editKey) end
        return
    end
    -- The guided test and the results window are their own windows: this one steps aside so they do not sit on top of it.
    local testKey = key:match("^test:(.+)$")
    if testKey then
        if (testKey == "best" or testKey == "crowded") and ns.ui and ns.ui.openSaved then
            ns.ui.openSaved(testKey)
            settings.hide()
        end
        return
    end
    local showKey = key:match("^show:(.+)$")                -- Show results: only for a result that is saved
    if showKey then
        local info = testsContext(nil)
        if info.results[showKey] and ns.ui and ns.ui.openSaved then
            ns.ui.openSaved(showKey)
            settings.hide()
        end
        return
    end
    -- Save as Everyday / Save as Crowded: keeps the game's current settings in that profile, whatever page is showing.
    local saveKey = key:match("^save:(.+)$")
    if saveKey then                          -- Original, Maximum and a name that is no profile are refused by save, quietly
        keepCurrent(saveKey)
        return
    end
    -- Ticks and levels edit the profile in use; Original and Maximum cannot be edited.
    local profile = TAB_TEXT[ctx.active] and ctx.active or nil
    if not profile then return end
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
-- page area. Nothing scrolls.

local skin = ns.skin
local frame, parts
local sinceRefresh = 0
local lastSignature

local NAV_WIDTH, PAD, TOP, TITLE_H = 150, 16, 8, 26
local SUMMARY_BOTTOM = 12                          -- the summary block stands this far above the bottom of the page (no footer)
local AREA_X = NAV_WIDTH + 1 + PAD                 -- where the page area starts inside the page frame
local AREA_W = WIDTH - 2 - AREA_X - PAD
local PAGE_H = HEIGHT - 38                         -- the page frame: under the 36 pixel header, inside the 1 pixel border
local CARD_GAP_X, CARD_GAP_Y = 18, 6
local LEVEL_W, LEVEL_H, LEVEL_GAP, COST_H = 50, 22, 3, 14
local COST_W = LEVEL_W + 8                         -- the cost under a level button is a little wider than the button: "+136 fps"
local TEST_BTN_W, TEST_BTN_H = 230, 26             -- Find my best settings / Find my crowded settings (Home, Tests and results)
local PILL_W, PILL_H = 104, 22                     -- the profile pill in the header
local EDIT_W, EDIT_H = 112, 24                     -- Everyday and Crowded on a read-only page
local SAVE_X, SAVE_W, SAVE_H, SAVE_GAP = 12, NAV_WIDTH - 24, 28, 6       -- the save buttons at the bottom of the page list
local HOME_CARD_W, HOME_CARD_H = math.floor((AREA_W - CARD_GAP_X) / 2), 56
local HOME_TESTS_NOTE = "A highlighted button has a saved result."
local SETTINGS_PAGE = { light = true, world = true, size = true }

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
    local list = { tostring(ctx.active), tostring(ctx.locked) }
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
    local version = addonVersion()
    f.versionText:SetText(version == "unknown" and "" or "Version " .. version)

    -- The page list at the left, with a rule between it and the page area.
    p.nav = {}
    for i, entry in ipairs(settings.PAGES) do
        local item = skin.navItem(page, entry.text, NAV_WIDTH, 28)
        item.key = "page:" .. entry.key
        item:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(10 + (i - 1) * 30 + (i > 4 and 14 or 0)))
        item:SetScript("OnClick", clicked)
        p.nav[i] = item
    end
    -- Under the page list, the last thing in it: Save as Everyday over Save as Crowded, with a line above them (or, for one
    -- draw after a click, what was saved).
    p.saveButtons = {}
    for i, key in ipairs(TABS) do
        local button = skin.button(page, "Save as " .. TAB_TEXT[key], SAVE_W, SAVE_H)
        button.key = "save:" .. key
        button:SetScript("OnClick", clicked)
        button:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", SAVE_X, 12 + (#TABS - i) * (SAVE_H + SAVE_GAP))
        p.saveButtons[i] = button
    end
    local captionY = 12 + #TABS * (SAVE_H + SAVE_GAP)
    p.saveCaption = skin.text(page, "small", "dim", SAVE_W)
    p.saveCaption:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", SAVE_X, captionY)
    p.saveNote = skin.text(page, "small", "accentLight", SAVE_W)
    p.saveNote:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", SAVE_X, captionY)
    local rule = page:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(skin.color("divider"))
    rule:SetWidth(1)
    rule:SetPoint("TOPLEFT", page, "TOPLEFT", NAV_WIDTH, 0)
    rule:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", NAV_WIDTH, 0)

    -- The profile pill in the header, left of the close button: the dot and name of the profile in use; it opens Home.
    local pill = CreateFrame("Button", nil, f.header)
    pill:SetSize(PILL_W, PILL_H)
    pill:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    pill.box = skin.box(pill, skin.RADIUS.control, "fill", "control")
    pill.dot = skin.dot(pill, "dim")
    pill.dot:SetPoint("LEFT", pill, "LEFT", 10, 0)
    pill.label = skin.text(pill, "small", "bright", PILL_W - 28)
    pill.label:SetPoint("LEFT", pill, "LEFT", 24, 0)
    pill.key = "pill"
    pill:SetScript("OnClick", clicked)
    p.pill = pill

    -- The page area: the title, the banner, the read-only line of Original and Maximum, the cards.
    local area = CreateFrame("Frame", nil, page)
    area:SetPoint("TOPLEFT", page, "TOPLEFT", AREA_X, -TOP)
    area:SetSize(AREA_W, PAGE_H - TOP - SUMMARY_BOTTOM)
    p.area = area
    p.title = skin.text(area, "large", "accent", AREA_W)
    p.title:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -2)
    p.readOnly = skin.text(area, "normal", "accentLight", AREA_W)
    p.editButtons = {}
    for i, key in ipairs(TABS) do
        local button = skin.button(area, TAB_TEXT[key], EDIT_W, EDIT_H)
        button.key = "edit:" .. key
        button:SetScript("OnClick", clicked)
        button.dot = skin.dot(button, PROFILE_COLOR[key])
        button.dot:SetPoint("LEFT", button, "LEFT", 12, 0)
        p.editButtons[i] = button
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
        local fs = skin.text(parent, "small", "dim", COST_W)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)                 -- never wraps: a figure wider than its column would otherwise break onto a second line
        return fs
    end)

    -- The picture sharpness block of the Picture size page.
    p.sizeLabel = skin.text(area, "normal", "bright", AREA_W)
    p.sizeSlider = makeSlider(area, p)
    p.sizeBack = skin.button(area, "Back to 100%", SIZE_BACK_WIDTH, 24)
    p.sizeBack.key = "sizeback"
    p.sizeBack:SetScript("OnClick", clicked)
    p.sizeWarn = skin.text(area, "small", "warning", AREA_W)
    p.sizeSafe = skin.text(area, "small", "dim", AREA_W)
    p.sizeNote = skin.text(area, "small", "dim", AREA_W)
    p.dynamicLine = skin.text(area, "small", "dim", AREA_W)

    -- The Home page: the profile in use, four profile cards (title and note, centred), the two test buttons.
    p.inUse = skin.text(area, "normal", "bright", AREA_W)
    p.profileCards = {}
    for i = 1, #PROFILE_KEYS do
        local card = skin.button(area, "", HOME_CARD_W, HOME_CARD_H)
        card:SetScript("OnClick", clicked)
        card.label:ClearAllPoints()
        card.label:SetPoint("CENTER", card, "CENTER", 0, 10)
        card.note = skin.text(card, "small", "dim", HOME_CARD_W - 16)
        card.note:SetJustifyH("CENTER")
        card.note:SetPoint("CENTER", card, "CENTER", 0, -10)
        card.dot = skin.dot(card, "dim")                  -- the profile's colour, as on the header pill
        card.dot:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
        p.profileCards[i] = card
    end
    p.testButtons = {}
    for i, key in ipairs({ "best", "crowded" }) do
        local button = skin.button(area, "", TEST_BTN_W, TEST_BTN_H)
        button.key = "test:" .. key
        button:SetScript("OnClick", clicked)
        p.testButtons[i] = button
    end
    p.testsNote = skin.text(area, "small", "dim", AREA_W)

    -- The Tests and results page, and the About page.
    p.testsIntro = skin.text(area, "normal", "dim", AREA_W)
    p.resultLines, p.resultButtons = {}, {}
    for i = 1, 2 do
        p.resultLines[i] = skin.text(area, "normal", "text", AREA_W - 150)
        local show = skin.button(area, "Show results", 140, 24)
        show:SetScript("OnClick", clicked)
        p.resultButtons[i] = show
    end
    p.progressLine = skin.text(area, "normal", "accentLight", AREA_W)
    p.aboutVersion = skin.text(area, "normal", "bright", AREA_W)
    p.aboutText = skin.text(area, "normal", "text", AREA_W)

    -- The summary block at the bottom of the page.
    p.your = skin.text(page, "small", "text", AREA_W)
    p.total = skin.text(page, "small", "text", AREA_W)
    p.mattersNote = skin.text(page, "small", "dim", AREA_W)

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

-- Draws the model: the page list, the profile pill, the page's title, the banner and the read-only line, then the page: cards for
-- a settings page, the size block on the Picture size page, and the summary block.
function settings.render()
    local f = ensure()
    local p = parts
    local ctx = context(true)
    local view = settings.model(state, ctx)
    state.notice = nil                       -- a refusal is shown once: until the next click or redraw
    state.saved = nil                        -- so is what a save button said
    lastSignature = signature(ctx)
    local onSettings = SETTINGS_PAGE[view.page] == true

    local title = ""
    for i, entry in ipairs(view.pages) do
        p.nav[i]:SetSelected(entry.selected)
        p.nav[i]:SetEnabled(entry.enabled)
        if entry.selected then title = entry.text end
    end
    p.title:SetText(title)
    for i, spec in ipairs(view.saveBar.buttons) do p.saveButtons[i]:SetEnabled(spec.enabled) end
    if view.saveBar.note then
        p.saveNote:SetText(view.saveBar.note)
        p.saveNote:Show()
        p.saveCaption:Hide()
    else
        p.saveCaption:SetText(view.saveBar.caption)
        p.saveCaption:Show()
        p.saveNote:Hide()
    end
    p.pill.label:SetText(view.profile.text)
    p.pill.dot:SetColorName(view.profile.color)

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
    if onSettings or view.page == "home" then placeText(p.costNote, view.costNote) else hideText(p.costNote) end
    local notices = {}
    if view.notice then notices[#notices + 1] = view.notice end
    if view.locked then notices[#notices + 1] = view.locked end
    if view.refusal then notices[#notices + 1] = view.refusal end
    if #notices > 0 then placeText(p.banner, table.concat(notices, "\n")) else hideText(p.banner) end
    -- Original or Maximum in use: the settings pages are read-only and offer Everyday and Crowded.
    if onSettings and view.readOnly then
        placeText(p.readOnly, view.readOnly.text)
        for i, spec in ipairs(view.readOnly.buttons) do
            local button = p.editButtons[i]
            button:SetEnabled(spec.enabled)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", p.area, "TOPLEFT", (i - 1) * (EDIT_W + 8), -y)
            button:Show()
        end
        y = y + EDIT_H + 8
    else
        hideText(p.readOnly)
        for _, button in ipairs(p.editButtons) do button:Hide() end
    end

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
        local helpTop = top + math.max(18, heightOf(name, row.name) + 2)         -- a name that wraps pushes the help down
        local helpText = row.line or ""
        local help = take(p.helps)
        help:SetText(helpText)
        help:SetWidth(cardW)
        help:ClearAllPoints()
        help:SetPoint("TOPLEFT", p.area, "TOPLEFT", x, -helpTop)
        local helpH = helpText == "" and 0 or heightOf(help, helpText)
        local levelsTop = helpTop + helpH + 4
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
                cost:SetPoint("TOPLEFT", p.area, "TOPLEFT", bx - (COST_W - LEVEL_W) / 2, -(by + LEVEL_H + 2))
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
        hideText(p.note)
    elseif #rows == 0 then
        placeText(p.note, NONE_TEXT)
    else
        hideText(p.note)
        local columns = view.page == "size" and 1 or settings.columnsFor(#rows)
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

    -- The two test buttons (Home and the Tests and results page), in a row at the current height.
    local function placeTestButtons()
        for i, test in ipairs(view.home.tests) do
            local button = p.testButtons[i]
            button:SetLabel(test.text)
            button:SetSelected(test.done)
            button:SetEnabled(test.enabled)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", p.area, "TOPLEFT", (i - 1) * (TEST_BTN_W + 12), -y)
            button:Show()
        end
        y = y + TEST_BTN_H + 8
    end

    -- The Home page.
    if view.page == "home" then
        placeText(p.inUse, "In use now: " .. view.home.inUse)
        for i, profile in ipairs(view.home.profiles) do
            local card = p.profileCards[i]
            local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
            card.key = "profile:" .. profile.key
            card:SetLabel(profile.title)
            card.note:SetText(profile.note)
            card.dot:SetColorName(profile.color)
            card:SetSelected(profile.selected)
            card:SetEnabled(profile.enabled)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", p.area, "TOPLEFT", col * (HOME_CARD_W + CARD_GAP_X), -(y + line * (HOME_CARD_H + 8)))
            card:Show()
        end
        y = y + 2 * (HOME_CARD_H + 8) + 6
        placeTestButtons()
        placeText(p.testsNote, HOME_TESTS_NOTE)
    else
        hideText(p.inUse)
        hideText(p.testsNote)
        for _, card in ipairs(p.profileCards) do card:Hide() end
    end

    -- The Tests and results page: the two test buttons, a line and a Show results button for each result, the progress of a test.
    if view.page == "tests" then
        placeText(p.testsIntro, view.testsPage.intro)
        placeTestButtons()
        for i, result in ipairs(view.testsPage.results) do
            p.resultLines[i]:SetText(result.text)
            p.resultLines[i]:ClearAllPoints()
            p.resultLines[i]:SetPoint("TOPLEFT", p.area, "TOPLEFT", 0, -(y + 4))
            p.resultLines[i]:Show()
            local show = p.resultButtons[i]
            show.key = "show:" .. result.kind
            show:ClearAllPoints()
            show:SetPoint("TOPRIGHT", p.area, "TOPRIGHT", 0, -y)
            if result.canShow then show:Show() else show:Hide() end
            y = y + 30
        end
        if view.testsPage.progress then placeText(p.progressLine, view.testsPage.progress) else hideText(p.progressLine) end
    else
        hideText(p.testsIntro)
        hideText(p.progressLine)
        for i = 1, 2 do
            hideText(p.resultLines[i])
            p.resultButtons[i]:Hide()
        end
    end
    if view.page ~= "home" and view.page ~= "tests" then
        for _, button in ipairs(p.testButtons) do button:Hide() end
    end

    -- The About page.
    if view.page == "about" then
        placeText(p.aboutVersion, "Version " .. view.about.version)
        placeText(p.aboutText, table.concat(view.about.lines, "\n"))
    else
        hideText(p.aboutVersion)
        hideText(p.aboutText)
    end

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
        if size.safe then placeText(p.sizeSafe, size.safe) else hideText(p.sizeSafe) end
        if size.note then placeText(p.sizeNote, size.note) else hideText(p.sizeNote) end
    else
        p.sizeSlider:Hide()
        p.sizeBack:Hide()
        hideText(p.sizeLabel)
        hideText(p.sizeWarn)
        hideText(p.sizeSafe)
        hideText(p.sizeNote)
    end
    if view.page == "size" and view.dynamicLine then
        p.dynamicLine:SetTextColor(skin.color(ctx.dynamicScale.on and "warning" or "dim"))
        placeText(p.dynamicLine, view.dynamicLine)
    else
        hideText(p.dynamicLine)
    end

    -- The summary block, stacked up from the bottom of the page: the matters note, the total, then the line on the profile's levels.
    local bottom = SUMMARY_BOTTOM
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
