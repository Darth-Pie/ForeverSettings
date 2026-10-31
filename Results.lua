-- Results.lua: the results window of the recommender (specs 2026-10-29-recommender-design.md section 5 and
-- 2026-10-30-results-window-design.md). It only draws what Recommend.chartModel computes (the verdict, the bars, the
-- changes, the setting list and one graph at a time through Graph.lua) and passes the one click, Save and switch, to
-- Profiles. Loaded after Guide.lua.
local _, ns = ...

local results = {}
ns.results = results

local FRAME_NAME = "ForeverSettingsResults"
local WIDTH, HEIGHT = 760, 540
local CHART_X, CHART_WIDTH = 20, 380        -- the bars: where they start and how long a bar of the full scale is
local CHANGES_X, CHANGES_WIDTH = 420, 320   -- the changes, to the right of the bars
local MAX_CHANGE_LINES = 6                  -- more changes than this are cut to one line fewer and a pointer to the list
local PANEL_HEIGHT = 186                    -- the setting list and the graph are anchored above the bottom block of the window
local BOTTOM_BLOCK = 104                    -- buttons (36), then room for the saved line (up to three small lines) and the footer
local PANEL_Y = HEIGHT - BOTTOM_BLOCK - PANEL_HEIGHT
local LIST_X, LIST_WIDTH, ROW_HEIGHT, MAX_ROWS = 20, 200, 18, 10
local PANEL_X, PANEL_WIDTH = 230, 510
local GRAPH_RECT = { x = 0, y = 18, width = PANEL_WIDTH, height = 122 }       -- inside the panel: a title above, up to three sentences below
local BUTTON_WIDTHS = { apply = 250, again = 150, later = 150 }
local BUTTON_GAP = 12
local REFRESH = 0.5                         -- seconds of frame time between checks of combat and of a running test

local SAVED = "Saved as your Everyday settings and switched on. Your original settings are kept: choose Original in the minimap menu to go back."
local SAVED_CROWD = "Saved as your Crowded settings and switched on. Your original settings are kept: choose Everyday or Original in the minimap menu "
    .. "to go back, or use the key you bound to toggle Everyday and Crowded."
local GOOD = { 0.3, 0.85, 0.4 }             -- the colour of the line that says the settings were saved
local BAD = { 1, 0.2, 0.2 }                 -- and of the line that says why they were not

-- Which profile the open result is written to: a crowd result goes to Crowded, any other to Everyday.
local function profileOf(result)
    return result.kind == "crowd" and "crowded" or "everyday"
end
local REFUSED = {
    combat = "You are in combat; try again afterwards.",
    busy = "A test is running; try again afterwards.",
}

-- Bar colours; the tests tell the bars apart by them.
results.COLORS = {
    now = { 0.55, 0.55, 0.55, 1 }, after = { 0.20, 0.60, 0.90, 1 }, target = { 1.00, 0.82, 0.00, 1 },
}
local COLORS = results.COLORS
local GREY = { 0.5, 0.5, 0.5, 1 }           -- the label of a setting that could not be measured

local current                -- {entry, target, result, model, selected, notice} while a recommendation is on offer
local frame, parts           -- built on first use
local lastError
local sinceRefresh = 0

-- A frame from a template; a client without that template gets the plain frame of `fallbackKind` (default: the same
-- kind) instead.
local function make(kind, name, parent, template, fallbackKind)
    local ok, made = pcall(CreateFrame, kind, name, parent, template)
    if ok and made then return made, true end
    return CreateFrame(fallbackKind or kind, name, parent), false
end

-- A plain button has no text of its own: it is given a font string to carry the label.
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

-- The height a font string needs for its text: the client's answer, else a line count.
local function heightOf(fs, str)
    local h = fs:GetStringHeight()
    if type(h) == "number" and h > 0 then return h end
    local _, breaks = str:gsub("\n", "\n")
    return 14 * (breaks + 1)
end

-- Pools of font strings, textures and rows, reused by every draw: what a draw does not use is hidden, and a font string
-- is also emptied (a texture has no text to empty).
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
local function release(pool, hasText)
    for i = pool.used + 1, #pool.items do
        pool.items[i]:Hide()
        if hasText then pool.items[i]:SetText("") end
    end
    pool.used = 0
end
local function fontMaker(font)
    return function(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH("LEFT")
        return fs
    end
end
local function textureMaker(parent)
    return parent:CreateTexture(nil, "ARTWORK")
end

-- A line of text at (x, y) below the top of the pool's parent.
local function put(pool, str, x, y, width)
    local fs = take(pool)
    fs:SetWidth(width)
    fs:SetText(str)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", x, -y)
    return fs
end
-- A bar of `color`, `width` by `height`, with its top left corner at (x, y).
local function bar(pool, color, x, y, width, height)
    local tex = take(pool)
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", x, -y)
    tex:SetSize(width, height)
    return tex
end

local function makeButton(f)
    local button, templated = make("Button", nil, f, "UIPanelButtonTemplate")
    if not templated then giveLabel(button) end
    button:SetSize(210, 24)
    button:SetScript("OnClick", function(self) results.click(self.key) end)
    return button
end

-- A row of the setting list: a plain button with its own label and the dot that marks a setting the test changes.
local function makeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.label:SetJustifyH("LEFT")
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(6, 6)
    row.dot:SetColorTexture(COLORS.target[1], COLORS.target[2], COLORS.target[3], COLORS.target[4])
    row.dot:SetPoint("LEFT", row, "LEFT", 2, 0)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.15)
    row:SetHighlightTexture(highlight)
    row:SetScript("OnClick", function(self) results.select(self.cvar) end)
    return row
end

-- Why Save and switch would be refused right now, from the same facts the switch checks: "combat", "busy" or nil.
local function refusal()
    if InCombatLockdown() then return "combat" end
    if ns.suspended or (ns.bench and ns.bench.active and ns.bench.active()) then return "busy" end
    return nil
end

-- The Save button follows combat and a running test. The notice says that the settings were saved (green), or why the
-- button is grey or why the last click failed (red).
local function updateButtons()
    local p = parts
    if not p or not current then return end
    local why = refusal()
    if p.apply then p.apply:SetEnabled(why == nil) end
    local notice, color = "", BAD
    if current.saved then
        notice, color = current.saved, GOOD
    elseif why and current.model.saveKind then
        notice = REFUSED[why]
    elseif current.notice then
        notice = current.notice
    end
    p.notice:SetText(notice)
    p.notice:SetTextColor(color[1], color[2], color[3])
    if notice == "" then p.notice:Hide() else p.notice:Show() end
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
    p.footer = text(f, "GameFontNormalSmall", WIDTH - 40)
    p.notice = text(f, "GameFontNormalSmall", WIDTH - 40)
    p.notice:SetTextColor(BAD[1], BAD[2], BAD[3])
    p.panel = CreateFrame("Frame", nil, f)
    p.panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    p.graph = ns.graph and ns.graph.new(p.panel) or nil
    p.fsMain, p.texMain = newPool(f, fontMaker("GameFontHighlight")), newPool(f, textureMaker)
    p.fsPanel = newPool(p.panel, fontMaker("GameFontHighlight"))
    p.rows = newPool(f, makeRow)
    p.buttons = { makeButton(f), makeButton(f), makeButton(f) }
    f:SetScript("OnUpdate", function(_, elapsed)
        if not current then return end
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh < REFRESH then return end
        sinceRefresh = 0
        updateButtons()
    end)
    -- Closing the window by any route ends the offer: nothing is applied from a window that is not on screen.
    f:SetScript("OnHide", function() current = nil end)
    local listedForEscape = false
    for _, name in ipairs(UISpecialFrames) do
        if name == FRAME_NAME then listedForEscape = true end
    end
    if not listedForEscape then tinsert(UISpecialFrames, FRAME_NAME) end
    frame, parts = f, p
    return f
end

local function ensure()
    return frame or build()
end

-- The setting list of the open result: measured settings (the graphs, in the model's order) then the unmeasured ones.
local function listOf(model)
    local list = {}
    for _, g in ipairs(model.graphs) do
        list[#list + 1] = { cvar = g.cvar, name = g.name, changed = g.changed, graph = g }
    end
    for _, n in ipairs(model.notMeasured) do
        list[#list + 1] = { cvar = n.cvar or n.setting, name = n.name or n.setting, reason = n.plain or n.reason }
    end
    return list
end

local function entryFor(list, cvar)
    for _, item in ipairs(list) do
        if item.cvar == cvar then return item end
    end
    return nil
end

-- Draws the current model: the verdict, the bars, the changes, the paragraphs that fit, the setting list with its graph,
-- the footer and the buttons.
local function draw()
    local f = ensure()
    local p = parts
    local m = current.model
    local y = 30

    p.title:SetText(m.title or "Your best settings")
    p.title:ClearAllPoints()
    p.title:SetPoint("TOPLEFT", f, "TOPLEFT", CHART_X, -y)
    y = 58

    if m.verdict and m.verdict ~= "" then
        local fs = put(p.fsMain, m.verdict, CHART_X, y, WIDTH - 40)
        y = y + heightOf(fs, m.verdict) + 8
    end

    -- Two columns: the bars on the left, the changes on the right.
    local left, right = y, y
    if m.headline then
        local h = m.headline
        local top = left
        local function row(entryRow, color)
            put(p.fsMain, entryRow.label, CHART_X, left, WIDTH - 40)
            left = left + 16
            bar(p.texMain, color, CHART_X, left, entryRow.fraction * CHART_WIDTH, 14)
            left = left + 20
        end
        row(h.now, COLORS.now)
        if h.after then row(h.after, COLORS.after) end
        bar(p.texMain, COLORS.target, CHART_X + h.target.fraction * CHART_WIDTH, top, 2, left - top)
        put(p.fsMain, h.target.label, CHART_X, left, WIDTH - 40)
        left = left + 24
    end
    -- The changes, as many as fit above the list (and at most MAX_CHANGE_LINES): when some are left out, the last line that
    -- was put gives its place to a pointer to the list.
    local placed = {}
    for i, line in ipairs(m.lines) do
        if i > MAX_CHANGE_LINES then break end
        local fs = put(p.fsMain, line, CHANGES_X, right, CHANGES_WIDTH)
        local h = heightOf(fs, line)
        if right + h > PANEL_Y - 4 then
            fs:SetText("")
            fs:Hide()
            break
        end
        placed[#placed + 1] = { fs = fs, top = right }
        right = right + h + 2
    end
    if #placed > 0 and #placed < #m.lines then
        local last = placed[#placed]
        local pointer = "and " .. (#m.lines - (#placed - 1)) .. " more changes: pick them in the list below."
        last.fs:SetText(pointer)
        right = last.top + heightOf(last.fs, pointer) + 2
    end
    y = math.max(left, right) + 6

    -- What the check of the recommendation found, where and when it was measured, and the pointer to the next test: each
    -- only when there is still room above the list (a paragraph that would run into it is left out).
    local function paragraph(str)
        if str == nil or str == "" then return end
        local fs = put(p.fsMain, str, CHART_X, y, WIDTH - 40)
        local h = heightOf(fs, str)
        if y + h > PANEL_Y - 4 then
            fs:SetText("")
            fs:Hide()
        else
            y = y + h + 8
        end
    end
    if #m.checkLines > 0 then paragraph(table.concat(m.checkLines, "\n")) end
    paragraph(current.extras and current.extras.measuredLine)
    paragraph(m.hint)
    if #m.lines == 0 and m.summary and m.summary ~= m.verdict then paragraph(m.summary) end

    -- The setting list, and the graph (or the reason) of the one that is open.
    local list = listOf(m)
    local open = entryFor(list, current.selected) and current.selected or nil
    local rowsShown = math.min(#list, MAX_ROWS)
    for i = 1, rowsShown do
        local item = list[i]
        local row = take(p.rows)
        row.key, row.cvar = "setting:" .. item.cvar, item.cvar
        row.label:SetText(item.name)
        local color = item.graph and { 1, 1, 1, 1 } or GREY
        row.label:SetTextColor(color[1], color[2], color[3], color[4])
        if item.changed then row.dot:Show() else row.dot:Hide() end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, -(PANEL_Y + (i - 1) * ROW_HEIGHT))
        if item.cvar == open then row:LockHighlight() else row:UnlockHighlight() end
    end
    p.panel:ClearAllPoints()
    p.panel:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL_X, -PANEL_Y)
    local chosen = open and entryFor(list, open) or nil
    if chosen and chosen.graph and p.graph then
        put(p.fsPanel, chosen.name .. ": fps if only this setting changes", 0, 0, PANEL_WIDTH)
        p.graph:draw(GRAPH_RECT, chosen.graph, m.axis)
        local sy = GRAPH_RECT.y + GRAPH_RECT.height + 4
        for _, line in ipairs(chosen.graph.lines) do
            put(p.fsPanel, line, 0, sy, PANEL_WIDTH)
            sy = sy + 14
        end
    else
        if p.graph then p.graph:clear() end
        if chosen then put(p.fsPanel, chosen.name .. ": not measured (" .. tostring(chosen.reason) .. ")", 0, 0, PANEL_WIDTH) end
    end

    release(p.fsMain, true)
    release(p.texMain)
    release(p.fsPanel, true)
    release(p.rows)

    -- The saved line (or the reason a click was refused) sits just above the buttons and may wrap onto two or three lines;
    -- the footer stands on top of it, so the two never run into each other.
    p.notice:ClearAllPoints()
    p.notice:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CHART_X, 40)
    p.footer:SetText(m.footer)
    p.footer:ClearAllPoints()
    p.footer:SetPoint("BOTTOMLEFT", p.notice, "TOPLEFT", 0, 4)

    -- Save (when there is something worth saving and it has not been saved yet), Run it again (a result opened from the
    -- menu or a guided test), Close.
    local specs = {}
    if m.saveKind and not current.saved then
        local profile = profileOf(current.result)
        local replace = ns.profiles and ns.profiles.hasValues and ns.profiles.hasValues(profile)
        local who = profile == "crowded" and "Crowded" or "Everyday"
        specs[1] = { key = "apply", text = replace and ("Replace my " .. who .. " settings with these") or ("Save these as my " .. who .. " settings") }
    end
    if current.extras and current.extras.again then specs[#specs + 1] = { key = "again", text = "Run it again" } end
    specs[#specs + 1] = { key = "later", text = "Close" }
    p.apply = nil
    -- Side by side, centred, each as wide as its label needs (the longest, "Replace my Everyday settings with these", needs 250).
    local total = BUTTON_GAP * (#specs - 1)
    for _, spec in ipairs(specs) do total = total + BUTTON_WIDTHS[spec.key] end
    local edge = -total / 2
    for i, button in ipairs(p.buttons) do
        local spec = specs[i]
        if spec then
            local width = BUTTON_WIDTHS[spec.key]
            button.key = spec.key
            button:SetText(spec.text)
            button:SetSize(width, 24)
            button:ClearAllPoints()
            button:SetPoint("BOTTOM", f, "BOTTOM", edge + width / 2, 12)
            edge = edge + width + BUTTON_GAP
            button:Show()
            if spec.key == "apply" then p.apply = button end
        else
            button:Hide()
        end
    end
    updateButtons()
end

-- The window could not be drawn: say so once per distinct error and print what it would have shown.
local function fail(err)
    if err ~= lastError then
        lastError = err
        ns.say("the results window could not be drawn: " .. tostring(err))
    end
    local m = current and current.model
    if not m then return end
    for _, line in ipairs(m.lines) do ns.say(line) end
    for _, line in ipairs(m.checkLines) do ns.say(line) end
    if m.summary then ns.say(m.summary) end
    for _, n in ipairs(m.notMeasured) do ns.say("Not measured: " .. (n.name or n.setting) .. " (" .. n.reason .. ")") end
end

-- Opens the window for a valid history entry (or a crowd entry from Recommend.crowdEntry) and the player's target frame
-- rate. `verify` is the check of the recommendation (Bench.lua, bench.verify), when there was one.
function results.show(entry, target, verify, extras)
    local result = ns.recommend.choose(entry, target)
    local model = ns.recommend.chartModel(result, verify)
    local first = model.notMeasured[1]
    current = { entry = entry, target = target, result = result, verify = verify, extras = extras, model = model,
        selected = model.selected or (first and (first.cvar or first.setting)) or nil }
    sinceRefresh = 0
    local ok, err = pcall(function()
        draw()
        frame:Show()
    end)
    if not ok then fail(err) end
end

-- Opens the graph (or the reason) of one setting of the open result; an unknown setting or no open window changes nothing.
function results.select(cvar)
    if not current or not entryFor(listOf(current.model), cvar) then return end
    current.selected = cvar
    local ok, err = pcall(draw)
    if not ok then fail(err) end
end

-- The setting that is open in the window, or nil.
function results.selected()
    return current and current.selected or nil
end

function results.hide()
    if frame then frame:Hide() end
end

function results.frame()
    return frame
end

-- A button of the window: `apply` saves the result as Everyday or Crowded through Profiles.adopt (the recommended values,
-- or what the game has now when nothing needs changing), `again` runs the test again, `later` closes.
function results.click(key)
    if not current then return end
    if key == "later" then
        results.hide()
        return
    end
    if key == "again" then
        local kind = current.extras and current.extras.again
        results.hide()
        if kind and ns.guide and ns.guide.open then ns.guide.open(kind) end
        return
    end
    if key ~= "apply" or not current.model.saveKind or current.saved then return end
    if not (ns.profiles and ns.profiles.adopt) then
        ns.say("profiles module not loaded")
        return
    end
    -- Profiles refuses (combat, a running test) before anything is written, and says nothing in chat: the window says why.
    local values = {}
    if current.model.saveKind == "changes" then
        for _, change in ipairs(current.result.changes) do values[change.cvar] = change.to end
    end
    local profile = profileOf(current.result)
    local ok, info = ns.profiles.adopt(profile, values, true)
    if ok then
        local line = profile == "crowded" and SAVED_CROWD or SAVED
        local kept = type(info) == "table" and type(info.mismatched) == "table" and #info.mismatched or 0
        if kept > 0 then line = line .. " The game kept " .. kept .. " setting" .. (kept == 1 and "" or "s") .. " at a different level than saved." end
        current.saved, current.notice = line, nil
        local drawn, err = pcall(draw)
        if not drawn then fail(err) end
    else
        current.notice = REFUSED[info] or ("Could not save: " .. tostring(info))
        updateButtons()
    end
end
