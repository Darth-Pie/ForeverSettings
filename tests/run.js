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
  nocombat: ['ForeverSettings.lua', 'local function applyAll(manual, silent, asked)', 'local function applyAll(manual, silent, asked)\n    local InCombatLockdown = function() return false end'],
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
  'extra-not-recorded': ['Profiles.lua', `    if db.active == "maximum" then return false, maximumRefusal(silent) end
    if db.original.values[cvar] == nil then`, `    if db.active == "maximum" then return false, maximumRefusal(silent) end
    if false then`],
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
  'ui-tooltip-profile-off': ['UI.lua', `    GameTooltip:AddLine("Profile: " .. ((ns.profiles and ns.profiles.LABEL[key]) or key))`, `    local _ = key`],
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
  // Guide (Task 6)
  'ui-start-enabled-unticked': ['Guide.lua', `            button:SetEnabled(spec.enabled)`, `            button:SetEnabled(true)`],
  'ui-windows-constant': ['Guide.lua', `    return ns.bench.countWindows(resolved, currents)`, `    return 3`],
  'ui-button-key-fixed': ['Guide.lua', `            button.key = spec.key`, `            button.key = button.key or spec.key`],
  // Found in the owner's first real run (Window 47 of 45; report and Finished windows overlapping)
  'rerun-total-not-extended': ['Bench.lua', `                                progressState.total = progressState.total + #tiers + 1`, `                                local _ = tiers`],
  'rerun-total-off-by-one': ['Bench.lua', `progressState.total = progressState.total + #tiers + 1`, `progressState.total = progressState.total + #tiers`],
  'report-auto-when-guided': ['UI.lua', `    if ns.guide and ns.guide.handlesReport and ns.guide.handlesReport() then return end`, `    local _ = ns.guide`],
  'guided-flag-any-running': ['Guide.lua', `    return state ~= nil and state.view == "running" and state.started == true
        and (state.kind == "run" or state.kind == "setup" or state.kind == "crowd")`, `    return state ~= nil and state.view == "running"`],
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
  'target-buttons-always-shown': ['Guide.lua', `        for _, button in ipairs(p.targets) do button:Hide() end`, `        local _ = p.targets`],
  'estimate-uses-run-count': ['Guide.lua', `        ctx.windows = ctx.windowsByMode[state.mode == "thorough" and "thorough" or "quick"]`, `        ctx.windows = windowCount()`],
  'target-lost-on-again': ['Guide.lua', `if (kind == "setup" or kind == "crowd") and state.view == "intro" then
            if target then state.target = target end`, `if false then
            if target then state.target = target end`],
  'stopped-drops-target': ['Guide.lua', `state = { view = "stopped", kind = kind, reason = reason, target = target, mode = mode }`, `state = { view = "stopped", kind = kind, reason = reason, mode = mode }`],
  // Results, recommender Task 7
  'headline-ignores-fraction': ['Results.lua', `bar(p.texMain, color, CHART_X, left, entryRow.fraction * CHART_WIDTH, 14)`, `bar(p.texMain, color, CHART_X, left, CHART_WIDTH, 14)`],
  'apply-skips-adopt': ['Results.lua', `local ok, info = ns.profiles.adopt(profile, values, true)`, `local ok, info = true, {}`],
  'replace-wording-always': ['Results.lua', `text = replace and ("Replace my " .. who .. " settings with these") or ("Save these as my " .. who .. " settings") }`, `text = "Replace my " .. who .. " settings with these" }`],
  'later-writes': ['Results.lua', `    if key == "later" then
        results.hide()`, `    if key == "later" then
        ns.profiles.adopt("everyday", {})
        results.hide()`],
  'combat-not-disabled': ['Results.lua', `if p.apply then p.apply:SetEnabled(why == nil) end`, `if p.apply then p.apply:SetEnabled(true) end`],
  'apply-failure-closes': ['Results.lua', `        current.notice = REFUSED[info] or ("Could not save: " .. tostring(info))`, `        current.notice = REFUSED[info] or ("Could not save: " .. tostring(info))
        results.hide()`],
  'fallback-silent': ['Results.lua', `    for _, line in ipairs(m.lines) do ns.say(line) end`, `    local _ = m`],
  'error-said-every-time': ['Results.lua', `    if err ~= lastError then`, `    if true then`],
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
  'rules-no-dynamic-scaling': ['Guide.lua', `    "- Turn off dynamic scaling in the graphics menu, if there is one. It changes the picture size during the test and spoils the numbers.",
`, ``],
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
    -- As setValue does:`, `    -- As setValue does:`],
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
  'silent-not-passed-to-applyall': ['Profiles.lua', `    ns.applyAll(true, silent, { [cvar:lower()] = true })`, `    ns.applyAll(true, nil, { [cvar:lower()] = true })`],
  'applyall-silent-ignored': ['ForeverSettings.lua', `    local say = silent and function() end or say`, `    local say = say`],
  'friendly-raw': ['Profiles.lua', `    if ns.names then return ns.names.label(cvar, label) end`, `    if false then return ns.names.label(cvar, label) end`],

  // The My settings window (words and menu, Task 3)
  'settings-order-reversed': ['Settings.lua', `        if ra ~= rb then return ra < rb end`, `        if ra ~= rb then return ra > rb end`],
  'settings-lowest-mark-missing': ['Settings.lua', `            if i == 1 then position = "lowest" elseif i == #entry.tiers then position = "highest" end`, `            if i == #entry.tiers then position = "highest" end`],
  'settings-kept-ignores-saved': ['Settings.lua', `kept = saved[cvar] ~= nil,`, `kept = false,`],
  'settings-click-active-stores-only': ['Settings.lua', `        ns.profiles.setProfileValue(profile, pickedCvar, value, true)`, `        ns.profiles.state().profiles[profile].values[pickedCvar] = value`],
  'settings-tick-wrong-value': ['Settings.lua', `ns.profiles.setProfileValue(profile, cvar, now, true)`, `ns.profiles.setProfileValue(profile, cvar, "0", true)`],
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
  'results-level-raw': ['Graph.lua', `                    say(p.text, item.x - 20, plot.y + plot.height + 6, 40)`, `                    say(p.value, item.x - 20, plot.y + plot.height + 6, 40)`],
  'results-notmeasured-raw': ['Results.lua', `put(p.fsPanel, chosen.name .. ": not measured (" ..`, `put(p.fsPanel, chosen.cvar .. ": not measured (" ..`],
  'results-measured-missing': ['Results.lua', `    paragraph(current.extras and current.extras.measuredLine)`, `    local _ = current.extras`],
  'results-again-missing': ['Results.lua', `    if current.extras and current.extras.again then specs[#specs + 1] = { key = "again", text = "Run it again" } end`, `    if false then specs[#specs + 1] = { key = "again", text = "Run it again" } end`],
  'results-again-always': ['Results.lua', `    if current.extras and current.extras.again then specs[#specs + 1] = { key = "again", text = "Run it again" } end`, `    if true then specs[#specs + 1] = { key = "again", text = "Run it again" } end`],
  'results-again-wrong-kind': ['Results.lua', `ns.guide.open(kind)`, `ns.guide.open("setup")`],
  'results-again-keeps-window': ['Results.lua', `        local kind = current.extras and current.extras.again
        results.hide()`, `        local kind = current.extras and current.extras.again`],

  // The plain menu and the saved results behind its green checks (words and menu, Task 7)
  'menu-order-wrong': ['UI.lua', `    add(profileItem("everyday"))
    add(profileItem("crowded"))`, `    add(profileItem("crowded"))
    add(profileItem("everyday"))`],
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
  'menu-raw-name': ['UI.lua', `    add({ text = "Find my best settings", kind = "button"`, `    add({ text = "Find my best settings (graphicsShadowQuality)", kind = "button"`],
  'menu-settings-without-module-silent': ['UI.lua', `if ns.settings and ns.settings.open then ns.settings.open() else ns.say("settings module not loaded") end`, `if ns.settings and ns.settings.open then ns.settings.open() end`],
  'menu-settings-never-opens': ['UI.lua', `if ns.settings and ns.settings.open then ns.settings.open() else ns.say("settings module not loaded") end`, `if ns.settings and ns.settings.open then local _ = ns.settings.open else ns.say("settings module not loaded") end`],
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
  'graph-draw-grid-missing': ['Graph.lua', `                box(COLORS.grid, plot.x, tick.y, plot.width, 1)`, `                local _ = plot`],
  'graph-draw-axis-line-missing': ['Graph.lua', `            box(COLORS.axis, plot.x, plot.y, 1, plot.height)`, `            local _ = plot`],
  'graph-draw-margin-top-small': ['Graph.lua', `graph.MARGIN = { left = 44, right = 14, top = 22, bottom = 26 }`, `graph.MARGIN = { left = 44, right = 14, top = 10, bottom = 26 }`],
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
  'results-w2-verdict-missing': ['Results.lua', `    if m.verdict and m.verdict ~= "" then`, `    if false then`],
  'results-w2-changes-unlimited': ['Results.lua', `        if i > MAX_CHANGE_LINES then break end`, `        if false then break end`],
  'results-w2-list-unmeasured-first': ['Results.lua', `        list[#list + 1] = { cvar = n.cvar or n.setting, name = n.name or n.setting, reason = n.plain or n.reason }`, `        table.insert(list, 1, { cvar = n.cvar or n.setting, name = n.name or n.setting, reason = n.plain or n.reason })`],
  'results-w2-list-dot-always': ['Results.lua', `        if item.changed then row.dot:Show() else row.dot:Hide() end`, `        row.dot:Show()`],
  'results-w2-list-uncapped': ['Results.lua', `    local rowsShown = math.min(#list, MAX_ROWS)`, `    local rowsShown = #list`],
  'results-w2-select-click-ignored': ['Results.lua', `    row:SetScript("OnClick", function(self) results.select(self.cvar) end)`, `    row:SetScript("OnClick", function() end)`],
  'results-w2-select-unknown-accepted': ['Results.lua', `    if not current or not entryFor(listOf(current.model), cvar) then return end`, `    if not current then return end`],
  'results-w2-unmeasured-shows-graph': ['Results.lua', `    if chosen and chosen.graph and p.graph then`, `    if chosen and p.graph then`],
  'results-w2-panel-title-raw': ['Results.lua', `        put(p.fsPanel, chosen.name .. ": fps if only this setting changes", 0, 0, PANEL_WIDTH)`, `        put(p.fsPanel, chosen.cvar .. ": fps if only this setting changes", 0, 0, PANEL_WIDTH)`],
  'results-w2-panel-sentences-missing': ['Results.lua', `        for _, line in ipairs(chosen.graph.lines) do`, `        for _, line in ipairs({}) do`],
  'results-w2-leftover-rows': ['Results.lua', `    release(p.rows)`, `    local _ = p.rows`],
  'results-w2-leftover-header': ['Results.lua', `    release(p.fsMain, true)`, `    local _ = p.fsMain`],
  'results-w2-leftover-panel': ['Results.lua', `    release(p.fsPanel, true)`, `    local _ = p.fsPanel`],

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
  'fix-change-pointer-count-wrong': ['Results.lua', `(#m.lines - (#placed - 1))`, `(#m.lines - #placed)`],
  'fix-change-pointer-missing': ['Results.lua', `        last.fs:SetText(pointer)`, `        local _ = pointer`],
  'fix-footer-not-above-notice': ['Results.lua', `    p.footer:SetPoint("BOTTOMLEFT", p.notice, "TOPLEFT", 0, 4)`, `    p.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CHART_X, 62)`],
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
  'settings-max-click-not-silent': ['Settings.lua', `local ok, info = ns.profiles.switch(name, true)`, `local ok, info = ns.profiles.switch(name)`],
  'settings-max-nothing-notice-missing': ['Settings.lua', `    if not ok and info == "nothing" then
        state.notice = NOTHING_TEXT`, `    if false then
        state.notice = NOTHING_TEXT`],
  'settings-max-refusal-not-shown': ['Settings.lua', `    if view.refusal then notices[#notices + 1] = view.refusal end`, `    if false then notices[#notices + 1] = view.refusal end`],
  'settings-max-notice-not-consumed': ['Settings.lua', `    state.notice = nil                       -- a refusal is shown once: until the next click or redraw`, `    local _ = state`],
  'settings-max-leftout-missing': ['Settings.lua', `if max and (max.leftOut or 0) > 0 then view.notice`, `if false then view.notice`],
  'settings-max-leftout-plural': ['Settings.lua', `    if n == 1 then return "1 setting stays as it is: the addon has not learned its levels yet." end`, `    if n == 0 then return "1 setting stays as it is: the addon has not learned its levels yet." end`],
  'settings-max-second-line-missing': ['Settings.lua', `            if level.cost then
                local cost = take(p.costs)`, `            if false then
                local cost = take(p.costs)`],
  'settings-max-cost-width-wrong': ['Settings.lua', `local fs = skin.text(parent, "small", "dim", COST_W)`, `local fs = skin.text(parent, "small", "dim", 100)`],
  'settings-max-cost-offset-wrong': ['Settings.lua', `bx - (COST_W - LEVEL_W) / 2, -(by + LEVEL_H + 2))`, `bx - (COST_W - LEVEL_W) / 2, -(by + 5))`],
  'ui-level-width': ['Settings.lua', `local LEVEL_W, LEVEL_H, LEVEL_GAP, COST_H = 50, 22, 3, 14`, `local LEVEL_W, LEVEL_H, LEVEL_GAP, COST_H = 36, 22, 3, 14`],
  'ui-cost-no-extra-width': ['Settings.lua', `local COST_W = LEVEL_W + 8`, `local COST_W = LEVEL_W`],
  'ui-cost-uncentred': ['Settings.lua', `bx - (COST_W - LEVEL_W) / 2`, `bx`],

  // The live total in My settings ("Your Everyday settings: about N fps")
  'live-counted-zero': ['Settings.lua', `type(est.fps) == "number" and (est.counted or 0) > 0 then`, `type(est.fps) == "number" then`],
  'live-note-dropped': ['Settings.lua', `        if (est.notCounted or 0) > 0 then`, `        if false then`],
  'live-note-plural': ['Settings.lua', `plural(est.notCounted, "setting")`, `(est.notCounted .. " settings")`],
  'live-whole-number': ['Settings.lua', `"Your %s settings: about %.0f fps"`, `"Your %s settings: about %.1f fps"`],
  'live-tail-missing': ['Settings.lua', `est.fps) .. YOUR_TAIL`, `est.fps)`],
  'live-guard-removed': ['Settings.lua', `local okHeld, yours = pcall(ns.recommend.estimateFps, source.entry, held)`, `local okHeld, yours = true, ns.recommend.estimateFps(source.entry, held)`],
  'live-count-ignores-missing': ['Settings.lua', `counted = heldCount - #yours.missing`, `counted = heldCount`],
  'live-not-counted-zero': ['Settings.lua', `notCounted = #yours.missing }`, `notCounted = 0 }`],
  'live-line-not-stacked': ['Settings.lua', `    stack(p.your, view.yourLine)
`, ``],
  'live-stack-order': ['Settings.lua', `    stack(p.total, view.totalLine)
    stack(p.your, view.yourLine)`, `    stack(p.your, view.yourLine)
    stack(p.total, view.totalLine)`],
  'settings-max-matters-over-total': ['Settings.lua', `        bottom = bottom + heightOf(fs, str) + 2`, `        bottom = bottom + 2`],
  'settings-max-matters-line-missing': ['Settings.lua', `            worth:SetText(row.tag or ("matters: " .. row.mattersWords))`, `            worth:SetText(row.tag or "")`],
  'settings-max-cost-note-missing': ['Settings.lua', `    if onSettings or view.page == "home" then placeText(p.costNote, view.costNote) else hideText(p.costNote) end`, `    hideText(p.costNote)`],
  'settings-max-costs-not-released': ['Settings.lua', `    release(p.costs, true)`, `    local _ = p.costs`],

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

  // /fset probe: ask the client by name which console variables exist, changing nothing
  'probe-counts-swapped': ['ForeverSettings.lua', `"; here: " .. #found .. ", not here: " .. #missing .. "."`, `"; here: " .. #missing .. ", not here: " .. #found .. "."`],
  'probe-found-not-listed': ['ForeverSettings.lua', `if #found > 0 then sayPacked(`, `if false then sayPacked(`],
  'probe-missing-not-listed': ['ForeverSettings.lua', `if #missing > 0 then sayPacked(`, `if false then sayPacked(`],
  'probe-unsorted': ['ForeverSettings.lua', `    table.sort(asked, function(a, b) return a:lower() < b:lower() end)`, `    local _ = asked`],
  'probe-writes': ['ForeverSettings.lua', `            local okDefault, default = false, nil`, `            pcall(SetCVar, name, now)
            local okDefault, default = false, nil`],
  'probe-not-routed': ['ForeverSettings.lua', `    elseif cmd == "probe" then`, `    elseif cmd == "probe-off" then`],
  'probe-commands-line': ['ForeverSettings.lua', `dump <text>, probe [names], size`, `dump <text>, size`],
  'probe-list-typo': ['ForeverSettings.lua', `"overridefarclip", "farclip", "horizonfarclip"`, `"overridefarclip", "farclp", "horizonfarclip"`],
  'probe-list-duplicate': ['ForeverSettings.lua', `"overridefarclip", "farclip", "horizonfarclip"`, `"overridefarclip", "farclip", "FarClip", "horizonfarclip"`],
  'probe-width-unbounded': ['ForeverSettings.lua', `local PROBE_WIDTH = 200`, `local PROBE_WIDTH = 100000`],
  'probe-wrap-loses-item': ['ForeverSettings.lua', `            line = item
`, `            line = ""
`],
  'probe-args-ignored': ['ForeverSettings.lua', `    for name in rest:gmatch("%S+") do add(name) end`, `    local _ = rest`],
  'probe-args-added-to-list': ['ForeverSettings.lua', `    if #asked == 0 then
        for _, name in ipairs(PROBE_CVARS) do add(name) end`, `    if true then
        for _, name in ipairs(PROBE_CVARS) do add(name) end`],
  'probe-case-dupes': ['ForeverSettings.lua', `        local key = name:lower()
        if not seen[key] then`, `        local key = name
        if not seen[key] then`],
  'probe-get-unguarded': ['ForeverSettings.lua', `local ok, now = pcall(GetCVar, name)`, `local ok, now = true, GetCVar(name)`],
  'probe-default-unguarded': ['ForeverSettings.lua', `okDefault, default = pcall(GetCVarDefault, name) end`, `okDefault, default = true, GetCVarDefault(name) end`],
  'probe-default-no-mark': ['ForeverSettings.lua', `tostring(default) or "?")`, `tostring(default) or "")`],

  // The flat skin (spec 2026-11-02-flat-hub-window-design.md)
  'skin-palette-accent': ['Skin.lua', `accent = "9a9cff"`, `accent = "9a9cfe"`],
  'skin-palette-fill-alpha': ['Skin.lua', `local ALPHA = { fill = 0.96 }`, `local ALPHA = { fill = 1 }`],
  'skin-unknown-colour': ['Skin.lua', `    if not c then return nil end`, `    if not c then return 0, 0, 0, 1 end`],
  'skin-border-missing': ['Skin.lua', `            strip(frame, "BORDER", { "TOPRIGHT", 0, -r }, { "BOTTOMRIGHT", 0, r }, 1, nil),`, `            -- no right edge`],
  'skin-border-thick': ['Skin.lua', `{ "TOPLEFT", r, 0 }, { "TOPRIGHT", -r, 0 }, nil, 1),`, `{ "TOPLEFT", r, 0 }, { "TOPRIGHT", -r, 0 }, nil, 2),`],
  'skin-no-fill': ['Skin.lua', `box.fill:SetColorTexture(skin.color(fillName))`, `box.fill:SetColorTexture(skin.color("border"))`],
  'skin-label-not-centred': ['Skin.lua', `label:SetPoint("CENTER", b, "CENTER", 0, 0)
    label:SetWidth(width - 8)`, `label:SetPoint("LEFT", b, "LEFT", 4, 0)
    label:SetWidth(width - 8)`],
  'skin-justify-h': ['Skin.lua', `    label:SetWidth(width - 8)
    label:SetJustifyH("CENTER")`, `    label:SetWidth(width - 8)
    label:SetJustifyH("LEFT")`],
  'skin-justify-v': ['Skin.lua', `    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    b.label = label`, `    label:SetJustifyV("TOP")
    label:SetWordWrap(false)
    b.label = label`],
  'skin-label-wraps': ['Skin.lua', `    label:SetWordWrap(false)
    b.label = label`, `    label:SetWordWrap(true)
    b.label = label`],
  'skin-label-width': ['Skin.lua', `label:SetWidth(width - 8)`, `label:SetWidth(width)`],
  'skin-state-hover': ['Skin.lua', `    elseif state.hover then
        fill = "hover"`, `    elseif state.hover then
        fill = "pressed"`],
  'skin-state-pressed': ['Skin.lua', `fill, edge = "pressed", "accent"`, `fill, edge = "pressed", "control"`],
  'skin-state-selected': ['Skin.lua', `fill, edge, text = "selected", "accent", "bright"`, `fill, edge, text = "selected", "accent", "text"`],
  'skin-disabled-hover': ['Skin.lua', `    if not b:IsEnabled() then`, `    if false then`],
  'skin-set-enabled-unpainted': ['Skin.lua', `        setEnabled(self, on)
        paint(self)`, `        setEnabled(self, on)`],
  'skin-selected-unpainted': ['Skin.lua', `        self.skinState.selected = on and true or false
        paint(self)`, `        self.skinState.selected = on and true or false`],
  'skin-close-noop': ['Skin.lua', `f.close:SetScript("OnClick", function() f:Hide() end)`, `f.close:SetScript("OnClick", function() end)`],
  'skin-escape-missing': ['Skin.lua', `    if not listed and name then tinsert(UISpecialFrames, name) end`, `    local _ = listed`],
  'skin-escape-twice': ['Skin.lua', `    if not listed and name then tinsert(UISpecialFrames, name) end`, `    if name then tinsert(UISpecialFrames, name) end`],
  'skin-window-shown': ['Skin.lua', `    f:Hide()
    return f`, `    return f`],
  'skin-check-size': ['Skin.lua', `box:SetSize(16, 16)`, `box:SetSize(18, 18)`],
  'skin-slider-range': ['Skin.lua', `slider:SetMinMaxValues(min, max)`, `slider:SetMinMaxValues(min, max - 1)`],
  'skin-slider-step': ['Skin.lua', `slider:SetValueStep(step)`, `slider:SetValueStep(1)`],
  'skin-slider-thumb': ['Skin.lua', `thumb:SetSize(10, 16)`, `thumb:SetSize(12, 16)`],
  'skin-slider-track': ['Skin.lua', `track:SetColorTexture(skin.color("control"))`, `track:SetColorTexture(skin.color("border"))`],
  'skin-text-colour': ['Skin.lua', `fs:SetTextColor(skin.color(colorName or "text"))`, `fs:SetTextColor(skin.color("text"))`],
  'skin-text-width': ['Skin.lua', `    if width then fs:SetWidth(width) end`, `    local _ = width`],
  'skin-template': ['Skin.lua', `local b = CreateFrame("Button", nil, parent)`, `local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")`],

  'skin-nav-label-centred': ['Skin.lua', `label:SetJustifyH("LEFT")`, `label:SetJustifyH("CENTER")`],
  'skin-nav-label-point': ['Skin.lua', `label:SetPoint("LEFT", row, "LEFT", 14, 0)`, `label:SetPoint("CENTER", row, "CENTER", 0, 0)`],
  'skin-nav-bar-never': ['Skin.lua', `if state.selected then row.bar:Show() else row.bar:Hide() end`, `row.bar:Hide()`],
  'skin-nav-fill-normal': ['Skin.lua', `local fillName, alpha, text = "fill", 0, "text"`, `local fillName, alpha, text = "fill", 1, "text"`],
  'skin-nav-selected-fill': ['Skin.lua', `fillName, alpha, text = "selected", 1, "accentLight"`, `fillName, alpha, text = "hover", 1, "accentLight"`],
  'skin-nav-selected-text': ['Skin.lua', `fillName, alpha, text = "selected", 1, "accentLight"`, `fillName, alpha, text = "selected", 1, "text"`],
  'skin-nav-hover': ['Skin.lua', `fillName, alpha = "hover", 1`, `fillName, alpha = "selected", 1`],
  'skin-nav-pressed': ['Skin.lua', `fillName, alpha = "pressed", 1`, `fillName, alpha = "hover", 1`],
  'skin-nav-bar-width': ['Skin.lua', `row.bar:SetWidth(2)`, `row.bar:SetWidth(4)`],
  // Rounded corners (owner request 2026-11-02)
  'skin-round-mid-top': ['Skin.lua', `{ "TOPLEFT", 0, -r }, { "BOTTOMRIGHT", 0, r })`, `{ "TOPLEFT", 0, -r + 1 }, { "BOTTOMRIGHT", 0, r })`],
  'skin-round-top-height': ['Skin.lua', `{ "TOPRIGHT", -r, 0 }, nil, r),`, `{ "TOPRIGHT", -r, 0 }, nil, r + 1),`],
  'skin-round-bottom-height': ['Skin.lua', `{ "BOTTOMRIGHT", -r, 0 }, nil, r),`, `{ "BOTTOMRIGHT", -r, 0 }, nil, 1),`],
  'skin-round-top-inset': ['Skin.lua', `{ "TOPLEFT", r, 0 }, { "TOPRIGHT", -r, 0 }, nil, r),`, `{ "TOPLEFT", 0, 0 }, { "TOPRIGHT", -r, 0 }, nil, r),`],
  'skin-round-edge-top-inset': ['Skin.lua', `{ "TOPLEFT", r, 0 }, { "TOPRIGHT", -r, 0 }, nil, 1),`, `{ "TOPLEFT", 0, 0 }, { "TOPRIGHT", -r, 0 }, nil, 1),`],
  'skin-round-edge-bottom-thick': ['Skin.lua', `{ "BOTTOMRIGHT", -r, 0 }, nil, 1),`, `{ "BOTTOMRIGHT", -r, 0 }, nil, 2),`],
  'skin-round-edge-left-thick': ['Skin.lua', `{ "BOTTOMLEFT", 0, r }, 1, nil),`, `{ "BOTTOMLEFT", 0, r }, 2, nil),`],
  'skin-round-edge-right-inset': ['Skin.lua', `{ "TOPRIGHT", 0, -r }, { "BOTTOMRIGHT", 0, r }, 1, nil),`, `{ "TOPRIGHT", 0, 0 }, { "BOTTOMRIGHT", 0, r }, 1, nil),`],
  'skin-round-corner-size': ['Skin.lua', `tex:SetSize(radius, radius)`, `tex:SetSize(radius, radius + 1)`],
  'skin-round-corner-anchor': ['Skin.lua', `tex:SetPoint(which, frame, which, 0, 0)`, `tex:SetPoint("TOPLEFT", frame, which, 0, 0)`],
  'skin-round-flip-topleft': ['Skin.lua', `TOPLEFT = { 0, 1, 0, 1 }`, `TOPLEFT = { 1, 0, 0, 1 }`],
  'skin-round-flip-topright': ['Skin.lua', `TOPRIGHT = { 1, 0, 0, 1 }`, `TOPRIGHT = { 0, 1, 0, 1 }`],
  'skin-round-flip-bottomleft': ['Skin.lua', `BOTTOMLEFT = { 0, 1, 1, 0 }`, `BOTTOMLEFT = { 0, 1, 0, 1 }`],
  'skin-round-flip-bottomright': ['Skin.lua', `BOTTOMRIGHT = { 1, 0, 1, 0 }`, `BOTTOMRIGHT = { 1, 0, 0, 1 }`],
  'skin-round-no-picture': ['Skin.lua', `    tex:SetTexture(file)`, `    local _ = file`],
  'skin-round-file-fill': ['Skin.lua', `MEDIA .. "fill" .. r .. ".tga"`, `MEDIA .. "ring" .. r .. ".tga"`],
  'skin-round-file-ring': ['Skin.lua', `MEDIA .. "ring" .. r .. ".tga"`, `MEDIA .. "fill" .. r .. ".tga"`],
  'skin-round-media-folder': ['Skin.lua', `.. "/Media/"`, `.. "/Textures/"`],
  'skin-round-fill-layer': ['Skin.lua', `cornerPicture(frame, "BACKGROUND", which`, `cornerPicture(frame, "BORDER", which`],
  'skin-round-edge-layer': ['Skin.lua', `cornerPicture(frame, "BORDER", which`, `cornerPicture(frame, "BACKGROUND", which`],
  'skin-round-untinted': ['Skin.lua', `        for _, tex in ipairs(pictures) do tex:SetVertexColor(r, g, b, a) end`, `        local _ = pictures`],
  'skin-round-strips-unpainted': ['Skin.lua', `        for _, tex in ipairs(strips) do tex:SetColorTexture(r, g, b, a) end`, `        local _ = strips`],
  'skin-round-colour-forgotten': ['Skin.lua', `        self._color = { r, g, b, a }`, `        self._color = nil`],
  'skin-round-edge-initial': ['Skin.lua', `box.edge:SetColorTexture(skin.color(edgeName))`, `box.edge:SetColorTexture(skin.color("fill"))`],
  'skin-round-edge-always': ['Skin.lua', `    if edgeName then`, `    if true then`],
  'skin-round-window-radius': ['Skin.lua', `skin.box(f, skin.RADIUS.window, "fill", "border")`, `skin.box(f, skin.RADIUS.control, "fill", "border")`],
  'skin-round-button-radius': ['Skin.lua', `skin.box(b, skin.RADIUS.control, "fill", "control")`, `skin.box(b, skin.RADIUS.window, "fill", "control")`],
  'skin-round-check-radius': ['Skin.lua', `skin.box(box, skin.RADIUS.control, "fill", "control")`, `skin.box(box, skin.RADIUS.window, "fill", "control")`],
  'skin-round-nav-radius': ['Skin.lua', `skin.box(row, skin.RADIUS.control, "fill").fill`, `skin.box(row, skin.RADIUS.window, "fill").fill`],
  'skin-round-bar-inset': ['Skin.lua', `local BAR_INSET = skin.RADIUS.control + 1`, `local BAR_INSET = 0`],
  'skin-round-bar-top': ['Skin.lua', `row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -BAR_INSET)`, `row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)`],
  'skin-round-bar-bottom': ['Skin.lua', `row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, BAR_INSET)`, `row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)`],
  'skin-round-edges-unlinked': ['Skin.lua', `b.bg, b.edges = box.fill, { box.edge }`, `b.bg, b.edges = box.fill, {}`],
  'skin-round-check-leave': ['Skin.lua', `tex:SetColorTexture(skin.color("control")) end end)`, `tex:SetColorTexture(skin.color("border")) end end)`],
  'skin-nav-select-unpainted': ['Skin.lua', `        self.skinState.selected = on and true or false
        paintRow(self)`, `        self.skinState.selected = on and true or false`],

  // The hub window: the shell and the settings pages
  'hub-window-size': ['Settings.lua', `local WIDTH, HEIGHT = 860, 560`, `local WIDTH, HEIGHT = 860, 540`],
  'hub-nav-click-missing': ['Settings.lua', `        item:SetScript("OnClick", clicked)`, `        local _ = clicked`],
  'hub-nav-gap': ['Settings.lua', `-(10 + (i - 1) * 30 + gap)`, `-(10 + (i - 1) * 30)`],
  'hub-nav-selected-unmarked': ['Settings.lua', `item:SetSelected(entry.selected)`, `item:SetSelected(false)`],
  'hub-card-tick-unchecked': ['Settings.lua', `box:SetChecked(row.kept)`, `box:SetChecked(false)`],
  'hub-card-tick-never-greyed': ['Settings.lua', `box:SetEnabled(row.enabled)`, `box:SetEnabled(true)`],
  'hub-card-name-missing': ['Settings.lua', `name:SetText(row.name)`, `name:SetText("")`],
  'hub-card-help-missing': ['Settings.lua', `help:SetText(helpText)`, `help:SetText("")`],
  'hub-level-long-label': ['Settings.lua', `button:SetLabel(level.short or level.text)`, `button:SetLabel(level.text)`],
  'hub-level-tip-short': ['Settings.lua', `button.tip = level.text`, `button.tip = level.short`],
  'hub-level-unmarked': ['Settings.lua', `button:SetSelected(level.selected)`, `button:SetSelected(false)`],
  'hub-level-never-greyed': ['Settings.lua', `button:SetEnabled(row.enabled)`, `button:SetEnabled(true)`],
  // Save as Everyday / Save as Crowded at the bottom of the page list (owner request 2026-11-02)
  'saveas-caption-text': ['Settings.lua', `local SAVE_CAPTION = "Save the game's current settings as:"`, `local SAVE_CAPTION = "Save the game's current settings as"`],
  'saveas-button-label': ['Settings.lua', `skin.button(page, "Save as " .. TAB_TEXT[key], SAVE_W, SAVE_H)`, `skin.button(page, TAB_TEXT[key], SAVE_W, SAVE_H)`],
  'saveas-frame-never-greyed': ['Settings.lua', `p.saveButtons[i]:SetEnabled(spec.enabled)`, `p.saveButtons[i]:SetEnabled(true)`],
  'saveas-key': ['Settings.lua', `button.key = "save:" .. key`, `button.key = "saveas:" .. key`],
  'saveas-width': ['Settings.lua', `local SAVE_X, SAVE_W, SAVE_H, SAVE_GAP = 12, NAV_WIDTH - 24, 28, 6`, `local SAVE_X, SAVE_W, SAVE_H, SAVE_GAP = 12, NAV_WIDTH - 12, 28, 6`],
  'saveas-height': ['Settings.lua', `local SAVE_X, SAVE_W, SAVE_H, SAVE_GAP = 12, NAV_WIDTH - 24, 28, 6`, `local SAVE_X, SAVE_W, SAVE_H, SAVE_GAP = 12, NAV_WIDTH - 24, 24, 6`],
  'saveas-gap': ['Settings.lua', `local SAVE_X, SAVE_W, SAVE_H, SAVE_GAP = 12, NAV_WIDTH - 24, 28, 6`, `local SAVE_X, SAVE_W, SAVE_H, SAVE_GAP = 12, NAV_WIDTH - 24, 28, 10`],
  'saveas-order': ['Settings.lua', `12 + (#TABS - i) * (SAVE_H + SAVE_GAP)`, `12 + (i - 1) * (SAVE_H + SAVE_GAP)`],
  'saveas-anchor': ['Settings.lua', `button:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", SAVE_X, 12 + (#TABS - i)`, `button:SetPoint("TOPLEFT", page, "BOTTOMLEFT", SAVE_X, 12 + (#TABS - i)`],
  'saveas-click-missing': ['Settings.lua', `        button.key = "save:" .. key
        button:SetScript("OnClick", clicked)`, `        button.key = "save:" .. key`],
  'saveas-saves-to-tab': ['Settings.lua', `        keepCurrent(saveKey)`, `        keepCurrent(state.tab)`],
  'saveas-loud': ['Settings.lua', `local count = ns.profiles.save(name, true)`, `local count = ns.profiles.save(name)`],
  'saveas-message-period': ['Settings.lua', `" as " .. TAB_TEXT[name] .. "."`, `" as " .. TAB_TEXT[name]`],
  'saveas-message-profile': ['Settings.lua', `" as " .. TAB_TEXT[name] .. "."`, `" as " .. TAB_TEXT[state.tab] .. "."`],
  'saveas-note-missing': ['Settings.lua', `    if view.saveBar.note then`, `    if false then`],
  'saveas-note-sticky': ['Settings.lua', `    state.saved = nil                        -- so is what a save button said`, `    local _ = state.saved`],
  'saveas-caption-stays': ['Settings.lua', `        p.saveNote:Show()
        p.saveCaption:Hide()`, `        p.saveNote:Show()
        p.saveCaption:Show()`],
  'saveas-note-stays': ['Settings.lua', `        p.saveCaption:Show()
        p.saveNote:Hide()`, `        p.saveCaption:Show()
        p.saveNote:Show()`],
  'saveas-caption-y': ['Settings.lua', `p.saveCaption:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", SAVE_X, captionY)`, `p.saveCaption:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", SAVE_X, 12)`],
  'saveas-caption-covers': ['Settings.lua', `local captionY = 12 + #TABS * (SAVE_H + SAVE_GAP)`, `local captionY = 12 + (#TABS - 1) * (SAVE_H + SAVE_GAP)`],
  'hub-level-key': ['Settings.lua', `button.key = "level:" .. row.cvar .. ":" .. level.value`, `button.key = "level:" .. row.cvar .. ":0"`],
  'hub-cost-now-colour': ['Settings.lua', `level.cost == "now" and "accentLight" or "dim"`, `"dim"`],
  'hub-two-columns-only': ['Settings.lua', `view.page == "size" and 1 or settings.columnsFor(#rows)`, `view.page == "size" and 1 or 2`],
  'hub-columns-high': ['Settings.lua', `return count > 6 and 3 or 2`, `return count > 8 and 3 or 2`],
  'hub-columns-low': ['Settings.lua', `return count > 6 and 3 or 2`, `return count > 5 and 3 or 2`],
  'hub-column-gap': ['Settings.lua', `local CARD_GAP_X, CARD_GAP_Y = 18, 6`, `local CARD_GAP_X, CARD_GAP_Y = 20, 6`],
  'hub-none-text-missing': ['Settings.lua', `        placeText(p.note, NONE_TEXT)`, `        hideText(p.note)`],
  'hub-levels-not-released': ['Settings.lua', `    release(p.levels)`, `    local _ = p.levels`],
  'hub-ticks-not-released': ['Settings.lua', `    release(p.checks)`, `    local _ = p.checks`],
  'hub-summary-on-every-page': ['Settings.lua', `        if not (onSettings and str) then`, `        if not str then`],

  // The final review's fix pass: a wrapped name pushes the help down, a Home click says what was refused
  'fix-name-wrap-ignored': ['Settings.lua', `local helpTop = top + math.max(18, heightOf(name, row.name) + 2)`, `local helpTop = top + 18`],
  'fix-name-wrap-no-gap': ['Settings.lua', `math.max(18, heightOf(name, row.name) + 2)`, `math.max(18, heightOf(name, row.name))`],
  'fix-cost-wraps': ['Settings.lua', `        fs:SetWordWrap(false)                 -- never wraps`, `        fs:SetWordWrap(true)                 -- never wraps`],
  'fix-refusal-unsaid': ['Settings.lua', `        if #refused > 0 then
            state.notice = "The game would not take " .. (REFUSED_WORDS[name] or "the level")`, `        if false then
            state.notice = "The game would not take " .. (REFUSED_WORDS[name] or "the level")`],
  'fix-refusal-words': ['Settings.lua', `crowded = "the level you saved" }`, `crowded = "the highest level" }`],
  'fix-empty-profile-unsaid': ['Settings.lua', `elseif (name == "everyday" or name == "crowded") and ns.profiles.hasValues and not ns.profiles.hasValues(name) then`, `elseif false then`],
  'fix-empty-note-for-original': ['Settings.lua', `elseif (name == "everyday" or name == "crowded") and ns.profiles.hasValues`, `elseif ns.profiles.hasValues`],
  'fix-maximum-nothing-unsaid': ['Settings.lua', `    if not ok and info == "nothing" then
        state.notice = NOTHING_TEXT
    elseif ok then
        -- The switch stands`, `    if false then
        state.notice = NOTHING_TEXT
    elseif ok then
        -- The switch stands`],

  // The dynamic render scale warning of the test's preflight
  'dynwarn-never': ['Bench.lua', `    if dynamic and dynamic ~= 0 then`, `    if false then`],
  'dynwarn-zero': ['Bench.lua', `    if dynamic and dynamic ~= 0 then`, `    if dynamic then`],
  'dynwarn-only-one': ['Bench.lua', `    if dynamic and dynamic ~= 0 then`, `    if dynamic == 1 then`],
  'dynwarn-text': ['Bench.lua', `"Dynamic render scale is on, so the game changes the picture size`, `"Dynamic scale is on, so the game changes the picture size`],
  'dynwarn-absent': ['Bench.lua', `local dynamic = tonumber(GetCVar("dynamicRenderScale") or "")`, `local dynamic = tonumber(GetCVar("dynamicRenderScale") or "1")`],
  'dynwarn-refuses': ['Bench.lua', `        warnings[#warnings + 1] = "Dynamic render scale is on`, `        problems[#problems + 1] = "Dynamic render scale is on`],

  // The Tests and results page, and the About page
  'tests-intro-text': ['Settings.lua', `local TESTS_INTRO = "The test measures what`, `local TESTS_INTRO = "A test measures what`],
  'tests-result-label': ['Settings.lua', `local label = kind == "best" and "Quiet-spot test" or "Crowd test"`, `local label = kind == "best" and "Crowd test" or "Quiet-spot test"`],
  'tests-not-done-text': ['Settings.lua', `(saved and saved.line or "not done yet.")`, `(saved and saved.line or "none yet.")`],
  'tests-can-always-show': ['Settings.lua', `canShow = saved ~= nil,`, `canShow = true,`],
  'tests-saved-unguarded': ['Settings.lua', `local ok, saved = pcall(ns.ui.savedResult, kind)`, `local ok, saved = true, ns.ui.savedResult(kind)`],
  'tests-progress-missing': ['Settings.lua', `    if progress then
        info.progress = string.format(`, `    if false then
        info.progress = string.format(`],
  'tests-progress-text': ['Settings.lua', `"A test is running: step %d of %d (%s)"`, `"Running: step %d of %d (%s)"`],
  'tests-show-without-result': ['Settings.lua', `if info.results[showKey] and ns.ui and ns.ui.openSaved then`, `if ns.ui and ns.ui.openSaved then`],
  'tests-show-wrong-kind': ['Settings.lua', `ns.ui.openSaved(showKey)`, `ns.ui.openSaved("best")`],
  'about-version-unknown': ['Settings.lua', `    return "unknown"
end`, `    return ""
end`],
  'about-header-version': ['Settings.lua', `f.versionText:SetText(version == "unknown" and "" or "Version " .. version)`, `f.versionText:SetText("Version " .. version)`],
  'about-no-data-sentence': ['Settings.lua', `"It doesn't collect or send anything."`, `"It collects nothing."`],
  'about-probe-command': ['Settings.lua', `    "/fset probe: ask the game which settings it has",
`, ``],
  'about-page-everywhere': ['Settings.lua', `    if view.page == "about" then
        placeText(p.aboutVersion`, `    if true then
        placeText(p.aboutVersion`],

  // The Home page
  'home-card-split': ['Settings.lua', `full:match("^([^:]+):%s*(.+)$")`, `full:match("^(.+)$")`],
  'home-max-fps-missing': ['Settings.lua', `if key == "maximum" and type(home.maxFps) == "number" then`, `if false then`],
  'home-max-fps-wrong-card': ['Settings.lua', `if key == "maximum" and type(home.maxFps) == "number" then`, `if key == "crowded" and type(home.maxFps) == "number" then`],
  'home-test-never-done': ['Settings.lua', `done = saved.best == true`, `done = false`],
  'home-test-crowded-done': ['Settings.lua', `done = saved.crowded == true`, `done = saved.best == true`],
  'home-test-never-greyed': ['Settings.lua', `{ key = "best", text = "Find my best settings", enabled = locked == nil,`, `{ key = "best", text = "Find my best settings", enabled = true,`],
  'home-click-profile-missing': ['Settings.lua', `        switchProfile(profileKey)
        return`, `        local _ = profileKey
        return`],
  'home-click-test-wrong-kind': ['Settings.lua', `ns.ui.openSaved(testKey)`, `ns.ui.openSaved("best")`],
  'home-click-test-any-key': ['Settings.lua', `if (testKey == "best" or testKey == "crowded") and ns.ui and ns.ui.openSaved then`, `if ns.ui and ns.ui.openSaved then`],
  'home-no-redraw-after-switch': ['Settings.lua', `    draw()
end

-- Shows the window on a page`, `end

-- Shows the window on a page`],
  'home-inuse-text': ['Settings.lua', `"In use now: " .. view.home.inUse`, `"In use: " .. view.home.inUse`],
  'home-card-columns': ['Settings.lua', `col * (HOME_CARD_W + CARD_GAP_X)`, `col * HOME_CARD_W`],
  'home-card-height': ['Settings.lua', `math.floor((AREA_W - CARD_GAP_X) / 2), 56`, `math.floor((AREA_W - CARD_GAP_X) / 2), 50`],
  'home-tests-note-missing': ['Settings.lua', `        placeText(p.testsNote, HOME_TESTS_NOTE)`, `        hideText(p.testsNote)`],
  'home-cards-not-hidden': ['Settings.lua', `        for _, card in ipairs(p.profileCards) do card:Hide() end`, `        local _ = p.profileCards`],
  'home-tests-not-hidden': ['Settings.lua', `        for _, button in ipairs(p.testButtons) do button:Hide() end`, `        local _ = p.testButtons`],
  'home-cost-note-missing': ['Settings.lua', `if onSettings or view.page == "home" then placeText(p.costNote`, `if onSettings then placeText(p.costNote`],
  'home-context-missing': ['Settings.lua', `        ctx.home = homeContext()`, `        local _ = homeContext`],
  'home-context-unguarded': ['Settings.lua', `local ok, home = pcall(ns.ui.buildContext)`, `local ok, home = true, ns.ui.buildContext()`],

  // The Picture size page: dynamic render scale
  'dynamic-never-on': ['Settings.lua', `return { on = n ~= nil and n ~= 0 }`, `return { on = false }`],
  'dynamic-zero-is-on': ['Settings.lua', `return { on = n ~= nil and n ~= 0 }`, `return { on = n ~= nil }`],
  'dynamic-absent-shown': ['Settings.lua', `    if raw == nil then return nil end
    local n = tonumber(raw)`, `    local n = tonumber(raw)`],
  'dynamic-line-missing': ['Settings.lua', `if ctx.dynamicScale then view.dynamicLine =`, `if false then view.dynamicLine =`],
  'dynamic-text-swapped': ['Settings.lua', `ctx.dynamicScale.on and DYNAMIC_ON or DYNAMIC_OFF`, `ctx.dynamicScale.on and DYNAMIC_OFF or DYNAMIC_ON`],
  'dynamic-on-text': ['Settings.lua', `which spoils a test. Turn it off`, `which spoils tests. Turn it off`],
  'dynamic-every-page': ['Settings.lua', `if view.page == "size" and view.dynamicLine then`, `if view.dynamicLine then`],
  'dynamic-line-not-placed': ['Settings.lua', `        placeText(p.dynamicLine, view.dynamicLine)`, `        hideText(p.dynamicLine)`],
  'dynamic-colour-swapped': ['Settings.lua', `ctx.dynamicScale.on and "warning" or "dim"`, `ctx.dynamicScale.on and "dim" or "warning"`],

  // The pages of the hub window
  'page-order-wrong': ['Settings.lua', `{ key = "home", text = "Home" }, { key = "light", text = "Light and shadows" },`, `{ key = "light", text = "Light and shadows" }, { key = "home", text = "Home" },`],
  'page-text-wrong': ['Settings.lua', `{ key = "size", text = "Picture size" }`, `{ key = "size", text = "Picture sizes" }`],
  'page-of-wrong': ['Settings.lua', `graphicsssao = "light"`, `graphicsssao = "world"`],
  'page-of-size-wrong': ['Settings.lua', `renderscale = "size",`, `renderscale = "world",`],
  'page-unknown-not-world': ['Settings.lua', `settings.PAGE_OF[cvar:lower()] or "world"`, `settings.PAGE_OF[cvar:lower()] or "light"`],


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
  'settings-max-clamp-notice-missing': ['Settings.lua', `        if #refused > 0 then
            state.notice = "The game would not take "`, `        if false then
            state.notice = "The game would not take "`],
  'settings-max-clamp-raw-name': ['Settings.lua', `local name = ns.names.label(m.cvar, "")`, `local name = m.cvar`],
  'settings-max-clamp-unnamed-listed': ['Settings.lua', `        if name ~= "" then list[#list + 1] = name end`, `        list[#list + 1] = name`],

  // Controls for the harness itself: a comment survives, a missing pattern and a syntax error are errors, never kills.
  'control-comment': ['Bench.lua', `    return guard.drift(a, b) > K.NOISE`, `    return guard.drift(a, b) > K.NOISE -- control`],
  'control-missing': ['Bench.lua', `this line does not exist anywhere in the file`, `x`],
  'control-syntax': ['Bench.lua', `    return guard.drift(a, b) > K.NOISE`, `    return (`],
  // One saved picture size (spec 2026-11-02-one-saved-picture-size-design.md)
  'sz-safe-shift-ignored': ['ForeverSettings.lua', `safeStart = IsShiftKeyDown() and true or false`, `safeStart = false`],
  'sz-safe-always': ['ForeverSettings.lua', `safeStart = IsShiftKeyDown() and true or false`, `safeStart = true`],
  'sz-safe-skips-all-settings': ['ForeverSettings.lua', `name:lower() == "renderscale" and (tonumber(value) or 0) > 1 then`, `(tonumber(value) or 0) > 1 then`],
  'sz-safe-skips-100': ['ForeverSettings.lua', `name:lower() == "renderscale" and (tonumber(value) or 0) > 1 then`, `name:lower() == "renderscale" and (tonumber(value) or 0) >= 1 then`],
  'sz-safe-silent': ['ForeverSettings.lua', `say("Shift is held: picture sharpness above 100% is not applied this session.")`, `local _ = say`],
  'sz-safe-said-every-time': ['ForeverSettings.lua', `            if not safeSaid then`, `            if true then`],
  'sz-logout-off': ['ForeverSettings.lua', `if kept and kept > 1 and live and live > 1 then pcall(SetCVar, "RenderScale", "1") end`, `local _ = kept`],
  'sz-logout-no-kept': ['ForeverSettings.lua', `kept and kept > 1 and live and live > 1`, `live and live > 1`],
  'sz-logout-no-live': ['ForeverSettings.lua', `kept and kept > 1 and live and live > 1`, `kept and kept > 1`],
  'sz-logout-100': ['ForeverSettings.lua', `kept and kept > 1 and live`, `kept and kept >= 1 and live`],
  'sz-logout-value': ['ForeverSettings.lua', `pcall(SetCVar, "RenderScale", "1") end`, `pcall(SetCVar, "RenderScale", "1.5") end`],
  'sz-logout-unguarded': ['ForeverSettings.lua', `pcall(SetCVar, "RenderScale", "1") end`, `SetCVar("RenderScale", "1") end`],
  'sz-cmd-range-low': ['ForeverSettings.lua', `if number < 50 or number > 200 then`, `if number < 49 or number > 200 then`],
  'sz-cmd-range-high': ['ForeverSettings.lua', `if number < 50 or number > 200 then`, `if number < 50 or number > 201 then`],
  'sz-cmd-no-off': ['ForeverSettings.lua', `if word == "off" or word == "normal" or word == "back" then`, `if word == "normal" or word == "back" then`],
  'sz-cmd-no-normal': ['ForeverSettings.lua', `if word == "off" or word == "normal" or word == "back" then`, `if word == "off" or word == "back" then`],
  'sz-cmd-no-back': ['ForeverSettings.lua', `if word == "off" or word == "normal" or word == "back" then`, `if word == "off" or word == "normal" then`],
  'sz-cmd-percent-sign': ['ForeverSettings.lua', `tonumber((word:gsub("%%$", "")))`, `tonumber(word)`],
  'sz-cmd-format': ['ForeverSettings.lua', `string.format("%.4g", number / 100)`, `string.format("%.2g", number / 100)`],
  'sz-cmd-unavailable': ['ForeverSettings.lua', `if live == nil then say("this client has no picture sharpness setting") return end`, `if live == nil then say("this client has no picture sharpness setting") end`],
  'sz-cmd-no-profiles': ['ForeverSettings.lua', `if not (ns.profiles and ns.profiles.setValue) then say("profiles module not loaded") return end`, `if false then end`],
  'sz-cmd-not-routed': ['ForeverSettings.lua', `    elseif cmd == "size" then`, `    elseif cmd == "sizes" then`],
  'sz-cmd-sets-nothing': ['ForeverSettings.lua', `ns.profiles.setValue("RenderScale", string.format("%.4g", number / 100))`, `local _ = number`],
  'sz-commands-line': ['ForeverSettings.lua', `probe [names], size [percent], profile`, `probe [names], profile`],
  'sz-extra-missing': ['Settings.lua', `            for _, value in ipairs(SIZE_EXTRA) do tiers[#tiers + 1] = value end`, `            local _ = SIZE_EXTRA`],
  'sz-extra-list': ['Settings.lua', `local SIZE_EXTRA = { "1.25", "1.5", "1.75", "2" }`, `local SIZE_EXTRA = { "1.25", "1.5", "2" }`],
  'sz-extra-in-place': ['Settings.lua', `            tiers = {}
            for _, value in ipairs(entry.tiers) do tiers[#tiers + 1] = value end
`, `            tiers = entry.tiers
`],
  'sz-extra-all-settings': ['Settings.lua', `        if cvar:lower() == "renderscale" then
            tiers = {}`, `        if true then
            tiers = {}`],
  'sz-value-unclamped': ['Settings.lua', `value = math.max(SIZE_MIN, math.min(SIZE_MAX, percent))`, `value = percent`],
  'sz-no-setting': ['Settings.lua', `    local live = tonumber(GetCVar("RenderScale"))
    if live == nil then return nil end`, `    local live = tonumber(GetCVar("RenderScale"))
    live = live or 1`],
  'sz-context-rounding': ['Settings.lua', `return { live = math.floor(live * 100 + 0.5) }`, `return { live = math.floor(live * 100) }`],
  'sz-round-down': ['Settings.lua', `math.floor((tonumber(value) or SIZE_MIN) / SIZE_STEP + 0.5) * SIZE_STEP`, `math.floor((tonumber(value) or SIZE_MIN) / SIZE_STEP) * SIZE_STEP`],
  'sz-applies-while-dragging': ['Settings.lua', `p.sizeLabel:SetText(settings.sizeLabel(roundToStep(value)))`, `settings.click("size:" .. roundToStep(value))`],
  'sz-save-range-low': ['Settings.lua', `if percent < SIZE_MIN or percent > SIZE_MAX then return end`, `if percent < 0 or percent > SIZE_MAX then return end`],
  'sz-save-range-high': ['Settings.lua', `if percent < SIZE_MIN or percent > SIZE_MAX then return end`, `if percent < SIZE_MIN or percent > 300 then return end`],
  'sz-save-format': ['Settings.lua', `local value = string.format("%.4g", percent / 100)`, `local value = string.format("%.2g", percent / 100)`],
  'sz-save-notice-missing': ['Settings.lua', `if held ~= nil and not sameValue(held, value) then`, `if false then`],
  'sz-save-click-pattern': ['Settings.lua', `key:match("^size:(%d+)$")`, `key:match("^size:(%d%d)$")`],
  'sz-save-back-missing': ['Settings.lua', `    if key == "sizeback" then
        saveSize(100)`, `    if key == "sizeback-off" then
        saveSize(100)`],
  'sz-save-back-value': ['Settings.lua', `        saveSize(100)`, `        saveSize(50)`],
  'sz-keep-reads-game': ['Settings.lua', `            local now = GetCVar(cvar)`, `            local now = nil`],
  'sz-frame-one-column': ['Settings.lua', `view.page == "size" and 1 or settings.columnsFor(#rows)`, `settings.columnsFor(#rows)`],
  'sz-frame-back-label': ['Settings.lua', `skin.button(area, "Back to 100%", SIZE_BACK_WIDTH, 24)`, `skin.button(area, "Back to normal", SIZE_BACK_WIDTH, 24)`],
  'sz-frame-safe-missing': ['Settings.lua', `        if size.safe then placeText(p.sizeSafe, size.safe) else hideText(p.sizeSafe) end`, `        hideText(p.sizeSafe)`],
  'sz-frame-label-missing': ['Settings.lua', `        placeText(p.sizeLabel, size.label)`, `        local _ = size.label`],
  'sz-frame-value-not-set': ['Settings.lua', `        p.sizeSlider:SetValue(size.value)`, `        local _ = size.value`],
  'sz-frame-back-enabled': ['Settings.lua', `p.sizeBack:SetEnabled(size.canPutBack)`, `p.sizeBack:SetEnabled(true)`],
  'sz-frame-slider-greyed': ['Settings.lua', `p.sizeSlider:SetEnabled(size.enabled)`, `p.sizeSlider:SetEnabled(true)`],
  'sz-range-max': ['Settings.lua', `SIZE_SLIDER_WIDTH, SIZE_MIN, SIZE_MAX, SIZE_STEP)`, `SIZE_SLIDER_WIDTH, SIZE_MIN, 150, SIZE_STEP)`],
  'sz-step': ['Settings.lua', `SIZE_SLIDER_WIDTH, SIZE_MIN, SIZE_MAX, SIZE_STEP)`, `SIZE_SLIDER_WIDTH, SIZE_MIN, SIZE_MAX, 1)`],
  // The fix pass after the fresh review of the saved picture size
  'sz-safe-reads-every-time': ['ForeverSettings.lua', `if safeStart and not asked[name:lower()] and name:lower()`, `if (safeStart or IsShiftKeyDown()) and not asked[name:lower()] and name:lower()`],
  'sz-safe-skips-manual': ['ForeverSettings.lua', `if safeStart and not asked[name:lower()] and name:lower()`, `if safeStart and name:lower()`],
  'sz-safe-skips-explicit': ['ForeverSettings.lua', `if safeStart and not asked[name:lower()] and name:lower()`, `if safeStart and not next(asked) and name:lower()`],
  'sz-cmd-status-kept': ['ForeverSettings.lua', `        local kept = keptSize()
        local tail`, `        local kept = nil
        local tail`],
  'sz-cmd-status-differs': ['ForeverSettings.lua', `        elseif kept ~= nil then
            tail = " (kept at "`, `        elseif false then
            tail = " (kept at "`],
  'sz-kept-any-spelling': ['ForeverSettings.lua', `        if name:lower() == "renderscale" then return tonumber(value) end`, `        if name == "RenderScale" then return tonumber(value) end`],
  'sz-own-spelling-set': ['ForeverSettings.lua', `        name = ownSpelling(name)
        warned[name] = nil`, `        warned[name] = nil`],
  'sz-own-spelling-unset-first': ['ForeverSettings.lua', `        if db.want[target] == nil then target = ownSpelling(target) end`, `        target = ownSpelling(target)`],
  'sz-own-spelling-unset-missing': ['ForeverSettings.lua', `        if db.want[target] == nil then target = ownSpelling(target) end`, `        local _ = ownSpelling`],
  'sz-pending-manual-lost': ['ForeverSettings.lua', `        for name in pairs(asked) do pendingAsked[name] = true end`, ``],
  'sz-pending-replay-plain': ['ForeverSettings.lua', `applyAll(false, false, pendingAsked)`, `applyAll(false)`],
  'sz-pending-manual-sticky': ['ForeverSettings.lua', `    pending = false
    pendingAsked = {}`, `    pending = false`],
  'sz-shift-clamp-missing': ['ForeverSettings.lua', `                if size and size > 1 then`, `                if false then`],
  'sz-shift-clamp-100': ['ForeverSettings.lua', `                if size and size > 1 then`, `                if size and size >= 1 then`],
  'sz-shift-clamp-always': ['ForeverSettings.lua', `            if safeStart then
                local size`, `            if true then
                local size`],
  'sz-shift-clamp-silent': ['ForeverSettings.lua', `say("Shift is held: picture sharpness was above 100%, so it is back at 100% for this session.")`, `local _ = say`],
  'sz-shift-clamp-value': ['ForeverSettings.lua', `                    pcall(SetCVar, "RenderScale", "1")
                    say("Shift`, `                    pcall(SetCVar, "RenderScale", "1.5")
                    say("Shift`],
  'sz-shift-clamp-unguarded': ['ForeverSettings.lua', `                    pcall(SetCVar, "RenderScale", "1")
                    say("Shift`, `                    SetCVar("RenderScale", "1")
                    say("Shift`],
  'sz-warning-at-100': ['Settings.lua', `local risky = percent > 100 or`, `local risky = percent >= 100 or`],
  'sz-warning-never': ['Settings.lua', `warning = risky and SIZE_WARNING or nil`, `warning = nil`],
  'sz-safe-never': ['Settings.lua', `safe = risky and SIZE_SAFE or nil`, `safe = nil`],
  'sz-safe-at-100': ['Settings.lua', `safe = risky and SIZE_SAFE or nil`, `safe = (risky or percent == 100) and SIZE_SAFE or nil`],
  'sz-kept-not-risky': ['Settings.lua', `(keptPercent ~= nil and keptPercent > 100)`, `false`],
  'sz-preflight-size-missing': ['Bench.lua', `    if size and size > 1 then`, `    if false then`],
  'sz-preflight-size-100': ['Bench.lua', `    if size and size > 1 then`, `    if size and size >= 1 then`],
  // Editing a tab that is not in use: the where line, Switch to <tab>, and what a save replaced (the owner's report of 2026-11-02)
  'sw-keep-save-routed': ['Settings.lua', `        keepCurrent(saveKey)`, `        local _ = saveKey`],
  'sw-keep-text-dropped': ['Settings.lua', `if replaced ~= "" then text = text .. " " .. replaced end`, `local _ = replaced`],
  'sw-keep-swapped': ['Settings.lua', `replacedText(before, db.profiles[name].values)`, `replacedText(db.profiles[name].values, before)`],
  'sw-keep-before-missing': ['Settings.lua', `for cvar, value in pairs(db and db.profiles[name] and db.profiles[name].values or {}) do before[cvar] = value end`, `local _ = db`],
  'sw-replaced-unchanged': ['Settings.lua', `if was ~= nil and now ~= nil and not sameValue(was, now) then`, `if was ~= nil and now ~= nil then`],
  'sw-replaced-no-prior': ['Settings.lua', `if was ~= nil and now ~= nil and not sameValue(was, now) then`, `if now ~= nil and not sameValue(was, now) then`],
  'sw-replaced-cap': ['Settings.lua', `for i = 1, math.min(3, #lines) do shown[i] = lines[i] end`, `for i = 1, math.min(4, #lines) do shown[i] = lines[i] end`],
  'sw-replaced-more': ['Settings.lua', `if #lines > 3 then text = text .. "; and " .. (#lines - 3) .. " more" end`, `if #lines > 4 then text = text .. "; and " .. (#lines - 3) .. " more" end`],
  'sw-replaced-more-count': ['Settings.lua', `"; and " .. (#lines - 3) .. " more"`, `"; and " .. #lines .. " more"`],
  'sw-replaced-words': ['Settings.lua', `" was " .. ns.names.level(cvar, was) .. ", now " .. ns.names.level(cvar, now)`, `" is " .. ns.names.level(cvar, now)`],
  // My settings edits the profile in use (spec 2026-11-02-edit-the-profile-in-use-design.md): rows re-anchored on the new code
  'settings-lock-not-checked': ['Settings.lua', `    if ctx.locked then
        -- a profile switch says why it was refused (the window may not have caught up with the lock yet)
        if key:find("^profile:") or key:find("^edit:") or key:find("^rocker:") then draw() end
        return
    end
`, `    local _ = ctx.locked
`],
  'saveas-locked-saves': ['Settings.lua', `    if ctx.locked then
        -- a profile switch says why`, `    if ctx.locked and not key:find("^save:") then
        -- a profile switch says why`],
  'home-card-unmarked': ['Settings.lua', `selected = ctx.active == key,`, `selected = false,`],
  'home-card-never-greyed': ['Settings.lua', `enabled = locked == nil, color = PROFILE_COLOR[key] }`, `enabled = true, color = PROFILE_COLOR[key] }`],
  'settings-use-wrong-profile': ['Settings.lua', `keepCurrent(saveKey)`, `keepCurrent("everyday")`],
  'live-no-test-needed': ['Settings.lua', `if editing and next(saved) ~= nil and costs and est and`, `if editing and next(saved) ~= nil and est and`],
  'live-tab-name': ['Settings.lua', `TAB_TEXT[editing], est.fps)`, `"Everyday", est.fps)`],
  'live-context-dropped': ['Settings.lua', `ctx.costs, ctx.maximum, ctx.estimate = costsAndMaximum(`, `ctx.costs, ctx.maximum = costsAndMaximum(`],
  'home-inuse-label': ['Settings.lua', `view.home = { inUse = labels[ctx.active] or tostring(ctx.active)`, `view.home = { inUse = tostring(ctx.active)`],
  'page-open-ignores-page': ['Settings.lua', `    elseif PAGE_KEYS[which] or ADVANCED_PAGE[which] then      -- an Advanced page shows only while Advanced is on (the model decides)
        state.page = which
    end`, `    end`],
  'page-open-bogus': ['Settings.lua', `    elseif PAGE_KEYS[which] or ADVANCED_PAGE[which] then`, `    elseif which then`],
  'sz-percent-rounding': ['Settings.lua', `math.floor(tonumber(keptSize) * 100 + 0.5)`, `math.floor(tonumber(keptSize) * 100)`],
  'sz-label-in-use': ['Settings.lua', `label = settings.sizeLabel(percent), note = note`, `label = settings.sizeLabel(keptPercent or percent), note = note`],
  'sz-note-none': ['Settings.lua', `            if keptSize == nil then
                note = "Not kept`, `            if keptSize ~= nil then
                note = "Not kept`],
  'sz-note-differs': ['Settings.lua', `            elseif differs then
                note = "Kept in "`, `            elseif false then
                note = "Kept in "`],
  'sz-save-loud': ['Settings.lua', `ns.profiles.setProfileValue(profile, "RenderScale", value, true)`, `ns.profiles.setProfileValue(profile, "RenderScale", value)`],
  'sz-putback-always': ['Settings.lua', `canPutBack = editing ~= nil and (percent ~= 100 or differs) and locked == nil`, `canPutBack = editing ~= nil and locked == nil`],
  'sz-putback-differs-missing': ['Settings.lua', `canPutBack = editing ~= nil and (percent ~= 100 or differs) and locked == nil`, `canPutBack = editing ~= nil and percent ~= 100 and locked == nil`],
  'sz-putback-ignores-lock': ['Settings.lua', `canPutBack = editing ~= nil and (percent ~= 100 or differs) and locked == nil`, `canPutBack = editing ~= nil and (percent ~= 100 or differs)`],
  'sz-enabled-ignores-lock': ['Settings.lua', `safe = risky and SIZE_SAFE or nil, enabled = locked == nil and editing ~= nil,`, `safe = risky and SIZE_SAFE or nil, enabled = editing ~= nil,`],
  'sz-frame-stack-order': ['Settings.lua', `        if size.safe then placeText(p.sizeSafe, size.safe) else hideText(p.sizeSafe) end
        if size.note then placeText(p.sizeNote, size.note) else hideText(p.sizeNote) end`, `        if size.note then placeText(p.sizeNote, size.note) else hideText(p.sizeNote) end
        if size.safe then placeText(p.sizeSafe, size.safe) else hideText(p.sizeSafe) end`],

  // My settings edits the profile in use: the new code
  'ed-costs-profile-in-use': ['Settings.lua', `costsAndMaximum(TAB_TEXT[ctx.active] and ctx.active or "everyday")`, `costsAndMaximum("everyday")`],
  'ed-pill-label': ['Settings.lua', `text = labels[ctx.active] or tostring(ctx.active), color = PROFILE_COLOR`, `text = tostring(ctx.active), color = PROFILE_COLOR`],
  'ed-open-profile-page': ['Settings.lua', `    if which == "everyday" or which == "crowded" then
        state.page = "light"`, `    if which == "everyday" or which == "crowded" then
        state.page = state.page`],
  'ed-size-note-only-editing': ['Settings.lua', `        if editing then
            local tab = TAB_TEXT[editing]`, `        if true then
            local tab = TAB_TEXT[editing] or "Everyday"`],
  'ed-size-save-read-only': ['Settings.lua', `    local profile = ns.profiles.active()
    if not TAB_TEXT[profile] then return end`, `    local profile = ns.profiles.active()
    if not TAB_TEXT[profile] then profile = "everyday" end`],
  'ed-putback-read-only': ['Settings.lua', `canPutBack = editing ~= nil and (percent ~= 100 or differs) and locked == nil`, `canPutBack = (percent ~= 100 or differs) and locked == nil`],
  'ed-size-enabled-read-only': ['Settings.lua', `safe = risky and SIZE_SAFE or nil, enabled = locked == nil and editing ~= nil,`, `safe = risky and SIZE_SAFE or nil, enabled = locked == nil,`],
  'ed-rows-editable-read-only': ['Settings.lua', `enabled = locked == nil and editing ~= nil, page = settings.PAGE_OF`, `enabled = locked == nil, page = settings.PAGE_OF`],
  'ed-saved-maximum-own': ['Settings.lua', `local saved = editing and ((ctx.saved or {})[editing] or {}) or (ctx.want or {})`, `local saved = editing and ((ctx.saved or {})[editing] or {}) or {}`],
  'ed-saved-wrong-profile': ['Settings.lua', `local saved = editing and ((ctx.saved or {})[editing] or {}) or (ctx.want or {})`, `local saved = editing and ((ctx.saved or {}).everyday or {}) or (ctx.want or {})`],
  'ed-chosen-saved': ['Settings.lua', `        local chosen = ctx.live(cvar)`, `        local chosen = saved[cvar] or ctx.live(cvar)`],
  'ed-read-only-missing': ['Settings.lua', `    if not editing then
        view.readOnly =`, `    if false then
        view.readOnly =`],
  'ed-read-only-text': ['Settings.lua', `view.readOnly = { text = view.profile.text .. READ_ONLY_TAIL, buttons = {} }`, `view.readOnly = { text = READ_ONLY_TAIL, buttons = {} }`],
  'ed-read-only-tail': ['Settings.lua', `READ_ONLY_TAIL = " can't be changed. To change settings, edit:"`, `READ_ONLY_TAIL = " can't be changed."`],
  'ed-read-only-buttons-unlocked': ['Settings.lua', `color = PROFILE_COLOR[key],
                enabled = locked == nil }`, `color = PROFILE_COLOR[key],
                enabled = true }`],
  'ed-edit-key': ['Settings.lua', `key = "edit:" .. key, text = TAB_TEXT[key]`, `key = "profile:" .. key, text = TAB_TEXT[key]`],
  'ed-home-card-colour': ['Settings.lua', `enabled = locked == nil, color = PROFILE_COLOR[key] }`, `enabled = locked == nil, color = "dim" }`],
  'ed-notice-maximum': ['Settings.lua', `    if ctx.active == "maximum" then
        view.notice = MAXIMUM_NOTE`, `    if false then
        view.notice = MAXIMUM_NOTE`],
  'ed-yourline-needs-saved': ['Settings.lua', `if editing and next(saved) ~= nil and costs`, `if editing and costs`],
  'ed-yourline-read-only': ['Settings.lua', `if editing and next(saved) ~= nil and costs`, `if next(saved) ~= nil and costs`],
  'ed-edit-switches': ['Settings.lua', `if TAB_TEXT[editKey] then switchProfile(editKey) end`, `if TAB_TEXT[editKey] then switchProfile("everyday") end`],
  'ed-click-read-only-guard': ['Settings.lua', `    local profile = TAB_TEXT[ctx.active] and ctx.active or nil
    if not profile then return end`, `    local profile = TAB_TEXT[ctx.active] and ctx.active or "everyday"
    if not profile then return end`],
  'ed-frame-read-only-on-home': ['Settings.lua', `    if (onSettings or onAdvanced) and view.readOnly then
        placeText(p.readOnly`, `    if view.readOnly then
        placeText(p.readOnly`],
  'ed-frame-read-only-never': ['Settings.lua', `    if (onSettings or onAdvanced) and view.readOnly then
        placeText(p.readOnly`, `    if false and view.readOnly then
        placeText(p.readOnly`],
  'ed-frame-edit-spacing': ['Settings.lua', `(i - 1) * (EDIT_W + 8), -y)`, `(i - 1) * EDIT_W, -y)`],
  'ed-frame-edit-gap-below': ['Settings.lua', `        y = y + EDIT_H + 8
    else
        hideText(p.readOnly)`, `        y = y + 8
    else
        hideText(p.readOnly)`],
  'ed-frame-edit-left-shown': ['Settings.lua', `for _, button in ipairs(p.editButtons) do button:Hide() end`, `local _ = p.editButtons`],
  'ed-frame-edit-size': ['Settings.lua', `local EDIT_W, EDIT_H = 112, 24`, `local EDIT_W, EDIT_H = 120, 24`],
  'ed-frame-card-dot': ['Settings.lua', `card.dot:SetColorName(profile.color)`, `card.dot:SetColorName("dim")`],
  'ed-summary-bottom': ['Settings.lua', `local SUMMARY_BOTTOM = 12`, `local SUMMARY_BOTTOM = 20`],
  'ed-skin-colour-everyday': ['Skin.lua', `profileEveryday = "5dcaa5"`, `profileEveryday = "5dcaa6"`],
  'ed-skin-colour-crowded': ['Skin.lua', `profileCrowded = "ef9f27"`, `profileCrowded = "ef9f28"`],
  'ed-skin-dot-size': ['Skin.lua', `dot:SetSize(8, 8)`, `dot:SetSize(10, 10)`],
  'ed-skin-dot-recolour': ['Skin.lua', `function dot:SetColorName(name) self.box.fill:SetColorTexture(skin.color(name)) end`, `function dot:SetColorName(name) end`],
  // The fix pass after the fresh review of the redesign: a read-only page still shows what the game has
  'ed-skin-disabled-selected-lost': ['Skin.lua', `if state.selected then fill, text = "selected", "dim" end`, `if false then fill, text = "selected", "dim" end`],
  'ed-skin-disabled-selected-bright': ['Skin.lua', `fill, text = "selected", "dim"`, `fill, text = "selected", "bright"`],
  'ed-skin-check-dim-mark-missing': ['Skin.lua', `    box:SetDisabledCheckedTexture(newMark("dim"))`, `    local _ = newMark`],
  'ed-skin-check-dim-mark-accent': ['Skin.lua', `newMark("dim")`, `newMark("accent")`],
  'ed-skin-check-hover-disabled': ['Skin.lua', `        if self:IsEnabled() then for _, tex`, `        if true then for _, tex`],
  'skin-check-mark': ['Skin.lua', `box:SetCheckedTexture(newMark("accent"))`, `box:SetCheckedTexture(newMark("text"))`],
  'skin-round-check-hover': ['Skin.lua', `do tex:SetColorTexture(skin.color("border")) end end`, `do tex:SetColorTexture(skin.color("text")) end end`],
  // The table run on the redesign: heldValues reads only the game now (its saved-values branch could no longer be reached)
  'live-held-none': ['Settings.lua', `        local value = GetCVar(entry.cvar)
        if value ~= nil then values[entry.cvar] = value end`, `        local _ = entry`],
  // The minimap button's own gauge icon (owner request 2026-11-03)
  'ui-icon-gear': ['UI.lua', `icon:SetTexture("Interface/AddOns/" .. addonName .. "/Media/icon.tga")`, `icon:SetTexture("Interface/Icons/INV_Misc_Gear_01")`],
  'ui-icon-size': ['UI.lua', `    icon:SetSize(20, 20)`, `    icon:SetSize(24, 24)`],
  'ui-icon-layer': ['UI.lua', `local icon = button:CreateTexture(nil, "ARTWORK")`, `local icon = button:CreateTexture(nil, "OVERLAY")`],
  // The gauge icon in the title bar (owner request 2026-11-03)
  'skin-title-icon-picture': ['Skin.lua', `    f.icon:SetTexture(MEDIA .. "icon.tga")`, `    f.icon:SetTexture(MEDIA .. "fill4.tga")`],
  'skin-title-icon-size': ['Skin.lua', `    f.icon:SetSize(20, 20)`, `    f.icon:SetSize(24, 24)`],
  'skin-title-icon-place': ['Skin.lua', `f.icon:SetPoint("LEFT", header, "LEFT", 12, 0)`, `f.icon:SetPoint("LEFT", header, "LEFT", 14, 0)`],
  'skin-title-not-after-icon': ['Skin.lua', `f.titleText:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)`, `f.titleText:SetPoint("LEFT", header, "LEFT", 14, 0)`],
  // Picks on the graph (spec 2026-11-03-tests-and-results-in-my-settings-design.md M5): recommend.withPicks and chartModel's marks
  'pk-original-changed': ['Recommend.lua', `    local view = {}
    for k, v in pairs(result) do view[k] = v end`, `    local view = result`],
  'pk-settings-shared': ['Recommend.lua', `        local copy = {}
        for k, v in pairs(s) do copy[k] = v end`, `        local copy = s`],
  'pk-recommend-unreachable': ['Recommend.lua', `copy.recommended = recommending and s.chosen or s.current`, `copy.recommended = s.chosen`],
  'pk-pick-unmeasured': ['Recommend.lua', `if level.counted and sameValue(level.value, pick) and not sameValue(level.value, copy.recommended) then`, `if sameValue(level.value, pick) and not sameValue(level.value, copy.recommended) then`],
  'pk-pick-recommended-counts': ['Recommend.lua', `if level.counted and sameValue(level.value, pick) and not sameValue(level.value, copy.recommended) then`, `if level.counted and sameValue(level.value, pick) then`],
  'pk-no-picks-recomputed': ['Recommend.lua', `    if view.picked == 0 then return view end`, `    local _ = view`],
  'pk-cap-missing': ['Recommend.lua', `view.afterMs = math.max(result.nowMs + total, result.nowMs / recommend.MAX_SPEEDUP)`, `view.afterMs = result.nowMs + total`],
  'pk-delta-ignored': ['Recommend.lua', `total = total + (to and to.deltaMs or 0)`, `total = total + 0`],
  'pk-same-level-a-change': ['Recommend.lua', `if from and to and not sameValue(from.value, to.value) then`, `if from and to then`],
  'pk-nochange-sentence': ['Recommend.lua', `view.status, view.summary = "nochange", "With your picks, nothing changes."`, `view.status, view.summary = "nochange", result.summary`],
  'pk-old-sentence-kept': ['Recommend.lua', `view.status, view.summary = "change", nil`, `view.status = "change"`],
  'pk-picked-mark': ['Recommend.lua', `picked = s.picked == true and level.value == s.chosen,`, `picked = false,`],
  'pk-recommended-follows-pick': ['Recommend.lua', `        local recommendedLevel = s.recommended
`, `        local recommendedLevel = nil
`],
  'pk-estimate-label': ['Recommend.lua', `" fps" .. (picked > 0 and " (estimate)" or ""),`, `" fps",`],
  'pk-check-before-missing': ['Recommend.lua', `    if checkedBefore then`, `    if false then`],
  'pk-measured-kept': ['Recommend.lua', `    if picked > 0 then measuredFps = nil end`, `    local _ = picked`],
  'pk-verdict-estimate': ['Recommend.lua', `(picked > 0 and " (an estimate)." or ".")`, `"."`],
  'check-zero-baseline-accepted': ['Recommend.lua', `        and type(verify.baselineMs) == "number" and verify.baselineMs > 0 then
        measuredFps =`, `        and type(verify.baselineMs) == "number" then
        measuredFps =`],
  'graph-recommended-on-current': ['Recommend.lua', `recommended = changing and level.value == recommendedLevel and not level.current, doubtful = false,`, `recommended = changing and level.value == recommendedLevel, doubtful = false,`],
  'graph-recommended-always': ['Recommend.lua', `recommended = changing and level.value == recommendedLevel and not level.current, doubtful = false,`, `recommended = level.value == recommendedLevel and not level.current, doubtful = false,`],
  // The graph's new look and clickable points (spec 2026-11-03-tests-and-results-in-my-settings-design.md M4, M5); the first nine
  // re-anchor the rows of the old square points
  'graph-draw-point-size': ['Graph.lua', `local POINT, HIT, RING = 8, graph.HIT, 16`, `local POINT, HIT, RING = 10, graph.HIT, 16`],
  'graph-draw-doubtful-filled': ['Graph.lua', `                elseif p.doubtful then
                    mark(dots, "hollow", item.x, item.y, nil, COLORS.hollow)`, `                elseif false then
                    mark(dots, "hollow", item.x, item.y, nil, COLORS.hollow)`],
  'graph-draw-ring-missing': ['Graph.lua', `                    mark(rings, "ring", item.x, item.y, nil, COLORS.ring)`, `                    local _ = rings`],
  'graph-draw-recommended-uncoloured': ['Graph.lua', `mark(dots, "recommended", item.x, item.y, COLORS.recommended)`, `mark(dots, "recommended", item.x, item.y, COLORS.point)`],
  'graph-draw-label-all-levels': ['Graph.lua', `if k == 1 or k == #points or p.current or p.recommended or p.picked then`, `if true then`],
  'graph-draw-label-last-missing': ['Graph.lua', `if k == 1 or k == #points or p.current or p.recommended or p.picked then`, `if k == 1 or p.current or p.recommended or p.picked then`],
  'gr-palette-line': ['Graph.lua', `line = paletteColor("accentDim")`, `line = paletteColor("accent")`],
  'gr-palette-recommended': ['Graph.lua', `recommended = paletteColor("accent")`, `recommended = paletteColor("warning")`],
  'gr-palette-picked': ['Graph.lua', `picked = paletteColor("profileEveryday")`, `picked = paletteColor("profileCrowded")`],
  'gr-accent-dim-value': ['Skin.lua', `accentDim = "6f72c8"`, `accentDim = "6f72c9"`],
  'gr-ring-size': ['Graph.lua', `local POINT, HIT, RING = 8, graph.HIT, 16`, `local POINT, HIT, RING = 8, graph.HIT, 14`],
  'gr-ring-square': ['Graph.lua', `return newMark(parent, RING, ns.skin.RADIUS.window)`, `return newMark(parent, RING, ns.skin.RADIUS.control)`],
  'gr-ring-filled': ['Graph.lua', `m.box.fill:SetColorTexture(f[1], f[2], f[3], fillColor and f[4] or 0)`, `m.box.fill:SetColorTexture(f[1], f[2], f[3], 1)`],
  'gr-picked-not-drawn': ['Graph.lua', `                if p.picked then
                    mark(dots, "picked"`, `                if false then
                    mark(dots, "picked"`],
  'gr-pick-colour-ignored': ['Graph.lua', `options.pickColor == "crowded" and COLORS.pickedCrowd or COLORS.picked`, `COLORS.picked`],
  'gr-pick-tooltip': ['Graph.lua', `    if p.picked then marks[#marks + 1] = "your pick" end`, `    local _ = p`],
  'gr-hit-small': ['Graph.lua', `graph.HIT = 20 `, `graph.HIT = 14 `],
  'gr-click-missing': ['Graph.lua', `button:SetScript("OnClick", onPick and function() onPick(value) end or nil)`, `button:SetScript("OnClick", nil)`],
  'gr-click-always': ['Graph.lua', `button:SetScript("OnClick", onPick and function() onPick(value) end or nil)`, `if onPick then button:SetScript("OnClick", function() onPick(value) end) end`],
  'gr-click-wrong-level': ['Graph.lua', `local onPick, value = options.onPick, p.value`, `local onPick, value = options.onPick, points[1].point.value`],
  'gr-marks-left-behind': ['Graph.lua', `        release(dots)
        release(rings)`, `        local _ = dots`],
  // The two pages in My settings (spec 2026-11-03-tests-and-results-in-my-settings-design.md M1-M3); the first thirteen re-anchor
  // older rows on the changed lines
  'hub-title-missing': ['Settings.lua', `    p.title:SetText(hosted and "" or title)`, `    p.title:SetText("")`],
  'hub-banner-missing': ['Settings.lua', `if #notices > 0 and not hosted then placeText(p.banner, table.concat(notices`, `if false then placeText(p.banner, table.concat(notices`],
  'saveas-model-label': ['Settings.lua', `text = "Save as " .. TAB_TEXT[key],
            enabled = locked == nil and not running }`, `text = TAB_TEXT[key],
            enabled = locked == nil and not running }`],
  'saveas-model-never-greyed': ['Settings.lua', `text = "Save as " .. TAB_TEXT[key],
            enabled = locked == nil and not running }`, `text = "Save as " .. TAB_TEXT[key],
            enabled = true }`],
  'tests-page-everywhere': ['Settings.lua', `    if view.page == "results" and not hosted then
        local page = view.resultsPage`, `    if not hosted then
        local page = view.resultsPage`],
  'tests-buttons-not-hidden': ['Settings.lua', `    if view.page ~= "home" then
        for _, button in ipairs(p.testButtons) do button:Hide() end`, `    if false then
        for _, button in ipairs(p.testButtons) do button:Hide() end`],
  'page-selected-wrong': ['Settings.lua', `selected = page.key == view.page,
            enabled = not running`, `selected = false,
            enabled = not running`],
  'page-default-wrong': ['Settings.lua', `(known and st.page or "home")`, `(known and st.page or "light")`],
  'page-bogus-accepted': ['Settings.lua', `local known = PAGE_KEYS[st.page] or (advancedOn and ADVANCED_PAGE[st.page])`, `local known = st.page`],
  'page-click-ignored': ['Settings.lua', `        if known and not (running and pageKey ~= "test") then`, `        if false then`],
  'page-click-bogus': ['Settings.lua', `local known = PAGE_KEYS[pageKey] or (ADVANCED_PAGE[pageKey] and fsdb and fsdb.advanced == true)`, `local known = pageKey`],
  'page-click-locked': ['Settings.lua', `        if known and not (running and pageKey ~= "test") then`, `        if known and not InCombatLockdown() and not (running and pageKey ~= "test") then`],
  'ed-pill-colour': ['Settings.lua', `color = PROFILE_COLOR[ctx.active] or "dim" }`, `color = "dim" }`],
  'ed-frame-edit-enabled': ['Settings.lua', `            button:SetEnabled(spec.enabled)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", p.area, "TOPLEFT", (i - 1) * (EDIT_W`, `            button:SetEnabled(true)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", p.area, "TOPLEFT", (i - 1) * (EDIT_W`],
  'pg-running-not-forced': ['Settings.lua', `view.page = running and "test" or (known and st.page or "home")`, `view.page = known and st.page or "home"`],
  'pg-running-pages-live': ['Settings.lua', `enabled = not running or page.key == "test" }`, `enabled = true }`],
  'pg-running-savebar-live': ['Settings.lua', `            enabled = locked == nil and not running }
    end`, `            enabled = locked == nil }
    end`],
  'pg-running-click-moves': ['Settings.lua', `        if known and not (running and pageKey ~= "test") then`, `        if known then`],
  'pg-open-not-kept': ['Settings.lua', `    if ns.guide and ns.guide.running and ns.guide.running() then state.page = "test" end`, `    local _ = ns.guide`],
  'pg-escape-kept': ['Settings.lua', `    if not view.running then tinsert(UISpecialFrames, FRAME_NAME) end`, `    tinsert(UISpecialFrames, FRAME_NAME)`],
  'pg-escape-not-restored': ['Settings.lua', `    if not view.running then tinsert(UISpecialFrames, FRAME_NAME) end`, `    local _ = view.running`],
  'pg-onhide-closes': ['Settings.lua', `        if ns.guide and ns.guide.running and ns.guide.running() then
            self:Show()`, `        if false then
            self:Show()`],
  'pg-endoffer-missing': ['Settings.lua', `        if ns.results and ns.results.endOffer then ns.results.endOffer() end`, `        local _ = ns.results`],
  'pg-host-wrong-page': ['Settings.lua', `        if hosted and key == view.page then`, `        if hosted then`],
  'pg-host-not-drawn': ['Settings.lua', `local ok, err = pcall(owner.renderPage, host)`, `local ok, err = true, nil`],
  'pg-title-on-host': ['Settings.lua', `    p.title:SetText(hosted and "" or title)`, `    p.title:SetText(title)`],
  'pg-banner-on-host': ['Settings.lua', `if #notices > 0 and not hosted then placeText(p.banner`, `if #notices > 0 then placeText(p.banner`],
  'pg-test-chooser-missing': ['Settings.lua', `    if view.page == "test" and not hosted then
        placeText(p.testsIntro`, `    if false then
        placeText(p.testsIntro`],
  'pg-test-chooser-on-host': ['Settings.lua', `    if view.page == "test" and not hosted then
        placeText(p.testsIntro`, `    if view.page == "test" then
        placeText(p.testsIntro`],
  'pg-run-key-wrong': ['Settings.lua', `{ key = "run:setup", text = "Find my best settings"`, `{ key = "run:crowd", text = "Find my best settings"`],
  'pg-run-never-greyed': ['Settings.lua', `{ key = "run:setup", text = "Find my best settings", enabled = locked == nil and not running },`, `{ key = "run:setup", text = "Find my best settings", enabled = true },`],
  'pg-run-click-ignored': ['Settings.lua', `if (runKey == "setup" or runKey == "crowd") and ns.guide and ns.guide.open then ns.guide.open(runKey) end`, `local _ = runKey`],
  'pg-results-none-missing': ['Settings.lua', `    if not any then view.resultsPage.none = NO_RESULTS end`, `    local _ = any`],
  'pg-results-none-always': ['Settings.lua', `    if not any then view.resultsPage.none = NO_RESULTS end`, `    view.resultsPage.none = NO_RESULTS`],
  'pg-go-test-key': ['Settings.lua', `p.goTest.key = "page:test"`, `p.goTest.key = "page:home"`],
  'pg-test-hides-window': ['Settings.lua', `ns.ui.openSaved then ns.ui.openSaved(testKey) end`, `ns.ui.openSaved then ns.ui.openSaved(testKey) settings.hide() end`],
  'pg-show-hides-window': ['Settings.lua', `if info.results[showKey] and ns.ui and ns.ui.openSaved then ns.ui.openSaved(showKey) end`, `if info.results[showKey] and ns.ui and ns.ui.openSaved then ns.ui.openSaved(showKey) settings.hide() end`],
  'pg-host-width': ['Settings.lua', `        host:SetSize(AREA_W, PAGE_H - TOP - SUMMARY_BOTTOM)`, `        host:SetSize(AREA_W + 3, PAGE_H - TOP - SUMMARY_BOTTOM)`],
  // The guided test as a page of My settings (spec 2026-11-03-tests-and-results-in-my-settings-design.md M2); the first five
  // re-anchor older rows on the page code
  'ui-box-click-ignored': ['Guide.lua', `p.box:SetScript("OnClick", function(self) guide.setTicked(self:GetChecked() and true or false) end)`, `p.box:SetScript("OnClick", function() end)`],
  'ui-box-state-not-pushed': ['Guide.lua', `        p.box:SetChecked(view.checkbox.checked)`, `        local _ = view.checkbox.checked`],
  'ui-hide-ignored': ['Guide.lua', `local function dismiss()
    state = nil`, `local function dismiss()
    local _ = state`],
  'report-click-keeps-window': ['Guide.lua', `        ns.ui.showReport(state.entry)    -- the report window`, `        local entry = state.entry dismiss() ns.ui.showReport(entry)    -- the report window`],
  'gp-onhide-closes': ['Settings.lua', `        if ns.guide and ns.guide.running and ns.guide.running() then
            self:Show()`, `        if false then
            self:Show()`],
  'gp-show-not-opening': ['Guide.lua', `    if ns.settings and ns.settings.open then ns.settings.open("test") end`, `    local _ = ns.settings`],
  'gp-render-not-redrawing': ['Guide.lua', `    if ns.settings and ns.settings.redraw then ns.settings.redraw() end`, `    local _ = ns.settings`],
  'gp-has-view-always': ['Guide.lua', `function guide.hasView()
    return state ~= nil`, `function guide.hasView()
    return true`],
  'gp-target-not-selected': ['Guide.lua', `            button:SetSelected(view.targets.selected == view.targets.list[i])`, `            button:SetSelected(false)`],
  'gp-mode-not-selected': ['Guide.lua', `            button:SetSelected(view.modes.selected == spec.key)`, `            button:SetSelected(false)`],
  'gp-buttons-left': ['Guide.lua', `button:SetPoint("BOTTOMRIGHT", into, "BOTTOMRIGHT", -(count - i) * (BUTTON_W + BUTTON_GAP), 0)`, `button:SetPoint("BOTTOMLEFT", into, "BOTTOMLEFT", 0, 0)`],
  'gp-stock-target': ['Guide.lua', `        local button = skin.button(into, tostring(n), TARGET_W, ROW_H)`, `        local button = CreateFrame("Button", nil, into, "UIPanelButtonTemplate")
        button:SetText(tostring(n))
        button.SetSelected, button.SetLabel = function() end, function(self, t) self:SetText(t) end`],
  'gp-running-any-view': ['Guide.lua', `function guide.running()
    return state ~= nil and state.view == "running"`, `function guide.running()
    return state ~= nil`],
  // The results as a page of My settings, with picks (spec 2026-11-03-tests-and-results-in-my-settings-design.md M3, M5); the
  // first nineteen re-anchor older rows on the page code
  'apply-passes-all-values': ['Results.lua', `for _, change in ipairs(current.view.changes) do values[change.cvar] = change.to end`, `for _, s in ipairs(current.view.settings) do values[s.cvar] = s.chosen end`],
  'draw-error-rethrown': ['Results.lua', `    local ok, err = pcall(draw)
    if not ok then fail(err) end`, `    local ok, err = pcall(draw)
    if not ok then error(err) end`],
  'hide-keeps-offer': ['Results.lua', `function results.endOffer()
    current = nil`, `function results.endOffer()
    local _ = current`],
  'after-bar-ignores-measured': ['Results.lua', `    current.model = ns.recommend.chartModel(current.view, current.verify)`, `    current.model = ns.recommend.chartModel(current.view)`],
  'results-third-button-missing': ['Results.lua', `    for i = 1, 4 do
        local button = skin.button(into, "", 120, 26)`, `    for i = 1, 2 do
        local button = skin.button(into, "", 120, 26)`],
  'results-w2-scroll-back': ['Results.lua', `    p.panel = CreateFrame("Frame", nil, into)`, `    p.panel = CreateFrame("ScrollFrame", nil, into)`],
  'results-w2-list-reversed': ['Results.lua', `        list[#list + 1] = { cvar = g.cvar, name = g.name, changed = g.changed, graph = g, picked = picked }`, `        table.insert(list, 1, { cvar = g.cvar, name = g.name, changed = g.changed, graph = g, picked = picked })`],
  'results-w2-list-name-from-label': ['Results.lua', `        list[#list + 1] = { cvar = g.cvar, name = g.name, changed = g.changed, graph = g, picked = picked }`, `        list[#list + 1] = { cvar = g.cvar, name = g.cvar, changed = g.changed, graph = g, picked = picked }`],
  'results-w2-select-default-missing': ['Results.lua', `    current.selected = current.model.selected or (first and (first.cvar or first.setting)) or nil`, `    current.selected = (first and (first.cvar or first.setting)) or nil`],
  'results-w2-select-nodata-default-missing': ['Results.lua', `    current.selected = current.model.selected or (first and (first.cvar or first.setting)) or nil`, `    current.selected = current.model.selected`],
  'results-w2-select-highlight-missing': ['Results.lua', `        row:SetSelected(item.cvar == open)`, `        row:SetSelected(false)`],
  'results-w2-graph-not-drawn': ['Results.lua', `        p.graph:draw(GRAPH_RECT, chosen.graph, m.axis,
            { onPick = onPick, pickColor = profileOf(current.result) == "crowded" and "crowded" or "everyday" })`, `        local _ = m.axis`],
  'results-w2-paragraph-overflow-kept': ['Results.lua', `        if y + h > panelY - 4 then`, `        if false then`],
  'save-changes-not-handed-over': ['Results.lua', `    if current.model.saveKind == "changes" then
        for _, change in ipairs(current.view.changes)`, `    if false then
        for _, change in ipairs(current.view.changes)`],
  'fix-change-lines-no-fit-rule': ['Results.lua', `        if right + h > panelY - 4 then`, `        if false then`],
  'fix-notice-over-buttons': ['Results.lua', `p.notice:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CHART_X, 34)`, `p.notice:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CHART_X, 26)`],
  'fix-button-widths-old': ['Results.lua', `local BUTTON_WIDTHS = { apply = 250, reset = 190, again = 120, later = 90 }`, `local BUTTON_WIDTHS = { apply = 210, reset = 190, again = 210, later = 210 }`],
  'fix-button-gap-wrong': ['Results.lua', `local BUTTON_GAP = 8`, `local BUTTON_GAP = 0`],
  'rp-pick-in-combat': ['Results.lua', `    if not current or refusal() then return end
    current.picks[cvar] = value`, `    if not current then return end
    current.picks[cvar] = value`],
  'rp-pick-keeps-saved': ['Results.lua', `    current.picks[cvar] = value
    current.saved, current.notice = nil, nil`, `    current.picks[cvar] = value`],
  'rp-reset-missing': ['Results.lua', `    if key == "reset" then
        current.picks = {}`, `    if key == "reset" then
        local _ = current.picks`],
  'rp-reset-shown-always': ['Results.lua', `if (m.picked or 0) > 0 then specs[#specs + 1] = { key = "reset"`, `if true then specs[#specs + 1] = { key = "reset"`],
  'rp-onpick-in-combat': ['Results.lua', `local onPick = refusal() == nil and function(value) results.pick(cvar, value) end or nil`, `local onPick = function(value) results.pick(cvar, value) end`],
  'rp-pick-colour-ignored': ['Results.lua', `pickColor = profileOf(current.result) == "crowded" and "crowded" or "everyday" })`, `pickColor = "everyday" })`],
  'rp-show-not-opening': ['Results.lua', `        if ns.settings and ns.settings.open then ns.settings.open("results") end`, `        local _ = ns.settings`],
  'rp-close-keeps-offer': ['Results.lua', `function results.hide()
    current = nil`, `function results.hide()
    local _ = current`],
  'rp-again-keeps-offer': ['Results.lua', `        local kind = current.extras and current.extras.again
        results.hide()`, `        local kind = current.extras and current.extras.again`],
  'rp-has-offer-always': ['Results.lua', `function results.hasOffer()
    return current ~= nil`, `function results.hasOffer()
    return true`],
  'rp-picks-not-applied': ['Results.lua', `    current.view = ns.recommend.withPicks(current.result, current.picks)`, `    current.view = ns.recommend.withPicks(current.result, {})`],
  // The fix pass after the fresh review of the pages; the first nine re-anchor rows on lines the fixes changed
  'skin-state-disabled': ['Skin.lua', `    if not b:IsEnabled() then
        text = "textDisabled"`, `    if not b:IsEnabled() then
        text = "text"`],
  'ui-refresh-off': ['Settings.lua', `            if ns.guide.refresh then guarded(ns.guide.refresh) end`, `            local _ = ns.guide`],
  'ui-refresh-every-frame': ['Settings.lua', `        if sinceRefresh < REFRESH then return end
        sinceRefresh = 0
        -- While a test runs`, `        sinceRefresh = 0
        -- While a test runs`],
  'ui-foreign-running-stays': ['Guide.lua', `    if ns.bench and not ns.bench.active() then
        state = nil
        draw()`, `    if false then
        state = nil
        draw()`],
  'gp-refresh-not-redrawing': ['Guide.lua', `    if host and host:IsShown() then guide.renderPage(host) end       -- only this page while the test measures`, `    local _ = host`],
  'results-text-raw': ['Results.lua', `        row.label:SetText(item.name)
        local profileColor`, `        row.label:SetText(item.cvar)
        local profileColor`],
  'results-w2-list-unmeasured-white': ['Results.lua', `(item.graph and "bright" or "dim")`, `"bright"`],
  'rp-pick-row-colour': ['Results.lua', `item.picked and profileColor or (item.graph and "bright" or "dim")`, `(item.graph and "bright" or "dim")`],
  'fx-save-picked-missing': ['Results.lua', `        if s.picked then values[s.cvar] = s.chosen end`, `        local _ = s`],
  'fx-reset-keeps-saved': ['Results.lua', `        current.picks = {}
        current.saved, current.notice = nil, nil`, `        current.picks = {}`],
  'fx-row-wraps': ['Results.lua', `    row.label:SetWordWrap(false)`, `    local _ = row`],
  'fx-row-disabled-look': ['Skin.lua', `    if row.IsEnabled and not row:IsEnabled() then`, `    if false then`],
  'fx-row-enable-repaint': ['Skin.lua', `        setEnabled(self, on)
        paintRow(self)
    end`, `        setEnabled(self, on)
    end`],
  'fx-running-full-redraw': ['Settings.lua', `        if ns.guide and ns.guide.running and ns.guide.running() then
            if ns.guide.refresh then guarded(ns.guide.refresh) end
            return
        end`, `        if ns.guide and ns.guide.refresh then guarded(ns.guide.refresh) end`],
  'fx-refresh-full-draw': ['Guide.lua', `    if host and host:IsShown() then guide.renderPage(host) end       -- only this page while the test measures`, `    draw()`],
  'fx-close-keeps-view': ['Settings.lua', `        if ns.guide and ns.guide.hide then ns.guide.hide() end`, `        local _ = ns.guide`],
  // The fixes after the owner's in-game look (2026-11-03); the first six re-anchor rows on the changed lines
  'target-line-at-now': ['Results.lua', `bar(p.texMain, COLORS.target, CHART_X + h.target.fraction * CHART_WIDTH, y - 3, 2, 14 + 6)`, `bar(p.texMain, COLORS.target, CHART_X + h.now.fraction * CHART_WIDTH, y - 3, 2, 14 + 6)`],
  'graph-draw-tag-wrong-point': ['Graph.lua', `                elseif p.recommended then
                    tag("recommended"`, `                elseif p.current then
                    tag("recommended"`],
  'graph-draw-tag-too-high': ['Graph.lua', `tag("recommended", item.x, item.y - TAG_RISE, rect, p.picked and pickedColor or COLORS.recommended)`, `tag("recommended", item.x, item.y - 28, rect, p.picked and pickedColor or COLORS.recommended)`],
  'graph-draw-now-tag-too-high': ['Graph.lua', `tag("now", item.x, item.y - TAG_RISE, rect, COLORS.ring)`, `tag("now", item.x, item.y - 28, rect, COLORS.ring)`],
  'gr-pick-tag-missing': ['Graph.lua', `tag("your pick", item.x, item.y - TAG_RISE, rect, pickedColor)`, `local _ = pickedColor`],
  'fx-tag-overlap': ['Graph.lua', `                if p.current and p.picked then
                    tag("now, your pick"`, `                if false then
                    tag("now, your pick"`],
  'ig-target-through-labels': ['Results.lua', `            bar(p.texMain, COLORS.target, CHART_X + h.target.fraction * CHART_WIDTH, y - 3, 2, 14 + 6)`, `            bar(p.texMain, COLORS.target, CHART_X + h.target.fraction * CHART_WIDTH, y - 19, 2, 14 + 22)`],
  'ig-target-once': ['Results.lua', `            barTops[#barTops + 1] = left`, `            if #barTops == 0 then barTops[1] = left end`],
  'ig-tag-narrow': ['Graph.lua', `["recommended"] = 110`, `["recommended"] = 70`],
  'ig-tag-not-centred': ['Graph.lua', `        strings.items[strings.used]:SetJustifyH("CENTER")`, `        local _ = strings`],
  'ig-tag-off-the-edge': ['Graph.lua', `local x = math.max(rect.x, math.min(cx - w / 2, rect.x + rect.width - w))`, `local x = cx - w / 2`],
  'ig-labels-stay-centred': ['Graph.lua', `        fs:SetJustifyH("LEFT")                   -- the strings are pooled`, `        local _ = fs                   -- the strings are pooled`],
  'ig-check-blames-alt-tab': ['Guide.lua', `["control did not respond"] = { "Graphics settings make no difference to the frame rate here.",`, `["control did not respond"] = { "The test could not tell the settings apart here.",`],
  'ig-hint-missing': ['Results.lua', `        if onPick then put(p.fsPanel, PICK_HINT, 0, sy, PANEL_WIDTH) end`, `        local _ = PICK_HINT`],
  'ig-hint-in-combat': ['Results.lua', `        if onPick then put(p.fsPanel, PICK_HINT, 0, sy, PANEL_WIDTH) end`, `        put(p.fsPanel, PICK_HINT, 0, sy, PANEL_WIDTH)`],
  // The opening check lowers every measured setting at once (owner's report 2026-11-03)
  'ctl-renderscale-only': ['Bench.lua', `            value = cheaperTier(entry, current[entry.cvar])`, `            value = nil`],
  'ctl-renderscale-unchanged': ['Bench.lua', `if now then value = string.format("%.4g", now * K.CONTROL_FACTOR) end`, `if now then value = string.format("%.4g", now) end`],
  'ctl-empty-not-nil': ['Bench.lua', `    if #changes == 0 then return nil end`, `    if false then return nil end`],
  'ctl-not-restored': ['Bench.lua', `                pcall(restore.putBack, originals)
                if not c1.ok then return abort(c1.reason) end`, `                if not c1.ok then return abort(c1.reason) end`],
  'ctl-refusal-stops': ['Bench.lua', `    if #before == 0 then return nil, refused end`, `    if #refused > 0 then return nil, refused end`],
  'ctl-check-words': ['Bench.lua', `ns.say(string.format("control (%s): frame time dropped %.1f%%: ok", control.label, drop * 100))`, `ns.say(string.format("control: frame time dropped %.1f%%: ok", drop * 100))`],
  // A click on the recommended point marks it (owner's look 2026-11-03)
  'gd-recommended-not-marked': ['Recommend.lua', `copy.chosen, copy.picked = copy.recommended, true`, `copy.chosen = copy.recommended`],
  'gd-recommended-not-marked-page': ['Recommend.lua', `copy.chosen, copy.picked = copy.recommended, true`, `copy.chosen = copy.recommended`],
  'gd-recommended-counted': ['Recommend.lua', `copy.chosen, copy.picked = copy.recommended, true`, `copy.chosen, copy.picked = copy.recommended, true; view.picked = view.picked + 1`],
  'gd-recommended-counted-page': ['Recommend.lua', `copy.chosen, copy.picked = copy.recommended, true`, `copy.chosen, copy.picked = copy.recommended, true; view.picked = view.picked + 1`],
  'gd-tag-not-pick-colour': ['Graph.lua', `rect, p.picked and pickedColor or COLORS.recommended)`, `rect, COLORS.recommended)`],
  'gd-tag-says-your-pick': ['Graph.lua', `                elseif p.recommended then
                    tag("recommended"`, `                elseif p.recommended and not p.picked then
                    tag("recommended"`],
  // The Everyday | Crowded rocker replaces the profile pill (spec 2026-11-03-advanced-page-title-switch-and-menu-design.md A5)
  'rk-lit-wrong': ['Settings.lua', `view.rocker = { lit = editing, enabled = locked == nil and not running }`, `view.rocker = { lit = "everyday", enabled = locked == nil and not running }`],
  'rk-other-missing': ['Settings.lua', `if not editing then view.rocker.other = { text = view.profile.text, color = view.profile.color } end`, `if false then view.rocker.other = { text = view.profile.text, color = view.profile.color } end`],
  'rk-enabled-in-combat': ['Settings.lua', `view.rocker = { lit = editing, enabled = locked == nil and not running }`, `view.rocker = { lit = editing, enabled = not running }`],
  'rk-click-not-switching': ['Settings.lua', `local editKey = key:match("^edit:(.+)$") or key:match("^rocker:(.+)$")`, `local editKey = key:match("^edit:(.+)$")`],
  'rk-click-while-running': ['Settings.lua', `    if running and key:find("^rocker:") then return end`, ``],
  'rk-anchor': ['Settings.lua', `rocker:SetPoint("RIGHT", f.close, "LEFT", -8, 0)`, `rocker:SetPoint("RIGHT", f.close, "LEFT", -4, 0)`],
  'rk-keys-swapped': ['Settings.lua', `rocker.left.key, rocker.right.key = "rocker:everyday", "rocker:crowded"`, `rocker.left.key, rocker.right.key = "rocker:crowded", "rocker:everyday"`],
  'rk-render-lit-swapped': ['Settings.lua', `rocker.lit == "everyday" and "left" or rocker.lit == "crowded" and "right" or nil`, `rocker.lit == "everyday" and "right" or rocker.lit == "crowded" and "left" or nil`],
  'rk-render-always-enabled': ['Settings.lua', `    p.rocker:SetEnabled(rocker.enabled)`, `    p.rocker:SetEnabled(true)`],
  'rk-other-not-shown': ['Settings.lua', `        p.rockerOther:Show()`, ``],
  'rk-other-text': ['Settings.lua', `p.rockerOther.label:SetText(rocker.other.text)`, `p.rockerOther.label:SetText("Original")`],
  'rk-other-dot': ['Settings.lua', `p.rockerOther.dot:SetColorName(rocker.enabled and rocker.other.color or "textDisabled")`, `p.rockerOther.dot:SetColorName("dim")`],
  'rk-size': ['Settings.lua', `local ROCKER_W, ROCKER_H = 160, 22`, `local ROCKER_W, ROCKER_H = 150, 22`],
  'sk-rocker-lit-colour': ['Skin.lua', `fill, text = rocker.litColor or "accent", "fill"`, `fill, text = "accent", "fill"`],
  'sk-rocker-lit-text': ['Skin.lua', `fill, text = rocker.litColor or "accent", "fill"`, `fill, text = rocker.litColor or "accent", "bright"`],
  'sk-rocker-disabled-text': ['Skin.lua', `            if not rocker.enabled then text = "textDisabled" end`, ``],
  'sk-rocker-halves-enabled': ['Skin.lua', `        self.left:SetEnabled(self.enabled)`, ``],
  'sk-rocker-half-width': ['Skin.lua', `        b:SetSize(width / 2, height)`, `        b:SetSize(width, height)`],
  'sk-rocker-no-hover': ['Skin.lua', `            elseif rocker.enabled and b.hover then`, `            elseif false then`],
  // The game-menu settings measured since 0.11, and 256 grass (spec 2026-11-03-advanced-page-title-switch-and-menu-design.md A1)
  't2-refused-not-remembered': ['Bench.lua', `                    if isRaw(setting.cvar) then rememberRefused(setting.cvar, value) end`, ``],
  't2-refused-not-filtered': ['Bench.lua', `        if not refused then return row.tiers end`, `        do return row.tiers end`],
  't2-256-missing': ['Bench.lua', `tiers = { "48", "64", "128", "256" }`, `tiers = { "48", "64", "128" }`],
  't2-filtering-tiers': ['Bench.lua', `tiers = { "0", "1", "2", "3", "4", "5" }, confirmed = true },`, `tiers = { "0", "1", "2", "3", "4" }, confirmed = true },`],
  't2-view-row-missing': ['Bench.lua', `    { key = "viewdistance", label = "View distance", cvars = { "graphicsViewDistance" }, confirmed = true },`, ``],
  't2-guard-msaa': ['Bench.lua', `"pbr", "msaa",`, `"pbr",`],
  't2-known-raw': ['ForeverSettings.lua', `    "textureFilteringMode", "ffxAntiAliasingMode", "MSAAQuality",`, `    "textureFilteringMode", "ffxAntiAliasingMode",`],
  't2-raid-view': ['Profiles.lua', `    graphicsViewDistance = "raidGraphicsViewDistance",`, ``],
  't2-managed': ['Profiles.lua', `    "graphicsSpellDensity", "graphicsDepthEffects", "graphicsOutlineMode", "textureFilteringMode", "ffxAntiAliasingMode",`, `    "graphicsSpellDensity", "graphicsDepthEffects", "graphicsOutlineMode", "textureFilteringMode",`],
  't2-page-effects': ['Settings.lua', `{ key = "effects", text = "Effects and smoothing" },`, ``],
  't2-page-effects-not-drawn': ['Settings.lua', `local SETTINGS_PAGE = { light = true, effects = true, world = true, size = true }`, `local SETTINGS_PAGE = { light = true, world = true, size = true }`],
  't2-pageof-view': ['Settings.lua', `    graphicsviewdistance = "world", graphicsenvironmentdetail = "world",`, `    graphicsviewdistance = "light", graphicsenvironmentdetail = "world",`],
  't2-pageof-msaa': ['Settings.lua', `ffxantialiasingmode = "effects", msaaquality = "effects",`, `ffxantialiasingmode = "effects", msaaquality = "light",`],
  't2-nav-gap-wrong': ['Settings.lua', `        if entry.key == "test" then gap = 14 end`, `        if entry.key == "results" then gap = 14 end`],
  't2-ranking-view': ['Recommend.lua', `    graphicsViewDistance = { weight = 8, raise = true },`, ``],
  't2-name-msaa': ['Names.lua', `"Edge smoothing (multisample)", "Smooths jagged edges while`, `"Edge smoothing", "Smooths jagged edges while`],
  // The Advanced catalogue (spec 2026-11-03-advanced-page-title-switch-and-menu-design.md A6)
  'av-entry-case': ['Advanced.lua', `return type(cvar) == "string" and BY_CVAR[cvar:lower()] or nil`, `return type(cvar) == "string" and BY_CVAR[cvar] or nil`],
  'av-available-all': ['Advanced.lua', `        if GetCVar(entry.cvar) ~= nil then list[#list + 1] = entry end`, `        list[#list + 1] = entry`],
  'av-risky-all': ['Advanced.lua', `        if entry.risky then list[#list + 1] = entry end`, `        list[#list + 1] = entry`],
  'av-levelword-missing': ['Advanced.lua', `    return entry.levelWords and entry.levelWords[value] or value`, `    return value`],
  'av-farclip-safe': ['Advanced.lua', `risky = true, safe = "1000", page = "adv-distance" },`, `risky = true, safe = "2000", page = "adv-distance" },`],
  'av-guard-ffx': ['Bench.lua', `    "ffx", "fog", "resample",`, `    "fog", "resample",`],
  'av-known-ffx': ['ForeverSettings.lua', `    "ffxGlow", "ffxDeath", "volumeFogLevel",`, `    "volumeFogLevel",`],
  // The safety net for risky Advanced settings (spec 2026-11-03-advanced-page-title-switch-and-menu-design.md A4)
  'safe-logout-off': ['ForeverSettings.lua', `            if entry and now ~= nil and not same(now, entry.safe) then pcall(SetCVar, entry.cvar, entry.safe) end`, ``],
  'safe-logout-unguarded': ['ForeverSettings.lua', `then pcall(SetCVar, entry.cvar, entry.safe) end`, `then SetCVar(entry.cvar, entry.safe) end`],
  'safe-logout-safe-game-set': ['ForeverSettings.lua', `if entry and now ~= nil and not same(now, entry.safe) then`, `if entry and now ~= nil then`],
  'risky-entry-kept-safe': ['ForeverSettings.lua', `    if entry and entry.risky and not same(value, entry.safe) then return entry end`, `    if entry and entry.risky then return entry end`],
  'risky-entry-any': ['ForeverSettings.lua', `    if entry and entry.risky and not same(value, entry.safe) then return entry end`, `    if entry and not same(value, entry.safe) then return entry end`],
  'shift-risky-off': ['ForeverSettings.lua', `        elseif safeStart and not asked[name:lower()] and riskyEntry(name, value) then`, `        elseif false then`],
  'shift-risky-manual': ['ForeverSettings.lua', `        elseif safeStart and not asked[name:lower()] and riskyEntry(name, value) then`, `        elseif safeStart and riskyEntry(name, value) then`],
  'shift-risky-said-each': ['ForeverSettings.lua', `            if not riskySaid then`, `            if true then`],
  'orig-other-not-recorded': ['Profiles.lua', `    -- As setValue does: a setting Original has no value for (an Advanced one) is recorded there first.
    if db.original.values[cvar] == nil then`, `    if false then`],
  // The Advanced pages and the title-bar switch (spec 2026-11-03-advanced-page-title-switch-and-menu-design.md A2, A3)
  'adv-pages-always': ['Settings.lua', `        if page.key == "about" and advancedOn then`, `        if page.key == "about" then`],
  'adv-page-not-known': ['Settings.lua', `local known = PAGE_KEYS[st.page] or (advancedOn and ADVANCED_PAGE[st.page])`, `local known = PAGE_KEYS[st.page] or ADVANCED_PAGE[st.page]`],
  'adv-accept-skipped': ['Settings.lua', `        else
            state.accepting = true
        end`, `        else
            fsdb.advanced = true
        end`],
  'adv-cancel-turns-on': ['Settings.lua', `        if key == "advanced:cancel" then
            state.accepting = nil`, `        if key == "advanced:cancel" then
            state.accepting, fsdb.advanced = nil, true`],
  'adv-accept-not-saved': ['Settings.lua', `            fsdb.advancedAccepted, fsdb.advanced = true, true`, `            fsdb.advanced = true`],
  'adv-off-keeps-page': ['Settings.lua', `            if ADVANCED_PAGE[state.page] then state.page = "home" end`, ``],
  'adv-switch-not-lit': ['Settings.lua', `    p.advanced:SetSelected(view.advancedSwitch.on)`, `    p.advanced:SetSelected(false)`],
  'adv-tag-missing': ['Settings.lua', `tag = entry.risky and "risky" or nil, levels = {} }`, `tag = nil, levels = {} }`],
  'adv-tag-colour': ['Settings.lua', `            worth:SetTextColor(skin.color(row.tag and "warning" or "dim"))`, `            worth:SetTextColor(skin.color("dim"))`],
  'adv-warning-missing': ['Settings.lua', `        placeText(p.advWarning, view.advanced.warning)`, `        hideText(p.advWarning)`],
  'adv-risky-everywhere': ['Settings.lua', `        if view.advanced.risky[view.page] then placeText(p.advRisky, view.advanced.riskyNote) else hideText(p.advRisky) end`, `        placeText(p.advRisky, view.advanced.riskyNote)`],
  'adv-readonly-off': ['Settings.lua', `    if (onSettings or onAdvanced) and view.readOnly then`, `    if onSettings and view.readOnly then`],
  'adv-cards-enabled': ['Settings.lua', `            enabled = locked == nil and editing ~= nil, noCosts = true,`, `            enabled = true, noCosts = true,`],
  'adv-level-word': ['Settings.lua', `            local text = ns.advanced.levelText(entry, value)`, `            local text = value`],
  'adv-tools-everywhere': ['Settings.lua', `    if lastAdvanced and view.page == lastAdvanced.key then`, `    if onAdvanced then`],
  'adv-raid-always-on': ['Settings.lua', `ns.command("profile raid " .. ((fsdb and fsdb.raidToo) and "off" or "on"))`, `ns.command("profile raid on")`],
  'adv-home-kept-missing': ['Settings.lua', `        if n > 0 then
            view.home.advancedKept`, `        if false then
            view.home.advancedKept`],
  'adv-open-advanced': ['Settings.lua', `    elseif PAGE_KEYS[which] or ADVANCED_PAGE[which] then`, `    elseif PAGE_KEYS[which] then`],
  'adv-page-click': ['Settings.lua', `local known = PAGE_KEYS[pageKey] or (ADVANCED_PAGE[pageKey] and fsdb and fsdb.advanced == true)`, `local known = PAGE_KEYS[pageKey]`],
  'adv-check-not-opened': ['Settings.lua', `        if ns.guide and ns.guide.open then ns.guide.open(key:sub(5)) end`, ``],
  'adv-report-not-shown': ['Settings.lua', `        if last and ns.ui and ns.ui.showReport then ns.ui.showReport(last) end`, ``],
  // The minimap menu since 0.11 (spec 2026-11-03-advanced-page-title-switch-and-menu-design.md A5)
  'mn-stop-always': ['UI.lua', `    if ctx.active then add({ text = "Stop"`, `    if true then add({ text = "Stop"`],
  'mn-stop-never': ['UI.lua', `    if ctx.active then add({ text = "Stop"`, `    if false then add({ text = "Stop"`],
  'mn-profile-enabled-in-combat': ['UI.lua', `    local switchOff = locked or (ctx.inCombat and true or false)`, `    local switchOff = locked`],
  'mn-profile-enabled-while-running': ['UI.lua', `    local switchOff = locked or (ctx.inCombat and true or false)`, `    local switchOff = ctx.inCombat and true or false`],
  'mn-profile-run-wrong': ['UI.lua', `            disabled = switchOff, run = command("profile " .. key) }`, `            disabled = switchOff, run = command("profile everyday") }`],
  'mn-profile-text-raw': ['UI.lua', `        local full = ns.names and ns.names.PROFILE[key] or key`, `        local full = key`],
  'mn-name-full': ['UI.lua', `        return { text = name, kind = "check", hint = hint,`, `        return { text = full, kind = "check", hint = hint,`],
  'mn-hint-not-capitalised': ['UI.lua', `        local hint = about:sub(1, 1):upper() .. about:sub(2)`, `        local hint = about`],
  'mn-max-estimate-missing': ['UI.lua', `if key == "maximum" and type(ctx.maxFps) == "number" then hint = hint .. string.format(" (about %.0f fps)", ctx.maxFps) end`, ``],
  'mn-settings-not-prominent': ['UI.lua', `    add({ text = "Settings", kind = "button", prominent = true, run = function()`, `    add({ text = "Settings", kind = "button", prominent = false, run = function()`],
  'mn-prominent-colour': ['UI.lua', `    if item.prominent then return "|cffffd100" .. item.text .. "|r" end`, ``],
  'mn-check-missing': ['UI.lua', `    return item.done and (CHECK .. item.text) or item.text`, `    return item.text`],
  'mn-check-on-all': ['UI.lua', `    return item.done and (CHECK .. item.text) or item.text`, `    return CHECK .. item.text`],
  'mn-return-hint-missing': ['UI.lua', `hint = "Your own settings, from before the addon changed anything.",`, `hint = nil,`],
  'mn-return-command': ['UI.lua', `        disabled = switchOff, run = command("profile original") })`, `        disabled = switchOff, run = command("reset") })`],
  'mn-new-check-hint-missing': ['UI.lua', `                addHint(element, item)
                if item.disabled then disable(element) end
            elseif kind == "submenu" then`, `                if item.disabled then disable(element) end
            elseif kind == "submenu" then`],
  'mn-new-button-hint-missing': ['UI.lua', `                local element = parent:CreateButton(shownText(item), item.run)
                addHint(element, item)`, `                local element = parent:CreateButton(shownText(item), item.run)`],
  'mn-new-hint-title': ['UI.lua', `        tooltip:SetText(item.text)`, `        tooltip:SetText("")`],
  'mn-old-hint-missing': ['UI.lua', `                if item.hint then info.tooltipTitle, info.tooltipText, info.tooltipOnButton = item.text, item.hint, true end`, ``],
  'adv-raid-note-always': ['Settings.lua', `        if tools.raidOff then placeText(p.advRaidOff, tools.raidOff, 22) else hideText(p.advRaidOff) end`, `        placeText(p.advRaidOff, RAID_SWITCH_OFF, 22)`],
  // The fix pass after the fresh review of 2026-11-03
  'fx-asked-not-passed': ['Profiles.lua', `    ns.applyAll(true, silent, { [cvar:lower()] = true })`, `    ns.applyAll(true, silent)`],
  'fx-asked-opens-all': ['ForeverSettings.lua', `        elseif safeStart and not asked[name:lower()] and riskyEntry(name, value) then`, `        elseif safeStart and not next(asked) and riskyEntry(name, value) then`],
  'fx-unset-risky-left': ['Profiles.lua', `        if now ~= nil and not sameValue(now, back) then pcall(SetCVar, cvar, back) end`, ``],
  'fx-unset-not-original': ['Profiles.lua', `        local back = db.original.values[cvar] or entry.safe`, `        local back = entry.safe`],
  'fx-unset-any-advanced': ['Profiles.lua', `    if entry and entry.risky then
        local back`, `    if entry then
        local back`],
  'fx-spelling-catalogue': ['ForeverSettings.lua', `        if entry.cvar:lower() == lower then return entry.cvar end`, ``],
  'fx-clamp-kept': ['Settings.lua', `            ns.profiles.unsetProfileValue(profile, pickedCvar, true)`, ``],
  'fx-clamp-silent': ['Settings.lua', `            state.notice = "The game turned " .. entry.name`, `            local _ = "The game turned " .. entry.name`],
  // A refused Advanced level: clearer words and not offered again (owner's look 2026-11-03)
  'cl-refused-not-hidden': ['Settings.lua', `            if not refused[value] then
                local text = ns.advanced.levelText(entry, value)`, `            if true then
                local text = ns.advanced.levelText(entry, value)`],
  'cl-refused-not-saved': ['Settings.lua', `            fsdb.advancedRefused[key][value] = true`, ``],
  'cl-refused-not-read': ['Settings.lua', `        refused = fsdb and fsdb.advancedRefused or {} }`, `        refused = {} }`],
  'cl-own-words-always': ['Settings.lua', `            if entry.risky and own ~= nil and sameValue(now, own) then where`, `            if true then where`],
  'cl-own-words-never': ['Settings.lua', `            if entry.risky and own ~= nil and sameValue(now, own) then where`, `            if false then where`],
  'cl-now-not-read': ['Settings.lua', `            local now = GetCVar(pickedCvar) or held`, `            local now = held`],
};

function main() {
  const [pkgDir, srcDir, testPath, mutation] = process.argv.slice(2);
  if (!pkgDir || !srcDir || !testPath) {
    throw new Error('usage: node run.js <fengari-pkg-dir> <src-dir> <test.lua> [mutation]');
  }
  const { lua, lauxlib, lualib, to_luastring, to_jsstring } =
    require(path.join(path.resolve(pkgDir), 'node_modules', 'fengari'));

  const read = (file) => (fs.existsSync(path.join(srcDir, file)) ? fs.readFileSync(path.join(srcDir, file), 'utf8') : '');
  const sources = { 'ForeverSettings.lua': read('ForeverSettings.lua'), 'Bench.lua': read('Bench.lua'), 'Profiles.lua': read('Profiles.lua'), 'UI.lua': read('UI.lua'), 'Guide.lua': read('Guide.lua'), 'Recommend.lua': read('Recommend.lua'), 'Results.lua': read('Results.lua'), 'Names.lua': read('Names.lua'), 'Settings.lua': read('Settings.lua'), 'Graph.lua': read('Graph.lua'), 'Skin.lua': read('Skin.lua'), 'Advanced.lua': read('Advanced.lua') };
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
  setGlobal('SKIN_SRC', sources['Skin.lua']);
  setGlobal('SETTINGS_SRC', sources['Settings.lua']);
  setGlobal('GRAPH_SRC', sources['Graph.lua']);
  setGlobal('ADVANCED_SRC', sources['Advanced.lua']);
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
