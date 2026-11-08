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
    selected = nil,       -- mob shown in the details panel
    panel = nil,          -- nil, "mob" (details) or "settings"
    key = "",             -- the one SpawnCamp key, for every mob with a sword or bubble
    attack = {
        spell = "",       -- instant spell; empty = auto attack only
        macro = "",       -- optional custom attack lines, replacing the spell lines
    },
    interact = {
        autoQuest = true, -- hand in finished quests, accept new and follow-up ones
        gossip = true,    -- click through chat options
        prefer = "",      -- chat options to pick first, one text match per line
        reward = 1,       -- reward choice when a quest offers several (0 = you pick)
    },
    shareParty = true,    -- send and receive sightings with your party
    shareRaid = true,     -- ... your raid
    shareGuild = true,    -- ... your guild
    shown = true,         -- the window is on screen
    showDone = true,      -- keep mobs you already got on the list
    locked = false,       -- window can't be dragged
    sound = true,         -- play a sound with alerts
    minimap = { hide = false },
}

SC.MOB_DEFAULTS = {
    mode = "attack",      -- "attack" (sword) or "interact" (bubble); always one of the two
    hunting = true,       -- on the key; turned off once you get the kill
    alertSpawn = true,    -- alert when it's seen alive
    alarm = true,         -- alarm before the expected respawn
    lead = 60,            -- seconds before the earliest expected respawn
    manualMin = 0,        -- minutes; >0 overrides the history's earliest respawn
    manualMax = 0,        -- minutes; >0 overrides the history's latest respawn
}

-- The selected target: the one mob the key works on. nil = the key does nothing.
function SC.Active()
    local n = SC.char and SC.char.active
    return n and SC.char.mobs[n] or nil
end

-- The selected target as a list when it's in this mode, else an empty list.
function SC.MobsIn(mode)
    local m = SC.Active()
    if m and m.mode == mode then return { m } end
    return {}
end

-- Makes a mob the selected target and moves it to the top of the recent list.
function SC.SetActive(name)
    if name and not SC.char.mobs[name] then return end
    SC.char.active = name
    if name then
        local m = SC.char.mobs[name]
        m.hunting = true
        for i, n in ipairs(SC.char.order) do
            if n == name then table.remove(SC.char.order, i); break end
        end
        table.insert(SC.char.order, 1, name)
    end
    SC.ApplyBindings()
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
    if SC.char.active == name then SC.char.active = nil end
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
    SpawnCampCharDB = SpawnCampCharDB or {}
    Fill(SpawnCampCharDB, SC.CHAR_DEFAULTS)
    SC.char = SpawnCampCharDB
    SC.db = SpawnCampDB
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
    -- 0.7: one "share" box became party/raid/guild; reward 0 (ask) became 1 (first).
    if SC.char.share == false then
        SC.char.shareParty, SC.char.shareRaid, SC.char.shareGuild = false, false, false
    end
    SC.char.share = nil
    if not I.rewardV then
        if I.reward == 0 then I.reward = 1 end
        I.rewardV = 2
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
    if SC.char.active and not SC.char.mobs[SC.char.active] then SC.char.active = nil end
    SC.char.expanded, SC.char.tab, SC.char.showTimers = nil, nil, nil
end)

SC.On("PLAYER_LOGIN", function()
    SC.ApplyBindings()
    SC.Refresh()
end)

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
    elseif cmd == "debug" or cmd == "probe" then
        SC.Debug()
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
    local cl = SC.combatLog
    if cl then
        line(string.format("combat log: registered %s, events seen %d, death names hidden %d",
            tostring(cl.registered), cl.seen, cl.hidden))
    end
    SpawnCampDB.probe = { time = date("%Y-%m-%d %H:%M:%S"), lines = out }
end

function SpawnCamp_OnCompartmentClick()
    SC.ToggleWindow()
end
