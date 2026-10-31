'use strict';
// usage: node run.js <fengari-pkg-dir> <src-dir> <test.lua> [mutation]
// Exit codes: 0 every test passed; 1 some tests failed; 2 the run itself could not be read
// (bad arguments, a mutation pattern not found exactly once, a Lua error outside a test).
// A mutation counts as killed only on exit code 1, never on 2.
const fs = require('fs');
const path = require('path');

// Each mutation breaks one behaviour on purpose: [file, find (exactly once), replace].
// A test suite that stays green under all of them would not be telling us anything.
const MUTATIONS = {
  nosetcvar: ['ForeverSettings.lua', 'pcall(SetCVar, name, value)', 'pcall(function() return true end)'],
  nocombat: ['ForeverSettings.lua', 'local function applyAll(manual, silent)', 'local function applyAll(manual, silent)\n    local InCombatLockdown = function() return false end'],
  nonumeric: ['ForeverSettings.lua', 'return x ~= nil and y ~= nil and x == y', 'return false'],

  // Bench.lua (Task 9): each line is copied from the file and must occur exactly once.
  'percentile-floor': ['Bench.lua', `    local i = math.ceil(p * n - 1e-9)`, `    local i = math.floor(p * n - 1e-9)`],
  'noisy-never': ['Bench.lua', `    return guard.drift(a, b) > K.NOISE`, `    return false`],
  'responds-always': ['Bench.lua', `    return (baseMs - controlMs) / baseMs >= K.SENSITIVITY`, `    return true`],
  'readback-exact': ['Bench.lua', `    return x ~= nil and y ~= nil and x == y`, `    return false`],
  'probe-no-restore': ['Bench.lua', `    bench.restore.putBack(originals)`, `    local _ = originals`],
  'restore-noop': ['Bench.lua', `        if not sameValue(GetCVar(name), originals[name]) then pcall(SetCVar, name, originals[name]) end`, `        local _ = originals[name]`],
  'restore-alpha': ['Bench.lua', `        if ra ~= rb then return ra < rb end`, `        if false then return ra < rb end`],
  'no-defer': ['Bench.lua', `        deferred = originals`, `        deferred = nil`],
  'no-stall-retry': ['Bench.lua', `        if w.attempt == 1 then`, `        if false then`],
  'no-movement-guard': ['Bench.lua', `        if moving() then return finish({ ok = false, reason = "movement" }) end`, `        local _ = moving`],
  'no-watchdog': ['Bench.lua', `    C_Timer.After(K.WATCHDOG, function()`, `    local _ = (function()`],
  'watchdog-any-window': ['Bench.lua', `        if win == w and not w.sawFrame then finish({ ok = false, reason = "no frames" }) end`, `        if not w.sawFrame then finish({ ok = false, reason = "no frames" }) end`],
  'skip-pending-first': ['Bench.lua', `        bench.recover()`, `        local _ = bench.recover`],
  'allow-second-run': ['Bench.lua', `    if activeRun then problems[#problems + 1] = "a run is already active" end`, `    local _ = activeRun`],
  'no-suspend': ['Bench.lua', `    ns.suspended = true`, `    ns.suspended = false`],
  'noise-no-rerun': ['Bench.lua', `                        if not rerun then
                            rerun = true
                            reruns = reruns + 1
                            -- The rerun measures`, `                        if false then
                            rerun = true
                            reruns = reruns + 1
                            -- The rerun measures`],
  'no-effect-off': ['Bench.lua', `        if guard.noEffect(baseMean, tierMs) then`, `        if false then`],
  'rejected-tier-off': ['Bench.lua', `                if not sameValue(now, value) then`, `                if false then`],
  'time-flag-off': ['Bench.lua', `                    if g0 and g1 and guard.timeShifted(g0[1], g0[2], g1[1], g1[2]) then`, `                    if false then`],
  'history-no-cap': ['Bench.lua', `    while #h > K.HISTORY do
        local keepQuiet, keepCrowd`, `    while false do
        local keepQuiet, keepCrowd`],
  'check-no-safe': ['Bench.lua', `            if not ok then stop({ reason = "error: " .. tostring(err) }) end`, `            if not ok then error(err, 0) end`],
  'run-no-safe': ['Bench.lua', `            if not ok then abort("error: " .. tostring(err)) end`, `            if not ok then error(err, 0) end`],
  'finish-no-pcall': ['Bench.lua', `    local ok, err = pcall(restore.apply, originals)`, `    local ok, err = true, restore.apply(originals)`],
  'no-recover-call': ['ForeverSettings.lua', `                local ok, err = pcall(ns.bench.recover)`, `                local ok, err = true, nil`],
  'no-recover-pcall': ['ForeverSettings.lua', `                local ok, err = pcall(ns.bench.recover)`, `                local ok, err = true, ns.bench.recover()`],

  // The fixes from the fresh review of the whole build.
  'masters-first-off': ['Bench.lua', `    if MASTERS[lower] then return 0 end`, `    if false then return 0 end`],
  'putback-always-write': ['Bench.lua', `        if not sameValue(GetCVar(name), originals[name]) then pcall(SetCVar, name, originals[name]) end`, `        pcall(SetCVar, name, originals[name])`],
  'probe-active-allowed': ['Bench.lua', `    if InCombatLockdown() then return nil, "in combat" end
    if bench.active() or bench.measuring() then return nil, "a benchmark is running" end`, `    if InCombatLockdown() then return nil, "in combat" end
    local _ = bench.active`],
  'probe-restores-one': ['Bench.lua', `    bench.restore.putBack(originals)`, `    pcall(SetCVar, cvar, original)`],
  'probe-case-sensitive': ['Bench.lua', `                if name:lower() == cvar:lower() then return true end`, `                if name == cvar then return true end`],
  'drift-vs-start-off': ['Bench.lua', `                        if fromStart > K.DRIFT then`, `                        if false then`],
  'reused-flags-off': ['Bench.lua', `        flags = mergeFlags(a.flags, b.flags), deltaMs = 0,`, `        flags = {}, deltaMs = 0,`],
  'bracket-restores-one': ['Bench.lua', `                pcall(restore.putBack, originals)
                nextInfo = { cvar = setting.cvar }`, `                pcall(SetCVar, setting.cvar, current)
                nextInfo = { cvar = setting.cvar }`],
  'snapshot-extras-off': ['Bench.lua', `    for _, name in ipairs(extraNames or {}) do`, `    for _, name in ipairs({}) do`],
  'rerun-reference-off': ['Bench.lua', `progressState.total = progressState.total + #tiers + 1
                                progressState.repeats = (progressState.repeats or 0) + 1
                            end
                            reference = b`, `progressState.total = progressState.total + #tiers + 1
                                progressState.repeats = (progressState.repeats or 0) + 1
                            end
                            reference = reference`],
  'concluded-off': ['Bench.lua', `        if concluded then return end
        concluded = true
        local entry = {
            ok = valid, time = bench.now(), zone = spot.zone, instanceType = spot.instanceType, groupSize = spot.groupSize,
            resolution = spot.resolution, renderScale = spot.renderScale, baselineMs = b0 and b0.summary.meanMs or nil,
            valid = valid, reason = reason, rows = rows,`, `        local _ = concluded
        concluded = true
        local entry = {
            ok = valid, time = bench.now(), zone = spot.zone, instanceType = spot.instanceType, groupSize = spot.groupSize,
            resolution = spot.resolution, renderScale = spot.renderScale, baselineMs = b0 and b0.summary.meanMs or nil,
            valid = valid, reason = reason, rows = rows,`],
  'ui-active-unlocked': ['UI.lua', `    local locked = ctx.active and true or false`, `    local locked = false`],
  'ui-check-enabled': ['UI.lua', `                local element = parent:CreateCheckbox(item.text, item.isChecked or function() return item.checked end, item.run)`, `                local element = nil; parent:CreateCheckbox(item.text, item.isChecked or function() return item.checked end, item.run)`],

  // UI.lua (Task 10) and the hooks that reach it.
  'ui-combat-enabled': ['UI.lua', `    local busy = (ctx.inCombat or ctx.active) and true or false`, `    local busy = false`],
  'ui-stop-always': ['UI.lua', `    add({ text = "Stop", kind = "button", disabled = not ctx.active, run = bench("stop") })`, `    add({ text = "Stop", kind = "button", disabled = false, run = bench("stop") })`],
  'ui-report-no-escape': ['UI.lua', `    tinsert(UISpecialFrames, REPORT_NAME)`, `    local _ = REPORT_NAME`],
  'ui-autoreport-ignores-flag': ['UI.lua', `    if entry.valid and not (st and st.autoReport == false) then ui.showReport(entry) end`, `    if entry.valid then ui.showReport(entry) end`],
  'ui-autoreport-invalid': ['UI.lua', `    if entry.valid and not (st and st.autoReport == false) then ui.showReport(entry) end`, `    if not (st and st.autoReport == false) then ui.showReport(entry) end`],
  'ui-angle-ignored': ['UI.lua', `    local angle = math.rad((st and st.angle) or DEFAULT_ANGLE)`, `    local angle = math.rad(DEFAULT_ANGLE)`],
  'ui-hidden-ignored': ['UI.lua', `    if st and st.hidden then button:Hide() end`, `    local _ = st`],
  'ui-menu-fallback-off': ['UI.lua', `    elseif UIDropDownMenu_Initialize and ToggleDropDownMenu and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then`, `    elseif false then`],
  'ui-menu-no-pcall': ['UI.lua', `        ok, err = pcall(openNew, owner, model)`, `        ok, err = true, openNew(owner, model)`],
  'ui-run-hook-off': ['Bench.lua', `            starts = currents,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)
            if not opts.silent then
                for _, line in ipairs(bench.report(e)) do ns.say(line) end
            end
            if ns.ui and ns.ui.runFinished then pcall(ns.ui.runFinished, e) end`, `            starts = currents,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)
            if not opts.silent then
                for _, line in ipairs(bench.report(e)) do ns.say(line) end
            end
            local _ = e`],
  'ui-env-lines-off': ['Bench.lua', `        for _, c in ipairs(ns.ui.environment()) do all[#all + 1] = c end`, `        local _ = all`],
  'ui-minimap-route-off': ['ForeverSettings.lua', `            ns.ui.toggleButton()`, `            local _ = ns.ui`],

  // Task 12: the built-in CVar list for clients without a console list.
  'client-list-ignored': ['ForeverSettings.lua', `    for _, list in ipairs({ client or {}, KNOWN_CVARS }) do`, `    for _, list in ipairs({ {}, KNOWN_CVARS }) do`],
  'builtin-list-ignored': ['ForeverSettings.lua', `    for _, list in ipairs({ client or {}, KNOWN_CVARS }) do`, `    for _, list in ipairs({ client or {} }) do`],
  'legacy-source-off': ['ForeverSettings.lua', `    if type(ConsoleGetAllCommands) == "function" then sources[#sources + 1] = ConsoleGetAllCommands end`, `    if false then sources[#sources + 1] = ConsoleGetAllCommands end`],
  'console-no-pcall': ['ForeverSettings.lua', `        local ok, all = pcall(fn)`, `        local ok, all = true, fn()`],
  'entry-name-field-off': ['ForeverSettings.lua', `        local name = entry.command or entry.name`, `        local name = entry.command`],
  'dedup-case-off': ['ForeverSettings.lua', `            local key = name:lower()`, `            local key = name`],
  'source-always-client': ['ForeverSettings.lua', `    return names, client and "client" or "built-in"`, `    return names, "client"`],
  'dump-notice-off': ['ForeverSettings.lua', `    if source == "built-in" then`, `    if false then`],
  'known-missing-gi': ['ForeverSettings.lua', `    "giQuality", "graphicsBloomUserMult", "graphicsComputeEffects", "graphicsDepthEffects",`, `    "graphicsBloomUserMult", "graphicsComputeEffects", "graphicsDepthEffects",`],
  'known-missing-texsize': ['ForeverSettings.lua', `    "shadowMode", "shadowNumCascades", "shadowSoft", "shadowTextureSize",`, `    "shadowMode", "shadowNumCascades", "shadowSoft",`],
  'env-note-off': ['Bench.lua', `        source == "built-in" and "the client has no list of its CVars; using the built-in list" or nil)`, `        nil)`],
  'env-list-always-ok': ['Bench.lua', `    addCheck(list, "CVar list", next(found) ~= nil, "no known graphics CVar exists in this client; the snapshot of your settings needs one",`, `    addCheck(list, "CVar list", true, "no known graphics CVar exists in this client; the snapshot of your settings needs one",`],
  'say-note-off': ['Bench.lua', `        local why = c.note`, `        local why = nil`],
  'say-detail-on-pass': ['Bench.lua', `        if not c.ok then why = c.detail end`, `        why = c.note or c.detail`],
  'perseconds-by-end': ['Bench.lua', `        local bucket = math.floor(t) + 1`, `        local bucket = math.floor(t + dts[i]) + 1`],
  'settle-count-kept': ['Bench.lua', `    w.phase, w.t, w.dts, w.settleN = "settle", 0, {}, 0`, `    w.phase, w.t, w.dts = "settle", 0, {}`],
  'settle-ms-off': ['Bench.lua', `            w.settleMs = w.t / w.settleN * 1000`, `            w.settleMs = nil`],
  'seconds-off': ['Bench.lua', `        seconds = stats.perSecond(w.dts),`, `        seconds = {},`],
  'check-evidence-off': ['Bench.lua', `        for i, r in ipairs(wins) do ns.say(windowLine("baseline window " .. i, r)) end`, `        local _ = wins`],
  // Profiles (Task 1)
  'raid-table-typo': ['Profiles.lua', `    graphicsSSAO = "raidGraphicsSSAO",`, `    graphicsSSAO = "raidGraphicsSSA",`],
  'managed-missing-clutter': ['Profiles.lua', `"graphicsLiquidDetail", "graphicsTextureResolution", "graphicsGroundClutter", "groundEffectDensity", "RenderScale",`, `"graphicsLiquidDetail", "graphicsTextureResolution", "graphicsGroundClutter", "RenderScale",`],
  // Profiles (Task 2)
  'migrate-orig-all': ['Profiles.lua', `        for name in pairs(want) do`, `        for name in pairs(orig) do`],
  'migrate-active-original': ['Profiles.lua', `        db.active = "everyday"`, `        db.active = "original"`],
  'migrate-no-marker': ['Profiles.lua', `    if not db or db.profilesMigrated then return end`, `    if not db then return end`],
  // Profiles (Task 3)
  'plan-no-fallback': ['Profiles.lua', `        for k, v in pairs(original) do plan.writes[k] = own[k] or v end`, `        for k, v in pairs(original) do plan.writes[k] = own[k] end`],
  'plan-want-is-writes': ['Profiles.lua', `    local missing = {}`, `    for k2, v2 in pairs(plan.writes) do plan.want[k2] = v2 end\n    local missing = {}`],
  'plan-mirror-all': ['Profiles.lua', `            for k, v in pairs(own) do`, `            for k, v in pairs(original) do`],
  'plan-everyday-mirrors': ['Profiles.lua', `        if name == "crowded" and db.raidToo then`, `        if db.raidToo then`],
  'plan-keeps-missing': ['Profiles.lua', `        if GetCVar(k) == nil then missing[#missing + 1] = k end`, `        if false then missing[#missing + 1] = k end`],
  // Profiles (Task 4)
  'switch-no-combat-guard': ['Profiles.lua', `        return false, "unknown"
    end
    if InCombatLockdown() then`, `        return false, "unknown"
    end
    if false then`],
  'switch-busy-ignores-mark': ['Profiles.lua', `    return (ns.suspended or (ns.bench and ns.bench.active and ns.bench.active())) and true or false`, `    return ns.suspended and true or false`],
  'switch-recapture-always': ['Profiles.lua', `    if db.active == "original" and name ~= "original" then`, `    if name ~= "original" then`],
  'switch-write-always': ['Profiles.lua', `            if not sameValue(GetCVar(cvar), plan.writes[cvar]) then pcall(SetCVar, cvar, plan.writes[cvar]) end`, `            pcall(SetCVar, cvar, plan.writes[cvar])`],
  // Final review fixes (F1 to F4)
  'switch-differs-from-stale': ['Profiles.lua', `            if not sameValue(GetCVar(cvar), plan.writes[cvar]) then pcall(SetCVar, cvar, plan.writes[cvar]) end`, `            if not sameValue(before[cvar], plan.writes[cvar]) then pcall(SetCVar, cvar, plan.writes[cvar]) end`],
  'switch-no-second-pass': ['Profiles.lua', `    for _ = 1, 2 do`, `    for _ = 1, 1 do`],
  'switch-changed-counts-all': ['Profiles.lua', `            if not sameValue(before[cvar], plan.writes[cvar]) then changed = changed + 1 end`, `            changed = changed + 1`],
  'applyall-byte-order': ['ForeverSettings.lua', `    for _, name in ipairs(orderedKeys(db.want)) do`, `    for _, name in ipairs(sortedKeys(db.want)) do`],
  'recapture-drops-extras': ['Profiles.lua', `        for k in pairs(db.original.values) do names[#names + 1] = k end`, `        local _ = names`],
  'raid-saves-before-refusal': ['Profiles.lua', `    if db.active == "crowded" and (InCombatLockdown() or busy()) then`, `    if false then`],
  'raid-guard-any-profile': ['Profiles.lua', `    if db.active == "crowded" and (InCombatLockdown() or busy()) then`, `    if (InCombatLockdown() or busy()) then`],
  'ui-raid-enabled-in-combat': ['UI.lua', `        isChecked = raidOn, disabled = locked or (ctx.inCombat and true or false),`, `        isChecked = raidOn, disabled = locked,`],
  'switch-no-readback': ['Profiles.lua', `        if sameValue(now, plan.writes[cvar]) then`, `        if true then`],
  'switch-want-all': ['Profiles.lua', `    db.want = plan.want`, `    db.want = plan.writes`],
  'switch-no-raid-return': ['Profiles.lua', `    local plan = profiles.plan(name)`, `    local plan = profiles.plan(name)\n    if name ~= "crowded" then for _, raid in pairs(profiles.RAID_OF) do plan.writes[raid] = nil end end`],
  // Profiles (Task 5)
  'save-drops-extras': ['Profiles.lua', `    local values = profiles.live(profiles.MANAGED)`, `    db.profiles[name].values = {}\n    local values = profiles.live(profiles.MANAGED)`],
  'save-captures-raid': ['Profiles.lua', `    local values = profiles.live(profiles.MANAGED)`, `    local values = profiles.live(profiles.originalNames())`],
  'save-want-stale': ['Profiles.lua', `    if db.active == name then db.want = profiles.plan(name).want end`, `    if false then db.want = profiles.plan(name).want end`],
  'save-original-allowed': ['Profiles.lua', `        return nil, "original"`, `        local _ = 1`],
  'toggle-original-to-everyday': ['Profiles.lua', `    return profiles.switch("crowded")`, `    return profiles.switch("everyday")`],
  'raid-no-reapply': ['Profiles.lua', `    if db.active == "crowded" then profiles.switch("crowded") end`, `    if false then profiles.switch("crowded") end`],
  // Profiles (Task 6)
  'set-allowed-on-original': ['Profiles.lua', `    if db.active == "original" then`, `    if false then`],
  'set-skips-profile-save': ['Profiles.lua', `    db.profiles[db.active].values[cvar] = value`, `    local _ = value`],
  'extra-not-recorded': ['Profiles.lua', `    if db.original.values[cvar] == nil then`, `    if false then`],
  'unset-keeps-profile-value': ['Profiles.lua', `    profile.values[cvar] = nil
    db.want = profiles.plan(db.active).want`, `    local _ = profile
    db.want = profiles.plan(db.active).want`],
  'set-ignores-busy': ['Profiles.lua', `    if refuseIfBusy(silent) then return false, "busy" end
    if db.active == "original" then`, `    local _ = refuseIfBusy
    if db.active == "original" then`],
  'unset-ignores-busy': ['Profiles.lua', `    if refuseIfBusy(silent) then return false end`, `    local _ = refuseIfBusy`],
  'reset-not-original': ['ForeverSettings.lua', `        ns.profiles.switch("original")`, `        ns.profiles.switch("everyday")`],
  'applyall-writes-orig': ['ForeverSettings.lua', `            local ok, result = pcall(SetCVar, name, value)`, `            db.orig = db.orig or {}; db.orig[name] = current\n            local ok, result = pcall(SetCVar, name, value)`],
  // Profiles (Task 7)
  'ui-profile-tick-static': ['UI.lua', `            isChecked = function() return ns.profiles ~= nil and ns.profiles.active() == key end,`, `            isChecked = function() return (ctx.profile or "original") == key end,`],
  'ui-profile-enabled-in-combat': ['UI.lua', `            disabled = locked or (ctx.inCombat and true or false), run = command("profile " .. key) }`, `            disabled = locked, run = command("profile " .. key) }`],
  'ui-profile-run-wrong': ['UI.lua', `run = command("profile save everyday")`, `run = command("profile save crowded")`],
  'ui-raid-static': ['UI.lua', `        isChecked = raidOn, disabled = locked or (ctx.inCombat and true or false),`, `        isChecked = function() return ctx.raidToo == true end, disabled = locked or (ctx.inCombat and true or false),`],
  'ui-tooltip-profile-off': ['UI.lua', `    GameTooltip:AddLine("Profile: " .. ((ns.profiles and ns.profiles.LABEL[key]) or key))`, `    local _ = key`],
  'ui-raid-note-always': ['UI.lua', `    if ctx.raidSwitchOff then`, `    if true then`],
  'ui-raid-note-long': ['UI.lua', `        add({ text = "Needs the game's raid graphics turned on.",`, `        add({ text = "The game's raid graphics are switched off, so this has no effect until you turn them on.",`],
  // Profiles (Task 8)
  'history-profile-off': ['Bench.lua', `    entry.profile = entry.profile or (ns.db() and ns.db().active)`, `    local _ = entry`],
  // Profiles (Task 9)
  'binding-name-wrong': ['Profiles.lua', `BINDING_NAME_FOREVERSETTINGS_TOGGLE = "Toggle Everyday / Crowded"`, `BINDING_NAME_FOREVERSETTINGS_TOGGLE = "Toggle"`],
  // Profiles (Task 11: the hint)
  'hint-always': ['Profiles.lua', ` and sameWrites(profiles.plan(previous).writes, plan.writes)`, ` and true`],
  'hint-for-original': ['Profiles.lua', `local twin = previous ~= name and previous ~= "original" and name ~= "original" and not plan.empty`, `local twin = previous ~= name and not plan.empty`],
  'hint-for-empty': ['Profiles.lua', `name ~= "original" and not plan.empty`, `name ~= "original"`],
  'hint-for-same-profile': ['Profiles.lua', `    local twin = previous ~= name and`, `    local twin = true and`],
  // Guide (Task 1)
  'explain-text-changed': ['Guide.lua', `"You moved, so the test stopped."`, `"You moved."`],
  'explain-baseline-off': ['Guide.lua', `    local inner = reason:match("^baseline (.+)$")`, `    local inner = nil`],
  'explain-unknown-silent': ['Guide.lua', `    return "The test stopped (reason: " .. reason .. ").", "Your settings were put back. Try again."`, `    return "", ""`],
  // Guide (Task 2)
  'minutes-floor-off': ['Guide.lua', `    if minutes < 1 then minutes = 1 end`, `    local _ = minutes`],
  'timeleft-boundary': ['Guide.lua', `    if seconds < 60 then return "less than a minute to go" end`, `    if seconds <= 60 then return "less than a minute to go" end`],
  'restore-assumed': ['Guide.lua', `    if info.pending then return "Your settings will be put back when combat ends, or at your next login." end`, `    local _ = info.pending`],
  'restoreinfo-pending-ignored': ['Guide.lua', `    return { pending = st ~= nil and st.pending ~= nil, issues = issues }`, `    return { pending = false, issues = issues }`],
  // Guide (Task 3)
  'model-start-always-enabled': ['Guide.lua', `        button("start", "Start", state.ticked == true and ((not setup and not crowd) or state.target ~= nil))`, `        button("start", "Start", true)`],
  'model-start-never-enabled': ['Guide.lua', `        button("start", "Start", state.ticked == true and ((not setup and not crowd) or state.target ~= nil))`, `        button("start", "Start", false)`],
  'model-escape-while-running': ['Guide.lua', `        view.escapeCloses = false`, `        view.escapeCloses = true`],
  'model-first-problem-only': ['Guide.lua', `            for _, problem in ipairs(state.problems) do`, `            for _, problem in ipairs({ state.problems[1] }) do`],
  'model-flag-duplicates': ['Guide.lua', `                    if not seen[flag] then seen[flag] = true; add(guide.flagLine(flag)) end`, `                    add(guide.flagLine(flag))`],
  'model-full-when-bad': ['Guide.lua', `            if result.ok then button("full", "Run the full test", true) end`, `            button("full", "Run the full test", true)`],
  // Guide (Task 4)
  'watch-no-pcall': ['Bench.lua', `            local ok, why = pcall(bench.watch)`, `            local ok, why = true, bench.watch()`],
  'watch-only-measure': ['Bench.lua', `        if bench.watch then`, `        if bench.watch and w.phase == "measure" then`],
  'watch-reason-ignored': ['Bench.lua', `            if ok and why then return finish({ ok = false, reason = why }) end`, `            if ok and why then local _ = why end`],
  'panel-order-swapped': ['Guide.lua', `    for _, panel in ipairs(PANELS) do`, `    for i = #PANELS, 1, -1 do local panel = PANELS[i]`],
  'panel-missing-errors': ['Guide.lua', `        local ok, shown = pcall(function() return frame and frame.IsShown and frame:IsShown() end)`, `        local ok, shown = true, frame:IsShown()`],
  // Guide (Task 5)
  'start-ignores-tick': ['Guide.lua', `        if state.view == "intro" and state.ticked and (state.kind ~= "setup" or state.target) then start() end`, `        if state.view == "intro" then start() end`],
  'start-ignores-open-panel': ['Guide.lua', `    local reason = guide.panelReason()`, `    local reason = nil`],
  'open-ignores-active': ['Guide.lua', `    if ns.bench and ns.bench.active() then`, `    if false then`],
  'open-relabels-running': ['Guide.lua', `        if not (state and state.view == "running") then state = { view = "running", kind = kind } end`, `        state = { view = "running", kind = kind }`],
  'watch-not-cleared': ['Guide.lua', `    local function onDone(result)
        ns.bench.watch = nil
        state = finished(kind, result)`, `    local function onDone(result)
        local _ = nil
        state = finished(kind, result)`],
  'again-keeps-tick': ['Guide.lua', `        local kind, target, mode = state.kind, state.target, state.mode
        guide.open(kind)`, `        local kind, target, mode = state.kind, state.target, state.mode
        guide.open(kind); state.ticked = true`],
  'check-notgood-as-stopped': ['Guide.lua', `        if result.ok or result.reason == "control did not respond" then`, `        if result.ok then`],
  'finished-invalid-as-done': ['Guide.lua', `    elseif result.valid == true then`, `    elseif result.valid ~= nil then`],
  'finished-drops-problems': ['Guide.lua', `problems = result.problems, entry = result.rows and result or nil }`, `entry = result.rows and result or nil }`],
  'stop-button-off': ['Guide.lua', `        ns.bench.stop()`, `        local _ = nil`],
  'report-button-off': ['Guide.lua', `        ns.ui.showReport(state.entry)`, `        local _ = nil`],
  'route-bypasses-guide': ['Bench.lua', `        if ns.guide then ns.guide.open("run") else bench.run() end`, `        bench.run()`],
  'route-check-bypasses-guide': ['Bench.lua', `        if ns.guide then ns.guide.open("check") else bench.check() end`, `        bench.check()`],
  'menu-bypasses-guide': ['UI.lua', `            elseif ns.guide and (name == "run" or name == "check") then`, `            elseif false then`],
  // Guide (Task 6)
  'ui-start-enabled-unticked': ['Guide.lua', `            button:SetEnabled(spec.enabled)`, `            button:SetEnabled(true)`],
  'ui-escape-while-running': ['Guide.lua', `    syncEscape(view.escapeCloses)`, `    syncEscape(true)`],
  'ui-escape-duplicates': ['Guide.lua', `        if UISpecialFrames[i] == WINDOW_NAME then tremove(UISpecialFrames, i) end`, `        if false then tremove(UISpecialFrames, i) end`],
  'ui-refresh-off': ['Guide.lua', `        if sinceRefresh < REFRESH then return end`, `        if sinceRefresh < REFRESH + 1e9 then return end`],
  'ui-refresh-every-frame': ['Guide.lua', `        if sinceRefresh < REFRESH then return end`, `        if sinceRefresh < 0 then return end`],
  'ui-no-fallback': ['Guide.lua', `    local ok, made = pcall(CreateFrame, kind, name, parent, template)`, `    local ok, made = true, CreateFrame(kind, name, parent, template)`],
  'ui-windows-constant': ['Guide.lua', `    return ns.bench.countWindows(resolved, currents)`, `    return 3`],
  'ui-render-unguarded': ['Guide.lua', `    local ok, err = pcall(fn)`, `    local ok, err = true, fn()`],
  'ui-foreign-running-stays': ['Guide.lua', `        if ns.bench and not ns.bench.active() then`, `        if false then`],
  'ui-button-key-fixed': ['Guide.lua', `            button.key = spec.key`, `            button.key = button.key or spec.key`],
  'ui-box-click-ignored': ['Guide.lua', `        box:SetScript("OnClick", function(self) guide.setTicked(self:GetChecked() and true or false) end)`, `        box:SetScript("OnClick", function(self) end)`],
  'ui-box-state-not-pushed': ['Guide.lua', `            box:SetChecked(view.checkbox.checked)`, `            local _ = view.checkbox.checked`],
  'ui-hide-ignored': ['Guide.lua', `    if frame then frame:Hide() end`, `    local _ = frame`],
  'ui-hide-while-running-allowed': ['Guide.lua', `        if state and state.view == "running" then self:Show() end`, `        local _ = self`],
  'ui-hide-always-reshown': ['Guide.lua', `        if state and state.view == "running" then self:Show() end`, `        self:Show()`],
  // Found in the owner's first real run (Window 47 of 45; report and Finished windows overlapping)
  'rerun-total-not-extended': ['Bench.lua', `                                progressState.total = progressState.total + #tiers + 1`, `                                local _ = tiers`],
  'rerun-total-off-by-one': ['Bench.lua', `progressState.total = progressState.total + #tiers + 1`, `progressState.total = progressState.total + #tiers`],
  'report-auto-when-guided': ['UI.lua', `    if ns.guide and ns.guide.handlesReport and ns.guide.handlesReport() then return end`, `    local _ = ns.guide`],
  'guided-flag-any-running': ['Guide.lua', `    return state ~= nil and state.view == "running" and state.started == true
        and (state.kind == "run" or state.kind == "setup" or state.kind == "crowd")`, `    return state ~= nil and state.view == "running"`],
  'report-click-keeps-window': ['Guide.lua', `        dismiss()   -- the report takes the stage; the two windows are the same size class and would overlap`, `        local _ = nil`],
  // Recommend (Task 1)
  'margin-ignored': ['Recommend.lua', `    result.budgetMs = 1000 / target * (1 - margin)`, `    result.budgetMs = 1000 / target`],
  'no-raise-ignored': ['Recommend.lua', `            if rule and rule.raise and not noRaise then chosen = top end`, `            if rule and not noRaise then chosen = top end`],
  'uncounted-row-chosen': ['Recommend.lua', `            if level.counted then
                if level.current then current = i else others = others + 1 end`, `            if true then
                if level.current then current = i else others = others + 1 end`],
  'flag-row-counted': ['Recommend.lua', `        if UNUSABLE[flag] then return false end`, `        if false then return false end`],
  'no-effect-flag-excludes': ['Recommend.lua', `["lighting may have changed"] = true }`, `["lighting may have changed"] = true, ["no measurable effect or not applied"] = true }`],
  'notmeasured-needs-no-other': ['Recommend.lua', `        if not current or others == 0 then`, `        if not current then`],
  'notmeasured-needs-no-current': ['Recommend.lua', `        if not current or others == 0 then`, `        if others == 0 then`],
  'invalid-entry-used': ['Recommend.lua', `    if not entry or entry.valid ~= true then`, `    if not entry then`],
  'nochange-text-changed': ['Recommend.lua', `"Good news: your settings already hold "`, `"Good news: your settings hold "`],
  'afterms-ignores-chosen': ['Recommend.lua', `        total = total + levels[w.chosen].deltaMs`, `        total = total + levels[w.current].deltaMs`],
  'change-from-to-swapped': ['Recommend.lua', `from = levels[w.current].value, to = levels[w.chosen].value,`, `from = levels[w.chosen].value, to = levels[w.current].value,`],
  'unchanged-not-listed': ['Recommend.lua', `result.unchanged[#result.unchanged + 1] = { cvar = w.g.cvar, setting = w.g.setting }`, `local _ = w`],
  // Recommend (Task 2)
  'ratio-ignores-weight': ['Recommend.lua', `local ratio = rule.weight * lost / (here - levels[to].deltaMs)`, `local ratio = lost / (here - levels[to].deltaMs)`],
  'ratio-ignores-levels-lost': ['Recommend.lua', `local ratio = rule.weight * lost / (here - levels[to].deltaMs)`, `local ratio = rule.weight * 1 / (here - levels[to].deltaMs)`],
  'tie-higher-weight-first': ['Recommend.lua', `(ratio == best.ratio and rule.weight < best.weight)`, `(ratio == best.ratio and rule.weight > best.weight)`],
  'lower-to-next-level-always': ['Recommend.lua', `if levels[i].counted and levels[i].deltaMs < here then`, `if levels[i].counted then`],
  'lowers-to-farthest': ['Recommend.lua', `for i = w.chosen - 1, 1, -1 do`, `for i = 1, w.chosen - 1 do`],
  'unreachable-still-recommends': ['Recommend.lua', `        result.changes, result.unchanged = {}, {}`, `        result.unchanged = {}`],
  'unreachable-one-sentence': ['Recommend.lua', `        if fps < target then`, `        if true then`],
  'ranking-override-ignored': ['Recommend.lua', `    local ranking = options.ranking or recommend.RANKING`, `    local ranking = recommend.RANKING`],
  'margin-override-ignored': ['Recommend.lua', `    local margin = options.margin or (crowd and recommend.CROWD_MARGIN or recommend.MARGIN)`, `    local margin = crowd and recommend.CROWD_MARGIN or recommend.MARGIN`],
  'raise-start-skipped': ['Recommend.lua', `            if rule and rule.raise and not noRaise then chosen = top end`, `            if false then chosen = top end`],
  'estimate-ignores-lowered': ['Recommend.lua', `for _, w in ipairs(work) do sum = sum + w.g.levels[w.chosen].deltaMs end`, `for _, w in ipairs(work) do sum = sum + w.g.levels[w.current].deltaMs end`],
  'unranked-lowered': ['Recommend.lua', `local rule = ranking[w.g.cvar]`, `local rule = ranking[w.g.cvar] or { weight = 0, raise = false }`],
  // Recommend (Task 3)
  'chart-scale-per-setting': ['Recommend.lua', `                if not lowest or fps < lowest then lowest = fps end`, `                if not lowest then lowest = fps end`],
  'chart-scale-without-target': ['Recommend.lua', `local biggest = math.max(result.nowFps, result.target)`, `local biggest = result.nowFps`],
  'saves-costs-swapped': ['Recommend.lua', `(single >= 0 and "saves " or "costs ")`, `(single >= 0 and "costs " or "saves ")`],
  'uncounted-in-scale': ['Recommend.lua', `            if level.counted then
                local fps = fpsAt(level.deltaMs)`, `            if level.counted or level.deltaMs ~= nil then
                local fps = fpsAt(level.deltaMs)`],
  'canapply-always': ['Recommend.lua', `canApply = result.status == "change"`, `canApply = true`],
  'headline-after-always': ['Recommend.lua', `    elseif result.status == "change" then
        model.headline.after = {`, `    else
        model.headline.after = {`],
  'notmeasured-not-listed': ['Recommend.lua', `model.notMeasured[#model.notMeasured + 1] = { setting = n.setting, name = nameOf(n.cvar, n.setting), cvar = n.cvar, reason = n.reason,
            plain = recommend.plainReason(n.reason) }`, `local _ = n`],
  'now-label-uses-after': ['Recommend.lua', `"Now: about " .. whole(result.nowFps)`, `"Now: about " .. whole(result.afterFps)`],
  'after-fraction-uses-now': ['Recommend.lua', `fps = result.afterFps, fraction = result.afterFps / scaleFps,`, `fps = result.afterFps, fraction = result.nowFps / scaleFps,`],
  // Bench, recommender Task 4
  'current-flag-missing': ['Bench.lua', `flags = mergeFlags(a.flags, b.flags), deltaMs = 0, current = true,`, `flags = mergeFlags(a.flags, b.flags), deltaMs = 0,`],
  'learn-probes-known': ['Bench.lua', `            if not known or #known == 0 then
                local tiers, reason = bench.probe(cvar)`, `            if true then
                local tiers, reason = bench.probe(cvar)`],
  'learn-skips-absent': ['Bench.lua', `        if cvar then
            local known = tiersFor(row, cvar)      -- a raw setting's explicit list counts as known`, `        if true then
            local known = tiersFor(row, cvar)      -- a raw setting's explicit list counts as known`],
  'learn-ignores-combat': ['Bench.lua', `    if InCombatLockdown() then
        return nil, "in combat"
    end`, `    local _ = nil`],
  'learn-ignores-active': ['Bench.lua', `    if bench.active() or bench.measuring() then return nil, "a benchmark is running" end
    local learned, failed = {}, {}`, `    local learned, failed = {}, {}`],
  'learn-failure-aborts': ['Bench.lua', `if tiers then learned[#learned + 1] = cvar else failed[#failed + 1] = { cvar = cvar, reason = reason } end`, `if tiers then learned[#learned + 1] = cvar else return nil, reason end`],
  'estimate-ignores-unlearned': ['Bench.lua', `if not known or #known == 0 then windows = windows + assumed end`, `if not known or #known == 0 then windows = windows + 0 end`],
  // Profiles, recommender Task 5
  'adopt-writes-before-guard': ['Profiles.lua', `    if InCombatLockdown() then
        speak(silent, "in combat; try again afterwards")
        return false, "combat"
    end
    if busy() then
        speak(silent, "benchmark running; try again afterwards")
        return false, "busy"
    end
    local merged = profiles.live(profiles.MANAGED)`, `    local merged = profiles.live(profiles.MANAGED)`],
  'adopt-drops-live-values': ['Profiles.lua', `local merged = profiles.live(profiles.MANAGED)`, `local merged = {}`],
  'adopt-overlay-skipped': ['Profiles.lua', `for cvar, value in pairs(values or {}) do merged[cvar] = value end`, `local _ = values`],
  'adopt-skips-switch': ['Profiles.lua', `    for cvar, value in pairs(merged) do db.profiles[name].values[cvar] = value end
    return profiles.switch(name, silent)`, `    for cvar, value in pairs(merged) do db.profiles[name].values[cvar] = value end
    return true, { changed = 0, mismatched = {} }`],
  'adopt-allows-original': ['Profiles.lua', `        return false, "unknown"
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
    local merged`, `        return false, "unknown"
    end
    if name == "original" then
        speak(silent, "Original is read-only: it holds your own settings from before you first switched")
        name = "everyday"
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
    local merged`],
  'adopt-allows-unknown': ['Profiles.lua', `        unknownProfile(silent, name)
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
    local merged`, `        unknownProfile(silent, name)
        name = "everyday"
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
    local merged`],
  'adopt-drops-extras': ['Profiles.lua', `for cvar, value in pairs(merged) do db.profiles[name].values[cvar] = value end`, `db.profiles[name].values = merged`],
  'hasvalues-always-true': ['Profiles.lua', `return profile ~= nil and next(profile.values) ~= nil`, `return profile ~= nil`],
  // Guide, recommender Task 6
  'start-without-target': ['Guide.lua', `button("start", "Start", state.ticked == true and ((not setup and not crowd) or state.target ~= nil))`, `button("start", "Start", state.ticked == true)`],
  'click-start-without-target': ['Guide.lua', `if state.view == "intro" and state.ticked and (state.kind ~= "setup" or state.target) then start() end`, `if state.view == "intro" and state.ticked then start() end`],
  'target-saved-on-click': ['Guide.lua', `        state.target = n
        draw()`, `        state.target = n
        ns.ui.state().target = n
        draw()`],
  'settarget-accepts-unlisted': ['Guide.lua', `        and listedTarget(n) then`, `        and true then`],
  'open-ignores-saved-target': ['Guide.lua', `if listedTarget(saved) then state.target = saved end`, `if false then state.target = saved end`],
  'learn-skipped': ['Guide.lua', `        ns.bench.learn()`, `        local _ = nil`],
  'learn-before-panel-check': ['Guide.lua', `    local reason = guide.panelReason()`, `    if state.kind == "setup" then ns.bench.learn() end
    local reason = guide.panelReason()`],
  'target-not-saved': ['Guide.lua', `            saved.target = target`, `            local _ = target`],
  'setup-opens-report': ['Guide.lua', `        and (state.kind == "run" or state.kind == "setup" or state.kind == "crowd")`, `        and (state.kind == "run" or state.kind == "crowd")`],
  'handoff-off': ['Guide.lua', `if (kind == "setup" or kind == "crowd") and state.view == "done" and ns.results then`, `if false then`],
  'invalid-run-hands-off': ['Guide.lua', `if (kind == "setup" or kind == "crowd") and state.view == "done" and ns.results then`, `if (kind == "setup" or kind == "crowd") and ns.results then`],
  'results-missing-errors': ['Guide.lua', `if (kind == "setup" or kind == "crowd") and state.view == "done" and ns.results then`, `if (kind == "setup" or kind == "crowd") and state.view == "done" then`],
  'target-buttons-always-shown': ['Guide.lua', `        for _, button in ipairs(p.targets) do button:Hide() end`, `        local _ = p.targets`],
  'estimate-uses-run-count': ['Guide.lua', `        ctx.windows = ctx.windowsByMode[state.mode == "thorough" and "thorough" or "quick"]`, `        ctx.windows = windowCount()`],
  'target-lost-on-again': ['Guide.lua', `if (kind == "setup" or kind == "crowd") and state.view == "intro" then
            if target then state.target = target end`, `if false then
            if target then state.target = target end`],
  'stopped-drops-target': ['Guide.lua', `state = { view = "stopped", kind = kind, reason = reason, target = target, mode = mode }`, `state = { view = "stopped", kind = kind, reason = reason, mode = mode }`],
  // Results, recommender Task 7
  'headline-ignores-fraction': ['Results.lua', `bar(p.texMain, color, CHART_X, left, entryRow.fraction * CHART_WIDTH, 14)`, `bar(p.texMain, color, CHART_X, left, CHART_WIDTH, 14)`],
  'target-line-at-now': ['Results.lua', `CHART_X + h.target.fraction * CHART_WIDTH, top, 2, left - top)`, `CHART_X + h.now.fraction * CHART_WIDTH, top, 2, left - top)`],
  'apply-passes-all-values': ['Results.lua', `for _, change in ipairs(current.result.changes) do values[change.cvar] = change.to end`, `for _, s in ipairs(current.result.settings) do values[s.cvar] = s.chosen end`],
  'apply-skips-adopt': ['Results.lua', `local ok, info = ns.profiles.adopt(profile, values, true)`, `local ok, info = true, {}`],
  'replace-wording-always': ['Results.lua', `text = replace and ("Replace my " .. who .. " settings with these") or ("Save these as my " .. who .. " settings") }`, `text = "Replace my " .. who .. " settings with these" }`],
  'later-writes': ['Results.lua', `    if key == "later" then
        results.hide()`, `    if key == "later" then
        ns.profiles.adopt("everyday", {})
        results.hide()`],
  'combat-not-disabled': ['Results.lua', `if p.apply then p.apply:SetEnabled(why == nil) end`, `if p.apply then p.apply:SetEnabled(true) end`],
  'refresh-off': ['Results.lua', `        if sinceRefresh < REFRESH then return end`, `        if true then return end`],
  'apply-failure-closes': ['Results.lua', `        current.notice = REFUSED[info] or ("Could not save: " .. tostring(info))`, `        current.notice = REFUSED[info] or ("Could not save: " .. tostring(info))
        results.hide()`],
  'draw-error-rethrown': ['Results.lua', `        frame:Show()
    end)
    if not ok then fail(err) end`, `        frame:Show()
    end)
    if not ok then error(err) end`],
  'fallback-silent': ['Results.lua', `    for _, line in ipairs(m.lines) do ns.say(line) end`, `    local _ = m`],
  'error-said-every-time': ['Results.lua', `    if err ~= lastError then`, `    if true then`],
  'escape-not-listed': ['Results.lua', `    if not listedForEscape then tinsert(UISpecialFrames, FRAME_NAME) end`, `    if false then tinsert(UISpecialFrames, FRAME_NAME) end`],
  'hide-keeps-offer': ['Results.lua', `    f:SetScript("OnHide", function() current = nil end)`, `    f:SetScript("OnHide", function() end)`],
  'notmeasured-text-changed': ['Results.lua', `chosen.name .. ": not measured (" .. tostring(chosen.reason) .. ")"`, `chosen.name .. ": missing (" .. tostring(chosen.reason) .. ")"`],
  // Routes and menu, recommender Task 8
  'slash-setup-wrong-kind': ['ForeverSettings.lua', `            ns.guide.open("setup")`, `            ns.guide.open("run")`],
  'slash-setup-without-guide-silent': ['ForeverSettings.lua', `            ns.guide.open("setup")
        else
            say("guide module not loaded")`, `            ns.guide.open("setup")
        else
            local _ = nil`],
  'menu-setup-enabled-in-combat': ['UI.lua', `    add({ text = "Find my best settings", kind = "button", disabled = busy, done = saved.best == true,`, `    add({ text = "Find my best settings", kind = "button", disabled = false, done = saved.best == true,`],
  'menu-setup-wrong-kind': ['UI.lua', `        ns.guide.open(kind == "best" and "setup" or "crowd")`, `        ns.guide.open(kind == "best" and "crowd" or "crowd")`],
  'menu-setup-without-guide-silent': ['UI.lua', `    else
        ns.say("guide module not loaded")
    end
end

-- the menu model (pure)`, `    else
        local _ = nil
    end
end

-- the menu model (pure)`],
  // Fixes from the fresh review of the recommender
  'texture-release-settext': ['Results.lua', `        if hasText then pool.items[i]:SetText("") end`, `        pool.items[i]:SetText("")`],
  'afterms-floor-removed': ['Recommend.lua', `result.afterMs = math.max(result.nowMs + total, result.nowMs / recommend.MAX_SPEEDUP)`, `result.afterMs = result.nowMs + total`],
  'max-speedup-changed': ['Recommend.lua', `recommend.MAX_SPEEDUP = 4`, `recommend.MAX_SPEEDUP = 2`],
  'starts-not-recorded': ['Bench.lua', `            starts = currents,`, `            starts = nil,`],
  'synthetic-current-missing': ['Recommend.lua', `    for _, g in ipairs(order) do addCurrent(g, starts and starts[g.cvar]) end`, `    local _ = starts`],
  'synthetic-current-appended': ['Recommend.lua', `        if v and v > n then`, `        if false then`],
  'synthetic-nonnumeric': ['Recommend.lua', `    if not n then return end`, `    local _ = n`],
  'synthetic-duplicates-current': ['Recommend.lua', `        if level.current then return end`, `        if false then return end`],
  'synthetic-value-raw': ['Recommend.lua', `value = string.format("%g", n), deltaMs = 0`, `value = start, deltaMs = 0`],
  // Fixes after the owner's first live run
  'nodata-reported-as-nochange': ['Recommend.lua', `    if #work == 0 then`, `    if false then`],
  'nodata-text-changed': ['Recommend.lua', `The test couldn't get a steady reading here`, `The test did not get a steady reading here`],
  'settle-adaptive-off': ['Bench.lua', `        if w.t >= K.SETTLE and (w.t >= K.SETTLE_MAX or steady(w.slices)) then`, `        if w.t >= K.SETTLE then`],
  'settle-no-cap': ['Bench.lua', `        if w.t >= K.SETTLE and (w.t >= K.SETTLE_MAX or steady(w.slices)) then`, `        if w.t >= K.SETTLE and steady(w.slices) then`],
  'settle-never-steady': ['Bench.lua', `    return math.abs(a - b) <= K.SETTLE_STEADY * math.min(a, b)`, `    return false`],
  'settle-steady-always': ['Bench.lua', `    return math.abs(a - b) <= K.SETTLE_STEADY * math.min(a, b)`, `    return true`],
  'settle-judges-first-slice': ['Bench.lua', `    local a, b = slices[n - 1], slices[n]`, `    local a, b = slices[1], slices[n]`],
  'flag-noeffect-raw': ['Guide.lua', `        return "Some settings made no measurable difference in this spot; the report lists them."`, `        return flag`],
  'ui-fallback-box-stuck': ['Guide.lua', `        box:SetScript("OnClick", function() guide.setTicked(not (state and state.ticked)) end)`, `        box:SetScript("OnClick", function() guide.setTicked(false) end)`],
  'ui-tick-static': ['UI.lua', `                local element = parent:CreateCheckbox(item.text, item.isChecked or function() return item.checked end, item.run)`, `                local element = parent:CreateCheckbox(item.text, function() return item.checked end, item.run)`],
  'busy-ignores-suspended': ['Profiles.lua', `    return (ns.suspended or (ns.bench and ns.bench.active and ns.bench.active())) and true or false`, `    return (ns.bench and ns.bench.active and ns.bench.active()) and true or false`],
  'check-control-evidence-off': ['Bench.lua', `        ns.say(windowLine("control window", controlResult))`, `        local _ = controlResult`],
  'capture-unguarded': ['Bench.lua', `        if restore.isGuarded(name) then`, `        if true then`],

  // The crowd recommendation (crowd test, Task 1)
  'crowd-rebase-skipped': ['Recommend.lua', `    for _, item in ipairs(list) do item.rebased = item.delta - d0 end`, `    for _, item in ipairs(list) do item.rebased = item.delta end`],
  'crowd-interpolation-off': ['Recommend.lua', `            if v < n then lo = level elseif not hi then hi = level end`, `            if v < n then lo = level end`],
  'crowd-factor-unclamped': ['Recommend.lua', `        factor = math.min(math.max(saved / lowest, 0), recommend.CROWD_FACTOR_MAX)`, `        factor = math.max(saved / lowest, 0)`],
  'crowd-factor-floor-off': ['Recommend.lua', `        factor = math.min(math.max(saved / lowest, 0), recommend.CROWD_FACTOR_MAX)`, `        factor = math.min(saved / lowest, recommend.CROWD_FACTOR_MAX)`],
  'crowd-nosaving-scales': ['Recommend.lua', `    local saved = type(c.lowDelta) == "number" and c.lowDelta < 0 and c.lowDelta or nil`, `    local saved = type(c.lowDelta) == "number" and c.lowDelta or nil`],
  'crowd-flat-fallback-off': ['Recommend.lua', `    local flat = math.abs(lowest) < recommend.FLAT_MS`, `    local flat = false`],
  'crowd-only-setting-dropped': ['Recommend.lua', `                add(crowdOnlyRows(c, entry.starts[c.cvar], entry.baselineMs))`, `                local _ = crowdOnlyRows`],
  'crowd-status-reason-lost': ['Recommend.lua', `        notMeasuredReason = reason, flags = {} }`, `        flags = {} }`],
  'crowd-unmeasured-silent': ['Recommend.lua', `    if not d0 then return { statusRow(g.setting, g.cvar, c.lowValue, "unmeasured", UNCOVERED) } end`, `    if not d0 then return {} end`],
  'crowd-ignores-quiet-start': ['Recommend.lua', `    for _, g in ipairs(group(quiet.rows, quiet.starts)) do`, `    for _, g in ipairs(group(quiet.rows, nil)) do`],
  'crowd-margin-default-wrong': ['Recommend.lua', `    local margin = options.margin or (crowd and recommend.CROWD_MARGIN or recommend.MARGIN)`, `    local margin = options.margin or recommend.MARGIN`],
  'crowd-raises': ['Recommend.lua', `    local noRaise = crowd or (entry ~= nil and entry.mode == "quick")`, `    local noRaise = (entry ~= nil and entry.mode == "quick")`],
  'quick-mode-raises': ['Recommend.lua', `    local noRaise = crowd or (entry ~= nil and entry.mode == "quick")`, `    local noRaise = crowd`],
  'crowd-nochange-text-plain': ['Recommend.lua', `(crowd and " in crowds" or "")`, `""`],
  'choose-kind-fixed': ['Recommend.lua', `        kind = crowd and "crowd" or "quiet" }`, `        kind = "quiet" }`],
  'crowd-title-missing': ['Recommend.lua', `        title = crowd and "Your crowded settings" or "Your best settings",`, `        title = "Your best settings",`],
  'crowd-footer-missing': ['Recommend.lua', `footer = crowd and CROWD_FOOTER or FOOTER,`, `footer = FOOTER,`],
  'chart-hint-missing': ['Recommend.lua', `        model.hint = HINT`, `        model.hint = nil`],
  'chart-hint-on-crowd': ['Recommend.lua', `    if not crowd and (result.status == "change" or result.status == "nochange" or result.status == "unreachable") then`, `    if (result.status == "change" or result.status == "nochange" or result.status == "unreachable") then`],
  'chart-hint-on-nodata': ['Recommend.lua', `    if not crowd and (result.status == "change" or result.status == "nochange" or result.status == "unreachable") then`, `    if not crowd and result.status ~= "invalid" then`],

  // Quick levels (crowd test, Task 2)
  'quick-middle-is-current': ['Bench.lua', `        if isCurrent(middle) then`, `        if false then`],
  'quick-skips-lowest': ['Bench.lua', `        if not isCurrent(1) then list[#list + 1] = tiers[1] end`, `        if false then list[#list + 1] = tiers[1] end`],
  'quick-small-setting-partial': ['Bench.lua', `    if mode == "quick" and #tiers > 3 then`, `    if mode == "quick" then`],
  'quick-count-ignores-mode': ['Bench.lua', `        sweep = sweep + #bench.tiersToMeasure(entry, currents[entry.cvar], mode)`, `        sweep = sweep + #bench.tiersToMeasure(entry, currents[entry.cvar])`],
  'quick-estimate-ignores-mode': ['Bench.lua', `    local windows = bench.countWindows(resolved, currents, mode)`, `    local windows = bench.countWindows(resolved, currents)`],
  'quick-assumed-wrong': ['Bench.lua', `    local assumed = mode == "quick" and K.ASSUMED_QUICK or K.ASSUMED_LEVELS`, `    local assumed = K.ASSUMED_LEVELS`],
  'quick-run-measures-all': ['Bench.lua', `            local tiers = bench.tiersToMeasure(setting, current, mode)`, `            local tiers = bench.tiersToMeasure(setting, current)`],
  'quick-run-ignores-opt': ['Bench.lua', `    local mode = opts.levels == "quick" and "quick" or "all"`, `    local mode = "all"`],
  'quick-progress-total-full': ['Bench.lua', `total = bench.countWindows(resolved, currents, mode) }`, `total = bench.countWindows(resolved, currents) }`],
  'drift-current-row-dropped': ['Bench.lua', `                elseif m or sameValue(tier, current) then`, `                elseif m then`],
  'addrows-needs-every-level': ['Bench.lua', `            elseif measured[tier] then`, `            else`],
  'entry-mode-missing': ['Bench.lua', `            kind = opts.kind or "run", mode = mode,`, `            kind = opts.kind or "run",`],
  'entry-kind-ignores-opts': ['Bench.lua', `            kind = opts.kind or "run", mode = mode,`, `            kind = "run", mode = mode,`],

  // The crowd test (crowd test, Task 3)
  'crowd-sequence-short': ['Bench.lua', `        if not item then return conclude(true) end`, `        if not item or i > 3 then return conclude(true) end`],
  'crowd-lowest-wrong': ['Bench.lua', `                    if v and v < live and (not lowest or v < tonumber(lowest)) then lowest = row.value end`, `                    if v and v < live and (not lowest or v > tonumber(lowest)) then lowest = row.value end`],
  'crowd-delta-sign-swapped': ['Bench.lua', `record(item, { lowDelta = low.summary.meanMs - baseMs, baseMs = baseMs, drift = drift,`, `record(item, { lowDelta = baseMs - low.summary.meanMs, baseMs = baseMs, drift = drift,`],
  'crowd-delta-uses-one-baseline': ['Bench.lua', `                    local baseMs = (reference.summary.meanMs + b.summary.meanMs) / 2`, `                    local baseMs = reference.summary.meanMs`],
  'crowd-no-putback': ['Bench.lua', `                pcall(restore.putBack, originals)
                nextInfo = { cvar = item.cvar }
                baselineWindow("after " .. item.label, function(b)`, `                local _ = originals
                nextInfo = { cvar = item.cvar }
                baselineWindow("after " .. item.label, function(b)`],
  'crowd-uses-quiet-noise': ['Bench.lua', `                    if drift > K.CROWD_NOISE or fromStart > K.CROWD_DRIFT then`, `                    if drift > K.NOISE or fromStart > K.DRIFT then`],
  'crowd-no-repeat': ['Bench.lua', `        local reference, rerun = before, false`, `        local reference, rerun = before, true`],
  'crowd-repeats-twice': ['Bench.lua', `                            rerun = true
                            reruns = reruns + 1
                            -- The repeat takes one more window and one more baseline.`, `                            rerun = false
                            reruns = reruns + 1
                            -- The repeat takes one more window and one more baseline.`],
  'crowd-restore-skipped': ['Bench.lua', `            kind = "crowd", settings = settings, starts = currents, quietTime = quiet.time,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)`, `            kind = "crowd", settings = settings, starts = currents, quietTime = quiet.time,
        }
        pushHistory(entry)
        progressState = nil
        finishRun({}, entry, function(e)`],
  'crowd-accepts-invalid-quiet': ['Bench.lua', `    if type(quiet) ~= "table" or quiet.valid ~= true then`, `    if type(quiet) ~= "table" then`],
  'crowd-measures-unlisted': ['Bench.lua', `            if lowest then plan[#plan + 1] = { cvar = entry.cvar, label = entry.label, lowValue = lowest } end`, `            plan[#plan + 1] = { cvar = entry.cvar, label = entry.label, lowValue = lowest or entry.tiers[1] }`],
  'crowd-not-in-history': ['Bench.lua', `            kind = "crowd", settings = settings, starts = currents, quietTime = quiet.time,
        }
        pushHistory(entry)`, `            kind = "crowd", settings = settings, starts = currents, quietTime = quiet.time,
        }
        local _ = pushHistory`],
  'crowd-report-header-only': ['Bench.lua', `        for _, s in ipairs(entry.settings or {}) do`, `        for _, s in ipairs({}) do`],
  'crowd-report-shows-numbers-for-status': ['Bench.lua', `            if s.status then
                lines[#lines + 1] = "  " .. tostring(s.reason)`, `            if false then
                lines[#lines + 1] = "  " .. tostring(s.reason)`],
  'crowd-drift-not-recorded': ['Bench.lua', `record(item, { lowDelta = low.summary.meanMs - baseMs, baseMs = baseMs, drift = drift,`, `record(item, { lowDelta = low.summary.meanMs - baseMs, baseMs = baseMs,`],
  'crowd-rerun-total-not-grown': ['Bench.lua', `                                progressState.total = progressState.total + 2`, `                                progressState.total = progressState.total`],
  'ui-last-includes-crowd': ['UI.lua', `            if history[i].kind ~= "crowd" then`, `            if true then`],
  'ui-costs-from-crowd': ['UI.lua', `            if history[i].kind ~= "crowd" then
                ctx.last = history[i]`, `            if true then
                ctx.last = history[i]`],

  // The check of a recommendation (crowd test, Task 4)
  'verify-writes-extra': ['Bench.lua', `        pcall(SetCVar, cvar, values[cvar])`, `        pcall(SetCVar, "vsync", "0")
        pcall(SetCVar, cvar, values[cvar])`],
  'verify-no-putback-before-baseline': ['Bench.lua', `        progressState.done = 1
        pcall(restore.putBack, originals)`, `        progressState.done = 1
        local _ = originals`],
  'verify-restore-skipped-on-stop': ['Bench.lua', `        progressState = nil
        finishRun(originals, result, onDone)
    end
    local function stop(reason) finishWith({ ok = false, reason = reason }) end`, `        progressState = nil
        finishRun({}, result, onDone)
    end
    local function stop(reason) finishWith({ ok = false, reason = reason }) end`],
  'verify-no-readback': ['Bench.lua', `        if not sameValue(GetCVar(cvar), values[cvar]) then return stop("rejected") end`, `        local _ = sameValue`],
  'verify-ignores-combat': ['Bench.lua', `        for _, p in ipairs(problems) do say("cannot check: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    local names = {}`, `        for _, p in ipairs(problems) do say("cannot check: " .. p) end
    end
    local names = {}`],
  'verify-empty-runs': ['Bench.lua', `    if #names == 0 then return onDone({ ok = false, reason = "nothing to check" }) end`, `    if false then return onDone({ ok = false, reason = "nothing to check" }) end`],
  'verify-applied-uses-baseline': ['Bench.lua', `finishWith({ ok = true, appliedMs = applied.summary.meanMs, baselineMs = baseline.summary.meanMs })`, `finishWith({ ok = true, appliedMs = baseline.summary.meanMs, baselineMs = baseline.summary.meanMs })`],
  'verify-first-failure-ignored': ['Bench.lua', `        if not applied.ok then return stop(applied.reason) end`, `        if not applied.ok then local _ = stop end`],
  'verify-baseline-failure-ignored': ['Bench.lua', `            if not baseline.ok then return stop("baseline " .. tostring(baseline.reason)) end`, `            if not baseline.ok then local _ = stop end`],

  // The check lines in the chart model (crowd test, Task 5)
  'check-uses-raw-applied': ['Recommend.lua', `        measuredFps = 1000 / (result.nowMs * verify.appliedMs / verify.baselineMs)`, `        measuredFps = 1000 / verify.appliedMs`],
  'check-optimistic-never': ['Recommend.lua', `        if measuredFps < 0.75 * result.afterFps then`, `        if false then`],
  'check-optimistic-always': ['Recommend.lua', `        if measuredFps < 0.75 * result.afterFps then`, `        if true then`],
  'check-label-unmarked': ['Recommend.lua', `            label = "With these changes: about " .. whole(measuredFps) .. " fps (measured)",`, `            label = "With these changes: about " .. whole(measuredFps) .. " fps",`],
  'check-scale-ignores-measured': ['Recommend.lua', `    if result.status == "change" then biggest = math.max(biggest, measuredFps or result.afterFps) end`, `    if result.status == "change" then biggest = math.max(biggest, result.afterFps) end`],
  'check-shown-without-change': ['Recommend.lua', `    if result.status == "change" and type(verify) == "table" and verify.ok == true`, `    if type(verify) == "table" and verify.ok == true`],
  'check-expected-uses-now': ['Recommend.lua', `        model.checkLines[1] = "Checked: expected about " .. whole(result.afterFps) .. " fps, measured about "`, `        model.checkLines[1] = "Checked: expected about " .. whole(result.nowFps) .. " fps, measured about "`],
  'check-zero-baseline-accepted': ['Recommend.lua', `        and type(verify.baselineMs) == "number" and verify.baselineMs > 0 then`, `        and type(verify.baselineMs) == "number" then`],

  // Quick or Thorough in the guided window (crowd test, Task 6)
  'mode-default-thorough': ['Guide.lua', `            state.mode = mode == "thorough" and "thorough" or "quick"`, `            state.mode = mode == "quick" and "quick" or "thorough"`],
  'mode-saved-on-click': ['Guide.lua', `(mode == "quick" or mode == "thorough") then
        state.mode = mode`, `(mode == "quick" or mode == "thorough") then
        state.mode = mode
        if ns.ui and ns.ui.state() then ns.ui.state().mode = mode end`],
  'start-ignores-mode': ['Guide.lua', `        ns.bench.run(onDone, { levels = mode == "thorough" and "all" or "quick", kind = "setup", silent = true })`, `        ns.bench.run(onDone, { levels = "all", kind = "setup", silent = true })`],
  'mode-not-saved': ['Guide.lua', `            saved.mode = mode == "thorough" and "thorough" or "quick"`, `            local _ = mode`],
  'mode-buttons-never-hidden': ['Guide.lua', `        for _, button in ipairs(p.modes) do button:Hide() end`, `        local _ = p.modes`],
  'mode-lost-on-again': ['Guide.lua', `            if mode then state.mode = mode end`, `            local _ = mode`],
  'mode-thorough-minutes-from-selected': ['Guide.lua', `{ key = "thorough", text = label("Thorough", by.thorough or ctx.windows) },`, `{ key = "thorough", text = label("Thorough", ctx.windows) },`],
  'mode-thorough-estimate-is-quick': ['Guide.lua', `thorough = ns.bench.estimateSetupWindows("all") }`, `thorough = ns.bench.estimateSetupWindows("quick") }`],
  'mode-first-line-ignores-selection': ['Guide.lua', `        ctx.windows = ctx.windowsByMode[state.mode == "thorough" and "thorough" or "quick"]`, `        ctx.windows = ctx.windowsByMode.quick`],
  'mode-accepts-unknown': ['Guide.lua', `state.kind == "setup" and (mode == "quick" or mode == "thorough") then`, `state.kind == "setup" and mode ~= nil then`],

  // The crowd kind of the guided window (crowd test, Task 7)
  'crowd-opens-without-quiet': ['Guide.lua', `            state.missing = guide.findQuiet() == nil`, `            state.missing = false`],
  'crowd-missing-view-off': ['Guide.lua', `        if crowd and state.missing then`, `        if false then`],
  'quiet-picks-crowd-entry': ['Guide.lua', `        if entry.valid == true and not entry.label and entry.kind ~= "crowd" and type(entry.rows) == "table" and #entry.rows > 0 then`, `        if entry.valid == true and not entry.label and type(entry.rows) == "table" and #entry.rows > 0 then`],
  'quiet-picks-mark': ['Guide.lua', `        if entry.valid == true and not entry.label and entry.kind ~= "crowd" and type(entry.rows) == "table" and #entry.rows > 0 then`, `        if entry.valid == true and entry.kind ~= "crowd" and type(entry.rows) == "table" and #entry.rows > 0 then`],
  'quiet-accepts-empty-rows': ['Guide.lua', `        if entry.valid == true and not entry.label and entry.kind ~= "crowd" and type(entry.rows) == "table" and #entry.rows > 0 then`, `        if entry.valid == true and not entry.label and entry.kind ~= "crowd" and type(entry.rows) == "table" then`],
  'crowd-target-default-wrong': ['Guide.lua', `            state.target = listedTarget(saved) and saved or 60`, `            state.target = listedTarget(saved) and saved or 90`],
  'crowd-target-saved-on-click': ['Guide.lua', `        state.target = n
        draw()`, `        state.target = n
        if state.kind == "crowd" and ns.ui and ns.ui.state() then ns.ui.state().crowdTarget = n end
        draw()`],
  'crowd-start-without-target': ['Guide.lua', `state.ticked == true and ((not setup and not crowd) or state.target ~= nil))`, `state.ticked == true and ((not setup) or state.target ~= nil))`],
  'crowd-learns': ['Guide.lua', `    elseif kind == "crowd" and saved then
        saved.crowdTarget = target`, `    elseif kind == "crowd" and saved then
        ns.bench.learn()
        saved.crowdTarget = target`],
  'crowd-handoff-raw': ['Guide.lua', `                if kind == "crowd" then entry = ns.recommend.crowdEntry(quiet, measurement) end`, `                if false then entry = ns.recommend.crowdEntry(quiet, measurement) end`],
  'crowd-invalid-hands-off': ['Guide.lua', `        if (kind == "setup" or kind == "crowd") and state.view == "done" and ns.results then`, `        if (kind == "setup" or kind == "crowd") and ns.results then`],
  'crowd-opens-report': ['Guide.lua', `        and (state.kind == "run" or state.kind == "setup" or state.kind == "crowd")`, `        and (state.kind == "run" or state.kind == "setup")`],
  'crowd-targets-always': ['Guide.lua', `        if crowd then
            view.targets = {`, `        if true then
            view.targets = {`],
  'crowd-rules-quiet': ['Guide.lua', `CROWD_RULES[3] = "- Stand still somewhere busy, such as a city's main square."`, `CROWD_RULES[3] = RULES[3]`],
  'crowd-estimate-fixed': ['Guide.lua', `        ctx.windows = ns.bench.estimateCrowdWindows(guide.findQuiet())`, `        ctx.windows = 17`],
  'crowd-start-without-quiet': ['Guide.lua', `        if not quiet then
            state = { view = "stopped", kind = kind, reason = "no quiet result", target = target }`, `        if false then
            state = { view = "stopped", kind = kind, reason = "no quiet result", target = target }`],

  // The check step of the guided window (crowd test, Task 8)
  'check-skipped': ['Guide.lua', `            if choice.status == "change" and ns.bench.verify then`, `            if false then`],
  'check-values-wrong-level': ['Guide.lua', `                for _, change in ipairs(choice.changes) do values[change.cvar] = change.to end`, `                for _, change in ipairs(choice.changes) do values[change.cvar] = change.from end`],
  'check-for-nochange': ['Guide.lua', `            if choice.status == "change" and ns.bench.verify then`, `            if choice.status ~= "invalid" and ns.bench.verify then`],
  'check-failure-blocks-results': ['Guide.lua', `                    showResults(shown, verify)
                end, { silent = true })`, `                    if verify then showResults(shown, verify) end
                end, { silent = true })`],
  'check-stop-ignored': ['Guide.lua', `    elseif key == "stop" then
        ns.bench.stop()`, `    elseif key == "stop" then
        if not state.checking then ns.bench.stop() end`],
  'check-watch-kept': ['Guide.lua', `                    ns.bench.watch = nil
                    local verify`, `                    local verify`],
  'check-watch-not-set': ['Guide.lua', `                ns.bench.watch = guide.panelReason
                draw()
                ns.bench.verify(`, `                draw()
                ns.bench.verify(`],
  'check-not-for-crowd': ['Guide.lua', `                return entry, ns.recommend.choose(entry, target)`, `                local picked = ns.recommend.choose(entry, target)
                if kind == "crowd" then picked.status = "nochange" end
                return entry, picked`],
  'check-not-stored': ['Guide.lua', `                        measurement.verify = { predictedMs = choice.afterMs,
                            measuredMs = choice.nowMs * check.appliedMs / check.baselineMs }`, `                        local _ = measurement`],
  'check-failure-treated-as-success': ['Guide.lua', `                    if check and check.ok == true then`, `                    if check and check.ok ~= nil then`],
  'check-state-unmarked': ['Guide.lua', `                state = { view = "running", kind = kind, started = true, checking = true, target = target, mode = mode }`, `                state = { view = "running", kind = kind, started = true, target = target, mode = mode }`],
  'checking-text-changed': ['Guide.lua', `            view.progress = { "Checking the result..." }`, `            view.progress = { "Checking..." }`],

  // The crowd's results window (crowd test, Task 9)
  'crowd-applies-to-everyday': ['Results.lua', `    local profile = profileOf(current.result)
    local ok, info = ns.profiles.adopt(profile, values, true)`, `    local profile = "everyday"
    local ok, info = ns.profiles.adopt(profile, values, true)`],
  'crowd-label-uses-everyday': ['Results.lua', `        local profile = profileOf(current.result)
        local replace =`, `        local profile = "everyday"
        local replace =`],
  'crowd-saved-line-everyday': ['Results.lua', `        local line = profile == "crowded" and SAVED_CROWD or SAVED`, `        local line = SAVED`],
  'check-lines-never': ['Results.lua', `    if #m.checkLines > 0 then paragraph(table.concat(m.checkLines, "\\n")) end`, `    if false then paragraph(table.concat(m.checkLines, "\\n")) end`],
  'after-bar-ignores-measured': ['Results.lua', `    local model = ns.recommend.chartModel(result, verify)`, `    local model = ns.recommend.chartModel(result)`],
  'hint-not-drawn': ['Results.lua', `    paragraph(m.hint)`, `    local _ = m.hint`],
  'title-fixed': ['Results.lua', `    p.title:SetText(m.title or "Your best settings")`, `    p.title:SetText("Your best settings")`],
  'crowd-unreachable-offers-apply': ['Results.lua', `    if m.saveKind and not current.saved then`, `    if (m.saveKind or current.result.kind == "crowd") and not current.saved then`],

  // The crowd route and menu item (crowd test, Task 10)
  'slash-crowd-wrong-kind': ['ForeverSettings.lua', `            ns.guide.open("crowd")`, `            ns.guide.open("setup")`],
  'slash-crowd-without-guide-silent': ['ForeverSettings.lua', `            ns.guide.open("crowd")
        else
            say("guide module not loaded")`, `            ns.guide.open("crowd")
        else
            local _ = nil`],
  'menu-crowd-enabled-in-combat': ['UI.lua', `    add({ text = "Find my crowded settings", kind = "button", disabled = busy, done = saved.crowded == true,`, `    add({ text = "Find my crowded settings", kind = "button", disabled = false, done = saved.crowded == true,`],
  'menu-crowd-wrong-kind': ['UI.lua', `        run = function() ui.openSaved("crowded") end })`, `        run = function() ui.openSaved("best") end })`],
  'menu-crowd-order': ['UI.lua', `    add({ text = "Find my best settings", kind = "button", disabled = busy, done = saved.best == true,
        run = function() ui.openSaved("best") end })
    add({ text = "Find my crowded settings", kind = "button", disabled = busy, done = saved.crowded == true,
        run = function() ui.openSaved("crowded") end })`, `    add({ text = "Find my crowded settings", kind = "button", disabled = busy, done = saved.crowded == true,
        run = function() ui.openSaved("crowded") end })
    add({ text = "Find my best settings", kind = "button", disabled = busy, done = saved.best == true,
        run = function() ui.openSaved("best") end })`],
  'menu-crowd-without-guide-silent': ['UI.lua', `        ns.guide.open(kind == "best" and "setup" or "crowd")
    else
        ns.say("guide module not loaded")`, `        ns.guide.open(kind == "best" and "setup" or "crowd")
    else
        local _ = nil`],

  // Fix pass after the fresh review
  'crowd-lowest-scaled': ['Recommend.lua', `        if saved and tonumber(item.value) == tonumber(c.lowValue) then delta = saved end`, `        local _ = saved`],
  'crowd-nodata-quiet-text': ['Recommend.lua', `        result.summary = crowd and NODATA_CROWD or NODATA`, `        result.summary = NODATA`],
  'crowd-nodata-text-changed': ['Recommend.lua', `steady reading in this crowd,`, `steady reading here,`],
  'prepare-failure-ignored': ['Guide.lua', `            if not prepared then`, `            if false then`],
  'prepare-failure-not-shown': ['Guide.lua', `                ns.say("the results could not be prepared: " .. tostring(shown))
                present()`, `                ns.say("the results could not be prepared: " .. tostring(shown))
                local _ = nil`],

  // The plain words (words and menu, Task 1)
  'names-row-missing': ['Names.lua', `    { "giQuality", "Light bounce", LIGHT },`, ``],
  'names-line-changed': ['Names.lua', `"How detailed water and other liquids look."`, `"Water."`],
  'names-unknown-returns-nil': ['Names.lua', `    return cvar, nil`, `    return nil, nil`],
  'names-case-sensitive': ['Names.lua', `    return type(cvar) == "string" and INFO[cvar:lower()] or nil`, `    return type(cvar) == "string" and INFO[cvar] or nil`],
  'names-fallback-beats-known': ['Names.lua', `    if found then return found.name end`, `    if found and not fallback then return found.name end`],
  'level-percent-off': ['Names.lua', `        if n then return string.format("%.0f%%", n * 100) end`, `        if n then return value end`],
  'level-percent-not-rounded': ['Names.lua', `string.format("%.0f%%", n * 100)`, `string.format("%.1f%%", n * 100)`],
  'level-position-ignored': ['Names.lua', `    if info(cvar) and position == "lowest" then return value .. " (lowest)" end`, `    if false then return value .. " (lowest)" end`],
  'level-position-on-percent': ['Names.lua', `        if n then return string.format("%.0f%%", n * 100) end`, `        if n then return string.format("%.0f%%", n * 100) .. (position == "lowest" and " (lowest)" or "") end`],
  'progress-start-text': ['Names.lua', `        return "Getting a steady starting speed"`, `        return "Getting started"`],
  'progress-after-ignores-cvar': ['Names.lua', `        if p.cvar then return "Checking the speed again after " .. names.label(p.cvar, p.label) end`, `        if false then return "Checking the speed again after " .. names.label(p.cvar, p.label) end`],
  'progress-level-raw': ['Names.lua', `text .. ", level " .. names.level(p.cvar, tostring(p.value))`, `text .. ", level " .. tostring(p.value)`],
  'ago-singular-wrong': ['Names.lua', `(n == 1 and "" or "s")`, `"s"`],
  'ago-hours-as-minutes': ['Names.lua', `return unit(math.floor(seconds / 3600), "hour") end`, `return unit(math.floor(seconds / 60), "hour") end`],
  'measured-unknown-zone-printed': ['Names.lua', `type(zone) == "string" and zone ~= "" and zone ~= "unknown" then`, `type(zone) == "string" and zone ~= "" then`],

  // Silent edits and edits to a named profile (words and menu, Task 2)
  'set-profile-value-writes-cvar': ['Profiles.lua', `    db.profiles[name].values[cvar] = value
    return true`, `    db.profiles[name].values[cvar] = value
    pcall(SetCVar, cvar, value)
    return true`],
  'set-profile-value-changes-want': ['Profiles.lua', `    db.profiles[name].values[cvar] = value
    return true`, `    db.profiles[name].values[cvar] = value
    db.want = profiles.plan(name).want
    return true`],
  'set-profile-value-ignores-busy': ['Profiles.lua', `    if refuseIfBusy(silent) then return false, "busy" end
    db.profiles[name].values[cvar] = value`, `    db.profiles[name].values[cvar] = value`],
  'set-profile-value-active-skips-apply': ['Profiles.lua', `    if db.active == name then return profiles.setValue(cvar, value, silent) end`, `    if false then return profiles.setValue(cvar, value, silent) end`],
  'set-profile-value-original-ok': ['Profiles.lua', `        return false, "original"
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if db.active == name then return profiles.setValue(cvar, value, silent) end`, `        return true
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if db.active == name then return profiles.setValue(cvar, value, silent) end`],
  'unset-profile-value-active-wrong': ['Profiles.lua', `    if db.active == name then return profiles.unsetValue(cvar, silent) end`, `    if false then return profiles.unsetValue(cvar, silent) end`],
  'unset-profile-value-absent-true': ['Profiles.lua', `        speak(silent, "'" .. friendly(cvar) .. "' is not in the list")
        return false
    end
    profile.values[cvar] = nil
    return true`, `        speak(silent, "'" .. friendly(cvar) .. "' is not in the list")
        return true
    end
    profile.values[cvar] = nil
    return true`],
  'silent-ignored-set': ['Profiles.lua', `    speak(silent, "keeping " .. friendly(cvar) .. " at " .. value)`, `    ns.say("keeping " .. friendly(cvar) .. " at " .. value)`],
  'silent-ignored-unset': ['Profiles.lua', `    speak(silent, "no longer forcing " .. friendly(cvar) .. " (its current value is left as it is)")`, `    ns.say("no longer forcing " .. friendly(cvar) .. " (its current value is left as it is)")`],
  'silent-ignored-save': ['Profiles.lua', `    speak(silent, "Saved " .. plural(count, "setting") .. " as " .. profiles.LABEL[name])`, `    ns.say("Saved " .. plural(count, "setting") .. " as " .. profiles.LABEL[name])`],
  'silent-not-passed-to-applyall': ['Profiles.lua', `    ns.applyAll(true, silent)`, `    ns.applyAll(true)`],
  'applyall-silent-ignored': ['ForeverSettings.lua', `    local say = silent and function() end or say`, `    local say = say`],
  'friendly-raw': ['Profiles.lua', `    if ns.names then return ns.names.label(cvar, label) end`, `    if false then return ns.names.label(cvar, label) end`],

  // The My settings window (words and menu, Task 3)
  'settings-default-tab-wrong': ['Settings.lua', `    return ns.profiles and ns.profiles.active() == "crowded" and "crowded" or "everyday"`, `    return "crowded"`],
  'settings-original-note-missing': ['Settings.lua', `    if ctx.active == "original" then
        view.notice = ORIGINAL_NOTE`, `    if false then
        view.notice = ORIGINAL_NOTE`],
  'settings-tab-in-use-mark-missing': ['Settings.lua', `text = TAB_TEXT[key] .. (inUse and " (in use)" or ""),`, `text = TAB_TEXT[key],`],
  'settings-order-reversed': ['Settings.lua', `        if ra ~= rb then return ra < rb end`, `        if ra ~= rb then return ra > rb end`],
  'settings-lowest-mark-missing': ['Settings.lua', `            if i == 1 then position = "lowest" elseif i == #entry.tiers then position = "highest" end`, `            if i == #entry.tiers then position = "highest" end`],
  'settings-active-highlights-saved': ['Settings.lua', `        if onTabInUse then chosen = ctx.live(cvar) end`, `        if false then chosen = ctx.live(cvar) end`],
  'settings-other-highlights-live': ['Settings.lua', `    local onTabInUse = st.tab == ctx.active`, `    local onTabInUse = true`],
  'settings-kept-ignores-saved': ['Settings.lua', `kept = saved[cvar] ~= nil,`, `kept = false,`],
  'settings-click-active-stores-only': ['Settings.lua', `        ns.profiles.setProfileValue(profile, pickedCvar, value, true)`, `        ns.profiles.state().profiles[profile].values[pickedCvar] = value`],
  'settings-click-other-writes-cvar': ['Settings.lua', `        ns.profiles.setProfileValue(profile, pickedCvar, value, true)
        draw()`, `        ns.profiles.setProfileValue(profile, pickedCvar, value, true)
        pcall(SetCVar, pickedCvar, value)
        draw()`],
  'settings-untick-other-keeps': ['Settings.lua', `            ns.profiles.unsetProfileValue(profile, cvar, true)`, `            if profile == ns.profiles.active() then ns.profiles.unsetProfileValue(profile, cvar, true) end`],
  'settings-tick-wrong-value': ['Settings.lua', `ns.profiles.setProfileValue(profile, cvar, now, true)`, `ns.profiles.setProfileValue(profile, cvar, "0", true)`],
  'settings-lock-not-checked': ['Settings.lua', `    if ctx.locked then
        if key == "maximum" then draw() end          -- the draw says why (the window may not have caught up yet)
        return
    end
    local tab = key:match("^tab:(.+)$")`, `    local tab = key:match("^tab:(.+)$")`],
  'settings-lock-tabs-live': ['Settings.lua', `            note = names.PROFILE_NOTE[key], enabled = locked == nil,`, `            note = names.PROFILE_NOTE[key], enabled = true,`],
  'settings-use-wrong-profile': ['Settings.lua', `        ns.profiles.save(profile, true)`, `        ns.profiles.save("everyday", true)`],
  'settings-refresh-missing': ['Settings.lua', `        if signature(context()) ~= lastSignature then draw() end`, `        if false then draw() end`],
  'settings-prints': ['Settings.lua', `        ns.profiles.setProfileValue(profile, pickedCvar, value, true)`, `        ns.profiles.setProfileValue(profile, pickedCvar, value)`],
  'settings-row-shows-raw-name': ['Settings.lua', `        name:SetText(row.name)`, `        name:SetText(row.cvar)`],
  'slash-settings-wrong-silent': ['ForeverSettings.lua', `            ns.settings.open()
        else
            say("settings module not loaded")`, `            ns.settings.open()
        else
            local _ = nil`],

  // Results that survive, and progress that names its setting (words and menu, Task 4)
  'protect-quiet-off': ['Bench.lua', `                keepQuiet = keepQuiet or e`, `                local _ = e`],
  'protect-crowd-off': ['Bench.lua', `                keepCrowd = keepCrowd or e`, `                local _ = e`],
  'protect-invalid': ['Bench.lua', `            elseif e.valid == true and not e.label and type(e.rows) == "table" and #e.rows > 0 then`, `            elseif not e.label and type(e.rows) == "table" and #e.rows > 0 then`],
  'protect-all-falls-back-off': ['Bench.lua', `        local drop = 1`, `        local drop = #h`],
  'quiettime-missing': ['Bench.lua', `starts = currents, quietTime = quiet.time,`, `starts = currents,`],
  'progress-cvar-missing': ['Bench.lua', `        cvar = progressState.cvar, value = progressState.value, repeats = progressState.repeats or 0 }`, `        repeats = progressState.repeats or 0 }`],
  'progress-start-has-cvar': ['Bench.lua', `        baselineWindow("start", function(r)`, `        nextInfo = { cvar = "RenderScale" }
        baselineWindow("start", function(r)`],
  'progress-sweep-value-missing': ['Bench.lua', `nextInfo = { cvar = setting.cvar, value = value }`, `nextInfo = { cvar = setting.cvar }`],
  'progress-after-cvar-missing': ['Bench.lua', `                nextInfo = { cvar = setting.cvar }
                baselineWindow("after " .. setting.label, function(b)`, `                baselineWindow("after " .. setting.label, function(b)`],
  'progress-control-cvar-missing': ['Bench.lua', `        nextInfo = { cvar = control.cvar }
        window("control", control.label, function(c0)`, `        window("control", control.label, function(c0)`],
  'crowd-progress-sweep-value-missing': ['Bench.lua', `nextInfo = { cvar = item.cvar, value = item.lowValue }`, `nextInfo = { cvar = item.cvar }`],

  // Plain words in the guided window (words and menu, Task 5)
  'guide-progress-raw-label': ['Guide.lua', `                ns.names and ns.names.progress(p) or ("Now testing: " .. tostring(p.label)) }`, `                "Now testing: " .. tostring(p.label) }`],
  'guide-progress-ignores-cvar': ['Guide.lua', `ns.names and ns.names.progress(p) or`, `ns.names and ns.names.progress({ phase = p.phase, label = p.label, value = p.value }) or`],

  // Plain words and the extras of a saved result (words and menu, Task 6)
  'chart-name-raw': ['Recommend.lua', `nameOf(c.cvar, c.setting) .. ": " .. levelText(c.cvar, c.from) .. " to "`, `c.setting .. ": " .. levelText(c.cvar, c.from) .. " to "`],
  'chart-level-raw': ['Recommend.lua', `.. levelText(c.cvar, c.to) .. ", "`, `.. c.to .. ", "`],
  'chart-value-replaced': ['Recommend.lua', `value = level.value, text = levelText(s.cvar, level.value), fps = fps,`, `value = levelText(s.cvar, level.value), text = levelText(s.cvar, level.value), fps = fps,`],
  'chart-notmeasured-raw': ['Recommend.lua', `name = nameOf(n.cvar, n.setting), cvar = n.cvar, reason = n.reason,`, `name = n.setting, cvar = n.cvar, reason = n.reason,`],
  'chart-name-ignores-cvar': ['Recommend.lua', `cvar = s.cvar, name = nameOf(s.cvar, s.setting), changed = changing`, `cvar = s.cvar, name = s.setting, changed = changing`],
  'chart-names-required': ['Recommend.lua', `    if ns.names then return ns.names.label(cvar, fallback) end
    return fallback`, `    return ns.names.label(cvar, fallback)`],
  'results-text-raw': ['Results.lua', `        row.label:SetText(item.name)`, `        row.label:SetText(item.cvar)`],
  'results-level-raw': ['Graph.lua', `                    say(p.text, item.x - 20, plot.y + plot.height + 6, 40)`, `                    say(p.value, item.x - 20, plot.y + plot.height + 6, 40)`],
  'results-notmeasured-raw': ['Results.lua', `put(p.fsPanel, chosen.name .. ": not measured (" ..`, `put(p.fsPanel, chosen.cvar .. ": not measured (" ..`],
  'results-measured-missing': ['Results.lua', `    paragraph(current.extras and current.extras.measuredLine)`, `    local _ = current.extras`],
  'results-again-missing': ['Results.lua', `    if current.extras and current.extras.again then specs[#specs + 1] = { key = "again", text = "Run it again" } end`, `    if false then specs[#specs + 1] = { key = "again", text = "Run it again" } end`],
  'results-again-always': ['Results.lua', `    if current.extras and current.extras.again then specs[#specs + 1] = { key = "again", text = "Run it again" } end`, `    if true then specs[#specs + 1] = { key = "again", text = "Run it again" } end`],
  'results-again-wrong-kind': ['Results.lua', `ns.guide.open(kind)`, `ns.guide.open("setup")`],
  'results-again-keeps-window': ['Results.lua', `        local kind = current.extras and current.extras.again
        results.hide()`, `        local kind = current.extras and current.extras.again`],
  'results-third-button-missing': ['Results.lua', `    p.buttons = { makeButton(f), makeButton(f), makeButton(f) }`, `    p.buttons = { makeButton(f), makeButton(f) }`],

  // The plain menu and the saved results behind its green checks (words and menu, Task 7)
  'menu-order-wrong': ['UI.lua', `    add(profileItem("everyday"))
    add(profileItem("crowded"))`, `    add(profileItem("crowded"))
    add(profileItem("everyday"))`],
  'menu-profile-text-raw': ['UI.lua', `local text = ns.names and ns.names.PROFILE[key] or key`, `local text = key`],
  'menu-done-always': ['UI.lua', `kind = "button", disabled = busy, done = saved.best == true,`, `kind = "button", disabled = busy, done = true,`],
  'menu-done-never': ['UI.lua', `kind = "button", disabled = busy, done = saved.crowded == true,`, `kind = "button", disabled = busy, done = false,`],
  'menu-done-swapped': ['UI.lua', `kind = "button", disabled = busy, done = saved.best == true,`, `kind = "button", disabled = busy, done = saved.crowded == true,`],
  'menu-click-ignores-saved': ['UI.lua', `    local saved = ui.savedResult(kind)
    if saved and ns.results and ns.results.show then`, `    local saved = ui.savedResult(kind)
    if false then`],
  'menu-click-always-opens-saved': ['UI.lua', `    local saved = ui.savedResult(kind)
    if saved and ns.results and ns.results.show then`, `    local saved = ui.savedResult(kind) or { entry = {} }
    if saved and ns.results and ns.results.show then`],
  'menu-click-guide-wrong-kind': ['UI.lua', `        ns.guide.open(kind == "best" and "setup" or "crowd")`, `        ns.guide.open("setup")`],
  'saved-target-not-required': ['UI.lua', `    if kind == "best" then
        if not listedTarget(st.target) then return nil end`, `    if kind == "best" then
        if false then return nil end`],
  'saved-quiet-not-required': ['UI.lua', `    local quiet = ns.guide.findQuiet()
    if not quiet then return nil end`, `    local quiet = ns.guide.findQuiet()
    if not quiet then quiet = {} end`],
  'saved-crowd-target-not-required': ['UI.lua', `        if not listedTarget(st.crowdTarget) then return nil end`, `        if false then return nil end`],
  'saved-invalid-crowd-accepted': ['UI.lua', `            if history[i].kind == "crowd" and history[i].valid == true then`, `            if history[i].kind == "crowd" then`],
  'saved-crowd-uses-newest-quiet': ['UI.lua', `        if crowd.quietTime then`, `        if false then`],
  'saved-crowd-first-quiet': ['UI.lua', `                if entry.time == crowd.quietTime and entry.kind ~= "crowd"`, `                if entry.kind ~= "crowd"`],
  'saved-crowd-entry-raw': ['UI.lua', `entry = ns.recommend.crowdEntry(base, crowd), target = st.crowdTarget,`, `entry = crowd, target = st.crowdTarget,`],
  'saved-best-target-wrong': ['UI.lua', `return { kind = "best", entry = quiet, target = st.target,`, `return { kind = "best", entry = quiet, target = st.crowdTarget,`],
  'saved-crowd-target-wrong': ['UI.lua', `target = st.crowdTarget,
            verify = verifyOf(crowd), again = "crowd",`, `target = st.target,
            verify = verifyOf(crowd), again = "crowd",`],
  'saved-best-again-wrong': ['UI.lua', `verify = verifyOf(quiet), again = "setup",`, `verify = verifyOf(quiet), again = "crowd",`],
  'saved-crowd-again-wrong': ['UI.lua', `verify = verifyOf(crowd), again = "crowd",`, `verify = verifyOf(crowd), again = "setup",`],
  'saved-verify-dropped': ['UI.lua', `        return { ok = true, appliedMs = v.measuredMs, baselineMs = measurement.baselineMs }
    end
    return nil`, `        return nil
    end
    return nil`],
  'saved-verify-raw': ['UI.lua', `        return { ok = true, appliedMs = v.measuredMs, baselineMs = measurement.baselineMs }`, `        return v`],
  'saved-verify-baseline-wrong': ['UI.lua', `baselineMs = measurement.baselineMs }`, `baselineMs = v.measuredMs }`],
  'saved-verify-fabricated': ['UI.lua', `    end
    return nil
end

-- "Measured in`, `    end
    return { ok = false }
end

-- "Measured in`],
  'saved-measured-line-off': ['UI.lua', `    return ns.names and ns.names.measured(measurement.zone, seconds) or nil`, `    return nil`],
  'saved-click-drops-extras': ['UI.lua', `            { again = saved.again, measuredLine = saved.measuredLine })`, `            {})`],
  'saved-click-unguarded': ['UI.lua', `        local ok, err = pcall(ns.results.show, saved.entry, saved.target, saved.verify,
            { again = saved.again, measuredLine = saved.measuredLine })
        if not ok then ns.say("the saved result could not be shown: " .. tostring(err)) end`, `        ns.results.show(saved.entry, saved.target, saved.verify, { again = saved.again, measuredLine = saved.measuredLine })`],
  'saved-click-silent-failure': ['UI.lua', `        if not ok then ns.say("the saved result could not be shown: " .. tostring(err)) end`, `        local _ = ok`],
  'saved-context-best-wrong': ['UI.lua', `ctx.saved = { best = ui.savedResult("best") ~= nil,`, `ctx.saved = { best = ui.savedResult("crowded") ~= nil,`],
  'saved-context-crowded-wrong': ['UI.lua', `crowded = ui.savedResult("crowded") ~= nil }`, `crowded = ui.savedResult("best") ~= nil }`],
  'menu-status-hidden-while-running': ['UI.lua', `    if progress then
        add({ text = string.format("A test is running: step`, `    if progress and not ctx.active then
        add({ text = string.format("A test is running: step`],
  'menu-status-raw-label': ['UI.lua', `ns.names and ns.names.progress(progress) or tostring(progress.label)), kind = "info"`, `tostring(progress.label)), kind = "info"`],
  'menu-advanced-missing-item': ['UI.lua', `        { text = "Apply all now", kind = "button", disabled = locked, run = command("apply") },
`, ``],
  'menu-advanced-report-enabled-always': ['UI.lua', `kind = "button", disabled = ctx.last == nil,`, `kind = "button", disabled = false,`],
  'menu-raw-name': ['UI.lua', `    add({ text = "Find my best settings", kind = "button"`, `    add({ text = "Find my best settings (graphicsShadowQuality)", kind = "button"`],
  'menu-settings-without-module-silent': ['UI.lua', `if ns.settings and ns.settings.open then ns.settings.open() else ns.say("settings module not loaded") end`, `if ns.settings and ns.settings.open then ns.settings.open() end`],
  'menu-settings-never-opens': ['UI.lua', `if ns.settings and ns.settings.open then ns.settings.open() else ns.say("settings module not loaded") end`, `if ns.settings and ns.settings.open then local _ = ns.settings.open else ns.say("settings module not loaded") end`],
  'menu-adapter-check-missing': ['UI.lua', `                local element = parent:CreateButton(item.done and (CHECK .. item.text) or item.text, item.run)`, `                local element = parent:CreateButton(item.text, item.run)`],
  'menu-adapter-check-on-all': ['UI.lua', `                local element = parent:CreateButton(item.done and (CHECK .. item.text) or item.text, item.run)`, `                local element = parent:CreateButton(CHECK .. item.text, item.run)`],
  'menu-adapter-old-check-missing': ['UI.lua', `                info.text = item.done and (CHECK .. item.text) or item.text`, `                info.text = item.text`],
  'menu-adapter-old-check-on-all': ['UI.lua', `                info.text = item.done and (CHECK .. item.text) or item.text`, `                info.text = CHECK .. item.text`],
  'menu-tooltip-progress-raw': ['UI.lua', `        ns.names and ns.names.progress(p) or tostring(p.label)) or "no test running")`, `        tostring(p.label)) or "no test running")`],

  // Fix pass after the fresh review of the whole build (words and menu, Task 8)
  'tooltip-jargon-back': ['UI.lua', `"Keeping %d setting%s for you"`, `"%d forced setting%s"`],
  'tooltip-plural-off': ['UI.lua', `for you", forced, forced == 1 and "" or "s"))`, `for you", forced, ""))`],
  'tooltip-count-wrong': ['UI.lua', `for _ in pairs(db.want) do forced = forced + 1 end`, `for _ in pairs(db.want) do forced = 1 end`],
  'profile-empty-hint-stale': ['Profiles.lua', `choose some in My settings (minimap menu), or set`, `set things up in the game menu, then Save current settings as Everyday, or set`],
  'profile-twin-hint-stale': ['Profiles.lua', `change a setting in My settings (minimap menu)")`, `change a setting (/fset set or the Tiers menu)")`],

  // A quiet guided test (results window, Task 1)
  'quiet-env-always': ['Bench.lua', `    if silent then return end
    local all = {}`, `    local all = {}`],
  'quiet-report-always': ['Bench.lua', `            starts = currents,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)
            if not opts.silent then`, `            starts = currents,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)
            if true then`],
  'quiet-refusal-prints': ['Bench.lua', `        for _, p in ipairs(problems) do say("cannot run: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    local resolved, skipped = bench.resolve()`, `        for _, p in ipairs(problems) do ns.say("cannot run: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    local resolved, skipped = bench.resolve()`],
  'quiet-nothing-to-measure-prints': ['Bench.lua', `        say("nothing to measure: no setting has both a CVar in this client and known tiers")`, `        ns.say("nothing to measure: no setting has both a CVar in this client and known tiers")`],
  'quiet-stop-prints': ['Bench.lua', `    local function abort(reason)
        say("run stopped: " .. tostring(reason))
        conclude(false, reason)
    end
    -- Set just before a window starts`, `    local function abort(reason)
        ns.say("run stopped: " .. tostring(reason))
        conclude(false, reason)
    end
    -- Set just before a window starts`],
  'quiet-restore-silenced': ['Bench.lua', `        ns.say("in combat: your settings will be restored when combat ends")`, `        local _ = deferred`],
  'quiet-warning-silenced': ['Bench.lua', `    sayEnvironment(env, opts.silent)
    for _, w in ipairs(warnings) do ns.say("warning: " .. w) end
    if not ok then
        for _, p in ipairs(problems) do say("cannot run: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    local resolved, skipped`, `    sayEnvironment(env, opts.silent)
    for _, w in ipairs(warnings) do say("warning: " .. w) end
    if not ok then
        for _, p in ipairs(problems) do say("cannot run: " .. p) end
        return onDone({ ok = false, reason = "preflight", problems = problems })
    end
    local resolved, skipped`],
  'quiet-warning-old-words': ['Bench.lua', `"Vsync is on, so your frame rate is capped at your screen's refresh rate and the test cannot see "`, `"vsync is on: the frame rate is capped at your refresh rate, which hides cost; "`],
  'quiet-fpscap-old-words': ['Bench.lua', `"A frame-rate limit is set in the game, so the test cannot see what settings cost above that limit. "`, `"an FPS cap is set (useMaxFPS or maxFPS): it hides cost above the cap; "`],
  'quiet-recovered-old-words': ['Bench.lua', `"Settings from an interrupted test were put back first."`, `"restored an interrupted run first"`],
  'quiet-crowd-prints': ['Bench.lua', `    local say = opts.silent and function() end or ns.say     -- see bench.run
    local ok, problems, warnings, env = bench.preflight()
    sayEnvironment(env, opts.silent)`, `    local say = ns.say     -- see bench.run
    local ok, problems, warnings, env = bench.preflight()
    sayEnvironment(env, opts.silent)`],
  'quiet-crowd-report-always': ['Bench.lua', `            kind = "crowd", settings = settings, starts = currents, quietTime = quiet.time,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)
            if not opts.silent then`, `            kind = "crowd", settings = settings, starts = currents, quietTime = quiet.time,
        }
        pushHistory(entry)
        progressState = nil
        finishRun(originals, entry, function(e)
            if true then`],
  'quiet-verify-prints': ['Bench.lua', `    local say = opts and opts.silent and function() end or ns.say     -- see bench.run`, `    local say = ns.say     -- see bench.run`],
  'quiet-guide-not-silent': ['Guide.lua', `kind = "setup", silent = true })`, `kind = "setup" })`],
  'quiet-guide-crowd-not-silent': ['Guide.lua', `ns.bench.crowd(quiet, onDone, { silent = true })`, `ns.bench.crowd(quiet, onDone)`],
  'quiet-guide-verify-not-silent': ['Guide.lua', `                end, { silent = true })
                return`, `                end)
                return`],
  'quiet-guide-run-silent': ['Guide.lua', `        ns.bench.run(onDone)
    end`, `        ns.bench.run(onDone, { silent = true })
    end`],

  // The graph model and the plain change lines (results window, Task 2)
  'graph-fps-wrong-base': ['Recommend.lua', `    return 1000 / math.max(nowMs + deltaMs, nowMs / recommend.MAX_SPEEDUP)`, `    return 1000 / math.max(nowMs - deltaMs, nowMs / recommend.MAX_SPEEDUP)`],
  'graph-no-clamp': ['Recommend.lua', `    return 1000 / math.max(nowMs + deltaMs, nowMs / recommend.MAX_SPEEDUP)`, `    return 1000 / (nowMs + deltaMs)`],
  'graph-current-not-marked': ['Recommend.lua', `fps = fps, current = level.current == true,`, `fps = fps, current = false,`],
  'graph-recommended-on-current': ['Recommend.lua', `recommended = changing and level.value == s.chosen and not level.current, doubtful = false,`, `recommended = changing and level.value == s.chosen, doubtful = false,`],
  'graph-recommended-always': ['Recommend.lua', `recommended = changing and level.value == s.chosen and not level.current, doubtful = false,`, `recommended = level.value == s.chosen and not level.current, doubtful = false,`],
  'graph-order-by-position': ['Recommend.lua', `        if a.swing ~= b.swing then return a.swing > b.swing end
        return a.position < b.position`, `        if false then return a.swing > b.swing end
        return a.position < b.position`],
  'graph-swing-zero': ['Recommend.lua', `for _, q in ipairs(points) do swing = math.max(swing, p.fps - q.fps) end`, `for _, q in ipairs(points) do swing = math.max(swing, 0) end`],
  'graph-selected-first-always': ['Recommend.lua', `        if g.changed and not model.selected then model.selected = g.cvar end`, `        if false then model.selected = g.cvar end`],
  'graph-changed-without-change': ['Recommend.lua', `changed = changing and s.chosen ~= s.current, swing = swing,`, `changed = s.chosen ~= s.current, swing = swing,`],
  'graph-notmeasured-cvar-missing': ['Recommend.lua', `name = nameOf(n.cvar, n.setting), cvar = n.cvar, reason = n.reason,`, `name = nameOf(n.cvar, n.setting), reason = n.reason,`],
  'axis-step-too-small': ['Recommend.lua', `if math.ceil(highest / s) - math.floor(lowest / s) <= 4 then`, `if math.ceil(highest / s) - math.floor(lowest / s) <= 8 then`],
  'axis-no-widen': ['Recommend.lua', `    while (hi - lo) / step + 1 < 3 do`, `    while false do`],
  'axis-widen-wrong-side': ['Recommend.lua', `        if above or lo - step < 0 then hi = hi + step else lo = lo - step end`, `        if above then lo = lo - step else hi = hi + step end`],
  'axis-below-zero': ['Recommend.lua', `        if above or lo - step < 0 then hi = hi + step else lo = lo - step end`, `        if above then hi = hi + step else lo = lo - step end`],
  'steps-three-listed': ['Recommend.lua', `        while #steps > 2 do steps[#steps] = nil end`, `        while #steps > 3 do steps[#steps] = nil end`],
  'steps-by-size-order': ['Recommend.lua', `        table.sort(steps, function(a, b) return a.at < b.at end)`, `        local _ = steps`],
  'steps-no-threshold': ['Recommend.lua', `            if cost >= 1 then steps[#steps + 1] = { at = i, cost = cost } end`, `            if cost > 0 then steps[#steps + 1] = { at = i, cost = cost } end`],
  'doubtful-zero': ['Recommend.lua', `if deltas[i] < deltas[i - 1] - recommend.DOUBTFUL * result.nowMs then`, `if deltas[i] < deltas[i - 1] then`],
  'doubtful-loose': ['Recommend.lua', `if deltas[i] < deltas[i - 1] - recommend.DOUBTFUL * result.nowMs then`, `if deltas[i] < deltas[i - 1] - 0.1 * result.nowMs then`],
  'doubtful-one-side-only': ['Recommend.lua', `points[i].doubtful, points[i - 1].doubtful, doubtful = true, true, true`, `points[i].doubtful, doubtful = true, true`],
  'doubtful-line-missing': ['Recommend.lua', `        if doubtful then lines[#lines + 1] = "Some readings look off; run the test again to confirm." end`, `        local _ = doubtful`],
  'verdict-plural-wrong': ['Recommend.lua', `(n == 1 and "This change" or ("These " .. n .. " changes"))`, `("These " .. n .. " changes")`],
  'verdict-unmeasured-figure': ['Recommend.lua', `whole(measuredFps or result.afterFps)`, `whole(result.afterFps)`],
  'lines-ms-back': ['Recommend.lua', `whole(math.abs(single)) .. " fps")`, `whole(math.abs(single)) .. " ms")`],
  'lines-verb-wrong': ['Recommend.lua', `(single >= 0 and "saves " or "costs ")`, `("saves ")`],
  'lines-small-gain-rounded': ['Recommend.lua', `local amount = math.abs(single) < 0.5 and "less than 1 fps"`, `local amount = false and "less than 1 fps"`],
  'lines-single-ignores-from': ['Recommend.lua', `local single = fpsAt(c.toDelta - c.fromDelta) - result.nowFps`, `local single = fpsAt(c.toDelta) - result.nowFps`],
  'savekind-nochange-missing': ['Recommend.lua', `(result.status == "nochange" and "current" or nil)`, `nil`],
  'savekind-invalid-set': ['Recommend.lua', `(result.status == "nochange" and "current" or nil)`, `(result.status ~= "change" and "current" or nil)`],
  'footer-overlap-missing': ['Recommend.lua', `not how the picture looks." .. OVERLAP`, `not how the picture looks."`],
  'footer-old-sentence-lost': ['Recommend.lua', `estimated from your quiet-spot test."
    .. OVERLAP`, `estimated from your quiet-spot tests."
    .. OVERLAP`],

  // Graph.lua, the drawing of one graph (results window, Task 3)
  'graph-draw-x-spacing-wrong': ['Graph.lua', `(plot.x + (k - 1) / (n - 1) * plot.width)`, `(plot.x + (k - 1) / n * plot.width)`],
  'graph-draw-y-flipped': ['Graph.lua', `        return plot.y + (1 - (fps - axis.min) / span) * plot.height`, `        return plot.y + ((fps - axis.min) / span) * plot.height`],
  'graph-draw-margin-ignored': ['Graph.lua', `        x = rect.x + m.left, y = rect.y + m.top,`, `        x = rect.x, y = rect.y,`],
  'graph-draw-single-point-edge': ['Graph.lua', `local x = n == 1 and (plot.x + plot.width / 2) or (plot.x + (k - 1) / (n - 1) * plot.width)`, `local x = plot.x + (k - 1) / (n - 1) * plot.width`],
  'graph-draw-flat-axis-divides': ['Graph.lua', `        if span <= 0 then return plot.y + plot.height / 2 end`, `        if false then return plot.y + plot.height / 2 end`],
  'graph-draw-tick-format': ['Graph.lua', `label = string.format("%.0f", t)`, `label = string.format("%.1f", t)`],
  'graph-draw-lines-off': ['Graph.lua', `    local useLines = type(parent.CreateLine) == "function"`, `    local useLines = false`],
  'graph-draw-fallback-sparse': ['Graph.lua', `local DOT, DOT_STEP = 2, 6`, `local DOT, DOT_STEP = 2, 60`],
  'graph-draw-raising-lines-fatal': ['Graph.lua', `            local ok, line = pcall(take, segments)`, `            local ok, line = true, take(segments)`],
  'graph-draw-point-size': ['Graph.lua', `local POINT, HIT, RING = 8, 14, 14`, `local POINT, HIT, RING = 10, 14, 14`],
  'graph-draw-doubtful-filled': ['Graph.lua', `                if p.doubtful then
                    outline(COLORS.hollow, item.x, item.y, POINT)`, `                if false then
                    outline(COLORS.hollow, item.x, item.y, POINT)`],
  'graph-draw-ring-missing': ['Graph.lua', `                    outline(COLORS.ring, item.x, item.y, RING)`, `                    local _ = RING`],
  'graph-draw-recommended-uncoloured': ['Graph.lua', `box(p.recommended and COLORS.recommended or COLORS.point,`, `box(COLORS.point,`],
  'graph-draw-grid-missing': ['Graph.lua', `                box(COLORS.grid, plot.x, tick.y, plot.width, 1)`, `                local _ = plot`],
  'graph-draw-axis-line-missing': ['Graph.lua', `            box(COLORS.axis, plot.x, plot.y, 1, plot.height)`, `            local _ = plot`],
  'graph-draw-tag-wrong-point': ['Graph.lua', `                if p.recommended then say("recommended", item.x - 35, item.y - TAG_RISE, 70, COLORS.recommended) end`, `                if p.current then say("recommended", item.x - 35, item.y - TAG_RISE, 70, COLORS.recommended) end`],
  'graph-draw-tag-too-high': ['Graph.lua', `                if p.recommended then say("recommended", item.x - 35, item.y - TAG_RISE, 70, COLORS.recommended) end`, `                if p.recommended then say("recommended", item.x - 35, item.y - 28, 70, COLORS.recommended) end`],
  'graph-draw-now-tag-too-high': ['Graph.lua', `                    say("now", item.x - 20, item.y - TAG_RISE, 40)`, `                    say("now", item.x - 20, item.y - 28, 40)`],
  'graph-draw-margin-top-small': ['Graph.lua', `graph.MARGIN = { left = 44, right = 14, top = 22, bottom = 26 }`, `graph.MARGIN = { left = 44, right = 14, top = 10, bottom = 26 }`],
  'graph-draw-label-all-levels': ['Graph.lua', `                if k == 1 or k == #points or p.current or p.recommended then`, `                if true then`],
  'graph-draw-label-last-missing': ['Graph.lua', `                if k == 1 or k == #points or p.current or p.recommended then`, `                if k == 1 or p.current or p.recommended then`],
  'graph-draw-tooltip-unit': ['Graph.lua', `"about %.0f fps if only this setting changes"`, `"about %.0f ms if only this setting changes"`],
  'graph-draw-doubtful-mark-missing': ['Graph.lua', `    if p.doubtful then marks[#marks + 1] = "this reading looks off" end`, `    local _ = marks`],
  'graph-draw-leave-keeps-tooltip': ['Graph.lua', `                button:SetScript("OnLeave", function() GameTooltip:Hide() end)`, `                button:SetScript("OnLeave", function() end)`],
  'graph-draw-leftover-buttons': ['Graph.lua', `        release(buttons)`, `        local _ = buttons`],
  'graph-draw-leftover-lines': ['Graph.lua', `        release(segments)`, `        local _ = segments`],
  'graph-draw-leftover-text': ['Graph.lua', `        release(strings)`, `        local _ = strings`],
  'graph-draw-leftover-boxes': ['Graph.lua', `        release(textures)`, `        local _ = textures`],
  'graph-draw-clear-keeps': ['Graph.lua', `        self:draw(nil, nil, nil)`, `        local _ = self`],
  'graph-draw-nil-axis-draws': ['Graph.lua', `        if entry and axis then`, `        if entry then`],

  // The rebuilt results window (results window, Task 4)
  'results-w2-size-old': ['Results.lua', `local WIDTH, HEIGHT = 760, 540`, `local WIDTH, HEIGHT = 680, 480`],
  'results-w2-scroll-back': ['Results.lua', `    p.panel = CreateFrame("Frame", nil, f)`, `    p.panel = CreateFrame("ScrollFrame", nil, f)`],
  'results-w2-verdict-missing': ['Results.lua', `    if m.verdict and m.verdict ~= "" then`, `    if false then`],
  'results-w2-changes-unlimited': ['Results.lua', `        if i > MAX_CHANGE_LINES then break end`, `        if false then break end`],
  'results-w2-list-reversed': ['Results.lua', `        list[#list + 1] = { cvar = g.cvar, name = g.name, changed = g.changed, graph = g }`, `        table.insert(list, 1, { cvar = g.cvar, name = g.name, changed = g.changed, graph = g })`],
  'results-w2-list-unmeasured-first': ['Results.lua', `        list[#list + 1] = { cvar = n.cvar or n.setting, name = n.name or n.setting, reason = n.plain or n.reason }`, `        table.insert(list, 1, { cvar = n.cvar or n.setting, name = n.name or n.setting, reason = n.plain or n.reason })`],
  'results-w2-list-dot-always': ['Results.lua', `        if item.changed then row.dot:Show() else row.dot:Hide() end`, `        row.dot:Show()`],
  'results-w2-list-unmeasured-white': ['Results.lua', `        local color = item.graph and { 1, 1, 1, 1 } or GREY`, `        local color = { 1, 1, 1, 1 }`],
  'results-w2-list-name-from-label': ['Results.lua', `        list[#list + 1] = { cvar = g.cvar, name = g.name, changed = g.changed, graph = g }`, `        list[#list + 1] = { cvar = g.cvar, name = g.cvar, changed = g.changed, graph = g }`],
  'results-w2-list-uncapped': ['Results.lua', `    local rowsShown = math.min(#list, MAX_ROWS)`, `    local rowsShown = #list`],
  'results-w2-select-default-missing': ['Results.lua', `        selected = model.selected or (first and (first.cvar or first.setting)) or nil }`, `        selected = (first and (first.cvar or first.setting)) or nil }`],
  'results-w2-select-nodata-default-missing': ['Results.lua', `        selected = model.selected or (first and (first.cvar or first.setting)) or nil }`, `        selected = model.selected }`],
  'results-w2-select-kept-across-show': ['Results.lua', `        selected = model.selected or (first and (first.cvar or first.setting)) or nil }`, `        selected = (current and current.selected) or model.selected or (first and (first.cvar or first.setting)) or nil }`],
  'results-w2-select-click-ignored': ['Results.lua', `    row:SetScript("OnClick", function(self) results.select(self.cvar) end)`, `    row:SetScript("OnClick", function() end)`],
  'results-w2-select-unknown-accepted': ['Results.lua', `    if not current or not entryFor(listOf(current.model), cvar) then return end`, `    if not current then return end`],
  'results-w2-select-highlight-missing': ['Results.lua', `        if item.cvar == open then row:LockHighlight() else row:UnlockHighlight() end`, `        row:UnlockHighlight()`],
  'results-w2-unmeasured-shows-graph': ['Results.lua', `    if chosen and chosen.graph and p.graph then`, `    if chosen and p.graph then`],
  'results-w2-panel-title-raw': ['Results.lua', `        put(p.fsPanel, chosen.name .. ": fps if only this setting changes", 0, 0, PANEL_WIDTH)`, `        put(p.fsPanel, chosen.cvar .. ": fps if only this setting changes", 0, 0, PANEL_WIDTH)`],
  'results-w2-graph-not-drawn': ['Results.lua', `        p.graph:draw(GRAPH_RECT, chosen.graph, m.axis)`, `        local _ = m.axis`],
  'results-w2-panel-sentences-missing': ['Results.lua', `        for _, line in ipairs(chosen.graph.lines) do`, `        for _, line in ipairs({}) do`],
  'results-w2-leftover-rows': ['Results.lua', `    release(p.rows)`, `    local _ = p.rows`],
  'results-w2-leftover-header': ['Results.lua', `    release(p.fsMain, true)`, `    local _ = p.fsMain`],
  'results-w2-leftover-panel': ['Results.lua', `    release(p.fsPanel, true)`, `    local _ = p.fsPanel`],
  'results-w2-paragraph-overflow-kept': ['Results.lua', `        if y + h > PANEL_Y - 4 then`, `        if false then`],

  // The Save button and a silent switch and adopt (results window, Task 5)
  'save-silent-switch-prints': ['Profiles.lua', `    speak(silent, "Profile: " .. label .. " (" .. summary .. ")")`, `    ns.say("Profile: " .. label .. " (" .. summary .. ")")`],
  'save-silent-switch-mismatch-prints': ['Profiles.lua', `        speak(silent, friendly(m.cvar) .. " stayed at "`, `        ns.say(friendly(m.cvar) .. " stayed at "`],
  'save-silent-switch-skipped-prints': ['Profiles.lua', `    if #plan.skipped > 0 then speak(silent, "skipped (not in this client): "`, `    if #plan.skipped > 0 then ns.say("skipped (not in this client): "`],
  'save-silent-switch-empty-prints': ['Profiles.lua', `        speak(silent, label .. " has no saved settings yet:`, `        ns.say(label .. " has no saved settings yet:`],
  'save-silent-switch-twin-prints': ['Profiles.lua', `        speak(silent, label .. " holds the same settings as "`, `        ns.say(label .. " holds the same settings as "`],
  'save-silent-switch-refusal-prints': ['Profiles.lua', `        speak(silent, "in combat; try again afterwards")
        return false, "combat"
    end
    if busy() then
        speak(silent, "benchmark running; try again afterwards")
        return false, "busy"
    end
    local leftOut`, `        ns.say("in combat; try again afterwards")
        return false, "combat"
    end
    if busy() then
        ns.say("benchmark running; try again afterwards")
        return false, "busy"
    end
    local leftOut`],
  'save-silent-adopt-not-passed': ['Profiles.lua', `    return profiles.switch(name, silent)`, `    return profiles.switch(name)`],
  'save-silent-adopt-original-prints': ['Profiles.lua', `        return false, "unknown"
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
    local merged`, `        return false, "unknown"
    end
    if name == "original" then
        ns.say("Original is read-only: it holds your own settings from before you first switched")
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
    local merged`],
  'save-silent-adopt-combat-prints': ['Profiles.lua', `        return false, "original"
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if InCombatLockdown() then
        speak(silent, "in combat; try again afterwards")`, `        return false, "original"
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if InCombatLockdown() then
        ns.say("in combat; try again afterwards")`],
  'save-text-everyday-for-crowd': ['Results.lua', `        local who = profile == "crowded" and "Crowded" or "Everyday"
        specs[1]`, `        local who = "Everyday"
        specs[1]`],
  'save-replace-never': ['Results.lua', `text = replace and ("Replace my " .. who`, `text = false and ("Replace my " .. who`],
  'save-visible-for-unreachable': ['Results.lua', `    if m.saveKind and not current.saved then`, `    if not current.saved then`],
  'save-hidden-for-nochange': ['Results.lua', `    if m.saveKind and not current.saved then`, `    if m.saveKind == "changes" and not current.saved then`],
  'save-stays-after-saving': ['Results.lua', `    if m.saveKind and not current.saved then`, `    if m.saveKind then`],
  'save-changes-not-handed-over': ['Results.lua', `    if current.model.saveKind == "changes" then
        for _, change in ipairs(current.result.changes) do values[change.cvar] = change.to end`, `    if false then
        for _, change in ipairs(current.result.changes) do values[change.cvar] = change.to end`],
  'save-not-silent': ['Results.lua', `ns.profiles.adopt(profile, values, true)`, `ns.profiles.adopt(profile, values)`],
  'save-prints-to-chat': ['Results.lua', `        current.saved, current.notice = line, nil`, `        current.saved, current.notice = line, nil
        ns.say(line)`],
  'save-twice-writes': ['Results.lua', `    if key ~= "apply" or not current.model.saveKind or current.saved then return end`, `    if key ~= "apply" or not current.model.saveKind then return end`],
  'save-green-missing': ['Results.lua', `        notice, color = current.saved, GOOD`, `        notice, color = current.saved, BAD`],
  'save-enabled-in-combat': ['Results.lua', `    if p.apply then p.apply:SetEnabled(why == nil) end`, `    if p.apply then p.apply:SetEnabled(true) end`],
  'save-refusal-silent': ['Results.lua', `        current.notice = REFUSED[info] or ("Could not save: " .. tostring(info))`, `        current.notice = nil`],
  'save-mismatch-sentence-missing': ['Results.lua', `        if kept > 0 then line = line .. " The game kept "`, `        if false then line = line .. " The game kept "`],
  'save-mismatch-plural-wrong': ['Results.lua', `(kept == 1 and "" or "s")`, `""`],
  'save-close-text-old': ['Results.lua', `    specs[#specs + 1] = { key = "later", text = "Close" }`, `    specs[#specs + 1] = { key = "later", text = m.canApply and "Not now" or "Close" }`],

  // The fix pass after the fresh review of the whole build (results window, Task 6)
  'fix-change-lines-no-fit-rule': ['Results.lua', `        if right + h > PANEL_Y - 4 then
            fs:SetText("")
            fs:Hide()
            break`, `        if false then
            fs:SetText("")
            fs:Hide()
            break`],
  'fix-change-pointer-count-wrong': ['Results.lua', `(#m.lines - (#placed - 1))`, `(#m.lines - #placed)`],
  'fix-change-pointer-missing': ['Results.lua', `        last.fs:SetText(pointer)`, `        local _ = pointer`],
  'fix-footer-not-above-notice': ['Results.lua', `    p.footer:SetPoint("BOTTOMLEFT", p.notice, "TOPLEFT", 0, 4)`, `    p.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CHART_X, 62)`],
  'fix-notice-over-buttons': ['Results.lua', `    p.notice:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CHART_X, 40)`, `    p.notice:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CHART_X, 30)`],
  'fix-button-widths-old': ['Results.lua', `local BUTTON_WIDTHS = { apply = 250, again = 150, later = 150 }`, `local BUTTON_WIDTHS = { apply = 210, again = 210, later = 210 }`],
  'fix-button-gap-wrong': ['Results.lua', `local BUTTON_GAP = 12`, `local BUTTON_GAP = 0`],
  'fix-buttons-not-centred': ['Results.lua', `    local edge = -total / 2`, `    local edge = 0`],
  'fix-reason-raw': ['Results.lua', `name = n.name or n.setting, reason = n.plain or n.reason }`, `name = n.name or n.setting, reason = n.reason }`],
  'fix-plain-reason-not-added': ['Recommend.lua', `            plain = recommend.plainReason(n.reason) }`, `            plain = n.reason }`],
  'fix-plain-reason-stall-missing': ['Recommend.lua', `    if reason:find("^inconclusive %(stall%)") then return "the game froze for a moment while testing it" end`, `    local _ = reason`],
  'fix-plain-reason-few-missing': ['Recommend.lua', `    if reason:find("^inconclusive %(few%)") then return "the game ran too slowly to measure it" end`, `    local _ = reason`],
  'fix-plain-reason-baseline-missing': ['Recommend.lua', `    if reason:find("^inconclusive %(baseline") then return "the frame rate kept changing while testing it" end`, `    local _ = reason`],
  'fix-plain-reason-rejected-missing': ['Recommend.lua', `    if reason:find("^rejected") then return "the game wouldn't take that level" end`, `    local _ = reason`],
  'fix-plain-reason-uncovered-missing': ['Recommend.lua', `    if reason == UNCOVERED then return "the level you use now wasn't part of your quiet-spot test" end`, `    local _ = reason`],
  'fix-plain-reason-other-inconclusive-missing': ['Recommend.lua', `    if reason:find("^inconclusive") then return "the test couldn't get a steady reading for it" end`, `    local _ = reason`],
  'fix-plain-reason-default-raw': ['Recommend.lua', `    return "the test couldn't measure it"
end`, `    return reason
end`],

  // The cost of the levels and the words of Maximum (maximum and costs, Task 1)
  'lc-uncounted-listed': ['Recommend.lua', `            if level.counted then list[#list + 1] = { value = level.value, fps = fpsFor(result.nowMs, level.deltaMs) } end`, `            if level.counted or level.deltaMs ~= nil then list[#list + 1] = { value = level.value, fps = fpsFor(result.nowMs, level.deltaMs) } end`],
  'lc-invalid-not-nil': ['Recommend.lua', `    if result.status == "invalid" then return nil end
    local info = { nowFps = result.nowFps, byCvar = {} }`, `    if false then return nil end
    local info = { nowFps = result.nowFps, byCvar = {} }`],
  'ef-sum-ignores-delta': ['Recommend.lua', `        if found then sum = sum + found.deltaMs else missing[#missing + 1] = cvar end`, `        if found then sum = sum + 0 else missing[#missing + 1] = cvar end`],
  'ef-missing-dropped': ['Recommend.lua', `        if found then sum = sum + found.deltaMs else missing[#missing + 1] = cvar end`, `        if found then sum = sum + found.deltaMs else local _ = cvar end`],
  'ef-missing-unsorted': ['Recommend.lua', `    table.sort(missing)
    local ms = math.max(result.nowMs + sum, result.nowMs / recommend.MAX_SPEEDUP)`, `    local ms = math.max(result.nowMs + sum, result.nowMs / recommend.MAX_SPEEDUP)`],
  'ef-no-clamp': ['Recommend.lua', `    local ms = math.max(result.nowMs + sum, result.nowMs / recommend.MAX_SPEEDUP)
    return { fps = 1000 / ms, ms = ms, missing = missing }`, `    local ms = result.nowMs + sum
    return { fps = 1000 / ms, ms = ms, missing = missing }`],
  'ef-values-by-text': ['Recommend.lua', `            if level.counted and sameValue(level.value, value) then`, `            if level.counted and level.value == value then`],
  'ef-nodata-estimates': ['Recommend.lua', `    if result.status == "invalid" or result.status == "nodata" then return nil end`, `    if result.status == "invalid" then return nil end`],
  'ef-uncounted-level-found': ['Recommend.lua', `            if level.counted and sameValue(level.value, value) then`, `            if sameValue(level.value, value) and level.deltaMs ~= nil then`],
  'matters-threshold-low': ['Names.lua', `    if weight >= 5 then return "some" end`, `    if weight >= 6 then return "some" end`],
  'matters-threshold-high': ['Names.lua', `    if weight >= 9 then return "a lot" end`, `    if weight >= 10 then return "a lot" end`],
  'matters-nil-as-text': ['Names.lua', `    if type(weight) ~= "number" or weight < 1 then return nil end`, `    if weight == nil then return nil end`],
  'matters-below-one-given-words': ['Names.lua', `    if type(weight) ~= "number" or weight < 1 then return nil end`, `    if type(weight) ~= "number" then return nil end`],
  'menu-max-word-raw': ['Names.lua', `    maximum = "Maximum: everything at its highest",`, `    maximum = "maximum",`],

  // Maximum and costs, Task 2: the Maximum profile
  'mx-maxvalues-first-tier': ['Profiles.lua', `values[entry.cvar] = entry.tiers[#entry.tiers]`, `values[entry.cvar] = entry.tiers[1]`],
  'mx-maxvalues-includes-unlearned': ['Profiles.lua', `                if values[cvar] == nil then leftOut[#leftOut + 1] = cvar end`, `                if values[cvar] == nil then values[cvar] = GetCVar(cvar) end`],
  'mx-leftout-wrong': ['Profiles.lua', `            if GetCVar(cvar) ~= nil then`, `            if true then`],
  'mx-leftout-lighting-twice': ['Profiles.lua', `                if values[cvar] == nil then leftOut[#leftOut + 1] = cvar end
                break`, `                if values[cvar] == nil then leftOut[#leftOut + 1] = cvar end`],
  'mx-plan-ignores-original': ['Profiles.lua', `        plan.empty = next(own) == nil`, `        plan.empty = next(own) == nil
        if name == "maximum" then original = {} end`],
  'mx-plan-want-includes-original': ['Profiles.lua', `        if name == "crowded" and db.raidToo then`, `        if name == "maximum" then for k, v in pairs(plan.writes) do plan.want[k] = v end end
        if name == "crowded" and db.raidToo then`],
  'mx-profile-stored': ['Profiles.lua', `    db.profiles = db.profiles or {}
    for _, key in ipairs({ "everyday", "crowded" }) do`, `    db.profiles = db.profiles or {}
    for _, key in ipairs({ "everyday", "crowded", "maximum" }) do`],
  'mx-switch-texture-line-missing': ['Profiles.lua', `        speak(silent, "Maximum includes the sharpest textures, which need plenty of graphics memory.")`, `        local _ = silent`],
  'mx-switch-leftout-plural': ['Profiles.lua', `    if n == 1 then
        return "1 setting stays`, `    if n == 0 then
        return "1 setting stays`],
  'mx-switch-leftout-always': ['Profiles.lua', `        if #leftOut > 0 then speak(silent, leftOutLine(#leftOut)) end`, `        speak(silent, leftOutLine(#leftOut))`],
  'mx-switch-silent-prints': ['Profiles.lua', `        speak(silent, "Maximum includes the sharpest textures`, `        ns.say("Maximum includes the sharpest textures`],
  'mx-switch-silent-leftout-prints': ['Profiles.lua', `if #leftOut > 0 then speak(silent, leftOutLine(#leftOut)) end`, `if #leftOut > 0 then ns.say(leftOutLine(#leftOut)) end`],
  'mx-nothing-switches': ['Profiles.lua', `        if next(values) == nil then
            speak(silent, "Maximum has nothing`, `        if false then
            speak(silent, "Maximum has nothing`],
  'mx-nothing-silent': ['Profiles.lua', `            speak(silent, "Maximum has nothing to set yet:`, `            ns.say("Maximum has nothing to set yet:`],
  'mx-nothing-sets-active': ['Profiles.lua', `            return false, "nothing"`, `            db.active = "maximum"
            return false, "nothing"`],
  'mx-nothing-before-refusals': ['Profiles.lua', `    if InCombatLockdown() then
        speak(silent, "in combat; try again afterwards")
        return false, "combat"
    end
    if busy() then
        speak(silent, "benchmark running; try again afterwards")
        return false, "busy"
    end
    local leftOut`, `    if name == "maximum" and next((profiles.maxValues())) == nil then return false, "nothing" end
    if InCombatLockdown() then
        speak(silent, "in combat; try again afterwards")
        return false, "combat"
    end
    if busy() then
        speak(silent, "benchmark running; try again afterwards")
        return false, "busy"
    end
    local leftOut`],
  'mx-back-keeps-maximum': ['Profiles.lua', `    if db.active == "original" and name ~= "original" then`, `    if name ~= "original" then`],
  'mx-setvalue-edits-maximum': ['Profiles.lua', `    if db.active == "maximum" then return false, maximumRefusal(silent) end
    if db.original.values[cvar] == nil then`, `    if db.original.values[cvar] == nil then`],
  'mx-unsetvalue-edits-maximum': ['Profiles.lua', `    if db.active == "maximum" then return false, maximumRefusal(silent) end
    local profile = db.profiles[db.active]`, `    local profile = db.profiles[db.active]`],
  'mx-save-maximum-stores': ['Profiles.lua', `    if name == "maximum" then return nil, maximumRefusal(silent) end`, `    local _ = name`],
  'mx-adopt-maximum-stores': ['Profiles.lua', `    if name == "maximum" then return false, maximumRefusal(silent) end
    if InCombatLockdown() then`, `    if InCombatLockdown() then`],
  'mx-profilevalue-maximum-stores': ['Profiles.lua', `    if name == "maximum" then return false, maximumRefusal(silent) end
    if db.active == name then return profiles.setValue(cvar, value, silent) end`, `    if db.active == name then return profiles.setValue(cvar, value, silent) end`],
  'mx-unsetprofilevalue-maximum-stores': ['Profiles.lua', `    if name == "maximum" then return false, maximumRefusal(silent) end
    if db.active == name then return profiles.unsetValue(cvar, silent) end`, `    if db.active == name then return profiles.unsetValue(cvar, silent) end`],
  'mx-refusal-says-nothing': ['Profiles.lua', `    speak(silent, "Maximum cannot be changed:`, `    ns.say("Maximum cannot be changed:`],
  'mx-refusal-reason-wrong': ['Profiles.lua', `    return "maximum"
end`, `    return "original"
end`],
  'mx-usage-old': ['Profiles.lua', `crowded | maximum | save <name>`, `crowded | save <name>`],
  'mx-unknown-text-old': ['Profiles.lua', `(original, everyday, crowded or maximum)")`, `(original, everyday or crowded)")`],
  'mx-order-no-maximum': ['Profiles.lua', `profiles.ORDER = { "original", "everyday", "crowded", "maximum" }`, `profiles.ORDER = { "original", "everyday", "crowded" }`],
  'mx-label-missing': ['Profiles.lua', `crowded = "Crowded", maximum = "Maximum" }`, `crowded = "Crowded" }`],
  'mx-raid-applies-to-maximum': ['Profiles.lua', `        if name == "crowded" and db.raidToo then`, `        if (name == "crowded" or name == "maximum") and db.raidToo then`],
  'mx-want-empty-for-maximum': ['Profiles.lua', `    db.want = plan.want
    for _, m in ipairs(mismatched) do`, `    db.want = name == "maximum" and {} or plan.want
    for _, m in ipairs(mismatched) do`],
  'mx-unknown-unsaid-switch': ['Profiles.lua', `        unknownProfile(silent, name)
        return false, "unknown"
    end
    if InCombatLockdown() then`, `        return false, "unknown"
    end
    if InCombatLockdown() then`],
  'mx-unknown-unsaid-adopt': ['Profiles.lua', `        unknownProfile(silent, name)
        return false, "unknown"
    end
    if name == "original" then
        speak(silent, "Original is read-only: it holds your own settings from before you first switched")
        return false, "original"
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if InCombatLockdown() then`, `        return false, "unknown"
    end
    if name == "original" then
        speak(silent, "Original is read-only: it holds your own settings from before you first switched")
        return false, "original"
    end
    if name == "maximum" then return false, maximumRefusal(silent) end
    if InCombatLockdown() then`],
  'mx-unknown-unsaid-save': ['Profiles.lua', `        unknownProfile(silent, name)
        return nil, "unknown"`, `        return nil, "unknown"`],
  'mx-unknown-unsaid-setvalue': ['Profiles.lua', `function profiles.setProfileValue(name, cvar, value, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if not profiles.LABEL[name] then
        unknownProfile(silent, name)`, `function profiles.setProfileValue(name, cvar, value, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if not profiles.LABEL[name] then`],
  'mx-unknown-unsaid-unsetvalue': ['Profiles.lua', `function profiles.unsetProfileValue(name, cvar, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if not profiles.LABEL[name] then
        unknownProfile(silent, name)`, `function profiles.unsetProfileValue(name, cvar, silent)
    local db = profiles.state()
    if not db then return false, "unavailable" end
    if not profiles.LABEL[name] then`],
  'mx-twin-hint-to-maximum': ['Profiles.lua', `        and previous ~= "maximum" and name ~= "maximum" and sameWrites(profiles.plan(previous).writes, plan.writes)`, `        and previous ~= "maximum" and sameWrites(profiles.plan(previous).writes, plan.writes)`],
  'mx-twin-hint-from-maximum': ['Profiles.lua', `        and previous ~= "maximum" and name ~= "maximum" and sameWrites(profiles.plan(previous).writes, plan.writes)`, `        and name ~= "maximum" and sameWrites(profiles.plan(previous).writes, plan.writes)`],
  'mx-no-bench-guard': ['Profiles.lua', `    if not ns.bench then return values, leftOut end`, `    local _ = ns`],

  // Maximum and costs, Task 3: the Maximum tick and its estimate
  'menu-max-order-wrong': ['UI.lua', `    add(profileItem("crowded"))
    add(profileItem("maximum"))`, `    add(profileItem("maximum"))
    add(profileItem("crowded"))`],
  'menu-max-text-estimate-missing': ['UI.lua', `if key == "maximum" and type(ctx.maxFps) == "number" then`, `if false then`],
  'menu-max-estimate-on-all-ticks': ['UI.lua', `if key == "maximum" and type(ctx.maxFps) == "number" then`, `if type(ctx.maxFps) == "number" then`],
  'menu-max-estimate-always': ['UI.lua', `if not ok or not estimate or #estimate.missing > 0 then return nil end`, `if not ok or not estimate then return nil end`],
  'menu-max-estimate-ignores-levels': ['UI.lua', `pcall(ns.recommend.estimateFps, ns.guide.findQuiet(), values)`, `pcall(ns.recommend.estimateFps, ns.guide.findQuiet(), {})`],
  'menu-max-estimate-without-levels': ['UI.lua', `    if next(values) == nil then return nil end`, `    local _ = values`],
  'menu-max-estimate-truncates': ['UI.lua', `return math.floor(estimate.fps + 0.5)`, `return math.floor(estimate.fps)`],
  'menu-max-estimate-unguarded': ['UI.lua', `local ok, estimate = pcall(ns.recommend.estimateFps, ns.guide.findQuiet(), values)`, `local ok, estimate = true, ns.recommend.estimateFps(ns.guide.findQuiet(), values)`],
  'menu-max-module-guard-missing': ['UI.lua', `    if not (ns.profiles and ns.guide and ns.recommend) then return nil end`, `    local _ = ns`],
  'menu-max-enabled-in-combat': ['UI.lua', `            isChecked = function() return ns.profiles ~= nil and ns.profiles.active() == key end,
            disabled = locked or (ctx.inCombat and true or false), run = command("profile " .. key) }`, `            isChecked = function() return ns.profiles ~= nil and ns.profiles.active() == key end,
            disabled = locked or (key ~= "maximum" and ctx.inCombat and true or false), run = command("profile " .. key) }`],
  'menu-max-enabled-while-running': ['UI.lua', `            isChecked = function() return ns.profiles ~= nil and ns.profiles.active() == key end,
            disabled = locked or (ctx.inCombat and true or false), run = command("profile " .. key) }`, `            isChecked = function() return ns.profiles ~= nil and ns.profiles.active() == key end,
            disabled = (key ~= "maximum" and locked) or (ctx.inCombat and true or false), run = command("profile " .. key) }`],
  'menu-max-wrong-command': ['UI.lua', `run = command("profile " .. key) }`, `run = command("profile " .. (key == "maximum" and "crowded" or key)) }`],
  'menu-max-not-ticked': ['UI.lua', `checked = ((ctx.profile or "original") == key),`, `checked = (key ~= "maximum" and (ctx.profile or "original") == key),`],
  'menu-max-ischecked-wrong': ['UI.lua', `isChecked = function() return ns.profiles ~= nil and ns.profiles.active() == key end,`, `isChecked = function() return ns.profiles ~= nil and ns.profiles.active() == (key == "maximum" and "crowded" or key) end,`],
  'menu-max-context-missing': ['UI.lua', `    ctx.maxFps = maxFps()`, `    local _ = maxFps`],

  // Maximum and costs, Task 4: My settings (costs, what a setting is worth, the total, the Maximum button)
  'cost-sign-flipped': ['Settings.lua', `    return (diff > 0 and "+" or "-") .. whole .. " fps"`, `    return (diff > 0 and "-" or "+") .. whole .. " fps"`],
  'cost-held-ignored': ['Settings.lua', `local heldFps = list and chosen ~= nil and fpsOf(list, chosen) or nil`, `local heldFps = list and list[1] and list[1].fps or nil`],
  'cost-same-threshold': ['Settings.lua', `    if whole == 0 then return "same" end`, `    if whole <= 1 then return "same" end`],
  'cost-rounds-down': ['Settings.lua', `local whole = math.floor(math.abs(diff) + 0.5)`, `local whole = math.floor(math.abs(diff))`],
  'cost-unmeasured-blank': ['Settings.lua', `level.cost = fps and costText(fps, heldFps) or "?"`, `level.cost = fps and costText(fps, heldFps) or nil`],
  'cost-shown-without-held': ['Settings.lua', `local heldFps = list and chosen ~= nil and fpsOf(list, chosen) or nil`, `local heldFps = list and chosen ~= nil and fpsOf(list, chosen) or 0`],
  'cost-shown-without-test': ['Settings.lua', `if costs and not (costs.fps and next(costs.fps.byCvar or {}) ~= nil) then costs = nil end`, `if false then costs = nil end`],
  'cost-now-missing': ['Settings.lua', `                if sameValue(chosen, value) then
                    level.cost = "now"`, `                if false then
                    level.cost = "now"`],
  'settings-max-note-quiet-for-crowd': ['Settings.lua', `(costs.kind == "crowd" and "crowd" or "quiet-spot")`, `("quiet-spot")`],
  'settings-max-crowd-ignored': ['Settings.lua', `    if tab == "crowded" and ns.ui then`, `    if false then`],
  'settings-max-measured-line-missing': ['Settings.lua', `            .. (costs.measuredLine and (" " .. costs.measuredLine) or "")`, `            .. ""`],
  'settings-max-quiet-time-wrong': ['Settings.lua', `ns.bench.now() - quiet.time`, `quiet.time - ns.bench.now()`],
  'settings-max-time-unguarded': ['Settings.lua', `if type(quiet.time) == "number" then line`, `if true then line`],
  'settings-max-saved-unguarded': ['Settings.lua', `local ok, saved = pcall(ns.ui.savedResult, "crowded")`, `local ok, saved = true, ns.ui.savedResult("crowded")`],
  'settings-max-module-guard-missing': ['Settings.lua', `    if not (ns.guide and ns.recommend) then return nil end`, `    local _ = ns`],
  'settings-max-ranking-unguarded': ['Settings.lua', `local ranking = ns.recommend and ns.recommend.RANKING or {}`, `local ranking = ns.recommend.RANKING`],
  'settings-max-matters-wrong': ['Settings.lua', `names.matters(ranking[cvar].weight)`, `names.matters(11 - ranking[cvar].weight)`],
  'settings-max-matters-unknown-shown': ['Settings.lua', `local words = ranking[cvar] and names.matters(ranking[cvar].weight)`, `local words = names.matters(ranking[cvar] and ranking[cvar].weight or 5)`],
  'settings-max-matters-note-always': ['Settings.lua', `    view.refusal = st.notice`, `    view.refusal = st.notice
    view.mattersNote = MATTERS_NOTE`],
  'settings-max-total-with-skipped': ['Settings.lua', `if #estimate.missing > 0 then maximum.skipped = #estimate.missing else maximum.fps = estimate.fps end`, `maximum.skipped = #estimate.missing; maximum.fps = estimate.fps`],
  'settings-max-total-plural': ['Settings.lua', `plural(max.skipped, "setting")`, `(max.skipped .. " settings")`],
  'settings-max-total-nonsense-without-test': ['Settings.lua', `    if costs and max then`, `    if max then`],
  'settings-max-total-skipped-zero': ['Settings.lua', `        elseif (max.skipped or 0) > 0 then`, `        elseif true then`],
  'settings-max-total-nothing-to-set': ['Settings.lua', `    if next(values) ~= nil then`, `    if true then`],
  'settings-max-total-ignores-values': ['Settings.lua', `ns.recommend.estimateFps(source.entry, values)`, `ns.recommend.estimateFps(source.entry, {})`],
  'settings-max-total-truncates': ['Settings.lua', `string.format("Everything at the highest: about %.0f fps.", max.fps)`, `"Everything at the highest: about " .. math.floor(max.fps) .. " fps."`],
  'settings-max-button-in-use': ['Settings.lua', `    if ctx.active ~= "maximum" then`, `    if true then`],
  'settings-max-button-in-combat': ['Settings.lua', `{ key = "maximum", text = MAXIMUM_TEXT, enabled = locked == nil }`, `{ key = "maximum", text = MAXIMUM_TEXT, enabled = true }`],
  'settings-max-click-not-silent': ['Settings.lua', `ns.profiles.switch("maximum", true)`, `ns.profiles.switch("maximum")`],
  'settings-max-click-locked-writes': ['Settings.lua', `    if ctx.locked then
        if key == "maximum" then draw() end`, `    if ctx.locked and key ~= "maximum" then
        if key == "maximum" then draw() end`],
  'settings-max-nothing-notice-missing': ['Settings.lua', `        if not ok and info == "nothing" then
            state.notice = NOTHING_TEXT`, `        if false then
            state.notice = NOTHING_TEXT`],
  'settings-max-refusal-not-shown': ['Settings.lua', `    if view.refusal then notices[#notices + 1] = view.refusal end`, `    if false then notices[#notices + 1] = view.refusal end`],
  'settings-max-notice-not-consumed': ['Settings.lua', `    state.notice = nil                       -- a refusal is shown once: until the next click or redraw`, `    local _ = state`],
  'settings-max-level-click-wrong-call': ['Settings.lua', `ns.profiles.setProfileValue(profile, pickedCvar, value, true)`, `ns.profiles.setValue(pickedCvar, value, true)`],
  'settings-max-note-in-use-missing': ['Settings.lua', `    elseif ctx.active == "maximum" then`, `    elseif false then`],
  'settings-max-leftout-missing': ['Settings.lua', `if max and (max.leftOut or 0) > 0 then view.notice`, `if false then view.notice`],
  'settings-max-leftout-plural': ['Settings.lua', `    if n == 1 then return "1 setting stays as it is: the addon has not learned its levels yet." end`, `    if n == 0 then return "1 setting stays as it is: the addon has not learned its levels yet." end`],
  'settings-max-second-line-missing': ['Settings.lua', `            if level.cost then
                local cost = take(p.costs)`, `            if false then
                local cost = take(p.costs)`],
  'settings-max-cost-width-wrong': ['Settings.lua', `        fs:SetWidth(BUTTON_WIDTH)
        fs:SetJustifyH("CENTER")`, `        fs:SetWidth(BUTTON_WIDTH * 2)
        fs:SetJustifyH("CENTER")`],
  'settings-max-cost-offset-wrong': ['Settings.lua', `cost:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -(top + 25))`, `cost:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -(top + 5))`],
  'settings-max-row-height-same': ['Settings.lua', `if level.cost then pitch = 28 + COST_HEIGHT end`, `if level.cost then pitch = 28 end`],
  'settings-max-total-over-buttons': ['Settings.lua', `    local bottom = 44`, `    local bottom = 20`],
  'settings-max-matters-over-total': ['Settings.lua', `        bottom = bottom + heightOf(fs, str) + 4`, `        bottom = bottom + 4`],
  'settings-max-scroll-over-block': ['Settings.lua', `math.max(56, bottom + 2)`, `56`],
  'settings-max-footer-overlap': ['Settings.lua', `        x = x + w + FOOTER_GAP`, `        x = x + w`],
  'settings-max-matters-line-missing': ['Settings.lua', `        if row.matters then
            local worth = take(p.matters)`, `        if false then
            local worth = take(p.matters)`],
  'settings-max-cost-note-missing': ['Settings.lua', `    place(p.costNote, view.costNote, 6)`, `    local _ = view.costNote`],
  'settings-max-costs-not-released': ['Settings.lua', `    release(p.costs, true)`, `    local _ = p.costs`],
  'settings-max-button-not-hidden': ['Settings.lua', `    p.maximum:Hide()`, `    local _ = p.maximum`],

  // The step count of a guided test grows when a reading is repeated: the window says why
  'bench-repeats-not-counted': ['Bench.lua', `progressState.total = progressState.total + #tiers + 1
                                progressState.repeats = (progressState.repeats or 0) + 1`, `progressState.total = progressState.total + #tiers + 1`],
  'crowd-repeats-not-counted': ['Bench.lua', `progressState.total = progressState.total + 2
                                progressState.repeats = (progressState.repeats or 0) + 1`, `progressState.total = progressState.total + 2`],
  'bench-progress-drops-repeats': ['Bench.lua', `cvar = progressState.cvar, value = progressState.value, repeats = progressState.repeats or 0 }`, `cvar = progressState.cvar, value = progressState.value }`],
  'bench-repeats-nil-at-start': ['Bench.lua', `repeats = progressState.repeats or 0 }`, `repeats = progressState.repeats }`],
  'guide-repeats-line-missing': ['Guide.lua', `            if (p.repeats or 0) > 0 then`, `            if false then`],
  'guide-repeats-line-always': ['Guide.lua', `            if (p.repeats or 0) > 0 then`, `            if true then`],

  // A first install forces nothing (the owner's decision before the addon is shared)
  'defaults-forced': ['ForeverSettings.lua', `    -- Nothing is forced on a first install: every setting is the player's to choose (My settings, or /fset set).`, `    groundEffectDensity = "64",`],

  // Maximum and costs, review fix pass: Maximum is re-derived at a loading screen, the window names a level the game refused
  'mx-refresh-always': ['Profiles.lua', `    if db and db.active == "maximum" then db.want = profiles.plan("maximum").want end`, `    if db then db.want = profiles.plan("maximum").want end`],
  'mx-refresh-no-want': ['Profiles.lua', `    if db and db.active == "maximum" then db.want = profiles.plan("maximum").want end`, `    if db and db.active == "maximum" then local _ = profiles.plan("maximum") end`],
  'mx-refresh-missing': ['ForeverSettings.lua', `        if ns.profiles and ns.profiles.refresh then
            local ok, err = pcall(ns.profiles.refresh)`, `        if false then
            local ok, err = pcall(ns.profiles.refresh)`],
  'mx-refresh-unguarded': ['ForeverSettings.lua', `local ok, err = pcall(ns.profiles.refresh)`, `local ok, err = true, ns.profiles.refresh()`],
  'settings-max-pending-missing': ['Settings.lua', `if max and (max.pending or 0) > 0 then view.notice`, `if false then view.notice`],
  'settings-max-pending-plural': ['Settings.lua', `    if n == 1 then return "1 setting will go to its highest level" .. tail end`, `    if n == 0 then return "1 setting will go to its highest level" .. tail end`],
  'settings-max-pending-counts-all': ['Settings.lua', `if not (db and db.want[cvar] ~= nil and sameValue(db.want[cvar], value)) then`, `if true then`],
  'settings-max-pending-ignores-value': ['Settings.lua', `db.want[cvar] ~= nil and sameValue(db.want[cvar], value)`, `db.want[cvar] ~= nil`],
  'settings-max-clamp-notice-missing': ['Settings.lua', `            if #refused > 0 then`, `            if false then`],
  'settings-max-clamp-raw-name': ['Settings.lua', `local name = ns.names.label(m.cvar, "")`, `local name = m.cvar`],
  'settings-max-clamp-unnamed-listed': ['Settings.lua', `        if name ~= "" then list[#list + 1] = name end`, `        list[#list + 1] = name`],

  // Controls for the harness itself: a comment survives, a missing pattern and a syntax error are errors, never kills.
  'control-comment': ['Bench.lua', `    return guard.drift(a, b) > K.NOISE`, `    return guard.drift(a, b) > K.NOISE -- control`],
  'control-missing': ['Bench.lua', `this line does not exist anywhere in the file`, `x`],
  'control-syntax': ['Bench.lua', `    return guard.drift(a, b) > K.NOISE`, `    return (`],
};

function main() {
  const [pkgDir, srcDir, testPath, mutation] = process.argv.slice(2);
  if (!pkgDir || !srcDir || !testPath) {
    throw new Error('usage: node run.js <fengari-pkg-dir> <src-dir> <test.lua> [mutation]');
  }
  const { lua, lauxlib, lualib, to_luastring, to_jsstring } =
    require(path.join(path.resolve(pkgDir), 'node_modules', 'fengari'));

  const read = (file) => (fs.existsSync(path.join(srcDir, file)) ? fs.readFileSync(path.join(srcDir, file), 'utf8') : '');
  const sources = { 'ForeverSettings.lua': read('ForeverSettings.lua'), 'Bench.lua': read('Bench.lua'), 'Profiles.lua': read('Profiles.lua'), 'UI.lua': read('UI.lua'), 'Guide.lua': read('Guide.lua'), 'Recommend.lua': read('Recommend.lua'), 'Results.lua': read('Results.lua'), 'Names.lua': read('Names.lua'), 'Settings.lua': read('Settings.lua'), 'Graph.lua': read('Graph.lua') };
  if (!sources['ForeverSettings.lua']) throw new Error('ForeverSettings.lua not found in ' + srcDir);

  if (mutation) {
    const m = MUTATIONS[mutation];
    if (!m) throw new Error('unknown mutation: ' + mutation);
    const [file, find, replace] = m;
    const src = sources[file];
    const first = src.indexOf(find);
    if (first < 0) throw new Error('mutation pattern not found in ' + file + ': ' + mutation);
    if (src.indexOf(find, first + 1) >= 0) throw new Error('mutation pattern found more than once in ' + file + ': ' + mutation);
    sources[file] = src.slice(0, first) + replace + src.slice(first + find.length);
  }

  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const setGlobal = (name, text) => {
    lua.lua_pushstring(L, to_luastring(text));
    lua.lua_setglobal(L, to_luastring(name));
  };
  setGlobal('ADDON_SRC', sources['ForeverSettings.lua']);
  setGlobal('BENCH_SRC', sources['Bench.lua']);
  setGlobal('PROFILES_SRC', sources['Profiles.lua']);
  setGlobal('UI_SRC', sources['UI.lua']);
  setGlobal('GUIDE_SRC', sources['Guide.lua']);
  setGlobal('RECOMMEND_SRC', sources['Recommend.lua']);
  setGlobal('RESULTS_SRC', sources['Results.lua']);
  setGlobal('NAMES_SRC', sources['Names.lua']);
  setGlobal('SETTINGS_SRC', sources['Settings.lua']);
  setGlobal('GRAPH_SRC', sources['Graph.lua']);
  setGlobal('HARNESS_SRC', fs.readFileSync(path.join(__dirname, 'harness.lua'), 'utf8'));

  const test = fs.readFileSync(testPath, 'utf8');
  let status = lauxlib.luaL_loadstring(L, to_luastring(test));
  if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 1, 0);
  const text = to_jsstring(lua.lua_tostring(L, -1));
  if (status !== lua.LUA_OK) throw new Error('LUA ERROR: ' + text);

  console.log(text);
  const lines = text.split('\n');
  const failed = lines.filter((l) => l.startsWith('FAIL')).length;
  const total = lines.filter((l) => /^(PASS|FAIL)/.test(l)).length;
  console.log('\n' + (total - failed) + '/' + total + ' passed' + (mutation ? ' (mutation: ' + mutation + ')' : ''));
  return failed ? 1 : 0;
}

try {
  process.exitCode = main();
} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exitCode = 2;
}
