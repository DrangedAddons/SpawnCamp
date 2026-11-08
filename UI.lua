-- SpawnCamp window. Compact: a header and one line per watched mob (status,
-- countdown bar, key), meant to stay on screen. "More" opens a panel under it
-- with three tabs: Setup (action, spell/macro, key, alarms), History (every
-- sighting and respawn time) and Options.
--
-- Drag the header to move it. Click a mob's line to open its setup.

local ADDON, SC = ...

local F                 -- the window
local ui = {}
local rowOffset, histOffset = 0, 0
local MAX_ROWS, HIST_ROWS = 8, 14
local ROW_H = 20
local W_COMPACT, W_EXPANDED = 300, 480
local TAB_H = { setup = 400, history = 330, options = 118 }
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

local function Tip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Check(parent, label, x, y, get, set, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        SC.Refresh()
    end)
    if tip then Tip(cb, label, tip) end
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

local function Backdrop(f, a)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.07, a or 0.9)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
end

-- Multi-line edit box with a backdrop; onSave gets the text.
local function BigEdit(parent, w, h, x, y, maxLetters, onSave)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetPoint("TOPLEFT", x, y)
    e:SetSize(w, h)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetTextInsets(6, 6, 4, 4)
    e:SetMaxLetters(maxLetters)
    Backdrop(e, 0.8)
    local function save(self) onSave(self:GetText() or "") end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self) save(self); SC.Refresh() end)
    e:SetScript("OnTextChanged", function(self) if self:HasFocus() then save(self) end end)
    e:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    return e
end

local function SetEditText(e, text)
    if not e:HasFocus() then e:SetText(text or "") end
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
    local kind, a, _, c = GetCursorInfo()
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
    if ui.key then ui.key:EnableKeyboard(false) end
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
    b:SetSize(160, 22)
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
    b:SetScript("OnKeyDown", function(_, key)
        if not capturing then return end
        if key == "ESCAPE" then StopCapture(); return end
        if MODIFIERS[key] then return end
        SetKey(key)
    end)
    b:EnableKeyboard(false)
    b:SetScript("OnHide", function() if capturing then StopCapture() end end)
    Tip(b, "Key", "Click, then press the key (with Shift/Ctrl/Alt if you like) or mouse button 3-5. Escape cancels. While the key is active it does this mob's action instead of its normal binding.")
    return b
end

------------------------------------------------------------------------------
-- Status colours
------------------------------------------------------------------------------

local function StatusColor(state)
    if state == "up" then return "|cff40ff40" end
    if state == "window" then return "|cffffd100" end
    if state == "late" then return "|cffff8040" end
    return "|cffcccccc"
end
SC.StatusColor = StatusColor

local BAR = {
    up = { 0.2, 0.8, 0.2 }, window = { 0.9, 0.7, 0.1 }, late = { 0.9, 0.4, 0.1 },
    waiting = { 0.3, 0.45, 0.8 }, dead = { 0.4, 0.4, 0.4 }, none = { 0.25, 0.25, 0.25 },
}

local MODE_TAG = { attack = "|cffff6060Attack|r", interact = "|cff60c0ffInteract|r", macro = "|cffd0a0ffMacro|r" }

------------------------------------------------------------------------------
-- Build: header and mob lines
------------------------------------------------------------------------------

local function SavePos()
    local p, _, rp, x, y = F:GetPoint()
    SC.char.framePos = { p, rp, x, y }
end

local function BuildRows()
    ui.rows = {}
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", nil, F)
        r:SetHeight(ROW_H - 2)
        r:SetPoint("TOPLEFT", 6, -26 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", F, "RIGHT", -6, 0)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bar = CreateFrame("StatusBar", nil, r)
        r.bar:SetAllPoints()
        r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        r.bar:SetMinMaxValues(0, 1)
        r.name = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 4, 0)
        r.name:SetWidth(110)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.key = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.key:SetPoint("RIGHT", -4, 0)
        r.key:SetJustifyH("RIGHT")
        r.status = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.status:SetPoint("RIGHT", r.key, "LEFT", -4, 0)
        r.status:SetJustifyH("LEFT")
        r.status:SetWordWrap(false)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnDragStart", function() F:StartMoving() end)
        r:SetScript("OnDragStop", function() F:StopMovingOrSizing(); SavePos() end)
        r:SetScript("OnClick", function(self)
            if SC.char.selected == self.mobName and SC.char.expanded then
                SC.char.expanded = false
            else
                SC.char.selected = self.mobName
                SC.char.expanded = true
                SC.char.tab = SC.char.tab or "setup"
            end
            histOffset = 0
            SC.Refresh()
        end)
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            rowOffset = math.max(0, math.min(rowOffset - d, #SC.char.order - MAX_ROWS))
            SC.Refresh()
        end)
        ui.rows[i] = r
    end
    ui.hint = Text(F, "Target a mob and press |cffffd100+|r to watch it.", 10, -30)
end

local function BuildHeader()
    local icon = F:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(SC.ICON)
    Text(F, "SpawnCamp", 26, -7, "GameFontNormalSmall")

    local close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -1, -1)
    close:SetScript("OnClick", function()
        SC.char.shown = false
        SC.Print("hidden. /spawncamp (or the minimap button) brings it back.")
        SC.Refresh()
    end)

    ui.more = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    ui.more:SetSize(52, 18)
    ui.more:SetPoint("RIGHT", close, "LEFT", 0, 0)
    ui.more:SetScript("OnClick", function()
        SC.char.expanded = not SC.char.expanded
        if SC.char.expanded and not SC.char.selected then SC.char.selected = SC.char.order[1] end
        SC.Refresh()
    end)
    Tip(ui.more, "More / Less", "Shows setup (action, spell or macro, key, alarms), full history and options.")

    local near = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    near:SetSize(58, 18)
    near:SetPoint("RIGHT", ui.more, "LEFT", -2, 0)
    near:SetText("Nearby")
    near:SetScript("OnClick", function() SC.ToggleNearby() end)
    Tip(near, "Nearby mobs", "NPCs around you that have shown a nameplate, or that you targeted or moused over in the last 3 minutes. Click one to watch it.")

    local add = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    add:SetSize(22, 18)
    add:SetPoint("RIGHT", near, "LEFT", -2, 0)
    add:SetText("+")
    add:SetScript("OnClick", function()
        SC.AddTarget()
        if SC.char.selected then SC.char.expanded = true; SC.char.tab = "setup" end
        SC.Refresh()
    end)
    Tip(add, "Watch my target", "Adds your current target and opens its setup. To add something you can't target, use the name box under More.")
end

------------------------------------------------------------------------------
-- Build: expanded panel
------------------------------------------------------------------------------

local function ModeButton(parent, text, x, y, w, field, value, tip)
    local b = Btn(parent, text, w, x, y, function()
        local mob = Sel()
        if not mob then return end
        mob[field] = value
        SC.ApplyBindings()
        SC.Refresh()
    end)
    b.field, b.value = field, value
    if tip then Tip(b, text, tip) end
    table.insert(ui.modes, b)
    return b
end

local function BuildSetup(S)
    ui.none = Text(S, "Pick a mob above, or add one.", 8, -8, "GameFontNormal")
    local D = CreateFrame("Frame", nil, S)
    D:SetAllPoints()
    ui.setup = D

    ui.name = Text(D, "", 8, -6, "GameFontNormalLarge")
    ui.name:SetWidth(360)
    Btn(D, "Remove", 70, 392, -4, function()
        local mob = Sel()
        if mob then SC.RemoveMob(mob.name) end
    end)

    -- 1. Action
    Text(D, "1. Action", 8, -34, "GameFontNormal")
    ModeButton(D, "Attack", 80, -30, 90, "mode", "attack",
        "Targets the mob by name and casts your spell on it, then starts auto attack. For getting the tag.")
    ModeButton(D, "Interact", 174, -30, 90, "mode", "interact",
        "Talks to an NPC (or loots an object with soft interact), and can hand in and accept its quests.")
    ModeButton(D, "Custom macro", 268, -30, 110, "mode", "macro",
        "Your own macro text runs on the key.")

    -- 2. What it does (one block per action)
    Text(D, "2. What it does", 8, -62, "GameFontNormal")

    local A = CreateFrame("Frame", nil, D)
    A:SetPoint("TOPLEFT", 0, -78)
    A:SetSize(470, 190)
    ui.attack = A
    Text(A, "Spell", 8, -8)
    ui.spell = Edit(A, 170, 44, -4, function(t)
        local mob = Sel()
        if mob then mob.spell = strtrim(t); SC.ApplyBindings() end
    end)
    ui.spell:SetScript("OnReceiveDrag", TakeDroppedSpell)
    ui.spell:HookScript("OnMouseDown", function() TakeDroppedSpell() end)
    Text(A, "Drag a spell from your spellbook here,\nor type its name. Empty = auto attack.", 232, -4)
    ui.spellNote = Text(A, "", 8, -32)
    Text(A, "The key runs:", 8, -54)
    ui.macro = Text(A, "", 8, -70)
    ui.macro:SetWidth(450)
    Text(A, "Spam the key while you wait. A miss leaves you with no target,\nso it never casts on anything else.", 8, -150)

    local I = CreateFrame("Frame", nil, D)
    I:SetPoint("TOPLEFT", 0, -78)
    I:SetSize(470, 190)
    ui.interact = I
    Text(I, "How", 8, -8)
    ModeButton(I, "Target by name", 40, -4, 112, "interact", "target")
    ModeButton(I, "Mouseover", 156, -4, 86, "interact", "mouseover")
    ModeButton(I, "Nearest", 246, -4, 74, "interact", "nearest")
    ui.soft = Btn(I, "Turn on soft interact", 130, 330, -4, function()
        SC.EnableSoftInteract()
        SC.Refresh()
    end)
    ui.howNote = Text(I, "", 8, -30)
    ui.howNote:SetWidth(450)
    Check(I, "Accept and hand in its quests", 4, -46,
        function() local m = Sel(); return m and m.autoQuest end,
        function(v) local m = Sel(); if m then m.autoQuest = v end end,
        "Hands in finished quests, takes available ones and accepts follow-ups. Hold Shift while interacting to do it yourself.")
    Check(I, "Pick the chat option when there's only one", 4, -68,
        function() local m = Sel(); return m and m.onlyOption end,
        function(v) local m = Sel(); if m then m.onlyOption = v end end)
    Text(I, "Chat options to pick, in order (part of the text, one per line):", 8, -96)
    ui.gossip = BigEdit(I, 300, 72, 8, -112, 600, function(t)
        local m = Sel(); if m then m.gossip = t end
    end)
    Text(I, "Reward choice", 320, -114)
    ui.reward = Edit(I, 30, 398, -110, function(t)
        local m = Sel(); if m then m.reward = tonumber(t) or 0 end
    end, true)
    Text(I, "For quests with several\nrewards: 1 = first.\nEmpty = you pick.", 320, -136)

    local M = CreateFrame("Frame", nil, D)
    M:SetPoint("TOPLEFT", 0, -78)
    M:SetSize(470, 190)
    ui.custom = M
    Text(M, "Macro text. {mob} is replaced with the mob's name.", 8, -6)
    ui.macroEdit = BigEdit(M, 456, 120, 8, -22, 1000, function(t)
        local m = Sel(); if m then m.macro = t; SC.ApplyBindings() end
    end)
    Btn(M, "Start from the Attack macro", 180, 8, -148, function()
        local m = Sel(); if not m then return end
        m.macro = SC.AttackMacro("{mob}", m.spell)
        ui.macroEdit:SetText(m.macro)
        SC.ApplyBindings()
        SC.Refresh()
    end)
    ui.macroNote = Text(M, "", 196, -152)

    -- 3. Key
    Text(D, "3. Key", 8, -276, "GameFontNormal")
    ui.key = BuildKeyButton(D, 64, -272)
    Btn(D, "Clear", 56, 228, -272, function()
        local m = Sel(); if not m then return end
        m.key = ""
        SC.ApplyBindings()
        SC.Refresh()
    end)
    Check(D, "Key active", 290, -271,
        function() local m = Sel(); return m and m.armed end,
        function(v) local m = Sel(); if m then m.armed = v; SC.ApplyBindings() end end,
        "Untick to give the key back to its normal binding without forgetting it.")
    ui.keyNote = Text(D, "", 8, -298)
    ui.keyNote:SetWidth(460)

    -- 4. Alarms
    Text(D, "4. Alarms", 8, -318, "GameFontNormal")
    Check(D, "Still hunting", 4, -332,
        function() local m = Sel(); return m and m.hunting end,
        function(v) local m = Sel(); if m then m.hunting = v end end,
        "Unticks itself when you get the kill and frees the key. Alerts and alarms only run while ticked.")
    Check(D, "Alert when it spawns", 130, -332,
        function() local m = Sel(); return m and m.alertSpawn end,
        function(v) local m = Sel(); if m then m.alertSpawn = v end end)
    Check(D, "Respawn alarm", 290, -332,
        function() local m = Sel(); return m and m.alarm end,
        function(v) local m = Sel(); if m then m.alarm = v end end,
        "Goes off a set time before the earliest expected respawn, and again when the window opens.")
    Text(D, "Alarm", 8, -364)
    ui.lead = Edit(D, 36, 40, -360, function(t)
        local m = Sel(); if m then m.lead = tonumber(t) or 0 end
    end, true)
    Text(D, "sec early.   Respawn time", 88, -364)
    ui.min = Edit(D, 36, 214, -360, function(t)
        local m = Sel(); if m then m.manualMin = tonumber(t) or 0 end
    end, true)
    Text(D, "to", 262, -364)
    ui.max = Edit(D, 36, 276, -360, function(t)
        local m = Sel(); if m then m.manualMax = tonumber(t) or 0 end
    end, true)
    Text(D, "min (empty = from history)", 324, -364)
end

local function BuildHistory(H)
    ui.histNone = Text(H, "Pick a mob above.", 8, -8, "GameFontNormal")
    local D = CreateFrame("Frame", nil, H)
    D:SetAllPoints()
    ui.histPanel = D
    ui.histName = Text(D, "", 8, -6, "GameFontNormal")
    ui.status = Text(D, "", 8, -24, "GameFontNormal")
    ui.status:SetWidth(460)
    ui.stats = Text(D, "", 8, -42)
    ui.stats:SetWidth(460)
    Btn(D, "It died now", 96, 8, -58, function()
        local m = Sel(); if m then SC.Observe(m.name, "D", nil, nil, "you", { manual = true }) end
    end)
    Btn(D, "It's up now", 96, 108, -58, function()
        local m = Sel(); if m then SC.Observe(m.name, "A", nil, nil, "you", { manual = true }) end
    end)
    Text(D, "for sightings the addon missed", 210, -62)
    ui.histCount = Text(D, "", 8, -86)
    ui.hist = {}
    for i = 1, HIST_ROWS do
        local r = CreateFrame("Frame", nil, D)
        r:SetSize(456, 16)
        r:SetPoint("TOPLEFT", 6, -100 - (i - 1) * 16)
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
        Tip(x, "Delete this entry", "For bad sightings that throw off the respawn time.")
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

local function BuildOptions(O)
    Check(O, "Share sightings with group/guild", 4, -4,
        function() return SC.char.share end, function(v) SC.char.share = v end,
        "Sends spawns and deaths you see to party/raid and guild members running SpawnCamp, and logs theirs for mobs you watch.")
    Check(O, "Play sound with alerts", 4, -28,
        function() return SC.char.sound end, function(v) SC.char.sound = v end)
    Check(O, "Show mobs I already got", 4, -52,
        function() return SC.char.showDone end, function(v) SC.char.showDone = v end,
        "Unticked, mobs you've killed (Still hunting unticked) drop off the compact list. They stay in the setup list.")
    Check(O, "Lock window position", 4, -76,
        function() return SC.char.locked end, function(v) SC.char.locked = v end)
end

local function BuildPanel()
    local P = CreateFrame("Frame", nil, F)
    P:SetPoint("LEFT", 6, 0)
    P:SetPoint("RIGHT", -6, 0)
    ui.panel = P

    ui.addName = Edit(P, 160, 0, -2, function() end)
    local function addTyped()
        local n = strtrim(ui.addName:GetText() or "")
        if n ~= "" then SC.AddMob(n); ui.addName:SetText(""); ui.addName:ClearFocus(); SC.char.tab = "setup"; SC.Refresh() end
    end
    ui.addName:SetScript("OnEnterPressed", addTyped)
    Btn(P, "Add by name", 90, 172, -2, addTyped)
    Text(P, "exact name; works for objects too", 268, -6)

    ui.tabs = {}
    local function Tab(id, label, x)
        local b = Btn(P, label, 80, x, -28, function()
            SC.char.tab = id
            SC.Refresh()
        end)
        b.id = id
        ui.tabs[#ui.tabs + 1] = b
    end
    Tab("setup", "Setup", 0)
    Tab("history", "History", 84)
    Tab("options", "Options", 168)

    ui.pages = {}
    for _, id in ipairs({ "setup", "history", "options" }) do
        local page = CreateFrame("Frame", nil, P, "BackdropTemplate")
        page:SetPoint("TOPLEFT", 0, -54)
        page:SetPoint("RIGHT", 0, 0)
        page:SetHeight(TAB_H[id])
        Backdrop(page, 0.5)
        ui.pages[id] = page
    end
    BuildSetup(ui.pages.setup)
    BuildHistory(ui.pages.history)
    BuildOptions(ui.pages.options)
end

------------------------------------------------------------------------------
-- Nearby picker: a list beside the window of NPCs seen recently
------------------------------------------------------------------------------

local NEAR_ROWS = 16
local N   -- the picker frame

local CLASS_TAG = { worldboss = "|cffff4040boss|r", rareelite = "|cffd0d0ffrare elite|r",
                    rare = "|cffd0d0ffrare|r", elite = "|cffffd100elite|r" }

local function RefreshNearby()
    if not (N and N:IsShown()) then return end
    local list = SC.NearbyList()
    local now = GetTime()
    N.offset = math.max(0, math.min(N.offset or 0, #list - NEAR_ROWS))
    for i, r in ipairs(N.rows) do
        local item = list[i + N.offset]
        if item then
            local e = item.info
            local color = e.hostile == false and "|cff60c0ff" or "|cffff8080"
            local bits = {}
            if e.level then bits[#bits + 1] = e.level == -1 and "??" or tostring(e.level) end
            if CLASS_TAG[e.class or ""] then bits[#bits + 1] = CLASS_TAG[e.class] end
            if e.dead then bits[#bits + 1] = "|cff999999dead|r" end
            local ago = now - e.t
            if ago > 3 then bits[#bits + 1] = "|cff999999" .. SC.Clock(ago) .. " ago|r" end
            r.name:SetText(color .. item.name .. "|r")
            r.info:SetText(table.concat(bits, " "))
            r.watching:SetShown(SC.char.mobs[item.name] ~= nil)
            r.mobName, r.hostile = item.name, e.hostile
            r:Show()
        else
            r:Hide()
        end
    end
    N.empty:SetShown(#list == 0)
    N.count:SetText(#list > NEAR_ROWS and (#list .. " mobs, scroll for more") or "")
end

local function BuildNearby()
    N = CreateFrame("Frame", nil, F, "BackdropTemplate")
    N:SetSize(250, 52 + NEAR_ROWS * 18)
    N:SetPoint("TOPLEFT", F, "TOPRIGHT", 2, 0)
    Backdrop(N, 0.9)
    N:EnableMouse(true)
    Text(N, "Nearby mobs", 8, -8, "GameFontNormal")
    N.count = Text(N, "", 110, -10)
    local close = CreateFrame("Button", nil, N, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -1, -1)
    N.empty = Text(N, "None yet. Turn on nameplates (V for enemies,\nShift-V for friendly NPCs) or mouse over mobs.\nObjects can't be listed: add them by name.", 8, -30)
    N.rows = {}
    for i = 1, NEAR_ROWS do
        local r = CreateFrame("Button", nil, N)
        r:SetSize(234, 17)
        r:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 18)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 2, 0)
        r.name:SetWidth(120)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.info:SetPoint("RIGHT", -16, 0)
        r.info:SetJustifyH("LEFT")
        r.info:SetWordWrap(false)
        r.watching = r:CreateTexture(nil, "OVERLAY")
        r.watching:SetSize(12, 12)
        r.watching:SetPoint("RIGHT", -2, 0)
        r.watching:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        r:SetScript("OnClick", function(self)
            if not SC.char.mobs[self.mobName] then
                SC.AddMob(self.mobName, self.hostile == false and "interact" or "attack")
            end
            SC.char.selected = self.mobName
            SC.char.expanded, SC.char.tab = true, "setup"
            SC.Refresh()
        end)
        Tip(r, "Watch this mob", "Adds it and opens its setup. Red = hostile (starts as Attack), blue = friendly (starts as Interact).")
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            N.offset = (N.offset or 0) - d
            RefreshNearby()
        end)
        N.rows[i] = r
    end
    N:SetScript("OnShow", RefreshNearby)
    N:Hide()
end

function SC.ToggleNearby()
    if not F then return end
    if not N then BuildNearby() end
    N:SetShown(not N:IsShown())
    RefreshNearby()
end

local function Build()
    F = CreateFrame("Frame", "SpawnCampFrame", UIParent, "BackdropTemplate")
    F:SetSize(W_COMPACT, 60)
    F:SetPoint("TOP", UIParent, "TOP", 0, -160)
    F:SetFrameStrata("MEDIUM")
    F:SetClampedToScreen(true)
    F:EnableMouse(true)
    F:SetMovable(true)
    F:RegisterForDrag("LeftButton")
    F:SetScript("OnDragStart", function(self) if not SC.char.locked then self:StartMoving() end end)
    F:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    Backdrop(F, 0.75)
    local pos = SC.char.framePos
    if pos then
        F:ClearAllPoints()
        F:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    ui.checks, ui.modes = {}, {}
    BuildHeader()
    BuildRows()
    BuildPanel()
end

------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------

local HOW_NOTES = {
    target = "Targets it by name, then interacts. NPCs only.",
    mouseover = "Interacts with the NPC under your mouse when you press the key.",
    nearest = "The key becomes the game's Interact key: the nearest NPC, or an object when soft interact is on.",
}

local function RefreshRows()
    local list = {}
    for _, n in ipairs(SC.char.order) do
        local m = SC.char.mobs[n]
        if m and (m.hunting or SC.char.showDone or SC.char.expanded) then list[#list + 1] = n end
    end
    rowOffset = math.max(0, math.min(rowOffset, #list - MAX_ROWS))
    local shown = 0
    for i, r in ipairs(ui.rows) do
        local n = list[i + rowOffset]
        if n then
            local m = SC.char.mobs[n]
            local state, text, frac = SC.Status(n)
            local c = BAR[state] or BAR.none
            r.mobName = n
            r.bar:SetStatusBarColor(c[1], c[2], c[3], 0.55)
            r.bar:SetValue((state == "up" or state == "window" or state == "late") and 1 or (frac or 0))
            r.name:SetText(n .. (m.hunting and "" or " |cff40ff40(got)|r"))
            r.status:SetText(StatusColor(state) .. text .. "|r")
            local key = m.key ~= "" and (m.armed and ("|cffffd100" .. m.key .. "|r") or ("|cff777777" .. m.key .. "|r"))
                or "|cffff6060no key|r"
            r.key:SetText(key)
            local sel = SC.char.expanded and n == SC.char.selected
            r.bg:SetColorTexture(1, 0.6, 0.2, sel and 0.3 or 0.06)
            r:Show()
            shown = shown + 1
        else
            r:Hide()
        end
    end
    ui.hint:SetShown(#list == 0)
    return math.max(shown, 1)
end

local function RefreshSetup(mob)
    ui.setup:SetShown(mob ~= nil)
    ui.none:SetShown(mob == nil)
    if not mob then return end
    ui.name:SetText(mob.name .. "  " .. (MODE_TAG[mob.mode] or ""))
    for _, b in ipairs(ui.modes) do
        if mob[b.field] == b.value then b:LockHighlight() else b:UnlockHighlight() end
    end
    ui.attack:SetShown(mob.mode == "attack")
    ui.interact:SetShown(mob.mode == "interact")
    ui.custom:SetShown(mob.mode == "macro")

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
    elseif mob.mode == "interact" then
        local on = SC.SoftInteractOn()
        ui.howNote:SetText((HOW_NOTES[mob.interact] or "")
            .. (mob.interact == "nearest" and on and "  |cff40ff40Soft interact is on.|r" or ""))
        ui.soft:SetShown(mob.interact == "nearest" and not on)
        SetEditText(ui.gossip, mob.gossip)
        SetEditText(ui.reward, (mob.reward or 0) > 0 and tostring(mob.reward) or "")
    else
        SetEditText(ui.macroEdit, mob.macro)
        local text = SC.MacroText(mob) or ""
        ui.macroNote:SetText(text == "" and "|cffff6060Empty: the key does nothing.|r"
            or string.format("|cffcccccc%d characters|r", #text))
    end

    if not capturing then
        ui.key:SetText(mob.key ~= "" and mob.key or "Click to set a key")
    end
    local clash = SC.KeyClashes()[mob.key]
    if mob.key == "" then
        ui.keyNote:SetText("|cffff6060No key yet: click the button and press the key you want.|r")
    elseif clash then
        ui.keyNote:SetText("|cffff8040Also used by " .. table.concat(clash, ", ") .. ". The lower one in the list wins.|r")
    elseif not mob.armed then
        ui.keyNote:SetText("|cffccccccKey not active: it does its normal job.|r")
    elseif InCombatLockdown() then
        ui.keyNote:SetText("|cffccccccKey changes apply after combat.|r")
    else
        ui.keyNote:SetText("|cff40ff40" .. mob.key .. " is set.|r")
    end

    SetEditText(ui.lead, tostring(mob.lead or 0))
    SetEditText(ui.min, (mob.manualMin or 0) > 0 and tostring(mob.manualMin) or "")
    SetEditText(ui.max, (mob.manualMax or 0) > 0 and tostring(mob.manualMax) or "")
end

local function RefreshHistory(mob)
    ui.histPanel:SetShown(mob ~= nil)
    ui.histNone:SetShown(mob == nil)
    if not mob then return end
    ui.histName:SetText(mob.name)
    local state, text = SC.Status(mob.name)
    ui.status:SetText(StatusColor(state) .. text .. "|r")
    local lo, avg, hi, n = SC.Stats(mob.name)
    if n > 0 then
        ui.stats:SetText(string.format("Respawn from %d kill%s: earliest %s, average %s, latest %s",
            n, n == 1 and "" or "s", SC.Clock(lo), SC.Clock(avg), SC.Clock(hi)))
    elseif lo then
        ui.stats:SetText("Respawn from your times: " .. SC.Clock(lo) .. (hi and (" to " .. SC.Clock(hi)) or ""))
    else
        ui.stats:SetText("|cffccccccNo respawn time yet: needs a death followed by a spawn.|r")
    end

    local events = SC.History(mob.name).events
    histOffset = math.max(0, math.min(histOffset, #events - HIST_ROWS))
    ui.histCount:SetText(string.format("%d sightings, newest first%s", #events,
        #events > HIST_ROWS and " (scroll for more)" or ""))
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

function SC.RefreshWindow()
    if not SC.char then return end
    if not SC.char.shown then
        if F then F:Hide() end
        return
    end
    if not F then Build() end
    F:Show()

    local expanded = SC.char.expanded
    F:SetWidth(expanded and W_EXPANDED or W_COMPACT)
    ui.more:SetText(expanded and "Less" or "More")
    local rows = RefreshRows()
    for _, cb in ipairs(ui.checks) do cb:SetChecked(cb.get() and true or false) end

    local height = 26 + rows * ROW_H + 6
    if expanded then
        local tab = SC.char.tab or "setup"
        ui.panel:ClearAllPoints()
        ui.panel:SetPoint("TOPLEFT", F, "TOPLEFT", 6, -height)
        ui.panel:SetPoint("RIGHT", F, "RIGHT", -6, 0)
        ui.panel:SetHeight(54 + TAB_H[tab])
        ui.panel:Show()
        for id, page in pairs(ui.pages) do page:SetShown(id == tab) end
        for _, b in ipairs(ui.tabs) do
            if b.id == tab then b:LockHighlight() else b:UnlockHighlight() end
        end
        local mob = Sel()
        if tab == "setup" then RefreshSetup(mob) elseif tab == "history" then RefreshHistory(mob) end
        height = height + 54 + TAB_H[tab] + 8
    else
        ui.panel:Hide()
    end
    F:SetHeight(height)
end

function SC.ShowWindow()
    SC.char.shown = true
    SC.Refresh()
end

function SC.ToggleWindow()
    SC.char.shown = not SC.char.shown
    SC.Refresh()
end

-- Keep timers ticking.
C_Timer.NewTicker(1, function()
    if F and F:IsShown() and not capturing then
        pcall(SC.RefreshWindow)
        pcall(RefreshNearby)
    end
end)

SC.On("PLAYER_REGEN_DISABLED", function() if capturing then StopCapture() end end)
