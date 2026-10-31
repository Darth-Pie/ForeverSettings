-- Graph.lua: draws one cost graph of the results window (spec 2026-10-30-results-window-design.md section 3.4): the frame
-- rate each measured level of a setting would give, joined by a line, with the level in use ringed and the recommended
-- one tagged. The geometry (graph.layout) is pure; graph.new draws it with the client's frames. Loaded after Settings.lua
-- and before Guide.lua; Results.lua is the only caller.
local _, ns = ...

local graph = {}
ns.graph = graph

-- Colours as RGBA. They differ from each other because the tests tell the elements apart by them.
graph.COLORS = {
    line = { 0.20, 0.55, 0.85, 1 }, point = { 0.20, 0.65, 0.95, 1 }, hollow = { 0.45, 0.80, 1.00, 1 },
    ring = { 0.95, 0.95, 0.95, 1 }, recommended = { 1.00, 0.82, 0.00, 1 },
    grid = { 0.35, 0.35, 0.40, 0.5 }, axis = { 0.75, 0.75, 0.80, 1 },
}
local COLORS = graph.COLORS

-- Space kept free inside the rectangle for the fps numbers (left), the level words (bottom) and the tags over the points
-- (top: a tag stands TAG_RISE above its point, so even a point on the top of the axis keeps its tag inside the rectangle).
graph.MARGIN = { left = 44, right = 14, top = 22, bottom = 26 }

local POINT, HIT, RING = 8, 14, 14          -- sizes of a point, of the button over it, and of the ring around the current one
local TAG_RISE = 18                         -- how far above its point a tag stands (the tag is one small line of text)
local DOT, DOT_STEP = 2, 6                  -- the squares that stand in for a line: their size and how far apart they are

-- Where everything goes, relative to the top left of the parent. rect = {x, y, width, height}. Returns
-- {plot = {x, y, width, height}, ticks = {{y, label}}, points = {{x, y, point}}}; a flat axis puts everything in the middle.
function graph.layout(entry, axis, rect)
    local m = graph.MARGIN
    local plot = {
        x = rect.x + m.left, y = rect.y + m.top,
        width = rect.width - m.left - m.right, height = rect.height - m.top - m.bottom,
    }
    local span = axis.max - axis.min
    local function yOf(fps)
        if span <= 0 then return plot.y + plot.height / 2 end
        return plot.y + (1 - (fps - axis.min) / span) * plot.height
    end
    local ticks = {}
    for i, t in ipairs(axis.ticks or {}) do
        ticks[i] = { y = yOf(t), label = string.format("%.0f", t) }
    end
    local points = {}
    local n = #(entry.points or {})
    for k, p in ipairs(entry.points or {}) do
        local x = n == 1 and (plot.x + plot.width / 2) or (plot.x + (k - 1) / (n - 1) * plot.width)
        points[k] = { x = x, y = yOf(p.fps), point = p }
    end
    return { plot = plot, ticks = ticks, points = points }
end

-- Pools of what a draw needs: what a draw does not use is hidden.
local function newPool(create)
    return { create = create, items = {}, used = 0 }
end
local function take(pool)
    local item = pool.items[pool.used + 1]
    if not item then
        item = pool.create()
        pool.items[pool.used + 1] = item
    end
    pool.used = pool.used + 1
    item:Show()
    return item
end
local function release(pool)
    for i = pool.used + 1, #pool.items do pool.items[i]:Hide() end
    pool.used = 0
end

-- The words of a point's tooltip: its level, then what the frame rate would be, with what is special about it.
local function tooltipLines(entry, p)
    local marks = {}
    if p.current then marks[#marks + 1] = "now" end
    if p.recommended then marks[#marks + 1] = "recommended" end
    if p.doubtful then marks[#marks + 1] = "this reading looks off" end
    local second = string.format("about %.0f fps if only this setting changes", p.fps)
    if #marks > 0 then second = second .. " (" .. table.concat(marks, ", ") .. ")" end
    return entry.name .. ": " .. p.text, second
end

-- A graph drawn into `parent`. g:draw(rect, entry, axis) replaces what it drew before; g:clear() hides it all.
function graph.new(parent)
    local g = {}
    local textures = newPool(function() return parent:CreateTexture(nil, "ARTWORK") end)
    local strings = newPool(function()
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        return fs
    end)
    local buttons = newPool(function()
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(HIT, HIT)
        b:EnableMouse(true)
        return b
    end)
    local segments = newPool(function() return parent:CreateLine() end)
    -- The client's line object when it has one; a client that raises when asked for one falls back to squares for good.
    local useLines = type(parent.CreateLine) == "function"

    local function box(color, x, y, w, h)
        local tex = take(textures)
        tex:SetColorTexture(color[1], color[2], color[3], color[4])
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        tex:SetSize(w, h)
    end
    -- The outline of a square `size` wide centred on (cx, cy).
    local function outline(color, cx, cy, size)
        local left, top = cx - size / 2, cy - size / 2
        box(color, left, top, size, 1)
        box(color, left, top + size - 1, size, 1)
        box(color, left, top, 1, size)
        box(color, left + size - 1, top, 1, size)
    end
    local function say(text, x, y, width, color)
        local fs = take(strings)
        fs:SetWidth(width)
        fs:SetText(text)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        if color then fs:SetTextColor(color[1], color[2], color[3], color[4]) else fs:SetTextColor(1, 1, 1, 1) end
    end
    local function join(x1, y1, x2, y2)
        if useLines then
            local ok, line = pcall(take, segments)
            if ok then
                line:SetThickness(2)
                line:SetColorTexture(COLORS.line[1], COLORS.line[2], COLORS.line[3], COLORS.line[4])
                line:SetStartPoint("TOPLEFT", parent, x1, -y1)
                line:SetEndPoint("TOPLEFT", parent, x2, -y2)
                return
            end
            useLines = false
        end
        local dx, dy = x2 - x1, y2 - y1
        local count = math.max(1, math.floor(math.sqrt(dx * dx + dy * dy) / DOT_STEP))
        for k = 0, count do
            box(COLORS.line, x1 + dx * k / count - DOT / 2, y1 + dy * k / count - DOT / 2, DOT, DOT)
        end
    end

    function g:draw(rect, entry, axis)
        textures.used, strings.used, buttons.used, segments.used = 0, 0, 0, 0
        if entry and axis then
            local lay = graph.layout(entry, axis, rect)
            local plot = lay.plot
            for _, tick in ipairs(lay.ticks) do
                box(COLORS.grid, plot.x, tick.y, plot.width, 1)
                say(tick.label, rect.x, tick.y - 6, graph.MARGIN.left - 6)
            end
            box(COLORS.axis, plot.x, plot.y, 1, plot.height)
            box(COLORS.axis, plot.x, plot.y + plot.height, plot.width, 1)
            local points = lay.points
            for k = 1, #points - 1 do join(points[k].x, points[k].y, points[k + 1].x, points[k + 1].y) end
            for k, item in ipairs(points) do
                local p = item.point
                if p.doubtful then
                    outline(COLORS.hollow, item.x, item.y, POINT)
                else
                    box(p.recommended and COLORS.recommended or COLORS.point, item.x - POINT / 2, item.y - POINT / 2, POINT, POINT)
                end
                if p.current then
                    outline(COLORS.ring, item.x, item.y, RING)
                    say("now", item.x - 20, item.y - TAG_RISE, 40)
                end
                if p.recommended then say("recommended", item.x - 35, item.y - TAG_RISE, 70, COLORS.recommended) end
                if k == 1 or k == #points or p.current or p.recommended then
                    say(p.text, item.x - 20, plot.y + plot.height + 6, 40)
                end
                local button = take(buttons)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", parent, "TOPLEFT", item.x - HIT / 2, -(item.y - HIT / 2))
                local first, second = tooltipLines(entry, p)
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(first)
                    GameTooltip:AddLine(second)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end
        release(textures)
        release(strings)
        release(buttons)
        release(segments)
    end

    function g:clear()
        self:draw(nil, nil, nil)
    end

    return g
end
