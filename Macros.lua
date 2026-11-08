-- SpawnCamp keys: one hidden secure button per watched mob, bound to the
-- mob's key with an override binding (owned by the addon, so the player's own
-- bindings are never rewritten, and unbinding the mob gives the key back).
--
-- Every press is a real keypress: the game won't let addons target, cast or
-- interact on their own, and SpawnCamp never presses anything for you.
--
-- Attack:   /cleartarget, /targetexact <name>, /cast [@target,harm,nodead] <spell>, /startattack.
--           Clearing first means a miss leaves you with no target, so the cast can't
--           land on whatever you had targeted before.
-- Interact: "target"    - the macro targets by name, then /clicks a secure button
--                         whose action is "interact" on the target.
--           "mouseover" - the key interacts with the unit under the mouse.
--           "nearest"   - the key is the game's own Interact key (INTERACTTARGET),
--                         which also reaches game objects when soft-target interact is on.

local ADDON, SC = ...

local owner = CreateFrame("Frame", "SpawnCampBindingOwner", UIParent)
local buttons = {}       -- mob name -> secure button
local nextId = 0

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

-- Shared button the "target" interact macro /clicks after targeting.
local interactTarget

local function InteractTargetButton()
    if not interactTarget then
        interactTarget = NewSecure("SpawnCampInteractTarget")
        interactTarget:SetAttribute("type", "interact")
        interactTarget:SetAttribute("unit", "target")
    end
    return interactTarget
end

function SC.AttackMacro(name, spell)
    local lines = { "/cleartarget", "/targetexact " .. name }
    if spell and spell ~= "" then
        lines[#lines + 1] = "/cast [@target,harm,nodead] " .. spell
    end
    lines[#lines + 1] = "/startattack [@target,harm,nodead]"
    return table.concat(lines, "\n")
end

function SC.MacroText(mob)
    local n = mob.name
    if mob.mode == "attack" then return SC.AttackMacro(n, mob.spell) end
    if mob.mode == "macro" then
        -- {mob} -> the name; the replacement goes through a function so a "%" in it stays literal.
        local text = (mob.macro or ""):gsub("{mob}", function() return n end)
        return text
    end
    if mob.interact == "target" then
        InteractTargetButton()
        return "/cleartarget\n/targetexact " .. n .. "\n/click SpawnCampInteractTarget"
    end
    return nil
end

local function SetupButton(mob)
    local b = buttons[mob.name]
    if not b then
        nextId = nextId + 1
        b = NewSecure("SpawnCampMob" .. nextId)
        buttons[mob.name] = b
    end
    b:RegisterForClicks(ClickEdge())
    if mob.mode == "interact" and mob.interact == "mouseover" then
        b:SetAttribute("type", "interact")
        b:SetAttribute("unit", "mouseover")
        b:SetAttribute("macrotext", nil)
    else
        b:SetAttribute("type", "macro")
        b:SetAttribute("unit", nil)
        b:SetAttribute("macrotext", SC.MacroText(mob) or "")
    end
    return b
end

-- Keys used by more than one armed mob: key -> list of names.
function SC.KeyClashes()
    local seen, clashes = {}, {}
    for _, n in ipairs(SC.char.order) do
        local m = SC.char.mobs[n]
        if m and m.armed and m.key ~= "" then
            if seen[m.key] then
                clashes[m.key] = clashes[m.key] or { seen[m.key] }
                table.insert(clashes[m.key], n)
            else
                seen[m.key] = n
            end
        end
    end
    return clashes
end

function SC.ApplyBindings()
    if not SC.char then return end
    if InCombatLockdown() then
        SC.AfterCombat(SC.ApplyBindings)
        return
    end
    ClearOverrideBindings(owner)
    for name, b in pairs(buttons) do
        if not SC.char.mobs[name] then
            b:SetAttribute("type", nil)
            b:SetAttribute("macrotext", nil)
        end
    end
    -- In list order, so with a clash the mob lower in the list wins (and the UI says so).
    for _, n in ipairs(SC.char.order) do
        local mob = SC.char.mobs[n]
        if mob then
            local b = SetupButton(mob)
            if mob.armed and mob.key ~= "" then
                if mob.mode == "interact" and mob.interact == "nearest" then
                    SetOverrideBinding(owner, true, mob.key, "INTERACTTARGET")
                else
                    SetOverrideBindingClick(owner, true, mob.key, b:GetName(), "LeftButton")
                end
            end
        end
    end
end

SC.On("CVAR_UPDATE", function(name)
    if name == "ActionButtonUseKeyDown" or name == "ACTION_BUTTON_USE_KEY_DOWN" then
        SC.ApplyBindings()
    end
end)

-- Soft-target interact lets the Interact key reach the nearest NPC or object
-- (chests, quest items) without targeting it. Changed only when the player
-- presses the button for it in the window.
function SC.SoftInteractOn()
    local v = GetCVar and SC.Plain(GetCVar("SoftTargetInteract"))
    return v ~= nil and tonumber(v) ~= nil and tonumber(v) > 0
end

function SC.EnableSoftInteract()
    if InCombatLockdown() then SC.Print("can't change that in combat"); return end
    if not (SetCVar and GetCVar and GetCVar("SoftTargetInteract")) then
        SC.Print("this client has no soft-target interact setting")
        return
    end
    SetCVar("SoftTargetInteract", "3")
    SC.Print("soft-target interact is on (Options > Controls can turn it off again)")
end
