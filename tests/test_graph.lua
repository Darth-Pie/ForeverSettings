-- Tests for Graph.lua (spec 2026-10-30-results-window-design.md section 3.4), driven through the shared harness. The pure
-- geometry (graph.layout) is read as numbers; the drawing is read from what the stubs record: textures, lines, font
-- strings and buttons. How the real client draws them is checked only in the game.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function boot(opts)
    opts = opts or {}
    opts.fresh = true
    local e = H.boot({ graphicsShadowQuality = "4", RenderScale = "1" }, opts)
    return e, e.ns.graph, e.ns.recommend
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 1e-6) end

local LABEL = { graphicsShadowQuality = "Shadows", graphicsSSAO = "SSAO" }
local function rows(cvar, baseline, levels)
    local list = {}
    for _, l in ipairs(levels) do
        local r = { setting = LABEL[cvar] or cvar, cvar = cvar, value = l[1], flags = {} }
        r.deltaMs, r.meanMs = l[2], baseline + l[2]
        if l.current then r.current = true end
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
-- T1 (baseline 4.0 ms), target 250: Shadows 333.33 / 277.78 / 250 fps, the middle level recommended, the last one now.
local function T1()
    return entry(4.0,
        rows("graphicsShadowQuality", 4.0, { { "0", -1.0 }, { "1", -0.4 }, { "2", 0, current = true } }),
        rows("graphicsSSAO", 4.0, { { "0", -0.6 }, { "1", -0.3 }, { "2", 0, current = true } }))
end
local function modelOf(r, e, target)
    return r.chartModel(r.choose(e or T1(), target or 250))
end
local function graphOf(model, cvar)
    for _, g in ipairs(model.graphs) do
        if g.cvar == cvar then return g end
    end
end
local RECT = { x = 0, y = 0, width = 510, height = 122 }       -- the rectangle Results.lua gives the graph

-- What is on a frame, shown (a hidden child frame shows none of its textures)
local function walk(f, fn)
    fn(f)
    for _, c in ipairs(f.children) do
        if c.shown ~= false then walk(c, fn) end
    end
end
-- The round points and rings (spec 2026-11-03 M4): small frames with a rounded box, read by their role and paint.
local function marks(f, role)
    local list = {}
    walk(f, function(frame)
        if frame ~= f and frame.graphMark == role and frame.shown then list[#list + 1] = frame end
    end)
    return list
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
local function shownLines(f)
    local list = {}
    walk(f, function(frame)
        for _, line in ipairs(frame.lines) do
            if line.shown then list[#list + 1] = line end
        end
    end)
    return list
end
local function shownTextures(f)
    local n = 0
    walk(f, function(frame)
        for _, tex in ipairs(frame.textures) do
            if tex.shown then n = n + 1 end
        end
    end)
    return n
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
local function countExact(f, text)
    local n = 0
    for _, t in ipairs(texts(f)) do
        if t == text then n = n + 1 end
    end
    return n
end
local function pointButtons(f)
    local list = {}
    walk(f, function(frame)
        if frame ~= f and frame.kind == "Button" and frame.shown then list[#list + 1] = frame end
    end)
    table.sort(list, function(a, b) return (a._point and a._point[4] or 0) < (b._point and b._point[4] or 0) end)
    return list
end
local function newParent()
    return CreateFrame("Frame", nil, UIParent)
end

test("GR-1 layout puts the points evenly across the plot and the heights on the shared axis, inside the margins", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local lay = graph.layout(graphOf(m, "graphicsShadowQuality"), m.axis, RECT)
    local p, t = lay.points, lay.ticks
    return near(lay.plot.x, 44) and near(lay.plot.y, 22) and near(lay.plot.width, 452) and near(lay.plot.height, 74)
        and #p == 3 and near(p[1].x, 44) and near(p[2].x, 270) and near(p[3].x, 496)
        and near(p[1].y, 22 + (1 - 83.3333 / 100) * 74, 0.01) and near(p[3].y, 96) and p[1].point.text == "0"
        and #t == 5 and t[1].label == "250" and near(t[1].y, 96) and t[5].label == "350" and near(t[5].y, 22)
        and graph.MARGIN.left == 44 and graph.MARGIN.right == 14 and graph.MARGIN.top == 22 and graph.MARGIN.bottom == 26,
        tostring(p[1] and p[1].y) .. " " .. tostring(lay.plot.height)
end)

test("GR-2 one point goes to the middle, equal points to the middle height, and a flat axis divides by nothing", function()
    local _, graph, r = boot()
    local single = { cvar = "x", name = "X", points = { { value = "1", text = "1", fps = 250, current = true } }, lines = {} }
    local flatAxis = { min = 245, max = 255, step = 5, ticks = { 245, 250, 255 } }
    local lay = graph.layout(single, flatAxis, RECT)
    local degenerate = graph.layout(single, { min = 250, max = 250, step = 5, ticks = { 250 } }, RECT)
    local flatEntry = { cvar = "x", name = "X", lines = {}, points = {
        { value = "0", text = "0", fps = 250 }, { value = "1", text = "1", fps = 250, current = true } } }
    local flat = graph.layout(flatEntry, { min = 250, max = 250, step = 5, ticks = { 250 } }, RECT)
    local none = graph.layout({ cvar = "x", name = "X", points = {}, lines = {} }, flatAxis, RECT)
    return near(lay.points[1].x, 270) and near(lay.points[1].y, 59) and near(degenerate.points[1].y, 59)
        and near(flat.points[1].y, 59) and near(flat.points[2].y, 59) and #none.points == 0 and #none.ticks == 3,
        tostring(lay.points[1].x) .. " " .. tostring(degenerate.points[1].y)
end)

test("GR-3 the points are joined by the client's lines, or by a row of small squares where there are none", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent = newParent()
    local g = graph.new(parent)
    g:draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    local lines = shownLines(parent)
    local lay = graph.layout(graphOf(m, "graphicsShadowQuality"), m.axis, RECT)
    local first = lines[1]
    local withLines = #lines == 2 and first._thickness == 2 and sameColor(first._color, graph.COLORS.line)
        and first._start[1] == "TOPLEFT" and near(first._start[3], lay.points[1].x) and near(first._start[4], -lay.points[1].y)
        and near(first._end[3], lay.points[2].x) and near(first._end[4], -lay.points[2].y)

    local _, graph2, r2 = boot({ lines = false })
    local m2 = modelOf(r2)
    local parent2 = newParent()
    local g2 = graph2.new(parent2)
    g2:draw(RECT, graphOf(m2, "graphicsShadowQuality"), m2.axis)
    local dots = texturesOf(parent2, graph2.COLORS.line)
    local small = true
    for _, d in ipairs(dots) do small = small and d._width == 2 and d._height == 2 end
    -- a client that has the call but raises when it is used falls back to the squares too
    local parent3 = newParent()
    parent3.CreateLine = function() error("no lines here") end
    local g3 = graph.new(parent3)
    local raised = pcall(g3.draw, g3, RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    return withLines and #shownLines(parent2) == 0 and #dots >= 2 * 37 and small and parent2.CreateLine == false
        and raised and #texturesOf(parent3, graph.COLORS.line) >= 2 * 37, tostring(#lines) .. " " .. tostring(#dots)
end)

test("GR-4 points: round dots, the recommended one in its own colour, an outline for doubtful ones, a round ring on the current one", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent = newParent()
    local g = graph.new(parent)
    g:draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    local filled, recommended, rings = marks(parent, "point"), marks(parent, "recommended"), marks(parent, "ring")
    local grid = texturesOf(parent, graph.COLORS.grid)
    local axis = texturesOf(parent, graph.COLORS.axis)
    local okFilled = #filled == 2 and filled[1]._width == 8 and filled[1]._height == 8 and sameColor(filled[1].box.fill._color, graph.COLORS.point)
        and #recommended == 1 and recommended[1]._width == 8 and sameColor(recommended[1].box.fill._color, graph.COLORS.recommended)
        and #rings == 1 and rings[1]._width == 16 and sameColor(rings[1].box.edge._color, graph.COLORS.ring) and rings[1].box.fill._color[4] == 0
    -- a curve with two doubtful points: an outlined dot each
    local odd = r.chartModel(r.choose(entry(4.0, rows("graphicsShadowQuality", 4.0,
        { { "0", -1.5 }, { "1", -0.30 }, { "2", -0.9 }, { "3", 0, current = true } })), 100))
    local parent2 = newParent()
    local g2 = graph.new(parent2)
    g2:draw(RECT, odd.graphs[1], odd.axis)
    local hollow = marks(parent2, "hollow")
    local okHollow = #hollow == 2 and sameColor(hollow[1].box.edge._color, graph.COLORS.hollow) and hollow[1].box.fill._color[4] == 0
    return okFilled and okHollow and #grid == #m.axis.ticks and #axis == 2 and #marks(parent2, "point") == 2,
        #filled .. " " .. #recommended .. " " .. #rings .. " " .. #grid .. " " .. #axis .. " " .. #hollow
end)

test("GR-5 tags and labels: now and recommended over their points, level texts only under the ends and the marked points", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent = newParent()
    local g = graph.new(parent)
    g:draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    local four = r.chartModel(r.choose(entry(4.0, rows("graphicsShadowQuality", 4.0,
        { { "0", -0.8 }, { "1", -0.6 }, { "2", -0.3 }, { "3", 0, current = true } })), 100))
    local parent2 = newParent()
    local g2 = graph.new(parent2)
    g2:draw(RECT, four.graphs[1], four.axis)
    -- the current level in the middle: the last level is labelled for being the end, the middle one for being now
    local middle = r.chartModel(r.choose(entry(4.0, rows("graphicsTextureResolution", 4.0,      -- a setting that is never raised
        { { "0", -0.5 }, { "1", 0, current = true }, { "2", 0.5 } })), 100))
    local parent3 = newParent()
    graph.new(parent3):draw(RECT, middle.graphs[1], middle.axis)
    -- where the tags stand: over their own points
    local lay = graph.layout(graphOf(m, "graphicsShadowQuality"), m.axis, RECT)
    local function stringAt(f, text)
        local found
        walk(f, function(frame)
            for _, fs in ipairs(frame.fontStrings) do
                if fs.shown and fs._text == text then found = fs end
            end
        end)
        return found
    end
    local now, rec = stringAt(parent, "now"), stringAt(parent, "recommended")
    local tagsOk = now and rec and near(now._point[4], lay.points[3].x - 20) and near(now._point[5], -(lay.points[3].y - 18))
        and near(rec._point[4], lay.points[2].x - 35) and near(rec._point[5], -(lay.points[2].y - 18))
    return tagsOk and countExact(parent3, "0") == 1 and countExact(parent3, "1") == 1 and countExact(parent3, "2") == 1
        and countExact(parent3, "now") == 1
        and countExact(parent, "now") == 1 and countExact(parent, "recommended") == 1
        and countExact(parent, "0") == 1 and countExact(parent, "1") == 1 and countExact(parent, "2") == 1
        and countExact(parent, "250") == 1 and countExact(parent, "350") == 1
        and countExact(parent2, "0") == 1 and countExact(parent2, "3") == 1 and countExact(parent2, "1") == 0
        and countExact(parent2, "2") == 0 and countExact(parent2, "recommended") == 0, table.concat(texts(parent), ",")
end)

test("GR-6 hovering a point tells its level and the frame rate; leaving hides the tooltip", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent = newParent()
    local g = graph.new(parent)
    g:draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    local buttons = pointButtons(parent)
    local function hover(b)
        b.scripts.OnEnter(b)
        local lines = { GameTooltip.lines[1], GameTooltip.lines[2] }
        return lines
    end
    local a = hover(buttons[1])
    local recommended = hover(buttons[2])
    local now = hover(buttons[3])
    local shownWhile = GameTooltip.shown
    buttons[3].scripts.OnLeave(buttons[3])
    local shownAfter = GameTooltip.shown
    local odd = r.chartModel(r.choose(entry(4.0, rows("graphicsShadowQuality", 4.0,
        { { "0", -1.5 }, { "1", -0.30 }, { "2", -0.9 }, { "3", 0, current = true } })), 100))
    local parent2 = newParent()
    graph.new(parent2):draw(RECT, odd.graphs[1], odd.axis)
    local doubtful = hover(pointButtons(parent2)[2])
    return #buttons == 3 and a[1] == "Shadow detail: 0" and a[2] == "about 333 fps if only this setting changes"
        and recommended[1] == "Shadow detail: 1" and recommended[2] == "about 278 fps if only this setting changes (recommended)"
        and now[2] == "about 250 fps if only this setting changes (now)" and shownWhile == true and shownAfter == false
        and doubtful[2] == "about 270 fps if only this setting changes (this reading looks off)", tostring(a[2]) .. " / " .. tostring(doubtful[2])
end)

test("GR-7 drawing another graph, clearing, or drawing nothing leaves nothing of the earlier one on screen", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent = newParent()
    local g = graph.new(parent)
    g:draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    local two = r.chartModel(r.choose(entry(4.0, rows("graphicsSSAO", 4.0, { { "0", -0.6 }, { "1", 0, current = true } })), 100))
    g:draw(RECT, two.graphs[1], two.axis)
    local fresh = newParent()
    graph.new(fresh):draw(RECT, two.graphs[1], two.axis)
    local sameAsFresh = #pointButtons(parent) == #pointButtons(fresh) and #shownLines(parent) == #shownLines(fresh)
        and shownTextures(parent) == shownTextures(fresh) and #texts(parent) == #texts(fresh)
    g:clear()
    local cleared = #pointButtons(parent) == 0 and #shownLines(parent) == 0 and shownTextures(parent) == 0 and #texts(parent) == 0
    g:draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    g:draw(RECT, nil, m.axis)
    local nothing = #pointButtons(parent) == 0 and #shownLines(parent) == 0 and shownTextures(parent) == 0 and #texts(parent) == 0
    return sameAsFresh and cleared and nothing and #pointButtons(fresh) == 2, #pointButtons(parent) .. " " .. #pointButtons(fresh)
end)

test("GR-8 a graph with no measured point draws only its axis and raises nothing", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent = newParent()
    local g = graph.new(parent)
    local empty = { cvar = "x", name = "X", points = {}, lines = {} }
    local ok = pcall(g.draw, g, RECT, empty, m.axis)
    local okNoAxis = pcall(g.draw, g, RECT, graphOf(m, "graphicsShadowQuality"), nil)
    return ok and okNoAxis and #pointButtons(parent) == 0 and #shownLines(parent) == 0, tostring(ok) .. tostring(okNoAxis)
end)

test("GR-9 a tag over a point at the top of the axis stays inside the rectangle, clear of the panel's title above it", function()
    local _, graph = boot()
    local parent = newParent()
    local g = graph.new(parent)
    -- the recommended level is the fastest one: its point sits on the top of the axis
    local entry = { cvar = "x", name = "X", lines = {}, points = {
        { value = "0", text = "0", fps = 300, recommended = true }, { value = "1", text = "1", fps = 250, current = true } } }
    local axis = { min = 250, max = 300, step = 50, ticks = { 250, 300 } }
    local rect = { x = 0, y = 18, width = 510, height = 122 }          -- as in the results window: the title sits above y 18
    g:draw(rect, entry, axis)
    local function tagsOk(text)
        local found
        walk(parent, function(frame)
            for _, fs in ipairs(frame.fontStrings) do
                if fs.shown and fs._text == text then found = fs end
            end
        end)
        return found ~= nil and -found._point[5] >= rect.y
    end
    return tagsOk("recommended") and tagsOk("now")
end)

-- The new look and the clicks (spec 2026-11-03-tests-and-results-in-my-settings-design.md M4, M5)
local function rgbOf(e, name) local r, g, b, a = e.ns.skin.color(name) return { r, g, b, a } end
local function hexIs(color, hex)
    return color ~= nil and near(color[1], tonumber(hex:sub(1, 2), 16) / 255) and near(color[2], tonumber(hex:sub(3, 4), 16) / 255)
        and near(color[3], tonumber(hex:sub(5, 6), 16) / 255)
end

test("GR-11 the graph's colours come from the window's palette and every element has its own", function()
    local e, graph = boot()
    local c = graph.COLORS
    local want = { grid = "divider", axis = "border", line = "accentDim", point = "accentLight", hollow = "dim", ring = "bright",
        recommended = "accent", picked = "profileEveryday", pickedCrowd = "profileCrowded" }
    local ok, seen = true, {}
    for key, name in pairs(want) do
        ok = ok and sameColor(c[key], rgbOf(e, name))
        local id = table.concat(c[key] or {}, ",")
        if seen[id] then ok = false end
        seen[id] = true
    end
    return ok and hexIs(c.line, "6f72c8"), tostring(ok)
end)

test("GR-12 points and rings are drawn from the rounded-box pictures: an 8 pixel dot, a 16 pixel ring", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent = newParent()
    graph.new(parent):draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    local dot, ring = marks(parent, "point")[1], marks(parent, "ring")[1]
    local function pictures(frame, file)
        local n = 0
        for _, tex in ipairs(frame.textures) do
            if tex._texture and tex._texture:find(file, 1, true) then n = n + 1 end
        end
        return n
    end
    return dot ~= nil and ring ~= nil and pictures(dot, "fill4.tga") == 4 and pictures(ring, "ring8.tga") == 4 and ring._height == 16,
        tostring(dot and pictures(dot, "fill4.tga")) .. " " .. tostring(ring and pictures(ring, "ring8.tga"))
end)

test("GR-13 a picked point is drawn in the colour of the profile it will be saved to, with the tag your pick, and its tooltip says so", function()
    local _, graph, r = boot()
    local m = r.chartModel(r.withPicks(r.choose(T1(), 250), { graphicsShadowQuality = "0" }))
    local parent, parent2 = newParent(), newParent()
    graph.new(parent):draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis, { pickColor = "everyday" })
    graph.new(parent2):draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis, { pickColor = "crowded" })
    local picked, picked2 = marks(parent, "picked")[1], marks(parent2, "picked")[1]
    local button = pointButtons(parent)[1]
    button.scripts.OnEnter(button)
    return picked ~= nil and sameColor(picked.box.fill._color, graph.COLORS.picked) and picked2 ~= nil
        and sameColor(picked2.box.fill._color, graph.COLORS.pickedCrowd) and countExact(parent, "your pick") == 1
        and countExact(parent, "recommended") == 1 and #marks(parent, "recommended") == 1
        and GameTooltip.lines[2] == "about 333 fps if only this setting changes (your pick)", tostring(GameTooltip.lines[2])
end)

test("GR-14 each point's button is 20 pixels and a click calls onPick with that level; without onPick a click does nothing", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent, parent2 = newParent(), newParent()
    local got = {}
    graph.new(parent):draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis, { onPick = function(value) got[#got + 1] = value end })
    graph.new(parent2):draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    local buttons, buttons2 = pointButtons(parent), pointButtons(parent2)
    local lay = graph.layout(graphOf(m, "graphicsShadowQuality"), m.axis, RECT)
    buttons[1]:Click()
    buttons[3]:Click()
    local inert = pcall(function() buttons2[1]:Click() end)
    return graph.HIT == 20 and buttons[1]._width == 20 and buttons[1]._height == 20 and near(buttons[1]._point[4], lay.points[1].x - 10)
        and #got == 2 and got[1] == "0" and got[2] == "2" and inert and buttons2[1].scripts.OnClick == nil,
        table.concat(got, ",") .. " " .. tostring(buttons[1]._width)
end)

-- The fresh review of 2026-11-03, finding 4: picking the level in use put two tags on one spot.
test("GR-16 a pick of the level in use carries one tag, now, your pick, instead of two over each other", function()
    local _, graph, r = boot()
    local m = r.chartModel(r.withPicks(r.choose(T1(), 250), { graphicsShadowQuality = "2" }))
    local parent = newParent()
    graph.new(parent):draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis, { pickColor = "everyday" })
    return countExact(parent, "now, your pick") == 1 and countExact(parent, "now") == 0 and countExact(parent, "your pick") == 0
        and countExact(parent, "recommended") == 1, table.concat(texts(parent), ",")
end)

test("GR-15 a redraw without onPick takes the click away from a button that had one", function()
    local _, graph, r = boot()
    local m = modelOf(r)
    local parent = newParent()
    local g = graph.new(parent)
    local got = 0
    g:draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis, { onPick = function() got = got + 1 end })
    g:draw(RECT, graphOf(m, "graphicsShadowQuality"), m.axis)
    pointButtons(parent)[1]:Click()
    return got == 0 and pointButtons(parent)[1].scripts.OnClick == nil, tostring(got)
end)

return H.results()
