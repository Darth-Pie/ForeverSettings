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
    local function edge()
        for _, tex in ipairs(b.textures) do
            if tex ~= b.bg and tex._color then return tex._color end
        end
    end
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

return H.results()
