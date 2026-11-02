-- Skin.lua: the flat look of the addon's windows (spec 2026-11-02-flat-hub-window-design.md sections 3 and 7). Widgets are
-- drawn from colour textures only: no backdrops and no stock templates, so they look the same in every client. Loaded after
-- UI.lua and before Settings.lua.
local _, ns = ...

local skin = {}
ns.skin = skin

-- Palette A (spec H3). The last three are the button states derived from it.
local HEX = {
    fill = "14161b", border = "3a3f4b", divider = "262a33", control = "2f3440", selected = "232850",
    accent = "9a9cff", accentLight = "c9caff", text = "d8dbe3", bright = "eef0f6", dim = "8b90a0",
    warning = "ff9933", danger = "e06060",
    hover = "1b1e28", pressed = "2c3266", textDisabled = "5d6170",
}
local ALPHA = { fill = 0.96 }

skin.COLORS = {}
for name, hex in pairs(HEX) do
    skin.COLORS[name] = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
        ALPHA[name] or 1 }
end

-- r, g, b, a of a palette colour, or nothing for a name the palette does not have.
function skin.color(name)
    local c = skin.COLORS[name]
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
end

local HEADER_HEIGHT = 36
local FONTS = { small = "GameFontHighlightSmall", normal = "GameFontNormal", large = "GameFontNormalLarge" }

-- A line of text in a palette colour, left-aligned; `width` (optional) is where it wraps.
function skin.text(parent, size, colorName, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", FONTS[size] or FONTS.normal)
    fs:SetTextColor(skin.color(colorName or "text"))
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    return fs
end

-- A one-pixel line across the parent in the divider colour.
function skin.divider(parent, width)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetColorTexture(skin.color("divider"))
    line:SetHeight(1)
    if width then line:SetWidth(width) end
    return line
end

-- A one-pixel border of four textures around a frame; returns them in the order top, bottom, left, right.
local function addEdges(frame, colorName)
    local function edge(a, b, width, height)
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(skin.color(colorName))
        tex:SetPoint(a, frame, a, 0, 0)
        tex:SetPoint(b, frame, b, 0, 0)
        if width then tex:SetWidth(width) end
        if height then tex:SetHeight(height) end
        return tex
    end
    return { edge("TOPLEFT", "TOPRIGHT", nil, 1), edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1),
        edge("TOPLEFT", "BOTTOMLEFT", 1, nil), edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil) }
end

-- A button: a flat fill and a one-pixel edge, its label centred both ways on one line. States are painted by colour:
-- normal, hover, pressed, selected, disabled.
local function paint(b)
    local state = b.skinState
    local fill, edge, text = "fill", "control", "text"
    if not b:IsEnabled() then
        text = "textDisabled"
    elseif state.pressed then
        fill, edge = "pressed", "accent"
    elseif state.selected then
        fill, edge, text = "selected", "accent", "bright"
    elseif state.hover then
        fill = "hover"
    end
    b.bg:SetColorTexture(skin.color(fill))
    for _, tex in ipairs(b.edges) do tex:SetColorTexture(skin.color(edge)) end
    b.label:SetTextColor(skin.color(text))
end

function skin.button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 24)
    b.skinState = { hover = false, pressed = false, selected = false }
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edges = addEdges(b, "control")
    local label = b:CreateFontString(nil, "OVERLAY", FONTS.small)
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    label:SetWidth(width - 8)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    b.label = label
    b:SetFontString(label)
    b:SetText(text)
    b:SetScript("OnEnter", function(self) self.skinState.hover = true paint(self) end)
    b:SetScript("OnLeave", function(self) self.skinState.hover = false paint(self) end)
    b:SetScript("OnMouseDown", function(self) self.skinState.pressed = true paint(self) end)
    b:SetScript("OnMouseUp", function(self) self.skinState.pressed = false paint(self) end)
    local setEnabled = b.SetEnabled
    function b:SetEnabled(on)
        setEnabled(self, on)
        paint(self)
    end
    function b:SetSelected(on)
        self.skinState.selected = on and true or false
        paint(self)
    end
    function b:SetLabel(label2) self:SetText(label2) end
    paint(b)
    return b
end

-- A row of the page list: no edge, its label at the left; the selected row has the selected fill and a two pixel accent bar.
local function paintRow(row)
    local state = row.skinState
    local fillName, alpha, text = "fill", 0, "text"
    if state.pressed then
        fillName, alpha = "pressed", 1
    elseif state.selected then
        fillName, alpha, text = "selected", 1, "accentLight"
    elseif state.hover then
        fillName, alpha = "hover", 1
    end
    local r, g, b = skin.color(fillName)
    row.bg:SetColorTexture(r, g, b, alpha)
    if state.selected then row.bar:Show() else row.bar:Hide() end
    row.label:SetTextColor(skin.color(text))
end

function skin.navItem(parent, text, width, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, height)
    row.navItem = true
    row.skinState = { hover = false, pressed = false, selected = false }
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetColorTexture(skin.color("accent"))
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    local label = row:CreateFontString(nil, "OVERLAY", FONTS.normal)
    label:SetPoint("LEFT", row, "LEFT", 14, 0)
    label:SetWidth(width - 20)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    row.label = label
    row:SetFontString(label)
    row:SetText(text)
    row:SetScript("OnEnter", function(self) self.skinState.hover = true paintRow(self) end)
    row:SetScript("OnLeave", function(self) self.skinState.hover = false paintRow(self) end)
    row:SetScript("OnMouseDown", function(self) self.skinState.pressed = true paintRow(self) end)
    row:SetScript("OnMouseUp", function(self) self.skinState.pressed = false paintRow(self) end)
    function row:SetSelected(on)
        self.skinState.selected = on and true or false
        paintRow(self)
    end
    function row:SetLabel(text2) self:SetText(text2) end
    paintRow(row)
    return row
end

-- A check box: a 16 pixel square with an accent mark when ticked.
function skin.check(parent)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(16, 16)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(skin.color("fill"))
    local edges = addEdges(box, "control")
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetColorTexture(skin.color("accent"))
    mark:SetSize(8, 8)
    mark:SetPoint("CENTER", box, "CENTER", 0, 0)
    box:SetCheckedTexture(mark)
    box:SetScript("OnEnter", function() for _, tex in ipairs(edges) do tex:SetColorTexture(skin.color("border")) end end)
    box:SetScript("OnLeave", function() for _, tex in ipairs(edges) do tex:SetColorTexture(skin.color("control")) end end)
    return box
end

-- A horizontal slider: a thin track and a flat 10 by 16 thumb.
function skin.slider(parent, name, width, min, max, step)
    local slider = CreateFrame("Slider", name, parent)
    slider:SetSize(width, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(skin.color("control"))
    track:SetHeight(2)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(skin.color("accent"))
    thumb:SetSize(10, 16)
    slider:SetThumbTexture(thumb)
    return slider
end

-- A window: a flat fill, a one-pixel border, a header (title, version, close button) that drags it, and `.page`, the area
-- under the header. Escape closes it. Hidden until shown.
function skin.window(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    local fill = f:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(skin.color("fill"))
    f.edges = addEdges(f, "border")

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT - 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.header = header
    f.titleText = skin.text(header, "large", "accent")
    f.titleText:SetPoint("LEFT", header, "LEFT", 14, 0)
    f.titleText:SetText(title or "")
    f.versionText = skin.text(header, "small", "dim")
    f.versionText:SetPoint("BOTTOMLEFT", f.titleText, "BOTTOMRIGHT", 8, 1)
    local line = skin.divider(f)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -HEADER_HEIGHT)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -HEADER_HEIGHT)

    f.close = skin.button(header, "x", 24, 24)
    f.close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.page = CreateFrame("Frame", nil, f)
    f.page:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(HEADER_HEIGHT + 1))
    f.page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    local listed = false
    for _, listedName in ipairs(UISpecialFrames) do
        if listedName == name then listed = true end
    end
    if not listed and name then tinsert(UISpecialFrames, name) end
    f:Hide()
    return f
end
