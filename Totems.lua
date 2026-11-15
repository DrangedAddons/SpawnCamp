-- Auto > Totem / Ward: the key goes for an enemy totem or ward first, before
-- your own targets, and back to them once it's gone.
--
-- Totems drop mid-fight, and in combat the key's macro is frozen, so the
-- totem lines have to be in the macro before the pull. They go straight into
-- the key's own macro, at the top. On a mob (or locked on one):
--
--   /cleartarget
--   /targetexact [noexists] Lava Spout Totem
--   /targetexact [noexists] Searing Totem
--   /targetlasttarget [noexists]
--   /cleartarget [noharm]
--
-- Each name only runs while nothing is targeted yet, so a miss can't undo an
-- earlier hit, whatever the game does on a miss. No totem up: back to the mob
-- you were on. While the key is searching (target already cleared) it's the
-- same without the clear and the restore.
-- [noharm] drops a friendly totem of the same name (a party shaman's).
--
-- Not through a hidden button and /click: in Zul'Farrak, "/click <button>" to
-- one of SpawnCamp's hidden macro buttons did nothing, typed or from the key,
-- while the same /targetexact typed by hand, or on a card in the key, worked.
-- So the names share the key's 255 characters, ahead of your own searches.
--
-- The names: every enemy nameplate of the game's Totem creature type (wards
-- are totems too) is remembered for the zone it was seen in, in
-- SpawnCampDB.totems. One seen mid-fight joins the key when that fight ends.
-- In a dungeon names can't be read, so the dungeon's list (Dungeon.lua, with
-- DungeonData.lua's summons) supplies its totems and wards from the start.

local _, SC = ...

local MACRO_MAX = 255
local TOTEM_TYPE = 11            -- creature type id for Totem

-- The names on the key, fixed out of combat (ApplyBindings). SC.totemText is
-- the same for /spc totems.
SC.totemList, SC.totemText = {}, ""

local typeName
local function TotemTypeName()
    if typeName then return typeName end
    typeName = "Totem"
    if C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo then
        local ok, info = pcall(C_CreatureInfo.GetCreatureTypeInfo, TOTEM_TYPE)
        if ok and type(info) == "table" and type(info.name) == "string" then typeName = info.name end
    end
    return typeName
end

-- The unit is a totem or ward (creature type Totem).
function SC.IsTotem(unit)
    if not SC.MaybeExists(unit) then return false end
    local ok, name, id = pcall(UnitCreatureType, unit)
    if not ok then return false end
    if SC.Plain(id) == TOTEM_TYPE then return true end
    name = SC.Plain(name)
    return type(name) == "string" and name == TotemTypeName()
end

-- Where a learned totem belongs: the dungeon, else the zone.
local function ZoneKey()
    if SC.dungeon then return "instance:" .. tostring(SC.dungeon.area) end
    local z = GetRealZoneText and GetRealZoneText()
    if type(z) == "string" and z ~= "" then return z end
end

-- An enemy totem's nameplate: remember its name for this zone.
function SC.NoteTotem(unit)
    if not SpawnCampDB or not SC.IsTotem(unit) then return end
    if SC.Bool(UnitCanAttack("player", unit)) ~= true or SC.True(UnitIsPlayer(unit)) then return end
    local n = SC.UnitNameSafe(unit)
    local k = ZoneKey()
    if not (n and k) then return end
    SpawnCampDB.totems = SpawnCampDB.totems or {}
    local t = SpawnCampDB.totems[k]
    if not t then t = {}; SpawnCampDB.totems[k] = t end
    if t[n] then return end
    t[n] = true
    if SC.char and SC.char.autoTotem then
        SC.Print("Auto Totem: |cffffffff" .. n .. "|r is on the key here" ..
            (InCombatLockdown() and " once this fight ends." or "."))
        SC.ApplyBindings()   -- waits for combat to end by itself
        if SC.Refresh then SC.Refresh() end
    end
end

-- The map id of the dungeon or raid you're in, or nil.
local function InstanceID()
    local inInstance, kind = IsInInstance()
    if not (SC.True(inInstance) and (kind == "party" or kind == "raid")) then return nil end
    local _, _, _, _, _, _, _, id = GetInstanceInfo()
    return id
end
SC.InstanceID = InstanceID

-- Totem and ward names the key goes for here. In an instance: its totems and
-- wards from DungeonData.lua, which ships with the addon, so they're there
-- the moment you zone in or reload. That matters: the key can only be bound
-- out of combat, and waiting on Questie's list (several seconds) left the
-- key unbound for the whole first fight after a reload. Then the Questie-built
-- list's, then the ones seen in this zone. Healing ones first: they share
-- the key's 255 characters and the first names are the ones that fit.
function SC.TotemNames()
    local found, seen = {}, {}
    local function add(n)
        if not seen[n] then seen[n] = true; found[#found + 1] = n end
    end
    local id = InstanceID()
    local data = id and SC.DUNGEON_DATA and SC.DUNGEON_DATA[id]
    for _, s in ipairs(data and data.summons or {}) do
        if s[3] or (SC.IsTotemName and SC.IsTotemName(s[1])) then add(s[1]) end
    end
    local d = SC.dungeon
    for _, m in ipairs(d and d.mobs or {}) do
        if m.totem then add(m.name) end
    end
    local out = {}
    for _, n in ipairs(found) do if n:lower():find("heal", 1, true) then out[#out + 1] = n end end
    for _, n in ipairs(found) do if not n:lower():find("heal", 1, true) then out[#out + 1] = n end end
    seen = {}
    for _, n in ipairs(out) do seen[n] = true end
    add = function(n)
        if not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    local k = ZoneKey()
    local learned = k and SpawnCampDB and SpawnCampDB.totems and SpawnCampDB.totems[k]
    local names = {}
    for n in pairs(learned or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do add(n) end
    return out
end

-- Picks the names for the key. Out of combat only (ApplyBindings calls it
-- before it builds the key).
function SC.WriteTotemButton()
    if InCombatLockdown() then return end
    SC.totemList = (SC.char and SC.char.autoTotem) and SC.TotemNames() or {}
    SC.totemText = table.concat(SC.totemList, ", ")
end

-- The key's totem lines, within budget characters (newlines counted), or
-- nil when none fit. keep: you're on a mob, so clear first and go back to it
-- when no totem is up. SC.totemOnKey is how many names made it.
function SC.TotemLines(keep, budget)
    SC.totemOnKey = 0
    if #SC.totemList == 0 then return nil end
    local pre = keep and { "/cleartarget" } or {}
    -- [noharm] is for a party shaman's totem sharing a learned name. A
    -- dungeon's names are its mobs' own summons, so it's left out there.
    local post = {}
    if keep then post[#post + 1] = "/targetlasttarget [noexists]" end
    if not (SC.dungeon or InstanceID()) then post[#post + 1] = "/cleartarget [noharm]" end
    local len = 0
    for _, l in ipairs(pre) do len = len + #l + 1 end
    for _, l in ipairs(post) do len = len + #l + 1 end
    local names = {}
    for i, n in ipairs(SC.totemList) do
        -- "/tar <full name>": what works typed by hand in Zul'Farrak
        -- ("/tar greater healing ward"), and the short form leaves room for
        -- more names. The first has no condition (the target is always
        -- clear here: the key or the line before cleared it).
        local line = (i == 1 and "/tar " or "/tar [noexists] ") .. n
        if len + #line + 1 > budget then break end
        names[#names + 1] = line
        len = len + #line + 1
    end
    if #names == 0 then return nil end
    SC.totemOnKey = #names
    local out = {}
    for _, l in ipairs(pre) do out[#out + 1] = l end
    for _, l in ipairs(names) do out[#out + 1] = l end
    for _, l in ipairs(post) do out[#out + 1] = l end
    return out
end

-- The totem the key is on: your target, when it's an enemy totem with a
-- readable name. nil otherwise.
function SC.TotemShown()
    if not (SC.MaybeExists("target") and SC.IsTotem("target")) then return nil end
    if SC.Bool(UnitCanAttack("player", "target")) ~= true or SC.Bool(UnitIsDead("target")) ~= false then return nil end
    return SC.UnitNameSafe("target")
end

-- Auto Totem has names for the key here.
function SC.TotemOn()
    return #SC.totemList > 0
end

function SC.SetAutoTotem(on)
    SC.char.autoTotem = on and true or false
    SC.ApplyBindings()
    if SC.Refresh then SC.Refresh() end
end

-- Zone changes change the list.
SC.On("ZONE_CHANGED_NEW_AREA", function() if SC.char then SC.ApplyBindings() end end)
SC.On("PLAYER_ENTERING_WORLD", function() if SC.char then SC.ApplyBindings() end end)

-- /spc totems: what the game tells an addon about every nameplate and your
-- target, and what the totem button holds. For when totem targeting fails.
-- Saved to SpawnCampDB.totemProbe (/reload writes it to disk).
function SC.TotemReport()
    local out = {}
    local function line(s) out[#out + 1] = s; print("  " .. s) end
    local function show(f, ...)
        local ok, a, b = pcall(f, ...)
        if not ok then return "ERROR " .. tostring(a) end
        local function one(v)
            if v == nil then return "nil" end
            if SC.issecret(v) then return "SECRET" end
            return type(v) == "string" and ('"' .. v .. '"') or tostring(v)
        end
        if b ~= nil then return one(a) .. "/" .. one(b) end
        return one(a)
    end
    local function npcID(unit)
        local ok, g = pcall(UnitGUID, unit)
        if not ok or g == nil or SC.issecret(g) or type(g) ~= "string" then return "?" end
        return g:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)") or g:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)") or "?"
    end
    SC.Print("totem probe (also saved; /reload to write it to disk):")
    local _, itype = IsInInstance()
    line("zone " .. tostring(GetRealZoneText and GetRealZoneText()) .. ", instance " .. tostring(itype)
        .. ", dungeon list " .. tostring(SC.dungeon and #SC.dungeon.mobs or ("none: " .. tostring(SC.dungeonWhy or "no lookup yet")))
        .. ", Auto Totem " .. tostring(SC.char and SC.char.autoTotem) .. ", in combat " .. tostring(InCombatLockdown()))
    line("totem names: " .. (SC.totemText ~= "" and SC.totemText or "(none)")
        .. "; on the key: " .. tostring(SC.totemOnKey or 0))
    local kb = _G.SpawnCampKey
    local live = type(kb) == "table" and kb.GetAttribute and kb:GetAttribute("macrotext") or ""
    if type(live) ~= "string" then live = "" end
    line("key " .. tostring(SC.char and SC.char.key) .. ": " .. (SC.keyBound and "bound" or "NOT BOUND (presses do nothing)")
        .. (SC.keyWaiting and ", an update is waiting for this fight to end" or ""))
    line("live key (" .. (SC.talkBound and "bound to Interact, the macro doesn't run" or "runs its macro") .. "): "
        .. (live ~= "" and (live:gsub("\n", " ; ")) or "(empty)"))
    local units = { "target", "mouseover" }
    for i = 1, 40 do
        local ok, v = pcall(UnitExists, "nameplate" .. i)
        if ok and v ~= nil and (SC.issecret(v) or v) then units[#units + 1] = "nameplate" .. i end
    end
    for _, u in ipairs(units) do
        if SC.MaybeExists(u) then
            local n, why = SC.UnitNameSafe(u)
            line(string.format("[%s] name %s, type %s, totem %s, npc %s, canAttack %s, dead %s, guid %s",
                u, n and ('"' .. n .. '"') or ("(" .. why .. ")"), show(UnitCreatureType, u),
                tostring(SC.IsTotem(u)), npcID(u), show(UnitCanAttack, "player", u), show(UnitIsDead, u),
                show(UnitGUID, u)))
        end
    end
    SpawnCampDB.totemProbe = { time = date("%Y-%m-%d %H:%M:%S"), lines = out }
end

