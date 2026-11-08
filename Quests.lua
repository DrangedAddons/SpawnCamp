-- SpawnCamp chat and quests: when the Talk key opens a chat or quest window,
-- step through it with the Talk settings. Hold Shift while interacting to
-- handle a window yourself.
--
-- Order on a chat window: hand in finished quests, take available ones, then
-- pick a chat option (the preferred text matches in order, else the first
-- option). Follow-up quests open as a new quest
-- window from the same NPC and are accepted the same way.

local ADDON, SC = ...

local G = C_GossipInfo

-- Stops a chat page that reopens itself from looping forever.
local steps, stepsSince = 0, 0
local function Step()
    local now = GetTime()
    if now - stepsSince > 5 then steps, stepsSince = 0, now end
    steps = steps + 1
    if steps > 12 then
        if steps == 13 then SC.Print("stopped auto-chat: it kept looping") end
        return false
    end
    return true
end

-- How long after a Talk key press (or the last window step) a chat or quest
-- window counts as one to handle.
local PRESS_WINDOW = 8

-- The Talk settings when the open window should be handled, else nil. The
-- main signal is a recent Talk key press (names can be hidden); a readable
-- name of a bubble mob also counts.
local function WindowMob()
    if IsShiftKeyDown() then return nil end
    local S = SC.char.interact
    local t = SC.lastPress.interact
    if t and GetTime() - t < PRESS_WINDOW then
        -- Each step keeps the chain going (chat -> quest -> follow-up quest).
        SC.lastPress.interact = GetTime()
        return S
    end
    for _, unit in ipairs({ "npc", "questnpc" }) do
        local name = SC.UnitNameSafe(unit)
        local mob = name and SC.char.mobs[name]
        if mob and mob.mode == "interact" and SC.IsActive(name) then return S end
    end
    return nil
end

-- Closing the window yourself ends the chain, so the next NPC you talk to isn't handled.
SC.On("GOSSIP_CLOSED", function()
    C_Timer.After(0.5, function()
        if not ((GossipFrame and GossipFrame:IsShown()) or (QuestFrame and QuestFrame:IsShown())) then
            local t = SC.lastPress.interact
            if t and GetTime() - t > 0.4 then SC.lastPress.interact = 0 end
        end
    end)
end)
local function Later(fn)
    C_Timer.After(0.05, function()
        local ok, err = pcall(fn)
        if not ok then SC.Print("|cffff4040error|r " .. tostring(err)) end
    end)
end

local function PickGossipOption(S, options, onlyQuestsLeft)
    local lines = {}
    for line in (S.prefer or ""):gmatch("[^\r\n]+") do
        line = strtrim(line)
        if line ~= "" then lines[#lines + 1] = line:lower() end
    end
    for _, want in ipairs(lines) do
        for _, opt in ipairs(options) do
            local text = SC.Plain(opt.name)
            if text and text:lower():find(want, 1, true) then return opt end
        end
    end
    -- No preferred match: the first option, as the window lists them.
    if onlyQuestsLeft and #options > 0 then
        table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
        return options[1]
    end
    return nil
end

SC.On("GOSSIP_SHOW", function()
    local mob = WindowMob()
    if not (mob and G) then return end
    Later(function()
        if not Step() then return end
        local active = G.GetActiveQuests and G.GetActiveQuests() or {}
        local avail = G.GetAvailableQuests and G.GetAvailableQuests() or {}
        if mob.autoQuest then
            for _, q in ipairs(active) do
                if q.isComplete and q.questID then G.SelectActiveQuest(q.questID); return end
            end
            for _, q in ipairs(avail) do
                if q.questID then G.SelectAvailableQuest(q.questID); return end
            end
        end
        local options = G.GetOptions and G.GetOptions() or {}
        local noQuestsWaiting = #avail == 0
        if not mob.gossip then return end
        local opt = PickGossipOption(mob, options, noQuestsWaiting)
        if opt and opt.gossipOptionID then G.SelectOption(opt.gossipOptionID) end
    end)
end)

-- Older multi-quest greeting window (no chat options).
SC.On("QUEST_GREETING", function()
    local mob = WindowMob()
    if not (mob and mob.autoQuest) then return end
    Later(function()
        if not Step() then return end
        for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
            local _, complete = GetActiveTitle(i)
            if complete then SelectActiveQuest(i); return end
        end
        if GetNumAvailableQuests and GetNumAvailableQuests() > 0 then SelectAvailableQuest(1) end
    end)
end)

SC.On("QUEST_DETAIL", function()
    local mob = WindowMob()
    if not (mob and mob.autoQuest) then return end
    Later(function()
        if Step() then AcceptQuest() end
    end)
end)

SC.On("QUEST_ACCEPT_CONFIRM", function()
    local mob = WindowMob()
    if mob and mob.autoQuest and ConfirmAcceptQuest then Later(ConfirmAcceptQuest) end
end)

SC.On("QUEST_PROGRESS", function()
    local mob = WindowMob()
    if not (mob and mob.autoQuest) then return end
    Later(function()
        if Step() and IsQuestCompletable() then CompleteQuest() end
    end)
end)

SC.On("QUEST_COMPLETE", function()
    local mob = WindowMob()
    if not (mob and mob.autoQuest) then return end
    Later(function()
        if not Step() then return end
        local n = GetNumQuestChoices() or 0
        if n <= 1 then
            GetQuestReward(n == 1 and 1 or nil)
        elseif mob.reward and mob.reward >= 1 and mob.reward <= n then
            GetQuestReward(mob.reward)
        else
            SC.Print("pick a reward (Quest reward in the settings is empty, or past the last choice)")
        end
    end)
end)

------------------------------------------------------------------------------
-- Quest mobs: the Quest pop-out lists mobs your current quests want.
--   1. Kill objectives in your quest log ("Young Panther slain: 3/10").
--   2. Mobs you've seen nearby whose tooltip names one of your quests (this
--      catches item drops, where the log doesn't name the mob).
------------------------------------------------------------------------------

local QL = C_QuestLog
local logCache, logDirty = {}, true

local function ParseCount(text)
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    return tonumber(have), tonumber(need)
end

-- The mob's name from a kill objective, in either word order.
local function MobFromObjective(text)
    text = strtrim(text)
    local name = text:match("^(.-)%s+[Ss]lain:%s*%d+%s*/%s*%d+")
        or text:match("^(.-)%s+[Kk]illed:%s*%d+%s*/%s*%d+")
        or text:match("^%d+%s*/%s*%d+%s+(.-)%s+[Ss]lain$")
        or text:match("^%d+%s*/%s*%d+%s+(.-)%s+[Kk]illed$")
        or text:match("^(.-):%s*%d+%s*/%s*%d+$")
        or text:match("^%d+%s*/%s*%d+%s+(.+)$")
    if name then name = strtrim(name) end
    if name == "" then return nil end
    return name
end

local function AddObjective(q, text, otype, finished, have, need)
    text = SC.Plain(text)
    if type(text) ~= "string" or text == "" then return end
    if not have then have, need = ParseCount(text) end
    q.objectives[#q.objectives + 1] = { text = text, type = SC.Plain(otype), finished = SC.True(finished), have = have, need = need }
end

-- Your quest log: { { title, questID, objectives = { {text, type, finished, have, need} } } }.
function SC.QuestLog()
    if not logDirty then return logCache end
    logDirty = false
    local out = {}
    pcall(function()
        if QL and QL.GetNumQuestLogEntries and QL.GetInfo then
            for i = 1, (QL.GetNumQuestLogEntries() or 0) do
                local info = QL.GetInfo(i)
                if info and not info.isHeader and not info.isHidden and info.questID then
                    local q = { title = SC.Plain(info.title) or "?", questID = info.questID, objectives = {} }
                    for _, o in ipairs(QL.GetQuestObjectives and QL.GetQuestObjectives(info.questID) or {}) do
                        AddObjective(q, o.text, o.type, o.finished, SC.Plain(o.numFulfilled), SC.Plain(o.numRequired))
                    end
                    out[#out + 1] = q
                end
            end
        elseif GetNumQuestLogEntries and GetQuestLogTitle then
            for i = 1, (GetNumQuestLogEntries() or 0) do
                local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
                if title and not isHeader then
                    local q = { title = SC.Plain(title) or "?", questID = questID, objectives = {} }
                    for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0) do
                        local text, otype, finished = GetQuestLogLeaderBoard(j, i)
                        AddObjective(q, text, otype, finished)
                    end
                    out[#out + 1] = q
                end
            end
        end
    end)
    logCache = out
    return out
end

for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED" }) do
    SC.On(ev, function()
        logDirty = true
        if SC.RefreshQuests then SC.RefreshQuests() end
    end)
end

-- Which of your quests this unit belongs to, from its tooltip: the quest's
-- title (or true when the game only says "related"), and the objective line
-- under it. nil when it isn't a quest mob or nothing can be read.
local LINE = Enum and Enum.TooltipDataLineType
function SC.UnitQuest(unit)
    local found, objective
    pcall(function()
        local titles = {}
        for _, q in ipairs(SC.QuestLog()) do titles[q.title] = true end
        if C_TooltipInfo and C_TooltipInfo.GetUnit then
            local data = C_TooltipInfo.GetUnit(unit)
            for _, line in ipairs(data and data.lines or {}) do
                local text = SC.Plain(line.leftText)
                local lt = SC.Plain(line.type)
                if type(text) == "string" and text ~= "" then
                    text = strtrim((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
                    if titles[text] or (LINE and LINE.QuestTitle and lt == LINE.QuestTitle) then
                        found = text
                    elseif found and not objective and (text:find("^%-") or (LINE and LINE.QuestObjective and lt == LINE.QuestObjective)) then
                        objective = strtrim((text:gsub("^%-%s*", "")))
                    end
                end
            end
        end
        if not found and QL and QL.UnitIsRelatedToActiveQuest and SC.True(QL.UnitIsRelatedToActiveQuest(unit)) then
            found = true
        end
    end)
    return found, objective
end

-- Mobs for the Quest pop-out: { name, quest, have, need, finished, objective, nearby (SC.nearby entry or nil) }.
-- Unfinished first, then ones seen nearby, then by name.
function SC.QuestMobs()
    local byName, out = {}, {}
    local function add(name, quest)
        local r = byName[name]
        if not r then
            r = { name = name, quest = quest }
            byName[name] = r
            out[#out + 1] = r
        end
        return r
    end
    for _, q in ipairs(SC.QuestLog()) do
        for _, o in ipairs(q.objectives) do
            if o.type == "monster" or (o.type == nil and o.text:find("[Ss]lain")) then
                local name = MobFromObjective(o.text)
                if name then
                    local r = add(name, q.title)
                    r.have, r.need, r.finished = o.have, o.need, o.finished
                end
            end
        end
    end
    for name, e in pairs(SC.nearby or {}) do
        if e.quest then
            local r = add(name, type(e.quest) == "string" and e.quest or nil)
            r.objective = r.objective or e.questObjective
            if r.finished == nil and r.objective then
                local have, need = ParseCount(r.objective)
                if have and need then r.have, r.need, r.finished = have, need, have >= need end
            end
        end
    end
    for _, r in ipairs(out) do r.nearby = SC.nearby and SC.nearby[r.name] end
    table.sort(out, function(a, b)
        if (a.finished and true or false) ~= (b.finished and true or false) then return not a.finished end
        if (a.nearby and true or false) ~= (b.nearby and true or false) then return a.nearby ~= nil end
        return a.name < b.name
    end)
    return out
end

SC._MobFromObjective = MobFromObjective

------------------------------------------------------------------------------
-- "Any quest mob": the key also goes for any mob your quests still need.
------------------------------------------------------------------------------

-- Names of quest mobs still needed, nearby ones first. Skips finished
-- objectives, your own targets, and mobs seen as friendly.
local want, wantAt = {}, -10
function SC.QuestWanted()
    if not (SC.char and SC.char.anyQuest) then return {} end
    local now = GetTime()
    if now - wantAt < 1 then return want end
    wantAt = now
    local out = {}
    for _, r in ipairs(SC.QuestMobs()) do
        if not r.finished and not SC.IsActive(r.name) and not (r.nearby and r.nearby.hostile == false) then
            out[#out + 1] = r.name
        end
    end
    want = out
    return out
end

function SC.IsQuestWanted(name)
    for _, n in ipairs(SC.QuestWanted()) do
        if n == name then return true end
    end
    return false
end

function SC.QuestWantedReset() wantAt = -10 end

-- Rebuild the key when the list changes (a new quest, an objective done, a
-- drop mob first seen). Out of combat only; combat keeps the macro as it was.
local lastSig
C_Timer.NewTicker(1, function()
    if not SC.char then return end
    local sig = table.concat(SC.QuestWanted(), "|")
    if sig ~= lastSig and not InCombatLockdown() then
        lastSig = sig
        SC.ApplyBindings()
        if SC.Refresh then SC.Refresh() end
    end
end)

function SC.SetAnyQuest(on)
    SC.char.anyQuest = on and true or false
    SC.QuestWantedReset()
    if SC.fastUnit and not SC.onMob then SC.fastUnit = nil end
    SC.ApplyBindings()
    if SC.Refresh then SC.Refresh() end
end

-- The quest list row for a name, or nil.
function SC.QuestInfo(name)
    for _, r in ipairs(SC.QuestMobs()) do
        if r.name == name then return r end
    end
end

-- The mob the Auto Quest box shows: the only one left, else the one the key
-- last went for (while it's still needed), else nil ("Any quest mob").
SC.lastQuestMob = nil
function SC.QuestShown()
    local wanted = SC.QuestWanted()
    if #wanted == 1 then return wanted[1] end
    local last = SC.lastQuestMob
    if last then
        for _, n in ipairs(wanted) do
            if n == last then return last end
        end
    end
    return nil
end
