-- SpawnCamp tracker: spawn and death sightings, respawn stats and alarms.
--
-- The addon only knows what it sees: watched mobs on nameplates, your target
-- and your mouseover, checked a few times a second, plus sightings other
-- SpawnCamp users in your group or guild send. A death is logged when a seen
-- unit is dead; a spawn when it's seen alive with a spawn UID (from its GUID)
-- that wasn't seen before, or after a logged death when the GUID is unreadable.
--
-- Events: { k = "A" (alive) | "D" (dead), t = server time, s = spawn UID or nil,
--           src = "you" | sender, approx = found already dead, mine = your kill }
-- A respawn interval is a death followed by the next spawn.

local ADDON, SC = ...

local MAX_EVENTS = 300
local PREFIX = "SpawnCamp"

local plates = {}   -- active nameplate unit tokens

------------------------------------------------------------------------------
-- Logging
------------------------------------------------------------------------------

local function Insert(events, e)
    local i = #events
    while i >= 1 and events[i].t > e.t do i = i - 1 end
    table.insert(events, i + 1, e)
    while #events > MAX_EVENTS do table.remove(events, 1) end
end

local function Last(events, kind)
    for i = #events, 1, -1 do
        if not kind or events[i].k == kind then return events[i], i end
    end
end

-- Returns the new event, or nil when it repeats one already logged.
function SC.Observe(name, kind, spawn, t, src, extra)
    if not SC.db then return end
    extra = extra or {}
    t = t or GetServerTime()
    src = src or "you"
    local mob = SC.char.mobs[name]
    local events = SC.History(name).events
    local last = events[#events]
    if kind == "A" and src == "you" and last and last.k == "A" then last.seen = t end

    -- Synced sightings may land out of order; skip any that match one we have.
    for i = #events, math.max(1, #events - 10), -1 do
        local e = events[i]
        if e.k == kind and ((spawn and e.s == spawn) or math.abs(e.t - t) < 30) then
            if kind == "D" and e.approx and not extra.approx and t <= e.t then
                -- An exact time beats a "found dead" one.
                e.t, e.approx, e.src = t, nil, src
            end
            if extra.mine then e.mine = true end
            return nil
        end
    end

    if kind == "A" and last and last.k == "A" and not extra.manual then
        -- Still the same spawn when the UID matches or can't be read.
        if not spawn or not last.s or last.s == spawn then return nil end
    end
    if kind == "D" and last and last.k == "D" and not extra.manual then
        if not spawn or not last.s or last.s == spawn then return nil end
    end

    local e = { k = kind, t = t, s = spawn, src = src,
                approx = extra.approx or nil, mine = extra.mine or nil,
                manual = extra.manual or nil }
    Insert(events, e)

    if src == "you" then SC.Share(name, e) end

    -- Alerts only for the targets in the main window. Recent, Nearby and Auto
    -- Quest mobs just log.
    if mob and mob.hunting and SC.IsActive(name) then
        if kind == "A" and SC.char.alertSpawn and events[#events] == e then
            SC.Alert(name .. " is up!" .. (src ~= "you" and (" (seen by " .. src .. ")") or ""))
        end
        if kind == "D" and e.mine and mob.mode ~= "interact" and mob.keep then
            -- "Keep" ticked: stays the target and on the key.
            SC.Alert("You got " .. name .. "!")
        elseif kind == "D" and e.mine and mob.mode ~= "interact" then
            mob.hunting = false
            local slot = SC.SlotOf(name)
            if slot then
                SC.SetActive(nil, slot)
                SC.Print("cleared " .. name .. " as a target. Pick it from Recent to camp it again, or tick Keep to hold it.")
            end
            SC.ApplyBindings()
            SC.Alert("You got " .. name .. "!")
        end
    end
    SC.Refresh()
    return e
end

function SC.DeleteEvent(name, index)
    local events = SC.History(name).events
    table.remove(events, index)
    SC.Refresh()
end

------------------------------------------------------------------------------
-- Stats
------------------------------------------------------------------------------

-- Respawn intervals in seconds: each death to the next spawn.
function SC.Intervals(name)
    local events = SC.History(name).events
    local out = {}
    for i = 1, #events - 1 do
        local a, b = events[i], events[i + 1]
        if a.k == "D" and b.k == "A" then
            out[#out + 1] = { secs = b.t - a.t, from = i, approx = a.approx }
        end
    end
    return out
end

-- min, avg, max respawn in seconds and how many intervals they came from.
-- The mob's manual minutes override min/max.
function SC.Stats(name)
    local list = SC.Intervals(name)
    local lo, hi, sum = nil, nil, 0
    for _, iv in ipairs(list) do
        lo = (not lo or iv.secs < lo) and iv.secs or lo
        hi = (not hi or iv.secs > hi) and iv.secs or hi
        sum = sum + iv.secs
    end
    local avg = #list > 0 and sum / #list or nil
    local mob = SC.char.mobs[name]
    if mob then
        if (mob.manualMin or 0) > 0 then lo = mob.manualMin * 60 end
        if (mob.manualMax or 0) > 0 then hi = mob.manualMax * 60 end
        if not avg and lo and hi then avg = (lo + hi) / 2 end
        if not avg and lo then avg = lo end
        if lo and hi and hi < lo then hi = lo end
    end
    return lo, avg, hi, #list
end

-- What a mob's line shows. The timer runs from the death and stops when the
-- mob is seen again; that time is the respawn. Returns state, text, fraction
-- (bar fill toward the expected respawn) or nil.
--   "up"      seen alive since its last death
--   "waiting" dead, before the earliest expected respawn
--   "window"  dead, between earliest and latest expected respawn
--   "late"    dead, past the latest expected respawn
--   "dead"    dead, no respawn time known yet
--   "none"    nothing logged
function SC.Status(name)
    local events = SC.History(name).events
    local last = events[#events]
    if not last then return "none", "no sightings yet" end
    local now = GetServerTime()
    if last.k == "A" then
        local prev = events[#events - 1]
        local seen = now - (last.seen or last.t)
        local text = seen < 5 and "UP" or ("up, seen " .. SC.Clock(seen) .. " ago")
        if prev and prev.k == "D" then
            text = text .. ", respawned after " .. SC.Clock(last.t - prev.t) .. (prev.approx and "+" or "")
        end
        return "up", text
    end
    local dead = now - last.t
    local text = "dead " .. SC.Clock(dead) .. (last.approx and "+" or "")
    local lo, avg, hi = SC.Stats(name)
    if not lo then return "dead", text end
    if dead < lo then
        return "waiting", text .. ", earliest in " .. SC.Clock(lo - dead), dead / lo
    end
    if hi and dead <= hi then
        return "window", text .. ", in the respawn window", 1
    end
    return "late", text .. ", past the latest respawn seen", 1
end

-- Countdown to the average respawn, for the big ETA next to the name.
-- Returns big text, small text, colour code.
function SC.ETA(name)
    local events = SC.History(name).events
    local last = events[#events]
    local _, avg = SC.Stats(name)
    local avgText = avg and ("Avg respawn " .. SC.Clock(avg)) or "Avg respawn: not known yet"
    if last and last.k == "A" then return "UP", avgText, "|cff40ff40" end
    if not (last and avg) then return "ETA --:--", avgText, "|cff999999" end
    local left = avg - (GetServerTime() - last.t)
    if left > 0 then return "ETA " .. SC.Clock(left), avgText, "|cffffd100" end
    return "DUE", avgText .. ", " .. SC.Clock(-left) .. " over", "|cffff8040"
end

------------------------------------------------------------------------------
-- Alerts
------------------------------------------------------------------------------

function SC.Alert(text)
    SC.Print("|cffffd100" .. text .. "|r")
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 })
    end
    if SC.char.sound then
        local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
        pcall(PlaySound, kit, "Master")
    end
    if FlashClientIcon then pcall(FlashClientIcon) end
end

-- The quieter alert: a ding and a line in the middle of the screen. Used for
-- timing (early warning, average reached); the spawn alert keeps the raid warning.
function SC.Ding(text)
    SC.Print("|cffffd100" .. text .. "|r")
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, 0.82, 0.2)
    end
    if SC.char.sound then
        local kit = SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081
        pcall(PlaySound, kit, "Master")
    end
end

-- Alarm flags per death event, so each fires once. Session only.
local fired = setmetatable({}, { __mode = "k" })

local function CheckAlarms()
    local now = GetServerTime()
    for _, name in ipairs(SC.char.order) do
        local mob = SC.char.mobs[name]
        if mob and mob.hunting and SC.char.alarm and SC.IsActive(name) then
            local events = SC.History(name).events
            local last = events[#events]
            if last and last.k == "D" then
                local lo, avg = SC.Stats(name)
                if lo then
                    local f = fired[last]
                    if not f then f = {}; fired[last] = f end
                    local ago = now - last.t
                    local lead = SC.char.lead or 0
                    -- Only alarm for deaths inside the expected window plus a margin, so
                    -- logging in to an old death doesn't go off.
                    if not f.pre and lead > 0 and ago >= lo - lead and ago < lo then
                        f.pre = true
                        SC.Ding(name .. " may spawn in " .. SC.Clock(lo - ago))
                    end
                    if not f.open and ago >= lo and ago < lo + 120 then
                        f.open = true
                        SC.Ding(name .. ": respawn window is open")
                    end
                    -- The average respawn time is reached, whether or not it has shown.
                    if avg and not f.avg and ago >= avg and ago < avg + 120 then
                        f.avg = true
                        SC.Ding(name .. " is due (average respawn " .. SC.Clock(avg) .. ")")
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------------
-- Scanning
------------------------------------------------------------------------------

-- Every NPC seen on a nameplate, as target or as mouseover, for the Nearby picker.
-- name -> { t = GetTime() last seen, hostile, level, class = classification }. Session only.
SC.nearby = {}
local NEARBY_KEEP = 180

-- The game's own tooltip for a mob, copied line by line (text and colour) the
-- last time it was in view, so its box can show it when it isn't. Your targets'
-- copies are saved with their history; the rest last the session.
SC.tips = {}

local function TipColor(c)
    if type(c) == "table" then
        local r, g, b = SC.Plain(c.r), SC.Plain(c.g), SC.Plain(c.b)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    return 1, 1, 1
end

function SC.CaptureTip(name, unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return end
    local out = {}
    for _, ln in ipairs(data.lines) do
        local l = SC.Plain(ln.leftText)
        if type(l) == "string" and l ~= "" then
            local e = { l, TipColor(ln.leftColor) }
            local r = SC.Plain(ln.rightText)
            if type(r) == "string" and r ~= "" then
                e[5] = r
                e[6], e[7], e[8] = TipColor(ln.rightColor)
            end
            out[#out + 1] = e
        end
    end
    -- The first line is the mob's name; anything else isn't this mob's tooltip.
    if #out == 0 or out[1][1]:lower() ~= name:lower() then return end
    local tip = { lines = out, t = GetServerTime() }
    SC.tips[name] = tip
    if SC.char.mobs[name] then SC.History(name).tip = tip end
end

-- The saved copy, without creating a history entry.
function SC.TipFor(name)
    if not name then return nil end
    if SC.tips[name] then return SC.tips[name] end
    local r = SpawnCampDB and SpawnCampDB.realms and SpawnCampDB.realms[SC.Realm()]
    return r and r[name] and r[name].tip or nil
end

local function NoteNearby(unit)
    -- Returns what happened, for Scan now's report:
    -- "ok", "none" (no unit), "player", "hidden" (name secret), "other" (pet etc.), "error".
    local ok, res = pcall(function()
        if not SC.MaybeExists(unit) then return "none" end
        if SC.True(UnitIsPlayer(unit)) then return "player" end
        local n = SC.UnitNameSafe(unit)
        if not n then return "hidden" end
        local guid = SC.Plain(UnitGUID(unit))
        -- Skips pets and other non-creatures when the GUID is readable.
        if type(guid) == "string" and not (guid:find("^Creature") or guid:find("^Vehicle")) then return "other" end
        local e = SC.nearby[n] or {}
        e.t = GetTime()
        e.hostile = SC.Bool(UnitCanAttack("player", unit))
        e.level = SC.Plain(UnitLevel(unit))
        e.class = SC.Plain(UnitClassification(unit))
        e.ctype = SC.Plain(UnitCreatureType(unit))
        e.dead = SC.Bool(UnitIsDead(unit))
        -- Quest link from the tooltip, for the Quest pop-out. Throttled per mob.
        if SC.UnitQuest and (not e.qt or e.t - e.qt > 3) then
            e.qt = e.t
            e.quest, e.questObjective = SC.UnitQuest(unit)
        end
        -- Tooltip copy for your targets and Auto Quest mobs, every few seconds.
        if (not e.tt or e.t - e.tt > 3) and (SC.char.mobs[n] or (SC.char.anyQuest and SC.IsQuestWanted(n))) then
            e.tt = e.t
            SC.CaptureTip(n, unit)
        end
        SC.nearby[n] = e
        if SC.MatchPartial then SC.MatchPartial(n) end
        return "ok"
    end)
    if not ok then
        SC.nearbyError = tostring(res)
        return "error"
    end
    return res
end

-- Every unit token worth reading: nameplate1-40 (read directly, so nothing
-- depends on the nameplate events), plus target and mouseover.
local SCAN_UNITS = { "target", "mouseover" }
for i = 1, 40 do SCAN_UNITS[#SCAN_UNITS + 1] = "nameplate" .. i end

-- One full read now; returns a one-line report of what it found and what was blocked.
function SC.ScanNearby()
    local tally = { ok = 0, none = 0, player = 0, hidden = 0, other = 0, error = 0 }
    for _, unit in ipairs(SCAN_UNITS) do
        local r = NoteNearby(unit)
        tally[r] = (tally[r] or 0) + 1
    end
    local parts = { string.format("%d NPC%s read", tally.ok, tally.ok == 1 and "" or "s") }
    if tally.player > 0 then parts[#parts + 1] = tally.player .. " players skipped" end
    if tally.other > 0 then parts[#parts + 1] = tally.other .. " pets/other skipped" end
    if tally.hidden > 0 then parts[#parts + 1] = "|cffff8040" .. tally.hidden .. " with hidden names|r" end
    if tally.error > 0 then parts[#parts + 1] = "|cffff4040" .. tally.error .. " errors: " .. tostring(SC.nearbyError) .. "|r" end
    if tally.ok > 0 then SC.namesHidden = false elseif tally.hidden > 0 then SC.namesHidden = true end
    local seen = 42 - tally.none
    if seen == 0 then parts[#parts + 1] = "no nameplates, target or mouseover" end
    return table.concat(parts, ", "), tally
end

local RANK = { worldboss = 1, rareelite = 2, rare = 3, elite = 4 }

-- Nearby NPC names, rares first, then most recently seen.
function SC.NearbyList()
    local now, out = GetTime(), {}
    for n, e in pairs(SC.nearby) do
        if now - e.t > NEARBY_KEEP then
            SC.nearby[n] = nil
        else
            out[#out + 1] = { name = n, info = e, rank = RANK[e.class or ""] or 9 }
        end
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if math.abs(a.info.t - b.info.t) > 1 then return a.info.t > b.info.t end
        return a.name < b.name
    end)
    return out
end

-- The lock: the key points at the alive, untagged nameplate of the
-- highest-priority mob in view (your targets in list order, then Auto Quest
-- mobs). On a tie the current plate stays, so equal mobs don't hop. A plate
-- that just failed with "not in line of sight" ranks below every mob you can
-- see for a few seconds; it's still used when nothing else is around.
local blocked = {}       -- nameplate token -> GetTime() it ranks low until
SC.blockedPlates = blocked
local BLOCK_SECS = 8
local LOS_PENALTY = 100
local RANGE_PENALTY = 50

-- Is the unit in range of your attack spell? nil when it can't be told
-- (no spell set, custom macro, or the client won't say).
function SC.InRange(unit)
    local A = SC.char and SC.char.attack
    local spell = A and not SC.AttackMacroBody() and A.spell
    if not spell or spell == "" then return nil end
    local f = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    if not f then return nil end
    local ok, r = pcall(f, spell, unit)
    if not ok then return nil end
    r = SC.Plain(r)
    if r == true or r == 1 then return true end
    if r == false or r == 0 then return false end
    return nil
end

local function PlateRank(unit)
    if not SC.MaybeExists(unit) or SC.True(UnitIsPlayer(unit)) then return end
    if SC.Bool(UnitIsDead(unit)) ~= false then return end
    if UnitIsTapDenied and SC.Bool(UnitIsTapDenied(unit)) == true then return end
    local n = SC.UnitNameSafe(unit)
    if not n then return end
    local r = SC.SlotOf(n)
    if not r and SC.char.anyQuest and SC.IsQuestWanted(n) and SC.Bool(UnitCanAttack("player", unit)) ~= false then
        r = SC.MAX_TARGETS + 1
    end
    if not r then return end
    if blocked[unit] and blocked[unit] > GetTime() then r = r + LOS_PENALTY end
    if SC.InRange(unit) == false then r = r + RANGE_PENALTY end
    return r, n
end
SC._PlateRank = PlateRank

function SC.PickLock()
    if not SC.char or SC.inCombat or InCombatLockdown() then return end
    local best, bestRank, bestName
    for i = 1, 40 do
        local u = "nameplate" .. i
        local r, n = PlateRank(u)
        if r and (not bestRank or r < bestRank) then best, bestRank, bestName = u, r, n end
    end
    if SC.fastUnit and bestRank then
        local r, n = PlateRank(SC.fastUnit)
        if r and r <= bestRank then best, bestRank, bestName = SC.fastUnit, r, n end
    end
    if best and bestRank % RANGE_PENALTY > SC.MAX_TARGETS then SC.lastQuestMob = bestName end
    SC.SetFastUnit(best)
end

-- After "not in line of sight" on a key press: the mob you're on ranks below
-- the ones you can see, so the key moves to one of those if there is one.
function SC.BlockTarget()
    local now = GetTime()
    SC.targetBlocked = now + BLOCK_SECS
    for i = 1, 40 do
        local p = "nameplate" .. i
        if SC.MaybeExists(p) and SC.True(UnitIsUnit("target", p)) then blocked[p] = now + BLOCK_SECS end
    end
    SC.PickLock()
    SC.EvalTarget()
end

-- A unit token showing this mob right now, for its tooltip.
function SC.UnitFor(name)
    if not name then return nil end
    local want = name:lower()
    local function is(u)
        local n = SC.MaybeExists(u) and SC.UnitNameSafe(u)
        return n and n:lower() == want
    end
    if is("target") then return "target" end
    if SC.fastUnit and is(SC.fastUnit) then return SC.fastUnit end
    for i = 1, 40 do
        if is("nameplate" .. i) then return "nameplate" .. i end
    end
    if is("mouseover") then return "mouseover" end
end

local function Check(unit)
    NoteNearby(unit)
    local name, mob, dead, spawn, tapDenied = SC.ReadUnit(unit)
    if not name then return end
    if SC.CapturePortrait then SC.CapturePortrait(name, unit) end
    if dead == true then
        local events = SC.History(name).events
        -- Exact when we saw this spawn alive (same UID, or the last event was it alive).
        local last = events[#events]
        local sawAlive = last and last.k == "A" and (not spawn or not last.s or last.s == spawn)
        local mine = tapDenied == false and mob.mode ~= "interact" and sawAlive
        SC.Observe(name, "D", spawn, nil, "you", { approx = not sawAlive, mine = mine })
    elseif dead == false then
        SC.Observe(name, "A", spawn, nil, "you")
    end
end

------------------------------------------------------------------------------
-- Following the mob your key targeted (works with hidden names)
------------------------------------------------------------------------------

-- name -> { viaTarget = still your target, plate = its nameplate token,
--           sawAlive = seen alive while followed }
local follow = {}
SC.follow = follow

local function Died(name, unit)
    local f = follow[name] or {}
    local mob = SC.char.mobs[name]
    local tap = nil
    if UnitIsTapDenied then tap = SC.Bool(UnitIsTapDenied(unit)) end
    local mine = tap == false and f.sawAlive and mob and mob.mode ~= "interact"
    if mob then SC.Observe(name, "D", nil, nil, "you", { approx = not f.sawAlive, mine = mine }) end
    follow[name] = nil
end

-- Right after a key press: a target now is one of the lit mobs (the macro
-- cleared the old one). A readable name says which. With the name hidden,
-- hostile means a sword mob and friendly a bubble mob, which is enough when
-- that side has just one.
local function TakeTarget()
    if not SC.MaybeExists("target") or SC.True(UnitIsPlayer("target")) then return end
    local hostile = SC.Bool(UnitCanAttack("player", "target"))
    if hostile == false then SC.lastPress.interact = GetTime() end
    local mobs
    if hostile == true then
        mobs = SC.MobsIn("attack")
    elseif hostile == false then
        mobs = SC.MobsIn("interact")
    else
        mobs = SC.MobsIn("attack")
        for _, m in ipairs(SC.MobsIn("interact")) do mobs[#mobs + 1] = m end
    end
    if #mobs == 0 then return end
    local n = SC.UnitNameSafe("target")
    local name
    if n then
        for _, m in ipairs(mobs) do
            if m.name:lower() == n:lower() then name = m.name; break end
        end
    elseif #mobs == 1 then
        name = mobs[1].name
    end
    if not name then return end
    for _, m in ipairs(mobs) do
        if m.quest and m.name == name then SC.lastQuestMob = name end
    end
    if SC.CapturePortrait then SC.CapturePortrait(name, "target") end
    local f = follow[name]
    if not f then f = {}; follow[name] = f end
    f.viaTarget = true
    f.plate = nil
    for i = 1, 40 do
        local p = "nameplate" .. i
        if SC.MaybeExists(p) and SC.True(UnitIsUnit("target", p)) then f.plate = p; break end
    end
    local dead = SC.Bool(UnitIsDead("target"))
    if dead == true then
        Died(name, "target")
    elseif dead == false then
        f.sawAlive = true
        if SC.char.mobs[name] then SC.Observe(name, "A", nil, nil, "you") end
    end
end

function SC.OnKeyPressed()
    if not SC.char then return end
    TakeTarget()
    SC.EvalTarget()
    C_Timer.After(0.15, function() pcall(TakeTarget); pcall(SC.EvalTarget) end)
end

local function CheckFollowed()
    for name, f in pairs(follow) do
        local units = {}
        if f.viaTarget then units[#units + 1] = "target" end
        if f.plate then units[#units + 1] = f.plate end
        for _, u in ipairs(units) do
            if SC.MaybeExists(u) then
                local dead = SC.Bool(UnitIsDead(u))
                if dead == true then
                    Died(name, u)
                    break
                elseif dead == false then
                    f.sawAlive = true
                    if SC.char.mobs[name] then SC.Observe(name, "A", nil, nil, "you") end   -- updates "last seen"
                end
            end
        end
    end
end

-- Is your current target the selected mob, alive? Then the key stops touching
-- the target (no swapping while you spam). By name when readable; with hidden
-- names, when the key itself put it there.
function SC.EvalTarget()
    if not SC.char then return end
    local actives = SC.MobsIn("attack")
    for _, m in ipairs(SC.MobsIn("interact")) do actives[#actives + 1] = m end
    -- Leaving the mob needs a plain answer: no target, dead, tagged by someone
    -- else, or a name that isn't one of yours. A dead-or-alive read that comes
    -- back unknown keeps the key where it was, so a flicker can't make it clear
    -- a mob you're on (it also can't put the key on a mob it wasn't on).
    local on, onName = false, nil
    if #actives > 0 and SC.MaybeExists("target") and not SC.True(UnitIsPlayer("target")) then
        local dead = SC.Bool(UnitIsDead("target"))
        local tapped = UnitIsTapDenied and SC.Bool(UnitIsTapDenied("target")) == true
        if dead ~= true and not tapped then
            local n = SC.UnitNameSafe("target")
            for _, m in ipairs(actives) do
                if n then
                    if n:lower() == m.name:lower() then on = true; onName = onName or m.name end
                else
                    local f = follow[m.name]
                    if f and f.viaTarget then on = true; onName = onName or m.name end
                end
            end
            if on and dead == nil and not SC.onMob then on = false end
        end
    end
    -- Never swaps off a mob you're fighting. One you haven't hit yet gives way
    -- only to a DIFFERENT mob that ranks higher (in range and sight when this
    -- one isn't, or higher in the list). Never to itself or another of the
    -- same name: the nameplate-vs-target check can't always tell them apart,
    -- and swapping to "itself" made the key clear and re-take the same mob.
    local fu = SC.fastUnit
    if on and fu and not SC.inCombat and SC.Bool(UnitAffectingCombat("target")) ~= true
        and not SC.True(UnitIsUnit("target", fu)) then
        local fr, fn = PlateRank(fu)
        if fn and onName and fn:lower() ~= onName:lower() then
            local tr = SC.RankOf(onName) or SC.MAX_TARGETS + 2
            if SC.targetBlocked and SC.targetBlocked > GetTime() then tr = tr + LOS_PENALTY end
            if SC.InRange("target") == false then tr = tr + RANGE_PENALTY end
            if fr and fr < tr then on = false end
        end
    end
    SC.SetOnMob(on)
end

SC.On("PLAYER_REGEN_ENABLED", function() SC.EvalTarget() end)

-- Your own target change (not the key's) ends following through the target.
SC.On("PLAYER_TARGET_CHANGED", function()
    local now = GetTime()
    SC.targetBlocked = nil
    for name, f in pairs(follow) do
        if f.viaTarget and now - (SC.lastPress.key or 0) > 0.6 then
            f.viaTarget = nil
            if not f.plate then follow[name] = nil end
        end
    end
    SC.EvalTarget()
end)

-- A followed nameplate going away: dead means it died, alive means out of range.
SC.On("NAME_PLATE_UNIT_REMOVED", function(unit)
    for name, f in pairs(follow) do
        if f.plate == unit then
            if SC.Bool(UnitIsDead(unit)) == true then
                Died(name, unit)
            else
                f.plate = nil
                if not f.viaTarget then follow[name] = nil end
            end
        end
    end
end)

local function Scan()
    if not SC.char then return end
    CheckFollowed()
    SC.EvalTarget()
    for _, unit in ipairs(SCAN_UNITS) do
        if SC.MaybeExists(unit) then Check(unit) end
    end
    for unit in pairs(plates) do
        if not unit:find("^nameplate%d+$") then Check(unit) end
    end
    SC.PickLock()
    SC.EvalTarget()
end

SC.Scan = Scan

-- No combat log: Forever forbids addons from registering
-- COMBAT_LOG_EVENT_UNFILTERED (0.8.0 tried and got the "blocked from an action
-- only available to the Blizzard UI" popup). Deaths come from nameplates,
-- target, mouseover, the key, sharing and the manual buttons.

SC.On("NAME_PLATE_UNIT_ADDED", function(unit)
    plates[unit] = true
    blocked[unit] = nil
    Check(unit)
    SC.PickLock()
end)

-- Nameplates go away when the mob dies; read it once more on the way out.
SC.On("NAME_PLATE_UNIT_REMOVED", function(unit)
    Check(unit)
    plates[unit] = nil
    blocked[unit] = nil
    if SC.fastUnit == unit then SC.SetFastUnit(nil); SC.PickLock() end
end)

SC.On("PLAYER_TARGET_CHANGED", function() Check("target") end)
SC.On("UPDATE_MOUSEOVER_UNIT", function() Check("mouseover") end)

SC.On("PLAYER_LOGIN", function()
    C_Timer.NewTicker(0.3, function()
        local ok, err = pcall(Scan)
        if not ok then SC.Print("|cffff4040scan error|r " .. tostring(err)) end
    end)
    C_Timer.NewTicker(1, function()
        local ok, err = pcall(CheckAlarms)
        if not ok then SC.Print("|cffff4040alarm error|r " .. tostring(err)) end
    end)
end)

------------------------------------------------------------------------------
-- Sharing: "1;<A|D>;<server time>;<spawn uid>;<approx 0/1>;<name>"
------------------------------------------------------------------------------

-- Which addon channels sharing is on for (the Party / Raid / Guild boxes).
local SHARE_FLAG = { PARTY = "shareParty", RAID = "shareRaid", GUILD = "shareGuild" }

local function Channels()
    local out = {}
    local c = SC.char
    if IsInRaid and IsInRaid() then
        if c.shareRaid then out[#out + 1] = "RAID" end
    elseif IsInGroup and IsInGroup() then
        if c.shareParty then out[#out + 1] = "PARTY" end
    end
    if c.shareGuild and IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
    return out
end

function SC.Share(name, e)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local msg = table.concat({ "1", e.k, tostring(e.t), e.s or "", e.approx and "1" or "0", name }, ";")
    if #msg > 255 then return end
    for _, ch in ipairs(Channels()) do
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    end
end

SC.On("PLAYER_LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
end)

SC.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
    if prefix ~= PREFIX or not SC.char then return end
    local flag = SHARE_FLAG[channel]
    if not (flag and SC.char[flag]) then return end
    msg, sender = SC.Plain(msg), SC.Plain(sender)
    if not (msg and sender) then return end
    local me = SC.Plain(UnitName("player"))
    local short = Ambiguate and Ambiguate(sender, "short") or sender
    if short == me then return end
    local ver, kind, t, spawn, approx, name = strsplit(";", msg, 6)
    if ver ~= "1" or (kind ~= "A" and kind ~= "D") or not name then return end
    if not SC.char.mobs[name] then return end   -- only mobs this character watches
    t = tonumber(t)
    if not t or math.abs(GetServerTime() - t) > 6 * 3600 then return end
    SC.Observe(name, kind, spawn ~= "" and spawn or nil, t, short, { approx = approx == "1" })
end)
