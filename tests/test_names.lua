-- Tests for Names.lua (spec 2026-10-30-words-and-menu-design.md section 3.1): the plain words every window uses.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function names()
    local e = H.boot({}, { fresh = true })
    return e.ns.names
end

-- The spec's table, verbatim (both lighting cvars answer "Light bounce").
local LIGHT = "How light bounces around a scene. The new Forever lighting may change this one."
local WANT = {
    { "graphicsShadowQuality", "Shadow detail", "How sharp and detailed shadows look. Higher looks better and costs a lot of speed." },
    { "graphicsSSAO", "Soft corner shadows", "Soft darkening where things meet, like corners and under objects. Small visual gain, moderate cost." },
    { "graphicsComputeEffects", "Extra effects detail", "Extra effects the graphics card calculates. Hard to notice, moderate cost." },
    { "giQuality", "Light bounce", LIGHT },
    { "graphicsLightMode", "Light bounce", LIGHT },
    { "graphicsLiquidDetail", "Water detail", "How detailed water and other liquids look." },
    { "graphicsTextureResolution", "Texture sharpness", "How crisp surfaces look up close. Costs graphics memory more than speed." },
    { "graphicsGroundClutter", "Grass and plants", "How much grass, flowers and small plants cover the ground." },
    { "groundEffectDensity", "Grass and plants (exact amount)", "The same thing with a finer dial: 48 is sparse, 128 is lush." },
    { "RenderScale", "Picture sharpness", "100% is full sharpness. Lower is faster but blurrier." },
}

test("N1-1 every managed setting has exactly the spec's plain name and one line, and the order lists them all", function()
    local n = names()
    local bad = {}
    for _, row in ipairs(WANT) do
        local name, line = n.get(row[1])
        if name ~= row[2] or line ~= row[3] then bad[#bad + 1] = row[1] .. " -> " .. tostring(name) end
    end
    local order = {}
    for _, cvar in ipairs(n.ORDER or {}) do order[#order + 1] = cvar end
    local want = {}
    for _, row in ipairs(WANT) do want[#want + 1] = row[1] end
    return #bad == 0 and table.concat(order, ",") == table.concat(want, ","), table.concat(bad, "; ") .. " / " .. table.concat(order, ",")
end)

test("N1-2 a lookup ignores case, an unknown name answers itself, and a known name beats a fallback", function()
    local n = names()
    local name, line = n.get("GRAPHICSSHADOWQUALITY")
    local unknown, unknownLine = n.get("noSuchSetting")
    return name == "Shadow detail" and line == WANT[1][3] and unknown == "noSuchSetting" and unknownLine == nil
        and n.label("noSuchSetting", "Fallback") == "Fallback" and n.label("noSuchSetting") == "noSuchSetting"
        and n.label("graphicsSSAO", "Fallback") == "Soft corner shadows", tostring(name) .. " " .. tostring(unknown)
end)

test("N1-3 levels: Picture sharpness is a whole percentage, other settings show their number with the end levels marked", function()
    local n = names()
    return n.level("RenderScale", "0.5") == "50%" and n.level("RenderScale", "0.75") == "75%" and n.level("RenderScale", "0.7") == "70%"
        and n.level("RenderScale", "1") == "100%" and n.level("RenderScale", "1.000000") == "100%"
        and n.level("RenderScale", "0.5", "lowest") == "50%" and n.level("RenderScale", "1", "highest") == "100%"
        and n.level("graphicsShadowQuality", "2") == "2" and n.level("graphicsShadowQuality", "0", "lowest") == "0 (lowest)"
        and n.level("graphicsShadowQuality", "4", "highest") == "4 (highest)" and n.level("groundEffectDensity", "48", "lowest") == "48 (lowest)"
        and n.level("noSuchSetting", "7", "lowest") == "7" and n.level("RenderScale", "abc") == "abc",
        n.level("RenderScale", "0.75") .. " " .. n.level("graphicsShadowQuality", "0", "lowest")
end)

test("N1-4 the progress sentences for each kind of window, and nothing for no progress", function()
    local n = names()
    return n.progress({ phase = "sweep", label = "Ground clutter (raw) 48", cvar = "groundEffectDensity", value = "48" })
            == "Now testing: Grass and plants (exact amount), level 48"
        and n.progress({ phase = "sweep", label = "Render scale 0.5", cvar = "RenderScale", value = "0.5" })
            == "Now testing: Picture sharpness, level 50%"
        and n.progress({ phase = "sweep", label = "Shadows 0" }) == "Now testing: Shadows 0"
        and n.progress({ phase = "baseline", label = "start" }) == "Getting a steady starting speed"
        and n.progress({ phase = "baseline", label = "after Shadows", cvar = "graphicsShadowQuality" })
            == "Checking the speed again after Shadow detail"
        and n.progress({ phase = "control", label = "Render scale", cvar = "RenderScale" }) == "Checking that the test works here"
        and n.progress({ phase = "check", label = "your recommendation" }) == "Checking the result..."
        and n.progress({ phase = "odd", label = "Odd label" }) == "Odd label" and n.progress(nil) == nil,
        tostring(n.progress({ phase = "baseline", label = "start" }))
end)

test("N1-5 the profile texts and the tab notes are the spec's", function()
    local n = names()
    return n.PROFILE.original == "Original: my own settings, hands off" and n.PROFILE.everyday == "Everyday: normal play"
        and n.PROFILE.crowded == "Crowded: raids and busy cities" and n.PROFILE_NOTE.everyday == "Settings for normal play."
        and n.PROFILE_NOTE.crowded == "Settings for raids and busy cities." and n.PROFILE_NOTE.original == nil
end)

test("N1-6 how long ago, and the line that says where and when a result was measured", function()
    local n = names()
    return n.ago(0) == "just now" and n.ago(59) == "just now" and n.ago(-5) == "just now"
        and n.ago(60) == "1 minute ago" and n.ago(119) == "1 minute ago" and n.ago(120) == "2 minutes ago"
        and n.ago(3599) == "59 minutes ago" and n.ago(3600) == "1 hour ago" and n.ago(7200) == "2 hours ago"
        and n.ago(86399) == "23 hours ago" and n.ago(86400) == "1 day ago" and n.ago(259200) == "3 days ago"
        and n.measured("Highmountain", 259200) == "Measured in Highmountain, 3 days ago."
        and n.measured("unknown", 259200) == "Measured 3 days ago." and n.measured(nil, 30) == "Measured just now."
        and n.measured("Stormwind City", nil) == "Measured earlier."
        and n.measured("Stormwind City", 90) == "Measured in Stormwind City, 1 minute ago.", n.ago(3599) .. " " .. n.ago(86399)
end)

test("N1-7 Names.lua runs with no game function available", function()
    local env = { ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, tonumber = tonumber,
        math = math, string = string, table = table, select = select }
    local ns = {}
    local chunk = assert(load(NAMES_SRC, "=Names.lua", "t", env))
    chunk("ForeverSettings", ns)
    return ns.names.get("RenderScale") == "Picture sharpness" and ns.names.level("RenderScale", "0.5") == "50%"
end)

-- Maximum and costs (W3, Task 1): spec 2026-10-30-maximum-and-costs-design.md sections 3.1 and 3.2
test("N2-1 the menu's Maximum item has exactly the spec's words", function()
    local n = names()
    return n.PROFILE.maximum == "Maximum: everything at its highest", tostring(n.PROFILE.maximum)
end)

test("N2-2 how much a setting matters to the picture is said in three words by the ranking's weight", function()
    local n = names()
    return n.matters(10) == "a lot" and n.matters(9) == "a lot" and n.matters(8) == "some" and n.matters(5) == "some"
        and n.matters(4) == "a little" and n.matters(1) == "a little" and n.matters(0) == nil and n.matters(nil) == nil
        and n.matters("x") == nil and n.matters(-3) == nil, tostring(n.matters(8)) .. " " .. tostring(n.matters(4))
end)

return H.results()
