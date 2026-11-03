-- Graph.lua: draws one cost graph of the results page (specs 2026-10-30-results-window-design.md section 3.4 and
-- 2026-11-03-tests-and-results-in-my-settings-design.md M4, M5): the frame rate each measured level of a setting would give,
-- joined by a line, with the level in use ringed, the recommended one tagged and a picked one in its profile's colour; a
-- click on a point can choose its level. The geometry (graph.layout) is pure; graph.new draws it with the client's frames.
-- Loaded after Settings.lua and before Guide.lua; Results.lua is the only caller.
local _, ns = ...

local graph = {}
ns.graph = graph

-- Colours as RGBA, from the window's palette. They differ from each other because the tests tell the elements apart by them.
local function paletteColor(name)
    local r, g, b, a = ns.skin.color(name)
    return { r, g, b, a }
end
graph.COLORS = {
    grid = paletteColor("divider"), axis = paletteColor("border"), line = paletteColor("accentDim"), point = paletteColor("accentLight"),
    hollow = paletteColor("dim"), ring = paletteColor("bright"), recommended = paletteColor("accent"),
    picked = paletteColor("profileEveryday"), pickedCrowd = paletteColor("profileCrowded"),
    label = paletteColor("dim"), level = paletteColor("text"),
}
local COLORS = graph.COLORS

-- Space kept free inside the rectangle for the fps numbers (left), the level words (bottom) and the tags over the points
-- (top: a tag stands TAG_RISE above its point, so even a point on the top of the axis keeps its tag inside the rectangle).
graph.MARGIN = { left = 44, right = 14, top = 22, bottom = 26 }

graph.HIT = 20                              -- the button over each point: big enough to click
local POINT, HIT, RING = 8, graph.HIT, 16   -- sizes of a point, of the button over it, and of the ring around the current one
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
    if p.picked then marks[#marks + 1] = "your pick" end
    if p.doubtful then marks[#marks + 1] = "this reading looks off" end
    local second = string.format("about %.0f fps if only this setting changes", p.fps)
    if #marks > 0 then second = second .. " (" .. table.concat(marks, ", ") .. ")" end
    return entry.name .. ": " .. p.text, second
end

-- A round mark (spec M4): a small frame holding a rounded box, `size` pixels, drawn from the corner pictures. Its role
-- (point, recommended, picked, hollow, ring) is set at each draw.
local function newMark(parent, size, radius)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.box = ns.skin.box(f, radius, "fill", "fill")
    return f
end

-- A graph drawn into `parent`. g:draw(rect, entry, axis, options) replaces what it drew before; options = {onPick, pickColor}:
-- with onPick a click on a point calls onPick(level), without it a point only shows its tooltip; pickColor ("everyday" or
-- "crowded") is the colour of a picked point. g:clear() hides it all.
function graph.new(parent)
    local g = {}
    local dots = newPool(function() return newMark(parent, POINT, ns.skin.RADIUS.control) end)
    local rings = newPool(function() return newMark(parent, RING, ns.skin.RADIUS.window) end)
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
    -- A round mark centred on (cx, cy): filled in `fillColor` (nil: clear) with an edge in `edgeColor` (nil: the fill's).
    local function mark(pool, role, cx, cy, fillColor, edgeColor)
        local m = take(pool)
        m.graphMark = role
        local size = pool == rings and RING or POINT
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", parent, "TOPLEFT", cx - size / 2, -(cy - size / 2))
        local f = fillColor or { 0, 0, 0, 0 }
        m.box.fill:SetColorTexture(f[1], f[2], f[3], fillColor and f[4] or 0)
        local e = edgeColor or fillColor
        m.box.edge:SetColorTexture(e[1], e[2], e[3], e[4])
    end
    local function say(text, x, y, width, color)
        local fs = take(strings)
        fs:SetWidth(width)
        fs:SetText(text)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        local c = color or COLORS.level
        fs:SetTextColor(c[1], c[2], c[3], c[4])
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

    function g:draw(rect, entry, axis, options)
        options = options or {}
        local pickedColor = options.pickColor == "crowded" and COLORS.pickedCrowd or COLORS.picked
        textures.used, strings.used, buttons.used, segments.used, dots.used, rings.used = 0, 0, 0, 0, 0, 0
        if entry and axis then
            local lay = graph.layout(entry, axis, rect)
            local plot = lay.plot
            for _, tick in ipairs(lay.ticks) do
                box(COLORS.grid, plot.x, tick.y, plot.width, 1)
                say(tick.label, rect.x, tick.y - 6, graph.MARGIN.left - 6, COLORS.label)
            end
            box(COLORS.axis, plot.x, plot.y, 1, plot.height)
            box(COLORS.axis, plot.x, plot.y + plot.height, plot.width, 1)
            local points = lay.points
            for k = 1, #points - 1 do join(points[k].x, points[k].y, points[k + 1].x, points[k + 1].y) end
            for k, item in ipairs(points) do
                local p = item.point
                if p.picked then
                    mark(dots, "picked", item.x, item.y, pickedColor)
                elseif p.doubtful then
                    mark(dots, "hollow", item.x, item.y, nil, COLORS.hollow)
                elseif p.recommended then
                    mark(dots, "recommended", item.x, item.y, COLORS.recommended)
                else
                    mark(dots, "point", item.x, item.y, COLORS.point)
                end
                if p.current then
                    mark(rings, "ring", item.x, item.y, nil, COLORS.ring)
                    say("now", item.x - 20, item.y - TAG_RISE, 40, COLORS.ring)
                end
                if p.picked then
                    say("your pick", item.x - 35, item.y - TAG_RISE, 70, pickedColor)
                elseif p.recommended then
                    say("recommended", item.x - 35, item.y - TAG_RISE, 70, COLORS.recommended)
                end
                if k == 1 or k == #points or p.current or p.recommended or p.picked then
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
                -- A click chooses the level only when the caller allows it (not in combat, not during a test).
                local onPick, value = options.onPick, p.value
                button:SetScript("OnClick", onPick and function() onPick(value) end or nil)
            end
        end
        release(textures)
        release(strings)
        release(buttons)
        release(segments)
        release(dots)
        release(rings)
    end

    function g:clear()
        self:draw(nil, nil, nil)
    end

    return g
end
