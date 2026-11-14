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
--   * your typed searches ("slave", "totem"): matched against those names
--     first, else against every name Questie knows, preferring summons.
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
local CHAIN = 15                 -- search buttons the hub clicks
local HUB = "SpawnCampDH"
local BTN = "SpcD"               -- short: the hub's 255 characters hold all the /clicks
local LAST = "/targetenemy [noexists]"
local SEARCH_CAP = 8             -- names one typed search adds from outside the dungeon

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
local allNames        -- every Questie NPC: { { name, spawnless, friendly } }, built on the first scan

-- One pass over Questie's NPCs. step yields every few hundred so a scan
-- never stalls a frame.
local function Collect(db, area, step)
    local zone, avoid, seen, spawnless = {}, {}, {}, {}
    local all = not allNames and {} or nil
    local allSeen = {}
    local function Q(id, k)
        local ok, v = pcall(db.QueryNPCSingle, id, k)
        if ok then return v end
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
            if all and not service and not allSeen[name] then
                allSeen[name] = true
                all[#all + 1] = { name = name, spawnless = not hasSpawn, friendly = friendly }
            end
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
    if all then
        table.sort(all, function(a, b) return a.name < b.name end)
        allNames = all
    end
    -- Families: a first word two or more of the instance's mobs share.
    local fam = {}
    for _, m in ipairs(zone) do
        local w = FirstWord(m.name)
        if w then fam[w] = (fam[w] or 0) + 1 end
    end
    for _, s in ipairs(spawnless) do
        local w = FirstWord(s.name)
        local low = s.name:lower()
        -- invisible script helpers ("Zul'Farrak Concoction Stalker") can't be targeted
        local helper = low:find(" stalker$") or low:find("trigger") or low:find("bunny") or low:find("%[dn")
        if w and (fam[w] or 0) >= 2 and not seen[s.name] and not helper then
            seen[s.name] = true
            zone[#zone + 1] = { name = s.name, rank = 0, level = 0, friendly = s.friendly, family = true }
        end
    end
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
        local ok, a = pcall(zones.GetAreaIdByName, zones, name)
        area = ok and a or nil
    end
    return area, name
end

------------------------------------------------------------------------------
-- Typed searches
------------------------------------------------------------------------------

-- Full names a typed search stands for in this dungeon: the dungeon's own
-- names containing the text; if none, every Questie name containing it,
-- summons first (no spawn point: totems, wards, pets), shortest first, up to
-- SEARCH_CAP. Returns { { name, friendly } }.
function SC.DungeonExpand(text)
    local d = SC.dungeon
    if not d or type(text) ~= "string" or text == "" then return {} end
    local low, out = text:lower(), {}
    for _, m in ipairs(d.mobs) do
        if m.name:lower():find(low, 1, true) then out[#out + 1] = m end
    end
    if #out > 0 or not allNames then return out end
    local hits = {}
    for _, a in ipairs(allNames) do
        if a.name:lower():find(low, 1, true) then hits[#hits + 1] = a end
    end
    table.sort(hits, function(a, b)
        if a.spawnless ~= b.spawnless then return a.spawnless end
        if #a.name ~= #b.name then return #a.name < #b.name end
        return a.name < b.name
    end)
    for i = 1, math.min(SEARCH_CAP, #hits) do out[i] = hits[i] end
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

local hub = Secure(HUB)
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
        out[#out + 1] = { name = m.name, friendly = m.friendly, from = from }
    end
    for _, t in ipairs(SC.Actives()) do
        if t.partial then
            for _, m in ipairs(SC.DungeonExpand(t.name)) do add(m, t.name) end
        elseif not seen[t.name:lower()] then
            seen[t.name:lower()] = true   -- your own exact targets are in the key's macro
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
    local hubLines = {}
    for i = 1, #texts do hubLines[i] = "/click " .. BTN .. i end
    if anyEnemy then hubLines[#hubLines + 1] = LAST end
    return texts, table.concat(hubLines, "\n"), used
end

-- Rebuilds the buttons from the dungeon and your searches. Out of combat
-- only (ApplyBindings calls it).
function SC.WriteDungeonChain()
    if InCombatLockdown() then return end
    local names, anyEnemy = ChainNames()
    local texts, hubText, used = {}, "", 0
    if #names > 0 or anyEnemy then texts, hubText, used = SC.PackDungeon(names, anyEnemy) end
    for i, b in ipairs(buttons) do b:SetAttribute("macrotext", texts[i] or "") end
    hub:SetAttribute("macrotext", hubText)
    if hubText == "" then
        SC.dungeonChain = nil
    else
        local set = {}
        for _, n in ipairs(names) do set[n.name:lower()] = true end
        SC.dungeonChain = { names = names, texts = texts, hub = hubText, used = used, set = set }
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

-- Runs the lookup for the instance you're in. sync (tests) does it in one go.
function SC.DungeonCheck(sync, tries)
    local db, zones = SC.QuestieDBs()
    if not db then
        -- Questie starts its database a few seconds after login.
        if (tries or 0) < 15 and SC.True(IsInInstance()) then
            C_Timer.After(2, function() SC.DungeonCheck(sync, (tries or 0) + 1) end)
        end
        Leave()
        return
    end
    local area, name = InstanceArea(zones)
    if not area then Leave(); return end
    if SC.dungeon and SC.dungeon.area == area then return end
    if cache[area] then Apply(area, name, cache[area]); return end
    if sync then
        cache[area] = Collect(db, area)
        Apply(area, name, cache[area])
        return
    end
    if scanning == area then return end
    scanning = area
    local co = coroutine.create(function()
        cache[area] = Collect(db, area, coroutine.yield)
    end)
    local function Resume()
        local ok, err = coroutine.resume(co)
        if not ok then
            scanning = nil
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
        SC.Print(SC.True(IsInInstance()) and "Questie has no list for this instance (or isn't loaded)." or "you're not in a dungeon.")
        return
    end
    SC.Print(string.format("%s: %d mobs from Questie%s.", d.name, #d.mobs,
        SC.char.dungeonMobs and "" or " (not on the key: tick \"Dungeon mobs on the key\" in the settings)"))
    if not c then return end
    local names = {}
    for i, n in ipairs(c.names) do
        local s = n.name
        if n.from then s = s .. " |cff808080(\"" .. n.from .. "\")|r" end
        if i > c.used then s = "|cff808080" .. s .. " (left out)|r" end
        names[#names + 1] = s
    end
    print("  in order: " .. table.concat(names, ", "))
    if c.hub:find(LAST, 1, true) then print("  then any enemy left (pets, totems, wards)") end
end

-- For tests.
SC._dungeon = { buttons = buttons, hub = hub, cache = cache, Collect = Collect }
