-- SpawnCamp window. Always on screen:
--
--   [icon] SpawnCamp                                         [gear] [x]
--   Key [ F ] [Clear]                       works on your target below
--   [ type or paste a mob name ] [Add] [My Target] [Nearby] [Recent] [Quest]
--   TARGET
--   (portrait) Mechanized Sentry            [Attack] [Talk] [Clear]
--              dead 2:05, due in 2:55
--   RECENT
--   (p) Other Mob      up, seen 0:12 ago                          [x]
--
-- The key works on the selected target only; with none it does nothing.
-- Attack / Talk are a pressed/raised pair; right-click either for its options.
-- Click a Recent mob to make it the target, right-click it (or click the
-- target's name) for its respawn log, which opens beside the window. The gear
-- holds general settings.

local ADDON, SC = ...

local F
local ui = {}
local recentOffset, histOffset = 0, 0
local RECENT_ROWS, HIST_ROWS = 14, 14
local RECENT_H = 22
local W = 520
local PANEL_H = { settings = 192 }
local capturing     -- { settings = table with .key, button = key button } while setting a key

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

-- The mob's tooltip: the game's own when it's in view (target, nameplate,
-- mouseover), else the copy from when it was last seen, else what's known.
function SC.ShowMobTip(owner, name, click)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if not name then
        GameTooltip:SetText("Any quest mob")
        local w = SC.QuestWanted()
        GameTooltip:AddLine(#w > 0 and table.concat(w, ", ") or "No quest mobs needed right now.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local u = SC.UnitFor(name)
    local tip = not u and SC.TipFor(name)
    if u then
        GameTooltip:SetUnit(u)
    elseif tip then
        for i, e in ipairs(tip.lines) do
            if e[5] then
                GameTooltip:AddDoubleLine(e[1], e[5], e[2], e[3], e[4], e[6], e[7], e[8])
            else
                GameTooltip:AddLine(e[1], e[2], e[3], e[4], i > 1)
            end
        end
        GameTooltip:AddLine("Not in view. Last seen " .. SC.Clock(GetServerTime() - tip.t) .. " ago.", 0.6, 0.6, 0.6)
    else
        local info = SC.nearby[name]
        local m = SC.char.mobs[name]
        GameTooltip:AddLine(name, 1, 0.82, 0)
        local level = info and info.level
        local ctype = (info and info.ctype) or (m and m.ctype)
        local cls = info and info.class
        local parts = {}
        if type(level) == "number" then parts[#parts + 1] = "Level " .. (level < 0 and "??" or level) end
        if ctype then parts[#parts + 1] = ctype end
        if cls and cls ~= "normal" and cls ~= "minus" then parts[#parts + 1] = "(" .. cls:gsub("elite", " Elite"):gsub("^%s+", ""):gsub("^%l", string.upper) .. ")" end
        if #parts > 0 then GameTooltip:AddLine(table.concat(parts, " "), 1, 1, 1) end
        GameTooltip:AddLine("Not in view. Its full tooltip shows here once you've seen it.", 0.6, 0.6, 0.6, true)
    end
    if click then GameTooltip:AddLine("Click to target it.", 0.25, 1, 0.25) end
    GameTooltip:Show()
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
    cb.label = fs
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

local function Popup(name, w, h, title)
    local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    p:SetSize(w, h)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    Backdrop(p, 0.95)
    Text(p, title, 10, -10, "GameFontNormal")
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -1, -1)
    p:Hide()
    tinsert(UISpecialFrames, name)
    return p
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

local function KeyButton(parent, x, y, settings)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(150, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:RegisterForClicks("AnyUp")
    b.settings = settings
    b:SetScript("OnClick", function(self, button)
        if capturing then
            if capturing.button == self and MOUSE_KEYS[button] then SetKey(MOUSE_KEYS[button]) else StopCapture() end
            return
        end
        if InCombatLockdown() then SC.Print("set the key out of combat"); return end
        capturing = { settings = settings, button = self }
        self:SetText("|cffffd100Press a key or wheel...|r")
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
    -- The mouse wheel can be the key too (with modifiers), while waiting for a press.
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(self, delta)
        if not capturing or capturing.button ~= self then return end
        SetKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)
    b:SetScript("OnHide", function(self) if capturing and capturing.button == self then StopCapture() end end)
    Tip(b, "SpawnCamp key", "Click, then press a key, roll the mouse wheel, or press mouse button 3-5. Shift/Ctrl/Alt combos work. Escape cancels. It only takes over while you have a target selected.")
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
-- Portraits: the game draws a unit's portrait only while the unit exists, so
-- each mob's is captured whenever it's seen (target, nameplate, mouseover) and
-- kept for the session. Until then a question mark.
------------------------------------------------------------------------------

local portraits = {}   -- mob name -> frame

-- Until a real portrait is captured: an icon for the creature type (saved the
-- first time the mob is seen), else one for its action.
local TYPE_ICON = {
    Beast = "Ability_Hunter_Pet_Wolf",
    Humanoid = "INV_Misc_Head_Human_01",
    Undead = "INV_Misc_Bone_HumanSkull_01",
    Demon = "Spell_Shadow_SummonFelHunter",
    Elemental = "Spell_Nature_EarthElemental_Totem",
    Dragonkin = "INV_Misc_Head_Dragon_01",
    Giant = "Ability_Warrior_BattleShout",
    Mechanical = "INV_Gizmo_02",
    Critter = "Ability_Hunter_Pet_Rat",
    Aberration = "Spell_Shadow_UnholyFrenzy",
}

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local QUEST_KEY = "|quest|"   -- portrait cache key for "Any quest mob"

local function DefaultIcon(name)
    if name == nil or name == QUEST_KEY then return QUEST_ICON end
    local m = SC.char.mobs[name]
    local near = SC.nearby and SC.nearby[name]
    local icon = (m and m.ctype and TYPE_ICON[m.ctype]) or (near and near.ctype and TYPE_ICON[near.ctype])
    if not icon then icon = (m and m.mode == "interact") and "INV_Scroll_03" or "INV_Sword_04" end
    return "Interface\\Icons\\" .. icon
end

local function Portrait(name)
    local p = portraits[name]
    if p then return p end
    p = CreateFrame("Frame", nil, F)
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints()
    p.tex:SetTexture(DefaultIcon(name))
    pcall(function()
        local mask = p:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(p.tex)
        p.tex:AddMaskTexture(mask)
    end)
    portraits[name] = p
    return p
end

function SC.CapturePortrait(name, unit)
    local m = SC.char.mobs[name]
    if not m and not (SC.char.anyQuest and SC.IsQuestWanted(name)) then return end
    local ok, ctype = pcall(UnitCreatureType, unit)
    ctype = ok and SC.Plain(ctype)
    if ctype and m then m.ctype = ctype end
    if not F then return end
    local p = Portrait(name)
    local now = GetTime()
    if p.at and now - p.at < 15 then return end
    if pcall(SetPortraitTexture, p.tex, unit) then p.at = now end
end

local function PlacePortrait(name, holder)
    local p = Portrait(name)
    if not p.at then p.tex:SetTexture(DefaultIcon(name)) end
    p:SetParent(holder)
    p:ClearAllPoints()
    p:SetAllPoints(holder)
    p:Show()
    holder.portrait = p
end

------------------------------------------------------------------------------
-- Attack / Talk buttons: big square icon-only buttons. A pressed/raised pair:
-- pressed = bright red, thick gold border, gold glow, shaded top, gold icon
-- nudged down; raised = dark grey, grey border, light top band, grey icon.
-- Clicking the pressed one does nothing. Right-click opens its options.
------------------------------------------------------------------------------

local MODE_SIZE = 46

local function Gradient(tex, top, bottom)
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and pcall(tex.SetGradient, tex, "VERTICAL",
        CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    if not ok then tex:SetColorTexture(top[1], top[2], top[3], 1) end
end

local function ModeButton(parent, icon, onLeft, onRight, title, body)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(MODE_SIZE, MODE_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
    -- Gold glow around the pressed one.
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    b.glow:SetPoint("TOPLEFT", -10, 10)
    b.glow:SetPoint("BOTTOMRIGHT", 10, -10)
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.8, 0.2, 0.9)
    b.fill = b:CreateTexture(nil, "BACKGROUND")
    b.fill:SetPoint("TOPLEFT", 3, -3)
    b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    -- Raised: light band on top. Pressed: dark band on top (pushed in).
    b.shine = b:CreateTexture(nil, "BORDER")
    b.shine:SetPoint("TOPLEFT", 3, -3)
    b.shine:SetPoint("TOPRIGHT", -3, -3)
    b.shine:SetHeight(MODE_SIZE * 0.4)
    b.shine:SetColorTexture(1, 1, 1, 0.10)
    b.inset = b:CreateTexture(nil, "BORDER")
    b.inset:SetPoint("TOPLEFT", 3, -3)
    b.inset:SetPoint("TOPRIGHT", -3, -3)
    b.inset:SetHeight(8)
    b.inset:SetColorTexture(0, 0, 0, 0.45)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    b:GetHighlightTexture():SetVertexColor(1, 0.8, 0.3, 0.12)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(MODE_SIZE - 14, MODE_SIZE - 14)
    b.icon:SetTexture(icon)
    b.icon:SetDesaturated(true)
    b:SetScript("OnClick", Safe(function(self, button)
        if button == "RightButton" then onRight(self) else onLeft(self) end
    end))
    Tip(b, title, body)
    return b
end

local function SetPressed(b, pressed)
    b.icon:ClearAllPoints()
    b.icon:SetDesaturated(true)
    b.icon:SetAlpha(1)
    if pressed then
        Gradient(b.fill, { 0.55, 0.05, 0.03 }, { 0.9, 0.15, 0.06 })
        b:SetBackdropBorderColor(1, 0.82, 0.1, 1)
        b.glow:Show()
        b.shine:Hide()
        b.inset:Show()
        b.icon:SetPoint("CENTER", 1, -2)
        b.icon:SetVertexColor(1, 0.86, 0.15)
    else
        Gradient(b.fill, { 0.3, 0.3, 0.32 }, { 0.13, 0.13, 0.14 })
        b:SetBackdropBorderColor(0.38, 0.38, 0.4, 1)
        b.glow:Hide()
        b.shine:Show()
        b.inset:Hide()
        b.icon:SetPoint("CENTER", 0, 1)
        b.icon:SetVertexColor(0.72, 0.72, 0.72)
    end
end
local function SetMode(mode, slot)
    local mob = SC.Active(slot)
    if not mob or mob.mode == mode then return end
    mob.mode = mode
    SC.ApplyBindings()
    SC.Refresh()
end

------------------------------------------------------------------------------
-- Attack and Talk options (right-click popups)
------------------------------------------------------------------------------

local AP, TP, N, RP, Q

local function HideSidePanels(except)
    for _, p in ipairs({ AP, TP, N, RP, Q }) do
        if p and p ~= except then p:Hide() end
    end
end

-- Opens an options popup beside the window, or closes it if it's open. A
-- click outside an open popup (including on the other button) only closes it.
local closedAt = 0

local function ShowBeside(p, opener)
    if (p == AP or p == TP) and GetTime() - closedAt < 0.2 then return end
    local wasShown = p:IsShown()
    HideSidePanels()
    if not wasShown then
        p.opener = opener
        p:ClearAllPoints()
        local beside = (SC.char.logRight and ui.log and ui.log:IsShown()) and ui.log or F
        p:SetPoint("TOPLEFT", beside, "TOPRIGHT", 2, 0)
        p:Show()
    end
    SC.Refresh()
end

-- Clicks that shouldn't close the options: in the spellbook (to drag a spell
-- onto the Spell box), on the action bars, or while holding something.
local KEEP_OPEN = { "SpellBookFrame", "PlayerSpellsFrame", "ProfessionsBookFrame", "MainMenuBar",
                    "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }

local function ClickKeepsOpen()
    if GetCursorInfo and GetCursorInfo() then return true end
    for _, name in ipairs(KEEP_OPEN) do
        local frame = _G[name]
        if frame and frame.IsShown and frame:IsShown() and frame:IsMouseOver() then return true end
    end
    return false
end

SC.On("GLOBAL_MOUSE_DOWN", function()
    if ClickKeepsOpen() then return end
    for _, p in ipairs({ AP, TP }) do
        if p and p:IsShown() and not p:IsMouseOver() and not (p.opener and p.opener:IsMouseOver()) then
            p:Hide()
            closedAt = GetTime()
        end
    end
end)

local function Wrapped(parent, text, x, y, w)
    local fs = Text(parent, text, x, y)
    fs:SetWidth(w)
    fs:SetWordWrap(true)
    return fs
end

local function BuildAttackPopup()
    local A = SC.char.attack
    AP = Popup("SpawnCampAttackOptions", 380, 212, "Attack  |T" .. SWORD .. ":14|t")
    Text(AP, "Spell", 12, -40)
    ui.spell = Edit(AP, 200, 46, -36, function(t)
        A.spell = strtrim(t)
        SC.ApplyBindings()
    end)
    ui.spell:SetScript("OnReceiveDrag", TakeDroppedSpell)
    ui.spell:HookScript("OnMouseDown", TakeDroppedSpell)
    Wrapped(AP, "Drag a spell here from your spellbook, or type its name. Empty = auto attack only.", 12, -62, 356)
    ui.spellNote = Text(AP, "", 12, -90)
    Wrapped(AP, "Or your own macro lines. They replace the spell and run after the mob is targeted.", 12, -110, 356)
    ui.macroEdit = BigEdit(AP, 356, 62, 12, -138, 800, function(t) A.macro = t end)
end

local function BuildTalkPopup()
    local I = SC.char.interact
    TP = Popup("SpawnCampTalkOptions", 380, 250, "Talk  |T" .. BUBBLE .. ":14|t")
    Check(TP, "Hand in and accept quests (follow-ups too)", 8, -30,
        function() return I.autoQuest end, function(v) I.autoQuest = v end)
    Check(TP, "Click through chat", 8, -52,
        function() return I.gossip end, function(v) I.gossip = v end,
        "Picks a chat option for you: one matching the list below if there is one, otherwise the first option.")
    Wrapped(TP, "Prefer chat options containing (one per line, optional). Otherwise the first option is picked.", 12, -82, 356)
    ui.prefer = BigEdit(TP, 356, 46, 12, -110, 600, function(t) I.prefer = t end)
    Text(TP, "Quest reward", 12, -168)
    ui.reward = Edit(TP, 30, 92, -164, function(t) I.reward = tonumber(t) or 0 end, true)
    Wrapped(TP, "When a quest offers a choice of rewards: 1 = first, 2 = second, and so on. Empty = you pick.", 12, -190, 356)
    Text(TP, "Hold Shift while talking to do a window yourself.", 12, -224, "GameFontDisableSmall")
end
------------------------------------------------------------------------------
-- Build: header, key row, add row, target, recent
------------------------------------------------------------------------------

local function SavePos()
    local p, _, rp, x, y = F:GetPoint()
    SC.char.framePos = { p, rp, x, y }
end

local function BuildTop()
    local icon = F:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(SC.ICON)
    Text(F, "SpawnCamp", 26, -7, "GameFontNormal")

    local close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -1, -1)
    close:SetScript("OnClick", function()
        SC.char.shown = false
        HideSidePanels()
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
    Tip(gear, "Settings", "Sharing, alerts, sound, the list and the log side.")

    ui.logToggle = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    ui.logToggle:SetSize(52, 18)
    ui.logToggle:SetPoint("RIGHT", gear, "LEFT", -6, 0)
    ui.logToggle:SetScript("OnClick", function()
        SC.char.logOpen = not SC.char.logOpen
        SC.Refresh()
    end)
    Tip(ui.logToggle, "Log", "Opens or closes the target's log: respawn times and every sighting.")

    -- Recent: a quiet text link in the header.
    local recent = CreateFrame("Button", nil, F)
    recent:SetSize(46, 16)
    recent:SetPoint("RIGHT", ui.logToggle, "LEFT", -8, 0)
    recent:SetNormalFontObject("GameFontDisableSmall")
    recent:SetHighlightFontObject("GameFontHighlightSmall")
    recent:SetText("Recent")
    recent:SetScript("OnClick", function() SC.ToggleRecent() end)
    Tip(recent, "Recent", "Every mob you've targeted before. Pick one again or remove it.")

    -- Key row
    KeyButton(F, 8, -29, SC.char)
    local clearKey = Btn(F, "Unassign", 70, 162, -29, function()
        SC.char.key = ""
        SC.ApplyBindings()
        SC.Refresh()
    end)
    Tip(clearKey, "Unassign", "Removes the key. Your normal binding for it comes back.")
    ui.keyNote = Text(F, "", 240, -34)
    ui.keyNote:SetWidth(220)

end

local BOX_H = 64   -- height of a target box (and the picker)

-- The picker: a blank target box with the ways to add one. Shown when you have
-- no targets (and Auto Quest is off), or after "+ Add another target".
--   New target [ type or paste a mob name      ] [Add]               [x]
--   [My Target] [Nearby] [Quest] [Auto Quest]
local function BuildPicker()
    local T = CreateFrame("Frame", nil, F, "BackdropTemplate")
    T:SetHeight(BOX_H)
    Backdrop(T, 0.6)
    T:SetBackdropBorderColor(1, 0.82, 0, 0.6)
    ui.picker = T
    Text(T, "New target", 10, -11, "GameFontNormal")
    ui.addName = Edit(T, 230, 84, -8, function() end)
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
        if n ~= "" then SC.AddTyped(n) end
        ui.addName:SetText("")
        ui.addName:ClearFocus()
        SC.Refresh()
    end
    ui.addName:SetScript("OnEnterPressed", addTyped)
    ui.addName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Tip(Btn(T, "Add", 44, 326, -8, addTyped), "Add", "Adds the typed name to your targets. Part of a name works too: it becomes a search, and every mob seen with that in its name is added as its own target. Clear a wrong one and the search skips it from then on.")
    Tip(Btn(T, "My Target", 84, 8, -36, function() SC.AddTarget(); SC.Refresh() end),
        "My Target", "Adds the mob you have targeted in game to your targets: Attack if hostile, Talk if friendly.")
    Tip(Btn(T, "Nearby", 64, 94, -36, function() SC.ToggleNearby() end),
        "Nearby", "Lists mobs around you, with a button to use each one.")
    Tip(Btn(T, "Quest", 56, 160, -36, function() SC.ToggleQuests() end),
        "Quest", "Mobs your current quests want: kill objectives from your quest log, plus mobs nearby that your quests need (item drops too).")
    ui.autoQuest = Btn(T, "Auto Quest", 92, 218, -36, function() SC.SetAnyQuest(not SC.char.anyQuest) end)
    Tip(ui.autoQuest, "Auto Quest", "On, your key goes for any mob your quests still need, alive and not tagged by someone else, after your own targets. Finished objectives drop off by themselves.")

    ui.pickCancel = CreateFrame("Button", nil, T, "UIPanelCloseButton")
    ui.pickCancel:SetSize(22, 22)
    ui.pickCancel:SetPoint("TOPRIGHT", -2, -2)
    ui.pickCancel:SetScript("OnClick", function()
        ui.picking = false
        if ui.addName then ui.addName:ClearFocus() end
        SC.Refresh()
    end)
    Tip(ui.pickCancel, "Cancel", "Closes this without adding a target.")
end

-- Target boxes, one per slot, left to right:
--   [portrait] Name               ETA 0:15        [sword] [bubble]  [Clear]
--              dead 0:05, ...     Avg respawn 0:20                  Keep [x]

-- quest = the Auto Quest box: same look, but the key picks the mob.
local function BuildTargetBox(slot, quest)
    local bx = { quest = quest }
    local T = CreateFrame("Frame", nil, F, "BackdropTemplate")
    T:SetHeight(BOX_H)
    Backdrop(T, 0.6)
    T:SetBackdropBorderColor(1, 0.82, 0, 0.6)
    bx.frame = T

    bx.portrait = CreateFrame("Frame", nil, T)
    bx.portrait:SetSize(52, 52)
    bx.portrait:SetPoint("LEFT", 30, 0)
    bx.portrait:EnableMouse(true)
    bx.portrait:SetScript("OnEnter", function(self) SC.ShowMobTip(self, bx.tipName) end)
    bx.portrait:SetScript("OnLeave", GameTooltip_Hide)

    -- Right column: Clear, with Keep under it.
    bx.clear = Btn(T, "Clear", 58, 0, 0, function()
        if quest then SC.SetAnyQuest(false) else SC.SetActive(nil, slot) end
    end)
    bx.clear:ClearAllPoints()
    bx.clear:SetPoint("TOPRIGHT", -6, -8)
    bx.clear:SetHeight(20)
    if quest then
        Tip(bx.clear, "Clear", "Turns Auto Quest off.")
    else
        Tip(bx.clear, "Clear target", "Takes this mob off your key. It stays in Recent.")
    end
    bx.keep = Check(T, "Keep", 0, 0,
        function() local m = SC.Active(slot); return m and m.keep end,
        function(v) local m = SC.Active(slot); if m then m.keep = v end end,
        "Ticked, this mob stays your target after you get the kill, until you press Clear. Unticked, getting the kill clears it.")
    bx.keep:ClearAllPoints()
    bx.keep:SetSize(20, 20)
    bx.keep:SetPoint("TOPRIGHT", bx.clear, "BOTTOMRIGHT", 0, -4)
    bx.keep.label:ClearAllPoints()
    bx.keep.label:SetPoint("RIGHT", bx.keep, "LEFT", -1, 0)

    -- The two big buttons.
    bx.talk = ModeButton(T, BUBBLE, function() HideSidePanels(); SetMode("interact", slot) end, function(self) ShowBeside(TP, self) end,
        "Talk", "Your key talks to this NPC: chat, quest hand-ins, new and follow-up quests.\n|cffffd100Right-click|r for the chat and quest options.")
    bx.talk:SetPoint("RIGHT", T, "RIGHT", -74, 0)
    bx.attack = ModeButton(T, SWORD, function() HideSidePanels(); if not quest then SetMode("attack", slot) end end, function(self) ShowBeside(AP, self) end,
        "Attack", quest and "Your key targets the quest mob and casts your attack spell.\n|cffffd100Right-click|r to set the spell or macro."
            or "Your key targets this mob and casts your attack spell.\n|cffffd100Right-click|r to set the spell or macro.")
    bx.attack:SetPoint("RIGHT", bx.talk, "LEFT", -6, 0)

    -- ETA column.
    local eta = CreateFrame("Frame", nil, T)
    eta:SetSize(92, 52)
    eta:SetPoint("RIGHT", bx.attack, "LEFT", -8, 0)
    bx.eta = eta:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bx.eta:SetPoint("TOP", 0, -6)
    bx.avg = eta:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bx.avg:SetPoint("BOTTOM", 0, 8)
    eta:EnableMouse(true)
    if quest then
        Tip(eta, "Quest progress", "Kills (or items) done out of how many the quest needs. With several quest mobs, how many kinds are still needed.")
    else
    Tip(eta, "Respawn ETA", "Avg respawn: how long this mob usually takes to come back after it dies (from the log). ETA counts down to that from its last death. At zero you get a soft ding, whether or not it has shown.")
    end
    bx.etaBox = eta

    -- Name and status, taking the rest.
    local nameArea = CreateFrame("Frame", nil, T)
    nameArea:SetPoint("TOPLEFT", bx.portrait, "TOPRIGHT", 8, 0)
    nameArea:SetPoint("BOTTOMRIGHT", eta, "BOTTOMLEFT", -6, 0)
    bx.name = nameArea:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bx.name:SetPoint("TOPLEFT", 0, -6)
    bx.name:SetPoint("RIGHT", 0, 0)
    bx.name:SetJustifyH("LEFT")
    bx.name:SetWordWrap(false)
    bx.status = nameArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bx.status:SetPoint("BOTTOMLEFT", 0, 8)
    bx.status:SetPoint("RIGHT", 0, 0)
    bx.status:SetJustifyH("LEFT")
    bx.status:SetWordWrap(false)
    bx.nameArea = nameArea

    if not quest then
        -- Priority arrows at the left edge. Higher in the list = higher priority.
        local function Arrow(dir, delta, tip)
            local a = CreateFrame("Button", nil, T)
            a:SetSize(26, 26)
            a:SetNormalTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Up")
            a:SetPushedTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Down")
            a:SetDisabledTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Up")
            a:GetDisabledTexture():SetDesaturated(true)
            a:GetDisabledTexture():SetAlpha(0.3)
            a:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
            a:SetScript("OnClick", function() SC.MoveTarget(slot, delta) end)
            Tip(a, "Priority", tip)
            return a
        end
        bx.up = Arrow("Up", -1, "Higher priority. With several targets in view, the key goes for the highest one.")
        bx.up:SetPoint("TOPLEFT", T, "TOPLEFT", 2, -4)
        bx.down = Arrow("Down", 1, "Lower priority. With several targets in view, the key goes for the highest one.")
        bx.down:SetPoint("BOTTOMLEFT", T, "BOTTOMLEFT", 2, 4)
    end

    if quest then
        bx.talk:Hide()
        bx.keep:Hide()
        -- Gold "!" on the portrait: this box's mob is picked by the key.
        bx.badge = T:CreateTexture(nil, "OVERLAY", nil, 7)
        bx.badge:SetSize(20, 20)
        bx.badge:SetPoint("BOTTOMRIGHT", bx.portrait, "BOTTOMRIGHT", 4, -4)
        bx.badge:SetTexture(QUEST_ICON)
    end
    return bx
end

local function BuildTarget()
    ui.boxes = {}
    for slot = 1, SC.MAX_TARGETS do ui.boxes[slot] = BuildTargetBox(slot) end
    ui.questBox = BuildTargetBox(SC.MAX_TARGETS + 1, true)
    -- Under the last target: add another.
    ui.addAnother = Btn(F, "+ Add another target", 160, 0, 0, function()
        ui.picking = true
        SC.Refresh()
        if ui.addName then ui.addName:SetFocus() end
    end)
    Tip(ui.addAnother, "Another target", "Your key goes for the highest target in the list that's in view, alive and untagged (the arrows on each box's left edge change the order); each keeps its own Attack/Talk. Up to " .. SC.MAX_TARGETS .. ".")
end

-- Clicking a target's name or portrait targets that mob in game. Targeting is
-- protected, so a secure button sits over each. They're parented to UIParent and
-- placed by screen position (a protected frame anchored to the window would
-- make the window itself protected), and only moved or changed out of combat.
local nameSecure, portSecure = {}, {}

local function NewTargetButton(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    b:SetFrameStrata("MEDIUM")
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    b:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.15)
    b:SetScript("OnEnter", function(self) SC.ShowMobTip(self, self.mobName, true) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    return b
end

-- Puts b over region (screen coords), or hides it.
local function Cover(b, region, name, w, h, dy)
    local l, bottom = region:GetLeft(), region:GetBottom()
    if not (name and l and bottom and region:IsVisible()) then b:Hide(); return end
    b:SetAttribute("macrotext", SC.TargetCmd(name) .. name)
    b.mobName = name
    local s = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, (bottom + (dy or 0)) * s)
    b:SetSize(w * s, h * s)
    b:SetFrameLevel(F:GetFrameLevel() + 30)
    b:Show()
end

local function BuildNameSecure()
    for slot = 1, SC.MAX_TARGETS + 1 do
        portSecure[slot] = NewTargetButton("SpawnCampTargetPortrait" .. slot)
        local b = CreateFrame("Button", "SpawnCampTargetName" .. slot, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "")
        b:SetFrameStrata("MEDIUM")
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
        b:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.15)
        b:SetScript("OnEnter", function(self) SC.ShowMobTip(self, self.mobName, true) end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:Hide()
        nameSecure[slot] = b
    end
end

local function PlaceNameSecure()
    if InCombatLockdown() then return end
    for slot = 1, SC.MAX_TARGETS + 1 do
        local b, bx = nameSecure[slot], ui.boxes[slot] or ui.questBox
        local m = SC.Active(slot)
        if bx.quest then
            local name = SC.QuestShown()
            m = name and { name = name } or nil
        end
        local fs = bx.name
        local l, bottom = fs:GetLeft(), fs:GetBottom()
        local pb = portSecure[slot]
        if pb then
            if m and F:IsShown() and bx.frame:IsShown() then
                Cover(pb, bx.portrait, m.name, bx.portrait:GetWidth(), bx.portrait:GetHeight())
            else
                pb:Hide()
            end
        end
        if not (b and m and F:IsShown() and bx.frame:IsShown() and fs:IsVisible() and l and bottom) then
            if b then b:Hide() end
        else
            b:SetAttribute("macrotext", SC.TargetCmd(m.name) .. m.name)
            b.mobName = m.name
            local s = fs:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local w = math.max(fs:GetStringWidth() or 0, 40)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, bottom * s - 2)
            b:SetSize(w * s, fs:GetHeight() * s + 4)
            b:SetFrameLevel(F:GetFrameLevel() + 30)
            b:Show()
        end
    end
end
-- Recent targets: a pop-out beside the window listing every mob you've
-- targeted, newest first, with Use and remove.

local function BuildRecent()
    RP = Popup("SpawnCampRecent", 380, 60 + RECENT_ROWS * RECENT_H, "Recent targets")
    ui.recentEmpty = Text(RP, "Mobs you've targeted show up here.", 12, -36, "GameFontDisableSmall")
    ui.recentCount = Text(RP, "", 12, -40 - RECENT_ROWS * RECENT_H, "GameFontDisableSmall")
    ui.recent = {}
    for i = 1, RECENT_ROWS do
        local r = CreateFrame("Frame", nil, RP)
        r:SetHeight(RECENT_H - 2)
        r:SetPoint("TOPLEFT", 8, -32 - (i - 1) * RECENT_H)
        r:SetPoint("RIGHT", RP, "RIGHT", -8, 0)
        r.bar = CreateFrame("StatusBar", nil, r)
        r.bar:SetPoint("TOPLEFT", RECENT_H, 0)
        r.bar:SetPoint("BOTTOMRIGHT", -70, 0)
        r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        r.bar:SetMinMaxValues(0, 1)
        r.holder = CreateFrame("Frame", nil, r)
        r.holder:SetSize(RECENT_H - 4, RECENT_H - 4)
        r.holder:SetPoint("LEFT", 1, 0)
        r.name = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 4, 0)
        r.name:SetWidth(130)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.status = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.status:SetPoint("RIGHT", -4, 0)
        r.status:SetJustifyH("LEFT")
        r.status:SetWordWrap(false)
        r.x = CreateFrame("Button", nil, r)
        r.x:SetSize(18, 18)
        r.x:SetPoint("RIGHT", -2, 0)
        r.x:SetNormalFontObject("GameFontRed")
        r.x:SetText("x")
        r.x:SetScript("OnClick", Safe(function() SC.RemoveMob(r.mobName) end))
        Tip(r.x, "Remove", "Takes it off the list. Its sighting history is kept.")
        r.use = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.use:SetSize(44, 18)
        r.use:SetPoint("RIGHT", r.x, "LEFT", -4, 0)
        r.use:SetText("Use")
        r.use:SetScript("OnClick", Safe(function() SC.SetActive(r.mobName) end))
        Tip(r.use, "Use", "Adds it to your targets.")
        r.current = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.current:SetPoint("RIGHT", r.x, "LEFT", -6, 0)
        r.current:SetText("target")
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            recentOffset = math.max(0, recentOffset - d)
            SC.Refresh()
        end)
        ui.recent[i] = r
    end
end

function SC.ToggleRecent()
    if not F then return end
    ShowBeside(RP)
end
-- The log describes one target: the first, or the second when switched.
local function Sel()
    return SC.Active(SC.char.logSlot or 1) or SC.Active(1)
end

local LOG_W = 380
local LOG_H = 138 + HIST_ROWS * 16

-- A drawer beside the window (left by default; right in the settings).
local function BuildLog()
    local P = CreateFrame("Frame", "SpawnCampLog", F, "BackdropTemplate")
    P:SetSize(LOG_W, LOG_H)
    Backdrop(P, 0.9)
    P:EnableMouse(true)
    ui.log = P
    local titleBtn = CreateFrame("Button", nil, P)
    titleBtn:SetPoint("TOPLEFT", 8, -6)
    titleBtn:SetSize(340, 18)
    ui.logTitle = titleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.logTitle:SetPoint("LEFT", 2, 0)
    ui.logTitle:SetWidth(336)
    ui.logTitle:SetJustifyH("LEFT")
    ui.logTitle:SetWordWrap(false)
    titleBtn:SetScript("OnClick", function()
        local count = #SC.Actives()
        if count > 1 then
            SC.char.logSlot = (SC.char.logSlot or 1) % count + 1
            histOffset = 0
            SC.Refresh()
        end
    end)
    local close = CreateFrame("Button", nil, P, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -1, -1)
    close:SetScript("OnClick", function() SC.char.logOpen = false; SC.Refresh() end)
    ui.stats = Text(P, "", 10, -32)
    ui.stats:SetWidth(LOG_W - 20)
    ui.stats:SetWordWrap(true)

    Text(P, "Known respawn time", 10, -72)
    ui.min = Edit(P, 30, 118, -68, function(t)
        local m = Sel(); if m then m.manualMin = tonumber(t) or 0 end
    end, true)
    Text(P, "to", 158, -72)
    ui.max = Edit(P, 30, 172, -68, function(t)
        local m = Sel(); if m then m.manualMax = tonumber(t) or 0 end
    end, true)
    Text(P, "min (empty = from the log)", 212, -72)
    Tip(Btn(P, "It died now", 100, 10, -94, function()
        local m = Sel(); if m then SC.Observe(m.name, "D", nil, nil, "you", { manual = true }) end
    end), "It died now", "Logs a death now, for one SpawnCamp missed.")
    Tip(Btn(P, "It's up now", 100, 114, -94, function()
        local m = Sel(); if m then SC.Observe(m.name, "A", nil, nil, "you", { manual = true }) end
    end), "It's up now", "Logs a spawn now, for one SpawnCamp missed.")
    ui.histCount = Text(P, "", 10, -122, "GameFontDisableSmall")
    ui.hist = {}
    for i = 1, HIST_ROWS do
        local r = CreateFrame("Frame", nil, P)
        r:SetHeight(16)
        r:SetPoint("TOPLEFT", 8, -136 - (i - 1) * 16)
        r:SetPoint("RIGHT", P, "RIGHT", -6, 0)
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
-- Build: settings panel (general)
------------------------------------------------------------------------------

local function BuildSettings(P)
    Header(P, "Settings", -8)
    Text(P, "Share sightings with:", 8, -30)
    local tip = "Sends spawns and deaths you see to other SpawnCamp users there, and logs theirs for mobs you watch."
    Check(P, "Party", 130, -24,
        function() return SC.char.shareParty end, function(v) SC.char.shareParty = v end, tip)
    Check(P, "Raid", 200, -24,
        function() return SC.char.shareRaid end, function(v) SC.char.shareRaid = v end, tip)
    Check(P, "Guild", 266, -24,
        function() return SC.char.shareGuild end, function(v) SC.char.shareGuild = v end, tip)
    Check(P, "Show mobs I've already killed", 4, -48,
        function() return SC.char.showDone end, function(v) SC.char.showDone = v end,
        "When you get the kill on a mob it's marked \"got\" in Recent. Ticked, it stays listed; unticked, it's hidden.")
    Check(P, "Sound with alerts", 240, -48,
        function() return SC.char.sound end, function(v) SC.char.sound = v end)
    Check(P, "Lock window", 4, -72,
        function() return SC.char.locked end, function(v) SC.char.locked = v end)
    Check(P, "Log on the right side", 240, -72,
        function() return SC.char.logRight end, function(v) SC.char.logRight = v end,
        "Unticked, the log opens on the left of the window.")
    Check(P, "Alert when a mob spawns", 4, -96,
        function() return SC.char.alertSpawn end, function(v) SC.char.alertSpawn = v end,
        "Loud alert (raid warning sound) when a watched mob is seen alive.")
    Check(P, "Respawn dings", 240, -96,
        function() return SC.char.alarm end, function(v) SC.char.alarm = v end,
        "Soft ding: a set time before the earliest respawn, when the respawn window opens, and when the average respawn time is reached.")
    Text(P, "Early ding", 8, -124)
    ui.lead = Edit(P, 36, 66, -120, function(t) SC.char.lead = tonumber(t) or 0 end, true)
    Text(P, "seconds before the earliest respawn (0 = off)", 112, -124)
    Text(P, "Right-click Attack or Talk for their options.", 8, -150, "GameFontDisableSmall")
end

------------------------------------------------------------------------------
-- Nearby picker
------------------------------------------------------------------------------

local NEAR_ROWS = 16

local CLASS_TAG = { worldboss = "|cffff4040boss|r", rareelite = "|cffd0d0ffrare elite|r",
                    rare = "|cffd0d0ffrare|r", elite = "|cffffd100elite|r" }

local EMPTY_TEXT = "Nothing yet. The list fills from what your game\nalready shows: nameplates, your target and\nyour mouseover.\n\nTurn on nameplates (V = enemies, Shift-V =\nfriendly NPCs), or mouse over a mob, then\npress Scan now.\n\nObjects (chests, quest items) have no nameplate:\ntype their name instead."
local HIDDEN_TEXT = "|cffff8040The game hides NPC names here|r\n(dungeons do), so they can't be listed.\n\nType the name exactly as your target\nframe shows it."

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
            local current = SC.IsActive(item.name)
            r.use:SetShown(not current)
            r.current:SetShown(current)
            r.mobName, r.hostile, r.ctype = item.name, e.hostile, e.ctype
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
    N = Popup("SpawnCampNearby", 320, 92 + NEAR_ROWS * 18, "Nearby mobs")
    local scan = Btn(N, "Scan now", 74, 104, -6, function()
        N.report:SetText((SC.ScanNearby()))
        RefreshNearby()
    end)
    Tip(scan, "Scan now", "Reads every nameplate, your target and your mouseover right now. The list also fills by itself a few times a second.")
    N.count = Text(N, "", 8, -30 - NEAR_ROWS * 18 - 4)
    N.report = Text(N, "", 8, -30 - NEAR_ROWS * 18 - 20)
    N.report:SetWidth(304)
    N.empty = Text(N, EMPTY_TEXT, 8, -32)
    N.rows = {}
    for i = 1, NEAR_ROWS do
        local r = CreateFrame("Frame", nil, N)
        r:SetSize(304, 17)
        r:SetPoint("TOPLEFT", 8, -30 - (i - 1) * 18)
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
        r.use = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.use:SetSize(46, 17)
        r.use:SetPoint("RIGHT", 0, 0)
        r.use:SetText("Use")
        r.use:SetScript("OnClick", Safe(function()
            if SC.char.mobs[r.mobName] then
                SC.SetActive(r.mobName)
            else
                local m = SC.AddMob(r.mobName, r.hostile == false and "interact" or "attack")
                if m and r.ctype then m.ctype = r.ctype; SC.Refresh() end
            end
            RefreshNearby()
        end))
        Tip(r.use, "Use this mob", "Makes it your target. Hostile ones start on Attack, friendly ones on Talk.")
        r.current = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.current:SetPoint("RIGHT", -4, 0)
        r.current:SetText("target")
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
end

function SC.ToggleNearby()
    if not F then return end
    ShowBeside(N)
    RefreshNearby()
end

------------------------------------------------------------------------------
-- Quest picker
------------------------------------------------------------------------------

local QUEST_ROWS = 16
local QUEST_EMPTY = "No quest mobs found.\n\nKill objectives from your quest log show up\nhere. For quests where a mob drops an item,\nthe mob shows once you've seen it nearby\n(nameplates on, or mouse over it)."

function SC.RefreshQuests()
    if not (Q and Q:IsShown()) then return end
    local list = SC.QuestMobs()
    Q.offset = math.max(0, math.min(Q.offset or 0, #list - QUEST_ROWS))
    for i, r in ipairs(Q.rows) do
        local item = list[i + Q.offset]
        if item then
            local e = item.nearby
            local color = item.finished and "|cff999999" or (e and e.hostile == false and "|cff60c0ff" or "|cffff8080")
            local bits = {}
            if item.have and item.need then
                bits[#bits + 1] = (item.finished and "|cff40ff40" or "|cffffd100") .. item.have .. "/" .. item.need .. "|r"
            end
            if item.quest then bits[#bits + 1] = "|cffc0c0c0" .. item.quest .. "|r" end
            if e then bits[#bits + 1] = "|cff80ff80nearby|r" end
            r.name:SetText(color .. item.name .. "|r")
            r.info:SetText(table.concat(bits, "  "))
            local current = SC.IsActive(item.name)
            r.use:SetShown(not current)
            r.current:SetShown(current)
            if not current and SC.char.anyQuest and SC.IsQuestWanted(item.name) then
                bits[#bits + 1] = "|cff40ff40on key|r"
                r.info:SetText(table.concat(bits, "  "))
            end
            r.mobName, r.hostile, r.ctype = item.name, e and e.hostile, e and e.ctype
            r.tipQuest, r.tipObjective = item.quest, item.objective
            r:Show()
        else
            r:Hide()
        end
    end
    Q.empty:SetShown(#list == 0)
    Q.count:SetText(#list > QUEST_ROWS and (#list .. " mobs, scroll for more") or "")
end

local function BuildQuests()
    Q = Popup("SpawnCampQuests", 400, 60 + QUEST_ROWS * 18, "Quest mobs")
    Q.count = Text(Q, "", 8, -30 - QUEST_ROWS * 18 - 4)
    Q.empty = Text(Q, QUEST_EMPTY, 8, -32)
    Q.rows = {}
    for i = 1, QUEST_ROWS do
        local r = CreateFrame("Frame", nil, Q)
        r:SetSize(384, 17)
        r:SetPoint("TOPLEFT", 8, -30 - (i - 1) * 18)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 2, 0)
        r.name:SetWidth(140)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.info:SetPoint("RIGHT", -52, 0)
        r.info:SetJustifyH("LEFT")
        r.info:SetWordWrap(false)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.tipQuest and not self.tipObjective then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.mobName or "")
            if self.tipQuest then GameTooltip:AddLine(self.tipQuest, 1, 0.82, 0) end
            if self.tipObjective then GameTooltip:AddLine(self.tipObjective, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.use = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.use:SetSize(46, 17)
        r.use:SetPoint("RIGHT", 0, 0)
        r.use:SetText("Use")
        r.use:SetScript("OnClick", Safe(function()
            if SC.char.mobs[r.mobName] then
                SC.SetActive(r.mobName)
            else
                local m = SC.AddMob(r.mobName, r.hostile == false and "interact" or "attack")
                if m and r.ctype then m.ctype = r.ctype; SC.Refresh() end
            end
            SC.RefreshQuests()
        end))
        Tip(r.use, "Use this mob", "Adds it to your targets. Starts on Attack unless it's been seen as friendly.")
        r.current = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.current:SetPoint("RIGHT", -4, 0)
        r.current:SetText("target")
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            Q.offset = (Q.offset or 0) - d
            SC.RefreshQuests()
        end)
        Q.rows[i] = r
    end
    Q:SetScript("OnShow", function()
        SC.ScanNearby()
        SC.RefreshQuests()
    end)
end

function SC.ToggleQuests()
    if not F then return end
    ShowBeside(Q)
    SC.RefreshQuests()
end

------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------

local function Build()
    F = CreateFrame("Frame", "SpawnCampFrame", UIParent, "BackdropTemplate")
    F:SetSize(W, 200)
    F:SetPoint("TOP", UIParent, "TOP", 0, -160)
    F:SetFrameStrata("MEDIUM")
    F:SetClampedToScreen(true)
    F:EnableMouse(true)
    F:SetMovable(true)
    F:RegisterForDrag("LeftButton")
    F:SetScript("OnDragStart", function(self) if not SC.char.locked then self:StartMoving() end end)
    F:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    Backdrop(F, 0.8)
    local pos = SC.char.framePos
    if pos then
        F:ClearAllPoints()
        F:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    ui.checks, ui.keys = {}, {}
    BuildTop()
    BuildTarget()
    BuildPicker()
    BuildNameSecure()
    BuildRecent()
    BuildAttackPopup()
    BuildTalkPopup()
    BuildNearby()
    BuildQuests()
    BuildLog()
    ui.panels = {}
    for id, build in pairs({ settings = BuildSettings }) do
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

-- Short, readable key names that fit on the button: "Shift-Wheel Down", "Mouse 4".
local KEY_NAMES = { MOUSEWHEELUP = "Wheel Up", MOUSEWHEELDOWN = "Wheel Down", SPACE = "Space",
                    ESCAPE = "Esc", BACKSPACE = "Backspace", ENTER = "Enter", TAB = "Tab" }
local MOD_NAMES = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift", META = "Cmd" }

function SC.KeyLabel(key)
    local parts = {}
    for part in key:gmatch("[^%-]+") do parts[#parts + 1] = part end
    local base = parts[#parts] or key
    local out = {}
    for i = 1, #parts - 1 do out[#out + 1] = MOD_NAMES[parts[i]] or parts[i] end
    local n = base:match("^BUTTON(%d+)$")
    out[#out + 1] = n and ("Mouse " .. n) or KEY_NAMES[base] or base:gsub("^NUMPAD", "Num ")
    return table.concat(out, "-")
end

local function RefreshAutoQuest()
    local b = ui.autoQuest
    if not b then return end
    if SC.char.anyQuest then
        b:SetText("|cff40ff40Auto Quest|r")
        b:LockHighlight()
    else
        b:SetText("Auto Quest")
        b:UnlockHighlight()
    end
end

local function RefreshKey()
    RefreshAutoQuest()
    for _, b in ipairs(ui.keys) do
        if not (capturing and capturing.button == b) then
            b:SetText(SC.char.key ~= "" and ("|cffffffff" .. SC.KeyLabel(SC.char.key) .. "|r") or "Click to Bind Key")
        end
    end
    local m = SC.Active()
    local quests = #SC.QuestWanted()
    if SC.char.key == "" then
        ui.keyNote:SetText("|cffff6060No key assigned.|r")
    elseif not m and quests == 0 then
        ui.keyNote:SetText(SC.char.anyQuest and "|cff999999Does nothing: no quest mobs needed.|r"
            or "|cff999999Does nothing: no target.|r")
    else
        local state, text = SC.KeyState()
        local color = (state == "on" or state == "lock") and "|cff40ff40" or "|cffffd100"
        local what = m and (m.mode == "attack" and "Attack" or "Talk") or "Attack"
        ui.keyNote:SetText(color .. what .. ": " .. text .. "|r")
    end
end

-- The Auto Quest box: one mob when there's one to show (the only one left, or
-- the one the key last went for), else "Any quest mob" with the count.
local function RefreshQuestBox(bx)
    for _, w in ipairs({ bx.portrait, bx.nameArea, bx.etaBox, bx.attack, bx.clear }) do w:Show() end
    local wanted = SC.QuestWanted()
    local name = SC.QuestShown()
    local info = name and SC.QuestInfo(name)
    -- No name = the generic quest icon, cached under its own key.
    PlacePortrait(name or QUEST_KEY, bx.portrait)
    bx.tipName = name
    local tag = "|cffffd100Auto Quest|r"
    if name then
        bx.name:SetText(name)
        local more = #wanted - 1
        bx.status:SetText(tag .. (info and info.quest and ("  |cffc0c0c0" .. info.quest .. "|r") or "")
            .. (more > 0 and ("  |cff999999+" .. more .. " more|r") or ""))
    else
        bx.name:SetText(#wanted > 0 and "Any quest mob" or "No quest mobs needed")
        local names = table.concat(wanted, ", ")
        bx.status:SetText(tag .. "  |cffc0c0c0" .. (names ~= "" and names or "turn in your quests or pick up new ones") .. "|r")
    end
    if info and info.have and info.need then
        bx.eta:SetText((info.finished and "|cff40ff40" or "|cffffd100") .. info.have .. "/" .. info.need .. "|r")
        bx.avg:SetText("Quest progress")
    else
        bx.eta:SetText("|cffffd100" .. #wanted .. "|r")
        bx.avg:SetText(#wanted == 1 and "mob needed" or "mobs needed")
    end
    SetPressed(bx.attack, true)
end

local function RefreshBox(bx, m, slot)
    for _, w in ipairs({ bx.portrait, bx.nameArea, bx.etaBox, bx.attack, bx.talk, bx.clear, bx.keep }) do w:SetShown(m ~= nil) end
    if not m then bx.up:Hide(); bx.down:Hide(); return end
    PlacePortrait(m.name, bx.portrait)
    bx.tipName = m.name
    if m.partial then
        bx.name:SetText(m.name .. "  |cff999999(search)|r")
        local skipped = 0
        for _ in pairs(m.rejected or {}) do skipped = skipped + 1 end
        bx.status:SetText("|cffc0c0c0Adds any mob with this in its name|r" .. (skipped > 0 and ("  |cff808080(" .. skipped .. " skipped)|r") or ""))
    else
        bx.name:SetText(m.name)
        local state, text = SC.Status(m.name)
        bx.status:SetText(StatusColor(state) .. text .. "|r")
    end
    local big, small, color = SC.ETA(m.name)
    bx.eta:SetText(color .. big .. "|r")
    bx.avg:SetText(small)
    SetPressed(bx.attack, m.mode == "attack")
    SetPressed(bx.talk, m.mode == "interact")
    local n = #SC.Targets()
    bx.up:SetShown(n > 1)
    bx.down:SetShown(n > 1)
    bx.up:SetEnabled(slot > 1)
    bx.down:SetEnabled(slot < n)
end

-- Lays out a box per target and the "add another" button; returns the y below.
local function RefreshTarget()
    local y = -56
    local n = #SC.Actives()
    -- Adding a target (or turning on Auto Quest) closes the picker.
    if (ui.lastN and n > ui.lastN) or (SC.char.anyQuest and not ui.lastAQ) then ui.picking = false end
    ui.lastN, ui.lastAQ = n, SC.char.anyQuest
    for slot = 1, SC.MAX_TARGETS do
        local bx, m = ui.boxes[slot], SC.Active(slot)
        if m then
            bx.frame:ClearAllPoints()
            bx.frame:SetPoint("TOPLEFT", F, "TOPLEFT", 6, y)
            bx.frame:SetPoint("RIGHT", F, "RIGHT", -6, 0)
            bx.frame:Show()
            RefreshBox(bx, m, slot)
            y = y - BOX_H - 4
        else
            bx.frame:Hide()
        end
    end
    local qb = ui.questBox
    if SC.char.anyQuest then
        qb.frame:ClearAllPoints()
        qb.frame:SetPoint("TOPLEFT", F, "TOPLEFT", 6, y)
        qb.frame:SetPoint("RIGHT", F, "RIGHT", -6, 0)
        qb.frame:Show()
        RefreshQuestBox(qb)
        y = y - BOX_H - 4
    else
        qb.frame:Hide()
    end
    -- Nothing on the key: the picker stays open (no cancel).
    local empty = n == 0 and not SC.char.anyQuest
    local pick = n < SC.MAX_TARGETS and (empty or ui.picking)
    ui.picker:ClearAllPoints()
    ui.addAnother:ClearAllPoints()
    if pick then
        ui.picker:SetPoint("TOPLEFT", F, "TOPLEFT", 6, y)
        ui.picker:SetPoint("RIGHT", F, "RIGHT", -6, 0)
        ui.picker:Show()
        ui.pickCancel:SetShown(not empty)
        y = y - BOX_H - 4
    else
        ui.picker:Hide()
    end
    if not pick and n < SC.MAX_TARGETS then
        ui.addAnother:SetPoint("TOPLEFT", F, "TOPLEFT", 8, y)
        ui.addAnother:Show()
        y = y - 26
    else
        ui.addAnother:Hide()
    end
    return y
end
local function RefreshRecent()
    if not (RP and RP:IsShown()) then return end
    local list = {}
    for _, n in ipairs(SC.char.order) do
        local m = SC.char.mobs[n]
        if m and (m.hunting or SC.char.showDone or SC.IsActive(n)) then list[#list + 1] = n end
    end
    recentOffset = math.max(0, math.min(recentOffset, #list - RECENT_ROWS))
    for i, r in ipairs(ui.recent) do
        local n = list[i + recentOffset]
        if n then
            local m = SC.char.mobs[n]
            local state, text, frac = SC.Status(n)
            local c = BAR[state] or BAR.none
            r.mobName = n
            r.bar:SetStatusBarColor(c[1], c[2], c[3], 0.45)
            r.bar:SetValue((state == "up" or state == "window" or state == "late") and 1 or (frac or 0))
            r.name:SetText(n .. (m.hunting and "" or " |cff40ff40(got)|r"))
            r.status:SetText(StatusColor(state) .. text .. "|r")
            local current = SC.IsActive(n)
            r.use:SetShown(not current)
            r.current:SetShown(current)
            PlacePortrait(n, r.holder)
            r:Show()
        else
            r:Hide()
        end
    end
    ui.recentEmpty:SetShown(#list == 0)
    ui.recentCount:SetText(#list > RECENT_ROWS and (#list .. " mobs, scroll for more") or "")
end
local function RefreshMobPanel()
    local mob = Sel()
    if not mob then return false end
    local lo, avg, hi, n = SC.Stats(mob.name)
    if n > 0 then
        ui.stats:SetText(string.format("Respawn time (death until seen again), from %d kill%s:\nfastest |cffffffff%s|r   average |cffffd100%s|r   slowest |cffffffff%s|r",
            n, n == 1 and "" or "s", SC.Clock(lo), SC.Clock(avg), SC.Clock(hi)))
    elseif lo then
        ui.stats:SetText("Respawn time from your known time:\n" .. SC.Clock(lo) .. (hi and (" to " .. SC.Clock(hi)) or ""))
    else
        ui.stats:SetText("|cffccccccNo respawn time yet. It needs a death and then the\nmob seen alive again.|r")
    end
    SetEditText(ui.min, (mob.manualMin or 0) > 0 and tostring(mob.manualMin) or "")
    SetEditText(ui.max, (mob.manualMax or 0) > 0 and tostring(mob.manualMax) or "")

    local events = SC.History(mob.name).events
    histOffset = math.max(0, math.min(histOffset, #events - HIST_ROWS))
    ui.histCount:SetText(#events == 0 and "No sightings yet. Deaths and spawns show here with their times."
        or string.format("%d sighting%s, newest first%s", #events, #events == 1 and "" or "s",
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

local function RefreshPopups()
    local A, I = SC.char.attack, SC.char.interact
    SetEditText(ui.spell, A.spell)
    local sname, cast = SpellInfo(A.spell)
    if strtrim(A.macro or "") ~= "" then
        ui.spellNote:SetText("|cffffd100Your macro lines are used instead of the spell.|r")
    elseif A.spell == "" then
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
        if F then F:Hide(); HideSidePanels() end
        if not InCombatLockdown() then
            for _, b in pairs(nameSecure) do b:Hide() end
            for _, b in pairs(portSecure) do b:Hide() end
        end
        return
    end
    if not F then Build() end
    F:Show()
    for _, p in pairs(portraits) do p:Hide() end

    RefreshKey()
    local y = RefreshTarget()
    if not SC.Active(SC.char.logSlot or 1) then SC.char.logSlot = 1 end
    local m = SC.Active(SC.char.logSlot or 1) or SC.Active(1)
    ui.logToggle:SetShown(m ~= nil)
    if SC.char.logRight then
        ui.logToggle:SetText(SC.char.logOpen and "Log <" or "Log >")
    else
        ui.logToggle:SetText(SC.char.logOpen and "> Log" or "< Log")
    end
    if m and SC.char.logOpen then
        ui.log:ClearAllPoints()
        if SC.char.logRight then
            ui.log:SetPoint("TOPLEFT", F, "TOPRIGHT", 2, 0)
        else
            ui.log:SetPoint("TOPRIGHT", F, "TOPLEFT", -2, 0)
        end
        ui.logTitle:SetText("Log: " .. m.name .. (SC.Active(2) and "  |cff999999(click for the next target)|r" or ""))
        ui.log:Show()
        RefreshMobPanel()
    else
        ui.log:Hide()
    end
    SetEditText(ui.lead, tostring(SC.char.lead or 0))
    RefreshRecent()
    for _, cb in ipairs(ui.checks) do cb:SetChecked(cb.get() and true or false) end
    RefreshPopups()

    local panel = SC.char.panel
    if panel ~= "settings" then panel = nil; SC.char.panel = nil end
    local height = -y + 6
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
    if panel then height = height + PANEL_H[panel] + 6 end
    F:SetHeight(height)
    pcall(PlaceNameSecure)
end

-- Focuses the name box (when the game hides a target's name).
function SC.FocusAddName()
    SC.char.shown = true
    ui.picking = true
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
        pcall(SC.RefreshQuests)
    end
end)

SC.On("PLAYER_REGEN_DISABLED", function() if capturing then StopCapture() end end)
