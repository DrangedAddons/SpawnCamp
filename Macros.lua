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

local function NewSecure(name, bothEdges)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:SetSize(1, 1)
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    b:SetAlpha(0)
    b:EnableMouse(false)
    b.bothEdges = bothEdges
    if bothEdges then b:RegisterForClicks("AnyUp", "AnyDown") else b:RegisterForClicks(ClickEdge()) end
    b:Show()
    return b
end

-- Key presses. In dungeons Forever hides NPC names from addons, so a press is
-- how the addon knows what it's looking at: a target right after the press is
-- one of the lit mobs. A friendly one also tells the quest code that the next
-- chat window is one to handle.
SC.lastPress = {}

-- Buttons the key's macro /clicks listen on both edges: a macro /click sends
-- an up-click, which a down-only button (cast on key down, the default)
-- ignores. One /click is one edge, so it still fires once.
local keyBtn = NewSecure("SpawnCampKey")
local interactBtn = NewSecure("SpawnCampInteract", true)
interactBtn:SetAttribute("type", "interact")
interactBtn:SetAttribute("unit", "target")

-- Raid marker on the target through the secure "raidtarget" action (the macro
-- /clicks it). Addon code can't call SetRaidTarget here (it's blocked).
local markBtn = NewSecure("SpawnCampMark", true)
markBtn:SetAttribute("type", "raidtarget")
markBtn:SetAttribute("unit", "target")
-- The icon goes in both "action" and "raidtarget": client versions differ on
-- which one the raidtarget action reads.
markBtn:SetAttribute("action", 8)
markBtn:SetAttribute("raidtarget", 8)

-- Runs after the secure action, so the macro's /targetexact has happened.
-- Why a press didn't cast: the game's red error text (facing, range, line of
-- sight...) right after a key press is echoed to chat, once per message every
-- few seconds, so a "slow" cast can be traced to its cause.
local lastErr, lastErrAt = nil, 0
SC.On("UI_ERROR_MESSAGE", function(_, msg)
    msg = SC.Plain(msg)
    if not msg or not SC.lastPress.key or GetTime() - SC.lastPress.key > 0.5 then return end
    if (SPELL_FAILED_LINE_OF_SIGHT and msg == SPELL_FAILED_LINE_OF_SIGHT) or msg:lower():find("line of sight", 1, true) then
        if SC.BlockTarget then pcall(SC.BlockTarget) end
    end
    if msg == lastErr and GetTime() - lastErrAt < 4 then return end
    lastErr, lastErrAt = msg, GetTime()
    SC.Print("|cffff8040key press didn't cast:|r " .. msg)
end)

keyBtn:HookScript("OnClick", function()
    local now = GetTime()
    if SC.lastPress.key and now - SC.lastPress.key < 0.1 then return end
    SC.lastPress.key = now
    SC.ranMacro = keyBtn:GetAttribute("macrotext") or ""
    -- The marker line has run: take it out before combat freezes the macro.
    if not SC.markDone and SC.ranMacro:find("/click SpawnCampMark", 1, true) then
        SC.markDone = true
        SC.UpdateKeyMacro()
        C_Timer.After(1.5, SC.CheckMark)
    end
    if SC.OnKeyPressed then
        local ok, err = pcall(SC.OnKeyPressed)
        if not ok then SC.Print("|cffff4040error|r " .. tostring(err)) end
    end
    pcall(SC.LogPress)
end)

-- The last 20 presses: mode, the macro that ran, and what you ended up targeting.
-- /spc key prints them; they're saved in SpawnCampDB.keyLog for bug reports.
function SC.LogPress()
    local state = SC.KeyState()
    local function show(v)
        if v == nil then return "nil" end
        if SC.issecret(v) then return "hidden" end
        return tostring(v)
    end
    local target = SC.MaybeExists("target") and (show(UnitName("target")) .. (SC.Bool(UnitIsDead("target")) and " (dead)" or "")) or "none"
    local mark = "none"
    if GetRaidTargetIndex then
        local ok, i = pcall(GetRaidTargetIndex, "target")
        if ok then mark = show(i) end
    end
    local entry = string.format("%s %s | target after: %s | marker: %s | ran: %s", date("%H:%M:%S"), state,
        target, mark, ((SC.ranMacro or ""):gsub("\n", " ; ")))
    SpawnCampDB.keyLog = SpawnCampDB.keyLog or {}
    table.insert(SpawnCampDB.keyLog, entry)
    while #SpawnCampDB.keyLog > 20 do table.remove(SpawnCampDB.keyLog, 1) end
end

-- How the key gets the mob, best first. The macro is rewritten (out of combat
-- only) as the situation changes:
--   1. Your target already is the alive mob (SC.onMob): never touch the target,
--      just cast at it. Spamming can't swap you off it. The name search only runs
--      if the target is gone ([noexists]).
--   2. The mob's alive nameplate is known (SC.fastUnit): target that unit, with
--      the name search as a backup, drop a corpse, cast at the target.
--   3. Neither: clear, search by name, drop a corpse. No cast: once the target
--      checks out the key becomes 1 and the next press casts.
-- Combat freezes the macro; PLAYER_REGEN_DISABLED drops the nameplate token
-- (it could be reused for another mob) and leaves 1 or 3.
SC.fastUnit = nil
SC.onMob = false

-- Raid marker over the mob. Addons can't call SetRaidTarget on this client
-- (it raised "blocked" errors); the key's macro /clicks a secure raidtarget
-- button instead. The line goes in only until one press has run it
-- (SC.markDone), and not when the target already has that marker, in case the
-- action toggles a marker that's already there.
SC.markDone = false
SC.markTries = 0

local function TargetIcon()
    if not GetRaidTargetIndex then return nil end
    local ok, cur = pcall(GetRaidTargetIndex, "target")
    return ok and SC.Plain(cur) or nil
end

-- After a press that ran the marker line: if the mob still has no marker,
-- put the line back for the next press (out of combat, up to 3 tries).
function SC.CheckMark()
    if not (SC.char.markTarget and SC.markDone and SC.onMob) or InCombatLockdown() then return end
    if TargetIcon() ~= nil then SC.markTries = 0; return end
    if SC.markTries >= 3 then return end
    SC.markTries = SC.markTries + 1
    SC.markDone = false
    SC.UpdateKeyMacro()
end

local function MarkLine(lines, unitKnown)
    if not (SC.char.markTarget and unitKnown and not SC.markDone) then return end
    local icon = SC.char.markIcon or 8
    if SC.onMob and TargetIcon() == icon then return end
    lines[#lines + 1] = "/click SpawnCampMark"
end

local function TalkAndAttack(lines, attack, talk, at)
    if #attack > 0 and at then
        MarkLine(lines, not SC.inCombat)
        local A = SC.char.attack
        if A.macro and strtrim(A.macro) ~= "" then
            lines[#lines + 1] = strtrim(A.macro)
        else
            if A.spell and A.spell ~= "" then
                lines[#lines + 1] = "/cast " .. at .. " " .. A.spell
            end
            lines[#lines + 1] = "/startattack " .. at
        end
    end
    if #talk > 0 then
        lines[#lines + 1] = "/click [help,nodead] SpawnCampInteract"
    end
end

-- The game's limit on a secure macro's text is 1023 characters.
local MACRO_MAX = 1000

function SC.KeyMacro()
    SC.questCap = 8
    local text = SC.BuildKeyMacro()
    while #text > MACRO_MAX and SC.questCap > 0 do
        SC.questCap = SC.questCap - 1
        text = SC.BuildKeyMacro()
    end
    return text
end

function SC.BuildKeyMacro()
    local attack, talk = SC.MobsIn("attack"), SC.MobsIn("interact")
    if #attack + #talk == 0 then return "" end
    local all = {}
    for _, x in ipairs(attack) do all[#all + 1] = x end
    for _, x in ipairs(talk) do all[#all + 1] = x end
    local lines = {}
    -- Name search for every target in priority order: the first unconditional,
    -- the rest only if the earlier ones found nothing. With clearDead, a corpse
    -- found by one search is dropped before the next, so a dead mob higher up
    -- doesn't hide the live ones below it.
    local function Search(firstCond, clearDead)
        for i, x in ipairs(all) do
            lines[#lines + 1] = ((i == 1 and not firstCond) and "/targetexact " or "/targetexact [noexists] ") .. x.name
            if clearDead then lines[#lines + 1] = "/cleartarget [dead]" end
        end
    end
    if SC.onMob then
        Search(true)
        TalkAndAttack(lines, attack, talk, "[@target,harm,nodead]")
    elseif SC.fastUnit then
        -- The exact unit first; the name search backs it up in case the client
        -- won't target a nameplate token. Your target isn't the mob here, so
        -- clearing first loses nothing.
        -- The cast goes at that exact unit (checked alive and not tagged by
        -- someone else), never at whatever the name search found.
        lines[#lines + 1] = "/cleartarget"
        lines[#lines + 1] = "/target " .. SC.fastUnit
        Search(true, true)
        TalkAndAttack(lines, attack, talk, "[@" .. SC.fastUnit .. ",harm,nodead]")
    else
        -- Search only, no cast: the search can't tell a mob someone else tagged
        -- from a free one, and casting at it would cost the global cooldown. Once
        -- the target checks out (alive, free), the key switches to "on target"
        -- and the next press casts.
        -- In combat the macro is frozen and can't switch to "on target", so it
        -- casts at what it finds (the old behaviour).
        lines[#lines + 1] = "/cleartarget"
        Search(false, true)
        TalkAndAttack(lines, attack, talk, SC.inCombat and "[@target,harm,nodead]" or nil)
    end
    return table.concat(lines, "\n")
end

-- Which state the key is in, for the line next to it.
function SC.KeyState()
    if SC.onMob then return "on", "On target: won't swap" end
    if SC.fastUnit then return "lock", "Locked on its nameplate" end
    if InCombatLockdown() then return "off", "In combat: searching by name (no cast)" end
    return "off", "Searching: next press casts once it's checked"
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

function SC.SetOnMob(v)
    v = v and true or false
    if v == SC.onMob or InCombatLockdown() then return end
    SC.onMob = v
    SC.UpdateKeyMacro()
end

-- PLAYER_REGEN_DISABLED runs just before lockdown: last chance to drop the
-- nameplate token and switch the search to casting.
SC.inCombat = false
SC.On("PLAYER_REGEN_DISABLED", function()
    SC.inCombat = true
    SC.fastUnit = nil
    keyBtn:SetAttribute("macrotext", SC.KeyMacro())
end)
SC.On("PLAYER_REGEN_ENABLED", function()
    SC.inCombat = false
    SC.UpdateKeyMacro()
end)

function SC.ApplyBindings()
    if not SC.char then return end
    if InCombatLockdown() then
        SC.AfterCombat(SC.ApplyBindings)
        return
    end
    ClearOverrideBindings(owner)
    keyBtn:RegisterForClicks(ClickEdge())
    markBtn:SetAttribute("action", SC.char.markIcon or 8)
    markBtn:SetAttribute("raidtarget", SC.char.markIcon or 8)
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
