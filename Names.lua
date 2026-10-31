-- Names.lua: the plain words every window uses (spec 2026-10-30-words-and-menu-design.md section 3.1). Pure: it reads
-- nothing from the game. Loaded right after ForeverSettings.lua, before everything that shows a setting to a player.
local _, ns = ...

local names = {}
ns.names = names

local LIGHT = "How light bounces around a scene. The new Forever lighting may change this one."

-- {cvar, plain name, one line}, in the order a window lists them.
local ROWS = {
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

names.ORDER = {}
local INFO = {}
for _, row in ipairs(ROWS) do
    names.ORDER[#names.ORDER + 1] = row[1]
    INFO[row[1]:lower()] = { name = row[2], line = row[3] }
end
names.INFO = INFO

-- The game answers setting names without regard to case, so a lookup does too.
local function info(cvar)
    return type(cvar) == "string" and INFO[cvar:lower()] or nil
end

-- The plain name and the one line; a name this table does not know answers itself and no line.
function names.get(cvar)
    local found = info(cvar)
    if found then return found.name, found.line end
    return cvar, nil
end

-- The plain name when there is one, else `fallback`, else the setting's own name.
function names.label(cvar, fallback)
    local found = info(cvar)
    if found then return found.name end
    return fallback or cvar
end

-- A level as a player reads it: Picture sharpness as a whole percentage, any other known setting as its number, with
-- " (lowest)" or " (highest)" added when `position` says so (the My settings window knows a setting's full list).
function names.level(cvar, value, position)
    if value == nil then return nil end
    if type(cvar) == "string" and cvar:lower() == "renderscale" then
        local n = tonumber(value)
        if n then return string.format("%.0f%%", n * 100) end
        return value
    end
    if info(cvar) and position == "lowest" then return value .. " (lowest)" end
    if info(cvar) and position == "highest" then return value .. " (highest)" end
    return value
end

-- What a test is doing, in a sentence, from a progress table {phase, label, cvar, value}.
function names.progress(p)
    if p == nil then return nil end
    if p.phase == "sweep" then
        if p.cvar then
            local text = "Now testing: " .. names.label(p.cvar, p.label)
            if p.value ~= nil then text = text .. ", level " .. names.level(p.cvar, tostring(p.value)) end
            return text
        end
        return "Now testing: " .. tostring(p.label)
    elseif p.phase == "baseline" then
        if p.cvar then return "Checking the speed again after " .. names.label(p.cvar, p.label) end
        return "Getting a steady starting speed"
    elseif p.phase == "control" then
        return "Checking that the test works here"
    elseif p.phase == "check" then
        return "Checking the result..."
    end
    return tostring(p.label)
end

-- The menu's profile texts and the My settings tabs' notes.
names.PROFILE = {
    original = "Original: my own settings, hands off",
    everyday = "Everyday: normal play",
    crowded = "Crowded: raids and busy cities",
    maximum = "Maximum: everything at its highest",
}

-- How much a setting matters to how the game looks, in three words, from its weight in the recommender's ranking
-- (Recommend.RANKING, 1 to 10): the addon's own judgement, not something it measured. nil for anything else.
function names.matters(weight)
    if type(weight) ~= "number" or weight < 1 then return nil end
    if weight >= 9 then return "a lot" end
    if weight >= 5 then return "some" end
    return "a little"
end
names.PROFILE_NOTE = {
    everyday = "Settings for normal play.",
    crowded = "Settings for raids and busy cities.",
}

-- How long ago, in the largest whole unit.
function names.ago(seconds)
    if type(seconds) ~= "number" or seconds < 60 then return "just now" end
    local function unit(n, word) return n .. " " .. word .. (n == 1 and "" or "s") .. " ago" end
    if seconds < 3600 then return unit(math.floor(seconds / 60), "minute") end
    if seconds < 86400 then return unit(math.floor(seconds / 3600), "hour") end
    return unit(math.floor(seconds / 86400), "day")
end

-- Where and when a saved result was measured.
function names.measured(zone, seconds)
    if type(seconds) ~= "number" then return "Measured earlier." end
    local when = names.ago(seconds)
    if type(zone) == "string" and zone ~= "" and zone ~= "unknown" then
        return "Measured in " .. zone .. ", " .. when .. "."
    end
    return "Measured " .. when .. "."
end
