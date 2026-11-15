-- Auto > Totem / Ward: the key goes for an enemy totem or ward first, before
-- your own targets, and back to them once it's gone.
--
-- Totems drop mid-fight, and in combat the key's macro is frozen, so the
-- totem lines have to be in the macro before the pull. The key clicks one of
-- two hidden buttons first on every press. On a mob (or locked on one):
--
--   SpawnCampTotem:  /cleartarget
--                    /targetexact [noexists] Lava Spout Totem
--                    /targetexact [noexists] Searing Totem
--                    /targetlasttarget [noexists]
--                    /cleartarget [noharm]
--
-- Each name only runs while nothing is targeted yet, so a miss can't undo an
-- earlier hit, whatever the game does on a miss. No totem up: back to the mob
-- you were on. While the key is searching (target already cleared) it clicks
-- SpawnCampTotemFind: the same without the clear and the restore.
-- [noharm] drops a friendly totem of the same name (a party shaman's).
--
-- The names: every enemy nameplate of the game's Totem creature type (wards
-- are totems too) is remembered for the zone it was seen in, in
-- SpawnCampDB.totems. One seen mid-fight joins the key when that fight ends.
-- In a dungeon names can't be read, so the dungeon's list (Dungeon.lua, with
-- DungeonData.lua's summons) supplies its totems and wards from the start.

local _, SC = ...

local MACRO_MAX = 255
local TOTEM_TYPE = 11            -- creature type id for Totem

local function NewButton(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:SetSize(1, 1)
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    b:SetAlpha(0)
    b:EnableMouse(false)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    b:Show()
    return b
end
local btn = NewButton("SpawnCampTotem")          -- keeps your target when no totem is up
local findBtn = NewButton("SpawnCampTotemFind")  -- for the search, target already cleared
SC.totemText, SC.totemFindText = "", ""

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

-- Totem and ward names the key goes for here: the dungeon's totems and wards,
-- then the ones seen in this zone.
function SC.TotemNames()
    local out, seen = {}, {}
    local function add(n)
        if not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    local d = SC.dungeon
    for _, m in ipairs(d and d.mobs or {}) do
        if m.totem then add(m.name) end
    end
    local k = ZoneKey()
    local learned = k and SpawnCampDB and SpawnCampDB.totems and SpawnCampDB.totems[k]
    local names = {}
    for n in pairs(learned or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do add(n) end
    return out
end

-- Rebuilds the totem button. Out of combat only (ApplyBindings calls it).
function SC.WriteTotemButton()
    if InCombatLockdown() then return end
    local text, find = "", ""
    if SC.char and SC.char.autoTotem then
        -- Sized for the longer one (the keep button's extra lines).
        local head, restore, tail = "/cleartarget", "/targetlasttarget [noexists]", "/cleartarget [noharm]"
        local lines, len = {}, #head + 1 + #restore + 1 + #tail
        for _, n in ipairs(SC.TotemNames()) do
            local line = "/targetexact [noexists] " .. n
            if len + #line + 1 > MACRO_MAX then break end
            lines[#lines + 1] = line
            len = len + #line + 1
        end
        if #lines > 0 then
            local names = table.concat(lines, "\n")
            text = table.concat({ head, names, restore, tail }, "\n")
            find = names .. "\n" .. tail
        end
    end
    btn:SetAttribute("macrotext", text)
    findBtn:SetAttribute("macrotext", find)
    SC.totemText, SC.totemFindText = text, find
end

-- The totem the key is on: your target, when it's an enemy totem with a
-- readable name. nil otherwise.
function SC.TotemShown()
    if not (SC.MaybeExists("target") and SC.IsTotem("target")) then return nil end
    if SC.Bool(UnitCanAttack("player", "target")) ~= true or SC.Bool(UnitIsDead("target")) ~= false then return nil end
    return SC.UnitNameSafe("target")
end

-- The key macro's line for a totem button, or nil when it has nothing.
-- find: the key is searching (target already cleared), so no restore.
function SC.TotemClick(find)
    if SC.totemText == "" then return nil end
    return find and "/click SpawnCampTotemFind" or "/click SpawnCampTotem"
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
    line("totem button: " .. (SC.totemText ~= "" and (SC.totemText:gsub("\n", " ; ")) or "(empty)"))
    for _, b in ipairs({ { "SpawnCampTotem", btn }, { "SpawnCampTotemFind", findBtn } }) do
        local t = b[2]:GetAttribute("macrotext")
        t = type(t) == "string" and t or ""
        line("live " .. b[1] .. ": " .. (t ~= "" and (t:gsub("\n", " ; ")) or "(empty)"))
    end
    local kb = _G.SpawnCampKey
    local live = type(kb) == "table" and kb.GetAttribute and kb:GetAttribute("macrotext") or ""
    if type(live) ~= "string" then live = "" end
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

SC._totem = { button = btn, find = findBtn }
