-- Skin.lua: the flat look of the addon's windows (spec 2026-11-02-flat-hub-window-design.md sections 3 and 7). Widgets are
-- drawn from colour textures and four small corner pictures (the Media folder), with no backdrops and no stock templates, so
-- they look the same in every client. Loaded after UI.lua and before Settings.lua.
local addonName, ns = ...

local skin = {}
ns.skin = skin

-- Palette A (spec H3). The last three are the button states derived from it.
local HEX = {
    fill = "14161b", border = "3a3f4b", divider = "262a33", control = "2f3440", selected = "232850",
    accent = "9a9cff", accentLight = "c9caff", accentDim = "6f72c8", text = "d8dbe3", bright = "eef0f6", dim = "8b90a0",
    warning = "ff9933", danger = "e06060",
    hover = "1b1e28", pressed = "2c3266", textDisabled = "5d6170",
    -- The colour of each profile (spec 2026-11-02-edit-the-profile-in-use-design.md P5).
    profileOriginal = "b4b2a9", profileEveryday = "5dcaa5", profileCrowded = "ef9f27", profileMaximum = "f0997b",
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

-- Rounded boxes (owner request 2026-11-02). The straight parts are colour strips; each corner is a small picture from the
-- addon's Media folder (the top-left corner, flipped by texture coordinates for the other three) tinted to the same colour.
-- There are pictures for two radii only, in pixels: the one for controls and the one for windows.
local MEDIA = "Interface/AddOns/" .. addonName .. "/Media/"
skin.RADIUS = { control = 4, window = 8 }
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local FLIP = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 }, BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 } }

-- A colour strip stretched between two anchors of the frame ({point, x, y} each), with an optional width or height.
local function strip(frame, layer, from, to, width, height)
    local tex = frame:CreateTexture(nil, layer)
    tex:SetPoint(from[1], frame, from[1], from[2], from[3])
    tex:SetPoint(to[1], frame, to[1], to[2], to[3])
    if width then tex:SetWidth(width) end
    if height then tex:SetHeight(height) end
    return tex
end

local function cornerPicture(frame, layer, which, file, radius)
    local tex = frame:CreateTexture(nil, layer)
    tex:SetTexture(file)
    local flip = FLIP[which]
    tex:SetTexCoord(flip[1], flip[2], flip[3], flip[4])
    tex:SetSize(radius, radius)
    tex:SetPoint(which, frame, which, 0, 0)
    return tex
end

-- Textures painted as one: SetColorTexture colours the strips and tints the corner pictures, and remembers the colour.
local function paintSet(strips, pictures)
    local set = {}
    function set:SetColorTexture(r, g, b, a)
        self._color = { r, g, b, a }
        for _, tex in ipairs(strips) do tex:SetColorTexture(r, g, b, a) end
        for _, tex in ipairs(pictures) do tex:SetVertexColor(r, g, b, a) end
    end
    return set
end

-- A rounded fill (under the frame's other textures) and, when `edgeName` is given, a one-pixel rounded edge on top of it, in
-- palette colours.
-- Returns {fill, edge}; each answers SetColorTexture and paints all its pieces, so a widget repaints it like a single texture.
function skin.box(frame, radius, fillName, edgeName)
    local r = radius
    local box = {}
    local fillStrips = {
        strip(frame, "BACKGROUND", { "TOPLEFT", 0, -r }, { "BOTTOMRIGHT", 0, r }),
        strip(frame, "BACKGROUND", { "TOPLEFT", r, 0 }, { "TOPRIGHT", -r, 0 }, nil, r),
        strip(frame, "BACKGROUND", { "BOTTOMLEFT", r, 0 }, { "BOTTOMRIGHT", -r, 0 }, nil, r),
    }
    local fillPictures = {}
    for _, which in ipairs(CORNERS) do
        fillPictures[#fillPictures + 1] = cornerPicture(frame, "BACKGROUND", which, MEDIA .. "fill" .. r .. ".tga", r)
    end
    box.fill = paintSet(fillStrips, fillPictures)
    box.fill:SetColorTexture(skin.color(fillName))
    if edgeName then
        local strips = {
            strip(frame, "BORDER", { "TOPLEFT", r, 0 }, { "TOPRIGHT", -r, 0 }, nil, 1),
            strip(frame, "BORDER", { "BOTTOMLEFT", r, 0 }, { "BOTTOMRIGHT", -r, 0 }, nil, 1),
            strip(frame, "BORDER", { "TOPLEFT", 0, -r }, { "BOTTOMLEFT", 0, r }, 1, nil),
            strip(frame, "BORDER", { "TOPRIGHT", 0, -r }, { "BOTTOMRIGHT", 0, r }, 1, nil),
        }
        local pictures = {}
        for _, which in ipairs(CORNERS) do
            pictures[#pictures + 1] = cornerPicture(frame, "BORDER", which, MEDIA .. "ring" .. r .. ".tga", r)
        end
        box.edge = paintSet(strips, pictures)
        box.edge:SetColorTexture(skin.color(edgeName))
    end
    return box
end

-- A coloured dot: an 8 pixel circle (the rounded box of radius 4 on an 8 pixel frame is four quarter discs), used for the profile
-- colours. dot:SetColorName(name) repaints it.
function skin.dot(parent, colorName)
    local dot = CreateFrame("Frame", nil, parent)
    dot:SetSize(8, 8)
    dot.box = skin.box(dot, skin.RADIUS.control, colorName or "dim")
    function dot:SetColorName(name) self.box.fill:SetColorTexture(skin.color(name)) end
    return dot
end

-- A button: a flat fill and a one-pixel edge, its label centred both ways on one line. States are painted by colour:
-- normal, hover, pressed, selected, disabled.
local function paint(b)
    local state = b.skinState
    local fill, edge, text = "fill", "control", "text"
    if not b:IsEnabled() then
        text = "textDisabled"
        if state.selected then fill, text = "selected", "dim" end      -- a read-only page still shows what the game has
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
    local box = skin.box(b, skin.RADIUS.control, "fill", "control")
    b.bg, b.edges = box.fill, { box.edge }
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

local BAR_INSET = skin.RADIUS.control + 1

function skin.navItem(parent, text, width, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, height)
    row.navItem = true
    row.skinState = { hover = false, pressed = false, selected = false }
    row.bg = skin.box(row, skin.RADIUS.control, "fill").fill
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetColorTexture(skin.color("accent"))
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -BAR_INSET)           -- clear of the rounded corners
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, BAR_INSET)
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

-- A check box: a 16 pixel rounded square with an accent mark when ticked, a dim mark when ticked but disabled, and no hover
-- while disabled.
function skin.check(parent)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(16, 16)
    local shape = skin.box(box, skin.RADIUS.control, "fill", "control")
    local edges = { shape.edge }
    local function newMark(colorName)
        local mark = box:CreateTexture(nil, "OVERLAY")
        mark:SetColorTexture(skin.color(colorName))
        mark:SetSize(8, 8)
        mark:SetPoint("CENTER", box, "CENTER", 0, 0)
        return mark
    end
    box:SetCheckedTexture(newMark("accent"))
    box:SetDisabledCheckedTexture(newMark("dim"))
    box:SetScript("OnEnter", function(self)
        if self:IsEnabled() then for _, tex in ipairs(edges) do tex:SetColorTexture(skin.color("border")) end end
    end)
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
    f.box = skin.box(f, skin.RADIUS.window, "fill", "border")

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT - 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.header = header
    -- The addon's gauge (the minimap button's picture) at the left of the header, the title to its right.
    f.icon = header:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture(MEDIA .. "icon.tga")
    f.icon:SetSize(20, 20)
    f.icon:SetPoint("LEFT", header, "LEFT", 12, 0)
    f.titleText = skin.text(header, "large", "accent")
    f.titleText:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
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
