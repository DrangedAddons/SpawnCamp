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

local issecret = issecretvalue or function() return false end
SC.issecret = issecret

-- The value, or nil when it's missing or secret.
function SC.Plain(v)
    if v == nil or issecret(v) then return nil end
    return v
end

-- true only for a plain true; secret booleans count as false.
function SC.True(v)
    return v ~= nil and not issecret(v) and v == true
end

function SC.Print(msg)
    print("|cffff9933SpawnCamp|r " .. tostring(msg))
end

------------------------------------------------------------------------------
-- Defaults
------------------------------------------------------------------------------

SC.CHAR_DEFAULTS = {
    mobs = {},            -- name -> mob settings (MOB_DEFAULTS)
    order = {},           -- names in list order
    selected = nil,
    share = true,         -- send and receive sightings with party/raid and guild
    showTimers = true,    -- the small timer list
    sound = true,         -- play a sound with alerts
    minimap = { hide = false },
}

SC.MOB_DEFAULTS = {
    mode = "attack",      -- "attack" or "interact"
    spell = "",           -- attack: instant spell to cast; empty = auto attack only
    interact = "target",  -- interact: "target" (by name), "mouseover", "nearest" (game Interact key)
    key = "",             -- binding, e.g. "SHIFT-F"
    armed = true,         -- the key is active
    hunting = true,       -- still after this one; unticked once you get the kill
    alertSpawn = true,    -- alert when it's seen alive
    alarm = true,         -- alarm before the expected respawn
    lead = 60,            -- seconds before the earliest expected respawn
    manualMin = 0,        -- minutes; >0 overrides the history's earliest respawn
    manualMax = 0,        -- minutes; >0 overrides the history's latest respawn
    autoQuest = true,     -- interact: accept and hand in its quests
    onlyOption = true,    -- interact: pick the chat option when there's only one
    gossip = "",          -- interact: chat options to pick, one text match per line
    reward = 0,           -- interact: quest reward choice when there are several (0 = ask)
}

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
        if mode then mobs[name].mode = mode end
        table.insert(SC.char.order, name)
    end
    SC.char.selected = name
    SC.ApplyBindings()
    SC.Refresh()
    return mobs[name]
end

function SC.RemoveMob(name)
    local mobs = SC.char.mobs
    if not mobs[name] then return end
    mobs[name] = nil
    for i, n in ipairs(SC.char.order) do
        if n == name then table.remove(SC.char.order, i); break end
    end
    if SC.char.selected == name then SC.char.selected = SC.char.order[1] end
    SC.ApplyBindings()
    SC.Refresh()
end

-- Called after anything changes; UI files replace these.
function SC.Refresh()
    if SC.RefreshWindow then SC.RefreshWindow() end
    if SC.RefreshTimers then SC.RefreshTimers() end
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

-- Reads a unit if it's a watched mob. Returns name, mob, dead, spawn, tapDenied
-- (tapDenied: true = someone else's tag, false = yours or nobody's, nil = unknown).
function SC.ReadUnit(unit)
    local ok, name, mob, dead, spawn, tap = pcall(function()
        if not SC.True(UnitExists(unit)) then return end
        if SC.True(UnitIsPlayer(unit)) then return end
        local n = SC.Plain(UnitName(unit))
        if not n then return end
        local m = SC.char.mobs[n]
        if not m then return end
        local _, s = SC.ParseGUID(UnitGUID(unit))
        local d = SC.Plain(UnitIsDead(unit))
        local t = SC.Plain(UnitIsTapDenied and UnitIsTapDenied(unit))
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
    for n, m in pairs(SC.char.mobs) do
        m.name = n
        Fill(m, SC.MOB_DEFAULTS)
        if not seen[n] then order[#order + 1] = n end
    end
    SC.char.order = order
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
    print("  /spawncamp - open the window")
    print("  /spawncamp add [name] - watch your target, or a mob by name")
    print("  /spawncamp died [name] - log a death now (selected mob if no name)")
    print("  /spawncamp up [name] - log a spawn now")
    print("  /spawncamp timers - show or hide the timer list")
    print("  /spawncamp debug - print what the addon can read from your target")
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
        SC.ShowWindow()
    elseif cmd == "died" or cmd == "up" then
        local n = MobArg(rest)
        if not n then SC.Print("no such mob being watched"); return end
        SC.Observe(n, cmd == "died" and "D" or "A", nil, nil, "you", { manual = true })
        SC.Refresh()
    elseif cmd == "timers" then
        SC.char.showTimers = not SC.char.showTimers
        SC.Refresh()
    elseif cmd == "debug" then
        SC.Debug()
    else
        Help()
    end
end

function SC.AddTarget()
    local name = SC.Plain(UnitName("target"))
    if not name or SC.True(UnitIsPlayer("target")) then
        SC.Print("target a mob first (or type its name)")
        return
    end
    local friendly = SC.Plain(UnitCanAttack("player", "target")) == false
    SC.AddMob(name, friendly and "interact" or "attack")
end

function SC.Debug()
    local function show(v)
        if v == nil then return "nil" end
        if issecret(v) then return "SECRET" end
        return tostring(v)
    end
    SC.Print("target reads:")
    print("  exists " .. show(UnitExists("target")) .. ", name " .. show(UnitName("target")))
    print("  guid " .. show(UnitGUID("target")))
    print("  dead " .. show(UnitIsDead("target")) .. ", tapDenied " .. show(UnitIsTapDenied and UnitIsTapDenied("target")))
    print("  canAttack " .. show(UnitCanAttack("player", "target")) .. ", in combat " .. tostring(InCombatLockdown()))
    print("  server time " .. tostring(GetServerTime()))
end

function SpawnCamp_OnCompartmentClick()
    SC.ToggleWindow()
end
