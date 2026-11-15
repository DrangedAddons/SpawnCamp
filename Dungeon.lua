-- Dungeon mobs. Inside an instance the nameplate scan can't read names, and
-- /target <part of a name> doesn't find anything either. /targetexact with a
-- full name is what works, so SpawnCamp needs the full names, and Questie's
-- database has them:
--
--   * every NPC Questie places in the instance (a spawn there, or the
--     instance as its main zone);
--   * gaps Questie leaves, from DungeonData.lua (generated from the cMaNGOS
--     classic database by tools/build_dungeon_data.py): mobs cMaNGOS spawns
--     there that Questie doesn't place, and what the instance's mobs summon
--     (totems, wards, adds), which Questie has no record of at all, and
--     what the instance's server script creates (event waves, boss adds:
--     Sandfury Drudge, Sandfury Zealot);
--   * the SUMMONS table below, for what neither has (summons the server
--     scripts in code, Forever-only NPCs);
--
-- No name gets on the list by resemblance. An earlier version took in
-- placeless NPCs that shared a first word with the instance's mobs, or were
-- "<something> of <a boss>": that put every "Spirit of ..." in the game on
-- Maraudon's list and the Defias of Westfall in the Deadmines. Every name now
-- comes from data that ties that NPC to this instance.
--
--   * your typed searches ("slave", "totem") match only those names.
--
-- What the list is for: the key itself only ever goes for your own targets
-- and (Auto > Totem / Ward) the instance's totems and wards, never "any
-- enemy", so it can't pull something you didn't pick. The list supplies the
-- full names:
--   * a typed search ("slave") adds a card for every name on it containing
--     the text, and each card is a full-name line in the key's own macro;
--   * Auto Totem takes its totem and ward names from it (Totems.lua).
--
-- There used to be hidden buttons holding a /targetexact line per mob, which
-- the key reached with /click. In game that /click never targeted anything
-- (the game refuses /click on buttons like those), so they're gone.
--
-- NPCs Questie marks friendly stay on the list: Zul'Farrak's Witch Doctor and
-- Sergeant Bly's crew turn hostile mid-run. Quest givers, vendors and
-- trainers never turn and are left out.

local _, SC = ...


------------------------------------------------------------------------------
-- Questie lookup
------------------------------------------------------------------------------

-- npcFlags bit 1 is gossip, which hostile-later NPCs (Sergeant Bly) have too.
-- Anything above it is a service.
local function Service(flags)
    return type(flags) == "number" and flags > 1
end

local cache = {}      -- area id -> { mobs = {...} }

-- Summons DungeonData.lua doesn't have, by Questie area id: the ones the
-- server makes in its C++ scripts rather than its database, and Forever-only
-- NPCs. Written by hand from what was seen in game. Names must be exact.
local SUMMONS = {
    [1176] = {   -- Zul'Farrak
        "Skeleton of Zum'rah",      -- Ward of Zum'rah
        "Zombie Troll of Zum'rah",  -- Witch Doctor Zum'rah
    },
}
SC.DUNGEON_SUMMONS = SUMMONS

-- A totem or ward by name ("Sul'lithuz Warder" isn't one).
local function TotemName(n)
    local low = n:lower()
    return low:find("%f[%a]totem%f[%A]") ~= nil or low:find("%f[%a]ward%f[%A]") ~= nil
end
SC.IsTotemName = TotemName

-- One pass over Questie's NPCs. step yields every few hundred so a scan
-- never stalls a frame.
local function Collect(db, area, step, mapID)
    local zone, avoid, seen = {}, {}, {}
    -- Questie reads a number it has no value for as 0 (a summon's zone is 0,
    -- not nil), so 0 counts as "none" here.
    local function Q(id, k)
        local ok, v = pcall(db.QueryNPCSingle, id, k)
        if ok and v ~= 0 then return v end
    end
    local n = 0
    for id in pairs(db.NPCPointers) do
        n = n + 1
        if step and n % 300 == 0 then step() end
        local name = Q(id, "name")
        if type(name) == "string" and name ~= "" then
            local zid = Q(id, "zoneID")
            local sp = Q(id, "spawns")
            local hasSpawn = type(sp) == "table" and next(sp) ~= nil
            local service = Service(Q(id, "npcFlags"))
            local friendly = Q(id, "friendlyToFaction") ~= nil
            local here = zid == area or (hasSpawn and sp[area] ~= nil)
            if here then
                if service then
                    avoid[name] = true
                elseif not seen[name] then
                    seen[name] = true
                    zone[#zone + 1] = { name = name, rank = Q(id, "rank") or 0, level = Q(id, "maxLevel") or 0, friendly = friendly, src = "questie" }
                end
            end
        end
    end
    -- Gaps from the generated data, then the hand-written summons. A name
    -- already on the list only gets marked (a totem, who summons it).
    -- src says why a name is on the list: "questie" (Questie places it
    -- here), "spawn" (cMaNGOS spawns it here), "summon" (a mob here summons
    -- it), "script" (the instance's server script creates it), "seen"
    -- (written down from the game). A name with no src must never get on.
    local function Extra(n, totem, by, src)
        if seen[n] then
            for _, m in ipairs(zone) do
                if m.name == n then
                    m.totem = m.totem or totem or nil
                    m.by = m.by or by
                    break
                end
            end
            return
        end
        seen[n] = true
        zone[#zone + 1] = { name = n, rank = 0, level = 0, family = true, totem = totem or nil, by = by, src = src }
    end
    local prof = mapID and SC.DUNGEON_DATA and SC.DUNGEON_DATA[mapID]
    if prof then
        for _, n in ipairs(prof.mobs or {}) do
            if not avoid[n] then Extra(n, false, nil, "spawn") end
        end
        for _, s in ipairs(prof.summons or {}) do
            Extra(s[1], s[3] or TotemName(s[1]), s[2] ~= "" and s[2] or nil, "summon")
        end
        for _, n in ipairs(prof.scripted or {}) do
            if not avoid[n] then Extra(n, TotemName(n), nil, "script") end
        end
    end
    for _, n in ipairs(SUMMONS[area] or {}) do Extra(n, TotemName(n), nil, "seen") end
    -- Bosses and elites first, then by level; family extras after the
    -- instance's own mobs of the same rank.
    table.sort(zone, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        if (a.family or false) ~= (b.family or false) then return not a.family end
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return { mobs = zone }
end

-- Questie area id and name for the instance you're in, or nil.
local function InstanceArea(zones)
    local inInstance, kind = IsInInstance()
    if not (SC.True(inInstance) and (kind == "party" or kind == "raid")) then return nil end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local map = zones and zones.instanceIdToAreaId
    local area = type(map) == "table" and map[instanceID] or nil
    if not area and zones and type(zones.GetAreaIdByName) == "function" then
        for _, n in ipairs({ name, GetRealZoneText and GetRealZoneText() }) do
            local ok, a = pcall(zones.GetAreaIdByName, zones, n)
            if ok and a then area = a; break end
        end
    end
    if not area and zones and type(zones.GetAreaIdByUiMapId) == "function" and C_Map and C_Map.GetBestMapForUnit then
        local okM, ui = pcall(C_Map.GetBestMapForUnit, "player")
        if okM and ui then
            local ok, a = pcall(zones.GetAreaIdByUiMapId, zones, ui)
            area = ok and a or nil
        end
    end
    return area, name, instanceID
end

------------------------------------------------------------------------------
-- Typed searches
------------------------------------------------------------------------------

-- Full names a typed search stands for in this dungeon: the dungeon's own
-- names (its mobs and what they summon) containing the text.
-- Returns { { name, friendly } }.
function SC.DungeonExpand(text)
    local d = SC.dungeon
    if not d or type(text) ~= "string" or text == "" then return {} end
    local low, out = text:lower(), {}
    for _, m in ipairs(d.mobs) do
        if m.name:lower():find(low, 1, true) then out[#out + 1] = m end
    end
    return out
end

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

-- SC.dungeon: { name, area, mobs } while you're in an instance Questie
-- knows, else nil.
SC.dungeon = nil

-- In an instance with its list loaded. The key then skips its partial
-- "/target <text>" lines: your searches are cards with full names there.
function SC.DungeonOn()
    return SC.dungeon ~= nil
end

------------------------------------------------------------------------------
-- Zoning
------------------------------------------------------------------------------

-- Cards a search added for names that aren't on this instance's list and
-- that you've never seen: leftovers of a list that had strangers on it
-- (0.50.0 put every "Spirit of ..." in the game on Maraudon's).
local function DropStrays()
    local c = SC.char
    if not (c and SC.dungeon) then return end
    local on = {}
    for _, m in ipairs(SC.dungeon.mobs) do on[m.name] = true end
    for i = #c.targets, 1, -1 do
        local n = c.targets[i]
        local m = c.mobs[n]
        if m and m.fromPartial and not m.partial and not on[n]
            and not SC.WasSeen(n) and not (SC.nearby and SC.nearby[n]) then
            table.remove(c.targets, i)
            c.mobs[n] = nil
            for j, o in ipairs(c.order) do
                if o == n then table.remove(c.order, j); break end
            end
            if c.selected == n then c.selected = nil end
        end
    end
end

local function Apply(area, name, data)
    SC.dungeon = { name = name or "Dungeon", area = area, mobs = data.mobs }
    -- Your searches get a card for each of the dungeon's mobs they match,
    -- as outdoors when a matching nameplate shows.
    pcall(DropStrays)
    if SC.FindPartials then pcall(SC.FindPartials) end
    if SC.ApplyBindings then SC.ApplyBindings() end
    if SC.Refresh then SC.Refresh() end
    SC.Print(string.format("%s: enemy list loaded (%d). Type a search to add its mobs as targets.",
        SC.dungeon.name, #data.mobs))
end

local function Leave()
    if not SC.dungeon then return end
    SC.dungeon = nil
    if SC.ApplyBindings then SC.ApplyBindings() end
    if SC.Refresh then SC.Refresh() end
end

local scanning   -- area being scanned
local retrying   -- a retry is queued
SC.dungeonWhy = nil   -- why the last lookup found no list, for /spc dungeon

-- Questie can take a while to build its database after login or /reload.
-- While you're in an instance with no list, look again every 3 seconds.
local function Retry(sync)
    if retrying or sync or not SC.True(IsInInstance()) then return end
    retrying = true
    C_Timer.After(3, function()
        retrying = nil
        if not SC.dungeon and SC.True(IsInInstance()) then SC.DungeonCheck() end
    end)
end

-- One chat line per stay in an instance while its list isn't in yet, so a
-- wait doesn't look like a broken key.
local told
local function Loading(sync)
    if sync or not SC.char then return end
    local inInstance, kind = IsInInstance()
    if not (SC.True(inInstance) and (kind == "party" or kind == "raid")) then told = nil; return end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    if told == id then return end
    told = id
    if SC.RefreshStatus then SC.RefreshStatus() end
    SC.Print(tostring(name) .. ": loading enemy list.")
end

-- Runs the lookup for the instance you're in. sync (tests) does it in one go.
function SC.DungeonCheck(sync)
    local db, zones = SC.QuestieDBs()
    if not db then
        SC.dungeonWhy = "Questie's database isn't ready (or Questie isn't loaded)"
        Leave()
        Loading(sync)
        Retry(sync)
        return
    end
    local area, name, mapID = InstanceArea(zones)
    if not area then
        Loading(sync)
        if SC.True(IsInInstance()) then
            local _, _, _, _, _, _, _, id = GetInstanceInfo()
            SC.dungeonWhy = string.format("Questie has no zone for instance %s (%s)%s", tostring(id), tostring((GetInstanceInfo())),
                zones and "" or ", and its ZoneDB module didn't load")
            Retry(sync)
        else
            SC.dungeonWhy = nil
        end
        Leave()
        return
    end
    SC.dungeonWhy = nil
    if SC.dungeon and SC.dungeon.area == area then return end
    if cache[area] then Apply(area, name, cache[area]); return end
    if sync then
        cache[area] = Collect(db, area, nil, mapID)
        Apply(area, name, cache[area])
        return
    end
    if scanning == area then return end
    scanning = area
    Loading(sync)
    local co = coroutine.create(function()
        cache[area] = Collect(db, area, coroutine.yield, mapID)
    end)
    local function Resume()
        local ok, err = coroutine.resume(co)
        if not ok then
            scanning = nil
            SC.dungeonWhy = "reading Questie's list failed: " .. tostring(err)
            SC.Print("|cffff4040couldn't read Questie's list for this instance:|r " .. tostring(err))
            return
        end
        if coroutine.status(co) == "dead" then
            scanning = nil
            local _, z = SC.QuestieDBs()
            if InstanceArea(z) == area then Apply(area, name, cache[area]) end
        else
            C_Timer.After(0, Resume)
        end
    end
    Resume()
end


SC.On("PLAYER_ENTERING_WORLD", function() SC.DungeonCheck() end)
SC.On("ZONE_CHANGED_NEW_AREA", function() SC.DungeonCheck() end)

-- The zone-in events alone missed Zul'Farrak in game: no lookup ran until
-- /spc dungeon. So while you're in an instance with no list for it (and no
-- scan running), look again every 5 seconds.
local function Watch()
    if not SC.char then return end
    if SC.RefreshStatus then SC.RefreshStatus() end
    if scanning then return end
    local inInstance, kind = IsInInstance()
    if not (SC.True(inInstance) and (kind == "party" or kind == "raid")) then
        if SC.dungeon then SC.DungeonCheck() end
        return
    end
    if not SC.dungeon then SC.DungeonCheck() end
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, function() pcall(Watch) end) end

-- The window's title-bar status: text, r, g, b. In an instance: its list
-- (loading or loaded) and how many totem names are on the key. Anywhere: a
-- key the game has locked because a fight is on.
function SC.StatusLine()
    if not SC.char then return "" end
    local hasKey = SC.char.key ~= ""
    if hasKey and SC.keyWaiting and not SC.keyBound then
        return "Key locked by combat: it works when this fight ends", 1, 0.45, 0.25
    end
    local inInstance, kind = IsInInstance()
    if not (SC.True(inInstance) and (kind == "party" or kind == "raid")) then
        if hasKey and SC.keyWaiting then return "Key changes apply when this fight ends", 1, 0.82, 0 end
        return ""
    end
    local name = tostring((GetInstanceInfo()))
    local totems = SC.char.autoTotem and string.format(", %d of %d totems/wards on the key",
        SC.totemOnKey or 0, #(SC.totemList or {})) or ""
    local wait = (hasKey and SC.keyWaiting) and "  (key updates after this fight)" or ""
    if SC.dungeon then
        return string.format("%s: %d enemies%s%s", name, #SC.dungeon.mobs, totems, wait), 0.3, 0.9, 0.45
    end
    return string.format("%s: loading enemy list...%s%s", name, totems, wait), 1, 0.82, 0
end

-- /spc dungeon
function SC.DungeonReport()
    local d = SC.dungeon
    if not d then
        if not SC.True(IsInInstance()) then SC.Print("you're not in a dungeon."); return end
        SC.DungeonCheck()
        d = SC.dungeon
    end
    if not d then
        if scanning then
            SC.Print("reading Questie's list for this instance now. Try /spc dungeon again in a few seconds.")
            return
        end
        SC.Print("no list for this instance: " .. (SC.dungeonWhy or "unknown reason") .. ".")
        local inI, kind = IsInInstance()
        local name, itype, _, _, _, _, _, id = GetInstanceInfo()
        local db, zones = SC.QuestieDBs()
        local map = zones and zones.instanceIdToAreaId
        print(string.format("  instance: %s, type %s / %s, id %s", tostring(name), tostring(kind), tostring(itype), tostring(id)))
        print(string.format("  Questie: loader %s, database %s, ZoneDB %s, map entry %s",
            rawget(_G, "QuestieLoader") and "yes" or "no", db and "ready" or "not ready", zones and "yes" or "no",
            type(map) == "table" and tostring(map[id]) or "no map"))
        print("  SpawnCamp keeps trying every 3 seconds while you're in here.")
        return
    end
    SC.Print(string.format("%s: %d enemies on the list.", d.name, #d.mobs))
    local names = {}
    for _, m in ipairs(d.mobs) do
        local n = m.name
        if m.totem then n = n .. " |cff808080(totem/ward)|r" end
        if m.by then n = n .. " |cff808080(summoned by " .. m.by .. ")|r" end
        names[#names + 1] = n
    end
    print("  " .. table.concat(names, ", "))
end

-- For tests.
SC._dungeon = { cache = cache, Collect = Collect }
