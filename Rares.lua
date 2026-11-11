-- Rare finder.
--
-- Three sources, kept apart:
--   SC.RARE_FOREVER     Forever-only rares (RareData.lua, from SilverDragon's
--                       Forever zone files). Treated as confirmed.
--   SC.RARE_DATA        vanilla 1.12 reference list (RareData.lua, from vmangos).
--                       Never written to. Shown as "vanilla data" until seen here.
--   SpawnCampDB.rareSeen  what this account actually saw on Forever: any unit
--                       whose nameplate says rare / rare elite, plus any unit
--                       named like a vanilla rare (so "not rare here" shows too).
-- Positions in RareData are world coordinates. C_Map turns them into zone
-- coordinates in game, so no zone table ships with the addon.

local _, SC = ...

local DATA = SC.RARE_DATA or {}
local FOREVER = SC.RARE_FOREVER or {}
local byName = {}
for id, r in pairs(DATA) do byName[r[1]:lower()] = id end
for id, r in pairs(FOREVER) do byName[r[1]:lower()] = id end

local CONT_MAP = { [0] = 1415, [1] = 1414 }   -- Eastern Kingdoms, Kalimdor
local ALERT_AGAIN = 300                       -- seconds before the same rare alerts again
local NOTE_EVERY = 10                         -- seconds between sighting updates per rare
local IS_RARE = { rare = true, rareelite = true }

function SC.RareInfo(name)
    local id = name and byName[name:lower()]
    return id and (DATA[id] or FOREVER[id]), id
end

local function Seen()
    SpawnCampDB.rareSeen = SpawnCampDB.rareSeen or {}
    return SpawnCampDB.rareSeen
end

------------------------------------------------------------------------------
-- Maps
------------------------------------------------------------------------------

local function HasMap()
    return C_Map and C_Map.GetMapPosFromWorldPos and C_Map.GetBestMapForUnit and CreateVector2D
end

-- The zone-level map you're on (climbs out of sub-zone maps).
function SC.RareZone()
    if not HasMap() then return nil end
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    id = ok and SC.Plain(id) or nil
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for _ = 1, 5 do
        if not id then return nil end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        if not info then return id end
        if info.mapType == zoneType or not info.parentMapID or info.parentMapID == 0 then return id, info.name end
        if info.mapType and info.mapType < zoneType then return nil end   -- on a continent or the world map
        id = info.parentMapID
    end
    return id
end

local function MapPos(cont, wx, wy, mapID)
    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), mapID)
    if ok and pos then
        local x, y = pos:GetXY()
        return x, y
    end
end

-- Which zone a world point is in. Uses the continent map's zone outlines when
-- the client has them (zone rectangles overlap at the borders), else nil.
local zoneCache = {}
local function ZoneAt(cont, wx, wy)
    local key = cont .. ":" .. wx .. ":" .. wy
    local z = zoneCache[key]
    if z ~= nil then return z or nil end
    z = false
    local cm = CONT_MAP[cont]
    if cm and C_Map.GetMapInfoAtPosition then
        local x, y = MapPos(cont, wx, wy, cm)
        if x then
            local ok, info = pcall(C_Map.GetMapInfoAtPosition, cm, x, y)
            if ok and info and info.mapID then z = info.mapID end
        end
    end
    zoneCache[key] = z
    return z or nil
end

local function InZone(r, mapID)
    local pts, inside = r[9], {}
    for i = 1, #pts, 2 do
        local wx, wy = pts[i], pts[i + 1]
        local z = ZoneAt(r[5], wx, wy)
        local x, y = MapPos(r[5], wx, wy, mapID)
        local ok
        if z then ok = z == mapID else ok = x and x >= 0 and x <= 1 and y >= 0 and y <= 1 end
        if ok and x then inside[#inside + 1] = { x = x, y = y, spawn = (i + 1) / 2 <= r[8], wx = wx, wy = wy } end
    end
    return #inside > 0 and inside or nil
end

-- World position of a map point, for distances. Cached.
local worldCache = {}
local function WorldOf(mapID, x, y)
    local key = mapID .. ":" .. x .. ":" .. y
    local w = worldCache[key]
    if w == nil then
        w = false
        if C_Map.GetWorldPosFromMapPos then
            local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
            if ok and pos then local a, b = pos:GetXY(); w = { a, b, cont } end
        end
        worldCache[key] = w
    end
    return w or nil
end

local function PlayerWorld()
    if not UnitPosition then return end
    local a, b, _, inst = UnitPosition("player")
    a, b, inst = SC.Plain(a), SC.Plain(b), SC.Plain(inst)
    if type(a) == "number" and type(b) == "number" then return a, b, inst end
end

local function PlayerMapPos(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition and mapID) then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if ok and pos then
        local x, y = pos:GetXY()
        x, y = SC.Plain(x), SC.Plain(y)
        if type(x) == "number" then return x, y end
    end
end

------------------------------------------------------------------------------
-- Sightings and alerts
------------------------------------------------------------------------------

local alerted, noted = {}, {}

local function SilverDragonOn()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return f and f("SilverDragon") and true or false
end
SC.SilverDragonOn = SilverDragonOn

-- Called from NoteNearby for every NPC read. e = the nearby entry.
function SC.NoteRare(name, e)
    if not (SC.char and SpawnCampDB) then return end
    local cls = e.class
    local inData = byName[name:lower()] ~= nil
    if not (IS_RARE[cls] or inData) then return end
    local now = GetTime()
    if not noted[name] or now - noted[name] > NOTE_EVERY then
        noted[name] = now
        local s = Seen()[name] or { n = 0 }
        if cls then s.class = cls end
        if type(e.level) == "number" then s.level = e.level end
        s.t = GetServerTime()
        s.n = (s.n or 0) + 1
        local zone, zoneName = SC.RareZone()
        if zone then
            s.map, s.zone = zone, zoneName or s.zone
            local x, y = PlayerMapPos(zone)
            if x then s.x, s.y = math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000 end
        end
        local a, b, inst = PlayerWorld()
        if a then s.wx, s.wy, s.cont = math.floor(a), math.floor(b), inst end
        Seen()[name] = s
    end
    -- Alert: rare by nameplate, or a vanilla rare whose class can't be read.
    local rare = IS_RARE[cls] or (cls == nil and inData)
    if not rare or e.dead or e.hostile == false then return end
    if not SC.char.rareAlert or SilverDragonOn() then return end
    if SC.char.mobs[name] and SC.IsActive(name) then return end   -- your own target alerts already
    if alerted[name] and now - alerted[name] < ALERT_AGAIN then return end
    alerted[name] = now
    SC.Alert("Rare nearby: " .. name)
end

------------------------------------------------------------------------------
-- The list for your zone
------------------------------------------------------------------------------

-- Every rare for the zone you're in. Each item:
--   name, id, minLevel, maxLevel, elite, respawn {min, max} (vanilla timer),
--   points {x, y, spawn} in zone coords, dist (yards to the nearest point),
--   seen (Forever sighting or nil), vanilla (only known from vanilla data),
--   notRare (seen here and its nameplate isn't rare).
local zoneLists = {}

function SC.RaresHere()
    local zone, zoneName = SC.RareZone()
    if not zone then return {}, nil end
    local base = zoneLists[zone]
    if not base then
        base = {}
        if HasMap() then
            for id, r in pairs(DATA) do
                local pts = InZone(r, zone)
                if pts then base[#base + 1] = { id = id, r = r, points = pts } end
            end
            for id, r in pairs(FOREVER) do
                if r[2] == zone then
                    local pts = {}
                    for i = 1, #r[3], 2 do
                        local p = { x = r[3][i], y = r[3][i + 1], spawn = true }
                        local w = WorldOf(zone, p.x, p.y)
                        if w then p.wx, p.wy, p.cont = w[1], w[2], w[3] end
                        pts[#pts + 1] = p
                    end
                    base[#base + 1] = { id = id, forever = true, name = r[1], points = pts }
                end
            end
        end
        zoneLists[zone] = base
    end
    local seen = Seen()
    local a, b, inst = PlayerWorld()
    local out, have = {}, {}
    for _, item in ipairs(base) do
        local r = item.r
        local name = item.forever and item.name or r[1]
        local s = seen[name]
        local dist
        for _, p in ipairs(item.points) do
            if a and p.wx and inst == (p.cont or (r and r[5])) then
                local d = math.sqrt((p.wx - a) ^ 2 + (p.wy - b) ^ 2)
                if not dist or d < dist then dist = d end
            end
        end
        have[name] = true
        local e = {
            name = name, id = item.id, points = item.points, dist = dist, seen = s,
            forever = item.forever, vanilla = not item.forever and s == nil,
            notRare = s and s.class and not IS_RARE[s.class] or false,
        }
        if r then
            e.minLevel, e.maxLevel, e.elite, e.respawn = r[2], r[3], r[4] == 1, { r[6], r[7] }
        elseif s then
            e.minLevel, e.maxLevel, e.elite = s.level, s.level, s.class == "rareelite"
        end
        out[#out + 1] = e
    end
    -- Rares seen here that the vanilla list doesn't have.
    for name, s in pairs(seen) do
        if not have[name] and s.map == zone and IS_RARE[s.class] then
            local dist
            if a and s.wx and inst == s.cont then dist = math.sqrt((s.wx - a) ^ 2 + (s.wy - b) ^ 2) end
            out[#out + 1] = {
                name = name, minLevel = s.level, maxLevel = s.level, elite = s.class == "rareelite",
                points = s.x and { { x = s.x, y = s.y } } or {}, dist = dist,
                seen = s, vanilla = false, foreverOnly = true, notRare = false,
            }
        end
    end
    if not SC.char.rareShowVanilla then
        for i = #out, 1, -1 do if out[i].vanilla then table.remove(out, i) end end
    end
    table.sort(out, function(x, y)
        if x.notRare ~= y.notRare then return y.notRare end
        if (x.dist ~= nil) ~= (y.dist ~= nil) then return x.dist ~= nil end
        if x.dist and y.dist and math.abs(x.dist - y.dist) > 1 then return x.dist < y.dist end
        return x.name < y.name
    end)
    return out, zoneName
end

SC.On("ZONE_CHANGED_NEW_AREA", function() if SC.char then SC.Refresh() end end)
