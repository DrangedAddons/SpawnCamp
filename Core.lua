-- SpawnCamp core: saved variables, event helper, secret-safe unit reads,
-- combat queue and slash commands.
--
-- SpawnCampCharDB (per character): the watched mobs and their key, spell,
-- interact and quest settings. Spells and keys differ per class.
-- SpawnCampDB (account): sighting history per realm and mob name, so alts on
-- the same realm share it.

local ADDON, SC = ...
_G.SpawnCamp = SC

SC.ICON = "Interface\\Icons\\Ability_Hunter_MarkedForDeath"

local issecret
if issecretvalue then
    issecret = issecretvalue
elseif canaccessvalue then
    issecret = function(v) return not canaccessvalue(v) end
else
    issecret = function() return false end
end
SC.issecret = issecret

-- The value, or nil when it's missing or secret.
function SC.Plain(v)
    if v == nil or issecret(v) then return nil end
    return v
end

-- Older-style APIs return 1/nil instead of true/false, so any plain truthy
-- value counts. Secret values count as false here.
function SC.True(v)
    return v ~= nil and not issecret(v) and v ~= false and v ~= 0
end

-- true/false from a boolean-ish API result, or nil when it's secret.
function SC.Bool(v)
    if v ~= nil and issecret(v) then return nil end
    return (v ~= nil and v ~= false and v ~= 0) and true or false
end

function SC.Print(msg)
    print("|cffff9933SpawnCamp|r " .. tostring(msg))
end

------------------------------------------------------------------------------
-- Defaults
------------------------------------------------------------------------------

-- Per character. Each mob only says sword (attack), bubble (talk) or neither;
-- how attacking and talking work is set once, in the gear settings.
SC.CHAR_DEFAULTS = {
    mobs = {},            -- name -> mob (MOB_DEFAULTS)
    order = {},           -- names in list order
    targets = {},         -- mob names the key works on, in order
    selected = nil,       -- mob shown in the details panel
    panel = nil,          -- nil, "mob" (details) or "settings"
    key = "",             -- the one SpawnCamp key, for every mob with a sword or bubble
    attack = {
        spell = "",       -- instant spell; empty = auto attack only
        macroName = "",   -- a saved macro (from /m) to run instead of the spell
    },
    interact = {
        autoQuest = true, -- hand in finished quests, accept new and follow-up ones
        gossip = true,    -- click through chat options
        prefer = "",      -- chat options to pick first, one text match per line
        reward = 1,       -- reward choice when a quest offers several (0 = you pick)
    },
    anyQuest = false,     -- the key also goes for any mob your quests still need
    alertSpawn = true,    -- loud alert when a watched mob is seen alive
    alarm = true,         -- soft dings: early warning, window open, average reached
    rareAlert = true,     -- a rare's nameplate adds it as a target box (silver) with an alert
    rareIgnore = {},      -- lower-case rare name -> name as shown; never pops up or alerts
    lead = 60,            -- early warning, seconds before the earliest expected respawn
    shareParty = true,    -- send and receive sightings with your party
    shareRaid = true,     -- ... your raid
    shareGuild = true,    -- ... your guild
    shown = true,         -- the window is on screen
    showDone = true,      -- keep mobs you already got on the list
    logOpen = true,       -- the log drawer beside the window is open
    logRight = false,     -- log on the right of the window instead of the left
    locked = false,       -- window can't be dragged
    sound = true,         -- play a sound with alerts
    minimap = { hide = false },
}

SC.MOB_DEFAULTS = {
    mode = "attack",      -- "attack" (sword) or "interact" (bubble); always one of the two
    hunting = true,       -- on the key; turned off once you get the kill
    manualMin = 0,        -- minutes; >0 overrides the history's earliest respawn
    manualMax = 0,        -- minutes; >0 overrides the history's latest respawn
}

-- The targets: an ordered list of mob names the key works on (SC.char.targets),
-- up to MAX_TARGETS. Empty = the key does nothing.
SC.MAX_TARGETS = 8

function SC.Targets()
    return SC.char and SC.char.targets or {}
end

function SC.Active(slot)
    if not SC.char then return nil end
    local n = SC.char.targets[slot or 1]
    return n and SC.char.mobs[n] or nil
end

function SC.Actives()
    local out = {}
    for _, n in ipairs(SC.Targets()) do
        local m = SC.char.mobs[n]
        if m then out[#out + 1] = m end
    end
    return out
end

-- Slot a name is in, or nil.
function SC.SlotOf(name)
    if name == nil then return nil end
    for i, n in ipairs(SC.Targets()) do
        if n == name then return i end
    end
end

function SC.IsActive(name)
    return SC.SlotOf(name) ~= nil
end

-- Priority for the key's lock: the slot (1 = highest), then Auto Quest mobs.
function SC.RankOf(name)
    if not name then return nil end
    local s = SC.SlotOf(name)
    if s then return s end
    if SC.char.anyQuest and SC.IsQuestWanted and SC.IsQuestWanted(name) then return SC.MAX_TARGETS + 1 end
end

-- Swaps a target with the one above (delta -1) or below (+1).
function SC.MoveTarget(slot, delta)
    local list, j = SC.char.targets, slot + delta
    if not (list[slot] and list[j]) then return end
    list[slot], list[j] = list[j], list[slot]
    if SC.char.logSlot == slot then SC.char.logSlot = j elseif SC.char.logSlot == j then SC.char.logSlot = slot end
    SC.ApplyBindings()
    if SC.PickLock then pcall(SC.PickLock) end
    if SC.EvalTarget then SC.EvalTarget() end
    SC.Refresh()
end

-- Moves the target in slot `from` to slot `to`; the ones between shift by one.
function SC.MoveTargetTo(from, to)
    local list = SC.char.targets
    if from == to or not (list[from] and list[to]) then return end
    table.insert(list, to, table.remove(list, from))
    local ls = SC.char.logSlot
    if ls == from then
        SC.char.logSlot = to
    elseif ls and from < to and ls > from and ls <= to then
        SC.char.logSlot = ls - 1
    elseif ls and from > to and ls >= to and ls < from then
        SC.char.logSlot = ls + 1
    end
    SC.ApplyBindings()
    if SC.PickLock then pcall(SC.PickLock) end
    if SC.EvalTarget then SC.EvalTarget() end
    SC.Refresh()
end

-- The targets in this mode. With "any quest mob" on, attack also gets the
-- mobs your quests still need (stand-ins with quest = true, after your own
-- targets), capped by SC.questCap so the key's macro stays short enough.
SC.questCap = 8
function SC.MobsIn(mode)
    local out = {}
    for _, m in ipairs(SC.Actives()) do
        if m.mode == mode and not m.partial then out[#out + 1] = m end
    end
    if mode == "attack" and SC.QuestWanted then
        for i, n in ipairs(SC.QuestWanted()) do
            if i > SC.questCap then break end
            out[#out + 1] = { name = n, mode = "attack", quest = true }
        end
    end
    return out
end

-- Adds a mob to the targets (or, with slot, replaces that one), and moves it to
-- the top of the recent list. nil with a slot removes that target.
function SC.SetActive(name, slot)
    if name and not SC.char.mobs[name] then return end
    local list = SC.char.targets
    SC.fastUnit = nil
    if not name then
        local gone = slot and list[slot]
        local gm = gone and SC.char.mobs[gone]
        if gm and gm.fromPartial then
            local search = SC.char.mobs[gm.fromPartial]
            if search and search.partial then
                search.rejected = search.rejected or {}
                search.rejected[gone] = true
            end
            gm.fromPartial = nil
        end
        if slot and list[slot] then table.remove(list, slot) end
        if gone and SC.QuestieForget then pcall(SC.QuestieForget, gone) end
        if gm and gm.test then
            SC.char.mobs[gone] = nil
            for i, n in ipairs(SC.char.order) do
                if n == gone then table.remove(SC.char.order, i); break end
            end
        end
    elseif not SC.SlotOf(name) then
        if slot and list[slot] then
            list[slot] = name
        elseif #list >= SC.MAX_TARGETS then
            SC.Print("that's " .. SC.MAX_TARGETS .. " targets already. Clear one first.")
            return
        else
            list[#list + 1] = name
        end
    end
    if name then
        local m = SC.char.mobs[name]
        m.hunting = true
        for i, n in ipairs(SC.char.order) do
            if n == name then table.remove(SC.char.order, i); break end
        end
        table.insert(SC.char.order, 1, name)
    end
    SC.ApplyBindings()
    if SC.EvalTarget then pcall(SC.EvalTarget) end
    SC.Refresh()
end

-- Removes every target.
function SC.ClearTargets()
    for i = #SC.char.targets, 1, -1 do
        local m = SC.char.mobs[SC.char.targets[i]]
        if m and m.test then SC.SetActive(nil, i) end
    end
    wipe(SC.char.targets)
    SC.fastUnit = nil
    SC.ApplyBindings()
    if SC.EvalTarget then pcall(SC.EvalTarget) end
    SC.Refresh()
end
local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            if type(v) == "table" then
                t[k] = {}
                Fill(t[k], v)
            else
                t[k] = v
            end
        elseif type(v) == "table" and type(t[k]) == "table" then
            Fill(t[k], v)
        end
    end
end
SC.Fill = Fill

function SC.Realm()
    return SC.Plain(GetRealmName()) or "?"
end

-- Sighting history for a mob on this realm: { events = { {k, t, s, src, approx, mine}, ... } }
function SC.History(name)
    local realms = SpawnCampDB.realms
    local r = realms[SC.Realm()]
    if not r then r = {}; realms[SC.Realm()] = r end
    local h = r[name]
    if not h then h = { events = {} }; r[name] = h end
    return h
end

function SC.AddMob(name, mode)
    if not name or name == "" then return end
    local mobs = SC.char.mobs
    if not mobs[name] then
        mobs[name] = { name = name }
        Fill(mobs[name], SC.MOB_DEFAULTS)
        mobs[name].mode = mode or "attack"
    end
    SC.SetActive(name)
    return mobs[name]
end

-- Typed names are always wildcard searches (m.partial). The key looks for a
-- search with "/target <text>" after its exact names. Every mob seen whose
-- name contains the text is added as a target of its own (fromPartial), right
-- under the search. Clearing one of those tells the search to skip that name
-- from then on.

-- A name the game has shown: a sighting in the log or a saved tooltip. Looking
-- a name up makes an empty log entry, so an entry alone doesn't count (that
-- turned a typed search like "owl" into an exact name nothing matches).
function SC.WasSeen(name)
    local r = SpawnCampDB and SpawnCampDB.realms and SpawnCampDB.realms[SC.Realm()]
    local h = r and r[name]
    return h ~= nil and ((h.events and #h.events > 0) or h.tip ~= nil)
end

function SC.KnownNames()
    local out, seen = {}, {}
    local function add(n)
        if type(n) == "string" and n ~= "" and not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    for n in pairs(SC.nearby or {}) do add(n) end
    if SC.QuestMobs then
        local ok, list = pcall(SC.QuestMobs)
        if ok then for _, r in ipairs(list) do add(r.name) end end
    end
    local r = SpawnCampDB and SpawnCampDB.realms and SpawnCampDB.realms[SC.Realm()]
    for n in pairs(r or {}) do if SC.WasSeen(n) then add(n) end end
    return out
end

-- The slash command that targets a target's name: part of a name for an
-- unconfirmed one, the exact name otherwise.
function SC.TargetCmd(name)
    local m = SC.char and SC.char.mobs[name]
    return (m and m.partial) and "/target " or "/targetexact "
end

function SC.AddTyped(text)
    text = strtrim(text or "")
    if text == "" then return end
    -- Always a wildcard search, even for a full name: every mob whose name
    -- contains the text is found.
    -- Adding it again starts it fresh: names skipped last time (cleared finds)
    -- are found again.
    local mobs = SC.char.mobs
    if not mobs[text] then
        mobs[text] = { name = text }
        Fill(mobs[text], SC.MOB_DEFAULTS)
    end
    mobs[text].partial, mobs[text].rejected = true, {}
    SC.SetActive(text)
    SC.FindPartials()
    return mobs[text]
end

local function Replace(list, old, new)
    for i, n in ipairs(list) do
        if n == old then list[i] = new; return i end
    end
end

-- A found mob goes on the key right under its search.
local function AddFound(key, name)
    local list = SC.char.targets
    if #list >= SC.MAX_TARGETS then
        SC.Print("found |cffffffff" .. name .. "|r for \"" .. key .. "\", but that's " .. SC.MAX_TARGETS .. " targets already.")
        return false
    end
    local mobs = SC.char.mobs
    if not mobs[name] then
        mobs[name] = { name = name }
        Fill(mobs[name], SC.MOB_DEFAULTS)
        mobs[name].mode = mobs[key].mode
    end
    local m = mobs[name]
    m.fromPartial, m.hunting = key, true
    local at = SC.SlotOf(key) or #list
    -- after the search and the finds already under it
    while list[at + 1] and mobs[list[at + 1]] and mobs[list[at + 1]].fromPartial == key do at = at + 1 end
    table.insert(list, at + 1, name)
    for i, n in ipairs(SC.char.order) do
        if n == name then table.remove(SC.char.order, i); break end
    end
    table.insert(SC.char.order, 1, name)
    SC.Print("found |cffffffff" .. name .. "|r for \"" .. key .. "\" and added it. Clear it if it's not the one.")
    return true
end

-- A name seen in game: added for every search it matches.
function SC.MatchPartial(name)
    if type(name) ~= "string" or name == "" or not SC.char or SC.IsActive(name) then return end
    local low, hits = name:lower(), {}
    for key, m in pairs(SC.char.mobs) do
        if m.partial and key ~= name and SC.IsActive(key)
            and not (m.rejected and m.rejected[name]) and low:find(key:lower(), 1, true) then
            hits[#hits + 1] = key
        end
    end
    if #hits == 0 then return end
    local changed = false
    for _, key in ipairs(hits) do
        if SC.IsActive(name) then break end
        if AddFound(key, name) then changed = true end
    end
    if changed then
        SC.fastUnit = nil
        SC.ApplyBindings()
        if SC.PickLock then pcall(SC.PickLock) end
        if SC.EvalTarget then pcall(SC.EvalTarget) end
        SC.Refresh()
    end
end

function SC.FindPartials()
    for _, n in ipairs(SC.KnownNames()) do SC.MatchPartial(n) end
end

-- The search that found this mob, while that search is still around.
function SC.SearchOf(name)
    local m = SC.char.mobs[name]
    local key = m and m.fromPartial
    local s = key and SC.char.mobs[key]
    return (s and s.partial) and key or nil
end

-- "That's the one": keeps this mob, removes its search and the other mobs
-- that search added.
function SC.LockIn(name)
    local key = SC.SearchOf(name)
    if not key then return end
    local mobs, list = SC.char.mobs, SC.char.targets
    for i = #list, 1, -1 do
        local n = list[i]
        if n == key or (n ~= name and mobs[n] and mobs[n].fromPartial == key) then table.remove(list, i) end
    end
    for _, m in pairs(mobs) do
        if m.fromPartial == key then m.fromPartial = nil end
    end
    mobs[key] = nil
    for i, n in ipairs(SC.char.order) do
        if n == key then table.remove(SC.char.order, i); break end
    end
    if SC.char.selected == key then SC.char.selected = nil end
    SC.fastUnit = nil
    SC.ApplyBindings()
    if SC.PickLock then pcall(SC.PickLock) end
    if SC.EvalTarget then pcall(SC.EvalTarget) end
    SC.Refresh()
end

function SC.RemoveMob(name)
    local mobs = SC.char.mobs
    if not mobs[name] then return end
    mobs[name] = nil
    for i, n in ipairs(SC.char.order) do
        if n == name then table.remove(SC.char.order, i); break end
    end
    if SC.char.selected == name then
        SC.char.selected = nil
        if SC.char.panel == "mob" then SC.char.panel = nil end
    end
    local slot = SC.SlotOf(name)
    if slot then
        SC.SetActive(nil, slot)
        return
    end
    SC.ApplyBindings()
    SC.Refresh()
end

-- Called after anything changes.
function SC.Refresh()
    if SC.RefreshWindow then SC.RefreshWindow() end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local evFrame = CreateFrame("Frame")
local handlers = {}

function SC.EventValid(event)
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

-- Registers fn for event; returns false when the client doesn't have the event.
function SC.On(event, fn)
    if not SC.EventValid(event) then return false end
    if not handlers[event] then
        local ok = pcall(evFrame.RegisterEvent, evFrame, event)
        if not ok then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

evFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then SC.Print("|cffff4040error|r in " .. event .. ": " .. tostring(err)) end
    end
end)

------------------------------------------------------------------------------
-- Combat queue: secure buttons and bindings can only change out of combat.
------------------------------------------------------------------------------

local queued = {}

function SC.AfterCombat(fn)
    if not InCombatLockdown() then fn(); return end
    queued[fn] = true
end

SC.On("PLAYER_REGEN_ENABLED", function()
    local list = queued
    queued = {}
    for fn in pairs(list) do fn() end
end)

------------------------------------------------------------------------------
-- Units
------------------------------------------------------------------------------

-- npcID, spawnUID from a creature GUID: "Creature-0-server-instance-zone-npcID-spawnUID".
-- The spawn UID changes every respawn, which is what tells a new spawn apart.
function SC.ParseGUID(guid)
    guid = SC.Plain(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, npcID, spawn = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(npcID), spawn
end

-- A unit's name as a plain string, trying every source in turn, since Forever
-- can hide UnitName. Returns name, source ("UnitName", "tooltip", ...), or nil
-- and the reason the last source gave.
local function TooltipName(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or issecret(data) then return nil end
    local lines = data.lines
    if type(lines) ~= "table" or issecret(lines) or not lines[1] then return nil end
    local line = lines[1]
    if type(TooltipUtil) == "table" and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
    return SC.Plain(line.leftText)
end

local function GameTooltipName(unit)
    if unit ~= "mouseover" or not GameTooltip or not GameTooltip:IsShown() then return nil end
    local ok, _, tipUnit = pcall(GameTooltip.GetUnit, GameTooltip)
    if not ok or not tipUnit then return nil end
    local fs = _G.GameTooltipTextLeft1
    return fs and SC.Plain(fs:GetText()) or nil
end

local NAME_SOURCES = {
    { "UnitName", function(u) return UnitName(u) end },
    { "GetUnitName", function(u) return GetUnitName and GetUnitName(u, false) end },
    { "UnitNameUnmodified", function(u) return UnitNameUnmodified and UnitNameUnmodified(u) end },
    { "tooltip data", TooltipName },
    { "game tooltip", GameTooltipName },
}
SC.NAME_SOURCES = NAME_SOURCES

-- true when the unit exists or the game hides whether it does (then the name
-- reads decide).
function SC.MaybeExists(unit)
    local v = UnitExists(unit)
    if v == nil then return false end
    if issecret(v) then return true end
    return SC.True(v)
end

function SC.UnitNameSafe(unit)
    local why = "no name"
    for _, src in ipairs(NAME_SOURCES) do
        local ok, v = pcall(src[2], unit)
        if ok and v ~= nil then
            if issecret(v) then
                why = "hidden"
            elseif type(v) == "string" and v ~= "" and v ~= UNKNOWNOBJECT then
                return v, src[1]
            end
        end
    end
    return nil, why
end

-- Reads a unit if it's a watched mob. Returns name, mob, dead, spawn, tapDenied
-- (tapDenied: true = someone else's tag, false = yours or nobody's, nil = unknown).
function SC.ReadUnit(unit)
    local ok, name, mob, dead, spawn, tap = pcall(function()
        if not SC.MaybeExists(unit) then return end
        if SC.True(UnitIsPlayer(unit)) then return end
        local n = SC.UnitNameSafe(unit)
        if not n then return end
        local m = SC.char.mobs[n]
        if not m then return end
        local _, s = SC.ParseGUID(UnitGUID(unit))
        local d = SC.Bool(UnitIsDead(unit))
        local t = nil
        if UnitIsTapDenied then t = SC.Bool(UnitIsTapDenied(unit)) end
        return n, m, d, s, t
    end)
    if not ok then return nil end
    return name, mob, dead, spawn, tap
end

------------------------------------------------------------------------------
-- Formatting
------------------------------------------------------------------------------

function SC.Clock(sec)
    sec = math.floor(math.abs(sec or 0) + 0.5)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

------------------------------------------------------------------------------
-- Load
------------------------------------------------------------------------------

SC.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    SpawnCampDB = SpawnCampDB or {}
    SpawnCampDB.realms = SpawnCampDB.realms or {}
    SpawnCampDB.theme = SpawnCampDB.theme or "auto"   -- house kit look (Theme.lua)
    SpawnCampCharDB = SpawnCampCharDB or {}
    Fill(SpawnCampCharDB, SC.CHAR_DEFAULTS)
    SC.char = SpawnCampCharDB
    SC.db = SpawnCampDB
    -- A test rare left over from a /reload goes.
    for n, m in pairs(SC.char.mobs) do
        if m.test then SC.char.mobs[n] = nil end
    end
    -- Drop order entries whose mob is gone, add mobs missing from the order.
    local seen, order = {}, {}
    for _, n in ipairs(SC.char.order) do
        if SC.char.mobs[n] and not seen[n] then seen[n] = true; order[#order + 1] = n end
    end
    -- 0.3 kept key/spell/quest options per mob, 0.4 had an Attack and a Talk key;
    -- now there's one key (SC.char.key) and shared attack/interact settings.
    local A, I = SC.char.attack, SC.char.interact
    for _, k in ipairs({ A.key or "", I.key or "" }) do
        if SC.char.key == "" and k ~= "" then SC.char.key = k end
    end
    A.key, I.key, I.how = nil, nil, nil
    -- 0.26: typed macro lines became a pick from your saved macros.
    if type(A.macro) == "string" and strtrim(A.macro) ~= "" then
        A.oldMacro = A.macro
        SC.Print("your typed attack macro was kept in the saved file but isn't used any more. Make it in /m and pick it under Attack options > Macro.")
    end
    A.macro = nil
    -- 0.7: one "share" box became party/raid/guild; reward 0 (ask) became 1 (first).
    if SC.char.share == false then
        SC.char.shareParty, SC.char.shareRaid, SC.char.shareGuild = false, false, false
    end
    SC.char.share = nil
    if not I.rewardV then
        if I.reward == 0 then I.reward = 1 end
        I.rewardV = 2
    end
    -- 0.32.3: lower-case names never seen in game were typed searches saved as
    -- exact names (see SC.WasSeen). Game NPC names start with a capital.
    for n, m in pairs(SC.char.mobs) do
        if not m.partial and not m.test and n:find("^%l") and not SC.WasSeen(n) then
            m.partial, m.rejected = true, m.rejected or {}
            SC.Print("\"" .. n .. "\" is a search again: it adds every mob seen with that in its name.")
        end
    end
    for n, m in pairs(SC.char.mobs) do
        m.name = n
        if m.mode == "macro" then m.mode = "attack" end
        if m.key ~= nil then
            if SC.char.key == "" and m.key ~= "" then SC.char.key = m.key end
            if m.mode == "attack" and A.spell == "" and m.spell and m.spell ~= "" then A.spell = m.spell end
            if m.armed == false then m.hunting = false end
        end
        -- 0.4/0.5 allowed no mode (timer only); that's now "attack" off the key.
        if m.mode == nil then
            m.mode = "attack"
            m.hunting = false
        end
        for _, old in ipairs({ "key", "spell", "macro", "interact", "armed", "autoQuest", "onlyOption", "gossip", "reward" }) do
            m[old] = nil
        end
        Fill(m, SC.MOB_DEFAULTS)
        if not seen[n] then order[#order + 1] = n end
    end
    SC.char.order = order
    -- 0.8-0.15 had one or two targets (active, active2); now a list.
    SC.char.targets = SC.char.targets or {}
    for _, n in ipairs({ SC.char.active, SC.char.active2 }) do
        if n and not SC.SlotOf(n) then table.insert(SC.char.targets, n) end
    end
    SC.char.active, SC.char.active2 = nil, nil
    for i = #SC.char.targets, 1, -1 do
        if not SC.char.mobs[SC.char.targets[i]] then table.remove(SC.char.targets, i) end
    end
    SC.char.expanded, SC.char.tab, SC.char.showTimers = nil, nil, nil
    SC.char.layout = nil   -- 0.36 had a layout choice; there's one layout now
    SC.char.theme = nil    -- 0.35-0.37 had its own skin; the house kit's look (SpawnCampDB.theme) replaced it
end)

SC.On("PLAYER_LOGIN", function()
    SC.ApplyBindings()
    SC.Refresh()
end)

-- When the game blocks one of SpawnCamp's calls, say which and keep the last
-- few in SpawnCampDB.blocked, so it can be fixed without guessing.
local lastBlockedAt
local function Blocked(kind)
    return function(addon, func)
        if addon ~= ADDON then return end
        local what = string.format("%s %s: %s", date("%m-%d %H:%M:%S"), kind, tostring(func))
        local now = GetTime()
        if not lastBlockedAt or now - lastBlockedAt > 30 then
            SC.Print("|cffff4040the game blocked|r " .. tostring(func) .. ". Please tell Dranged.")
        end
        lastBlockedAt = now
        if SpawnCampDB then
            SpawnCampDB.blocked = SpawnCampDB.blocked or {}
            table.insert(SpawnCampDB.blocked, what)
            while #SpawnCampDB.blocked > 10 do table.remove(SpawnCampDB.blocked, 1) end
        end
    end
end
SC.On("ADDON_ACTION_FORBIDDEN", Blocked("forbidden"))
SC.On("ADDON_ACTION_BLOCKED", Blocked("blocked"))

------------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------------

local function Help()
    SC.Print("commands:")
    print("  /spawncamp - show or hide the window")
    print("  /spawncamp settings - open the settings (keys, spell, talk options)")
    print("  /spawncamp add [name] - watch your target, or a mob by name")
    print("  /spawncamp died [name] - log a death now (selected mob if no name)")
    print("  /spawncamp up [name] - log a spawn now")
    print("  /spawncamp probe - print and save what the addon can read (target, mouseover, a nameplate)")
    print("  /spawncamp key - the key's mode, its macro, and the last presses")
    print("  /spawncamp vignettes - list the minimap vignettes (rare stars) the game gives addons")
end

local function MobArg(rest)
    rest = rest and strtrim(rest) or ""
    if rest ~= "" then return SC.char.mobs[rest] and rest or nil end
    return SC.char.selected
end

SLASH_SPAWNCAMP1 = "/spawncamp"
SLASH_SPAWNCAMP2 = "/spc"
SlashCmdList.SPAWNCAMP = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        SC.ToggleWindow()
    elseif cmd == "add" then
        if rest ~= "" then
            SC.AddMob(rest)
        else
            SC.AddTarget()
        end
        SC.char.shown = true
        SC.Refresh()
    elseif cmd == "died" or cmd == "up" then
        local n = MobArg(rest)
        if not n then SC.Print("no such mob being watched"); return end
        SC.Observe(n, cmd == "died" and "D" or "A", nil, nil, "you", { manual = true })
        SC.Refresh()
    elseif cmd == "settings" or cmd == "config" or cmd == "more" then
        SC.char.shown = true
        SC.char.panel = SC.char.panel ~= "settings" and "settings" or nil
        SC.Refresh()
    elseif cmd == "key" then
        SC.Print("key mode: " .. select(2, SC.KeyState()))
        local text = SC.KeyMacro()
        print(string.format("  macro (%d of %d characters%s): %s", #text, SC.MACRO_MAX,
            (SC.keyDropped or 0) > 0 and (", " .. SC.keyDropped .. " lowest searches left out") or "",
            (text:gsub("\n", " ; "))))
        for _, line in ipairs(SpawnCampDB.keyLog or {}) do print("  " .. line) end
    elseif cmd == "debug" or cmd == "probe" then
        SC.Debug()
    elseif cmd == "vignettes" then
        if SC.VignetteReport then SC.VignetteReport() end
    else
        Help()
    end
end

function SC.AddTarget()
    if not SC.MaybeExists("target") then
        SC.Print("no target: type the mob's name and press Enter.")
        if SC.FocusAddName then SC.FocusAddName() end
        return
    end
    if SC.True(UnitIsPlayer("target")) then
        SC.Print("that's a player. Target a mob.")
        return
    end
    local name = SC.UnitNameSafe("target")
    if not name then
        -- Forever hides NPC names from addons: ask for it typed, mode from what is readable.
        SC.Print("the game hides this NPC's name from addons here (dungeons do). Type it exactly as your target frame shows it and press Enter.")
        if SC.FocusAddName then SC.FocusAddName() end
        return
    end
    local friendly = SC.Bool(UnitCanAttack("player", "target")) == false
    SC.AddMob(name, friendly and "interact" or "attack")
    if SC.CapturePortrait then SC.CapturePortrait(name, "target") end
end

-- /spc probe: every read the addon relies on, for target, mouseover and the
-- first nameplate. Printed and saved to SpawnCampDB.probe (read after /reload).
function SC.Debug()
    local out = {}
    local function line(s) out[#out + 1] = s; print("  " .. s) end
    local function show(f, ...)
        local ok, v = pcall(f, ...)
        if not ok then return "ERROR " .. tostring(v) end
        if v == nil then return "nil" end
        if issecret(v) then return "SECRET" end
        return type(v) == "string" and ('"' .. v .. '"') or tostring(v)
    end
    SC.Print("probe (also saved; /reload to write it to disk):")
    line("in combat " .. tostring(InCombatLockdown()) .. ", issecretvalue " .. tostring(issecretvalue ~= nil)
        .. ", canaccessvalue " .. tostring(canaccessvalue ~= nil) .. ", C_TooltipInfo " .. tostring(C_TooltipInfo ~= nil))
    local plate = "nameplate1"
    for i = 1, 40 do
        local ok, v = pcall(UnitExists, "nameplate" .. i)
        if ok and v ~= nil and (issecret(v) or v) then plate = "nameplate" .. i; break end
    end
    for _, unit in ipairs({ "target", "mouseover", plate }) do
        line("[" .. unit .. "] exists " .. show(UnitExists, unit) .. ", player " .. show(UnitIsPlayer, unit)
            .. ", dead " .. show(UnitIsDead, unit) .. ", canAttack " .. show(UnitCanAttack, "player", unit))
        line("  guid " .. show(UnitGUID, unit) .. ", level " .. show(UnitLevel, unit)
            .. ", class " .. show(UnitClassification, unit))
        local names = {}
        for _, src in ipairs(NAME_SOURCES) do names[#names + 1] = src[1] .. " " .. show(src[2], unit) end
        line("  " .. table.concat(names, ", "))
        local n, why = SC.UnitNameSafe(unit)
        line("  -> name used: " .. (n and ('"' .. n .. '"') or ("none (" .. why .. ")")))
    end
    if SC.ScanNearby then line("nearby scan: " .. SC.ScanNearby()) end
    local b = SpawnCampDB.blocked
    if b and b[1] then line("last blocked action: " .. b[#b]) end
    SpawnCampDB.probe = { time = date("%Y-%m-%d %H:%M:%S"), lines = out }
end

function SpawnCamp_OnCompartmentClick()
    SC.ToggleWindow()
end
