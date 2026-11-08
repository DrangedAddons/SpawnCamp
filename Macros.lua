-- SpawnCamp keys. Two keys for the whole list, set in the gear settings:
--
-- Attack key: targets whichever sword mob is around and casts the attack spell.
--   /cleartarget
--   /targetexact Mob One
--   /targetexact [noexists] Mob Two      (only if the first wasn't found)
--   /cast [@target,harm,nodead] <spell>
--   /startattack [@target,harm,nodead]
--   Clearing first means a miss leaves you with no target, so the cast can't
--   land on whatever you had targeted before.
--
-- Talk key: same targeting for the bubble mobs, then interacts. Or, by setting,
--   the unit under the mouse, or the game's own Interact key (nearest NPC/object).
--
-- Each key is bound with an override binding owned by the addon, only while at
-- least one mob uses it, so the player's own bindings are never rewritten.
-- Every press is a real keypress: the game won't let addons target, cast or
-- interact on their own, and SpawnCamp never presses anything for you.

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

------------------------------------------------------------------------------
-- Key presses
------------------------------------------------------------------------------

-- Forever hides NPC names from addons in dungeons, so a press is how the addon
-- knows what it's looking at: a target right after the Attack/Talk key is one
-- of that key's mobs. SC.lastPress.interact also tells the quest code a chat
-- window is one to handle.
SC.lastPress = {}

local function Pressed(kind)
    local now = GetTime()
    if SC.lastPress[kind] and now - SC.lastPress[kind] < 0.1 then return end
    SC.lastPress[kind] = now
    if SC.OnKeyPressed then
        local ok, err = pcall(SC.OnKeyPressed, kind)
        if not ok then SC.Print("|cffff4040error|r " .. tostring(err)) end
    end
end

local attackBtn = NewSecure("SpawnCampAttack")
local talkBtn = NewSecure("SpawnCampTalk")
local interactTarget = NewSecure("SpawnCampInteractTarget")
interactTarget:SetAttribute("type", "interact")
interactTarget:SetAttribute("unit", "target")

-- Runs after the secure action, so the macro's /targetexact has happened.
attackBtn:HookScript("OnClick", function() Pressed("attack") end)
talkBtn:HookScript("OnClick", function() Pressed("interact") end)

-- "Nearest" binds the Talk key to the game's Interact key, so no button of ours
-- is clicked. A keyboard frame that passes every key on sees the press. It's
-- only switched on while that's the setting.
local watcher = CreateFrame("Frame", nil, UIParent)
local watchKey

watcher:SetScript("OnKeyDown", function(_, key)
    local full = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
    if full == watchKey then Pressed("interact") end
end)

local function SetWatcher(key)
    watchKey = key
    if key then
        local ok = pcall(watcher.SetPropagateKeyboardInput, watcher, true)
        -- Never take the keyboard without passing keys on.
        if ok then pcall(watcher.EnableKeyboard, watcher, true) end
    else
        pcall(watcher.EnableKeyboard, watcher, false)
    end
end

------------------------------------------------------------------------------
-- Macro text
------------------------------------------------------------------------------

local function TargetLines(mobs)
    local lines = { "/cleartarget" }
    for i, m in ipairs(mobs) do
        lines[#lines + 1] = (i == 1 and "/targetexact " or "/targetexact [noexists] ") .. m.name
    end
    return table.concat(lines, "\n")
end

-- Attack macro for the sword mobs (or for `names`, a list of mob tables, when given).
function SC.AttackMacro(mobs)
    mobs = mobs or SC.MobsIn("attack")
    if #mobs == 0 then return "" end
    local A = SC.char.attack
    local targeting = TargetLines(mobs)
    if A.macro and strtrim(A.macro) ~= "" then
        -- {target} -> the targeting lines; a function replacement keeps "%" literal.
        local text = A.macro:gsub("{target}", function() return targeting end)
        return text
    end
    local lines = { targeting }
    if A.spell and A.spell ~= "" then
        lines[#lines + 1] = "/cast [@target,harm,nodead] " .. A.spell
    end
    lines[#lines + 1] = "/startattack [@target,harm,nodead]"
    return table.concat(lines, "\n")
end

function SC.TalkMacro(mobs)
    mobs = mobs or SC.MobsIn("interact")
    if #mobs == 0 then return "" end
    return TargetLines(mobs) .. "\n/click SpawnCampInteractTarget"
end

------------------------------------------------------------------------------
-- Bindings
------------------------------------------------------------------------------

function SC.KeyClash()
    local a, i = SC.char.attack.key, SC.char.interact.key
    return a ~= "" and a == i
end

function SC.ApplyBindings()
    if not SC.char then return end
    if InCombatLockdown() then
        SC.AfterCombat(SC.ApplyBindings)
        return
    end
    ClearOverrideBindings(owner)
    attackBtn:RegisterForClicks(ClickEdge())
    talkBtn:RegisterForClicks(ClickEdge())
    interactTarget:RegisterForClicks(ClickEdge())

    local A, I = SC.char.attack, SC.char.interact
    local attackMobs, talkMobs = SC.MobsIn("attack"), SC.MobsIn("interact")

    attackBtn:SetAttribute("type", "macro")
    attackBtn:SetAttribute("macrotext", SC.AttackMacro(attackMobs))
    if A.key ~= "" and #attackMobs > 0 then
        SetOverrideBindingClick(owner, true, A.key, "SpawnCampAttack", "LeftButton")
    end

    local watch = nil
    if I.how == "mouseover" then
        talkBtn:SetAttribute("type", "interact")
        talkBtn:SetAttribute("unit", "mouseover")
        talkBtn:SetAttribute("macrotext", nil)
    else
        talkBtn:SetAttribute("type", "macro")
        talkBtn:SetAttribute("unit", nil)
        talkBtn:SetAttribute("macrotext", SC.TalkMacro(talkMobs))
    end
    if I.key ~= "" and #talkMobs > 0 and not SC.KeyClash() then
        if I.how == "nearest" then
            SetOverrideBinding(owner, true, I.key, "INTERACTTARGET")
            watch = I.key
        else
            SetOverrideBindingClick(owner, true, I.key, "SpawnCampTalk", "LeftButton")
        end
    end
    SetWatcher(watch)
end

SC.On("CVAR_UPDATE", function(name)
    if name == "ActionButtonUseKeyDown" or name == "ACTION_BUTTON_USE_KEY_DOWN" then
        SC.ApplyBindings()
    end
end)

-- Soft-target interact lets the Interact key reach the nearest NPC or object
-- (chests, quest items) without targeting it. Changed only when the player
-- presses the button for it in the settings.
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
