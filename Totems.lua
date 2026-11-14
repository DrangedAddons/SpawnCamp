-- Auto > Totem / Ward: the key goes for an enemy totem or ward first, before
-- your own targets, and back to them once it's gone.
--
-- Totems drop mid-fight, and in combat the key's macro is frozen, so the
-- totem lines have to be in the macro before the pull. The key clicks a
-- hidden button first on every press:
--
--   SpawnCampTotem:  /targetexact Lava Spout Totem
--                    /targetexact Searing Totem
--                    /cleartarget [noharm]
--
-- /targetexact with no match leaves your target alone, so with no totem up
-- the rest of the key runs as before. [noharm] drops a friendly totem of the
-- same name (a party shaman's Searing Totem).
--
-- The names: every enemy nameplate of the game's Totem creature type (wards
-- are totems too) is remembered for the zone it was seen in, in
-- SpawnCampDB.totems. One seen mid-fight joins the key when that fight ends.
-- In a dungeon names can't be read, so the dungeon's list (Dungeon.lua, with
-- DungeonData.lua's summons) supplies its totems and wards from the start.

local _, SC = ...

local MACRO_MAX = 255
local TOTEM_TYPE = 11            -- creature type id for Totem

local btn = CreateFrame("Button", "SpawnCampTotem", UIParent, "SecureActionButtonTemplate")
btn:SetSize(1, 1)
btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
btn:SetAlpha(0)
btn:EnableMouse(false)
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("useOnKeyDown", false)
btn:SetAttribute("type", "macro")
btn:SetAttribute("macrotext", "")
btn:Show()
SC.totemText = ""

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
    local text = ""
    if SC.char and SC.char.autoTotem then
        local tail = "/cleartarget [noharm]"
        local lines, len = {}, #tail
        for _, n in ipairs(SC.TotemNames()) do
            local line = "/targetexact " .. n
            if len + #line + 1 > MACRO_MAX then break end
            lines[#lines + 1] = line
            len = len + #line + 1
        end
        if #lines > 0 then
            lines[#lines + 1] = tail
            text = table.concat(lines, "\n")
        end
    end
    btn:SetAttribute("macrotext", text)
    SC.totemText = text
end

-- The key macro's line for the totem button, or nil when it has nothing.
function SC.TotemClick()
    if SC.totemText ~= "" then return "/click SpawnCampTotem" end
end

function SC.SetAutoTotem(on)
    SC.char.autoTotem = on and true or false
    SC.ApplyBindings()
    if SC.Refresh then SC.Refresh() end
end

-- Zone changes change the list.
SC.On("ZONE_CHANGED_NEW_AREA", function() if SC.char then SC.ApplyBindings() end end)
SC.On("PLAYER_ENTERING_WORLD", function() if SC.char then SC.ApplyBindings() end end)

SC._totem = { button = btn }
