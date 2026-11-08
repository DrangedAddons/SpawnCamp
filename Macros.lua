-- SpawnCamp key. One key, set in the settings, for every mob with a sword or a
-- bubble. The icon decides what the key does to that mob:
--
--   /cleartarget
--   /targetexact Sword Mob                    (sword mobs first)
--   /targetexact [noexists] Other Sword Mob
--   /targetexact [noexists] Bubble NPC        (then bubble mobs)
--   /cast [@target,harm,nodead] <spell>       attack lines: hostile target only
--   /startattack [@target,harm,nodead]
--   /click [help,nodead] SpawnCampInteract    talk: friendly target only
--
-- Clearing first means a miss leaves you with no target, so nothing lands on
-- whatever you had targeted before. The key is bound with an override binding
-- owned by the addon, only while some mob has a sword or bubble, so the
-- player's own bindings are never rewritten. Every press is a real keypress:
-- the game won't let addons target, cast or interact on their own, and
-- SpawnCamp never presses anything for you.

local ADDON, SC = ...

local owner = CreateFrame("Frame", "SpawnCampBindingOwner", UIParent)

local function ClickEdge()
    -- The game acts on press-down when "cast on key down" is on, else on release.
    -- Registering only that edge stops one keypress running the macro twice.
    local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    return down and "AnyDown" or "AnyUp"
end

local function NewSecure(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:SetSize(1, 1)
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    b:SetAlpha(0)
    b:EnableMouse(false)
    b:RegisterForClicks(ClickEdge())
    b:Show()
    return b
end

-- Key presses. In dungeons Forever hides NPC names from addons, so a press is
-- how the addon knows what it's looking at: a target right after the press is
-- one of the lit mobs. A friendly one also tells the quest code that the next
-- chat window is one to handle.
SC.lastPress = {}

local keyBtn = NewSecure("SpawnCampKey")
local interactBtn = NewSecure("SpawnCampInteract")
interactBtn:SetAttribute("type", "interact")
interactBtn:SetAttribute("unit", "target")

-- Runs after the secure action, so the macro's /targetexact has happened.
keyBtn:HookScript("OnClick", function()
    local now = GetTime()
    if SC.lastPress.key and now - SC.lastPress.key < 0.1 then return end
    SC.lastPress.key = now
    if SC.OnKeyPressed then
        local ok, err = pcall(SC.OnKeyPressed)
        if not ok then SC.Print("|cffff4040error|r " .. tostring(err)) end
    end
end)

-- Fast path: while out of combat, the nameplate of the target mob, alive, as
-- soon as it shows. Targeting that unit token is instant and can't pick up the
-- old corpse (corpses have no nameplate), which /targetexact (nearest by name,
-- dead or alive) can. Set by the tracker; cleared when combat starts, since the
-- token could be reused for another mob while the macro can't be changed.
SC.fastUnit = nil

function SC.KeyMacro()
    local attack, talk = SC.MobsIn("attack"), SC.MobsIn("interact")
    if #attack + #talk == 0 then return "" end
    local lines = { "/cleartarget" }
    local first = true
    if SC.fastUnit then
        lines[#lines + 1] = "/target " .. SC.fastUnit
        first = false
    end
    for _, list in ipairs({ attack, talk }) do
        for _, m in ipairs(list) do
            lines[#lines + 1] = (first and "/targetexact " or "/targetexact [noexists] ") .. m.name
            first = false
        end
    end
    -- The name search can land on a corpse; drop it so nothing is cast at it.
    lines[#lines + 1] = "/cleartarget [dead]"
    if #attack > 0 then
        local A = SC.char.attack
        if A.macro and strtrim(A.macro) ~= "" then
            lines[#lines + 1] = strtrim(A.macro)
        else
            if A.spell and A.spell ~= "" then
                lines[#lines + 1] = "/cast [@target,harm,nodead] " .. A.spell
            end
            lines[#lines + 1] = "/startattack [@target,harm,nodead]"
        end
    end
    if #talk > 0 then
        lines[#lines + 1] = "/click [help,nodead] SpawnCampInteract"
    end
    return table.concat(lines, "\n")
end

-- Rewrites only the macro text (for the fast path). Out of combat only.
function SC.UpdateKeyMacro()
    if InCombatLockdown() then return end
    keyBtn:SetAttribute("macrotext", SC.KeyMacro())
end

function SC.SetFastUnit(unit)
    if unit == SC.fastUnit or InCombatLockdown() then return end
    SC.fastUnit = unit
    SC.UpdateKeyMacro()
end

-- PLAYER_REGEN_DISABLED runs just before lockdown: last chance to drop the token.
SC.On("PLAYER_REGEN_DISABLED", function()
    if SC.fastUnit then
        SC.fastUnit = nil
        keyBtn:SetAttribute("macrotext", SC.KeyMacro())
    end
end)

function SC.ApplyBindings()
    if not SC.char then return end
    if InCombatLockdown() then
        SC.AfterCombat(SC.ApplyBindings)
        return
    end
    ClearOverrideBindings(owner)
    keyBtn:RegisterForClicks(ClickEdge())
    interactBtn:RegisterForClicks(ClickEdge())
    local text = SC.KeyMacro()
    keyBtn:SetAttribute("type", "macro")
    keyBtn:SetAttribute("macrotext", text)
    if SC.char.key ~= "" and text ~= "" then
        SetOverrideBindingClick(owner, true, SC.char.key, "SpawnCampKey", "LeftButton")
    end
end

SC.On("CVAR_UPDATE", function(name)
    if name == "ActionButtonUseKeyDown" or name == "ACTION_BUTTON_USE_KEY_DOWN" then
        SC.ApplyBindings()
    end
end)
