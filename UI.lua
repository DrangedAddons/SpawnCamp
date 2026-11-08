-- SpawnCamp window. Always on screen:
--
--   [icon] SpawnCamp                                   [gear] [x]
--   Key: F   attack: Moonfire
--   [ mob name...      ] [Add] [Current Target] [Nearby]
--   (portrait) Big Name                     [Attack] [Talk]
--              dead 2:05, due in 2:55
--
-- Attack and Talk are a pressed/raised pair per mob: the pressed one says what
-- the key does to it. Clicking a name opens its details (respawn times,
-- history, alarms); the gear opens the settings.

local ADDON, SC = ...

local F
local ui = {}
local rowOffset, histOffset = 0, 0
local MAX_ROWS, HIST_ROWS = 10, 10
local ROW_H = 40
local W_COMPACT, W_PANEL = 420, 440
local PANEL_H = { mob = 330, settings = 470 }
local capturing     -- the settings table whose key is being set, or nil

-- The game's sword and chat cursors, tinted gold on the buttons.
local SWORD = "Interface\\CURSOR\\Attack"
local BUBBLE = "Interface\\CURSOR\\Speak"

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

local function Tip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then SC.Print("|cffff4040error|r " .. tostring(err)) end
    end
end

local function Btn(parent, text, w, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", Safe(onClick))
    return b
end

local function Check(parent, label, x, y, get, set, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", Safe(function(self)
        set(self:GetChecked() and true or false)
        SC.ApplyBindings()
        SC.Refresh()
    end))
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
    e:SetScript("OnEditFocusLost", function(self) save(self); SC.ApplyBindings(); SC.Refresh() end)
    e:SetScript("OnTextChanged", function(self) if self:HasFocus() then save(self) end end)
    e:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    return e
end

local function SetEditText(e, text)
    if not e:HasFocus() then e:SetText(text or "") end
end

local function Header(parent, text, y)
    local fs = Text(parent, text, 8, y, "GameFontNormal")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    return fs
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

local function TakeDroppedSpell()
    local kind, a, _, c = GetCursorInfo()
    if kind ~= "spell" then return end
    local id = c or a
    local n
    if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id) end
    if not n and GetSpellInfo then n = GetSpellInfo(id) end
    if not n then return end
    ClearCursor()
    SC.char.attack.spell = n
    ui.spell:ClearFocus()
    ui.spell:SetText(n)
    SC.ApplyBindings()
    SC.Refresh()
end

------------------------------------------------------------------------------
-- Key capture
------------------------------------------------------------------------------

local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local MODIFIERS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }

local function StopCapture()
    if capturing and capturing.button then capturing.button:EnableKeyboard(false) end
    capturing = nil
    SC.Refresh()
end

local function SetKey(key)
    if not capturing then return end
    local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
    capturing.settings.key = mods .. key
    SC.ApplyBindings()
    StopCapture()
end

local function KeyButton(parent, x, y, settings, what)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(140, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:RegisterForClicks("AnyUp")
    b.settings = settings
    b:SetScript("OnClick", function(self, button)
        if capturing then
            if capturing.button == self and MOUSE_KEYS[button] then SetKey(MOUSE_KEYS[button]) else StopCapture() end
            return
        end
        if InCombatLockdown() then SC.Print("set keys out of combat"); return end
        capturing = { settings = settings, button = self }
        self:SetText("|cffffd100press a key...|r")
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    end)
    b:SetScript("OnKeyDown", function(self, key)
        if not capturing or capturing.button ~= self then return end
        if key == "ESCAPE" then StopCapture(); return end
        if MODIFIERS[key] then return end
        SetKey(key)
    end)
    b:EnableKeyboard(false)
    b:SetScript("OnHide", function(self) if capturing and capturing.button == self then StopCapture() end end)
    Tip(b, what, "Click, then press a key (Shift/Ctrl/Alt combos work) or mouse button 3-5. Escape cancels. The key only takes over while some mob has a sword or bubble.")
    local clear = Btn(parent, "Clear", 50, x + 144, y, function()
        settings.key = ""
        SC.ApplyBindings()
        SC.Refresh()
    end)
    b.clear = clear
    table.insert(ui.keys, b)
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

------------------------------------------------------------------------------
-- Mode toggles
------------------------------------------------------------------------------

local function OpenSettings()
    SC.char.panel = "settings"
    SC.Refresh()
end

-- Pressed/raised pair: clicking the pressed one does nothing.
local function SetMode(mob, mode)
    if not mob or mob.mode == mode then return end
    mob.mode = mode
    mob.hunting = true
    SC.ApplyBindings()
    SC.Refresh()
end

-- Attack / Talk buttons: the game's red panel button with gold trim, a gold
-- icon and gold text. Pressed = the "down" art with the face nudged in.
local MODE_W, MODE_H = 82, 26
local PANEL_TC = { 0, 0.625, 0, 0.6875 }

local function ModeButton(parent, icon, label, onClick, title, body)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(MODE_W, MODE_H)
    local function art(path)
        local t = b:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        t:SetTexture(path)
        t:SetTexCoord(unpack(PANEL_TC))
        return t
    end
    b.up = art("Interface\\Buttons\\UI-Panel-Button-Up")
    b.down = art("Interface\\Buttons\\UI-Panel-Button-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    b:GetHighlightTexture():SetTexCoord(unpack(PANEL_TC))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(MODE_H - 8, MODE_H - 8)
    b.icon:SetTexture(icon)
    b.icon:SetDesaturated(true)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetText(label)
    b:SetScript("OnClick", Safe(onClick))
    Tip(b, title, body)
    return b
end

local function SetPressed(b, pressed)
    b.up:SetShown(not pressed)
    b.down:SetShown(pressed)
    local o = pressed and 1 or 0
    b.icon:ClearAllPoints()
    b.icon:SetPoint("LEFT", 8 + o, -o)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
    if pressed then
        b.icon:SetVertexColor(1, 0.82, 0)
        b.text:SetTextColor(1, 0.82, 0)
    else
        b.icon:SetVertexColor(0.6, 0.5, 0.3)
        b.text:SetTextColor(0.65, 0.55, 0.35)
    end
end

------------------------------------------------------------------------------
-- Portraits: the game draws a unit's portrait only while the unit exists, so
-- each mob's is captured whenever it's seen (target, nameplate, mouseover) and
-- kept for the session. Until then a question mark.
------------------------------------------------------------------------------

local portraits = {}   -- mob name -> frame

local function Portrait(name)
    local p = portraits[name]
    if p then return p end
    p = CreateFrame("Frame", nil, F)
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints()
    p.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    pcall(function()
        local mask = p:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(p.tex)
        p.tex:AddMaskTexture(mask)
    end)
    p.ring = p:CreateTexture(nil, "OVERLAY")
    p.ring:SetPoint("TOPLEFT", -3, 3)
    p.ring:SetPoint("BOTTOMRIGHT", 3, -3)
    p.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    p.ring:SetTexCoord(0, 0.6, 0, 0.6)
    p.ring:Hide()
    portraits[name] = p
    return p
end

function SC.CapturePortrait(name, unit)
    if not F or not SC.char.mobs[name] then return end
    local p = Portrait(name)
    local now = GetTime()
    if p.at and now - p.at < 15 then return end
    if pcall(SetPortraitTexture, p.tex, unit) then p.at = now end
end


------------------------------------------------------------------------------
-- Build: header, key line, mob rows
------------------------------------------------------------------------------

local function SavePos()
    local p, _, rp, x, y = F:GetPoint()
    SC.char.framePos = { p, rp, x, y }
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

    local gear = CreateFrame("Button", nil, F)
    gear:SetSize(16, 16)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    gear:SetScript("OnClick", function()
        SC.char.panel = SC.char.panel ~= "settings" and "settings" or nil
        SC.Refresh()
    end)
    Tip(gear, "Settings", "Your SpawnCamp key, the attack spell, and how talking works.")

    -- Key summary; clicking it opens the settings.
    local keys = CreateFrame("Button", nil, F)
    keys:SetPoint("TOPLEFT", 8, -24)
    keys:SetPoint("RIGHT", F, "RIGHT", -8, 0)
    keys:SetHeight(14)
    ui.keyLine = keys:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.keyLine:SetAllPoints()
    ui.keyLine:SetJustifyH("LEFT")
    ui.keyLine:SetWordWrap(false)
    keys:SetScript("OnClick", OpenSettings)
    Tip(keys, "Your key", "One key for every mob: the sword or bubble on each line says what it does. Click to change it.")

    -- Add row: type or paste a name, or take your target, or pick from Nearby.
    local add = CreateFrame("Frame", nil, F)
    add:SetPoint("TOPLEFT", 4, -40)
    add:SetPoint("RIGHT", F, "RIGHT", -4, 0)
    add:SetHeight(24)
    ui.addName = Edit(add, 150, 0, -2, function() end)
    local hint = ui.addName:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("type or paste a mob name")
    local function showHint()
        hint:SetShown(not ui.addName:HasFocus() and (ui.addName:GetText() or "") == "")
    end
    ui.addName:HookScript("OnEditFocusGained", showHint)
    ui.addName:HookScript("OnEditFocusLost", showHint)
    ui.addName:HookScript("OnTextChanged", showHint)
    local function addTyped()
        local n = strtrim(ui.addName:GetText() or "")
        if n ~= "" then SC.AddMob(n) end
        ui.addName:SetText("")
        ui.addName:ClearFocus()
        SC.Refresh()
    end
    ui.addName:SetScript("OnEnterPressed", addTyped)
    ui.addName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local addBtn = Btn(add, "Add", 44, 162, -2, addTyped)
    Tip(addBtn, "Add", "Adds the name in the box. Use the exact name the game shows.")
    local cur = Btn(add, "Current Target", 104, 208, -2, function() SC.AddTarget(); SC.Refresh() end)
    Tip(cur, "Current Target", "Adds the mob you have targeted: Attack if it's hostile, Talk if it's friendly.")
    local near = Btn(add, "Nearby", 64, 314, -2, function() SC.ToggleNearby() end)
    Tip(near, "Nearby", "Lists mobs around you, with a button to add each one.")
end

local function BuildRows()
    ui.rows = {}
    for i = 1, MAX_ROWS do
        -- [portrait] Big Name               [sword] [bubble]
        --            status / timer (bar behind)
        local r = CreateFrame("Button", nil, F)
        r:SetHeight(ROW_H - 2)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.portraitHolder = CreateFrame("Frame", nil, r)
        r.portraitHolder:SetSize(ROW_H - 4, ROW_H - 4)
        r.portraitHolder:SetPoint("LEFT", 2, 0)
        r.bar = CreateFrame("StatusBar", nil, r)
        r.bar:SetPoint("BOTTOMLEFT", r.portraitHolder, "BOTTOMRIGHT", 4, 1)
        r.bar:SetPoint("RIGHT", r, "RIGHT", -(MODE_W * 2 + 14), 0)
        r.bar:SetHeight(14)
        r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        r.bar:SetMinMaxValues(0, 1)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        r.name:SetPoint("TOPLEFT", r.portraitHolder, "TOPRIGHT", 6, -1)
        r.name:SetPoint("RIGHT", r.bar, "RIGHT", 0, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.status = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("LEFT", 3, 0)
        r.status:SetPoint("RIGHT", -3, 0)
        r.status:SetJustifyH("LEFT")
        r.status:SetWordWrap(false)
        r.talk = ModeButton(r, BUBBLE, "Talk", function() SetMode(SC.char.mobs[r.mobName], "interact") end,
            "Talk", "Your key talks to this NPC: chat, quest hand-ins, new and follow-up quests.")
        r.talk:SetPoint("RIGHT", -4, 0)
        r.sword = ModeButton(r, SWORD, "Attack", function() SetMode(SC.char.mobs[r.mobName], "attack") end,
            "Attack", "Your key targets this mob and casts your attack spell.")
        r.sword:SetPoint("RIGHT", r.talk, "LEFT", -4, 0)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnDragStart", function() if not SC.char.locked then F:StartMoving() end end)
        r:SetScript("OnDragStop", function() F:StopMovingOrSizing(); SavePos() end)
        r:SetScript("OnClick", function(self)
            if SC.char.panel == "mob" and SC.char.selected == self.mobName then
                SC.char.panel = nil
            else
                SC.char.selected = self.mobName
                SC.char.panel = "mob"
                histOffset = 0
            end
            SC.Refresh()
        end)
        Tip(r, "Details", "Click for respawn times, history and alarms.")
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            rowOffset = math.max(0, math.min(rowOffset - d, #SC.char.order - MAX_ROWS))
            SC.Refresh()
        end)
        ui.rows[i] = r
    end
    ui.hint = Text(F, "No mobs yet: type a name, use |cffffd100Current Target|r, or pick from |cffffd100Nearby|r.", 10, 0)
end

------------------------------------------------------------------------------
-- Build: mob details panel
------------------------------------------------------------------------------

local function Sel()
    local n = SC.char and SC.char.selected
    return n and SC.char.mobs[n]
end

local function BuildMobPanel(P)
    ui.mobName = Text(P, "", 8, -8, "GameFontNormalLarge")
    ui.mobName:SetWidth(300)
    Btn(P, "Remove", 70, 352, -6, function()
        local m = Sel(); if m then SC.RemoveMob(m.name) end
    end)
    ui.status = Text(P, "", 8, -32, "GameFontNormal")
    ui.status:SetWidth(420)
    ui.stats = Text(P, "", 8, -50)
    ui.stats:SetWidth(420)

    Check(P, "Alert when it spawns", 4, -66,
        function() local m = Sel(); return m and m.alertSpawn end,
        function(v) local m = Sel(); if m then m.alertSpawn = v end end)
    Check(P, "Respawn alarm", 160, -66,
        function() local m = Sel(); return m and m.alarm end,
        function(v) local m = Sel(); if m then m.alarm = v end end,
        "Goes off a set time before the earliest expected respawn, and again when the window opens.")
    ui.lead = Edit(P, 34, 280, -68, function(t)
        local m = Sel(); if m then m.lead = tonumber(t) or 0 end
    end, true)
    Text(P, "sec early", 324, -72)
    Check(P, "Still hunting", 4, -90,
        function() local m = Sel(); return m and m.hunting end,
        function(v) local m = Sel(); if m then m.hunting = v end end,
        "Unticks itself when you get the kill. Alerts and alarms only run while ticked.")
    Text(P, "Known respawn", 164, -96)
    ui.min = Edit(P, 30, 240, -92, function(t)
        local m = Sel(); if m then m.manualMin = tonumber(t) or 0 end
    end, true)
    Text(P, "to", 280, -96)
    ui.max = Edit(P, 30, 294, -92, function(t)
        local m = Sel(); if m then m.manualMax = tonumber(t) or 0 end
    end, true)
    Text(P, "min", 334, -96)

    Btn(P, "It died now", 90, 8, -118, function()
        local m = Sel(); if m then SC.Observe(m.name, "D", nil, nil, "you", { manual = true }) end
    end)
    Btn(P, "It's up now", 90, 102, -118, function()
        local m = Sel(); if m then SC.Observe(m.name, "A", nil, nil, "you", { manual = true }) end
    end)
    Text(P, "for sightings SpawnCamp missed", 198, -122)

    ui.histCount = Text(P, "", 8, -148)
    ui.hist = {}
    for i = 1, HIST_ROWS do
        local r = CreateFrame("Frame", nil, P)
        r:SetSize(416, 16)
        r:SetPoint("TOPLEFT", 6, -164 - (i - 1) * 16)
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

------------------------------------------------------------------------------
-- Build: settings panel
------------------------------------------------------------------------------


local function BuildSettings(P)
    local A, I = SC.char.attack, SC.char.interact

    -- Key
    local y = -8
    Header(P, "Key", y)
    Text(P, "Key", 8, y - 24)
    KeyButton(P, 60, y - 20, SC.char, "SpawnCamp key")
    Text(P, "One key for every mob. The sword or bubble on a mob\nsays what the key does to it.", 8, y - 46)

    -- Attack
    y = -78
    Header(P, "Sword: attack  |TInterface\\Icons\\INV_Sword_04:14|t", y)
    Text(P, "Spell", 8, y - 24)
    ui.spell = Edit(P, 160, 54, y - 20, function(t)
        A.spell = strtrim(t)
        SC.ApplyBindings()
    end)
    ui.spell:SetScript("OnReceiveDrag", TakeDroppedSpell)
    ui.spell:HookScript("OnMouseDown", TakeDroppedSpell)
    Text(P, "drag one from your spellbook;\nempty = auto attack", 230, y - 20)
    ui.spellNote = Text(P, "", 60, y - 44)
    Text(P, "Custom attack lines (optional, replace the spell lines; run after targeting):", 8, y - 62)
    ui.macroEdit = BigEdit(P, 420, 54, 8, y - 78, 800, function(t)
        A.macro = t
    end)

    -- Talk
    y = -222
    Header(P, "Bubble: talk  |TInterface\\GossipFrame\\GossipGossipIcon:14|t", y)
    Check(P, "Hand in and accept quests (follow-ups too)", 4, y - 16,
        function() return I.autoQuest end, function(v) I.autoQuest = v end)
    Check(P, "Click through chat", 4, y - 38,
        function() return I.gossip end, function(v) I.gossip = v end,
        "Picks the chat option when there's only one. With several, it picks one matching the list below, or asks you.")
    Text(P, "Prefer chat options containing (one per line):", 8, y - 66)
    ui.prefer = BigEdit(P, 270, 46, 8, y - 82, 600, function(t) I.prefer = t end)
    Text(P, "Reward choice", 290, y - 84)
    ui.reward = Edit(P, 30, 370, y - 80, function(t) I.reward = tonumber(t) or 0 end, true)
    Text(P, "1 = first, empty = ask", 290, y - 106)
    Text(P, "Hold Shift while talking to do it yourself.", 8, y - 136)

    -- General
    y = -380
    Header(P, "General", y)
    Check(P, "Share sightings with group/guild", 4, y - 16,
        function() return SC.char.share end, function(v) SC.char.share = v end,
        "Sends spawns and deaths you see to party/raid and guild members running SpawnCamp, and logs theirs for mobs you watch.")
    Check(P, "Sound with alerts", 230, y - 16,
        function() return SC.char.sound end, function(v) SC.char.sound = v end)
    Check(P, "Keep mobs I already got", 4, y - 40,
        function() return SC.char.showDone end, function(v) SC.char.showDone = v end)
    Check(P, "Lock window", 230, y - 40,
        function() return SC.char.locked end, function(v) SC.char.locked = v end)
end

------------------------------------------------------------------------------
-- Nearby picker
------------------------------------------------------------------------------

local NEAR_ROWS = 16
local N

local CLASS_TAG = { worldboss = "|cffff4040boss|r", rareelite = "|cffd0d0ffrare elite|r",
                    rare = "|cffd0d0ffrare|r", elite = "|cffffd100elite|r" }

local EMPTY_TEXT = "Nothing yet. The list fills from what your game\nalready shows: nameplates, your target and\nyour mouseover.\n\nTurn on nameplates (V = enemies, Shift-V =\nfriendly NPCs), or mouse over a mob, then\npress Scan now.\n\nObjects (chests, quest items) have no nameplate:\nuse + and type the name."
local HIDDEN_TEXT = "|cffff8040The game hides NPC names here|r\n(dungeons do), so they can't be listed.\n\nUse + and type the name exactly as your\ntarget frame shows it."

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
            local have = SC.char.mobs[item.name] ~= nil
            r.watching:SetShown(have)
            r.add:SetShown(not have)
            r.mobName, r.hostile = item.name, e.hostile
            r:Show()
        else
            r:Hide()
        end
    end
    N.empty:SetShown(#list == 0)
    N.empty:SetText(SC.namesHidden and HIDDEN_TEXT or EMPTY_TEXT)
    N.count:SetText(#list > NEAR_ROWS and (#list .. " mobs, scroll for more") or "")
end

local function BuildNearby()
    N = CreateFrame("Frame", nil, F, "BackdropTemplate")
    N:SetSize(320, 92 + NEAR_ROWS * 18)
    N:SetPoint("TOPLEFT", F, "TOPRIGHT", 2, 0)
    Backdrop(N, 0.9)
    N:EnableMouse(true)
    Text(N, "Nearby mobs", 8, -8, "GameFontNormal")
    local scan = Btn(N, "Scan now", 74, 104, -4, function()
        N.report:SetText((SC.ScanNearby()))
        RefreshNearby()
    end)
    Tip(scan, "Scan now", "Reads every nameplate, your target and your mouseover right now. The list also fills by itself a few times a second.")
    local close = CreateFrame("Button", nil, N, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -1, -1)
    N.count = Text(N, "", 8, -28 - NEAR_ROWS * 18 - 4)
    N.report = Text(N, "", 8, -28 - NEAR_ROWS * 18 - 20)
    N.report:SetWidth(304)
    N.empty = Text(N, EMPTY_TEXT, 8, -30)
    N.rows = {}
    for i = 1, NEAR_ROWS do
        local r = CreateFrame("Button", nil, N)
        r:SetSize(304, 17)
        r:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 18)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 2, 0)
        r.name:SetWidth(130)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.info:SetPoint("RIGHT", -52, 0)
        r.info:SetJustifyH("LEFT")
        r.info:SetWordWrap(false)
        r.add = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.add:SetSize(46, 17)
        r.add:SetPoint("RIGHT", 0, 0)
        r.add:SetText("Add")
        r.add:SetScript("OnClick", Safe(function()
            if not SC.char.mobs[r.mobName] then
                SC.AddMob(r.mobName, r.hostile == false and "interact" or "attack")
            end
            SC.Refresh()
            RefreshNearby()
        end))
        Tip(r.add, "Add this mob", "Hostile ones start on Attack, friendly ones on Talk.")
        r.watching = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.watching:SetPoint("RIGHT", -4, 0)
        r.watching:SetText("added")
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            N.offset = (N.offset or 0) - d
            RefreshNearby()
        end)
        N.rows[i] = r
    end
    N:SetScript("OnShow", function()
        N.report:SetText((SC.ScanNearby()))
        RefreshNearby()
    end)
    N:Hide()
end

function SC.ToggleNearby()
    if not F then return end
    if not N then BuildNearby() end
    N:SetShown(not N:IsShown())
    RefreshNearby()
end

------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------

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
    ui.checks, ui.keys = {}, {}
    BuildHeader()
    BuildRows()
    ui.panels = {}
    for id, build in pairs({ mob = BuildMobPanel, settings = BuildSettings }) do
        local P = CreateFrame("Frame", nil, F, "BackdropTemplate")
        P:SetPoint("LEFT", F, "LEFT", 6, 0)
        P:SetPoint("RIGHT", F, "RIGHT", -6, 0)
        P:SetHeight(PANEL_H[id])
        Backdrop(P, 0.5)
        P:Hide()
        build(P)
        ui.panels[id] = P
    end
end

------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------

local function RefreshKeyLine()
    local A = SC.char.attack
    local key = SC.char.key ~= "" and ("|cffffd100" .. SC.char.key .. "|r") or "|cffff6060not set, click to set|r"
    local spell = A.spell ~= "" and A.spell or "auto attack"
    if strtrim(A.macro or "") ~= "" then spell = "custom" end
    ui.keyLine:SetText("Key: " .. key .. "   |cff999999attack: " .. spell .. "|r")
end

local function RefreshRows(top)
    local list = {}
    for _, n in ipairs(SC.char.order) do
        local m = SC.char.mobs[n]
        if m and (m.hunting or m.mode or SC.char.showDone) then list[#list + 1] = n end
    end
    rowOffset = math.max(0, math.min(rowOffset, #list - MAX_ROWS))
    for _, p in pairs(portraits) do p:Hide() end
    local shown = 0
    for i, r in ipairs(ui.rows) do
        local n = list[i + rowOffset]
        if n then
            local m = SC.char.mobs[n]
            local state, text, frac = SC.Status(n)
            local c = BAR[state] or BAR.none
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", F, "TOPLEFT", 6, top - shown * ROW_H)
            r:SetPoint("RIGHT", F, "RIGHT", -6, 0)
            r.mobName = n
            r.bar:SetStatusBarColor(c[1], c[2], c[3], 0.55)
            r.bar:SetValue((state == "up" or state == "window" or state == "late") and 1 or (frac or 0))
            r.name:SetText(n .. (m.hunting and "" or " |cff40ff40(got)|r"))
            local p = Portrait(n)
            p:SetParent(r.portraitHolder)
            p:ClearAllPoints()
            p:SetAllPoints(r.portraitHolder)
            p:Show()
            r.status:SetText(StatusColor(state) .. text .. "|r")
            SetPressed(r.sword, m.mode == "attack")
            SetPressed(r.talk, m.mode == "interact")
            local sel = SC.char.panel == "mob" and n == SC.char.selected
            r.bg:SetColorTexture(1, 0.6, 0.2, sel and 0.3 or 0.06)
            r:Show()
            shown = shown + 1
        else
            r:Hide()
        end
    end
    ui.hint:ClearAllPoints()
    ui.hint:SetPoint("TOPLEFT", F, "TOPLEFT", 10, top - 3)
    ui.hint:SetShown(#list == 0)
    return math.max(shown, 1)
end

local function RefreshMobPanel()
    local mob = Sel()
    if not mob then SC.char.panel = nil; return false end
    ui.mobName:SetText(mob.name)
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
    SetEditText(ui.lead, tostring(mob.lead or 0))
    SetEditText(ui.min, (mob.manualMin or 0) > 0 and tostring(mob.manualMin) or "")
    SetEditText(ui.max, (mob.manualMax or 0) > 0 and tostring(mob.manualMax) or "")

    local events = SC.History(mob.name).events
    histOffset = math.max(0, math.min(histOffset, #events - HIST_ROWS))
    ui.histCount:SetText(string.format("History: %d sighting%s, newest first%s", #events, #events == 1 and "" or "s",
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
    return true
end

local function RefreshSettings()
    local A, I = SC.char.attack, SC.char.interact
    for _, b in ipairs(ui.keys) do
        if not (capturing and capturing.button == b) then
            b:SetText(b.settings.key ~= "" and b.settings.key or "Click to set")
        end
    end
    SetEditText(ui.spell, A.spell)
    local sname, cast = SpellInfo(A.spell)
    if A.spell == "" then
        ui.spellNote:SetText("|cffccccccNo spell: the key starts auto attack.|r")
    elseif not sname then
        ui.spellNote:SetText("|cffff6060Not a spell you know.|r")
    elseif cast and cast > 0 then
        ui.spellNote:SetText(string.format("|cffff6060Not instant (%.1f sec cast).|r", cast / 1000))
    else
        ui.spellNote:SetText("|cff40ff40Instant cast.|r")
    end
    SetEditText(ui.macroEdit, A.macro)
    SetEditText(ui.prefer, I.prefer)
    SetEditText(ui.reward, (I.reward or 0) > 0 and tostring(I.reward) or "")
end

function SC.RefreshWindow()
    if not SC.char then return end
    if not SC.char.shown then
        if F then F:Hide() end
        return
    end
    if not F then Build() end
    F:Show()

    local panel = SC.char.panel
    if panel == "mob" and not Sel() then panel = nil; SC.char.panel = nil end
    F:SetWidth(panel and W_PANEL or W_COMPACT)
    RefreshKeyLine()

    local rows = RefreshRows(-68)
    local top = -68
    for _, cb in ipairs(ui.checks) do cb:SetChecked(cb.get() and true or false) end

    local height = -top + rows * ROW_H + 6
    for id, P in pairs(ui.panels) do
        if id == panel then
            P:ClearAllPoints()
            P:SetPoint("TOPLEFT", F, "TOPLEFT", 6, -height)
            P:SetPoint("RIGHT", F, "RIGHT", -6, 0)
            P:Show()
        else
            P:Hide()
        end
    end
    if panel == "mob" then RefreshMobPanel() elseif panel == "settings" then RefreshSettings() end
    if panel then height = height + PANEL_H[panel] + 6 end
    F:SetHeight(height)
end

-- Shows the name box (from + when the name can't be read).
function SC.FocusAddName()
    SC.char.shown = true
    SC.Refresh()
    if ui.addName then ui.addName:SetFocus() end
end

function SC.ShowWindow()
    SC.char.shown = true
    SC.Refresh()
end

function SC.ToggleWindow()
    SC.char.shown = not SC.char.shown
    SC.Refresh()
end

C_Timer.NewTicker(1, function()
    if F and F:IsShown() and not capturing then
        pcall(SC.RefreshWindow)
        pcall(RefreshNearby)
    end
end)

SC.On("PLAYER_REGEN_DISABLED", function() if capturing then StopCapture() end end)
