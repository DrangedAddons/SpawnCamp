-- Questie map pins for a target. Does what Questie's own Advanced Search
-- "Show on Map" button does: QuestieMap:ShowNPC for each NPC id, which pins
-- every spawn on the world map and the minimap. "Remove" unloads those pins.
-- Questie's database is looked up by name: exact for a mob, "contains" for a
-- typed search. Optional: without Questie the button isn't shown.

local _, SC = ...

local MAX_IDS = 40          -- a short search ("a") would match half the game
local shown = {}            -- target name -> { npc ids pinned }
SC.questiePins = shown

local function Modules()
    local loader = rawget(_G, "QuestieLoader")
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return end
    local okM, map = pcall(loader.ImportModule, loader, "QuestieMap")
    local okD, db = pcall(loader.ImportModule, loader, "QuestieDB")
    if not (okM and okD and map and db) then return end
    if type(map.ShowNPC) ~= "function" or type(map.UnloadManualFrames) ~= "function" then return end
    if type(db.NPCPointers) ~= "table" or type(db.QueryNPCSingle) ~= "function" then return end
    return map, db
end

-- Questie is loaded and its database is ready.
function SC.QuestieReady()
    return Modules() ~= nil
end

-- Questie's database and zone modules, for Dungeon.lua. nil until Questie is ready.
function SC.QuestieDBs()
    local _, db = Modules()
    if not db then return end
    local ok, zones = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    return db, ok and zones or nil
end

-- NPC ids in Questie's database for a target: the exact name (any capitals),
-- or every name containing a search's text. Only NPCs with spawns.
function SC.QuestieIds(name, partial)
    local _, db = Modules()
    if not db or type(name) ~= "string" or name == "" then return {} end
    local want, out = name:lower(), {}
    for id in pairs(db.NPCPointers) do
        local ok, n = pcall(db.QueryNPCSingle, id, "name")
        if ok and type(n) == "string" then
            local low = n:lower()
            if (partial and low:find(want, 1, true)) or (not partial and low == want) then
                local okS, spawns = pcall(db.QueryNPCSingle, id, "spawns")
                if okS and type(spawns) == "table" and next(spawns) then
                    out[#out + 1] = id
                    if #out >= MAX_IDS then break end
                end
            end
        end
    end
    table.sort(out)
    return out
end

function SC.QuestieShown(name)
    return shown[name] ~= nil
end

-- Pins or unpins a target's spawns. Returns a line for chat.
function SC.QuestieToggle(name)
    local map = Modules()
    if not map then return "Questie isn't loaded (or still starting)." end
    if shown[name] then
        for _, id in ipairs(shown[name]) do pcall(map.UnloadManualFrames, map, id) end
        shown[name] = nil
        SC.Refresh()
        return "removed " .. name .. " from your map."
    end
    local m = SC.char.mobs[name]
    local ids = SC.QuestieIds(name, m and m.partial)
    if #ids == 0 then return "Questie has no spawns for \"" .. name .. "\"." end
    for _, id in ipairs(ids) do pcall(map.ShowNPC, map, id) end
    shown[name] = ids
    SC.Refresh()
    local more = #ids >= MAX_IDS and " (first " .. MAX_IDS .. "; type more of the name to narrow it)" or ""
    return "showing " .. name .. " on your map and minimap: " .. #ids .. " NPC" .. (#ids == 1 and "" or "s") .. more .. "."
end

-- A target leaving the list takes its pins with it.
function SC.QuestieForget(name)
    if shown[name] then SC.QuestieToggle(name) end
end
