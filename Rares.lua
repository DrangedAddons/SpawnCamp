-- Rare pop-up. No list. A rare is found two ways:
--   vignette   the minimap star the game shows for a rare, from further out
--              than nameplates (C_VignetteInfo; only if Forever has them).
--   nameplate  UnitClassification "rare" / "rareelite", within nameplate range.
-- Whichever comes first announces it and adds a target box at the top (silver
-- frame). The box puts it on the key, so the key's name search targets it once
-- it's in reach. Clearing that box stops it popping up again this session.

local _, SC = ...

local IS_RARE = { rare = true, rareelite = true }
local ALERT_AGAIN = 300            -- seconds before the same rare alerts again
local alerted = {}
SC.rareDismissed = {}              -- name -> true once you Clear its box (session only)

function SC.IsRareClass(cls) return IS_RARE[cls] == true end

function SC.SilverDragonOn()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return f and f("SilverDragon") and true or false
end

-- Adds the rare as target 1, opens the window and alerts. where = extra text
-- for the alert (direction and distance from a vignette), or nil.
local function Found(name, cls, ctype, where, how)
    if not SC.char.rareAlert or SC.IsActive(name) or SC.rareDismissed[name] then return end
    local now = GetTime()
    if alerted[name] and now - alerted[name] < ALERT_AGAIN then return end
    alerted[name] = now
    if #SC.Targets() < SC.MAX_TARGETS then
        local m = SC.AddMob(name, "attack")
        if m then
            m.rare, m.rareAuto = cls, true
            if type(ctype) == "string" then m.ctype = ctype end
            -- Top of the list, so the key goes for it first.
            local list = SC.char.targets
            for i, n in ipairs(list) do
                if n == name then table.remove(list, i); break end
            end
            table.insert(list, 1, name)
            SC.fastUnit = nil
            SC.ApplyBindings()
            if SC.EvalTarget then pcall(SC.EvalTarget) end
        end
    end
    SC.char.shown = true
    if not SC.SilverDragonOn() then
        SC.Alert((cls == "rareelite" and "Rare elite " or "Rare ") .. how .. ": " .. name .. (where and ("  " .. where) or ""))
    end
    SC.Refresh()
end

-- Called from NoteNearby for every NPC read. e = the nearby entry.
function SC.NoteRare(name, e)
    if not SC.char or not IS_RARE[e.class] then return end
    local m = SC.char.mobs[name]
    if m then m.rare = e.class end
    if e.dead or e.hostile == false then return end
    Found(name, e.class, e.ctype, nil, "nearby")
end

------------------------------------------------------------------------------
-- Vignettes
------------------------------------------------------------------------------

local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- "~140 yd NE" from you to a vignette, or nil if the map can't say.
local function Where(guid)
    if not (C_Map and C_Map.GetBestMapForUnit and C_VignetteInfo.GetVignettePosition) then return end
    local map = SC.Plain(C_Map.GetBestMapForUnit("player"))
    if not map then return end
    local ok, vp = pcall(C_VignetteInfo.GetVignettePosition, guid, map)
    local pp = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not (ok and vp and pp) then return end
    local vx, vy = vp:GetXY()
    local px, py = pp:GetXY()
    vx, vy, px, py = SC.Plain(vx), SC.Plain(vy), SC.Plain(px), SC.Plain(py)
    if not (vx and px) then return end
    local w, h
    if C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(map) end
    local dx, dy = vx - px, vy - py               -- map y grows southwards
    local dir = DIRS[math.floor((math.deg(math.atan2(dx, -dy)) + 22.5) % 360 / 45) + 1]
    if type(w) == "number" and w > 0 and type(h) == "number" then
        local yd = math.floor(math.sqrt((dx * w) ^ 2 + (dy * h) ^ 2) / 10 + 0.5) * 10
        return string.format("~%d yd %s", yd, dir)
    end
    return dir
end
SC.VignetteWhere = Where

local function IsMobVignette(info)
    local atlas = SC.Plain(info.atlasName)
    local guid = SC.Plain(info.objectGUID)
    if type(atlas) == "string" and atlas:find("Loot", 1, true) then return false end
    if type(guid) == "string" then return guid:find("^Creature") ~= nil end
    return type(atlas) == "string" and atlas:find("Kill", 1, true) ~= nil
end

function SC.ScanVignettes()
    if not (SC.char and C_VignetteInfo and C_VignetteInfo.GetVignettes) then return end
    local ok, list = pcall(C_VignetteInfo.GetVignettes)
    if not ok or type(list) ~= "table" then return end
    for _, guid in ipairs(list) do
        local okI, info = pcall(C_VignetteInfo.GetVignetteInfo, guid)
        if okI and type(info) == "table" and SC.True(info.onMinimap) and IsMobVignette(info) then
            local name = SC.Plain(info.name)
            if type(name) == "string" and name ~= "" then
                local atlas = SC.Plain(info.atlasName)
                local cls = (type(atlas) == "string" and atlas:find("Elite", 1, true)) and "rareelite" or "rare"
                local m = SC.char.mobs[name]
                if m and not m.rare then m.rare = cls end
                Found(name, cls, nil, Where(guid), "spotted")
            end
        end
    end
end

for _, ev in ipairs({ "VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED" }) do
    if SC.EventValid(ev) then SC.On(ev, function() SC.ScanVignettes() end) end
end

-- /spc vignettes: everything C_VignetteInfo returns right now.
function SC.VignetteReport()
    if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then
        SC.Print("this client has no vignette API, so rares are only found by nameplate.")
        return
    end
    local ok, list = pcall(C_VignetteInfo.GetVignettes)
    if not ok or type(list) ~= "table" then SC.Print("vignettes: couldn't read the list"); return end
    SC.Print(#list .. " vignette" .. (#list == 1 and "" or "s") .. " right now:")
    for _, guid in ipairs(list) do
        local okI, info = pcall(C_VignetteInfo.GetVignetteInfo, guid)
        if okI and type(info) == "table" then
            print(string.format("  %s  atlas=%s  minimap=%s  mob=%s  %s",
                tostring(SC.Plain(info.name) or "?"), tostring(SC.Plain(info.atlasName)),
                tostring(SC.Plain(info.onMinimap)), tostring(IsMobVignette(info)), tostring(Where(guid) or "")))
        end
    end
end
