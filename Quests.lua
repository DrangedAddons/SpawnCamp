-- SpawnCamp chat and quests: when a watched interact-mode NPC opens a chat or
-- quest window, step through it. Only for watched NPCs; hold Shift while
-- interacting to handle a window yourself.
--
-- Order on a chat window: hand in finished quests, take available ones, then
-- pick a chat option (the mob's text matches in order, else the only option
-- when "pick the only option" is on). Follow-up quests open as a new quest
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

-- How long after an interact key press (or the last window step) a chat or
-- quest window counts as that mob's.
local PRESS_WINDOW = 8

-- The watched interact mob behind the open window, or nil. Forever hides NPC
-- names, so the main signal is a recent press of an interact-mode key; a
-- readable name is used when there is one.
local function WindowMob()
    if IsShiftKeyDown() then return nil end
    local now, best, bestT = GetTime(), nil, nil
    for name, t in pairs(SC.lastPress) do
        local m = SC.char.mobs[name]
        if m and m.mode == "interact" and now - t < PRESS_WINDOW and (not bestT or t > bestT) then
            best, bestT = m, t
        end
    end
    if best then
        -- Each step keeps the chain going (gossip -> quest -> follow-up quest).
        SC.lastPress[best.name] = now
        return best
    end
    for _, unit in ipairs({ "npc", "questnpc" }) do
        local name = SC.UnitNameSafe(unit)
        local mob = name and SC.char.mobs[name]
        if mob and mob.mode == "interact" then return mob end
    end
    return nil
end

-- Closing the window yourself ends the chain, so the next NPC you talk to isn't handled.
SC.On("GOSSIP_CLOSED", function()
    C_Timer.After(0.5, function()
        if not ((GossipFrame and GossipFrame:IsShown()) or (QuestFrame and QuestFrame:IsShown())) then
            for name, t in pairs(SC.lastPress) do
                if GetTime() - t > 0.4 then SC.lastPress[name] = 0 end
            end
        end
    end)
end)

local function Later(fn)
    C_Timer.After(0.05, function()
        local ok, err = pcall(fn)
        if not ok then SC.Print("|cffff4040error|r " .. tostring(err)) end
    end)
end

local function PickGossipOption(mob, options, onlyQuestsLeft)
    local lines = {}
    for line in (mob.gossip or ""):gmatch("[^\r\n]+") do
        line = strtrim(line)
        if line ~= "" then lines[#lines + 1] = line:lower() end
    end
    for _, want in ipairs(lines) do
        for _, opt in ipairs(options) do
            local text = SC.Plain(opt.name)
            if text and text:lower():find(want, 1, true) then return opt end
        end
    end
    if mob.onlyOption and #options == 1 and onlyQuestsLeft then return options[1] end
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
            SC.Print("pick a reward (set \"Reward choice\" for " .. mob.name .. " to pick one automatically)")
        end
    end)
end)
