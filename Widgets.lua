---------------------------------------------------------
--  House kit - Widgets (from CastCount)
--  Author: Dranged
---------------------------------------------------------
-- Small UI pieces built by hand, so nothing depends on old Classic templates
-- (dropdowns, sliders, scroll lists) that Forever's client may not have.

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI
local WHITE = "Interface\\Buttons\\WHITE8X8"
UI.WHITE = WHITE

---------------------------------------------------------
--  SECTION: Refresh registry
---------------------------------------------------------
-- Anything with a :Refresh() that shows a setting; RefreshAll re-reads them all.
local tracked = {}
function UI.Track(obj) tracked[#tracked + 1] = obj; return obj end
function UI.RefreshAll()
    for _, obj in ipairs(tracked) do
        if obj.Refresh then obj:Refresh() end
    end
end

---------------------------------------------------------
--  SECTION: Basics
---------------------------------------------------------
function UI.Backdrop(f, r, g, b, a, br, bg, bb, ba)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(r or 0.06, g or 0.06, b or 0.07, a or 0.95)
    f:SetBackdropBorderColor(br or 0.25, bg or 0.25, bb or 0.28, ba or 1)
end

function UI.Text(parent, text, font, layer)
    local fs = parent:CreateFontString(nil, layer or "ARTWORK", font or "GameFontHighlight")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

function UI.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, h or 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if NS.ThemeRegisterButton then NS.ThemeRegisterButton(b) end
    return b
end

function UI.Check(parent, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    if cb.Text then cb.Text:SetText("") end
    if cb.text then cb.text:SetText("") end
    cb.label = UI.Text(cb, label)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        UI.RefreshAll()
    end)
    function cb:Refresh() self:SetChecked(get() and true or false) end
    function cb:SetActive(on)
        self:SetEnabled(on)
        local v = on and 1 or 0.5
        self.label:SetTextColor(v, v, v)
    end
    return UI.Track(cb)
end

---------------------------------------------------------
--  SECTION: Slider
---------------------------------------------------------
-- With arrows, < and > buttons sit at the ends (a click moves 1 step, Shift 5, Ctrl 10)
-- and the value is a box centred under the bar that you can type into.
function UI.Slider(parent, label, minV, maxV, step, width, get, set, arrows)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, arrows and 54 or 34)
    local title = UI.Text(holder, label, "GameFontNormalSmall")
    title:SetPoint("TOPLEFT")
    local value = UI.Text(holder, "", "GameFontHighlightSmall")
    value:SetPoint("TOPRIGHT")

    local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    local inset = arrows and 22 or 0
    s:SetPoint("TOPLEFT", inset, -16)
    s:SetPoint("TOPRIGHT", -inset, -16)
    s:SetHeight(12)
    UI.Backdrop(s, 0.1, 0.1, 0.11, 1)
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetVertexColor(NS.AccentColor())
    thumb:SetSize(8, 14)
    holder.updating = true
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    holder.updating = false

    -- Whole steps show as whole numbers; fractional steps with one decimal.
    local function Fmt(v) return (step < 1) and ("%.1f"):format(v) or v end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        value:SetText(Fmt(v))
        -- The typed-value box follows the bar (unless you're typing in it).
        if holder.box and not holder.box:HasFocus() then holder.box:SetText(v) end
        if not holder.updating then set(v) end
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)

    if arrows then
        local function Nudge(dir)
            local n = (IsControlKeyDown() and 10) or (IsShiftKeyDown() and 5) or 1
            set(math.max(minV, math.min(maxV, get() + dir * n * step)))
            holder:Refresh()
        end
        local function Tip(b)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("Click: 1   Shift-click: 5   Ctrl-click: 10", 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local left = UI.Button(holder, "<", 20, 18, function() Nudge(-1) end)
        left:SetPoint("TOPLEFT", 0, -13)
        Tip(left)
        local right = UI.Button(holder, ">", 20, 18, function() Nudge(1) end)
        right:SetPoint("TOPRIGHT", 0, -13)
        Tip(right)

        value:Hide()
        local box = UI.Edit(holder, 44, "signed", get, function(v)
            set(math.max(minV, math.min(maxV, v)))
            holder:Refresh()
        end)
        box:SetPoint("TOP", s, "BOTTOM", 0, -4)
        box:SetJustifyH("CENTER")
        holder.box = box
    end

    function holder:Refresh()
        self.updating = true
        local v = get()
        s:SetValue(v)
        value:SetText(Fmt(v))
        if self.box and not self.box:HasFocus() then self.box:SetText(v) end
        self.updating = false
    end
    return UI.Track(holder)
end

---------------------------------------------------------
--  SECTION: Scrolling list
---------------------------------------------------------
-- A virtual list: maxRows row buttons, scrolled over f.data. render(row, item, selected)
-- draws a row; onClick(list, item, mouseButton) and list.onDouble(list, item) handle clicks.
function UI.RenderRow(row, label, icon, font)
    if icon then
        row.icon:SetWidth(row:GetHeight() - 4)
        row.icon:SetTexture(icon)
        row.icon:Show()
    else
        row.icon:SetWidth(0.1)
        row.icon:Hide()
    end
    row.text:SetFontObject(GameFontHighlight)
    if font then row.text:SetFont(font, 12, "") end
    row.text:SetText(label)
end

function UI.List(parent, width, rowH, maxRows, render, onClick)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.Backdrop(f, 0.03, 0.03, 0.035, 0.95)
    f.rowH, f.maxRows, f.visible, f.data, f.offset = rowH, maxRows, maxRows, {}, 0
    f:SetSize(width, maxRows * rowH + 4)
    f.rows = {}
    for i = 1, maxRows do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(rowH)
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
        r:SetPoint("RIGHT", f, "RIGHT", -10, 0)
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        local ar, ag, ab = NS.AccentColor()
        r.sel:SetColorTexture(ar, ag, ab, 0.25)
        r.sel:Hide()
        r:SetHighlightTexture(WHITE)
        local hl = r:GetHighlightTexture()
        hl:SetVertexColor(1, 1, 1)
        hl:SetAlpha(0.08)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(rowH - 4, rowH - 4)
        r.icon:SetPoint("LEFT", 2, 0)
        r.text = UI.Text(r, "")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        r.text:SetPoint("RIGHT", -4, 0)
        r.text:SetWordWrap(false)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, mouse)
            if self.item and onClick then onClick(f, self.item, mouse) end
        end)
        r:SetScript("OnDoubleClick", function(self)
            if self.item and f.onDouble then f.onDouble(f, self.item) end
        end)
        f.rows[i] = r
    end

    local track = CreateFrame("Frame", nil, f)
    track:SetPoint("TOPRIGHT", -2, -2)
    track:SetPoint("BOTTOMRIGHT", -2, 2)
    track:SetWidth(6)
    local tbg = track:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    tbg:SetColorTexture(0.12, 0.12, 0.12, 1)
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.55, 0.55, 0.55, 1)
    thumb:SetWidth(6)

    local function MaxOffset() return math.max(0, #f.data - f.visible) end

    function f:Update()
        for i, r in ipairs(self.rows) do
            local item = (i <= self.visible) and self.data[self.offset + i] or nil
            r.item = item
            if item then
                render(r, item, self.selected == item)
                r.sel:SetShown(self.selected == item)
                r:Show()
            else
                r:Hide()
            end
        end
        local max = MaxOffset()
        track:SetShown(max > 0)
        if max > 0 then
            local th = track:GetHeight()
            local h = math.max(10, th * self.visible / #self.data)
            thumb:SetHeight(h)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(th - h) * self.offset / max)
        end
    end
    function f:ScrollTo(o)
        self.offset = math.max(0, math.min(MaxOffset(), math.floor(o + 0.5)))
        self:Update()
    end
    function f:SetData(data)
        self.data = data or {}
        local keep = false
        for _, item in ipairs(self.data) do
            if item == self.selected then keep = true break end
        end
        if not keep then self.selected = nil end
        self:ScrollTo(self.offset)
    end
    function f:SetVisibleRows(n)
        self.visible = math.max(1, math.min(n, self.maxRows))
        self:SetHeight(self.visible * self.rowH + 4)
        self:Update()
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self.offset - delta * 3) end)
    local function FromCursor()
        local _, y = GetCursorPosition()
        y = y / track:GetEffectiveScale()
        local top, h = track:GetTop(), track:GetHeight()
        if top and h and h > 0 then f:ScrollTo((top - y) / h * MaxOffset()) end
    end
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self) FromCursor(); self:SetScript("OnUpdate", FromCursor) end)
    track:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    return f
end

---------------------------------------------------------
--  SECTION: Scroll area
---------------------------------------------------------
-- Fills parent with a scrolling area; widgets go on the returned content frame,
-- and sf:SetContentHeight(h) says how tall it is.
function UI.ScrollArea(parent, contentWidth)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT")
    sf:SetPoint("BOTTOMRIGHT", -12, 0)
    if sf.SetClipsChildren then sf:SetClipsChildren(true) end
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(contentWidth or 630, 10)
    sf:SetScrollChild(content)

    local track = CreateFrame("Frame", nil, parent)
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(6)
    local tbg = track:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    tbg:SetColorTexture(0.12, 0.12, 0.12, 1)
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.55, 0.55, 0.55, 1)
    thumb:SetWidth(6)

    sf.contentH = 10
    local function MaxScroll() return math.max(0, sf.contentH - (sf:GetHeight() or 0)) end
    function sf:UpdateThumb()
        local max = MaxScroll()
        track:SetShown(max > 0)
        if max <= 0 then return end
        local th, vh = track:GetHeight(), self:GetHeight()
        local h = math.max(16, th * vh / self.contentH)
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(th - h) * (self:GetVerticalScroll() / max))
    end
    function sf:ScrollTo(v)
        self:SetVerticalScroll(math.max(0, math.min(MaxScroll(), v)))
        self:UpdateThumb()
    end
    function sf:ScrollToBottom() self:ScrollTo(MaxScroll()) end
    function sf:SetContentHeight(h)
        self.contentH = h
        content:SetHeight(h)
        self:ScrollTo(self:GetVerticalScroll() or 0)
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo((self:GetVerticalScroll() or 0) - delta * 40) end)
    sf:SetScript("OnSizeChanged", function(self) self:ScrollTo(self:GetVerticalScroll() or 0) end)
    local function FromCursor()
        local _, y = GetCursorPosition()
        y = y / track:GetEffectiveScale()
        local top, h = track:GetTop(), track:GetHeight()
        if top and h and h > 0 then sf:ScrollTo((top - y) / h * MaxScroll()) end
    end
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self) FromCursor(); self:SetScript("OnUpdate", FromCursor) end)
    track:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    track:Hide()
    return sf, content
end

---------------------------------------------------------
--  SECTION: Dropdown
---------------------------------------------------------
-- One shared pop-up list for every dropdown. Items: { value, label, font? }.
local menu, catcher

function UI.CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end

local function Menu()
    if menu then return menu end
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", UI.CloseMenu)
    catcher:Hide()
    menu = UI.List(UIParent, 200, 20, 14, function(row, item)
        UI.RenderRow(row, item.label, nil, item.font)
    end, function(_, item)
        local pick = menu.onPick
        UI.CloseMenu()
        if pick then pick(item.value) end
    end)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(50)
    menu:EnableMouse(true)
    menu:Hide()
    return menu
end

function UI.OpenMenu(anchor, items, current, onPick)
    local m = Menu()
    m.onPick = onPick
    m:SetWidth(math.max(140, anchor:GetWidth()))
    m.selected = nil
    local index = 1
    for i, item in ipairs(items) do
        if item.value == current then m.selected, index = item, i end
    end
    m:SetData(items)
    m:SetVisibleRows(#items)
    m:ScrollTo(index - math.floor(m.visible / 2))
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    catcher:Show()
    m:Show()
end

function UI.Dropdown(parent, width, items, get, set)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 22)
    UI.Backdrop(b, 0.1, 0.1, 0.11, 1)
    b.text = UI.Text(b, "")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -18, 0)
    b.text:SetWordWrap(false)
    local arrow = UI.Text(b, "v", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnClick", function(self)
        UI.OpenMenu(self, items(), get(), function(v)
            set(v)
            UI.RefreshAll()
        end)
    end)
    function b:Refresh()
        local cur = get()
        for _, item in ipairs(items()) do
            if item.value == cur then self.text:SetText(item.label) return end
        end
        self.text:SetText(tostring(cur))
    end
    function b:SetActive(on)
        self:SetEnabled(on)
        self:SetAlpha(on and 1 or 0.5)
    end
    return UI.Track(b)
end

---------------------------------------------------------
--  SECTION: Colour swatch
---------------------------------------------------------
-- Opens the game's colour picker on colour table c ({r,g,b,a}); onChange(c) runs
-- with the new colour as it changes (and the old one on cancel).
function UI.PickColor(c, onChange)
    local r, g, b, a = c.r, c.g, c.b, c.a or 1
    local function Current()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = a
        if ColorPickerFrame.GetColorAlpha then
            na = ColorPickerFrame:GetColorAlpha()
        elseif OpacitySliderFrame then
            na = 1 - OpacitySliderFrame:GetValue()
        end
        return { r = nr, g = ng, b = nb, a = na }
    end
    local function Changed() onChange(Current()) end
    local function Cancel() onChange({ r = r, g = g, b = b, a = a }) end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = true,
            swatchFunc = Changed, opacityFunc = Changed, cancelFunc = Cancel,
        })
    else
        ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = Changed, Changed, Cancel
        ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = true, 1 - a
        ColorPickerFrame.previousValues = { r, g, b, a }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

-- getColor returns the saved colour table; it's changed in place, then onChange runs.
function UI.Swatch(parent, getColor, onChange)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(22, 22)
    UI.Backdrop(b, 0, 0, 0, 1, 0.6, 0.6, 0.6, 1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 3, -3)
    b.tex:SetPoint("BOTTOMRIGHT", -3, 3)
    function b:Refresh()
        local c = getColor()
        self.tex:SetColorTexture(c.r, c.g, c.b, c.a or 1)
    end
    b:SetScript("OnClick", function(self)
        UI.PickColor(getColor(), function(nc)
            local c = getColor()
            c.r, c.g, c.b, c.a = nc.r, nc.g, nc.b, nc.a
            self:Refresh()
            if onChange then onChange() end
        end)
    end)
    function b:SetActive(on)
        self:SetEnabled(on)
        self:SetAlpha(on and 1 or 0.5)
    end
    return UI.Track(b)
end

---------------------------------------------------------
--  SECTION: Edit boxes
---------------------------------------------------------
-- Saved on Enter and when focus is lost (OnTextChanged's user-input flag isn't
-- reliable on Forever). numeric: true = whole numbers, "signed" = may be negative.
function UI.Edit(parent, width, numeric, get, set)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    if numeric == "signed" then
        e:SetMaxLetters(4)
    elseif numeric then
        e:SetNumeric(true)
        e:SetMaxLetters(3)
    else
        e:SetMaxLetters(60)
    end
    local function Save()
        local text = e:GetText()
        if numeric then
            local v = tonumber(text)
            if v then set(math.floor(v + 0.5)) end
        elseif text ~= "" or e.allowEmpty then
            set(text)
        end
        e:Refresh()
    end
    e:SetScript("OnEnterPressed", function(self) Save(); self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self)
        if self.cancelled then
            self.cancelled = nil
            self:Refresh()
        else
            Save()
        end
    end)
    -- Escape puts the old value back.
    e:SetScript("OnEscapePressed", function(self) self.cancelled = true; self:ClearFocus() end)
    -- Clicking in selects what's there, so typing replaces it (again a frame later,
    -- since the click itself places the cursor after focus arrives).
    e:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        C_Timer.After(0, function() if self:HasFocus() then self:HighlightText() end end)
    end)
    function e:Refresh()
        if not self:HasFocus() then self:SetText(tostring(get())) end
    end
    function e:SetActive(on)
        self:SetEnabled(on)
        self:SetAlpha(on and 1 or 0.5)
    end
    return UI.Track(e)
end
