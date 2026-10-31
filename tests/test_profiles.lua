-- Tests for Profiles.lua (spec 2026-10-29-profiles-design.md), driven through the shared harness.
local H = assert(load(HARNESS_SRC, "=harness"))()
local test = H.test

local function boot(cvars, opts)
    opts = opts or {}
    opts.fresh = true
    local e = H.boot(cvars, opts)
    return e, e.ns.profiles, e.ns.bench
end
local function outText() return table.concat(OUT, " | ") end

local MANAGED = { "graphicsShadowQuality", "graphicsSSAO", "graphicsComputeEffects", "giQuality", "graphicsLightMode",
    "graphicsLiquidDetail", "graphicsTextureResolution", "graphicsGroundClutter", "groundEffectDensity", "RenderScale" }
local RAID_OF = {
    graphicsShadowQuality = "raidGraphicsShadowQuality", graphicsSSAO = "raidGraphicsSSAO",
    graphicsComputeEffects = "raidGraphicsComputeEffects", graphicsLiquidDetail = "raidGraphicsLiquidDetail",
    graphicsTextureResolution = "raidGraphicsTextureResolution", graphicsGroundClutter = "raidGraphicsGroundClutter",
    groundEffectDensity = "RAIDgroundEffectDensity", giQuality = "RAIDgiQuality", graphicsLightMode = "raidGraphicsLightMode",
}
-- A client with every managed setting and its raid counterpart.
local function fullCvars()
    local cv = {}
    for i, name in ipairs(MANAGED) do
        cv[name] = tostring(i)
        if RAID_OF[name] then cv[RAID_OF[name]] = tostring(100 + i) end
    end
    return cv
end

-- Task 1: the tables, live and originalNames
test("P1-1 the managed list and the raid table are the spec's, and every name is a known, guarded CVar", function()
    local e, p, b = boot({})
    local problems = {}
    if table.concat(p.MANAGED, ",") ~= table.concat(MANAGED, ",") then problems[#problems + 1] = "managed order" end
    local pairsSeen = 0
    for k, v in pairs(p.RAID_OF) do
        pairsSeen = pairsSeen + 1
        if RAID_OF[k] ~= v then problems[#problems + 1] = "raid " .. k end
    end
    if pairsSeen ~= 9 then problems[#problems + 1] = "raid pairs " .. pairsSeen end
    if p.RAID_OF.RenderScale ~= nil then problems[#problems + 1] = "RenderScale has a raid counterpart" end
    local known = {}
    for _, name in ipairs(e.ns.knownCVars) do known[name:lower()] = true end
    local all = {}
    for _, name in ipairs(p.MANAGED) do all[#all + 1] = name end
    for _, name in pairs(p.RAID_OF) do all[#all + 1] = name end
    for _, name in ipairs(all) do
        if not known[name:lower()] then problems[#problems + 1] = "not known: " .. name end
        if not b.restore.isGuarded(name) then problems[#problems + 1] = "not guarded: " .. name end
    end
    return #problems == 0, table.concat(problems, "; ")
end)

test("P1-2 live() returns only settings the client answers for, with their live values", function()
    local _, p = boot({ graphicsShadowQuality = "4", graphicsSSAO = "3", groundEffectDensity = "64", RenderScale = "1" })
    local got = p.live(p.originalNames())
    local keys = {}
    for k in pairs(got) do keys[#keys + 1] = k end
    table.sort(keys)
    return table.concat(keys, ",") == "RenderScale,graphicsSSAO,graphicsShadowQuality,groundEffectDensity"
        and got.graphicsShadowQuality == "4" and got.RenderScale == "1" and got.giQuality == nil, table.concat(keys, ",")
end)

test("P1-3 originalNames() is the ten managed names then the nine raid counterparts, 19 unique names", function()
    local _, p = boot({})
    local names = p.originalNames()
    local seen, dup = {}, false
    for _, n in ipairs(names) do
        if seen[n] then dup = true end
        seen[n] = true
    end
    local expected = {}
    for _, n in ipairs(MANAGED) do expected[#expected + 1] = n end
    for _, n in ipairs(MANAGED) do if RAID_OF[n] then expected[#expected + 1] = RAID_OF[n] end end
    return #names == 19 and not dup and table.concat(names, ",") == table.concat(expected, ","), #names .. " names"
end)

test("P1-4 a second boot sees none of the first boot's profiles state", function()
    local _, p1 = boot({})
    p1.marker = 1
    local _, p2 = boot({})
    return p2.marker == nil
end)

-- Task 2: saved state and first-run migration
local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
-- Boots with the given saved variables already in place (as the game does before ADDON_LOADED).
local function bootWith(saved, cvars)
    local e = H.boot(cvars, { noload = true, fresh = true })
    _G.ForeverSettingsDB = saved
    e.fire("ADDON_LOADED", "ForeverSettings")
    return e, e.ns.profiles, ForeverSettingsDB
end

test("P2-1 state() is nil before the saved variables load and a complete table after", function()
    local e0 = H.boot({}, { noload = true, fresh = true })
    local before = e0.ns.profiles.state()
    local e1, p1 = boot({ graphicsSSAO = "3" })
    local st = p1.state()
    return before == nil and st ~= nil and st == ForeverSettingsDB and type(st.profiles.everyday.values) == "table"
        and type(st.profiles.crowded.values) == "table" and type(st.original.values) == "table" and st.raidToo == false
        and type(st.active) == "string"
end)

test("P2-2 migration of the 0.1 defaults: the forced entry becomes Everyday, Original is the live values, db.orig goes", function()
    local _, p, _ = boot({ groundEffectDensity = "48", graphicsSSAO = "3" })
    local db = p.state()
    return db.active == "everyday" and deepEqual(db.profiles.everyday.values, { groundEffectDensity = "64" })
        and db.original.values.groundEffectDensity == "48" and db.original.values.graphicsSSAO == "3"
        and db.orig == nil and db.want.groundEffectDensity == "64" and db.want ~= db.profiles.everyday.values and db.profilesMigrated == true,
        tostring(db.active)
end)

test("P2-3 a stale db.orig with an empty forced list is discarded and the player starts on Original", function()
    local _, p, db = bootWith({ want = {}, orig = { graphicsShadowQuality = "2" } }, { graphicsShadowQuality = "4" })
    return db.active == "original" and next(db.original.values) == nil and db.orig == nil and next(db.want) == nil
end)

test("P2-4 db.orig supplies Original only for names that were forced", function()
    local _, p, db = bootWith({ want = { groundEffectDensity = "64", graphicsSSAO = "2" },
        orig = { groundEffectDensity = "48", graphicsLiquidDetail = "1" } },
        { groundEffectDensity = "64", graphicsSSAO = "2", graphicsLiquidDetail = "2" })
    return deepEqual(db.original.values, { groundEffectDensity = "48", graphicsSSAO = "2", graphicsLiquidDetail = "2" })
        and db.active == "everyday" and deepEqual(db.profiles.everyday.values, { groundEffectDensity = "64", graphicsSSAO = "2" })
end)

test("P2-5 a second start on the same saved variables changes nothing, even when the live values have moved", function()
    local _, p1 = boot({ groundEffectDensity = "48", graphicsSSAO = "3" })
    local d1 = p1.state()
    local snap = { profiles = d1.profiles, active = d1.active, original = d1.original }
    local copy = {}
    local function clone(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and clone(v) or v end return c end
    copy.profiles, copy.active, copy.original = clone(snap.profiles), snap.active, clone(snap.original)
    local e2 = H.boot({ groundEffectDensity = "64", graphicsSSAO = "1" }, {})   -- same saved variables, new live values
    local d2 = e2.ns.profiles.state()
    return deepEqual(d2.profiles, copy.profiles) and d2.active == copy.active and deepEqual(d2.original, copy.original)
end)

-- Task 3: the plan (target values and enforced list)
-- over.cvars adds or overrides live settings, over.remove drops some; the saved profiles are then set directly.
local function planSetup(over)
    local cv = fullCvars()
    for k, v in pairs(over.cvars or {}) do cv[k] = v end
    for _, k in ipairs(over.remove or {}) do cv[k] = nil end
    local e, p = boot(cv)
    local db = p.state()
    db.original.values = over.original or {}
    db.profiles.everyday.values = over.everyday or {}
    db.profiles.crowded.values = over.crowded or {}
    db.raidToo = over.raidToo or false
    return p, db
end

test("P3-1 Original: the captured values, nothing enforced", function()
    local p = planSetup({ original = { graphicsShadowQuality = "4", graphicsSSAO = "4", raidGraphicsShadowQuality = "3" } })
    local plan = p.plan("original")
    return deepEqual(plan.writes, { graphicsShadowQuality = "4", graphicsSSAO = "4", raidGraphicsShadowQuality = "3" })
        and next(plan.want) == nil and plan.empty == false and #plan.skipped == 0
end)

test("P3-2 a profile's own value wins, a missing one falls back to Original, and only its own values are enforced", function()
    local p = planSetup({ original = { graphicsShadowQuality = "4", graphicsSSAO = "4" }, everyday = { graphicsShadowQuality = "1" } })
    local plan = p.plan("everyday")
    return deepEqual(plan.writes, { graphicsShadowQuality = "1", graphicsSSAO = "4" })
        and deepEqual(plan.want, { graphicsShadowQuality = "1" }) and plan.empty == false
end)

test("P3-3 Crowded with the raid option off: the raid settings go back to Original and are not enforced", function()
    local p = planSetup({ original = { graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" },
        crowded = { graphicsShadowQuality = "1" }, raidToo = false })
    local plan = p.plan("crowded")
    return plan.writes.raidGraphicsShadowQuality == "3" and plan.writes.graphicsShadowQuality == "1"
        and plan.want.raidGraphicsShadowQuality == nil and deepEqual(plan.want, { graphicsShadowQuality = "1" })
end)

test("P3-4 Crowded with the raid option on mirrors only the settings it has a value for", function()
    local p = planSetup({ original = { graphicsShadowQuality = "4", graphicsSSAO = "4", raidGraphicsShadowQuality = "3", raidGraphicsSSAO = "3" },
        crowded = { graphicsShadowQuality = "1" }, raidToo = true })
    local plan = p.plan("crowded")
    return plan.writes.raidGraphicsShadowQuality == "1" and plan.want.raidGraphicsShadowQuality == "1"
        and plan.writes.raidGraphicsSSAO == "3" and plan.want.raidGraphicsSSAO == nil and plan.writes.graphicsSSAO == "4"
end)

test("P3-5 Everyday never mirrors to the raid set, even with the option on", function()
    local p = planSetup({ original = { graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" },
        everyday = { graphicsShadowQuality = "1" }, raidToo = true })
    local plan = p.plan("everyday")
    return plan.writes.raidGraphicsShadowQuality == "3" and plan.want.raidGraphicsShadowQuality == nil
end)

test("P3-6 an extra setting is written and enforced by its profile and restored by Original", function()
    local p = planSetup({ cvars = { maxFPS = "0" }, original = { graphicsShadowQuality = "4", maxFPS = "0" },
        everyday = { maxFPS = "144" } })
    local plan, back = p.plan("everyday"), p.plan("original")
    return plan.writes.maxFPS == "144" and plan.want.maxFPS == "144" and back.writes.maxFPS == "0" and back.want.maxFPS == nil
end)

test("P3-7 a setting the client does not have is skipped, listed, and does not block the rest", function()
    local p = planSetup({ remove = { "giQuality", "RAIDgiQuality" }, original = { graphicsSSAO = "4" },
        crowded = { giQuality = "2", graphicsSSAO = "1" } })
    local plan = p.plan("crowded")
    local listed = false
    for _, n in ipairs(plan.skipped) do if n == "giQuality" then listed = true end end
    return plan.writes.giQuality == nil and plan.want.giQuality == nil and listed and plan.writes.graphicsSSAO == "1"
        and plan.want.graphicsSSAO == "1"
end)

test("P3-8 empty is true only for a saved profile with no values", function()
    local p = planSetup({ original = { graphicsSSAO = "4" }, crowded = { graphicsSSAO = "1" } })
    return p.plan("everyday").empty == true and p.plan("crowded").empty == false and p.plan("original").empty == false
end)

test("P3-9 plan() changes nothing: no setting is written and the saved state is untouched", function()
    local p, db = planSetup({ original = { graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" },
        everyday = { graphicsShadowQuality = "1" }, crowded = { graphicsShadowQuality = "2" }, raidToo = true })
    local function clone(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and clone(v) or v end return c end
    local before = clone(db)
    SETLOG = {}
    p.plan("original"); p.plan("everyday"); p.plan("crowded")
    return #SETLOG == 0 and deepEqual(before, db)
end)

-- Task 4: switch and undo
local function has(sub)
    for _, l in ipairs(OUT) do
        if l:find(sub, 1, true) then return true end
    end
    return false
end
local function count(sub)
    local n = 0
    for _, l in ipairs(OUT) do
        if l:find(sub, 1, true) then n = n + 1 end
    end
    return n
end
-- A game whose saved variables are empty (the player starts on Original) with the given live settings.
local function clean(cvars)
    local e, p, db = bootWith({ want = {} }, cvars)
    OUT = {}
    SETLOG = {}
    return e, p, db, e.ns.bench
end
local function copyOf(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

test("P4-1 a switch in combat is refused, writes nothing and says so once", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    COMBAT = true
    local ok, why = p.switch("crowded")
    return ok == false and why == "combat" and db.active == "original" and #SETLOG == 0 and CVARS.graphicsShadowQuality == "4"
        and count("in combat; try again afterwards") == 1, outText()
end)

test("P4-2 a switch while a check or run has suspended the addon is refused", function()
    local e, p, db = clean({ graphicsShadowQuality = "4" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    e.ns.suspended = true
    local ok, why = p.switch("crowded")
    return ok == false and why == "busy" and #SETLOG == 0 and db.active == "original"
        and count("benchmark running; try again afterwards") == 1, outText()
end)

test("P4-3 a switch while a mark window runs is refused even though the addon is not suspended", function()
    local e, p, db, b = clean({ graphicsShadowQuality = "4" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    b.mark("m")
    local precondition = e.ns.suspended == false and b.active() == true
    OUT = {}
    local ok, why = p.switch("crowded")
    return precondition and ok == false and why == "busy" and #SETLOG == 0 and db.active == "original", outText()
end)

test("P4-4 leaving Original captures the live values, and nothing else replaces Original", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "4", raidGraphicsShadowQuality = "3", RenderScale = "1" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    p.switch("crowded")
    local first = deepEqual(db.original.values, { graphicsShadowQuality = "4", graphicsSSAO = "4", raidGraphicsShadowQuality = "3", RenderScale = "1" })
    CVARS.graphicsShadowQuality = "2"                      -- a hand edit while Crowded is active
    p.switch("everyday")
    local kept = db.original.values.graphicsShadowQuality == "4"
    p.switch("original")
    local back = CVARS.graphicsShadowQuality == "4"
    CVARS.graphicsShadowQuality = "3"                      -- a hand edit while on Original
    p.switch("crowded")
    return first and kept and back and db.original.values.graphicsShadowQuality == "3",
        tostring(first) .. tostring(kept) .. tostring(back) .. tostring(db.original.values.graphicsShadowQuality)
end)

test("P4-5 only settings whose live value differs are written, menu-level before raw, and the count is said", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", groundEffectDensity = "64", graphicsSSAO = "4" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1", groundEffectDensity = "48", graphicsSSAO = "4" }
    local ok, info = p.switch("crowded")
    return ok and info.changed == 2 and table.concat(SETLOG, ",") == "graphicsShadowQuality,groundEffectDensity"
        and has("Profile: Crowded (2 settings changed)"), table.concat(SETLOG, ",") .. " / " .. outText()
end)

test("P4-6 a setting the game will not keep is reported in plain words and does not count as changed", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    SETFAIL.graphicsShadowQuality = "clamp"
    local ok, info = p.switch("crowded")
    return ok == true and info.changed == 0 and #info.mismatched == 1 and info.mismatched[1].cvar == "graphicsShadowQuality"
        and info.mismatched[1].wanted == "1" and info.mismatched[1].now == "4"
        and has("Shadow detail stayed at 4 (wanted 1)") and has("Profile: Crowded (0 settings changed)"), outText()
end)

test("P4-6b a raw setting the game rewrites by itself is not reported as a problem", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", shadowTextureSize = "2048" })
    DERIVED.graphicsShadowQuality = function(_, all) all.shadowTextureSize = "512" end
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    local ok, info = p.switch("crowded")
    return ok and #info.mismatched == 0 and not has("shadowTextureSize") and not has("stayed"), outText()
end)

test("P4-7 undo: choosing Original puts every value back, checked by a live read, and enforces nothing", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "4", RenderScale = "1" })
    local before = copyOf(CVARS)
    db.profiles.everyday.values = { graphicsShadowQuality = "1", graphicsSSAO = "2" }
    p.switch("everyday")
    local changed = CVARS.graphicsShadowQuality == "1" and CVARS.graphicsSSAO == "2"
    local ok, info = p.switch("original")
    return changed and ok and #info.mismatched == 0 and deepEqual(CVARS, before) and next(db.want) == nil and db.active == "original"
end)

test("P4-8 the enforced list is the profile's own values plus mirrored raid values, and the loading screen puts one back", function()
    local e, p, db = clean({ graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3", graphicsSSAO = "4", raidGraphicsSSAO = "3" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    db.raidToo = true
    p.switch("crowded")
    local listed = deepEqual(db.want, { graphicsShadowQuality = "1", raidGraphicsShadowQuality = "1" })
    CVARS.graphicsShadowQuality = "3"
    OUT = {}
    e.fire("PLAYER_ENTERING_WORLD")
    return listed and CVARS.graphicsShadowQuality == "1" and has("graphicsShadowQuality 3 -> 1") and CVARS.graphicsSSAO == "4",
        tostring(listed) .. " / " .. outText()
end)

test("P4-9 switching to the profile that is already active changes nothing and does not recapture Original", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    p.switch("crowded")
    db.original.values.graphicsShadowQuality = "99"        -- a marker: a recapture would overwrite it
    OUT = {}
    local ok, info = p.switch("crowded")
    return ok and info.changed == 0 and db.original.values.graphicsShadowQuality == "99"
        and has("Profile: Crowded (nothing needed changing)"), outText()
end)

test("P4-10 leaving Crowded with the raid option on returns the raid settings to Original", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    db.raidToo = true
    p.switch("crowded")
    local mirrored = CVARS.raidGraphicsShadowQuality == "1"
    p.switch("everyday")
    return mirrored and CVARS.raidGraphicsShadowQuality == "3" and CVARS.graphicsShadowQuality == "4"
end)

test("P4-11 after a reload the active profile, its list and Original agree, and the loading screen re-applies it", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    db.raidToo = true
    p.switch("crowded")
    -- the same saved variables; the game's settings are back as they were (as after a crash)
    local e2 = H.boot({ graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" }, {})
    local db2 = e2.ns.profiles.state()
    local kept = db2.active == "crowded" and deepEqual(db2.want, { graphicsShadowQuality = "1", raidGraphicsShadowQuality = "1" })
    e2.fire("PLAYER_ENTERING_WORLD")
    return kept and CVARS.graphicsShadowQuality == "1" and CVARS.raidGraphicsShadowQuality == "1"
        and db2.original.values.graphicsShadowQuality == "4" and db2.active == "crowded"
end)

test("P4-12 an unknown profile name is refused in plain words, and an empty profile says it has nothing saved", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    local ok, why = p.switch("nope")
    local refused = ok == false and why == "unknown" and has("unknown profile 'nope' (original, everyday, crowded or maximum)")
        and #SETLOG == 0 and db.active == "original"
    OUT = {}
    local ok2 = p.switch("everyday")
    return refused and ok2 == true and db.active == "everyday" and next(db.want) == nil
        and has("Everyday has no saved settings yet: choose some in My settings (minimap menu), or set things up in the game "
            .. "and use Save my game's current settings as... in the same menu"), outText()
end)

test("P4-13 a setting the client lacks is skipped with a plain note and the rest still applies", function()
    local _, p, db = clean({ graphicsSSAO = "4" })         -- no giQuality, as on retail
    db.profiles.crowded.values = { giQuality = "2", graphicsSSAO = "1" }
    local ran, ok = pcall(p.switch, "crowded")
    local noted = has("skipped (not in this client): giQuality")
    OUT = {}
    db.profiles.everyday.values = { graphicsSSAO = "3" }
    p.switch("everyday")
    return ran and ok == true and CVARS.graphicsSSAO == "3" and CVARS.giQuality == nil and noted and not has("skipped"), outText()
end)

-- Task 5: the /fset profile commands
local USAGE = "usage: /fset profile [original | everyday | crowded | maximum | save <name> | raid on|off | toggle]"

test("P5-1 each /fset profile word reaches its function, and an unknown word prints the usage line", function()
    local e, _, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3" })
    e.slash("profile everyday")
    local a = db.active == "everyday"
    OUT = {}
    e.slash("profile bogus")
    local usage = count(USAGE) == 1
    e.slash("profile save crowded")
    local saved = db.profiles.crowded.values.graphicsShadowQuality == "4"
    e.slash("profile raid on")
    local raid = db.raidToo == true
    e.slash("profile toggle")
    return a and usage and saved and raid and db.active == "crowded", outText()
end)

test("P5-1b without the profiles module the route says so", function()
    local e = H.boot({ graphicsSSAO = "3" }, { fresh = true, profiles = false })
    OUT = {}
    e.slash("profile everyday")
    return count("profiles module not loaded") == 1, outText()
end)

test("P5-2 save captures only the managed settings that exist, replaces them and keeps extras", function()
    local _, p, db = clean({ graphicsShadowQuality = "2", graphicsSSAO = "3", maxFPS = "60", raidGraphicsShadowQuality = "3" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1", maxFPS = "144" }
    local n = p.save("crowded")
    return n == 2 and deepEqual(db.profiles.crowded.values, { graphicsShadowQuality = "2", graphicsSSAO = "3", maxFPS = "144" })
        and has("Saved 2 settings as Crowded"), tostring(n) .. " / " .. outText()
end)

test("P5-2b save refuses Original and a busy benchmark", function()
    local e, p, db = clean({ graphicsShadowQuality = "2" })
    local n1, why1 = p.save("original")
    local readOnly = n1 == nil and why1 == "original"
        and has("Original is read-only: it holds your own settings from before you first switched")
    OUT = {}
    e.ns.suspended = true
    local n2, why2 = p.save("everyday")
    return readOnly and n2 == nil and why2 == "busy" and next(db.profiles.everyday.values) == nil
        and has("benchmark running; try again afterwards"), outText()
end)

test("P5-2c save works in combat, and the enforced list follows when that profile is active", function()
    local _, p, db = clean({ graphicsShadowQuality = "2", graphicsSSAO = "3", maxFPS = "60" })
    db.profiles.crowded.values = { maxFPS = "144" }
    db.active = "crowded"
    COMBAT = true
    local n = p.save("crowded")
    return n == 2 and deepEqual(db.want, db.profiles.crowded.values) and db.want.graphicsShadowQuality == "2"
        and db.want.maxFPS == "144", tostring(n)
end)

test("P5-3 the raid option applies at once when Crowded is active, and only saves the choice otherwise", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    db.profiles.everyday.values = {}
    p.switch("everyday")
    SETLOG = {}
    OUT = {}
    p.setRaid(true)
    local savedOnly = db.raidToo == true and #SETLOG == 0 and has("Crowded will also set the game's raid and battleground graphics")
    p.switch("crowded")
    local viaOn = CVARS.raidGraphicsShadowQuality == "1"
    OUT = {}
    p.setRaid(false)
    local viaOff = CVARS.raidGraphicsShadowQuality == "3" and has("Crowded leaves the game's raid and battleground graphics alone")
    p.setRaid(true)
    return savedOnly and viaOn and viaOff and CVARS.raidGraphicsShadowQuality == "1" and db.raidToo == true,
        tostring(savedOnly) .. tostring(viaOn) .. tostring(viaOff)
end)

test("P5-4 toggle: Crowded to Everyday, Everyday to Crowded, Original to Crowded", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    p.toggle()
    local a = db.active == "crowded"
    p.toggle()
    local b = db.active == "everyday"
    p.toggle()
    local c = db.active == "crowded"
    p.switch("original")
    p.toggle()
    return a and b and c and db.active == "crowded"
end)

test("P5-5 show prints the active profile, the raid option and each profile's size", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    db.profiles.everyday.values = { graphicsShadowQuality = "1", graphicsSSAO = "2" }
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    OUT = {}
    p.show()
    local first = has("Profile: Original (raid set: left alone)") and has("Everyday: 2 settings") and has("Crowded: 1 setting")
    db.profiles.crowded.values = {}
    db.raidToo = true
    db.active = "crowded"
    OUT = {}
    p.show()
    return first and has("Profile: Crowded (raid set: also)") and has("Crowded: no saved settings yet"), outText()
end)

-- Task 6: /fset set, unset and reset edit the active profile; db.orig is gone
local READ_ONLY = "Original is read-only; pick Everyday or Crowded first (/fset profile everyday)"

test("P6-1 /fset set on Original is refused in plain words and writes nothing", function()
    local e, _, db = clean({ graphicsShadowQuality = "4" })
    e.slash("set graphicsShadowQuality 2")
    return count(READ_ONLY) == 1 and next(db.want) == nil and #SETLOG == 0 and CVARS.graphicsShadowQuality == "4"
        and next(db.profiles.everyday.values) == nil, outText()
end)

test("P6-2 /fset set on a profile saves the value in it, enforces it and applies it", function()
    local e, _, db = clean({ graphicsShadowQuality = "4" })
    e.slash("profile everyday")
    e.slash("set graphicsShadowQuality 2")
    return deepEqual(db.profiles.everyday.values, { graphicsShadowQuality = "2" })
        and deepEqual(db.want, { graphicsShadowQuality = "2" }) and CVARS.graphicsShadowQuality == "2" and has("keeping Shadow detail at 2"), outText()
end)

test("P6-3 an extra setting added with /fset set is recorded in Original and put back by Original", function()
    local e, p, db = clean({ graphicsShadowQuality = "4", maxFPS = "60" })
    e.slash("profile everyday")
    e.slash("set maxFPS 144")
    local recorded = db.original.values.maxFPS == "60" and CVARS.maxFPS == "144"
    p.switch("original")
    return recorded and CVARS.maxFPS == "60" and db.active == "original", outText()
end)

test("P6-4 /fset unset removes the value from the profile and the list and leaves the live value", function()
    local e, _, db = clean({ graphicsShadowQuality = "4" })
    e.slash("profile everyday")
    e.slash("set graphicsShadowQuality 2")
    OUT = {}
    e.slash("unset graphicsShadowQuality")
    local removed = db.profiles.everyday.values.graphicsShadowQuality == nil and db.want.graphicsShadowQuality == nil
        and CVARS.graphicsShadowQuality == "2" and has("no longer forcing Shadow detail (its current value is left as it is)")
    OUT = {}
    e.slash("unset graphicsShadowQuality")
    return removed and has("'Shadow detail' is not in the list"), outText()
end)

test("P6-5 /fset reset is the same as choosing Original", function()
    local e, _, db = clean({ graphicsShadowQuality = "4" })
    e.slash("profile everyday")
    e.slash("set graphicsShadowQuality 2")
    e.slash("reset")
    return CVARS.graphicsShadowQuality == "4" and next(db.want) == nil and db.active == "original", outText()
end)

test("P6-5b /fset reset in combat is refused and changes nothing", function()
    local e, _, db = clean({ graphicsShadowQuality = "4" })
    e.slash("profile everyday")
    e.slash("set graphicsShadowQuality 2")
    COMBAT = true
    OUT = {}
    e.slash("reset")
    return CVARS.graphicsShadowQuality == "2" and db.active == "everyday" and count("in combat; try again afterwards") == 1, outText()
end)

test("P6-6 the loading-screen enforcement no longer keeps db.orig", function()
    local e = boot({ groundEffectDensity = "48" })
    e.fire("PLAYER_ENTERING_WORLD")
    return CVARS.groundEffectDensity == "64" and ForeverSettingsDB.orig == nil
end)

test("P6-7 /fset set and unset are refused while a mark window runs", function()
    local e, _, db, b = clean({ graphicsShadowQuality = "4" })
    e.slash("profile everyday")
    e.slash("set graphicsShadowQuality 3")
    b.mark("m")
    OUT = {}
    e.slash("set graphicsShadowQuality 2")
    e.slash("unset graphicsShadowQuality")
    return e.ns.suspended == false and db.profiles.everyday.values.graphicsShadowQuality == "3" and CVARS.graphicsShadowQuality == "3"
        and count("benchmark running; try again afterwards") == 2, outText()
end)

-- Task 9: the keybinding (Bindings.xml itself is checked by run_all.sh, because Lua tests cannot read files)
test("P9-1 the binding's name is defined by the addon", function()
    _G.BINDING_NAME_FOREVERSETTINGS_TOGGLE = nil
    boot({})
    return BINDING_NAME_FOREVERSETTINGS_TOGGLE == "Toggle Everyday / Crowded"
end)

test("P9-2 the call Bindings.xml runs toggles the profile", function()
    local _, _, db = clean({ graphicsShadowQuality = "4" })
    SlashCmdList.FOREVERSETTINGS("profile toggle")
    local first = db.active == "crowded"
    SlashCmdList.FOREVERSETTINGS("profile toggle")
    return first and db.active == "everyday"
end)

-- Final review fixes (review-findings.md F1 to F4): each pins what the whole-result review found one step past the first tests
local function derivedClutter()      -- the game derives the raw density from the menu-level clutter
    DERIVED.graphicsGroundClutter = function(v, all) all.groundEffectDensity = tostring(tonumber(v) * 16) end
end

test("P4-14 a menu-level write that moves a raw setting does not leave it wrong: it is rewritten and counted right (F1)", function()
    local _, p, db = clean({ graphicsGroundClutter = "5", groundEffectDensity = "64" })
    derivedClutter()
    db.profiles.crowded.values = { graphicsGroundClutter = "2", groundEffectDensity = "64" }
    local ok, info = p.switch("crowded")
    return ok and #info.mismatched == 0 and CVARS.groundEffectDensity == "64" and CVARS.graphicsGroundClutter == "2"
        and info.changed == 1 and has("Profile: Crowded (1 setting changed)"), outText()
end)

test("P4-14b a setting that returns to Original is put right even when the game derived it away (F1)", function()
    local _, p, db = clean({ graphicsGroundClutter = "5", groundEffectDensity = "80" })
    derivedClutter()
    db.profiles.everyday.values = { graphicsGroundClutter = "2" }
    local ok, info = p.switch("everyday")
    return ok and #info.mismatched == 0 and CVARS.groundEffectDensity == "80" and CVARS.graphicsGroundClutter == "2", outText()
end)

test("P4-14c a later write that moves an earlier menu-level setting is put right by a second pass (F1)", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "4" })
    DERIVED.graphicsSSAO = function(_, all) all.graphicsShadowQuality = "5" end
    db.profiles.crowded.values = { graphicsShadowQuality = "1", graphicsSSAO = "2" }
    local ok, info = p.switch("crowded")
    return ok and #info.mismatched == 0 and CVARS.graphicsShadowQuality == "1" and CVARS.graphicsSSAO == "2", outText()
end)

test("P4-15 the loading screen writes a menu-level setting before the raw setting the game derives from it (F2)", function()
    local function game() return { graphicsGroundClutter = "5", groundEffectDensity = "80", raidGraphicsGroundClutter = "5", RAIDgroundEffectDensity = "80" } end
    local _, p, db = clean(game())
    db.profiles.crowded.values = { graphicsGroundClutter = "2", groundEffectDensity = "64" }
    db.raidToo = true
    p.switch("crowded")
    local e2 = H.boot(game(), {})        -- the same saved variables; the game's settings are back as they were
    DERIVED.graphicsGroundClutter = function(v, all) all.groundEffectDensity = tostring(tonumber(v) * 16) end
    DERIVED.raidGraphicsGroundClutter = function(v, all) all.RAIDgroundEffectDensity = tostring(tonumber(v) * 16) end
    e2.fire("PLAYER_ENTERING_WORLD")
    return CVARS.groundEffectDensity == "64" and CVARS.RAIDgroundEffectDensity == "64"
        and CVARS.graphicsGroundClutter == "2" and CVARS.raidGraphicsGroundClutter == "2",
        CVARS.groundEffectDensity .. "/" .. CVARS.RAIDgroundEffectDensity
end)

test("P6-3b an extra setting is still put back by Original the second time round (F3)", function()
    local e, p, db = clean({ graphicsShadowQuality = "4", maxFPS = "60" })
    e.slash("profile everyday")
    e.slash("set maxFPS 144")
    p.switch("original")
    local first = CVARS.maxFPS == "60"
    p.switch("everyday")
    local again = CVARS.maxFPS == "144"
    p.switch("original")
    return first and again and CVARS.maxFPS == "60" and db.original.values.maxFPS == "60", outText()
end)

test("P5-3b the raid option is left as it was when applying it would be refused in combat (F4)", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    p.switch("crowded")
    COMBAT = true
    OUT = {}
    p.setRaid(true)
    local refusedOn = db.raidToo == false and db.want.raidGraphicsShadowQuality == nil
        and count("in combat; try again afterwards") == 1
    COMBAT = false
    p.setRaid(true)
    COMBAT = true
    OUT = {}
    p.setRaid(false)
    return refusedOn and db.raidToo == true and db.want.raidGraphicsShadowQuality == "1"
        and count("in combat; try again afterwards") == 1, outText()
end)

test("P5-3c the raid option is left as it was while a mark window runs (F4)", function()
    local e, p, db, b = clean({ graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" })
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    p.switch("crowded")
    b.mark("m")
    OUT = {}
    e.slash("profile raid on")
    return db.raidToo == false and db.want.raidGraphicsShadowQuality == nil
        and count("benchmark running; try again afterwards") == 1, outText()
end)

test("P5-3d the raid option can still be saved in combat when Crowded is not the active profile (F4)", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    p.switch("everyday")
    COMBAT = true
    OUT = {}
    p.setRaid(true)
    return db.raidToo == true and has("Crowded will also set the game's raid and battleground graphics"), outText()
end)

-- Task 11 (the owner's request after the first in-game run): a hint when the profile switched to holds the same
-- settings as the one just left, so "nothing needed changing" is not left unexplained
local function hintFor(target, previous)
    return target .. " holds the same settings as " .. previous .. " right now: to make them differ, change a setting in My settings (minimap menu)"
end

test("P11-1 two saved profiles with the same settings: switching between them says so, in both directions", function()
    local e, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "4" })
    e.slash("profile everyday")
    e.slash("profile save everyday")
    e.slash("profile save crowded")
    OUT = {}
    e.slash("profile crowded")
    local first = count(hintFor("Crowded", "Everyday")) == 1
    OUT = {}
    e.slash("profile everyday")
    return first and count(hintFor("Everyday", "Crowded")) == 1, outText()
end)

test("P11-2 the owner's sequence (set on Everyday, then save as Crowded) gets the hint, and the working flow does not", function()
    local e = clean({ graphicsShadowQuality = "4", graphicsSSAO = "4" })
    e.slash("profile everyday")
    e.slash("profile save everyday")
    e.slash("set graphicsSSAO 1")
    e.slash("profile save crowded")
    OUT = {}
    e.slash("profile crowded")
    local identical = count(hintFor("Crowded", "Everyday")) == 1
    e.slash("set graphicsSSAO 3")                         -- now editing Crowded: the two differ
    OUT = {}
    e.slash("profile everyday")
    local differ = count("holds the same settings") == 0 and has("Profile: Everyday (1 setting changed)")
    return identical and differ, outText()
end)

test("P11-3 two different profiles give no hint", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "4" })
    db.profiles.everyday.values = { graphicsShadowQuality = "4" }
    db.profiles.crowded.values = { graphicsShadowQuality = "1" }
    p.switch("everyday")
    OUT = {}
    p.switch("crowded")
    return count("holds the same settings") == 0, outText()
end)

test("P11-4 two empty profiles give only the empty-profile line, not the hint", function()
    local _, p = clean({ graphicsShadowQuality = "4" })
    p.switch("everyday")
    OUT = {}
    p.switch("crowded")
    return count("holds the same settings") == 0 and has("Crowded has no saved settings yet"), outText()
end)

test("P11-5 Original never gets the hint, even when a profile equals it", function()
    local e, p = clean({ graphicsShadowQuality = "4" })
    e.slash("profile everyday")
    e.slash("profile save everyday")                      -- Everyday now equals Original
    OUT = {}
    p.switch("original")
    local out1 = count("holds the same settings") == 0
    OUT = {}
    p.switch("everyday")
    return out1 and count("holds the same settings") == 0, outText()
end)

test("P11-6 with the raid option on, Crowded writes raid values Everyday does not, so they are not the same", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", raidGraphicsShadowQuality = "3" })
    db.profiles.everyday.values = { graphicsShadowQuality = "4" }
    db.profiles.crowded.values = { graphicsShadowQuality = "4" }
    db.raidToo = true
    p.switch("everyday")
    OUT = {}
    p.switch("crowded")
    return count("holds the same settings") == 0, outText()
end)

test("P11-7 switching to the profile that is already active gives no hint", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    db.profiles.everyday.values = { graphicsShadowQuality = "4" }
    p.switch("everyday")
    OUT = {}
    p.switch("everyday")
    return count("holds the same settings") == 0, outText()
end)

-- Recommender, Task 5: adopt and hasValues (plan 2026-10-29-recommender.md)
test("PA-1 adopt saves the recommended values over the live ones into Everyday, switches to it and keeps the player's own as Original", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3", RenderScale = "1", maxFPS = "60" })
    local ok = p.adopt("everyday", { graphicsShadowQuality = "1" })
    return ok == true and deepEqual(db.profiles.everyday.values, { graphicsShadowQuality = "1", graphicsSSAO = "3", RenderScale = "1" })
        and CVARS.graphicsShadowQuality == "1" and CVARS.graphicsSSAO == "3" and db.active == "everyday"
        and db.original.values.graphicsShadowQuality == "4" and db.original.values.graphicsSSAO == "3"
        and deepEqual(db.want, db.profiles.everyday.values), outText()
end)

test("PA-2 in combat adopt is refused before anything is written", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3" })
    COMBAT = true
    local ok, why = p.adopt("everyday", { graphicsShadowQuality = "1" })
    return ok == false and why == "combat" and next(db.profiles.everyday.values) == nil and db.active == "original"
        and CVARS.graphicsShadowQuality == "4" and #SETLOG == 0 and has("in combat"), tostring(why) .. " / " .. outText()
end)

test("PA-3 while a benchmark window is active adopt is refused before anything is written", function()
    local e, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3" })
    e.ns.suspended = true
    local ok, why = p.adopt("everyday", { graphicsShadowQuality = "1" })
    return ok == false and why == "busy" and next(db.profiles.everyday.values) == nil and db.active == "original"
        and CVARS.graphicsShadowQuality == "4" and #SETLOG == 0 and has("benchmark running"), tostring(why) .. " / " .. outText()
end)

test("PA-4 adopt refuses Original and an unknown name and changes nothing", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    local ok1, why1 = p.adopt("original", { graphicsShadowQuality = "1" })
    local readOnly = ok1 == false and why1 == "original" and has("Original is read-only")
    OUT = {}
    local ok2, why2 = p.adopt("nope", { graphicsShadowQuality = "1" })
    return readOnly and ok2 == false and why2 == "unknown" and has("unknown profile 'nope' (original, everyday, crowded or maximum)")
        and next(db.profiles.everyday.values) == nil and next(db.profiles.crowded.values) == nil and db.active == "original"
        and CVARS.graphicsShadowQuality == "4", tostring(why1) .. " / " .. tostring(why2)
end)

test("PA-5 an Everyday that already holds values has its managed ones replaced and keeps what is outside the managed list", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3", maxFPS = "60" })
    db.profiles.everyday.values = { graphicsShadowQuality = "0", graphicsSSAO = "0", maxFPS = "144" }
    local ok = p.adopt("everyday", { graphicsShadowQuality = "1" })
    return ok == true and deepEqual(db.profiles.everyday.values, { graphicsShadowQuality = "1", graphicsSSAO = "3", maxFPS = "144" }),
        tostring(ok)
end)

test("PA-6 hasValues is false for an empty profile, Original and an unknown name, and true once something is saved", function()
    local _, p = clean({ graphicsShadowQuality = "4" })
    local before = p.hasValues("everyday")
    p.save("everyday")
    local afterSave = p.hasValues("everyday")
    local other = p.hasValues("crowded")
    local _, p2 = clean({ graphicsShadowQuality = "4" })
    p2.adopt("crowded", { graphicsShadowQuality = "1" })
    return before == false and afterSave == true and other == false and p.hasValues("original") == false
        and p.hasValues("nope") == false and p2.hasValues("crowded") == true
end)

-- Words and menu, Task 2: edits to a named profile, and edits that say nothing (spec sections 3.4 and 4)
test("P8-1 an edit to the profile in use is a setValue: stored, enforced, applied once, silent when asked", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    p.switch("everyday")
    OUT, SETLOG = {}, {}
    local ok = p.setProfileValue("everyday", "graphicsShadowQuality", "2", true)
    local silent, writes = #OUT == 0, #SETLOG
    OUT = {}
    p.setProfileValue("everyday", "graphicsShadowQuality", "1")
    return ok == true and silent and writes == 1 and CVARS.graphicsShadowQuality == "1"
        and db.profiles.everyday.values.graphicsShadowQuality == "1" and db.want.graphicsShadowQuality == "1"
        and has("keeping Shadow detail at 1"), outText()
end)

test("P8-2 an edit to a profile that is not in use only stores it: nothing is written, the profile in use is untouched", function()
    local _, p, db = clean({ graphicsShadowQuality = "4" })
    p.switch("everyday")
    p.setValue("graphicsShadowQuality", "2", true)
    OUT, SETLOG = {}, {}
    local wantBefore = copyOf(db.want)
    local ok = p.setProfileValue("crowded", "graphicsShadowQuality", "0", true)
    local first = ok == true and db.profiles.crowded.values.graphicsShadowQuality == "0" and #SETLOG == 0 and #OUT == 0
        and deepEqual(db.want, wantBefore) and db.profiles.everyday.values.graphicsShadowQuality == "2"
        and db.active == "everyday" and CVARS.graphicsShadowQuality == "2"
    local _, p2, db2 = clean({ graphicsShadowQuality = "4" })      -- Original in use
    local ok2 = p2.setProfileValue("everyday", "graphicsShadowQuality", "3", true)
    return first and ok2 == true and db2.profiles.everyday.values.graphicsShadowQuality == "3" and db2.active == "original"
        and #SETLOG == 0 and CVARS.graphicsShadowQuality == "4" and next(db2.want) == nil, outText()
end)

test("P8-3 refusals: an unknown profile, Original and a running test store nothing; combat does not stop a stored edit", function()
    local e, p, db = clean({ graphicsShadowQuality = "4" })
    p.switch("everyday")
    local a, ra = p.setProfileValue("nope", "graphicsShadowQuality", "1", true)
    local b, rb = p.setProfileValue("original", "graphicsShadowQuality", "1", true)
    e.ns.suspended = true
    local c, rc = p.setProfileValue("crowded", "graphicsShadowQuality", "1", true)
    local stored = db.profiles.crowded.values.graphicsShadowQuality
    e.ns.suspended = false
    COMBAT = true
    local d = p.setProfileValue("crowded", "graphicsShadowQuality", "1", true)
    COMBAT = false
    return a == false and ra == "unknown" and b == false and rb == "original" and c == false and rc == "busy" and stored == nil
        and d == true and db.profiles.crowded.values.graphicsShadowQuality == "1" and db.original.values.graphicsShadowQuality == "4"
        and next(db.profiles.everyday.values) == nil, tostring(ra) .. " " .. tostring(rb) .. " " .. tostring(rc)
end)

test("P8-4 unsetProfileValue removes only that stored value (false when absent); on the profile in use it is unsetValue", function()
    local _, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3" })
    p.switch("everyday")
    p.setValue("graphicsShadowQuality", "2", true)
    p.setProfileValue("crowded", "graphicsShadowQuality", "0", true)
    p.setProfileValue("crowded", "graphicsSSAO", "1", true)
    OUT = {}
    local removed = p.unsetProfileValue("crowded", "graphicsShadowQuality", true)
    local absent = p.unsetProfileValue("crowded", "graphicsShadowQuality", true)
    local rest = db.profiles.crowded.values.graphicsSSAO == "1" and db.profiles.crowded.values.graphicsShadowQuality == nil
    local active = p.unsetProfileValue("everyday", "graphicsShadowQuality", true)
    return removed == true and absent == false and rest and active == true and db.want.graphicsShadowQuality == nil
        and db.profiles.everyday.values.graphicsShadowQuality == nil and CVARS.graphicsShadowQuality == "2" and #OUT == 0, outText()
end)

test("P8-5 the silent argument silences every edit call; without it the old texts still print", function()
    local _, p = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3" })
    p.switch("everyday")
    OUT = {}
    p.setValue("graphicsShadowQuality", "2", true)
    p.unsetValue("graphicsShadowQuality", true)
    p.unsetValue("graphicsShadowQuality", true)
    p.save("crowded", true)
    p.setProfileValue("crowded", "graphicsSSAO", "1", true)
    p.unsetProfileValue("crowded", "graphicsSSAO", true)
    p.unsetProfileValue("crowded", "graphicsSSAO", true)
    local quiet = #OUT == 0
    p.setValue("graphicsShadowQuality", "2")
    p.unsetValue("graphicsShadowQuality")
    p.save("crowded")
    return quiet and has("keeping Shadow detail at 2") and has("no longer forcing Shadow detail") and has("Saved "), outText()
end)

-- Results window, Task 5: a silent switch and adopt (the results window's Save button says nothing in chat)
local function switchWith(silent, arrange)
    local e, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3", groundEffectDensity = "64" })
    if arrange then arrange(e, db) end
    OUT = {}
    local ok, info = p.switch("everyday", silent)
    return ok, info, outText()
end

test("P12-1 a silent switch prints nothing in any outcome and returns what the chatty one returns", function()
    local scenarios = {
        { "changed", function(_, db) db.profiles.everyday.values = { graphicsShadowQuality = "2" } end, "Profile: Everyday (1 setting changed)" },
        { "clamped", function(_, db)
            db.profiles.everyday.values = { graphicsShadowQuality = "2" }
            SETFAIL.graphicsShadowQuality = "clamp"
        end, "stayed at" },
        { "skipped", function(_, db) db.profiles.everyday.values = { notACvar = "1", graphicsSSAO = "1" } end, "skipped (not in this client)" },
        { "empty", function(_, db) db.profiles.everyday.values = {} end, "has no saved settings yet" },
        { "twin", function(_, db)
            db.profiles.everyday.values = { graphicsSSAO = "1" }
            db.profiles.crowded.values = { graphicsSSAO = "1" }
            db.active = "crowded"
        end, "holds the same settings" },
    }
    local bad = {}
    for _, s in ipairs(scenarios) do
        local okQuiet, infoQuiet, quietText = switchWith(true, s[2])
        local okLoud, infoLoud, loudText = switchWith(false, s[2])
        local same = okQuiet == okLoud and infoQuiet.changed == infoLoud.changed and #infoQuiet.mismatched == #infoLoud.mismatched
        if quietText ~= "" or not loudText:find(s[3], 1, true) or not same then bad[#bad + 1] = s[1] .. ": [" .. quietText .. "] [" .. loudText .. "]" end
    end
    return #bad == 0, table.concat(bad, " // ")
end)

test("P12-2 a silent switch that is refused prints nothing and still says why to its caller", function()
    local function refused(arrange)
        local e, p = clean({ graphicsShadowQuality = "4" })
        arrange(e)
        OUT = {}
        local ok, why = p.switch(arrange == nil and "everyday" or "everyday", true)
        return ok, why, outText()
    end
    local _, p0 = clean({ graphicsShadowQuality = "4" })
    local unknownOk, unknownWhy = p0.switch("nope", true)
    local unknownText = outText()
    local combatOk, combatWhy, combatText = refused(function() COMBAT = true end)
    local busyOk, busyWhy, busyText = refused(function(e) e.ns.bench.active = function() return true end end)
    return unknownOk == false and unknownWhy == "unknown" and unknownText == "" and combatOk == false and combatWhy == "combat"
        and combatText == "" and busyOk == false and busyWhy == "busy" and busyText == "", combatText .. busyText
end)

test("P12-3 a silent adopt stores and switches as before but prints nothing, in success and in every refusal", function()
    local function adopted(silent, arrange, name, values)
        local e, p, db = clean({ graphicsShadowQuality = "4", graphicsSSAO = "3" })
        if arrange then arrange(e) end
        OUT = {}
        local ok, info = p.adopt(name or "everyday", values or { graphicsShadowQuality = "1" }, silent)
        return ok, info, outText(), db
    end
    local ok, info, text, db = adopted(true)
    local stored = ok == true and info.changed ~= nil and db.profiles.everyday.values.graphicsShadowQuality == "1"
        and db.profiles.everyday.values.graphicsSSAO == "3" and db.active == "everyday" and CVARS.graphicsShadowQuality == "1" and text == ""
    local okO, whyO, textO = adopted(true, nil, "original")
    local okU, whyU, textU = adopted(true, nil, "nope")
    local okC, whyC, textC = adopted(true, function() COMBAT = true end)
    local okB, whyB, textB = adopted(true, function(e) e.ns.bench.active = function() return true end end)
    local _, whyLoud, textLoud = adopted(false, function() COMBAT = true end)
    return stored and okO == false and whyO == "original" and textO == "" and okU == false and whyU == "unknown" and textU == ""
        and okC == false and whyC == "combat" and textC == "" and okB == false and whyB == "busy" and textB == ""
        and whyLoud == "combat" and textLoud:find("in combat; try again afterwards", 1, true) ~= nil, text .. "|" .. textLoud
end)

-- Maximum and costs, Task 2: Maximum is a derived profile, every setting at its highest level, never stored
-- (spec 2026-10-30-maximum-and-costs-design.md section 3.1)
local NOTHING = "Maximum has nothing to set yet: run Find my best settings once so the addon learns what each setting can do."
local REFUSED = "Maximum cannot be changed: it always holds every setting at its highest level. Pick Everyday or Crowded first."
local TEXTURE = "Maximum includes the sharpest textures, which need plenty of graphics memory."
local LEFT2 = "2 settings stay as they are: the addon has not learned their levels yet. Run Find my best settings once."
local LEFT1 = "1 setting stays as it is: the addon has not learned its levels yet. Run Find my best settings once."
local UNKNOWN = "unknown profile 'nope' (original, everyday, crowded or maximum)"

-- A game where only Shadows and SSAO have learned levels: Compute effects and Texture resolution are in the client but
-- unlearned; Ground clutter (raw) and Render scale have built-in levels. The highest of each: Shadows 4, SSAO 4,
-- Ground clutter (raw) 128, Render scale 1. `extra` adds client settings; the player starts on Original.
local function maxGame(extra)
    local cv = { graphicsShadowQuality = "2", graphicsSSAO = "1", graphicsComputeEffects = "1", RenderScale = "1",
        groundEffectDensity = "64", graphicsTextureResolution = "2", vsync = "0" }
    for k, v in pairs(extra or {}) do cv[k] = v end
    local e, p, db, b = clean(cv)
    b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
    return e, p, db, b
end
local MAXIMA = { graphicsShadowQuality = "4", graphicsSSAO = "4", groundEffectDensity = "128", RenderScale = "1" }
local function managedNow()
    local now = {}
    for _, name in ipairs(MANAGED) do now[name] = CVARS[name] end
    return now
end
local function lineOf(sub)
    for i, l in ipairs(OUT) do
        if l:find(sub, 1, true) then return i end
    end
    return nil
end

test("MX-1 maxValues is the last level of each setting whose levels are known, and lists the unlearned ones the client has", function()
    local _, p, _, b = maxGame()
    b.state().tiers.graphicsLiquidDetail = { "0", "1", "2" }          -- learned, but this client has no such setting
    local values, leftOut = p.maxValues()
    return deepEqual(values, MAXIMA) and table.concat(leftOut, ",") == "graphicsComputeEffects,graphicsTextureResolution",
        table.concat(leftOut, ",")
end)

test("MX-11 Secondary lighting counts once when the client has it under two names", function()
    local _, p, _, b = maxGame({ giQuality = "1", graphicsLightMode = "1" })
    b.state().tiers.giQuality = { "0", "1", "2" }
    local values, leftOut = p.maxValues()
    local learned = values.giQuality == "2" and values.graphicsLightMode == nil
        and table.concat(leftOut, ",") == "graphicsComputeEffects,graphicsTextureResolution"
    local _, p2 = maxGame({ giQuality = "1", graphicsLightMode = "1" })        -- the same row, levels unlearned
    local _, leftOut2 = p2.maxValues()
    return learned and table.concat(leftOut2, ",") == "graphicsComputeEffects,giQuality,graphicsTextureResolution",
        table.concat(leftOut, ",") .. " / " .. table.concat(leftOut2, ",")
end)

test("MX-2 plan('maximum') writes the maxima over Original's values, enforces exactly the maxima and stores no profile", function()
    local _, p, db = maxGame({ maxFPS = "60" })
    db.original.values = { graphicsShadowQuality = "2", graphicsSSAO = "1", graphicsComputeEffects = "1",
        graphicsTextureResolution = "2", groundEffectDensity = "64", RenderScale = "1", maxFPS = "60" }
    local plan = p.plan("maximum")
    return deepEqual(plan.want, MAXIMA)
        and deepEqual(plan.writes, { graphicsShadowQuality = "4", graphicsSSAO = "4", groundEffectDensity = "128", RenderScale = "1",
            graphicsComputeEffects = "1", graphicsTextureResolution = "2", maxFPS = "60" })
        and plan.empty == false and db.profiles.maximum == nil and #SETLOG == 0
end)

test("MX-3 switching to Maximum writes the maxima, enforces them, and says the profile, texture and left-out lines in order", function()
    local _, p, db = maxGame()
    p.switch("everyday")
    OUT, SETLOG = {}, {}
    local ok, info = p.switch("maximum")
    local profileAt, textureAt, leftAt = lineOf("Profile: Maximum (3 settings changed)"), lineOf(TEXTURE), lineOf(LEFT2)
    return ok == true and info.changed == 3 and #info.mismatched == 0 and db.active == "maximum" and deepEqual(db.want, MAXIMA)
        and CVARS.graphicsShadowQuality == "4" and CVARS.graphicsSSAO == "4" and CVARS.groundEffectDensity == "128"
        and CVARS.graphicsComputeEffects == "1" and CVARS.graphicsTextureResolution == "2" and CVARS.RenderScale == "1"
        and profileAt ~= nil and textureAt ~= nil and leftAt ~= nil and profileAt < textureAt and textureAt < leftAt
        and db.profiles.maximum == nil, outText()
end)

test("MX-3b the left-out line counts the settings with unlearned levels: one, none", function()
    local function said(learn)
        local _, p, _, b = maxGame()
        learn(b)
        OUT = {}
        p.switch("maximum")
        return outText()
    end
    local one = said(function(b) b.state().tiers.graphicsTextureResolution = { "0", "1", "2", "3" } end)
    local none = said(function(b)
        b.state().tiers.graphicsTextureResolution = { "0", "1", "2", "3" }
        b.state().tiers.graphicsComputeEffects = { "0", "1", "2" }
    end)
    return one:find(LEFT1, 1, true) ~= nil and one:find(TEXTURE, 1, true) ~= nil
        and none:find("stay", 1, true) == nil and none:find(TEXTURE, 1, true) ~= nil, one .. " // " .. none
end)

test("MX-3c a silent switch to Maximum changes the same settings and says nothing", function()
    local _, p, db = maxGame()
    OUT = {}
    local ok, info = p.switch("maximum", true)
    return ok == true and info.changed == 3 and #OUT == 0 and db.active == "maximum" and CVARS.graphicsShadowQuality == "4", outText()
end)

test("MX-4 with nothing to set Maximum says so, returns false 'nothing' and writes and records nothing", function()
    local function attempt(cvars, learn, silent)
        local _, p, db, b = clean(cvars)
        if learn then learn(b) end
        OUT = {}
        local ok, why = p.switch("maximum", silent)
        return ok, why, db, outText(), p
    end
    local ok1, why1, db1, text1, p1 = attempt({ graphicsShadowQuality = "2", graphicsSSAO = "1", vsync = "0" })
    local none = ok1 == false and why1 == "nothing" and db1.active == "original" and #SETLOG == 0 and next(db1.original.values) == nil
        and next(db1.want) == nil and count(NOTHING) == 1 and p1.plan("maximum").empty == true
    local ok2, why2, db2, text2 = attempt({ graphicsShadowQuality = "2", vsync = "0" },
        function(b) b.state().tiers.graphicsLiquidDetail = { "0", "1", "2" } end)
    local lacking = ok2 == false and why2 == "nothing" and db2.active == "original" and #SETLOG == 0 and count(NOTHING) == 1
    local ok3, why3, _, text3 = attempt({ graphicsShadowQuality = "2", vsync = "0" }, nil, true)
    return none and lacking and ok3 == false and why3 == "nothing" and text3 == "", text1 .. " // " .. text2 .. " // " .. text3
end)

test("MX-5 after Maximum, Everyday, Crowded and Original put every setting where they hold it, including one only Maximum touched", function()
    local function back(target)
        local _, p, db = maxGame()
        db.profiles.everyday.values = { graphicsSSAO = "0" }
        db.profiles.crowded.values = { groundEffectDensity = "48" }
        p.switch("maximum", true)                      -- from Original: records Original's values first
        local atMaximum = CVARS.graphicsShadowQuality == "4" and db.original.values.graphicsShadowQuality == "2"
        p.switch(target, true)
        return atMaximum, managedNow(), db
    end
    local expected = {
        everyday = { graphicsShadowQuality = "2", graphicsSSAO = "0", graphicsComputeEffects = "1", graphicsTextureResolution = "2",
            groundEffectDensity = "64", RenderScale = "1" },
        crowded = { graphicsShadowQuality = "2", graphicsSSAO = "1", graphicsComputeEffects = "1", graphicsTextureResolution = "2",
            groundEffectDensity = "48", RenderScale = "1" },
        original = { graphicsShadowQuality = "2", graphicsSSAO = "1", graphicsComputeEffects = "1", graphicsTextureResolution = "2",
            groundEffectDensity = "64", RenderScale = "1" },
    }
    local bad = {}
    for _, target in ipairs({ "everyday", "crowded", "original" }) do
        local atMaximum, now, db = back(target)
        if not atMaximum or not deepEqual(now, expected[target]) or db.active ~= target then bad[#bad + 1] = target end
    end
    return #bad == 0, table.concat(bad, ",")
end)

test("MX-6 nothing can edit Maximum: set, unset, save, adopt and both profile-value calls refuse with 'maximum' and write nothing", function()
    local _, p, db = maxGame()
    p.switch("everyday", true)
    p.setValue("graphicsSSAO", "0", true)
    local calls = {
        { "save", function(s) return p.save("maximum", s) end },
        { "adopt", function(s) return p.adopt("maximum", { graphicsSSAO = "1" }, s) end },
        { "setProfileValue", function(s) return p.setProfileValue("maximum", "graphicsSSAO", "1", s) end },
        { "unsetProfileValue", function(s) return p.unsetProfileValue("maximum", "graphicsSSAO", s) end },
        { "setValue", function(s) return p.setValue("graphicsSSAO", "1", s) end, true },
        { "unsetValue", function(s) return p.unsetValue("graphicsSSAO", s) end, true },
    }
    local function sweep(label, activeIsMaximum)
        local bad = {}
        for _, c in ipairs(calls) do
            if activeIsMaximum or not c[3] then
                for _, silent in ipairs({ false, true }) do
                    OUT, SETLOG = {}, {}
                    local wantBefore, everydayBefore, activeBefore = copyOf(db.want), copyOf(db.profiles.everyday.values), db.active
                    local a, why = c[2](silent)
                    local said = silent and #OUT == 0 or (not silent and count(REFUSED) == 1 and #OUT == 1)
                    if (a ~= false and a ~= nil) or why ~= "maximum" or not said or #SETLOG ~= 0 or not deepEqual(db.want, wantBefore)
                        or not deepEqual(db.profiles.everyday.values, everydayBefore) or db.profiles.maximum ~= nil
                        or db.active ~= activeBefore then
                        bad[#bad + 1] = label .. ":" .. c[1] .. (silent and ":silent" or "") .. " -> " .. tostring(a) .. "," .. tostring(why)
                    end
                end
            end
        end
        return bad
    end
    local bad = sweep("everyday in use", false)
    p.switch("maximum", true)
    for _, line in ipairs(sweep("maximum in use", true)) do bad[#bad + 1] = line end
    return #bad == 0 and db.active == "maximum", table.concat(bad, " // ")
end)

test("MX-7 a level the game clamps while switching to Maximum is reported in plain words and the switch still stands", function()
    local _, p, db = maxGame()
    SETFAIL.graphicsShadowQuality = "clamp"
    local ok, info = p.switch("maximum")
    return ok == true and db.active == "maximum" and #info.mismatched == 1 and info.mismatched[1].cvar == "graphicsShadowQuality"
        and has("Shadow detail stayed at 2 (wanted 4)") and has("Profile: Maximum (2 settings changed)") and has(TEXTURE), outText()
end)

test("MX-8 /fset profile maximum switches; the listing, usage and refusal name it; toggle leaves it for Crowded", function()
    local e, p, db = maxGame()
    local named = table.concat(p.ORDER, ",") == "original,everyday,crowded,maximum" and p.LABEL.maximum == "Maximum"
    e.slash("profile maximum")
    local on = db.active == "maximum" and CVARS.graphicsShadowQuality == "4"
    OUT = {}
    e.slash("profile")
    local listed = has("Profile: Maximum (raid set: left alone)")
    OUT = {}
    e.slash("profile save maximum")
    local refused = count(REFUSED) == 1 and db.profiles.maximum == nil and db.active == "maximum"
    OUT = {}
    e.slash("profile bogus")
    local usage = count(USAGE) == 1
    e.slash("profile toggle")
    return named and on and listed and refused and usage and db.active == "crowded", outText()
end)

test("MX-8b Crowded's raid option adds nothing to Maximum", function()
    local _, p, db = maxGame({ raidGraphicsShadowQuality = "3" })
    db.raidToo = true
    p.switch("maximum", true)
    return CVARS.raidGraphicsShadowQuality == "3" and db.want.raidGraphicsShadowQuality == nil and CVARS.graphicsShadowQuality == "4"
        and p.plan("maximum").writes.raidGraphicsShadowQuality == "3"
end)

test("MX-9 combat and a running test refuse a switch to Maximum before anything is written, even when there is nothing to set", function()
    local function refused(arrange, cvars)
        local e, p, db, b = clean(cvars or { graphicsShadowQuality = "2", graphicsSSAO = "1" })
        if cvars == nil then
            b.state().tiers.graphicsShadowQuality = { "0", "1", "2", "3", "4" }
            b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4" }
        end
        arrange(e)
        OUT = {}
        local ok, why = p.switch("maximum")
        COMBAT = false
        return ok, why, db, outText()
    end
    local ok1, why1, db1, text1 = refused(function() COMBAT = true end)
    local ok2, why2, db2, text2 = refused(function(e) e.ns.suspended = true end)
    local ok3, why3 = refused(function() COMBAT = true end, { vsync = "0" })
    return ok1 == false and why1 == "combat" and db1.active == "original" and #SETLOG == 0 and next(db1.original.values) == nil
        and text1:find("in combat; try again afterwards", 1, true) ~= nil
        and ok2 == false and why2 == "busy" and db2.active == "original" and #SETLOG == 0
        and text2:find("benchmark running; try again afterwards", 1, true) ~= nil and ok3 == false and why3 == "combat", text1 .. " // " .. text2
end)

test("MX-10 with Maximum in use a loading screen puts back a level the game changed and leaves the unlearned ones alone", function()
    local e, p, db = maxGame()
    p.switch("maximum", true)
    CVARS.graphicsShadowQuality = "1"
    CVARS.groundEffectDensity = "64"
    CVARS.graphicsComputeEffects = "0"
    e.fire("PLAYER_ENTERING_WORLD")
    return CVARS.graphicsShadowQuality == "4" and CVARS.groundEffectDensity == "128" and CVARS.graphicsComputeEffects == "0"
        and db.active == "maximum"
end)

test("MX-12 every function that rejects an unknown profile name says the four names", function()
    local _, p = maxGame()
    local calls = {
        { "switch", function() return p.switch("nope") end },
        { "adopt", function() return p.adopt("nope", {}) end },
        { "save", function() return p.save("nope") end },
        { "setProfileValue", function() return p.setProfileValue("nope", "graphicsSSAO", "1") end },
        { "unsetProfileValue", function() return p.unsetProfileValue("nope", "graphicsSSAO") end },
    }
    local bad = {}
    for _, c in ipairs(calls) do
        OUT = {}
        c[2]()
        if count(UNKNOWN) ~= 1 then bad[#bad + 1] = c[1] end
    end
    return #bad == 0, table.concat(bad, ",")
end)

test("MX-15 with Maximum in use a loading screen takes in the levels learned since it was switched on", function()
    local e, p, db, b = maxGame()                      -- Compute effects is in the client, its levels unlearned
    p.switch("maximum", true)
    local before = db.want.graphicsComputeEffects == nil
    b.state().tiers.graphicsComputeEffects = { "0", "1", "2", "3" }
    local stale = db.want.graphicsComputeEffects == nil and CVARS.graphicsComputeEffects == "1"     -- nothing re-derives it by itself
    e.fire("PLAYER_ENTERING_WORLD")
    return before and stale and db.want.graphicsComputeEffects == "3" and CVARS.graphicsComputeEffects == "3" and db.active == "maximum"
        and CVARS.graphicsShadowQuality == "4", outText()
end)

test("MX-16 refresh recomputes only Maximum's enforced list and writes nothing", function()
    local _, p, db, b = maxGame()
    p.switch("everyday", true)
    db.want = { graphicsSSAO = "3" }
    b.state().tiers.graphicsComputeEffects = { "0", "1", "2", "3" }
    SETLOG = {}
    p.refresh()
    local others = deepEqual(db.want, { graphicsSSAO = "3" }) and #SETLOG == 0
    p.switch("maximum", true)
    b.state().tiers.graphicsSSAO = { "0", "1", "2", "3", "4", "5" }
    SETLOG = {}
    p.refresh()
    return others and db.want.graphicsSSAO == "5" and db.want.graphicsComputeEffects == "3" and #SETLOG == 0
        and CVARS.graphicsSSAO == "4", outText()
end)

test("MX-17 a loading screen still applies the list when the refresh fails, and says so", function()
    local e, p, db = maxGame()
    p.switch("everyday", true)
    db.want = { graphicsSSAO = "3" }
    e.ns.profiles.refresh = function() error("boom") end
    OUT = {}
    local ok = pcall(e.fire, "PLAYER_ENTERING_WORLD")
    return ok and CVARS.graphicsSSAO == "3" and has("profiles could not refresh"), outText()
end)

test("MX-14 without the benchmark module Maximum has nothing to set and says so, without an error", function()
    local e = H.boot({ graphicsShadowQuality = "2", graphicsSSAO = "1" }, { fresh = true, bench = false })
    local p = e.ns.profiles
    OUT = {}
    local ran, ok, why = pcall(p.switch, "maximum")
    local values, leftOut = p.maxValues()
    return ran and ok == false and why == "nothing" and count(NOTHING) == 1 and next(values) == nil and #leftOut == 0, outText()
end)

test("MX-13 no 'same settings' hint to or from Maximum, even when Everyday holds exactly the maxima", function()
    local _, p, db = maxGame()
    db.profiles.everyday.values = { graphicsShadowQuality = "4", graphicsSSAO = "4", groundEffectDensity = "128" }
    p.switch("everyday", true)
    OUT = {}
    p.switch("maximum")
    local to = has("Profile: Maximum (nothing needed changing)") and count("holds the same settings") == 0
    OUT = {}
    p.switch("everyday")
    local from = has("Profile: Everyday (nothing needed changing)") and count("holds the same settings") == 0
    return to and from, outText()
end)

return H.results()
