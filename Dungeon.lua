-- Dungeon mobs. Inside an instance the nameplate scan can't read names, and
-- /target <part of a name> doesn't find anything either. /targetexact with a
-- full name is what works, so SpawnCamp needs the full names, and Questie's
-- database has them:
--
--   * every NPC Questie places in the instance (a spawn there, or the
--     instance as its main zone);
--   * spawnless NPCs of the same family: event and summoned mobs (Sandfury
--     Slave, Sandfury Drudge, Sandfury Zealot) have no spawn point or zone in
--     Questie, but share a first word with two or more of the instance's mobs;
--   * gaps Questie leaves, from DungeonData.lua (generated from the cMaNGOS
--     classic database by tools/build_dungeon_data.py): mobs cMaNGOS spawns
--     there that Questie doesn't place, and what the instance's mobs summon
--     (totems, wards, adds), which Questie has no record of at all;
--   * the SUMMONS table below, for what neither has (summons the server
--     scripts in code, Forever-only NPCs);
--   * your typed searches ("slave", "totem") match only those names.
--
-- Each name is one /targetexact line. That's far past one macro's 255
-- characters, so the lines go into hidden buttons and a hub button /clicks
-- them in order:
--
--   key macro:  ... /click [noexists] SpawnCampDH ; cast lines
--   hub:        /click SpcD1 ; /click SpcD2 ; ... ; /targetenemy [noexists]
--   SpcD1:      /targetexact [noexists] Sandfury Executioner
--               /cleartarget [dead]
--               ...
--
-- Every search line has [noexists], so once one finds a live mob the rest do
-- nothing. The hub ends with /targetenemy: whatever hostile is left (pets,
-- totems, wards) is still part of the fight.
--
-- NPCs Questie marks friendly stay on the list: Zul'Farrak's Witch Doctor and
-- Sergeant Bly's crew turn hostile mid-run. Their lines clear [noharm] too.
-- Quest givers, vendors and trainers never turn and are left out.

local _, SC = ...

local MACRO_MAX = 255
local HUBS, PER_HUB = 4, 15     -- each hub /clicks 15 search buttons, then the next hub
local CHAIN = HUBS * PER_HUB     -- search buttons: room for about 200 names (60 x 3-4)
local HUB = "SpawnCampDH"        -- hubs 2-4 are SpawnCampDH2 ... SpawnCampDH4
local BTN = "SpcD"               -- short: a hub's 255 characters hold all its /clicks
local LAST = "/targetenemy [noexists]"

SC.DUNGEON_CHAIN = CHAIN

------------------------------------------------------------------------------
-- Questie lookup
------------------------------------------------------------------------------

-- npcFlags bit 1 is gossip, which hostile-later NPCs (Sergeant Bly) have too.
-- Anything above it is a service.
local function Service(flags)
    return type(flags) == "number" and flags > 1
end

local function FirstWord(name)
    local w = name:match("^(%S+)")
    return w and #w >= 4 and w:lower() or nil
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
    local zone, avoid, seen, spawnless = {}, {}, {}, {}
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
                    zone[#zone + 1] = { name = name, rank = Q(id, "rank") or 0, level = Q(id, "maxLevel") or 0, friendly = friendly }
                end
            elseif not hasSpawn and zid == nil and not service then
                spawnless[#spawnless + 1] = { name = name, friendly = friendly }
            end
        end
    end
    -- Families: a first word two or more of the instance's mobs share.
    local fam = {}
    for _, m in ipairs(zone) do
        local w = FirstWord(m.name)
        if w then fam[w] = (fam[w] or 0) + 1 end
    end
    local zoneLow = {}
    for _, m in ipairs(zone) do zoneLow[#zoneLow + 1] = m.name:lower() end
    -- A boss's summons: "Ward of Zum'rah", "Skeleton of Zum'rah".
    local function OfBoss(low)
        local y = low:match(" of (.+)$")
        if not y or #y < 4 then return false end
        for _, z in ipairs(zoneLow) do
            if z:find(y, 1, true) then return true end
        end
        return false
    end
    for _, s in ipairs(spawnless) do
        local w = FirstWord(s.name)
        local low = s.name:lower()
        -- invisible script helpers ("Zul'Farrak Concoction Stalker") can't be targeted
        local helper = low:find(" stalker$") or low:find("trigger") or low:find("bunny") or low:find("%[dn")
        if ((w and (fam[w] or 0) >= 2) or OfBoss(low)) and not seen[s.name] and not helper then
            seen[s.name] = true
            zone[#zone + 1] = { name = s.name, rank = 0, level = 0, friendly = s.friendly, family = true }
        end
    end
    -- Gaps from the generated data, then the hand-written summons. A name
    -- already on the list only gets marked (a totem, who summons it).
    local function Extra(n, totem, by)
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
        zone[#zone + 1] = { name = n, rank = 0, level = 0, family = true, totem = totem or nil, by = by }
    end
    local prof = mapID and SC.DUNGEON_DATA and SC.DUNGEON_DATA[mapID]
    if prof then
        for _, n in ipairs(prof.mobs or {}) do
            if not avoid[n] then Extra(n, false) end
        end
        for _, s in ipairs(prof.summons or {}) do
            Extra(s[1], s[3] or TotemName(s[1]), s[2] ~= "" and s[2] or nil)
        end
    end
    for _, n in ipairs(SUMMONS[area] or {}) do Extra(n, TotemName(n)) end
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
-- The buttons
------------------------------------------------------------------------------

local function Secure(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:SetSize(1, 1)
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    b:SetAlpha(0)
    b:EnableMouse(false)
    -- /click sends one edge; listen on both and act on the up edge whatever
    -- "cast on key down" says (as SpawnCampInteract does).
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    b:Show()
    return b
end

local hubs = {}
for h = 1, HUBS do hubs[h] = Secure(h == 1 and HUB or (HUB .. h)) end
local buttons = {}
for i = 1, CHAIN do buttons[i] = Secure(BTN .. i) end

-- SC.dungeon: { name, area, mobs } while you're in an instance Questie
-- knows, else nil. SC.dungeonChain: what's on the buttons now.
SC.dungeon = nil
SC.dungeonChain = nil

local function Line(name, friendly)
    return "/targetexact [noexists] " .. name .. "\n/cleartarget [dead]" .. (friendly and "[noharm]" or "")
end

-- The search names in key order: typed searches (expanded), then the
-- dungeon's mobs when "Dungeon mobs on the key" is on. Returns
-- { { name, friendly, from } } and whether /targetenemy ends the chain.
local function ChainNames()
    local d = SC.dungeon
    if not d then return {}, false end
    local out, seen = {}, {}
    local function add(m, from)
        local k = m.name:lower()
        if seen[k] then return end
        seen[k] = true
        out[#out + 1] = { name = m.name, friendly = m.friendly, from = from, by = m.by, totem = m.totem }
    end
    -- Your own exact targets (cards, including ones a search added) are in
    -- the key's macro already.
    for _, t in ipairs(SC.Actives()) do
        if not t.partial then seen[t.name:lower()] = true end
    end
    for _, t in ipairs(SC.Actives()) do
        if t.partial then
            local rejected = t.rejected or {}
            for _, m in ipairs(SC.DungeonExpand(t.name)) do
                if not rejected[m.name] then add(m, t.name) end
            end
        end
    end
    local on = SC.char and SC.char.dungeonMobs
    if on then
        for _, m in ipairs(d.mobs) do add(m, nil) end
    end
    return out, on
end

-- Packs names into the search buttons. Returns the button texts, the hub
-- text and how many names fit.
function SC.PackDungeon(names, anyEnemy)
    local texts, cur, len, used = {}, {}, 0, 0
    for _, n in ipairs(names) do
        local line = Line(n.name, n.friendly)
        local cost = #line + (#cur > 0 and 1 or 0)
        if #cur > 0 and len + cost > MACRO_MAX then
            texts[#texts + 1] = table.concat(cur, "\n")
            if #texts >= CHAIN then cur = nil; break end
            cur, len, cost = {}, 0, #line
        end
        if #line > MACRO_MAX then break end
        cur[#cur + 1] = line
        len = len + cost
        used = used + 1
    end
    if cur and #cur > 0 then texts[#texts + 1] = table.concat(cur, "\n") end
    -- Hubs: each clicks its share of buttons, then the next hub only while
    -- nothing's been found yet.
    local hubTexts = {}
    local nHubs = math.max(1, math.ceil(#texts / PER_HUB))
    for h = 1, nHubs do
        local lines = {}
        for i = (h - 1) * PER_HUB + 1, math.min(#texts, h * PER_HUB) do lines[#lines + 1] = "/click " .. BTN .. i end
        if h < nHubs then
            lines[#lines + 1] = "/click [noexists] " .. HUB .. (h + 1)
        elseif anyEnemy then
            lines[#lines + 1] = LAST
        end
        hubTexts[h] = table.concat(lines, "\n")
    end
    return texts, hubTexts, used
end

-- Rebuilds the buttons from the dungeon and your searches. Out of combat
-- only (ApplyBindings calls it).
function SC.WriteDungeonChain()
    if InCombatLockdown() then return end
    local names, anyEnemy = ChainNames()
    local texts, hubTexts, used = {}, {}, 0
    if #names > 0 or anyEnemy then texts, hubTexts, used = SC.PackDungeon(names, anyEnemy) end
    for i, b in ipairs(buttons) do b:SetAttribute("macrotext", texts[i] or "") end
    for h, b in ipairs(hubs) do b:SetAttribute("macrotext", hubTexts[h] or "") end
    if (hubTexts[1] or "") == "" then
        SC.dungeonChain = nil
    else
        local set = {}
        for _, n in ipairs(names) do set[n.name:lower()] = true end
        SC.dungeonChain = { names = names, texts = texts, hubs = hubTexts, hub = table.concat(hubTexts, "\n"),
                            used = used, set = set }
    end
end

function SC.DungeonOn()
    return SC.dungeonChain ~= nil
end

-- The key's stand-in for the chain: one "mob" the key follows once a press
-- lands on anything the chain found.
function SC.DungeonStandIn()
    if not SC.dungeonChain then return nil end
    return { name = SC.dungeon.name, mode = "attack", dungeon = true }
end

-- A readable target name that's on the chain.
function SC.IsDungeonName(n)
    return SC.dungeonChain ~= nil and type(n) == "string" and SC.dungeonChain.set[n:lower()] == true
end

-- The key macro's line for the chain.
function SC.DungeonClick()
    return "/click [noexists] " .. HUB
end

------------------------------------------------------------------------------
-- Zoning
------------------------------------------------------------------------------

local function Apply(area, name, data)
    SC.dungeon = { name = name or "Dungeon", area = area, mobs = data.mobs }
    -- Your searches get a card for each of the dungeon's mobs they match,
    -- as outdoors when a matching nameplate shows.
    if SC.FindPartials then pcall(SC.FindPartials) end
    if SC.ApplyBindings then SC.ApplyBindings() end
    if SC.Refresh then SC.Refresh() end
    local c = SC.dungeonChain
    if c and SC.char.dungeonMobs then
        local left = #c.names - c.used
        SC.Print(string.format("%s: the key goes for its %d mobs%s. /spc dungeon lists them.",
            SC.dungeon.name, #data.mobs, left > 0 and (" (" .. left .. " lowest left out)") or ""))
    end
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

-- Runs the lookup for the instance you're in. sync (tests) does it in one go.
function SC.DungeonCheck(sync)
    local db, zones = SC.QuestieDBs()
    if not db then
        SC.dungeonWhy = "Questie's database isn't ready (or Questie isn't loaded)"
        Leave()
        Retry(sync)
        return
    end
    local area, name, mapID = InstanceArea(zones)
    if not area then
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

function SC.SetDungeonMobs(on)
    SC.char.dungeonMobs = on and true or false
    SC.ApplyBindings()
    SC.Refresh()
end

SC.On("PLAYER_ENTERING_WORLD", function() SC.DungeonCheck() end)
SC.On("ZONE_CHANGED_NEW_AREA", function() SC.DungeonCheck() end)

-- /spc dungeon
function SC.DungeonReport()
    local d, c = SC.dungeon, SC.dungeonChain
    if not d then
        if not SC.True(IsInInstance()) then SC.Print("you're not in a dungeon."); return end
        SC.DungeonCheck()
        d, c = SC.dungeon, SC.dungeonChain
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
    SC.Print(string.format("%s: %d mobs from Questie%s.", d.name, #d.mobs,
        SC.char.dungeonMobs and "" or " (not on the key: tick \"Dungeon mobs on the key\" in the settings)"))
    if not c then return end
    local names = {}
    for i, n in ipairs(c.names) do
        local s = n.name
        if n.from then s = s .. " |cff808080(\"" .. n.from .. "\")|r" end
        if n.by then s = s .. " |cff808080(summoned by " .. n.by .. ")|r" end
        if i > c.used then s = "|cff808080" .. s .. " (left out)|r" end
        names[#names + 1] = s
    end
    print("  in order: " .. table.concat(names, ", "))
    if c.hub:find(LAST, 1, true) then print("  then any enemy left (pets, totems, wards)") end
end

-- For tests.
SC._dungeon = { buttons = buttons, hubs = hubs, cache = cache, Collect = Collect }
