-- SpawnCamp window. Always on screen:
--
--   [icon] SpawnCamp                              [Recent] [Log] [gear] [x]
--   [  R  ]  * On target                                          [Unassign]
--            Attack - Vicious Owlbeast - won't swap
--   [ Add a mob or search...       ] [My Target] [Nearby] [Quest] [Auto Quest]
--   TARGETS  2 / 8
--   | (portrait) Vicious Owlbeast [KEY]   DUE        [sword] [bubble] [Clear]
--   |            dead 4:59                3:03 over avg               Keep [x]
--
-- The key works on the targets, top first; with none it does nothing. The
-- card the key is on is marked KEY. Sword / bubble are a pressed/raised pair;
-- right-click either for its options. Recent, the log, the settings and the
-- other lists open beside the window. The skin (modern flat or classic red
-- and gold) is the only look option.

local ADDON, SC = ...

local F
local ui = {}
local recentOffset, histOffset = 0, 0
local RECENT_ROWS, HIST_ROWS = 14, 14
local RECENT_H = 22
local W = 520
local PANEL_H = { settings = 268 }   -- settings panel height
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

------------------------------------------------------------------------------
-- Look: the DrangedAddons house kit (Theme.lua / Widgets.lua / Window.lua).
-- Every window and side panel sits in a kit-themed shell, so it matches
-- EllesmereUI: Match EllesmereUI, default, EllesmereUI Style, WoW Forever,
-- Blizzard Style, Classic WoW UI. The pick (SC.db.theme) applies live.
------------------------------------------------------------------------------

local UI = SC.UI
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MARGIN = 12   -- the shell's border around a window's content

-- Mode colours: red attack, blue talk, gold Auto Quest.
local MODE_COLOR = {
    attack = { 0.80, 0.22, 0.16 },
    talk = { 0.30, 0.58, 0.92 },
    quest = { 1, 0.82, 0 },
}

local function Flat() return SC.ActiveTheme() == "eui" end

-- The themed frame behind a window's content: a child that reaches MARGIN past
-- every edge and sits under the content's own regions.
local shells = {}
local function Shell(content, title)
    content:SetFrameLevel(math.max(content:GetFrameLevel(), 10))
    local shell = CreateFrame("Frame", nil, content, "BackdropTemplate")
    shell:SetPoint("TOPLEFT", -MARGIN, MARGIN)
    shell:SetPoint("BOTTOMRIGHT", MARGIN, -MARGIN)
    shell:SetFrameLevel(content:GetFrameLevel() - 5)
    shell:EnableMouse(false)
    shell.nsTitle = title
    content.scShell = shell
    shells[#shells + 1] = { shell = shell, content = content }
    SC.ThemeRegisterWindow(shell)
    return shell
end

-- Every panel button under a frame goes on the kit's list (flat with an
-- accent underline in EllesmereUI Style, the game's red button otherwise).
local function RegisterButtons(f, depth)
    depth = depth or 0
    if not (f and f.GetChildren) or depth > 12 then return end
    for _, c in ipairs({ f:GetChildren() }) do
        if type(c) == "table" then
            if c.GetObjectType and c:GetObjectType() == "Button" and type(c.Left) == "table"
                and type(c.Middle) == "table" and type(c.Right) == "table" then
                SC.ThemeRegisterButton(c)
            end
            RegisterButtons(c, depth + 1)
        end
    end
end

-- Re-skins everything (after a look change, or once after building).
local function ReskinAll()
    for _, w in ipairs(shells) do
        SC.ApplyTheme(w.shell)
        SC.NoteThemeFonts(w.content)
    end
end

-- A look picked in the settings re-skins all SpawnCamp windows at once.
local kitSetLook = SC.SetLook
function SC.SetLook(key)
    kitSetLook(key)
    ReskinAll()
    SC.Refresh()
end

-- A small icon button (header tools).
local function IconButton(parent, texture, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(texture)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    return b
end

-- A card or box border: the house panel line.
local function BoxBorder(f)
    f:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
end

local function Btn(parent, text, w, x, y, onClick)
    local b = UI.Button(parent, text, w, 22, Safe(onClick))
    b:SetPoint("TOPLEFT", x, y)
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

-- House rule: saves on Enter and on focus loss; Esc puts the old value back.
-- live = also save while typing (a filter box), with HasFocus deciding, since
-- OnTextChanged's user-input flag isn't reliable on Forever.
local function Edit(parent, w, x, y, onSave, numeric, live)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetPoint("TOPLEFT", x + 6, y)
    e:SetAutoFocus(false)
    if numeric then e:SetNumeric(true) end
    local function save(self) onSave(self:GetText() or "") end
    e:SetScript("OnEditFocusGained", function(self) self.scOld = self:GetText() or "" end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self)
        self.scCancel = true
        self:SetText(self.scOld or "")
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        if self.scCancel then self.scCancel = nil else save(self) end
        SC.Refresh()
    end)
    if live then
        e:SetScript("OnTextChanged", function(self) if self:HasFocus() then save(self) end end)
    end
    return e
end

-- A box inside a window: the house panel colours.
local function Backdrop(f)
    UI.Backdrop(f)
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
    UI.Backdrop(e, 0.1, 0.1, 0.11, 1)
    local function save(self) onSave(self:GetText() or "") end
    e:SetScript("OnEditFocusGained", function(self) self.scOld = self:GetText() or "" end)
    e:SetScript("OnEscapePressed", function(self)
        self.scCancel = true
        self:SetText(self.scOld or "")
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        if self.scCancel then self.scCancel = nil else save(self) end
        SC.ApplyBindings()
        SC.Refresh()
    end)
    e:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    return e
end

local function SetEditText(e, text)
    if not e:HasFocus() then e:SetText(text or "") end
end

local function Header(parent, text, y)
    local fs = Text(parent, text, 8, y, "GameFontNormal")
    local line = parent:CreateTexture(nil, "ARTWORK")
    local r, g, b = SC.AccentColor()
    line:SetColorTexture(r, g, b, 0.3)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    return fs
end

local function Popup(name, w, h, title)
    local p = CreateFrame("Frame", name, UIParent)
    p:SetSize(w, h)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p.title = Text(p, title, 10, -10, "GameFontNormal")
    Shell(p, p.title)
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
    SC.ApplyBindings()
    SC.Refresh()
end

local function SpellIcon(name)
    if not name or name == "" then return nil end
    local ok, t
    if C_Spell and C_Spell.GetSpellTexture then ok, t = pcall(C_Spell.GetSpellTexture, name) end
    if (not ok or not t) and GetSpellTexture then ok, t = pcall(GetSpellTexture, name) end
    return ok and t or nil
end

-- Your spellbook: { {name, sub, icon} } for spells you can cast (no passives,
-- nothing you haven't learned). Retail-style C_SpellBook first, the older
-- spellbook calls if that's missing.
function SC.PlayerSpells()
    local out = {}
    local function add(name, sub, icon)
        name, sub = SC.Plain(name), SC.Plain(sub)
        if type(name) ~= "string" or name == "" then return end
        out[#out + 1] = { name = name, sub = type(sub) == "string" and sub or "", icon = SC.Plain(icon) }
    end
    pcall(function()
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
            local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
            local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
            for l = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
                local li = C_SpellBook.GetSpellBookSkillLineInfo(l)
                if li and not li.shouldHide and not li.offSpecID then
                    for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                        local it = C_SpellBook.GetSpellBookItemInfo(i, bank)
                        if it and (SPELL == nil or it.itemType == SPELL) and not it.isPassive and not it.isOffSpec then
                            add(it.name, it.subName, it.iconID)
                        end
                    end
                end
            end
        elseif GetNumSpellTabs and GetSpellTabInfo then
            local BOOK = BOOKTYPE_SPELL or "spell"
            for t = 1, GetNumSpellTabs() do
                local _, _, offset, num = GetSpellTabInfo(t)
                for i = offset + 1, offset + num do
                    local kind = GetSpellBookItemInfo and GetSpellBookItemInfo(i, BOOK)
                    local passive = IsPassiveSpell and IsPassiveSpell(i, BOOK)
                    if (kind == nil or kind == "SPELL") and not passive then
                        local name, sub = GetSpellBookItemName(i, BOOK)
                        add(name, sub, GetSpellBookItemTexture and GetSpellBookItemTexture(i, BOOK))
                    end
                end
            end
        end
    end)
    return out
end

-- Your saved macros (account, then character).
function SC.SavedMacros()
    local out = {}
    if not (GetNumMacros and GetMacroInfo) then return out end
    local na, nc = GetNumMacros()
    local maxA = type(MAX_ACCOUNT_MACROS) == "number" and MAX_ACCOUNT_MACROS or 120
    local function add(i, where)
        local name, icon, body = GetMacroInfo(i)
        if name then out[#out + 1] = { name = name, icon = icon, body = body, where = where } end
    end
    for i = 1, na or 0 do add(i, "account") end
    for i = maxA + 1, maxA + (nc or 0) do add(i, "character") end
    return out
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
        self:SetText("|cffffd100Press...|r")
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

local MODE_SIZE = 38

local function Gradient(tex, top, bottom)
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and pcall(tex.SetGradient, tex, "VERTICAL",
        CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    if not ok then tex:SetColorTexture(top[1], top[2], top[3], 1) end
end

local function ModeButton(parent, icon, onLeft, onRight, title, body)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local size = MODE_SIZE
    b:SetSize(size, size)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetBackdrop({ edgeFile = WHITE, edgeSize = 3 })
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
    b.shine:SetHeight(size * 0.4)
    b.shine:SetColorTexture(1, 1, 1, 0.10)
    b.inset = b:CreateTexture(nil, "BORDER")
    b.inset:SetPoint("TOPLEFT", 3, -3)
    b.inset:SetPoint("TOPRIGHT", -3, -3)
    b.inset:SetHeight(8)
    b.inset:SetColorTexture(0, 0, 0, 0.45)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    b:GetHighlightTexture():SetVertexColor(1, 0.8, 0.3, 0.12)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(size - 12, size - 12)
    b.icon:SetTexture(icon)
    b.icon:SetDesaturated(true)
    b:SetScript("OnClick", Safe(function(self, button)
        if button == "RightButton" then onRight(self) else onLeft(self) end
    end))
    Tip(b, title, body)
    return b
end

-- EllesmereUI Style: flat squares lit in the mode's colour. Every other look:
-- red with gold trim, pressed in.
local function SetPressed(b, pressed)
    b.icon:ClearAllPoints()
    b.icon:SetDesaturated(true)
    b.icon:SetAlpha(1)
    local edge = Flat() and 1 or 3
    if b.scEdge ~= edge then
        b.scEdge = edge
        b:SetBackdrop({ edgeFile = WHITE, edgeSize = edge })
        b.fill:ClearAllPoints()
        b.fill:SetPoint("TOPLEFT", edge, -edge)
        b.fill:SetPoint("BOTTOMRIGHT", -edge, edge)
    end
    if Flat() then
        b.glow:Hide()
        b.shine:Hide()
        b.inset:Hide()
        b.icon:SetPoint("CENTER", 0, 0)
        if pressed then
            local c = b.accent or MODE_COLOR.attack
            Gradient(b.fill, { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55 }, { c[1] * 0.85, c[2] * 0.85, c[3] * 0.85 })
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            b.icon:SetVertexColor(1, 0.92, 0.75)
        else
            b.fill:SetColorTexture(0.09, 0.09, 0.09, 1)
            b:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
            b.icon:SetVertexColor(0.6, 0.6, 0.62)
        end
        return
    end
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

local AP, TP, N, RP, Q, AQ, IG
local CH   -- the list chooser beside the Attack options

local function HideSidePanels(except)
    for _, p in ipairs({ AP, TP, N, RP, Q, AQ, IG, ui.settingsPopup }) do
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
        p:SetPoint("TOPLEFT", beside, "TOPRIGHT", MARGIN * 2 + 2, 0)
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
        if p and p:IsShown() and not p:IsMouseOver() and not (p.opener and p.opener:IsMouseOver())
            and not (CH and CH:IsShown() and CH:IsMouseOver()) then
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

------------------------------------------------------------------------------
-- Chooser: a list with icons and a text filter, beside the Attack options.
------------------------------------------------------------------------------

local CH_ROWS, CH_H = 14, 22

local function RefreshChooser()
    if not (CH and CH:IsShown() and CH.items) then return end
    local all = CH.items()
    local f = CH.filterText or ""
    local list = {}
    for _, it in ipairs(all) do
        if f == "" or it.text:lower():find(f, 1, true) or (it.sub and it.sub:lower():find(f, 1, true)) then
            list[#list + 1] = it
        end
    end
    CH.offset = math.max(0, math.min(CH.offset or 0, #list - CH_ROWS))
    for i = 1, CH_ROWS do
        local r, it = CH.rows[i], list[i + CH.offset]
        if it then
            r.item = it
            r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.icon:SetShown(not it.noIcon)
            r.text:SetText(it.text .. (it.sub and it.sub ~= "" and ("  |cff999999" .. it.sub .. "|r") or ""))
            r.sel:SetShown(it.selected and true or false)
            r:Show()
        else
            r.item = nil
            r:Hide()
        end
    end
    CH.count:SetText(#list > CH_ROWS and (#list .. " found, scroll for more") or (#list == 0 and "Nothing matches." or ""))
end
SC.RefreshChooser = RefreshChooser

local function BuildChooser()
    CH = Popup("SpawnCampChooser", 300, 96 + CH_ROWS * CH_H, "")
    CH.title = Text(CH, "", 10, -10, "GameFontNormal")
    CH.filter = Edit(CH, 160, 8, -32, function(t) CH.filterText = strtrim(t):lower(); CH.offset = 0; RefreshChooser() end, nil, true)
    local hint = CH.filter:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("type to filter")
    local function showHint() hint:SetShown(not CH.filter:HasFocus() and (CH.filter:GetText() or "") == "") end
    CH.filter:HookScript("OnEditFocusGained", showHint)
    CH.filter:HookScript("OnEditFocusLost", showHint)
    CH.filter:HookScript("OnTextChanged", showHint)
    CH.ranks = Check(CH, "Show all ranks", 182, -30,
        function() return SC.char.showRanks end,
        function(v) SC.char.showRanks = v; CH.offset = 0; RefreshChooser() end,
        "Off: one line per spell, cast at your highest rank. On: every rank you know, so you can pick a lower one.")
    CH.rows = {}
    for i = 1, CH_ROWS do
        local r = CreateFrame("Button", nil, CH)
        r:SetSize(284, CH_H - 1)
        r:SetPoint("TOPLEFT", 8, -58 - (i - 1) * CH_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        r.sel:SetColorTexture(1, 0.82, 0, 0.15)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(CH_H - 3, CH_H - 3)
        r.icon:SetPoint("LEFT", 2, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", Safe(function(self)
            if self.item and CH.onPick then
                CH.onPick(self.item)
                CH:Hide()
                SC.ApplyBindings()
                SC.Refresh()
            end
        end))
        r:SetScript("OnEnter", function(self)
            if not (self.item and self.item.tip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.item.text)
            GameTooltip:AddLine(self.item.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d) CH.offset = (CH.offset or 0) - d; RefreshChooser() end)
        CH.rows[i] = r
    end
    CH.count = Text(CH, "", 10, -62 - CH_ROWS * CH_H, "GameFontDisableSmall")
end

local function OpenChooser(title, items, onPick, ranks)
    if CH:IsShown() and CH.title:GetText() == title then CH:Hide(); return end
    CH.title:SetText(title)
    CH.items, CH.onPick = items, onPick
    CH.ranks:SetShown(ranks and true or false)
    CH.filterText, CH.offset = "", 0
    CH.filter:SetText("")
    CH:ClearAllPoints()
    CH:SetPoint("TOPLEFT", AP, "TOPRIGHT", 2, 0)
    CH:Show()
    CH.ranks:SetChecked(SC.char.showRanks and true or false)
    RefreshChooser()
end

-- Spell lines for the chooser. Ranks hidden: one line per spell (the key
-- casts it by name, which uses your highest rank).
local function SpellItems()
    local A = SC.char.attack
    local out = { { text = "None", sub = "auto attack only", noIcon = true, value = "", selected = A.spell == "" } }
    local spells, seen = SC.PlayerSpells(), {}
    local showRanks = SC.char.showRanks and true or false
    local function clean(t)
        return strtrim((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):lower()
    end
    for i = #spells, 1, -1 do
        local s = spells[i]
        local sub = clean(s.sub)
        local ranked = sub:find("rank", 1, true) ~= nil or sub:match("^%d+$") ~= nil
        local key = clean(s.name)
        if showRanks or not seen[key] then
            seen[key] = true
            local value = (showRanks and ranked) and (s.name .. "(" .. s.sub .. ")") or s.name
            table.insert(out, 2, { text = s.name, sub = (showRanks or not ranked) and s.sub or "", icon = s.icon,
                value = value, selected = A.spell == value })
        end
    end
    -- Ranks hidden: the highest rank came last in the book, so it's the one kept.
    return out
end

SC._SpellItems = SpellItems

local function MacroItems()
    local A = SC.char.attack
    local out = { { text = "None", sub = "use the spell", noIcon = true, value = "", selected = (A.macroName or "") == "" } }
    for _, m in ipairs(SC.SavedMacros()) do
        out[#out + 1] = { text = m.name, sub = m.where, icon = m.icon, value = m.name, tip = m.body,
            selected = A.macroName == m.name }
    end
    return out
end

local function BuildAttackPopup()
    local A = SC.char.attack
    AP = Popup("SpawnCampAttackOptions", 380, 196, "Attack  |T" .. SWORD .. ":14|t")
    AP:HookScript("OnHide", function() if CH then CH:Hide() end end)
    local function Slot(y, label)
        Text(AP, label, 12, y - 6)
        local s = CreateFrame("Button", nil, AP)
        s:SetSize(206, 26)
        s:SetPoint("TOPLEFT", 56, y)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetSize(24, 24)
        s.icon:SetPoint("LEFT", 0, 0)
        s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.text:SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
        s.text:SetPoint("RIGHT", 0, 0)
        s.text:SetJustifyH("LEFT")
        s.text:SetWordWrap(false)
        return s
    end
    ui.spellSlot = Slot(-34, "Spell")
    ui.spellSlot:RegisterForDrag("LeftButton")
    ui.spellSlot:SetScript("OnReceiveDrag", TakeDroppedSpell)
    local pickSpell = function()
        OpenChooser("Choose a spell", SpellItems, function(it) A.spell = it.value end, true)
    end
    ui.spellSlot:SetScript("OnClick", Safe(function()
        if GetCursorInfo and GetCursorInfo() then TakeDroppedSpell() else pickSpell() end
    end))
    Tip(Btn(AP, "Choose spell", 100, 268, -36, pickSpell), "Choose spell", "Lists your spells to pick from, with a filter.")
    Wrapped(AP, "Or drag a spell from your spellbook onto the icon. None = auto attack only.", 12, -66, 356)
    ui.spellNote = Text(AP, "", 12, -84)

    ui.macroSlot = Slot(-110, "Macro")
    Tip(Btn(AP, "Choose macro", 100, 268, -112, function()
        OpenChooser("Choose a macro", MacroItems, function(it) A.macroName = it.value end)
    end), "Choose macro", "Lists your saved macros (/m).")
    Wrapped(AP, "A saved macro from /m runs in place of the spell, after the mob is targeted. Edit it in /m and the key picks up the change.", 12, -142, 356)
    ui.macroNote = Text(AP, "", 12, -172)
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
    F.title = Text(F, "SpawnCamp", 26, -7, "GameFontNormal")

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
    gear:SetScript("OnClick", function() ShowBeside(ui.settingsPopup) end)
    ui.gear = gear
    Tip(gear, "Settings", "Sharing, alerts, sound, the list and the log side.")

    -- Header tools as icons: Recent, Log, Settings.
    local logIcon = IconButton(F, "Interface\\Icons\\INV_Misc_Book_09", 16, function()
        SC.char.logOpen = not SC.char.logOpen
        SC.Refresh()
    end)
    logIcon:SetPoint("RIGHT", gear, "LEFT", -8, 0)
    Tip(logIcon, "Log", "Opens or closes the target's log: respawn times and every sighting.")
    ui.logIcon = logIcon
    local recentIcon = IconButton(F, "Interface\\Icons\\INV_Misc_PocketWatch_01", 16, function() SC.ToggleRecent() end)
    recentIcon:SetPoint("RIGHT", logIcon, "LEFT", -8, 0)
    Tip(recentIcon, "Recent", "Every mob you've targeted before. Pick one again or remove it.")

    -- Key bar: the key as a big chip, and what the next press does.
    local bar = F:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar:SetPoint("TOPLEFT", 1, -26)
    bar:SetPoint("TOPRIGHT", -1, -26)
    bar:SetHeight(44)
    bar:SetColorTexture(0.1, 0.1, 0.11, 0.9)
    local chip = KeyButton(F, 10, -31, SC.char)
    chip.scBigFont = true
    chip:SetSize(84, 34)
    ui.keyDot = F:CreateTexture(nil, "ARTWORK")
    ui.keyDot:SetSize(8, 8)
    ui.keyDot:SetPoint("TOPLEFT", 106, -38)
    ui.keyDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    ui.keyState = Text(F, "", 118, -35, "GameFontNormal")
    ui.keyDetail = Text(F, "", 106, -53, "GameFontHighlightSmall")
    ui.keyDetail:SetWidth(330)
    ui.keyDetail:SetWordWrap(false)
    ui.clearKey = Btn(F, "Unassign", 64, 0, 0, function()
        SC.char.key = ""
        SC.ApplyBindings()
        SC.Refresh()
    end)
    ui.clearKey:ClearAllPoints()
    ui.clearKey:SetPoint("TOPRIGHT", -10, -40)
    ui.clearKey:SetHeight(18)
    Tip(ui.clearKey, "Unassign", "Removes the key. Your normal binding for it comes back.")
end

local BOX_H = 58   -- height of a target card

-- The add bar: one row, always open under the key bar.
--   [ Add a mob or search...       ] [My Target] [Nearby] [Quest] [Auto Quest]
local function BuildPicker()
    local T = CreateFrame("Frame", nil, F, "BackdropTemplate")
    T:SetHeight(32)
    Backdrop(T)
    ui.picker = T
    local function at(w, x, width)
        w:ClearAllPoints()
        w:SetPoint("LEFT", T, "LEFT", x, 0)
        if width then w:SetWidth(width) end
        if w.GetObjectType and w:GetObjectType() == "Button" then w:SetHeight(22) end
    end
    ui.addName = Edit(T, 202, 0, 0, function() end)
    at(ui.addName, 14)
    local hint = ui.addName:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("Add a mob or search...")
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
    Tip(ui.addName, "Add a mob or search", "Type a name or part of one and press Enter. Adds a search for the typed text: any mob with it in its name, capitals don't matter (\"owl\" finds Vicious Owlbeast). Your key looks for it straight away, and every mob seen that matches is added as its own target. Clear a wrong one and the search skips it from then on.")
    ui.pickMy = Btn(T, "My Target", 74, 0, 0, function() SC.AddTarget(); SC.Refresh() end)
    at(ui.pickMy, 222)
    Tip(ui.pickMy, "My Target", "Adds the mob you have targeted in game to your targets: Attack if hostile, Talk if friendly.")
    ui.pickNear = Btn(T, "Nearby", 62, 0, 0, function() SC.ToggleNearby() end)
    at(ui.pickNear, 300)
    Tip(ui.pickNear, "Nearby", "Lists mobs around you, with a button to use each one.")
    ui.pickQuest = Btn(T, "Quest", 52, 0, 0, function() SC.ToggleQuests() end)
    at(ui.pickQuest, 366)
    Tip(ui.pickQuest, "Quest", "Mobs your current quests want: kill objectives from your quest log, plus mobs nearby that your quests need (item drops too).")
    ui.autoQuest = Btn(T, "Auto Quest", 80, 0, 0, function() SC.SetAnyQuest(not SC.char.anyQuest) end)
    at(ui.autoQuest, 422)
    Tip(ui.autoQuest, "Auto Quest", "On, your key goes for any mob your quests still need, alive and not tagged by someone else, after your own targets. Finished objectives drop off by themselves.")

    ui.listLabel = Text(F, "", 10, 0, "GameFontNormalSmall")
    ui.emptyHint = Text(F, "Nothing on your key yet.\nType a mob's name (or part of it) above and press Enter, or use My Target, Nearby or Quest. Rares pop up here by themselves.", 10, 0, "GameFontDisableSmall")
    ui.emptyHint:SetWidth(490)
    ui.emptyHint:SetWordWrap(true)
end

-- Target boxes, one per slot, left to right:
--   [portrait] Name               ETA 0:15        [sword] [bubble]  [Clear]
--              dead 0:05, ...     Avg 0:20                          Keep [x]

-- The game's rare dragon art. On Forever's target frame (58 px portrait) the
-- silver dragon sits at its own size with its top-right corner 34 px right of
-- and 12 px above the portrait's top-right. Same here, scaled to our portrait
-- and mirrored. Returns false when the client doesn't have the art.
local RARE_DRAGONS = {
    "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged",
    "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver",
}
local function PlaceRareDragon(tex, portrait)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    for _, atlas in ipairs(RARE_DRAGONS) do
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if ok and info and info.file and info.width then
            local w = portrait:GetWidth()
            if type(w) ~= "number" or w <= 0 then w = 52 end
            local s = w / 58
            tex:SetTexture(info.file)
            tex:SetTexCoord(info.rightTexCoord, info.leftTexCoord, info.topTexCoord, info.bottomTexCoord)
            tex:SetSize(info.width * s, info.height * s)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", portrait, "TOPLEFT", -34 * s, 12 * s)
            return true
        end
    end
    return false
end

------------------------------------------------------------------------------
-- Drag to reorder. The grab bar on a card's left edge picks it up: the card
-- lifts (shadow, nudge), follows the cursor, and the others slide out of the
-- way. Letting go settles it into its gap and saves the new order. Out of
-- combat only: the cards' secure name/portrait buttons can't move in combat.
------------------------------------------------------------------------------
local STEP = BOX_H + 3
local HideTargetSecure   -- set once the secure overlays exist
local drag               -- the drag in progress, or nil
local dragDriver = CreateFrame("Frame")

local function CardY(i) return (ui.cardTop or -128) - (i - 1) * STEP end

local function PlaceCard(bx, y, x)
    bx.frame:ClearAllPoints()
    bx.frame:SetPoint("TOPLEFT", F, "TOPLEFT", x or 6, y)
    bx.frame:SetPoint("RIGHT", F, "RIGHT", -6 + ((x or 6) - 6), 0)
end

-- Cursor height in the window's coordinates (0 at its top, negative down).
local function CursorY()
    local _, cy = GetCursorPosition()
    return cy / F:GetEffectiveScale() - F:GetTop()
end

local function FinishDrag()
    local d = drag
    drag, ui.drag = nil, nil
    dragDriver:Hide()
    d.box.frame:SetFrameStrata(F:GetFrameStrata())
    ui.dragShadow:Hide()
    pcall(ResetCursor)
    local to = d.slots[d.to]
    if to ~= d.slot and not d.cancel and not InCombatLockdown() then
        SC.MoveTargetTo(d.slot, to)
    else
        SC.Refresh()
    end
end

dragDriver:Hide()
dragDriver:SetScript("OnUpdate", function(_, dt)
    local d = drag
    if not d then dragDriver:Hide(); return end
    -- Combat or a changed list mid-drag: put it back where it was.
    if not d.dropping then
        local changed = InCombatLockdown()
        for _, s in ipairs(d.slots) do if not SC.Active(s) then changed = true end end
        if not F:IsShown() then changed = true end
        if changed then d.dropping, d.cancel, d.to = true, true, d.from end
    end
    local k = math.min(1, dt * 16)
    d.lift = d.lift + ((d.dropping and 0 or 1) - d.lift) * math.min(1, dt * 14)
    if not d.dropping then
        -- Anchored to the cursor at the point it was grabbed, a little past the
        -- ends allowed so it doesn't feel walled in.
        local top = CursorY() - d.grab
        top = math.max(CardY(#d.slots) - 14, math.min(CardY(1) + 14, top))
        d.y = top
        d.to = math.max(1, math.min(#d.slots, math.floor((CardY(1) - top) / STEP + 1.5)))
    else
        d.y = d.y + (CardY(d.to) - d.y) * k
        if math.abs(CardY(d.to) - d.y) < 0.5 then d.y = CardY(d.to) end
    end
    local settled = d.y == CardY(d.to)
    -- Everyone else, in the order shown with the dragged card in its gap.
    local order = {}
    for _, s in ipairs(d.slots) do if s ~= d.slot then order[#order + 1] = s end end
    table.insert(order, d.to, d.slot)
    for i, s in ipairs(order) do
        if s ~= d.slot then
            local want, cur = CardY(i), d.ys[s]
            cur = cur + (want - cur) * k
            if math.abs(want - cur) < 0.5 then cur = want else settled = false end
            d.ys[s] = cur
            PlaceCard(ui.boxes[s], cur)
        end
    end
    -- Lifted: nudged up-left with a soft shadow below-right.
    PlaceCard(d.box, d.y + d.lift * 2, 6 - d.lift * 2)
    local sh = ui.dragShadow
    sh:ClearAllPoints()
    sh:SetPoint("TOPLEFT", d.box.frame, "TOPLEFT", 2 + d.lift * 3, -(2 + d.lift * 4))
    sh:SetPoint("BOTTOMRIGHT", d.box.frame, "BOTTOMRIGHT", 2 + d.lift * 3, -(2 + d.lift * 4))
    sh:SetAlpha(0.6 * d.lift)
    if d.dropping and settled and d.lift < 0.05 then FinishDrag() end
end)

local function StartDrag(slot)
    if drag or InCombatLockdown() or not F:GetTop() then return end
    local slots, from = {}, nil
    for s = 1, SC.MAX_TARGETS do
        if SC.Active(s) then
            slots[#slots + 1] = s
            if s == slot then from = #slots end
        end
    end
    if #slots < 2 or not from then return end
    local bx = ui.boxes[slot]
    drag = { slot = slot, box = bx, slots = slots, from = from, to = from, y = CardY(from), lift = 0, ys = {} }
    drag.grab = CursorY() - CardY(from)
    for i, s in ipairs(slots) do drag.ys[s] = CardY(i) end
    ui.drag = drag
    GameTooltip:Hide()
    if HideTargetSecure then HideTargetSecure() end
    bx.frame:SetFrameStrata("HIGH")
    ui.dragShadow:SetFrameStrata("HIGH")
    ui.dragShadow:SetFrameLevel(math.max(1, bx.frame:GetFrameLevel() - 1))
    ui.dragShadow:Show()
    pcall(SetCursor, "UI_MOVE_CURSOR")
    dragDriver:Show()
end

local function DropDrag()
    if drag then drag.dropping = true end
end
SC._drag = { start = StartDrag, drop = DropDrag, driver = dragDriver, state = function() return drag end }

-- The grab bar: a column of dots at the card's left edge.
local function GripBar(T, slot)
    local g = CreateFrame("Button", nil, T)
    g:SetPoint("TOPLEFT", T, "TOPLEFT", 5, -3)
    g:SetPoint("BOTTOMLEFT", T, "BOTTOMLEFT", 5, 3)
    g:SetWidth(20)
    g.hl = g:CreateTexture(nil, "BACKGROUND")
    g.hl:SetAllPoints()
    g.hl:SetColorTexture(1, 1, 1, 0.06)
    g.hl:Hide()
    g.dots = {}
    for r = 0, 2 do
        for c = 0, 1 do
            local t = g:CreateTexture(nil, "ARTWORK")
            t:SetSize(3, 3)
            t:SetPoint("CENTER", g, "CENTER", (c - 0.5) * 6, (1 - r) * 6)
            t:SetColorTexture(1, 1, 1, 1)
            g.dots[#g.dots + 1] = t
        end
    end
    local function Lit(on)
        for _, t in ipairs(g.dots) do t:SetAlpha(on and 0.9 or 0.35) end
        g.hl:SetShown(on)
    end
    Lit(false)
    g:RegisterForClicks()   -- presses go to OnMouseDown/Up, not OnClick
    g:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then StartDrag(slot) end
    end)
    g:SetScript("OnMouseUp", function() DropDrag() end)
    Tip(g, "Drag to reorder", "Higher in the list = higher priority. With several targets in view, the key goes for the highest one.")
    g:HookScript("OnEnter", function()
        Lit(true)
        if InCombatLockdown() then
            GameTooltip:AddLine("Not in combat.", 1, 0.4, 0.4)
            GameTooltip:Show()
        else
            pcall(SetCursor, "UI_MOVE_CURSOR")
        end
    end)
    g:HookScript("OnLeave", function()
        if not drag then Lit(false); pcall(ResetCursor) end
    end)
    g.Lit = Lit
    return g
end

-- quest = the Auto Quest box: same look, but the key picks the mob.
local function BuildTargetBox(slot, quest)
    local bx = { quest = quest }
    local T = CreateFrame("Frame", nil, F, "BackdropTemplate")
    T:SetHeight(BOX_H)
    Backdrop(T)
    bx.frame = T

    if not quest then
        bx.onGlow = T:CreateTexture(nil, "BACKGROUND", nil, 3)
        bx.onGlow:SetPoint("TOPLEFT", 1, -1)
        bx.onGlow:SetPoint("BOTTOMRIGHT", -1, 1)
        bx.onGlow:SetColorTexture(0.25, 0.85, 0.4, 0.07)
        bx.onGlow:Hide()
        bx.keyTag = CreateFrame("Frame", nil, T)
        bx.keyTag:SetSize(30, 13)
        bx.keyTag.bg = bx.keyTag:CreateTexture(nil, "BACKGROUND")
        bx.keyTag.bg:SetAllPoints()
        bx.keyTag.bg:SetColorTexture(0.16, 0.62, 0.3, 1)
        bx.keyTag.text = bx.keyTag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bx.keyTag.text:SetPoint("CENTER", 0, 0)
        bx.keyTag.text:SetText("KEY")
        bx.keyTag:SetFrameLevel(T:GetFrameLevel() + 8)
        bx.keyTag:Hide()
        Tip(bx.keyTag, "Your key is on this mob", "The next press works on it. Spamming won't swap you off it.")
    end
    do
        bx.accent = T:CreateTexture(nil, "BORDER", nil, 6)
        bx.accent:SetPoint("TOPLEFT", 1, -1)
        bx.accent:SetPoint("BOTTOMLEFT", 1, 1)
        bx.accent:SetWidth(3)
        bx.accent:SetColorTexture(MODE_COLOR.quest[1], MODE_COLOR.quest[2], MODE_COLOR.quest[3], 1)
    end

    bx.portrait = CreateFrame("Frame", nil, T)
    bx.portrait:SetSize(44, 44)
    bx.portrait:SetPoint("LEFT", 30, 0)
    bx.portrait:EnableMouse(true)
    bx.portrait:SetScript("OnEnter", function(self) SC.ShowMobTip(self, bx.tipName) end)
    bx.portrait:SetScript("OnLeave", GameTooltip_Hide)
    -- KEY badge sits on the portrait's bottom edge. After the name it landed
    -- on the Questie map button whenever a long name was truncated.
    if bx.keyTag then bx.keyTag:SetPoint("CENTER", bx.portrait, "BOTTOM", 0, 1) end

    -- Right column: Clear, with Keep under it.
    bx.clear = Btn(T, "Clear", 58, 0, 0, function()
        if quest then SC.SetAnyQuest(false); return end
        local m = SC.Active(slot)
        if m and m.rareAuto and SC.rareDismissed then SC.rareDismissed[m.name] = true end
        SC.SetActive(nil, slot)
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
    bx.talk.accent = MODE_COLOR.talk
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
    bx.avg:SetWidth(92)
    bx.avg:SetWordWrap(false)
    eta:EnableMouse(true)
    if quest then
        Tip(eta, "Quest progress", "Kills (or items) done out of how many the quest needs. With several quest mobs, how many kinds are still needed.")
    else
    Tip(eta, "Respawn ETA", "Avg: how long this mob usually takes to come back after it dies (from the log). ETA counts down to that from its last death. At zero you get a soft ding, whether or not it has shown.")
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
        -- Rares get an ornate silver frame over the box.
        bx.silver = CreateFrame("Frame", nil, T, "BackdropTemplate")
        bx.silver:SetPoint("TOPLEFT", -5, 5)
        bx.silver:SetPoint("BOTTOMRIGHT", 5, -5)
        bx.silver:SetFrameLevel(T:GetFrameLevel() + 6)
        bx.silver:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 20 })
        bx.silver:SetBackdropBorderColor(0.86, 0.9, 1, 1)
        bx.silverGlow = T:CreateTexture(nil, "BACKGROUND", nil, 1)
        bx.silverGlow:SetPoint("TOPLEFT", 3, -3)
        bx.silverGlow:SetPoint("BOTTOMRIGHT", -3, 3)
        bx.silverGlow:SetColorTexture(0.75, 0.8, 0.95, 0.08)
        -- The game's winged silver rare dragon around the portrait, mirrored so
        -- the wings spread left (out of the box) instead of over the name.
        bx.dragon = bx.silver:CreateTexture(nil, "OVERLAY")
        bx.dragonOK = PlaceRareDragon(bx.dragon, bx.portrait)
        bx.silver:Hide()
        bx.silverGlow:Hide()
    end

    if not quest then
        -- Questie: pin this mob's spawns on the map and minimap.
        bx.map = CreateFrame("Button", nil, T)
        bx.map:SetSize(20, 20)
        bx.map:SetPoint("TOPRIGHT", nameArea, "TOPRIGHT", 0, -6)
        bx.map.icon = bx.map:CreateTexture(nil, "ARTWORK")
        bx.map.icon:SetAllPoints()
        bx.map.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        bx.map:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        bx.map:SetScript("OnClick", Safe(function()
            local m = SC.Active(slot)
            if m then SC.Print(SC.QuestieToggle(m.name)) end
        end))
        bx.map:SetScript("OnEnter", function(self)
            local m = SC.Active(slot)
            if not m then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if SC.QuestieShown(m.name) then
                GameTooltip:SetText("Remove from map")
                GameTooltip:AddLine("Takes Questie's pins for " .. m.name .. " off your map and minimap.", 1, 1, 1, true)
            else
                GameTooltip:SetText("Show on map (Questie)")
                GameTooltip:AddLine(m.partial
                    and ("Pins every NPC with \"" .. m.name .. "\" in its name on your map and minimap, like Questie's Advanced Search > Show on Map.")
                    or ("Pins every spawn of " .. m.name .. " on your map and minimap, like Questie's Advanced Search > Show on Map."), 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        bx.map:SetScript("OnLeave", GameTooltip_Hide)
        bx.map:Hide()
    end

    if not quest then
        -- On a mob a search found: keep it and drop the search.
        bx.lock = Btn(T, "Lock in", 64, 0, 0, function() local m = SC.Active(slot); if m then SC.LockIn(m.name) end end)
        bx.lock:ClearAllPoints()
        bx.lock:SetPoint("BOTTOMRIGHT", nameArea, "BOTTOMRIGHT", 0, 3)
        bx.lock:SetHeight(20)
        Tip(bx.lock, "Lock in", "This is the one. Keeps this mob and removes the search that found it, along with anything else that search added.")
        bx.lock:Hide()
        bx.ignore = Btn(T, "Ignore", 58, 0, 0, function()
            local m = SC.Active(slot)
            if m then SC.IgnoreRare(m.name) end
        end)
        bx.ignore:SetHeight(20)
        Tip(bx.ignore, "Ignore this rare", "Takes it off your key and adds it to the ignored rares, so it never pops up or alerts again. Review the list in the gear settings.")
        bx.ignore:Hide()
    end

    if not quest then
        bx.grip = GripBar(T, slot)
    end

    if quest then
        bx.talk:Hide()
        bx.keep:Hide()
        bx.show = Btn(T, "Show targets", 92, 0, 0, function() SC.ToggleAutoTargets() end)
        bx.show:ClearAllPoints()
        bx.show:SetPoint("TOPRIGHT", bx.clear, "BOTTOMRIGHT", 0, -4)
        bx.show:SetHeight(20)
        Tip(bx.show, "Show targets", "Lists the quest mobs Auto Quest is looking for.")
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
    ui.dragShadow = CreateFrame("Frame", nil, F)
    local t = ui.dragShadow:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(0, 0, 0, 1)
    ui.dragShadow:Hide()
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

HideTargetSecure = function()
    if InCombatLockdown() then return end
    for _, b in pairs(nameSecure) do b:Hide() end
    for _, b in pairs(portSecure) do b:Hide() end
end

local function PlaceNameSecure()
    if InCombatLockdown() or ui.drag then return end
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
            -- The text as shown: a long name is cut short, and covering its full
            -- width would put this over the map button beside it.
            local shown = fs:GetWidth()
            local w = math.max(fs:GetStringWidth() or 0, 40)
            if type(shown) == "number" and shown > 0 then w = math.min(w, shown) end
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
    local P = CreateFrame("Frame", "SpawnCampLog", F)
    P:SetSize(LOG_W, LOG_H)
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
    Check(P, "Pop up rares", 4, -120,
        function() return SC.char.rareAlert end, function(v) SC.char.rareAlert = v end,
        "When a rare's nameplate shows, it's added as a target at the top (silver frame) with a loud alert. Clear its box and it won't pop up again until you log in again. While SilverDragon is loaded the box still pops up but the alert is left to SilverDragon.")
    Tip(Btn(P, "Test rare", 74, 344, -119, function() SC.TestRare() end),
        "Test rare", "Adds a pretend rare elite at the top of your targets, with the alert, so you can see how a rare looks. Clear or Ignore removes it. It's never saved.")
    Tip(Btn(P, "Ignored rares", 100, 240, -119, function() SC.ToggleIgnoredRares() end),
        "Ignored rares", "The rares you've ignored. Remove one to get its pop-up back, or type a name to ignore it ahead of time.")
    Text(P, "Early ding", 8, -148)
    ui.lead = Edit(P, 36, 66, -144, function(t) SC.char.lead = tonumber(t) or 0 end, true)
    Text(P, "seconds before the earliest respawn (0 = off)", 112, -148)
    Text(P, "Look:", 8, -178)
    local look = UI.Dropdown(P, 210, function()
        local out = {}
        for _, o in ipairs(SC.LookOptions()) do out[#out + 1] = { value = o.value, label = o.text } end
        return out
    end, function() return SC.db.theme or "auto" end, function(v) SC.SetLook(v) end)
    look:SetPoint("TOPLEFT", 50, -174)
    Tip(look, "Look", "Matches EllesmereUI by default. Pick another to change every SpawnCamp window straight away.")
    Check(P, "Show minimap button", 274, -172,
        function() return not (SC.char.minimap and SC.char.minimap.hide) end,
        function(v) UI.SetLauncherShown(SC.char.minimap, v) end,
        "The SpawnCamp button on the minimap. /spawncamp and the AddOns menu still open the window.")
    Check(P, "Dungeon mobs on the key", 4, -200,
        function() return SC.char.dungeonMobs end, function(v) SC.SetDungeonMobs(v) end,
        "In a dungeon, the key also goes for that dungeon's mobs, from Questie's database, then any enemy left (pets, totems, wards). Needs Questie. /spc dungeon lists them.")
    Text(P, "Right-click Attack or Talk for their options.", 8, -230, "GameFontDisableSmall")
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

-- Auto Quest's targets: the mobs the key is looking for, in its order.
local AQ_ROWS = 12

local function RefreshAutoTargets()
    if not (AQ and AQ:IsShown()) then return end
    if not SC.char.anyQuest then AQ:Hide(); return end
    local list = SC.QuestWanted()
    local cap = SC.questCap or #list
    AQ.offset = math.max(0, math.min(AQ.offset or 0, #list - AQ_ROWS))
    for i = 1, AQ_ROWS do
        local r = AQ.rows[i]
        local idx = i + AQ.offset
        local name = list[idx]
        if name then
            local info = SC.QuestInfo(name)
            local near = SC.nearby and SC.nearby[name]
            r.name:SetText((idx > cap and "|cff808080" or "|cffffffff") .. name .. "|r")
            local bits = {}
            if info and info.have and info.need then bits[#bits + 1] = "|cffffd100" .. info.have .. "/" .. info.need .. "|r" end
            if info and type(info.quest) == "string" then bits[#bits + 1] = "|cffc0c0c0" .. info.quest .. "|r" end
            if near and near.t and GetTime() - near.t < 30 then bits[#bits + 1] = "|cff40ff40nearby|r" end
            if idx > cap then bits[#bits + 1] = "|cff808080not on the key (macro full)|r" end
            r.info:SetText(table.concat(bits, "  "))
            r:Show()
        else
            r:Hide()
        end
    end
    AQ.empty:SetShown(#list == 0)
    AQ.count:SetText(#list > AQ_ROWS and (#list .. " mobs, scroll for more") or "")
end

local function BuildAutoTargets()
    AQ = Popup("SpawnCampAutoTargets", 380, 60 + AQ_ROWS * 18, "Auto Quest targets")
    AQ.count = Text(AQ, "", 8, -30 - AQ_ROWS * 18 - 4)
    AQ.empty = Text(AQ, "No quest mobs needed right now.\n\nKill objectives in your quest log show up\nhere, and item-drop mobs once you've seen\nthem nearby.", 8, -32)
    AQ.rows = {}
    for i = 1, AQ_ROWS do
        local r = CreateFrame("Frame", nil, AQ)
        r:SetSize(364, 17)
        r:SetPoint("TOPLEFT", 8, -30 - (i - 1) * 18)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 2, 0)
        r.name:SetWidth(150)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.info:SetPoint("RIGHT", 0, 0)
        r.info:SetJustifyH("LEFT")
        r.info:SetWordWrap(false)
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            AQ.offset = (AQ.offset or 0) - d
            RefreshAutoTargets()
        end)
        AQ.rows[i] = r
    end
    AQ:SetScript("OnShow", function()
        SC.ScanNearby()
        RefreshAutoTargets()
    end)
end

function SC.ToggleAutoTargets()
    if not F then return end
    ShowBeside(AQ)
    RefreshAutoTargets()
end

------------------------------------------------------------------------------
-- Ignored rares
------------------------------------------------------------------------------

local IG_ROWS = 12

local function RefreshIgnored()
    if not (IG and IG:IsShown()) then return end
    local list = SC.IgnoredRares()
    IG.offset = math.max(0, math.min(IG.offset or 0, #list - IG_ROWS))
    for i, r in ipairs(IG.rows) do
        local n = list[i + IG.offset]
        if n then
            r.mobName = n
            r.name:SetText(n)
            r:Show()
        else
            r.mobName = nil
            r:Hide()
        end
    end
    IG.empty:SetShown(#list == 0)
    IG.count:SetText(#list > IG_ROWS and (#list .. " rares, scroll for more") or "")
end

local function BuildIgnored()
    IG = Popup("SpawnCampIgnoredRares", 300, 96 + IG_ROWS * 18, "Ignored rares")
    IG.add = Edit(IG, 196, 4, -30, function() end)
    local function add()
        local n = strtrim(IG.add:GetText() or "")
        if n ~= "" then SC.IgnoreRare(n) end
        IG.add:SetText("")
        IG.add:ClearFocus()
        RefreshIgnored()
    end
    IG.add:SetScript("OnEnterPressed", add)
    Tip(Btn(IG, "Add", 50, 212, -29, add), "Add", "Type a rare's exact name to stop it popping up or alerting.")
    local top = -58
    IG.empty = Text(IG, "No ignored rares.\n\nClick Ignore on a rare's box, or type\na name above.", 8, top - 2)
    IG.count = Text(IG, "", 8, top - IG_ROWS * 18 - 6)
    IG.rows = {}
    for i = 1, IG_ROWS do
        local r = CreateFrame("Frame", nil, IG)
        r:SetSize(284, 17)
        r:SetPoint("TOPLEFT", 8, top - (i - 1) * 18)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 2, 0)
        r.name:SetPoint("RIGHT", -60, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.remove = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.remove:SetSize(56, 17)
        r.remove:SetPoint("RIGHT", 0, 0)
        r.remove:SetText("Remove")
        r.remove:SetScript("OnClick", Safe(function()
            if r.mobName then SC.UnignoreRare(r.mobName) end
            RefreshIgnored()
        end))
        Tip(r.remove, "Remove", "Takes it off the list, so it pops up and alerts again.")
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, d)
            IG.offset = (IG.offset or 0) - d
            RefreshIgnored()
        end)
        IG.rows[i] = r
    end
    IG:SetScript("OnShow", RefreshIgnored)
end

function SC.ToggleIgnoredRares()
    if not F then return end
    ShowBeside(IG)
    RefreshIgnored()
end

------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------

local function Build()
    F = CreateFrame("Frame", "SpawnCampFrame", UIParent)
    F:SetSize(W, 200)
    F:SetPoint("TOP", UIParent, "TOP", 0, -160)
    F:SetFrameStrata("MEDIUM")
    F:SetClampedToScreen(true)
    F:EnableMouse(true)
    F:SetMovable(true)
    F:RegisterForDrag("LeftButton")
    F:SetScript("OnDragStart", function(self) if not SC.char.locked then self:StartMoving() end end)
    F:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    local pos = SC.char.framePos
    if pos then
        F:ClearAllPoints()
        F:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    ui.checks, ui.keys = {}, {}
    Shell(F)
    BuildTop()
    F.scShell.nsTitle = F.title
    BuildTarget()
    BuildPicker()
    BuildNameSecure()
    BuildRecent()
    BuildAttackPopup()
    BuildChooser()
    BuildTalkPopup()
    BuildNearby()
    BuildQuests()
    BuildAutoTargets()
    BuildIgnored()
    BuildLog()
    Shell(ui.log, ui.logTitle)
    -- Settings open beside the window.
    ui.settingsPopup = Popup("SpawnCampSettings", 440, PANEL_H.settings + 6, "")
    local P = CreateFrame("Frame", nil, ui.settingsPopup)
    P:SetAllPoints()
    BuildSettings(P)
    for _, f in ipairs({ F, AP, TP, N, RP, Q, AQ, IG, CH, ui.settingsPopup }) do RegisterButtons(f) end
    ReskinAll()
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
    local m, quests = SC.Active(), #SC.QuestWanted()
    for _, b in ipairs(ui.keys) do
        if not (capturing and capturing.button == b) then
            b:SetText(SC.char.key ~= "" and SC.KeyLabel(SC.char.key) or "|cff999999Set key|r")
        end
    end
    ui.clearKey:SetShown(SC.char.key ~= "")
    local state, detail, r, g, b = nil, nil, 0.6, 0.6, 0.6
    if SC.char.key == "" then
        state, detail = "No key yet", "Click the box on the left, then press a key, roll the wheel or press a mouse button."
    elseif not m and quests == 0 then
        state = "Idle"
        detail = SC.char.anyQuest and "Auto Quest is on, but none of your quests needs a mob right now." or "Add a target below and your key goes for it."
    else
        local st, text = SC.KeyState()
        local what = m and (m.mode == "attack" and "Attack" or "Talk") or "Attack"
        local words = { on = "On target", lock = "Locked on its nameplate", off = "Searching" }
        state = words[st] or "Ready"
        local rest = (text:gsub("^[^:]+:%s*", ""))
        local tn = st == "on" and SC.UnitNameSafe("target")
        detail = what .. "  |cff808080-|r  " .. (tn and ("|cffffffff" .. tn .. "|r  |cff808080-|r  ") or "") .. rest
        if st == "on" or st == "lock" then r, g, b = 0.25, 0.9, 0.4 else r, g, b = 1, 0.82, 0 end
    end
    ui.keyState:SetText(state)
    ui.keyState:SetTextColor(r, g, b)
    ui.keyDot:SetVertexColor(r, g, b)
    ui.keyDetail:SetText(detail)
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
    local rare = m and SC.IsRareClass and SC.IsRareClass(m.rare)
    bx.silver:SetShown(rare and true or false)
    bx.silverGlow:SetShown(rare and true or false)
    if rare then bx.frame:SetBackdropBorderColor(0.86, 0.9, 1, 1) else BoxBorder(bx.frame) end
    bx.ignore:SetShown(rare and true or false)
    local questie = m and SC.QuestieReady and SC.QuestieReady()
    bx.map:SetShown(questie and true or false)
    bx.name:SetPoint("RIGHT", questie and bx.map or bx.nameArea, questie and "LEFT" or "RIGHT", questie and -4 or 0, 0)
    if questie then
        local on = SC.QuestieShown(m.name)
        bx.map.icon:SetDesaturated(not on)
        bx.map.icon:SetAlpha(on and 1 or 0.6)
    end
    if not m then bx.grip:Hide(); bx.lock:Hide(); return end
    PlacePortrait(m.name, bx.portrait)
    bx.tipName = m.name
    local search = SC.SearchOf(m.name)
    bx.lock:SetShown(search ~= nil)
    bx.ignore:ClearAllPoints()
    if search then
        bx.ignore:SetPoint("RIGHT", bx.lock, "LEFT", -4, 0)
    else
        bx.ignore:SetPoint("BOTTOMRIGHT", bx.nameArea, "BOTTOMRIGHT", 0, 3)
    end
    local leftmost = (rare and bx.ignore) or (search and bx.lock)
    if leftmost then
        bx.status:SetPoint("RIGHT", leftmost, "LEFT", -4, 0)
    else
        bx.status:SetPoint("RIGHT", bx.nameArea, "RIGHT", 0, 0)
    end
    if m.partial then
        bx.name:SetText(m.name .. "  |cff999999(search)|r")
        local skipped = 0
        for _ in pairs(m.rejected or {}) do skipped = skipped + 1 end
        bx.status:SetText("|cffc0c0c0Adds any mob with this in its name|r" .. (skipped > 0 and ("  |cff808080(" .. skipped .. " skipped)|r") or ""))
    else
        local tag = rare and ("  |A:nameplates-icon-elite-silver:16:16|a|cffd8e0ff" .. (m.rare == "rareelite" and "Rare Elite" or "Rare") .. "|r") or ""
        bx.name:SetText((rare and "|cffeef2ff" or "") .. m.name .. (rare and "|r" or "") .. tag
            .. (search and ("  |cff999999(found by \"" .. search .. "\")|r") or ""))
        local state, text = SC.Status(m.name)
        bx.status:SetText(StatusColor(state) .. text .. "|r")
    end
    local big, small, color = SC.ETA(m.name)
    bx.eta:SetText(color .. big .. "|r")
    bx.avg:SetText(small)
    SetPressed(bx.attack, m.mode == "attack")
    SetPressed(bx.talk, m.mode == "interact")
    if bx.accent then
        local c = (m.mode == "interact") and MODE_COLOR.talk or MODE_COLOR.attack
        bx.accent:SetColorTexture(c[1], c[2], c[3], 1)
    end
    if bx.keyTag then
        local tn = SC.onMob and SC.UnitNameSafe("target")
        local onThis = tn and tn:lower() == m.name:lower() or false
        bx.onGlow:SetShown(onThis)
        bx.keyTag:SetShown(onThis)
        if onThis then
            if not rare then bx.frame:SetBackdropBorderColor(0.25, 0.85, 0.4, 1) end
        end
    end
    bx.grip:SetShown(#SC.Targets() > 1)
end

-- Lays out the add bar and a card per target; returns the y below.
local function RefreshTarget()
    local n = #SC.Actives()
    ui.picker:ClearAllPoints()
    ui.picker:SetPoint("TOPLEFT", F, "TOPLEFT", 6, -74)
    ui.picker:SetPoint("RIGHT", F, "RIGHT", -6, 0)
    ui.picker:Show()
    local y = -112
    ui.listLabel:ClearAllPoints()
    ui.listLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 10, y)
    ui.listLabel:SetText("TARGETS  |cff808080" .. n .. " / " .. SC.MAX_TARGETS .. "   (top = highest priority)|r")
    y = y - 16
    ui.cardTop = y
    for slot = 1, SC.MAX_TARGETS do
        local bx, m = ui.boxes[slot], SC.Active(slot)
        if m then
            -- Mid-drag the drag places the cards.
            if not ui.drag then PlaceCard(bx, y) end
            bx.frame:Show()
            RefreshBox(bx, m, slot)
            y = y - BOX_H - 3
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
        y = y - BOX_H - 3
    else
        qb.frame:Hide()
    end
    local empty = n == 0 and not SC.char.anyQuest
    ui.emptyHint:SetShown(empty)
    if empty then
        ui.emptyHint:ClearAllPoints()
        ui.emptyHint:SetPoint("TOPLEFT", F, "TOPLEFT", 10, y - 4)
        y = y - 40
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
    local macroBody = SC.AttackMacroBody()
    ui.spellSlot.icon:SetTexture(SpellIcon(A.spell) or "Interface\\Icons\\INV_Misc_QuestionMark")
    ui.spellSlot.icon:SetDesaturated(A.spell == "" or macroBody ~= nil)
    ui.spellSlot:SetAlpha(macroBody and 0.4 or 1)
    if macroBody then
        ui.spellSlot.text:SetText("|cff808080" .. (A.spell ~= "" and A.spell or "None") .. "  (not used)|r")
    else
        ui.spellSlot.text:SetText(A.spell ~= "" and A.spell or "|cff808080None|r")
    end
    local mi = A.macroName ~= "" and GetMacroIndexByName and GetMacroIndexByName(A.macroName) or 0
    local micon = mi and mi > 0 and select(2, GetMacroInfo(mi))
    ui.macroSlot.icon:SetTexture(micon or "Interface\\Icons\\INV_Misc_QuestionMark")
    ui.macroSlot.icon:SetDesaturated(not micon)
    ui.macroSlot.text:SetText(A.macroName ~= "" and A.macroName or "|cff808080None|r")
    if A.macroName == "" then
        ui.macroNote:SetText("")
    elseif not mi or mi == 0 then
        ui.macroNote:SetText("|cffff6060Not in your macros any more. The spell is used.|r")
    elseif not macroBody then
        ui.macroNote:SetText("|cffff6060That macro is empty. The spell is used.|r")
    else
        ui.macroNote:SetText("|cff40ff40In use. The spell above is ignored while a macro is picked.|r")
    end
    local sname, cast = SpellInfo(A.spell)
    if macroBody then
        ui.spellNote:SetText("|cffff9933Not used: the macro below always wins. Set Macro to None to use the spell.|r")
    elseif A.spell == "" then
        ui.spellNote:SetText("|cffccccccNo spell: the key starts auto attack.|r")
    elseif not sname then
        ui.spellNote:SetText("|cffff6060Not a spell you know.|r")
    elseif cast and cast > 0 then
        ui.spellNote:SetText(string.format("|cffff6060Not instant (%.1f sec cast).|r", cast / 1000))
    else
        ui.spellNote:SetText("|cff40ff40Instant cast.|r")
    end
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
    ui.logIcon:SetShown(m ~= nil)
    ui.logIcon:SetAlpha(SC.char.logOpen and 1 or 0.55)
    if m and SC.char.logOpen then
        ui.log:ClearAllPoints()
        if SC.char.logRight then
            ui.log:SetPoint("TOPLEFT", F, "TOPRIGHT", MARGIN * 2 + 2, 0)
        else
            ui.log:SetPoint("TOPRIGHT", F, "TOPLEFT", -(MARGIN * 2 + 2), 0)
        end
        ui.logTitle:SetText("Log: " .. m.name .. (SC.Active(2) and "  |cff999999(click for the next target)|r" or ""))
        ui.log:Show()
        RefreshMobPanel()
    else
        ui.log:Hide()
    end
    SetEditText(ui.lead, tostring(SC.char.lead or 0))
    RefreshRecent()
    RefreshAutoTargets()
    RefreshIgnored()
    for _, cb in ipairs(ui.checks) do cb:SetChecked(cb.get() and true or false) end
    UI.RefreshAll()
    RefreshPopups()

    -- /spawncamp settings: open the side panel.
    if SC.char.panel == "settings" then
        SC.char.panel = nil
        if not ui.settingsPopup:IsShown() then ShowBeside(ui.settingsPopup) end
        return
    end
    SC.char.panel = nil
    F:SetHeight(-y + 6)
    pcall(PlaceNameSecure)
end

-- Focuses the name box (when the game hides a target's name).
function SC.FocusAddName()
    SC.char.shown = true
    SC.Refresh()
    if ui.addName then ui.addName:SetFocus() end
end

function SC.OpenSettings()
    SC.char.shown = true
    SC.char.panel = "settings"
    SC.Refresh()
end

-- Options > AddOns: a page that opens SpawnCamp's settings.
UI.RegisterSettingsPage(SC.ICON, "/spawncamp", function() SC.OpenSettings() end)

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
