-- Shared stubs for the ForeverSettings tests. run.js loads this file as HARNESS_SRC; a test starts with
--   local H = assert(load(HARNESS_SRC, "=harness"))()
-- ADDON_SRC and BENCH_SRC hold the addon sources ("" when Bench.lua does not exist yet).
-- The tests run under Lua 5.3 (fengari) but the game runs Lua 5.1: addon code stays within 5.1.
local H = {}
local results = {}

function H.check(name, cond, detail)
    results[#results + 1] = (cond and "PASS " or "FAIL ") .. name .. (cond and "" or ("  -- " .. tostring(detail)))
end

function H.results() return table.concat(results, "\n") end

-- Runs fn under pcall; the test passes when fn returns true. An error is a FAIL carrying its message,
-- so a missing function shows as a named failure instead of aborting the whole file.
function H.test(name, fn)
    local ok, res, detail = pcall(fn)
    if ok and res == true then
        H.check(name, true)
    elseif ok then
        H.check(name, false, detail or "assertion false")
    else
        H.check(name, false, tostring(res))
    end
end

-- Frames and timers belong to one boot; the next boot starts with none.
local frames, timers, clock = {}, {}, 0

local function runTimers()
    local progressed = true
    while progressed do
        progressed = false
        for i, t in ipairs(timers) do
            if t.due <= clock then
                table.remove(timers, i)
                t.fn()
                progressed = true
                break
            end
        end
    end
end

local function tick(dt)
    clock = clock + dt
    runTimers()
end

local noLines = false       -- set by H.boot (opts.lines = false): a client whose frames have no CreateLine

local function makeFrame(kind, name, parent, template)
    local f = { kind = kind, name = name, parent = parent, template = template, events = {}, scripts = {}, shown = true,
        children = {}, fontStrings = {}, textures = {}, lines = {}, enabled = true, checked = false }
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    -- A line records its end points, thickness and colour, so a test can read what a graph would look like. A client
    -- without lines answers `false` here, so `type(frame.CreateLine) == "function"` is the test for them.
    if noLines then
        f.CreateLine = false
    else
        function f:CreateLine()
            local line = { kind = "Line", shown = true, parent = self }
            function line:SetStartPoint(...) self._start = { ... } end
            function line:SetEndPoint(...) self._end = { ... } end
            function line:SetThickness(t) self._thickness = t end
            function line:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
            function line:Show() self.shown = true end
            function line:Hide() self.shown = false end
            function line:IsShown() return self.shown end
            setmetatable(line, { __index = function(_, k)
                if type(k) == "string" and k:match("^%u") then return function() return H.noop end end
            end })
            self.lines[#self.lines + 1] = line
            return line
        end
    end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts[k] end
    -- Showing and hiding run OnShow and OnHide on a real change of state, after it, as the client does.
    function f:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function f:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:IsShown() return self.shown end
    function f:SetPoint(...) self._point = { ... } end
    function f:SetSize(w, h) self._width, self._height = w, h end
    function f:SetText(text) self._text = text end
    function f:GetText() return self._text end
    function f:SetEnabled(on) self.enabled = on and true or false end
    function f:IsEnabled() return self.enabled end
    function f:LockHighlight() self.locked = true end
    function f:UnlockHighlight() self.locked = false end
    function f:SetChecked(on) self.checked = on and true or false end
    function f:GetChecked() return self.checked end
    -- A click on an enabled button runs its OnClick script; a check button flips first, as the client's does.
    function f:Click()
        if not self.enabled then return end
        if self.kind == "CheckButton" then self.checked = not self.checked end
        local fn = self.scripts.OnClick
        if fn then fn(self) end
    end
    -- A font string is a text holder that belongs to the frame that created it.
    function f:CreateFontString(fsName, layer, fsTemplate)
        local fs = { kind = "FontString", name = fsName, layer = layer, template = fsTemplate, shown = true, parent = self }
        function fs:SetText(text) self._text = text end
        function fs:GetText() return self._text end
        function fs:Show() self.shown = true end
        function fs:Hide() self.shown = false end
        function fs:IsShown() return self.shown end
        -- Where a font string stands and in what colour, so a test can read what a window would look like.
        function fs:SetPoint(...) self._point = { ... } end
        function fs:ClearAllPoints() self._point = nil end
        function fs:SetWidth(w) self._width = w end
        function fs:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
        -- The client's answer for how tall the text is once wrapped; a test sets STRINGHEIGHT(fs) to simulate it, else the
        -- answer is not a number and the addon falls back to a count of lines.
        function fs:GetStringHeight()
            if STRINGHEIGHT then return STRINGHEIGHT(self) end
            return H.noop
        end
        setmetatable(fs, { __index = function(_, k)
            if type(k) == "string" and k:match("^%u") then return function() return H.noop end end
        end })
        self.fontStrings[#self.fontStrings + 1] = fs
        return fs
    end
    -- A texture records its colour, size and position, so a test can read what a chart would look like.
    function f:CreateTexture(texName, layer)
        local tex = { kind = "Texture", name = texName, layer = layer, shown = true, parent = self }
        -- A real texture has no SetText (a font string does): calling it raises, as it does in the client.
        function tex:SetText() error("a texture has no SetText") end
        function tex:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
        function tex:SetWidth(w) self._width = w end
        function tex:SetHeight(h) self._height = h end
        function tex:SetSize(w, h) self._width, self._height = w, h end
        function tex:SetPoint(...) self._point = { ... } end
        function tex:ClearAllPoints() self._point = nil end
        function tex:Show() self.shown = true end
        function tex:Hide() self.shown = false end
        function tex:IsShown() return self.shown end
        setmetatable(tex, { __index = function(_, k)
            if type(k) == "string" and k:match("^%u") then return function() return H.noop end end
        end })
        self.textures[#self.textures + 1] = tex
        return tex
    end
    -- Any other capitalised method (SetSize, SetMovable ...) does nothing and can be chained.
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() return H.noop end end
    end })
    frames[#frames + 1] = f
    return f
end

H.noop = setmetatable({}, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() return H.noop end end
end })

function H.frames() return frames end

local function snapshotFrames()
    local list = {}
    for i, f in ipairs(frames) do list[i] = f end
    return list
end

-- opts.fresh          forget the saved variables (a first ever login)
-- opts.noload         do not fire ADDON_LOADED for the addon
-- opts.useC           expose the C_CVar namespace and make the global SetCVar unusable
-- opts.bench          false: do not load Bench.lua (default: load it when it exists)
-- opts.nounitspeed    leave GetUnitSpeed undefined
-- opts.console        "new" (default), "legacy" or "none": which console-list function the client has
-- opts.profiles       false: do not load Profiles.lua (default: load it when it exists)
-- opts.guide          false: do not load Guide.lua (default: load it when it exists)
-- opts.recommend      false: do not load Recommend.lua (default: load it when it exists)
-- opts.results        false: do not load Results.lua (default: load it when it exists)
-- opts.names          false: do not load Names.lua (default: load it when it exists)
-- opts.settings       false: do not load Settings.lua (default: load it when it exists)
-- opts.graph          false: do not load Graph.lua (default: load it when it exists)
-- opts.lines          false: the frames have no CreateLine (an older client)
-- opts.defaults       false: a real first install, which forces nothing. Otherwise a first login finds saved variables that
--                     already force groundEffectDensity at 64 (what the addon used to seed): most tests need one forced entry
function H.boot(cvars, opts)
    opts = opts or {}
    noLines = opts.lines == false
    if opts.fresh then _G.ForeverSettingsDB = nil end
    frames, timers, clock = {}, {}, 0

    _G.CVARS = cvars
    _G.OUT = {}
    _G.COMBAT = false
    _G.SETFAIL = {}
    _G.SPEED = 0
    _G.FALLING = false
    _G.NOUNITSPEED = opts.nounitspeed or false
    _G.GAMETIME = { 12, 0 }
    _G.DERIVED = {}
    _G.LOCKED = {}
    _G.EXTRACMDS = {}

    _G.GETHOOK = nil        -- a test may set this: called with the CVar name before every GetCVar answers
    _G.STRINGHEIGHT = nil   -- a test may set this: called with a font string, answers its wrapped height
    _G.SETLOG = {}          -- every SetCVar call, by name, in order
    _G.GetCVar = function(n)
        if GETHOOK then GETHOOK(n) end
        local value = CVARS[n]
        if value == nil and type(n) == "string" then      -- the client answers CVar names without regard to case
            for name, v in pairs(CVARS) do
                if name:lower() == n:lower() then return v end
            end
        end
        return value
    end
    _G.SetCVar = function(n, v)
        SETLOG[#SETLOG + 1] = n
        if opts.useC then error("global SetCVar must not be used when C_CVar exists") end
        if SETFAIL[n] == "error" then error("boom") end
        if LOCKED[n] and COMBAT then error("locked in combat") end
        if SETFAIL[n] == "clamp" then return true end
        if CVARS[n] == nil then error("Unknown CVar") end
        CVARS[n] = tostring(v)
        local derive = DERIVED[n]
        if derive then derive(CVARS[n], CVARS) end
        return true
    end
    _G.GetCVarDefault = function(n) return "D" .. n end
    _G.InCombatLockdown = function() return COMBAT end
    _G.print = function(s) OUT[#OUT + 1] = s end
    _G.SlashCmdList = {}
    _G.C_CVar = nil
    if opts.useC then
        _G.C_CVar = {
            GetCVar = function(n) return CVARS[n] end,
            SetCVar = function(n, v) CVARS[n] = tostring(v) return true end,
        }
    end
    -- The console list: "new" (default) is C_Console.GetAllCommands, "legacy" the older global ConsoleGetAllCommands,
    -- "none" has neither (what the real Forever client turned out to offer).
    local function consoleList()
        local list = {}
        for name in pairs(CVARS) do list[#list + 1] = { command = name } end
        table.sort(list, function(a, b) return a.command < b.command end)
        for _, name in ipairs(EXTRACMDS) do list[#list + 1] = { command = name } end
        return list
    end
    local console = opts.console or "new"
    _G.C_Console, _G.ConsoleGetAllCommands = nil, nil
    if console == "new" then
        _G.C_Console = { GetAllCommands = consoleList }
    elseif console == "legacy" then
        _G.ConsoleGetAllCommands = consoleList
    end
    if NOUNITSPEED then _G.GetUnitSpeed = nil else _G.GetUnitSpeed = function() return SPEED end end
    _G.IsFalling = function() return FALLING end
    _G.GetRealZoneText = function() return "Test Zone" end
    _G.IsInInstance = function() return false, "none" end
    _G.GetNumGroupMembers = function() return 0 end
    _G.GetPhysicalScreenSize = function() return 3440, 1440 end
    _G.GetGameTime = function() return GAMETIME[1], GAMETIME[2] end
    _G.time = function() return 1790000000 end
    _G.C_Timer = { After = function(sec, fn) timers[#timers + 1] = { due = clock + sec, fn = fn } end }
    _G.CreateFrame = makeFrame

    -- The client's UI surface that UI.lua touches. Menu systems are chosen with opts.menu: "new" (default), "old", "none".
    _G.UIParent = makeFrame("Frame", "UIParent")
    _G.Minimap = makeFrame("Frame", "Minimap")
    function Minimap:GetWidth() return 140 end
    function Minimap:GetCenter() return 1000, 800 end
    function Minimap:GetEffectiveScale() return 1 end
    _G.UISpecialFrames = {}
    _G.tinsert = table.insert
    _G.tremove = table.remove
    _G.CURSOR = { 1000, 800 }
    _G.GetCursorPosition = function() return CURSOR[1], CURSOR[2] end
    _G.ChatFontNormal = {}
    _G.GameTooltip = { lines = {}, shown = false }
    function GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {} end
    function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function GameTooltip:Show() self.shown = true end
    function GameTooltip:Hide() self.shown = false end
    _G.MENUCALLS = { items = {}, levels = {} }
    _G.MenuUtil, _G.UIDropDownMenu_Initialize, _G.ToggleDropDownMenu = nil, nil, nil
    _G.UIDropDownMenu_CreateInfo, _G.UIDropDownMenu_AddButton, _G.UIDropDownMenu_AddSeparator = nil, nil, nil
    local menu = opts.menu or "new"
    if menu == "new" then
        local function node(list)
            local n = {}
            function n:CreateTitle(text) list[#list + 1] = { kind = "title", text = text } end
            function n:CreateDivider() list[#list + 1] = { kind = "divider" } end
            function n:CreateCheckbox(text, isSelected, setSelected)
                local entry = { kind = "check", text = text, isSelected = isSelected, fn = setSelected }
                list[#list + 1] = entry
                local element = {}
                function element:SetEnabled(on) entry.disabled = not on end
                return element
            end
            function n:CreateButton(text, fn)
                local entry = { kind = fn and "button" or "submenu", text = text, fn = fn, children = {} }
                list[#list + 1] = entry
                local child = node(entry.children)
                function child:SetEnabled(on) entry.disabled = not on end
                return child
            end
            return n
        end
        _G.MenuUtil = { CreateContextMenu = function(owner, generator)
            MENUCALLS.owner = owner
            MENUCALLS.items = {}
            generator(owner, node(MENUCALLS.items))
        end }
    elseif menu == "old" then
        _G.UIDropDownMenu_Initialize = function(_, init, display) MENUCALLS.init, MENUCALLS.display = init, display end
        _G.UIDropDownMenu_CreateInfo = function() return {} end
        _G.UIDropDownMenu_AddButton = function(info, level)
            local l = MENUCALLS.levels[level or 1]
            l[#l + 1] = info
        end
        _G.UIDropDownMenu_AddSeparator = function(level)
            local l = MENUCALLS.levels[level or 1]
            l[#l + 1] = { separator = true }
        end
        _G.ToggleDropDownMenu = function(_, _, frame, anchor)
            MENUCALLS.anchor = anchor
            MENUCALLS.levels = { {}, {} }
            MENUCALLS.init(frame, 1)
            for _, info in ipairs(MENUCALLS.levels[1]) do
                if info.hasArrow then MENUCALLS.init(frame, 2, info.menuList) end
            end
        end
    end

    local ns = {}
    assert(load(ADDON_SRC, "=ForeverSettings.lua"))("ForeverSettings", ns)
    if opts.names ~= false and NAMES_SRC and NAMES_SRC ~= "" then
        assert(load(NAMES_SRC, "=Names.lua"))("ForeverSettings", ns)
    end
    if opts.bench ~= false and BENCH_SRC and BENCH_SRC ~= "" then
        assert(load(BENCH_SRC, "=Bench.lua"))("ForeverSettings", ns)
    end
    if opts.profiles ~= false and PROFILES_SRC and PROFILES_SRC ~= "" then
        assert(load(PROFILES_SRC, "=Profiles.lua"))("ForeverSettings", ns)
    end
    if opts.recommend ~= false and RECOMMEND_SRC and RECOMMEND_SRC ~= "" then
        assert(load(RECOMMEND_SRC, "=Recommend.lua"))("ForeverSettings", ns)
    end
    if opts.ui ~= false and UI_SRC and UI_SRC ~= "" then
        assert(load(UI_SRC, "=UI.lua"))("ForeverSettings", ns)
    end
    if opts.settings ~= false and SETTINGS_SRC and SETTINGS_SRC ~= "" then
        assert(load(SETTINGS_SRC, "=Settings.lua"))("ForeverSettings", ns)
    end
    if opts.graph ~= false and GRAPH_SRC and GRAPH_SRC ~= "" then
        assert(load(GRAPH_SRC, "=Graph.lua"))("ForeverSettings", ns)
    end
    if opts.guide ~= false and GUIDE_SRC and GUIDE_SRC ~= "" then
        assert(load(GUIDE_SRC, "=Guide.lua"))("ForeverSettings", ns)
    end
    if opts.results ~= false and RESULTS_SRC and RESULTS_SRC ~= "" then
        assert(load(RESULTS_SRC, "=Results.lua"))("ForeverSettings", ns)
    end

    local env = { ns = ns }
    function env.fire(e, ...)
        for _, f in ipairs(snapshotFrames()) do
            local fn = f.scripts.OnEvent
            if fn and f.events[e] then fn(f, e, ...) end
        end
    end
    function env.slash(m) SlashCmdList.FOREVERSETTINGS(m) end
    -- Calls every shown frame's OnUpdate with dt = costFn(CVARS) until `seconds` of frame time has passed.
    function env.pump(seconds, costFn)
        local t, n = 0, 0
        while t < seconds do
            local dt = costFn(CVARS)
            assert(dt > 0, "costFn must return a positive frame time")
            for _, f in ipairs(snapshotFrames()) do
                local fn = f.scripts.OnUpdate
                if fn and f.shown then fn(f, dt) end
            end
            t = t + dt
            n = n + 1
            tick(dt)
        end
        return n
    end
    -- Lets C_Timer.After callbacks come due without any frames being drawn.
    function env.advance(seconds) tick(seconds) end
    if not opts.noload then
        if _G.ForeverSettingsDB == nil and opts.defaults ~= false then _G.ForeverSettingsDB = { want = { groundEffectDensity = "64" } } end
        env.fire("ADDON_LOADED", "ForeverSettings")
    end
    return env
end

return H
