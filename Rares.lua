-- Rare pop-up. No list: a nameplate whose UnitClassification is "rare" or
-- "rareelite" is a rare. When one shows up alive and hostile, it becomes a
-- target box at the top (silver frame) and a loud alert goes off. Clearing that
-- box stops it popping up again this session.

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

-- Called from NoteNearby for every NPC read. e = the nearby entry.
function SC.NoteRare(name, e)
    if not SC.char or not IS_RARE[e.class] then return end
    local m = SC.char.mobs[name]
    if m then m.rare = e.class end
    if e.dead or e.hostile == false or not SC.char.rareAlert then return end
    if SC.IsActive(name) or SC.rareDismissed[name] then return end
    local now = GetTime()
    if alerted[name] and now - alerted[name] < ALERT_AGAIN then return end
    alerted[name] = now
    if #SC.Targets() < SC.MAX_TARGETS then
        m = SC.AddMob(name, "attack")
        if m then
            m.rare, m.rareAuto = e.class, true
            if type(e.ctype) == "string" then m.ctype = e.ctype end
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
        SC.Alert((e.class == "rareelite" and "Rare elite" or "Rare") .. " nearby: " .. name)
    end
    SC.Refresh()
end
