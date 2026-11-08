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

    if mob and mob.hunting then
        if kind == "A" and SC.char.alertSpawn and events[#events] == e then
            SC.Alert(name .. " is up!" .. (src ~= "you" and (" (seen by " .. src .. ")") or ""))
        end
        if kind == "D" and e.mine and mob.mode ~= "interact" and mob.keep then
            -- "Keep" ticked: stays the target and on the key.
            SC.Alert("You got " .. name .. "!")
        elseif kind == "D" and e.mine and mob.mode ~= "interact" then
            mob.hunting = false
            if SC.char.active == name then
                SC.char.active = nil
                SC.Print("cleared " .. name .. " as your target, so your key does nothing now. Pick it from Recent to camp it again.")
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
        if mob and mob.hunting and SC.char.alarm then
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
        SC.nearby[n] = e
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

local function Check(unit)
    NoteNearby(unit)
    local name, mob, dead, spawn, tapDenied = SC.ReadUnit(unit)
    if not name then return end
    if SC.CapturePortrait then SC.CapturePortrait(name, unit) end
    -- The target's alive nameplate: point the key straight at it.
    if name == SC.char.active and unit:find("^nameplate%d+$") then
        -- Alive and not tagged by someone else (yours or nobody's is fine).
        if dead == false and tapDenied ~= true then
            SC.SetFastUnit(unit)
        elseif SC.fastUnit == unit then
            SC.SetFastUnit(nil)
        end
    end
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
    SC.Observe(name, "D", nil, nil, "you", { approx = not f.sawAlive, mine = mine })
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
        SC.Observe(name, "A", nil, nil, "you")
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
                    SC.Observe(name, "A", nil, nil, "you")   -- updates "last seen"
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
    local m = SC.Active()
    local on = false
    if m and SC.MaybeExists("target") and not SC.True(UnitIsPlayer("target"))
        and SC.Bool(UnitIsDead("target")) == false
        and not (UnitIsTapDenied and SC.Bool(UnitIsTapDenied("target")) == true) then
        local n = SC.UnitNameSafe("target")
        if n then
            on = n:lower() == m.name:lower()
        else
            local f = follow[m.name]
            on = f and f.viaTarget or false
        end
    end
    SC.SetOnMob(on)
end

SC.On("PLAYER_REGEN_ENABLED", function() SC.EvalTarget() end)

-- Your own target change (not the key's) ends following through the target.
SC.On("PLAYER_TARGET_CHANGED", function()
    local now = GetTime()
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
end

SC.Scan = Scan

-- No combat log: Forever forbids addons from registering
-- COMBAT_LOG_EVENT_UNFILTERED (0.8.0 tried and got the "blocked from an action
-- only available to the Blizzard UI" popup). Deaths come from nameplates,
-- target, mouseover, the key, sharing and the manual buttons.

SC.On("NAME_PLATE_UNIT_ADDED", function(unit)
    plates[unit] = true
    Check(unit)
end)

-- Nameplates go away when the mob dies; read it once more on the way out.
SC.On("NAME_PLATE_UNIT_REMOVED", function(unit)
    Check(unit)
    plates[unit] = nil
    if SC.fastUnit == unit then SC.SetFastUnit(nil) end
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
