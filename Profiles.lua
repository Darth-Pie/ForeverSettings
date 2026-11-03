-- Profiles.lua: Everyday and Crowded profiles, switched only by the player, with one-click return to the player's
-- own settings (spec 2026-10-29-profiles-design.md). Loaded after Bench.lua and before UI.lua.
local _, ns = ...

local profiles = {}
ns.profiles = profiles

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or _G.SetCVar

-- The settings a profile holds: the ones the benchmark measures. The game rewrites the raw settings derived from
-- them by itself, so those are not held.
profiles.MANAGED = {
    "graphicsShadowQuality", "graphicsSSAO", "graphicsComputeEffects", "giQuality", "graphicsLightMode",
    "graphicsLiquidDetail", "graphicsTextureResolution", "graphicsGroundClutter", "groundEffectDensity", "RenderScale",
}

-- The game's raid and battleground counterpart of each managed setting (RenderScale has none).
profiles.RAID_OF = {
    graphicsShadowQuality = "raidGraphicsShadowQuality",
    graphicsSSAO = "raidGraphicsSSAO",
    graphicsComputeEffects = "raidGraphicsComputeEffects",
    graphicsLiquidDetail = "raidGraphicsLiquidDetail",
    graphicsTextureResolution = "raidGraphicsTextureResolution",
    graphicsGroundClutter = "raidGraphicsGroundClutter",
    groundEffectDensity = "RAIDgroundEffectDensity",
    giQuality = "RAIDgiQuality",
    graphicsLightMode = "raidGraphicsLightMode",
}

-- The key binding (Bindings.xml): the game reads this global for the label in the Key Bindings screen; the group
-- ("ForeverSettings") is the file's category= text.
BINDING_NAME_FOREVERSETTINGS_TOGGLE = "Toggle Everyday / Crowded"

profiles.ORDER = { "original", "everyday", "crowded", "maximum" }
profiles.LABEL = { original = "Original", everyday = "Everyday", crowded = "Crowded", maximum = "Maximum" }

-- The names Original captures: every managed setting, then each one's raid counterpart, in managed order.
function profiles.originalNames()
    local names = {}
    for _, name in ipairs(profiles.MANAGED) do names[#names + 1] = name end
    for _, name in ipairs(profiles.MANAGED) do
        if profiles.RAID_OF[name] then names[#names + 1] = profiles.RAID_OF[name] end
    end
    return names
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- The profiles' part of the saved variables, created on first use; nil before they have loaded.
function profiles.state()
    local db = ns.db()
    if not db then return nil end
    db.profiles = db.profiles or {}
    for _, key in ipairs({ "everyday", "crowded" }) do
        db.profiles[key] = db.profiles[key] or {}
        db.profiles[key].values = db.profiles[key].values or {}
    end
    db.original = db.original or {}
    db.original.values = db.original.values or {}
    db.active = db.active or "original"
    if db.raidToo == nil then db.raidToo = false end
    return db
end

-- First run of this version (spec section 7): the forced list becomes Everyday's values, the old per-setting
-- originals are used only for the names that were forced, and the rest of db.orig is dropped.
function profiles.migrate()
    local db = profiles.state()
    if not db or db.profilesMigrated then return end
    local want, orig = db.want or {}, db.orig or {}
    if next(want) ~= nil then
        db.profiles.everyday.values = copy(want)
        db.active = "everyday"
        db.original.values = profiles.live(profiles.originalNames())
        for name in pairs(want) do
            if orig[name] ~= nil then db.original.values[name] = orig[name] end
        end
    else
        db.active = "original"
    end
    db.orig = nil
    db.profilesMigrated = true
end

-- Maximum (spec 2026-10-30-maximum-and-costs-design.md section 3.1) holds no saved values: every setting the benchmark
-- knows the levels of, at its highest. Returns {cvar = last level} and the settings the client has whose levels are not
-- learned yet (the CVar each of the benchmark's settings is driven by, in its order). A setting with two candidate
-- CVars counts once.
function profiles.maxValues()
    local values, leftOut = {}, {}
    if not ns.bench then return values, leftOut end
    for _, entry in ipairs((ns.bench.resolve())) do values[entry.cvar] = entry.tiers[#entry.tiers] end
    for _, row in ipairs(ns.bench.SETTINGS) do
        for _, cvar in ipairs(row.cvars) do
            if GetCVar(cvar) ~= nil then
                if values[cvar] == nil then leftOut[#leftOut + 1] = cvar end
                break
            end
        end
    end
    return values, leftOut
end

-- Maximum is derived, so levels learned after it was switched on are not in its enforced list until it is derived again:
-- this does that (nothing is written), and is called at every loading screen before the list is applied. The other
-- profiles hold their own values: nothing to do for them.
function profiles.refresh()
    local db = profiles.state()
    if db and db.active == "maximum" then db.want = profiles.plan("maximum").want end
end

-- What switching to `name` would write and enforce, without writing anything (spec section 4, steps 3 and 6):
-- {writes = {cvar = value}, want = {cvar = value}, empty = boolean, skipped = {names}}.
-- A profile is Original plus its own values: a setting it has no value for returns to the Original value (written
-- once, not enforced). Crowded with the raid option on also gets, for each setting it has a value for, the same value
-- on the raid counterpart. A name the client does not have is dropped and listed in `skipped`. Maximum's own values
-- are `profiles.maxValues()`, computed here and never stored.
function profiles.plan(name)
    local plan = { writes = {}, want = {}, empty = false, skipped = {} }
    local db = profiles.state()
    if not db then return plan end
    local original = db.original.values
    if name == "original" then
        for k, v in pairs(original) do plan.writes[k] = v end
    else
        local own
        if name == "maximum" then
            own = profiles.maxValues()
        elseif db.profiles[name] then
            own = db.profiles[name].values
        else
            return plan
        end
        plan.empty = next(own) == nil
        for k, v in pairs(original) do plan.writes[k] = own[k] or v end
        for k, v in pairs(own) do
            plan.writes[k] = v
            plan.want[k] = v
        end
        if name == "crowded" and db.raidToo then
            for k, v in pairs(own) do
                local raid = profiles.RAID_OF[k]
                if raid then
                    plan.writes[raid] = v
                    plan.want[raid] = v
                end
            end
        end
    end
    local missing = {}
    for k in pairs(plan.writes) do
        if GetCVar(k) == nil then missing[#missing + 1] = k end
    end
    table.sort(missing)
    for _, k in ipairs(missing) do
        plan.writes[k] = nil
        plan.want[k] = nil
        plan.skipped[#plan.skipped + 1] = k
    end
    return plan
end

-- Numeric when both values parse as numbers (so "0.750000" equals "0.75"), else plain equality.
local function sameValue(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and y ~= nil and x == y
end

-- The benchmark's tested write order (master presets, menu-level, then raw); alphabetical when it is not loaded.
local function order(names)
    if ns.bench and ns.bench.restore and ns.bench.restore.order then return ns.bench.restore.order(names) end
    local list = {}
    for i, name in ipairs(names) do list[i] = name end
    table.sort(list)
    return list
end

-- A plain name for a setting: the friendly name (Names.lua) when it has one, else the benchmark's row label, else the
-- CVar name.
local function friendly(cvar)
    local label
    if ns.bench and ns.bench.SETTINGS then
        for _, row in ipairs(ns.bench.SETTINGS) do
            for _, name in ipairs(row.cvars) do
                if name:lower() == cvar:lower() then label = row.label end
            end
        end
    end
    if ns.names then return ns.names.label(cvar, label) end
    return label or cvar
end

-- Says `msg` unless the caller asked for silence (the My settings window shows the result in its rows instead).
local function speak(silent, msg)
    if not silent then ns.say(msg) end
end

local function unknownProfile(silent, name)
    speak(silent, "unknown profile '" .. tostring(name) .. "' (original, everyday, crowded or maximum)")
end

-- Maximum holds no values of its own to edit: says so unless `silent` and returns the reason for the caller to pass on.
local function maximumRefusal(silent)
    speak(silent, "Maximum cannot be changed: it always holds every setting at its highest level. Pick Everyday or Crowded first.")
    return "maximum"
end

local function leftOutLine(n)
    if n == 1 then
        return "1 setting stays as it is: the addon has not learned its levels yet. Run Find my best settings once."
    end
    return n .. " settings stay as they are: the addon has not learned their levels yet. Run Find my best settings once."
end

-- True when two planned write lists hold the same names with the same values.
local function sameWrites(a, b)
    for k, v in pairs(a) do
        if b[k] == nil or not sameValue(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- A check, a run or a mark window is measuring: `mark` sets bench.active() but not ns.suspended, so both count.
local function busy()
    return (ns.suspended or (ns.bench and ns.bench.active and ns.bench.active())) and true or false
end

function profiles.active()
    local db = profiles.state()
    return db and db.active or "original"
end

-- Makes `name` the active profile (spec section 4). Returns true and {changed, mismatched = {{cvar, wanted, now}}},
-- or false and "unknown", "combat", "busy" or "nothing" (Maximum with no level learned yet); a plain message has been
-- said.
function profiles.switch(name, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if not profiles.LABEL[name] then
        unknownProfile(silent, name)
        return false, "unknown"
    end
    if InCombatLockdown() then
        speak(silent, "in combat; try again afterwards")
        return false, "combat"
    end
    if busy() then
        speak(silent, "benchmark running; try again afterwards")
        return false, "busy"
    end
    local leftOut
    if name == "maximum" then
        local values
        values, leftOut = profiles.maxValues()
        if next(values) == nil then
            speak(silent, "Maximum has nothing to set yet: run Find my best settings once so the addon learns what each setting can do.")
            return false, "nothing"
        end
    end
    -- Leaving Original: its values are whatever the player has right now.
    if db.active == "original" and name ~= "original" then
        local names = profiles.originalNames()
        for k in pairs(db.original.values) do names[#names + 1] = k end     -- extras recorded by /fset set stay recorded
        db.original.values = profiles.live(names)
    end
    local plan = profiles.plan(name)
    -- Everyday and Crowded can end up holding the same settings (a /fset set on the active profile edits that one):
    -- say so, or "nothing needed changing" looks like a fault.
    local previous = db.active
    local twin = previous ~= name and previous ~= "original" and name ~= "original" and not plan.empty
        and previous ~= "maximum" and name ~= "maximum" and sameWrites(profiles.plan(previous).writes, plan.writes)
    local all, before = {}, {}
    for cvar in pairs(plan.writes) do
        all[#all + 1] = cvar
        before[cvar] = GetCVar(cvar)
    end
    all = order(all)
    -- A menu-level write can make the game rewrite a raw setting, so whether a setting differs is decided at the
    -- moment of its own write, and a second pass puts back whatever a later write moved.
    for _ = 1, 2 do
        for _, cvar in ipairs(all) do
            if not sameValue(GetCVar(cvar), plan.writes[cvar]) then pcall(SetCVar, cvar, plan.writes[cvar]) end
        end
    end
    -- The gate: every planned value is read back from the client.
    local changed, mismatched = 0, {}
    for _, cvar in ipairs(all) do
        local now = GetCVar(cvar)
        if sameValue(now, plan.writes[cvar]) then
            if not sameValue(before[cvar], plan.writes[cvar]) then changed = changed + 1 end
        else
            mismatched[#mismatched + 1] = { cvar = cvar, wanted = plan.writes[cvar], now = now }
        end
    end
    db.active = name
    db.want = plan.want
    for _, m in ipairs(mismatched) do
        speak(silent, friendly(m.cvar) .. " stayed at " .. tostring(m.now) .. " (wanted " .. tostring(m.wanted) .. ")")
    end
    if #plan.skipped > 0 then speak(silent, "skipped (not in this client): " .. table.concat(plan.skipped, ", ")) end
    local label = profiles.LABEL[name]
    local summary = "nothing needed changing"
    if changed > 0 or #mismatched > 0 then
        summary = changed .. " setting" .. (changed == 1 and "" or "s") .. " changed"
    end
    speak(silent, "Profile: " .. label .. " (" .. summary .. ")")
    if name == "maximum" then
        speak(silent, "Maximum includes the sharpest textures, which need plenty of graphics memory.")
        if #leftOut > 0 then speak(silent, leftOutLine(#leftOut)) end
    end
    if plan.empty then
        speak(silent, label .. " has no saved settings yet: choose some in My settings (minimap menu), or set things up in the game "
            .. "and use Save my game's current settings as... in the same menu")
    end
    if twin then
        speak(silent, label .. " holds the same settings as " .. profiles.LABEL[previous] .. " right now: "
            .. "to make them differ, change a setting in My settings (minimap menu)")
    end
    return true, { changed = changed, mismatched = mismatched }
end

-- Says so and returns true when a check, run or mark window is busy.
local function refuseIfBusy(silent)
    if busy() then
        speak(silent, "benchmark running; try again afterwards")
        return true
    end
    return false
end

-- `/fset set <cvar> <value>` (spec section 7): the value goes into the active profile, is enforced and applied. A
-- setting Original has no value for is recorded there first, so that choosing Original puts it back. `silent` says
-- nothing in chat (the My settings window).
function profiles.setValue(cvar, value, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if refuseIfBusy(silent) then return false, "busy" end
    if db.active == "original" then
        speak(silent, "Original is read-only; pick Everyday or Crowded first (/fset profile everyday)")
        return false, "original"
    end
    if db.active == "maximum" then return false, maximumRefusal(silent) end
    if db.original.values[cvar] == nil then
        local live = GetCVar(cvar)
        if live ~= nil then db.original.values[cvar] = live end
    end
    db.profiles[db.active].values[cvar] = value
    db.want = profiles.plan(db.active).want
    speak(silent, "keeping " .. friendly(cvar) .. " at " .. value)
    ns.applyAll(true, silent)
    return true
end

-- `/fset unset <cvar>`: stops holding the value in the active profile; the live value is left as it is.
function profiles.unsetValue(cvar, silent)
    local db = profiles.state()
    if not db then return false end
    if refuseIfBusy(silent) then return false end
    if db.active == "maximum" then return false, maximumRefusal(silent) end
    local profile = db.profiles[db.active]
    if not profile or profile.values[cvar] == nil then
        speak(silent, "'" .. friendly(cvar) .. "' is not in the list")
        return false
    end
    profile.values[cvar] = nil
    db.want = profiles.plan(db.active).want
    speak(silent, "no longer forcing " .. friendly(cvar) .. " (its current value is left as it is)")
    return true
end

-- The My settings window's edit of a named profile. On the profile in use it is `setValue` (stored, enforced and
-- applied); on any other it only stores the value, which is written when that profile is switched on. Returns true,
-- or false and "unavailable", "unknown", "original", "maximum" or "busy".
function profiles.setProfileValue(name, cvar, value, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if not profiles.LABEL[name] then
        unknownProfile(silent, name)
        return false, "unknown"
    end
    if name == "original" then
        speak(silent, "Original is read-only: it holds your own settings from before you first switched")
        return false, "original"
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if db.active == name then return profiles.setValue(cvar, value, silent) end
    if refuseIfBusy(silent) then return false, "busy" end
    db.profiles[name].values[cvar] = value
    return true
end

-- The same for removing a value: false when the profile held none for the setting.
function profiles.unsetProfileValue(name, cvar, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if not profiles.LABEL[name] then
        unknownProfile(silent, name)
        return false, "unknown"
    end
    if name == "original" then
        speak(silent, "Original is read-only: it holds your own settings from before you first switched")
        return false, "original"
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if db.active == name then return profiles.unsetValue(cvar, silent) end
    if refuseIfBusy(silent) then return false, "busy" end
    local profile = db.profiles[name]
    if profile.values[cvar] == nil then
        speak(silent, "'" .. friendly(cvar) .. "' is not in the list")
        return false
    end
    profile.values[cvar] = nil
    return true
end

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

-- Saves the live values of the managed settings that exist into Everyday or Crowded (spec section 5): those values
-- are replaced, extras the profile already holds are kept. Allowed in combat (it only reads). Returns the number of
-- settings saved, or nil and "unknown", "original", "maximum" or "busy".
function profiles.save(name, silent)
    local db = profiles.state()
    if not db then return nil, "unavailable" end
    if not profiles.LABEL[name] then
        unknownProfile(silent, name)
        return nil, "unknown"
    end
    if name == "original" then
        speak(silent, "Original is read-only: it holds your own settings from before you first switched")
        return nil, "original"
    end
    if name == "maximum" then return nil, maximumRefusal(silent) end
    if busy() then
        speak(silent, "benchmark running; try again afterwards")
        return nil, "busy"
    end
    local values = profiles.live(profiles.MANAGED)
    local count = 0
    for k, v in pairs(values) do
        db.profiles[name].values[k] = v
        count = count + 1
    end
    if db.active == name then db.want = profiles.plan(name).want end
    speak(silent, "Saved " .. plural(count, "setting") .. " as " .. profiles.LABEL[name])
    return count
end

-- True when the profile holds any saved settings.
function profiles.hasValues(name)
    local db = profiles.state()
    local profile = db and db.profiles[name]
    return profile ~= nil and next(profile.values) ~= nil
end

-- The recommender's one button: saves a computed set of values into Everyday or Crowded and switches to it. The live
-- values of the managed settings, with `values` laid over them, replace the profile's managed values; extras the
-- profile already holds are kept, as `save` does. Everything that can refuse does so before anything is written.
-- Returns what `switch` returns, or false and "unknown", "original", "maximum", "combat" or "busy" (a plain message has
-- been said, unless `silent`: the results window shows the outcome itself).
function profiles.adopt(name, values, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if not profiles.LABEL[name] then
        unknownProfile(silent, name)
        return false, "unknown"
    end
    if name == "original" then
        speak(silent, "Original is read-only: it holds your own settings from before you first switched")
        return false, "original"
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if InCombatLockdown() then
        speak(silent, "in combat; try again afterwards")
        return false, "combat"
    end
    if busy() then
        speak(silent, "benchmark running; try again afterwards")
        return false, "busy"
    end
    local merged = profiles.live(profiles.MANAGED)
    for cvar, value in pairs(values or {}) do merged[cvar] = value end
    for cvar, value in pairs(merged) do db.profiles[name].values[cvar] = value end
    return profiles.switch(name, silent)
end

-- Sets the option "Crowded also sets the game's raid and battleground graphics"; applies it at once when Crowded is
-- the active profile.
function profiles.setRaid(on)
    local db = profiles.state()
    if not db then return end
    if db.active == "crowded" and (InCombatLockdown() or busy()) then
        -- Applying Crowded would be refused: leave the option as it was (switch says why) instead of saving a choice
        -- that nothing applies.
        profiles.switch("crowded")
        return
    end
    db.raidToo = on and true or false
    if db.raidToo then
        ns.say("Crowded will also set the game's raid and battleground graphics")
    else
        ns.say("Crowded leaves the game's raid and battleground graphics alone")
    end
    if db.active == "crowded" then profiles.switch("crowded") end
end

-- Crowded to Everyday; from anything else to Crowded.
function profiles.toggle()
    if profiles.active() == "crowded" then return profiles.switch("everyday") end
    return profiles.switch("crowded")
end

function profiles.show()
    local db = profiles.state()
    if not db then return end
    ns.say("Profile: " .. profiles.LABEL[db.active] .. " (raid set: " .. (db.raidToo and "also" or "left alone") .. ")")
    for _, key in ipairs({ "everyday", "crowded" }) do
        local n = 0
        for _ in pairs(db.profiles[key].values) do n = n + 1 end
        ns.say(profiles.LABEL[key] .. ": " .. (n == 0 and "no saved settings yet" or plural(n, "setting")))
    end
end

local USAGE = "usage: /fset profile [original | everyday | crowded | maximum | save <name> | raid on|off | toggle]"

-- `/fset profile <rest>`: the word after `profile` picks the action.
function profiles.handle(rest)
    local word, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
    word, arg = word:lower(), arg:lower()
    if word == "" then
        profiles.show()
    elseif profiles.LABEL[word] then
        profiles.switch(word)
    elseif word == "save" then
        if arg == "" then ns.say(USAGE) else profiles.save(arg) end
    elseif word == "raid" and (arg == "on" or arg == "off") then
        profiles.setRaid(arg == "on")
    elseif word == "toggle" then
        profiles.toggle()
    else
        ns.say(USAGE)
    end
end

-- {name = value} for the names the client answers for; a name it does not have is left out, never an error.
function profiles.live(names)
    local values = {}
    for _, name in ipairs(names) do
        local value = GetCVar(name)
        if value ~= nil then values[name] = value end
    end
    return values
end
