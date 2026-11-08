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
        if kind == "A" and mob.alertSpawn and events[#events] == e then
            SC.Alert(name .. " is up!" .. (src ~= "you" and (" (seen by " .. src .. ")") or ""))
        end
        if kind == "D" and e.mine and mob.mode == "attack" then
            mob.hunting = false
            mob.armed = false
            SC.ApplyBindings()
            SC.Alert("You got " .. name .. "!")
            SC.Print("stopped hunting " .. name .. " and freed its key. Tick \"Still hunting\" to start again.")
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

-- What the timer list shows. Returns state, text, fraction (0-1 progress toward the window) or nil.
--   "up"      seen alive, last event is a spawn
--   "waiting" dead, window not open yet
--   "window"  dead, between earliest and latest expected respawn
--   "late"    dead, past the latest expected respawn
--   "dead"    dead, no timing data yet
--   "none"    nothing logged
function SC.Status(name)
    local events = SC.History(name).events
    local last = events[#events]
    if not last then return "none", "no sightings yet" end
    local now = GetServerTime()
    local ago = now - last.t
    if last.k == "A" then
        local seen = now - (last.seen or last.t)
        return "up", seen < 5 and "UP, in view" or ("up, last seen " .. SC.Clock(seen) .. " ago")
    end
    local lo, avg, hi = SC.Stats(name)
    local died = "died " .. SC.Clock(ago) .. " ago" .. (last.approx and "+" or "")
    if not lo then return "dead", died end
    if ago < lo then
        return "waiting", "spawns in " .. SC.Clock(lo - ago) .. " (" .. died .. ")", ago / lo
    end
    if hi and ago <= hi then
        return "window", "IN WINDOW, closes in " .. SC.Clock(hi - ago), 1
    end
    return "late", "overdue by " .. SC.Clock(ago - (hi or avg or lo)), 1
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

-- Alarm flags per death event, so each fires once. Session only.
local fired = setmetatable({}, { __mode = "k" })

local function CheckAlarms()
    local now = GetServerTime()
    for _, name in ipairs(SC.char.order) do
        local mob = SC.char.mobs[name]
        if mob and mob.hunting and mob.alarm then
            local events = SC.History(name).events
            local last = events[#events]
            if last and last.k == "D" then
                local lo = SC.Stats(name)
                if lo then
                    local f = fired[last]
                    if not f then f = {}; fired[last] = f end
                    local ago = now - last.t
                    local lead = mob.lead or 0
                    -- Only alarm for deaths inside the expected window plus a margin, so
                    -- logging in to an old death doesn't go off.
                    if not f.pre and lead > 0 and ago >= lo - lead and ago < lo then
                        f.pre = true
                        SC.Alert(name .. " may spawn in " .. SC.Clock(lo - ago))
                    end
                    if not f.open and ago >= lo and ago < lo + 120 then
                        f.open = true
                        SC.Alert(name .. " respawn window is open")
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------------
-- Scanning
------------------------------------------------------------------------------

local function Check(unit)
    local name, mob, dead, spawn, tapDenied = SC.ReadUnit(unit)
    if not name then return end
    if dead == true then
        local events = SC.History(name).events
        -- Exact when we saw this spawn alive (same UID, or the last event was it alive).
        local last = events[#events]
        local sawAlive = last and last.k == "A" and (not spawn or not last.s or last.s == spawn)
        local mine = tapDenied == false and mob.mode == "attack" and sawAlive
        SC.Observe(name, "D", spawn, nil, "you", { approx = not sawAlive, mine = mine })
    elseif dead == false then
        SC.Observe(name, "A", spawn, nil, "you")
    end
end

local function Scan()
    if not SC.char then return end
    for unit in pairs(plates) do Check(unit) end
    Check("target")
    Check("mouseover")
end

SC.On("NAME_PLATE_UNIT_ADDED", function(unit)
    plates[unit] = true
    Check(unit)
end)

-- Nameplates go away when the mob dies; read it once more on the way out.
SC.On("NAME_PLATE_UNIT_REMOVED", function(unit)
    Check(unit)
    plates[unit] = nil
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

local function Channels()
    local out = {}
    if IsInRaid and IsInRaid() then out[#out + 1] = "RAID"
    elseif IsInGroup and IsInGroup() then out[#out + 1] = "PARTY" end
    if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
    return out
end

function SC.Share(name, e)
    if not (SC.char.share and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
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

SC.On("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if prefix ~= PREFIX or not SC.char or not SC.char.share then return end
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
