-- Dungeon mobs. Inside an instance the nameplate scan can't read names, so
-- SpawnCamp can't learn what's around. Questie's database already knows every
-- NPC that spawns in each instance, so on zoning in the key gets that list:
--
--   key macro:          ... /click [noexists] SpawnCampDungeon1 ; cast lines
--   SpawnCampDungeon1:  /target [noexists] Sand
--                       /cleartarget [dead][noharm]
--                       /target [noexists] Sul'
--                       ...
--                       /click [noexists] SpawnCampDungeon2
--   last button:        ... /targetenemy [noexists]
--
-- Macros have no wildcards, but /target <text> matches the start of a name,
-- so names are grouped by a shared start ("Sand" covers every Sandfury mob,
-- Sandarr and Sandscalp). The game runs only 255 characters of a macro, so the
-- searches go in a chain of buttons the key /clicks. The chain ends with
-- /targetenemy: summoned pets, totems and wards that Questie has no spawn for
-- are still hostile, and nothing else in an instance is.
--
-- Friendly-to-start NPCs stay on the list: Zul'Farrak's Witch Doctor and
-- Sergeant Bly's crew turn hostile mid-run. [noharm] drops them while they're
-- friendly. NPCs with a service (quest giver, vendor, trainer) never turn, so
-- they're left out, and no group's text is allowed to match one of them.

local _, SC = ...

local MACRO_MAX = 255
local CHAIN = 8              -- buttons in the chain; 8 x ~4 searches covers a big dungeon
local BTN = "SpawnCampDungeon"
local MIN_PREFIX = 4         -- shortest group text, unless a whole name is shorter
local LAST = "/targetenemy [noexists]"
local CLEAR = "/cleartarget [dead][noharm]"

SC.DUNGEON_CHAIN = CHAIN

------------------------------------------------------------------------------
-- Grouping
------------------------------------------------------------------------------

-- Cut points that don't split a UTF-8 character or end on a space (a macro
-- line's trailing space is dropped, so "Oro " would become "Oro").
local function Cuts(name)
    local out = {}
    for len = math.min(MIN_PREFIX, #name), #name do
        local nb = name:byte(len + 1)
        if (not nb or nb < 0x80 or nb > 0xBF) and name:byte(len) ~= 32 then out[#out + 1] = len end
    end
    return out
end

-- mobs: { { name, rank, level } }; avoid: names a group must not match.
-- Returns { { text, names = { ... } } } in key order: biggest group first,
-- then by rank and level, so bosses and elites come before stragglers.
function SC.GroupNames(mobs, avoid)
    local left, info = {}, {}
    for _, m in ipairs(mobs) do
        local low = m.name:lower()
        if not info[low] then
            info[low] = { name = m.name, rank = m.rank or 0, level = m.level or 0 }
            left[#left + 1] = low
        end
    end
    local avoidLow = {}
    for _, n in ipairs(avoid or {}) do avoidLow[#avoidLow + 1] = n:lower() end
    local function Clean(p)
        for _, a in ipairs(avoidLow) do
            if a:sub(1, #p) == p then return false end
        end
        return true
    end
    local groups = {}
    while #left > 0 do
        local count = {}
        for _, low in ipairs(left) do
            for _, len in ipairs(Cuts(low)) do
                local p = low:sub(1, len)
                count[p] = (count[p] or 0) + 1
            end
        end
        local best, bestN
        for _, low in ipairs(left) do
            local cuts = Cuts(low)
            for ci, len in ipairs(cuts) do
                local p = low:sub(1, len)
                -- the whole name is always allowed, even if it starts a service NPC's name
                if ci == #cuts or Clean(p) then
                    local n = count[p]
                    if not best or n > bestN or (n == bestN and #p < #best) or (n == bestN and #p == #best and p < best) then
                        best, bestN = p, n
                    end
                end
            end
        end
        local g = { names = {}, rank = 0, level = 0 }
        local rest = {}
        for _, low in ipairs(left) do
            if low:sub(1, #best) == best then
                local i = info[low]
                g.names[#g.names + 1] = i.name
                g.text = g.text or i.name:sub(1, #best)
                g.rank = math.max(g.rank, i.rank)
                g.level = math.max(g.level, i.level)
            else
                rest[#rest + 1] = low
            end
        end
        table.sort(g.names)
        groups[#groups + 1] = g
        left = rest
    end
    table.sort(groups, function(a, b)
        if #a.names ~= #b.names then return #a.names > #b.names end
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.level ~= b.level then return a.level > b.level end
        return a.text < b.text
    end)
    return groups
end

-- Groups into button macros. Returns the macro texts and how many groups fit.
function SC.PackDungeon(groups)
    local reserve = math.max(#("/click [noexists] " .. BTN .. CHAIN), #LAST) + 1
    local buttons, cur, len, used = {}, {}, 0, 0
    for _, g in ipairs(groups) do
        local line = "/target [noexists] " .. g.text .. "\n" .. CLEAR
        local cost = #line + (#cur > 0 and 1 or 0)
        if #cur > 0 and len + cost + reserve > MACRO_MAX then
            if #buttons + 1 >= CHAIN then break end
            buttons[#buttons + 1] = cur
            cur, len, cost = {}, 0, #line
        end
        cur[#cur + 1] = line
        len = len + cost
        used = used + 1
    end
    buttons[#buttons + 1] = cur
    for i, lines in ipairs(buttons) do
        lines[#lines + 1] = i < #buttons and ("/click [noexists] " .. BTN .. (i + 1)) or LAST
        buttons[i] = table.concat(lines, "\n")
    end
    return buttons, used
end

------------------------------------------------------------------------------
-- Questie lookup
------------------------------------------------------------------------------

-- npcFlags bit 1 is gossip, which hostile-later NPCs (Sergeant Bly) have too.
-- Anything above it is a service.
local function Service(flags)
    return type(flags) == "number" and flags > 1
end

local cache = {}   -- area id -> { mobs = {...}, avoid = {...} }

-- Every NPC Questie places in this area: a spawn there, or (summoned and
-- scripted NPCs with no spawn point) the area as its main zone. step yields
-- every few hundred NPCs so a scan never stalls a frame.
local function Collect(db, area, step)
    local mobs, avoid, seen = {}, {}, {}
    local function Q(id, k)
        local ok, v = pcall(db.QueryNPCSingle, id, k)
        return ok and v or nil
    end
    local n = 0
    for id in pairs(db.NPCPointers) do
        n = n + 1
        if step and n % 400 == 0 then step() end
        local here = Q(id, "zoneID") == area
        if not here then
            local sp = Q(id, "spawns")
            here = type(sp) == "table" and sp[area] ~= nil
        end
        if here then
            local name = Q(id, "name")
            if type(name) == "string" and name ~= "" then
                if Service(Q(id, "npcFlags")) then
                    avoid[#avoid + 1] = name
                elseif not seen[name] then
                    seen[name] = true
                    mobs[#mobs + 1] = { name = name, rank = Q(id, "rank"), level = Q(id, "maxLevel") }
                end
            end
        end
    end
    table.sort(mobs, function(a, b) return a.name < b.name end)
    return { mobs = mobs, avoid = avoid }
end

-- Questie area id for the instance you're in, or nil.
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
-- The chain buttons
------------------------------------------------------------------------------

local buttons = {}
for i = 1, CHAIN do
    local b = CreateFrame("Button", BTN .. i, UIParent, "SecureActionButtonTemplate")
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
    buttons[i] = b
end

-- SC.dungeon: { name, area, mobs, groups, texts, used, set } while you're in
-- an instance Questie knows, else nil.
SC.dungeon = nil

local function WriteButtons()
    if InCombatLockdown() then SC.AfterCombat(WriteButtons); return end
    local texts = SC.dungeon and SC.DungeonOn() and SC.dungeon.texts or {}
    for i, b in ipairs(buttons) do b:SetAttribute("macrotext", texts[i] or "") end
end

function SC.DungeonOn()
    return SC.char and SC.char.dungeonMobs and SC.dungeon ~= nil and #SC.dungeon.mobs > 0
end

-- The key's stand-in for the dungeon: one "mob" the key follows once a press
-- lands on anything the chain found.
function SC.DungeonStandIn()
    if not SC.DungeonOn() then return nil end
    return { name = SC.dungeon.name, mode = "attack", dungeon = true }
end

-- A readable target name that's one of this dungeon's mobs.
function SC.IsDungeonName(n)
    return SC.dungeon ~= nil and type(n) == "string" and SC.dungeon.set[n:lower()] == true
end

-- The first line of the chain, for the key's macro.
function SC.DungeonClick()
    return "/click [noexists] " .. BTN .. "1"
end

local function Apply(area, name, data)
    local groups = SC.GroupNames(data.mobs, data.avoid)
    local texts, used = SC.PackDungeon(groups)
    local set = {}
    for _, m in ipairs(data.mobs) do set[m.name:lower()] = true end
    SC.dungeon = { name = name or "Dungeon", area = area, mobs = data.mobs, groups = groups,
                   texts = texts, used = used, set = set }
    WriteButtons()
    if SC.ApplyBindings then SC.ApplyBindings() end
    if SC.Refresh then SC.Refresh() end
    if SC.DungeonOn() then
        local left = #groups - used
        SC.Print(string.format("%s: the key goes for its %d mobs (%d searches%s). /spc dungeon lists them.",
            SC.dungeon.name, #data.mobs, used, left > 0 and (", " .. left .. " left out") or ""))
    end
end

local scanning   -- area being scanned

-- Runs the lookup for the instance you're in. sync (tests) does it in one go.
function SC.DungeonCheck(sync, tries)
    local db, zones = SC.QuestieDBs()
    if not db then
        -- Questie starts its database a few seconds after login.
        if (tries or 0) < 15 and IsInInstance() then
            C_Timer.After(2, function() SC.DungeonCheck(sync, (tries or 0) + 1) end)
        end
        if SC.dungeon then SC.dungeon = nil; WriteButtons(); SC.ApplyBindings() end
        return
    end
    local area, name = InstanceArea(zones)
    if not area then
        if SC.dungeon then
            SC.dungeon = nil
            WriteButtons()
            SC.ApplyBindings()
            SC.Refresh()
        end
        return
    end
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
            -- still there?
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
    WriteButtons()
    SC.ApplyBindings()
    SC.Refresh()
end

SC.On("PLAYER_ENTERING_WORLD", function() SC.DungeonCheck() end)
SC.On("ZONE_CHANGED_NEW_AREA", function() SC.DungeonCheck() end)

-- /spc dungeon
function SC.DungeonReport()
    local d = SC.dungeon
    if not d then
        SC.Print(IsInInstance() and "Questie has no list for this instance (or isn't loaded)." or "you're not in a dungeon.")
        return
    end
    SC.Print(string.format("%s: %d mobs, %d searches%s.", d.name, #d.mobs, #d.groups,
        SC.char.dungeonMobs and "" or " (off: tick \"Dungeon mobs on the key\" in the settings)"))
    for i, g in ipairs(d.groups) do
        local tag = i > d.used and "|cff808080(left out, macro chain full)|r " or ""
        print(string.format("  %s\"%s\": %s", tag, g.text, table.concat(g.names, ", ")))
    end
    print("  then any enemy left (pets, totems, wards)")
end

-- For tests.
SC._dungeon = { buttons = buttons, cache = cache, Collect = Collect }
