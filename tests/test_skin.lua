-- Tests for Skin.lua, the flat widgets of the hub window (spec 2026-11-02-flat-hub-window-design.md sections 3 and 7),
-- driven through the shared harness.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function boot()
    local e = H.boot({ graphicsShadowQuality = "2" }, { fresh = true })
    return e, e.ns.skin
end
local function rgb(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
local function near(a, b) return math.abs(a - b) < 0.0005 end
local function colorIs(color, hex, alpha)
    if type(color) ~= "table" then return false end
    local r, g, b = rgb(hex)
    return near(color[1], r) and near(color[2], g) and near(color[3], b) and near(color[4] or 1, alpha or 1)
end
local function find(f, kind)
    local list = {}
    local function walk(frame)
        if frame.kind == kind then list[#list + 1] = frame end
        for _, child in ipairs(frame.children) do walk(child) end
    end
    walk(f)
    return list
end

-- Palette A of the spec (H3), and the three button states derived from it.
local PALETTE = {
    fill = { "14161b", 0.96 }, border = { "3a3f4b" }, divider = { "262a33" }, control = { "2f3440" }, selected = { "232850" },
    accent = { "9a9cff" }, accentLight = { "c9caff" }, text = { "d8dbe3" }, bright = { "eef0f6" }, dim = { "8b90a0" },
    warning = { "ff9933" }, danger = { "e06060" }, hover = { "1b1e28" }, pressed = { "2c3266" }, textDisabled = { "5d6170" },
}

test("SK-1 the palette is the spec's: every named colour answers its values, and an unknown name answers nothing", function()
    local _, skin = boot()
    local bad = {}
    for name, want in pairs(PALETTE) do
        local r, g, b, a = skin.color(name)
        if not colorIs({ r, g, b, a }, want[1], want[2]) then bad[#bad + 1] = name end
        if not colorIs(skin.COLORS[name], want[1], want[2]) then bad[#bad + 1] = name .. "(table)" end
    end
    return #bad == 0 and skin.color("nosuchcolour") == nil, table.concat(bad, ",")
end)

test("SK-2 a window has its size, a flat fill, a one-pixel border of four textures, a header with title and a close button, and Escape closes it once", function()
    local _, skin = boot()
    local f = skin.window("SkinTestWindow", 780, 560, "ForeverSettings")
    local hiddenAtStart = f.shown == false
    local fill, edges = nil, {}
    for _, tex in ipairs(f.textures) do
        if tex._color and colorIs(tex._color, "14161b", 0.96) then fill = tex end
        if tex._color and colorIs(tex._color, "3a3f4b") then edges[#edges + 1] = tex end
    end
    local oneWide = #edges == 4
    for _, tex in ipairs(edges) do
        if not (tex._width == 1 or tex._height == 1) then oneWide = false end
    end
    local close = f.close
    skin.window("SkinTestWindow", 780, 560, "ForeverSettings")
    local listed = 0
    for _, name in ipairs(UISpecialFrames) do if name == "SkinTestWindow" then listed = listed + 1 end end
    f:Show()
    local before = f.shown
    close:Click()
    return hiddenAtStart and f.name == "SkinTestWindow" and f.template == nil and f._width == 780 and f._height == 560 and fill ~= nil and oneWide
        and f.header ~= nil and f.titleText ~= nil and f.titleText._text == "ForeverSettings"
        and colorIs(f.titleText._textColor, "9a9cff") and close ~= nil and close._text == "x" and before == true and f.shown == false
        and f.page ~= nil and listed == 1, tostring(oneWide) .. " " .. tostring(listed)
end)

test("SK-3 a button centres its label both ways on one line, and shows normal, hover, pressed, selected and disabled by colour", function()
    local _, skin = boot()
    local parent = skin.window("SkinTestWindow2", 400, 300, "t")
    local b = skin.button(parent, "Use what I have in the game now", 230, 26)
    local label = b.label
    local pt = label and label._point
    local centred = pt ~= nil and pt[1] == "CENTER" and label._justifyH == "CENTER" and label._justifyV == "MIDDLE"
        and label._wordWrap == false and label._width == 222 and b._width == 230 and b._height == 26 and b._text == "Use what I have in the game now"
    local function bg() return b.bg._color end
    local function edge() return b.edges[1]._color end
    local normal = colorIs(bg(), "14161b", 0.96) and colorIs(edge(), "2f3440") and colorIs(label._textColor, "d8dbe3")
    b.scripts.OnEnter(b)
    local hover = colorIs(bg(), "1b1e28")
    b.scripts.OnMouseDown(b)
    local pressed = colorIs(bg(), "2c3266") and colorIs(edge(), "9a9cff")
    b.scripts.OnMouseUp(b)
    b.scripts.OnLeave(b)
    local released = colorIs(bg(), "14161b", 0.96)
    b:SetSelected(true)
    local selected = colorIs(bg(), "232850") and colorIs(edge(), "9a9cff") and colorIs(label._textColor, "eef0f6")
    b:SetSelected(false)
    b:SetEnabled(false)
    local disabled = colorIs(bg(), "14161b", 0.96) and colorIs(label._textColor, "5d6170") and colorIs(edge(), "2f3440")
    b.scripts.OnEnter(b)
    local noHoverWhenOff = colorIs(bg(), "14161b", 0.96)
    b:SetEnabled(true)
    b:SetLabel("Close")
    return centred and normal and hover and pressed and released and selected and disabled and noHoverWhenOff and b._text == "Close",
        tostring(centred) .. tostring(normal) .. tostring(hover) .. tostring(pressed) .. tostring(released) .. tostring(selected)
            .. tostring(disabled) .. tostring(noHoverWhenOff)
end)

test("SK-4 a check box and a slider are drawn from textures; the slider keeps its range and step", function()
    local _, skin = boot()
    local parent = skin.window("SkinTestWindow3", 400, 300, "t")
    local box = skin.check(parent)
    local mark
    for _, tex in ipairs(box.textures) do
        if tex._color and colorIs(tex._color, "9a9cff") then mark = tex end
    end
    box:SetChecked(true)
    local slider = skin.slider(parent, "SkinTestSlider", 360, 50, 200, 5)
    local track, thumb
    for _, tex in ipairs(slider.textures) do
        if tex._color and colorIs(tex._color, "2f3440") then track = tex end
        if tex._color and colorIs(tex._color, "9a9cff") then thumb = tex end
    end
    return box._width == 16 and box._height == 16 and mark ~= nil and box:GetChecked() == true and box.template == nil
        and slider.kind == "Slider" and slider.name == "SkinTestSlider" and slider.template == nil and slider._width == 360
        and slider._min == 50 and slider._max == 200 and slider._step == 5 and track ~= nil and thumb ~= nil
        and thumb._width == 10 and thumb._height == 16, tostring(mark) .. tostring(track) .. tostring(thumb)
end)

test("SK-5 no widget asks for a stock template, so a client that lacks one cannot break the window", function()
    local e, skin = boot()
    local f = skin.window("SkinTestWindow4", 500, 400, "t")
    skin.button(f.page, "a", 100, 24)
    skin.check(f.page)
    skin.slider(f.page, "SkinTestSlider2", 200, 0, 10, 1)
    local templated = {}
    local function walk(frame)
        if frame.template ~= nil then templated[#templated + 1] = tostring(frame.kind) .. ":" .. tostring(frame.template) end
        for _, child in ipairs(frame.children) do walk(child) end
    end
    walk(f)
    local text = skin.text(f.page, "small", "dim", 120)
    return #templated == 0 and text._width == 120 and text._justifyH == "LEFT" and colorIs(text._textColor, "8b90a0"), table.concat(templated, ",")
end)

test("SK-6 a page list row is flat: its label sits at the left, a selected row has the selected fill and an accent bar, hover and pressed show by colour", function()
    local _, skin = boot()
    local parent = skin.window("SkinTestWindow5", 400, 300, "t")
    local row = skin.navItem(parent.page, "Light and shadows", 149, 28)
    local label = row.label
    local pt = label and label._point
    local leftAligned = pt ~= nil and pt[1] == "LEFT" and pt[4] == 14 and label._justifyH == "LEFT" and label._justifyV == "MIDDLE"
        and label._wordWrap == false and row._width == 149 and row._height == 28 and row._text == "Light and shadows" and row.navItem == true
    local function bg() return row.bg._color end
    local normal = bg()[4] == 0 and colorIs(label._textColor, "d8dbe3") and row.bar.shown == false
    row.scripts.OnEnter(row)
    local hover = colorIs(bg(), "1b1e28")
    row.scripts.OnMouseDown(row)
    local pressed = colorIs(bg(), "2c3266")
    row.scripts.OnMouseUp(row)
    row.scripts.OnLeave(row)
    row:SetSelected(true)
    local selected = colorIs(bg(), "232850") and row.bar.shown == true and colorIs(row.bar._color, "9a9cff") and row.bar._width == 2
        and colorIs(label._textColor, "c9caff")
    row:SetSelected(false)
    local cleared = bg()[4] == 0 and row.bar.shown == false
    return leftAligned and normal and hover and pressed and selected and cleared,
        tostring(leftAligned) .. tostring(normal) .. tostring(hover) .. tostring(pressed) .. tostring(selected) .. tostring(cleared)
end)

-- Rounded corners (owner request 2026-11-02): a box is solid strips plus four corner pictures from the addon's Media folder,
-- tinted by SetVertexColor, so a fill and a one-pixel edge keep their palette colours and still follow the button states.
local MEDIA = "Interface/AddOns/ForeverSettings/Media/"
local COORDS = { TOPLEFT = "0,1,0,1", TOPRIGHT = "1,0,0,1", BOTTOMLEFT = "0,1,1,0", BOTTOMRIGHT = "1,0,1,0" }
local function describe(tex)
    local parts = {}
    for _, p in ipairs(tex._points or {}) do parts[#parts + 1] = p[1] .. ":" .. p[4] .. ":" .. p[5] end
    return table.concat(parts, ",") .. " w=" .. tostring(tex._width) .. " h=" .. tostring(tex._height)
end
-- The textures of a frame on one layer: the solid strips described, the corners described with their file and coordinates.
local function onLayer(frame, layer)
    local solids, corners = {}, {}
    for _, tex in ipairs(frame.textures) do
        if tex.layer == layer then
            if tex._texture then
                local c = tex._texCoord or {}
                corners[#corners + 1] = describe(tex) .. " " .. tostring(tex._texture) .. " " .. table.concat(c, ",")
            else
                solids[#solids + 1] = describe(tex)
            end
        end
    end
    table.sort(solids)
    table.sort(corners)
    return solids, corners
end
local function sameList(got, want)
    table.sort(want)
    return table.concat(got, " | ") == table.concat(want, " | "), table.concat(got, " | ")
end
local function cornerLines(r, file)
    local list = {}
    for _, which in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        list[#list + 1] = which .. ":0:0 w=" .. r .. " h=" .. r .. " " .. MEDIA .. file .. " " .. COORDS[which]
    end
    return list
end

test("SK-7 a box of radius 4 is a fill of three strips and four corner pictures, and a one-pixel edge of four lines and four ring corners", function()
    local _, skin = boot()
    local f = CreateFrame("Frame", nil, UIParent)
    local box = skin.box(f, 4, "fill", "control")
    local fillSolids, fillCorners = onLayer(f, "BACKGROUND")
    local edgeSolids, edgeCorners = onLayer(f, "BORDER")
    local a, ga = sameList(fillSolids, { "TOPLEFT:0:-4,BOTTOMRIGHT:0:4 w=nil h=nil", "TOPLEFT:4:0,TOPRIGHT:-4:0 w=nil h=4",
        "BOTTOMLEFT:4:0,BOTTOMRIGHT:-4:0 w=nil h=4" })
    local b, gb = sameList(fillCorners, cornerLines(4, "fill4.tga"))
    local c, gc = sameList(edgeSolids, { "TOPLEFT:4:0,TOPRIGHT:-4:0 w=nil h=1", "BOTTOMLEFT:4:0,BOTTOMRIGHT:-4:0 w=nil h=1",
        "TOPLEFT:0:-4,BOTTOMLEFT:0:4 w=1 h=nil", "TOPRIGHT:0:-4,BOTTOMRIGHT:0:4 w=1 h=nil" })
    local d, gd = sameList(edgeCorners, cornerLines(4, "ring4.tga"))
    return a and b and c and d and box.fill ~= nil and box.edge ~= nil, ga .. " /// " .. gb .. " /// " .. gc .. " /// " .. gd
end)

test("SK-8 painting a box paints every piece: solids by colour, corners by tint; a fill-only box has no edge; radius 8 uses the larger pictures", function()
    local _, skin = boot()
    local f = CreateFrame("Frame", nil, UIParent)
    local box = skin.box(f, 4, "fill", "control")
    box.fill:SetColorTexture(0.1, 0.2, 0.3, 0.4)
    box.edge:SetColorTexture(0.5, 0.6, 0.7, 1)
    local function same(c, r, g, b, a) return c ~= nil and c[1] == r and c[2] == g and c[3] == b and c[4] == a end
    local fillOk, edgeOk, fillN, edgeN = true, true, 0, 0
    for _, tex in ipairs(f.textures) do
        if tex.layer == "BACKGROUND" then
            fillN = fillN + 1
            fillOk = fillOk and same(tex._texture and tex._vertex or tex._color, 0.1, 0.2, 0.3, 0.4)
        elseif tex.layer == "BORDER" then
            edgeN = edgeN + 1
            edgeOk = edgeOk and same(tex._texture and tex._vertex or tex._color, 0.5, 0.6, 0.7, 1)
        end
    end
    local remembered = same(box.fill._color, 0.1, 0.2, 0.3, 0.4) and same(box.edge._color, 0.5, 0.6, 0.7, 1)
    local g = CreateFrame("Frame", nil, UIParent)
    local plain = skin.box(g, 4, "fill")
    local solids = onLayer(g, "BORDER")
    local h = CreateFrame("Frame", nil, UIParent)
    skin.box(h, 8, "fill", "border")
    local bigSolids, bigCorners = onLayer(h, "BACKGROUND")
    local _, bigRings = onLayer(h, "BORDER")
    local function has(list, str)
        for _, item in ipairs(list) do if item == str then return true end end
        return false
    end
    local big = sameList(bigCorners, cornerLines(8, "fill8.tga")) and sameList(bigRings, cornerLines(8, "ring8.tga"))
        and has(bigSolids, "TOPLEFT:0:-8,BOTTOMRIGHT:0:8 w=nil h=nil") and has(bigSolids, "TOPLEFT:8:0,TOPRIGHT:-8:0 w=nil h=8")
    return fillN == 7 and edgeN == 8 and fillOk and edgeOk and remembered and plain.edge == nil and #solids == 0 and big == true,
        tostring(fillN) .. tostring(edgeN) .. tostring(fillOk) .. tostring(edgeOk) .. tostring(remembered) .. tostring(plain.edge) .. tostring(big)
end)

test("SK-9 the window is rounded by 8, buttons, check boxes and page rows by 4, and their colours still follow the states", function()
    local _, skin = boot()
    local w = skin.window("SkinTestWindow6", 400, 300, "t")
    local _, windowCorners = onLayer(w, "BACKGROUND")
    local _, windowRings = onLayer(w, "BORDER")
    local win = sameList(windowCorners, cornerLines(8, "fill8.tga")) and sameList(windowRings, cornerLines(8, "ring8.tga"))
    local b = skin.button(w.page, "Save as Everyday", 126, 28)
    local _, buttonCorners = onLayer(b, "BACKGROUND")
    local _, buttonRings = onLayer(b, "BORDER")
    local btn = sameList(buttonCorners, cornerLines(4, "fill4.tga")) and sameList(buttonRings, cornerLines(4, "ring4.tga"))
    local function tints(frame, layer)
        local list = {}
        for _, tex in ipairs(frame.textures) do
            if tex.layer == layer and tex._texture then list[#list + 1] = tex._vertex end
        end
        return list
    end
    local function allColor(list, hex, alpha)
        for _, c in ipairs(list) do if not colorIs(c, hex, alpha) then return false end end
        return #list == 4
    end
    local normal = allColor(tints(b, "BACKGROUND"), "14161b", 0.96) and allColor(tints(b, "BORDER"), "2f3440")
    b.scripts.OnEnter(b)
    local hover = allColor(tints(b, "BACKGROUND"), "1b1e28")
    b.scripts.OnMouseDown(b)
    local pressed = allColor(tints(b, "BACKGROUND"), "2c3266") and allColor(tints(b, "BORDER"), "9a9cff")
    b.scripts.OnMouseUp(b)
    b.scripts.OnLeave(b)
    b:SetSelected(true)
    local selected = allColor(tints(b, "BACKGROUND"), "232850") and allColor(tints(b, "BORDER"), "9a9cff")
    local box = skin.check(w.page)
    local _, boxRings = onLayer(box, "BORDER")
    local tick = sameList(boxRings, cornerLines(4, "ring4.tga"))
    box.scripts.OnEnter(box)
    local tickHover = allColor(tints(box, "BORDER"), "3a3f4b")
    box.scripts.OnLeave(box)
    local tickLeave = allColor(tints(box, "BORDER"), "2f3440")
    local row = skin.navItem(w.page, "Home", 149, 28)
    local _, rowCorners = onLayer(row, "BACKGROUND")
    local _, rowRings = onLayer(row, "BORDER")
    local rowOk = sameList(rowCorners, cornerLines(4, "fill4.tga")) and #rowRings == 0
    local bar = row.bar._points or {}
    local barInset = #bar == 2 and bar[1][1] == "TOPLEFT" and bar[1][5] == -5 and bar[2][1] == "BOTTOMLEFT" and bar[2][5] == 5
    row:SetSelected(true)
    local rowSelected = allColor(tints(row, "BACKGROUND"), "232850")
    return win and btn and normal and hover and pressed and selected and tick and tickHover and tickLeave and rowOk and barInset and rowSelected,
        tostring(win) .. tostring(btn) .. tostring(normal) .. tostring(hover) .. tostring(pressed) .. tostring(selected) .. tostring(tick)
            .. tostring(tickHover) .. tostring(tickLeave) .. tostring(rowOk) .. tostring(barInset) .. tostring(rowSelected)
end)

-- The profile colours and the dot (spec 2026-11-02-edit-the-profile-in-use-design.md P4, P5).
test("SK-10 the four profile colours are in the palette, and a dot is an 8 pixel circle of four corner pictures that can be recoloured", function()
    local _, skin = boot()
    local colours = colorIs(skin.COLORS.profileOriginal, "b4b2a9") and colorIs(skin.COLORS.profileEveryday, "5dcaa5")
        and colorIs(skin.COLORS.profileCrowded, "ef9f27") and colorIs(skin.COLORS.profileMaximum, "f0997b")
    local f = CreateFrame("Frame", nil, UIParent)
    local dot = skin.dot(f, "profileCrowded")
    local corners, tinted = 0, true
    for _, tex in ipairs(dot.textures) do
        if tex._texture then
            corners = corners + 1
            tinted = tinted and colorIs(tex._vertex, "ef9f27") and tex._width == 4 and tex._height == 4
        end
    end
    dot:SetColorName("profileMaximum")
    local recoloured = true
    for _, tex in ipairs(dot.textures) do
        if tex._texture then recoloured = recoloured and colorIs(tex._vertex, "f0997b") end
    end
    return colours and dot._width == 8 and dot._height == 8 and corners == 4 and tinted and recoloured and dot.parent == f,
        tostring(colours) .. tostring(corners) .. tostring(tinted) .. tostring(recoloured)
end)

-- The addon's gauge in the title bar, left of the title (owner request 2026-11-03).
test("SK-12 a window's header shows the gauge icon at 20 pixels at its left, with the title to its right and the version label after the title", function()
    local _, skin = boot()
    local f = skin.window("SkinTestWindow12", 780, 560, "ForeverSettings")
    local icon = f.icon
    local ip, tp, vp = icon and icon._point, f.titleText._point, f.versionText._point
    return icon ~= nil and icon._texture == "Interface/AddOns/ForeverSettings/Media/icon.tga" and icon._width == 20 and icon._height == 20
        and ip ~= nil and ip[1] == "LEFT" and ip[2] == f.header and ip[3] == "LEFT" and ip[4] == 12 and ip[5] == 0
        and tp ~= nil and tp[1] == "LEFT" and tp[2] == icon and tp[3] == "RIGHT" and tp[4] == 8
        and vp ~= nil and vp[2] == f.titleText and vp[3] == "BOTTOMRIGHT",
        tostring(icon and icon._texture) .. " " .. tostring(tp and tp[2] == f.header)
end)

-- A read-only page greys its controls but still shows what the game has (the fresh review of 2026-11-02, finding 1, and spec
-- 2026-11-02-edit-the-profile-in-use-design.md P2).
test("SK-11 a disabled selected button keeps the selected fill with dim text and the plain edge; a disabled check box shows a dim mark and no hover", function()
    local _, skin = boot()
    local parent = skin.window("SkinTestWindow11", 400, 300, "t")
    local b = skin.button(parent, "2", 50, 22)
    b:SetSelected(true)
    b:SetEnabled(false)
    local held = colorIs(b.bg._color, "232850") and colorIs(b.edges[1]._color, "2f3440") and colorIs(b.label._textColor, "8b90a0")
    b:SetSelected(false)
    local plain = colorIs(b.bg._color, "14161b", 0.96) and colorIs(b.label._textColor, "5d6170")
    b:SetSelected(true)
    b:SetEnabled(true)
    local back = colorIs(b.bg._color, "232850") and colorIs(b.edges[1]._color, "9a9cff") and colorIs(b.label._textColor, "eef0f6")
    local box = skin.check(parent)
    local mark, dimMark = box._checkedTexture, box._disabledCheckedTexture
    local marks = mark ~= nil and colorIs(mark._color, "9a9cff") and dimMark ~= nil and dimMark ~= mark and colorIs(dimMark._color, "8b90a0")
        and dimMark._width == 8 and dimMark._height == 8 and dimMark._point ~= nil and dimMark._point[1] == "CENTER"
    local edge
    for _, tex in ipairs(box.textures) do
        if tex._color and colorIs(tex._color, "2f3440") then edge = tex end
    end
    box:SetEnabled(false)
    box.scripts.OnEnter(box)
    local quiet = edge ~= nil and colorIs(edge._color, "2f3440")
    box:SetEnabled(true)
    box.scripts.OnEnter(box)
    local lit = edge ~= nil and colorIs(edge._color, "3a3f4b")
    return held and plain and back and marks and quiet and lit,
        tostring(held) .. tostring(plain) .. tostring(back) .. tostring(marks) .. tostring(quiet) .. tostring(lit)
end)

return H.results()
