-- SpawnCamp window (/spawncamp): watched mobs on the left, the selected mob's
-- key, attack/interact setup, alarms and sighting history on the right.

local ADDON, SC = ...

local W               -- the window
local ui = {}         -- widgets refreshed by RefreshWindow
local listOffset, histOffset = 0, 0
local LIST_ROWS, HIST_ROWS = 13, 7
local capturing = false

local function Sel()
    local n = SC.char and SC.char.selected
    return n and SC.char.mobs[n]
end

------------------------------------------------------------------------------
-- Widget helpers
------------------------------------------------------------------------------

local function Text(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

local function Btn(parent, text, w, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Check(parent, label, x, y, get, set, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb.label = fs
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        SC.Refresh()
    end)
    if tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
    end
    cb.get = get
    table.insert(ui.checks, cb)
    return cb
end

-- Saves on Enter, on focus lost and while typing (OnTextChanged's userInput flag
-- isn't reliable on Forever, so HasFocus decides).
local function Edit(parent, w, x, y, onSave, numeric)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetPoint("TOPLEFT", x + 6, y)
    e:SetAutoFocus(false)
    if numeric then e:SetNumeric(true) end
    local function save(self) onSave(self:GetText() or "") end
    e:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus(); SC.Refresh() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); SC.Refresh() end)
    e:SetScript("OnEditFocusLost", function(self) save(self); SC.Refresh() end)
    e:SetScript("OnTextChanged", function(self) if self:HasFocus() then save(self) end end)
    return e
end

local function SetEditText(e, text)
    if not e:HasFocus() then e:SetText(text or "") end
end

local function Backdrop(f, a)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.07, a or 0.95)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
end

------------------------------------------------------------------------------
-- Spell field
------------------------------------------------------------------------------

local function SpellInfo(name)
    if not name or name == "" then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and info then return info.name, info.castTime end
    elseif GetSpellInfo then
        local n, _, _, castTime = GetSpellInfo(name)
        return n, castTime
    end
    return nil
end

local function CursorSpellName()
    local kind, a, b, c = GetCursorInfo()
    if kind ~= "spell" then return nil end
    local id = c or a
    local n
    if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id) end
    if not n and GetSpellInfo then n = GetSpellInfo(id) end
    return n
end

local function TakeDroppedSpell()
    local mob = Sel()
    local n = CursorSpellName()
    if not (mob and n) then return false end
    ClearCursor()
    mob.spell = n
    ui.spell:ClearFocus()
    ui.spell:SetText(n)
    SC.ApplyBindings()
    SC.Refresh()
    return true
end

------------------------------------------------------------------------------
-- Key capture
------------------------------------------------------------------------------

local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local MODIFIERS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }

local function StopCapture()
    capturing = false
    ui.key:EnableKeyboard(false)
    SC.Refresh()
end

local function SetKey(key)
    local mob = Sel()
    if not mob then return end
    local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
    mob.key = mods .. key
    mob.armed = true
    SC.ApplyBindings()
    StopCapture()
end

local function BuildKeyButton(parent, x, y)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(150, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function(self, button)
        if capturing then
            if MOUSE_KEYS[button] then SetKey(MOUSE_KEYS[button]) else StopCapture() end
            return
        end
        if InCombatLockdown() then SC.Print("set keys out of combat"); return end
        capturing = true
        self:SetText("|cffffd100press a key...|r")
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    end)
    b:SetScript("OnKeyDown", function(self, key)
        if not capturing then return end
        if key == "ESCAPE" then StopCapture(); return end
        if MODIFIERS[key] then return end
        SetKey(key)
    end)
    b:EnableKeyboard(false)
    b:SetScript("OnHide", function() if capturing then StopCapture() end end)
    return b
end

------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------

local function ModeButton(parent, text, x, y, w, field, value)
    local b = Btn(parent, text, w, x, y, function()
        local mob = Sel()
        if not mob then return end
        mob[field] = value
        SC.ApplyBindings()
        SC.Refresh()
    end)
    b.field, b.value = field, value
    table.insert(ui.modes, b)
    return b
end

local function Build()
    W = CreateFrame("Frame", "SpawnCampWindow", UIParent, "BackdropTemplate")
    W:SetSize(680, 620)
    W:SetPoint("CENTER")
    W:SetFrameStrata("HIGH")
    W:SetToplevel(true)
    W:SetClampedToScreen(true)
    W:EnableMouse(true)
    W:SetMovable(true)
    W:RegisterForDrag("LeftButton")
    W:SetScript("OnDragStart", W.StartMoving)
    W:SetScript("OnDragStop", W.StopMovingOrSizing)
    Backdrop(W)
    W:Hide()
    tinsert(UISpecialFrames, "SpawnCampWindow")

    ui.checks, ui.modes = {}, {}

    local icon = W:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 12, -10)
    icon:SetTexture(SC.ICON)
    Text(W, "SpawnCamp", 38, -13, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, W, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Left: mob list ---------------------------------------------------------
    Text(W, "Watched mobs", 14, -44, "GameFontNormal")
    ui.rows = {}
    for i = 1, LIST_ROWS do
        local r = CreateFrame("Button", nil, W)
        r:SetSize(176, 20)
        r:SetPoint("TOPLEFT", 12, -60 - (i - 1) * 21)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, 0.05)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 4, 0)
        r.text:SetPoint("RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            SC.char.selected = self.name
            histOffset = 0
            SC.Refresh()
        end)
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            listOffset = math.max(0, math.min(listOffset - d, #SC.char.order - LIST_ROWS))
            SC.Refresh()
        end)
        ui.rows[i] = r
    end

    local listBottom = -60 - LIST_ROWS * 21 - 8
    Btn(W, "Add my target", 176, 12, listBottom, function() SC.AddTarget() end)
    ui.addName = Edit(W, 120, 12, listBottom - 28, function() end)
    Btn(W, "Add", 50, 142, listBottom - 28, function()
        local n = strtrim(ui.addName:GetText() or "")
        if n ~= "" then SC.AddMob(n); ui.addName:SetText(""); ui.addName:ClearFocus() end
    end)
    Text(W, "Type the exact name (needed for\nobjects you can't target).", 14, listBottom - 54)

    local sy = listBottom - 92
    Text(W, "Settings", 14, sy, "GameFontNormal")
    Check(W, "Share sightings with group/guild", 10, sy - 16,
        function() return SC.char.share end, function(v) SC.char.share = v end,
        "Sends spawns and deaths you see to party/raid and guild members running SpawnCamp, and logs theirs for mobs you watch.")
    Check(W, "Show timer list", 10, sy - 40,
        function() return SC.char.showTimers end, function(v) SC.char.showTimers = v end)
    Check(W, "Play sound with alerts", 10, sy - 64,
        function() return SC.char.sound end, function(v) SC.char.sound = v end)

    -- Right: selected mob ----------------------------------------------------
    local R = CreateFrame("Frame", nil, W, "BackdropTemplate")
    R:SetPoint("TOPLEFT", 200, -40)
    R:SetPoint("BOTTOMRIGHT", -10, 10)
    Backdrop(R, 0.6)
    ui.right = R
    ui.empty = Text(W, "Target a mob and press \"Add my target\".", 220, -60, "GameFontNormal")

    local D = CreateFrame("Frame", nil, R)
    D:SetAllPoints()
    ui.detail = D

    ui.name = Text(D, "", 12, -10, "GameFontNormalLarge")
    Btn(D, "Remove", 70, 384, -8, function()
        local mob = Sel()
        if mob then SC.RemoveMob(mob.name) end
    end)

    Text(D, "Mode", 12, -42, "GameFontNormal")
    ModeButton(D, "Attack", 60, -38, 90, "mode", "attack")
    ModeButton(D, "Interact", 154, -38, 90, "mode", "interact")

    -- Attack group
    local A = CreateFrame("Frame", nil, D)
    A:SetPoint("TOPLEFT", 0, -66)
    A:SetSize(460, 200)
    ui.attack = A
    Text(A, "Spell", 12, -8, "GameFontNormal")
    ui.spell = Edit(A, 180, 56, -4, function(t)
        local mob = Sel()
        if mob then mob.spell = strtrim(t); SC.ApplyBindings() end
    end)
    ui.spell:SetScript("OnReceiveDrag", TakeDroppedSpell)
    ui.spell:HookScript("OnMouseDown", function() TakeDroppedSpell() end)
    Text(A, "Drag a spell here or type its name.\nEmpty = auto attack only.", 252, -4)
    ui.spellNote = Text(A, "", 12, -32)
    Text(A, "Your key runs:", 12, -56, "GameFontNormal")
    ui.macro = Text(A, "", 12, -72, "GameFontHighlightSmall")
    ui.macro:SetWidth(440)
    Text(A, "Spam the key while you wait. A miss leaves you with no target,\nso it never casts on anything else.", 12, -150)

    -- Interact group
    local I = CreateFrame("Frame", nil, D)
    I:SetPoint("TOPLEFT", 0, -66)
    I:SetSize(460, 220)
    ui.interact = I
    Text(I, "How", 12, -8, "GameFontNormal")
    ModeButton(I, "Target by name", 56, -4, 112, "interact", "target")
    ModeButton(I, "Mouseover", 172, -4, 90, "interact", "mouseover")
    ModeButton(I, "Nearest", 266, -4, 80, "interact", "nearest")
    ui.howNote = Text(I, "", 12, -32)
    ui.howNote:SetWidth(330)
    ui.soft = Btn(I, "Turn on soft interact", 120, 340, -30, function()
        SC.EnableSoftInteract()
        SC.Refresh()
    end)
    ui.softNote = Text(I, "", 344, -54)
    Check(I, "Accept and hand in its quests", 8, -66,
        function() local m = Sel(); return m and m.autoQuest end,
        function(v) local m = Sel(); if m then m.autoQuest = v end end,
        "Hands in finished quests, takes available ones and accepts follow-ups. Hold Shift while interacting to do it yourself.")
    Check(I, "Pick the chat option when there's only one", 8, -90,
        function() local m = Sel(); return m and m.onlyOption end,
        function(v) local m = Sel(); if m then m.onlyOption = v end end)
    Text(I, "Chat options to pick, in order (part of the text, one per line):", 12, -118)
    local g = CreateFrame("EditBox", nil, I, "BackdropTemplate")
    g:SetPoint("TOPLEFT", 12, -134)
    g:SetSize(300, 54)
    g:SetMultiLine(true)
    g:SetAutoFocus(false)
    g:SetFontObject(ChatFontNormal)
    g:SetTextInsets(6, 6, 4, 4)
    g:SetMaxLetters(600)
    Backdrop(g, 0.8)
    local function saveG(self) local m = Sel(); if m then m.gossip = self:GetText() or "" end end
    g:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    g:SetScript("OnEditFocusLost", saveG)
    g:SetScript("OnTextChanged", function(self) if self:HasFocus() then saveG(self) end end)
    g:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    ui.gossip = g
    Text(I, "Reward choice", 324, -136)
    ui.reward = Edit(I, 30, 400, -132, function(t)
        local m = Sel(); if m then m.reward = tonumber(t) or 0 end
    end, true)
    Text(I, "When a quest offers\nseveral rewards: 1 = first.\nEmpty = you pick.", 324, -158)

    -- Common: key, alarms, history
    local C = CreateFrame("Frame", nil, D)
    C:SetPoint("TOPLEFT", 0, -290)
    C:SetSize(460, 290)
    Text(C, "Key", 12, -6, "GameFontNormal")
    ui.key = BuildKeyButton(C, 50, -2)
    Btn(C, "Clear", 60, 204, -2, function()
        local m = Sel(); if not m then return end
        m.key = ""
        SC.ApplyBindings()
        SC.Refresh()
    end)
    ui.keyNote = Text(C, "", 270, -6)
    ui.keyNote:SetWidth(190)

    Check(C, "Key active", 8, -28,
        function() local m = Sel(); return m and m.armed end,
        function(v) local m = Sel(); if m then m.armed = v; SC.ApplyBindings() end end,
        "Untick to give the key back to its normal binding without forgetting it.")
    Check(C, "Still hunting", 200, -28,
        function() local m = Sel(); return m and m.hunting end,
        function(v) local m = Sel(); if m then m.hunting = v end end,
        "Unticks itself when you get the kill (attack mode) and frees the key. Alerts and alarms only run while ticked.")
    Check(C, "Alert when it spawns", 8, -52,
        function() local m = Sel(); return m and m.alertSpawn end,
        function(v) local m = Sel(); if m then m.alertSpawn = v end end)
    Check(C, "Respawn alarm", 200, -52,
        function() local m = Sel(); return m and m.alarm end,
        function(v) local m = Sel(); if m then m.alarm = v end end,
        "Goes off a set time before the earliest expected respawn, and again when the window opens.")
    ui.lead = Edit(C, 36, 316, -52, function(t)
        local m = Sel(); if m then m.lead = tonumber(t) or 0 end
    end, true)
    Text(C, "sec early", 362, -56)

    Text(C, "Respawn time (min)", 12, -82)
    ui.min = Edit(C, 36, 120, -78, function(t)
        local m = Sel(); if m then m.manualMin = tonumber(t) or 0 end
    end, true)
    Text(C, "to", 168, -82)
    ui.max = Edit(C, 36, 184, -78, function(t)
        local m = Sel(); if m then m.manualMax = tonumber(t) or 0 end
    end, true)
    Text(C, "Leave empty to use the history.", 236, -82)

    Btn(C, "It died now", 100, 12, -104, function()
        local m = Sel(); if m then SC.Observe(m.name, "D", nil, nil, "you", { manual = true }) end
    end)
    Btn(C, "It's up now", 100, 116, -104, function()
        local m = Sel(); if m then SC.Observe(m.name, "A", nil, nil, "you", { manual = true }) end
    end)
    ui.status = Text(C, "", 224, -108, "GameFontNormal")
    ui.status:SetWidth(236)
    ui.stats = Text(C, "", 12, -134)

    Text(C, "History (newest first)", 12, -154, "GameFontNormal")
    ui.hist = {}
    for i = 1, HIST_ROWS do
        local r = CreateFrame("Frame", nil, C)
        r:SetSize(444, 16)
        r:SetPoint("TOPLEFT", 10, -170 - (i - 1) * 16)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 2, 0)
        r.text:SetJustifyH("LEFT")
        local x = CreateFrame("Button", nil, r)
        x:SetSize(16, 16)
        x:SetPoint("RIGHT", 0, 0)
        x:SetNormalFontObject("GameFontRedSmall")
        x:SetText("x")
        x:SetScript("OnClick", function()
            local m = Sel()
            if m and r.index then SC.DeleteEvent(m.name, r.index) end
        end)
        x:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Delete this entry (for bad sightings)")
            GameTooltip:Show()
        end)
        x:SetScript("OnLeave", GameTooltip_Hide)
        r.del = x
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            local m = Sel(); if not m then return end
            local n = #SC.History(m.name).events
            histOffset = math.max(0, math.min(histOffset - d, n - HIST_ROWS))
            SC.Refresh()
        end)
        ui.hist[i] = r
    end
end

------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------

local HOW_NOTES = {
    target = "Targets it by name, then interacts. Works on NPCs only.",
    mouseover = "Interacts with whatever NPC is under your mouse when you press the key.",
    nearest = "Your key becomes the game's Interact key: the nearest NPC, or object with soft interact on.",
}

local function StatusColor(state)
    if state == "up" then return "|cff40ff40" end
    if state == "window" then return "|cffffd100" end
    if state == "late" then return "|cffff8040" end
    return "|cffcccccc"
end
SC.StatusColor = StatusColor

function SC.RefreshWindow()
    if not (W and W:IsShown() and SC.char) then return end
    local order = SC.char.order
    listOffset = math.max(0, math.min(listOffset, #order - LIST_ROWS))
    for i, r in ipairs(ui.rows) do
        local n = order[i + listOffset]
        if n then
            local m = SC.char.mobs[n]
            r.name = n
            local tag = m.hunting and "" or " |cff40ff40(got it)|r"
            local key = (m.armed and m.key ~= "") and (" |cff999999[" .. m.key .. "]|r") or ""
            r.text:SetText(n .. tag .. key)
            r.bg:SetColorTexture(1, 0.6, 0.2, n == SC.char.selected and 0.25 or 0.05)
            r:Show()
        else
            r:Hide()
        end
    end

    for _, cb in ipairs(ui.checks) do cb:SetChecked(cb.get() and true or false) end

    local mob = Sel()
    ui.detail:SetShown(mob ~= nil)
    ui.empty:SetShown(mob == nil)
    if not mob then return end

    ui.name:SetText(mob.name)
    for _, b in ipairs(ui.modes) do
        if mob[b.field] == b.value then b:LockHighlight() else b:UnlockHighlight() end
    end
    ui.attack:SetShown(mob.mode == "attack")
    ui.interact:SetShown(mob.mode == "interact")

    if mob.mode == "attack" then
        SetEditText(ui.spell, mob.spell)
        local sname, cast = SpellInfo(mob.spell)
        if mob.spell == "" then
            ui.spellNote:SetText("|cffccccccNo spell: the key starts auto attack.|r")
        elseif not sname then
            ui.spellNote:SetText("|cffff6060Not a spell you know. Check the spelling.|r")
        elseif cast and cast > 0 then
            ui.spellNote:SetText(string.format("|cffff6060Not instant (%.1f sec cast). Pick an instant spell to tag first.|r", cast / 1000))
        else
            ui.spellNote:SetText("|cff40ff40Instant cast.|r")
        end
        ui.macro:SetText("|cffaaddff" .. (SC.MacroText(mob) or "") .. "|r")
    else
        ui.howNote:SetText(HOW_NOTES[mob.interact] or "")
        local on = SC.SoftInteractOn()
        ui.soft:SetShown(mob.interact == "nearest" and not on)
        ui.softNote:SetText(mob.interact == "nearest" and on and "|cff40ff40Soft interact is on.|r" or "")
        SetEditText(ui.gossip, mob.gossip)
        SetEditText(ui.reward, (mob.reward or 0) > 0 and tostring(mob.reward) or "")
    end

    if not capturing then
        ui.key:SetText(mob.key ~= "" and mob.key or "Click to set a key")
    end
    local clash = SC.KeyClashes()[mob.key]
    if mob.key ~= "" and clash then
        ui.keyNote:SetText("|cffff8040Also used by: " .. table.concat(clash, ", ") .. ". The lower one in the list wins.|r")
    elseif mob.key ~= "" and not mob.armed then
        ui.keyNote:SetText("|cffccccccKey not active.|r")
    elseif InCombatLockdown() then
        ui.keyNote:SetText("|cffccccccKey changes apply after combat.|r")
    else
        ui.keyNote:SetText("")
    end

    SetEditText(ui.lead, tostring(mob.lead or 0))
    SetEditText(ui.min, (mob.manualMin or 0) > 0 and tostring(mob.manualMin) or "")
    SetEditText(ui.max, (mob.manualMax or 0) > 0 and tostring(mob.manualMax) or "")

    local state, text = SC.Status(mob.name)
    ui.status:SetText(StatusColor(state) .. text .. "|r")
    local lo, avg, hi, n = SC.Stats(mob.name)
    if n > 0 then
        ui.stats:SetText(string.format("Respawn from %d kill%s: earliest %s, average %s, latest %s",
            n, n == 1 and "" or "s", SC.Clock(lo), SC.Clock(avg), SC.Clock(hi)))
    elseif lo then
        ui.stats:SetText("Respawn from your times: " .. SC.Clock(lo) .. (hi and (" to " .. SC.Clock(hi)) or ""))
    else
        ui.stats:SetText("|cffccccccNo respawn yet: needs a death followed by a spawn.|r")
    end

    -- History, newest first, with the respawn time on each spawn.
    local events = SC.History(mob.name).events
    histOffset = math.max(0, math.min(histOffset, #events - HIST_ROWS))
    for i, r in ipairs(ui.hist) do
        local idx = #events - histOffset - (i - 1)
        local e = events[idx]
        if e then
            local what = e.k == "D" and "|cffff6060died|r" or "|cff40ff40spawned|r"
            local extra = ""
            local prev = events[idx - 1]
            if e.k == "A" and prev and prev.k == "D" then
                extra = "  respawn " .. SC.Clock(e.t - prev.t) .. (prev.approx and "+" or "")
            end
            if e.approx then extra = extra .. "  (found dead)" end
            if e.mine then extra = extra .. "  |cff40ff40your kill|r" end
            local src = e.src == "you" and (e.manual and "you (manual)" or "you") or e.src
            r.text:SetText(date("%m-%d %H:%M:%S", e.t) .. "  " .. what .. "  |cff999999" .. src .. "|r" .. extra)
            r.index = idx
            r:Show()
        else
            r.index = nil
            r:Hide()
        end
    end
end

function SC.ShowWindow()
    if not W then Build() end
    W:Show()
    SC.Refresh()
end

function SC.ToggleWindow()
    if W and W:IsShown() then W:Hide() else SC.ShowWindow() end
end

-- Keep the status line ticking while the window is open.
C_Timer.NewTicker(1, function()
    if W and W:IsShown() and not capturing then
        local ok = pcall(SC.RefreshWindow)
    end
end)

SC.On("PLAYER_REGEN_DISABLED", function() if capturing then StopCapture() end end)
