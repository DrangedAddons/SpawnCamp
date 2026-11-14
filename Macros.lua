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
-- A macro /click is an up-click, and with "cast on key down" on the secure
-- template only acts on the down edge, so the click did nothing. Act on the
-- up edge regardless of that setting; one /click still runs it once.
interactBtn:SetAttribute("useOnKeyDown", false)

-- A "line of sight" error right after a key press makes the key look past
-- that mob for a few seconds. Other errors (range, cooldown, busy) are left to
-- the game's own red text.
SC.On("UI_ERROR_MESSAGE", function(_, msg)
    msg = SC.Plain(msg)
    if type(msg) ~= "string" or not SC.lastPress.key or GetTime() - SC.lastPress.key > 0.5 then return end
    if (SPELL_FAILED_LINE_OF_SIGHT and msg == SPELL_FAILED_LINE_OF_SIGHT) or msg:lower():find("line of sight", 1, true) then
        if SC.BlockTarget then pcall(SC.BlockTarget) end
    end
end)

-- The saved macro picked under Attack options, read fresh every time the key
-- is built, so edits made in /m apply without coming back here. nil when
-- none is picked or it's gone.
function SC.AttackMacroBody()
    local name = SC.char and SC.char.attack.macroName
    if not name or name == "" or not (GetMacroIndexByName and GetMacroInfo) then return nil end
    local i = GetMacroIndexByName(name)
    if not i or i == 0 then return nil end
    local _, _, body = GetMacroInfo(i)
    body = type(body) == "string" and strtrim(body) or ""
    if body == "" then return nil end
    return body
end

SC.On("UPDATE_MACROS", function()
    if not SC.char then return end
    SC.ApplyBindings()
    SC.Refresh()
end)

keyBtn:HookScript("OnClick", function(_, button, down)
    local now = GetTime()
    if SC.lastPress.key and now - SC.lastPress.key < 0.1 then return end
    SC.lastPress.key = now
    SC.pressEdge = string.format("%s %s, key-down cvar %s", tostring(button), down and "down" or "up",
        (GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")) and "on" or "off")
    SC.ranMacro = keyBtn:GetAttribute("macrotext") or ""
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
    local entry = string.format("%s %s | click: %s | target after: %s | marker: %s | ran: %s", date("%H:%M:%S"), state,
        SC.pressEdge or "?", target, mark, ((SC.ranMacro or ""):gsub("\n", " ; ")))
    SpawnCampDB.keyLog = SpawnCampDB.keyLog or {}
    table.insert(SpawnCampDB.keyLog, entry)
    while #SpawnCampDB.keyLog > 20 do table.remove(SpawnCampDB.keyLog, 1) end
end

-- What the game said in the second after a press: casts sent, failed or
-- done, and red error text. Added to that press's log line, so a key that
-- targets but doesn't cast shows why.
local function NoteAfterPress(what)
    local log = SpawnCampDB and SpawnCampDB.keyLog
    if not (log and #log > 0 and SC.lastPress.key) or GetTime() - SC.lastPress.key > 1 then return end
    local i = #log
    if not log[i]:find(" | game: ", 1, true) then log[i] = log[i] .. " | game: " .. what
    elseif #log[i] < 1500 then log[i] = log[i] .. ", " .. what end
end
SC.On("UI_ERROR_MESSAGE", function(_, msg)
    msg = SC.Plain(msg)
    if type(msg) == "string" then NoteAfterPress('error "' .. msg .. '"') end
end)
for ev, word in pairs({ UNIT_SPELLCAST_SENT = "cast sent", UNIT_SPELLCAST_START = "casting",
    UNIT_SPELLCAST_SUCCEEDED = "cast done", UNIT_SPELLCAST_FAILED = "cast failed",
    UNIT_SPELLCAST_FAILED_QUIET = "cast failed quietly", UNIT_SPELLCAST_INTERRUPTED = "cast interrupted" }) do
    SC.On(ev, function(unit)
        if unit == "player" then NoteAfterPress(word) end
    end)
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

local function TalkAndAttack(lines, attack, talk, at)
    -- In a dungeon: its mobs' searches, in the chain buttons (Dungeon.lua).
    -- In the tail so the length limit never cuts it.
    for _, m in ipairs(attack) do
        if m.dungeon then lines[#lines + 1] = SC.DungeonClick(); break end
    end
    if #attack > 0 and at then
        local A = SC.char.attack
        local body = SC.AttackMacroBody()
        if body then
            lines[#lines + 1] = body
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

-- The game runs only the first 255 characters of a secure button's macro
-- text, like a macro in /m. Past that, lines are dropped without an error:
-- a long target list ate the /cast line, so the key targeted but never cast.
local MACRO_MAX = 255
SC.MACRO_MAX = MACRO_MAX

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
    local anySearch = false
    for _, m in ipairs(SC.Actives()) do if m.partial then anySearch = true end end
    if #attack + #talk == 0 and not anySearch then return "" end
    local all = {}
    for _, x in ipairs(attack) do all[#all + 1] = x end
    for _, x in ipairs(talk) do all[#all + 1] = x end
    -- Built as three parts so the limit only ever costs search lines: the
    -- opening lines, one search per target, and the cast/attack/talk lines.
    -- The searches run in priority order, so the lowest ones are dropped.
    local head, units, tail = {}, {}, {}
    local skipName   -- already searched in head
    -- Name search for every target in priority order: the first unconditional,
    -- the rest only if the earlier ones found nothing. With clearDead, a corpse
    -- found by one search is dropped before the next, so a dead mob higher up
    -- doesn't hide the live ones below it.
    -- Wildcard searches come last, as "/target <text>": the game's own
    -- part-of-a-name match, nearest first. A mob it finds is added as its own
    -- target by the nameplate scan, and from then on found by exact name.
    -- In a dungeon the chain buttons search for these by full name instead
    -- (Dungeon.lua): /target <part of a name> finds nothing there.
    local searches = {}
    local inDungeon = SC.DungeonOn and SC.DungeonOn()
    for _, m in ipairs(SC.Actives()) do
        if m.partial and not inDungeon then searches[#searches + 1] = m.name end
    end
    local function Search(firstCond, clearDead)
        local n = 0
        local function unit(line)
            units[#units + 1] = clearDead and (line .. "\n/cleartarget [dead]") or line
        end
        for _, x in ipairs(all) do
            if x.dungeon then break end   -- the chain buttons search for those
            n = n + 1
            if x.name:lower() ~= skipName then
                unit(((n == 1 and not firstCond) and "/targetexact " or "/targetexact [noexists] ") .. x.name)
            end
        end
        for _, text in ipairs(searches) do
            n = n + 1
            unit(((n == 1 and not firstCond) and "/target " or "/target [noexists] ") .. text)
        end
    end
    if SC.onMob then
        Search(true)
        TalkAndAttack(tail, attack, talk, "[@target,harm,nodead]")
    elseif SC.fastUnit then
        -- The exact unit first; the name search backs it up in case the client
        -- won't target a nameplate token. Your target isn't the mob here, so
        -- clearing first loses nothing.
        -- The cast goes at that exact unit (checked alive and not tagged by
        -- someone else), never at whatever the name search found.
        -- The backup search tries the locked mob's name first, so a miss on the
        -- nameplate token still lands on that mob (nearest of that name), not
        -- on whichever target is first in the list.
        head[#head + 1] = "/cleartarget"
        head[#head + 1] = "/target " .. SC.fastUnit
        if SC.fastName then
            head[#head + 1] = "/targetexact [noexists] " .. SC.fastName
            head[#head + 1] = "/cleartarget [dead]"
            skipName = SC.fastName:lower()
        end
        Search(true, true)
        TalkAndAttack(tail, attack, talk, "[@" .. SC.fastUnit .. ",harm,nodead]")
    else
        -- Search only, no cast: the search can't tell a mob someone else tagged
        -- from a free one, and casting at it would cost the global cooldown. Once
        -- the target checks out (alive, free), the key switches to "on target"
        -- and the next press casts.
        -- In combat the macro is frozen and can't switch to "on target", so it
        -- casts at what it finds (the old behaviour).
        head[#head + 1] = "/cleartarget"
        Search(false, true)
        TalkAndAttack(tail, attack, talk, SC.inCombat and "[@target,harm,nodead]" or nil)
    end
    -- Opening lines and the first search always go in; then as many searches
    -- as still leave room for the cast/attack/talk lines.
    local lines = {}
    for _, l in ipairs(head) do lines[#lines + 1] = l end
    local tailText = table.concat(tail, "\n")
    local used = #table.concat(head, "\n")
    SC.keyDropped = 0
    for i, u in ipairs(units) do
        local cost = #u + 1
        if i == 1 or used + cost + (#tailText > 0 and #tailText + 1 or 0) <= MACRO_MAX then
            lines[#lines + 1] = u
            used = used + cost
        else
            SC.keyDropped = #units - i + 1
            break
        end
    end
    for _, l in ipairs(tail) do lines[#lines + 1] = l end
    return table.concat(lines, "\n")
end

-- Which state the key is in, for the line next to it.
function SC.KeyState()
    if SC.onMob and SC.talkBound then return "on", "On target: next press talks" end
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

function SC.SetFastUnit(unit, name)
    if (unit == SC.fastUnit and name == SC.fastName) or InCombatLockdown() then return end
    SC.fastUnit, SC.fastName = unit, unit and name or nil
    SC.UpdateKeyMacro()
end

function SC.SetOnMob(v)
    v = v and true or false
    if InCombatLockdown() then return end
    if v == SC.onMob then
        -- Same state, but the target may have changed side (bubble vs sword).
        if (v and SC.TalkBinding()) ~= SC.talkBound then SC.ApplyBindings() end
        return
    end
    SC.onMob = v
    SC.ApplyBindings()
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

-- On a Talk NPC: the key becomes the game's own "Interact with Target"
-- binding. Forever doesn't run the secure button's interact action from a
-- macro /click (the click arrives, nothing happens), but the binding works.
-- True when the key is on its target and that target is a friendly NPC with a
-- bubble (by name, or with the name hidden, any friendly target the key holds).
function SC.TalkBinding()
    if not SC.onMob then return false end
    local talk = SC.MobsIn("interact")
    if #talk == 0 or not SC.MaybeExists("target") or SC.True(UnitIsPlayer("target")) then return false end
    if SC.Bool(UnitCanAttack("player", "target")) ~= false then return false end
    if SC.Bool(UnitIsDead("target")) == true then return false end
    local n = SC.UnitNameSafe("target")
    if not n then return true end
    for _, m in ipairs(talk) do
        if m.name:lower() == n:lower() then return true end
    end
    return false
end

SC.talkBound = false

function SC.ApplyBindings()
    if not SC.char then return end
    if InCombatLockdown() then
        SC.AfterCombat(SC.ApplyBindings)
        return
    end
    ClearOverrideBindings(owner)
    if SC.WriteDungeonChain then SC.WriteDungeonChain() end
    keyBtn:RegisterForClicks(ClickEdge())
    local text = SC.KeyMacro()
    keyBtn:SetAttribute("type", "macro")
    keyBtn:SetAttribute("macrotext", text)
    SC.talkBound = false
    if SC.char.key ~= "" and text ~= "" then
        if SC.TalkBinding() then
            SetOverrideBinding(owner, true, SC.char.key, "INTERACTTARGET")
            SC.talkBound = true
            SC.lastPress.interact = GetTime()
        else
            SetOverrideBindingClick(owner, true, SC.char.key, "SpawnCampKey", "LeftButton")
        end
    end
end

SC.On("CVAR_UPDATE", function(name)
    if name == "ActionButtonUseKeyDown" or name == "ACTION_BUTTON_USE_KEY_DOWN" then
        SC.ApplyBindings()
    end
end)
