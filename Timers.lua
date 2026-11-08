-- SpawnCamp timer list: one line per mob you're still hunting, with a bar
-- that fills toward the earliest expected respawn. Drag to move; click a line
-- to open that mob in the window.

local ADDON, SC = ...

local T
local lines = {}
local ROW_H = 18

local function Build()
    T = CreateFrame("Frame", "SpawnCampTimers", UIParent, "BackdropTemplate")
    T:SetSize(260, 24)
    T:SetPoint("TOP", UIParent, "TOP", 0, -160)
    T:SetMovable(true)
    T:SetClampedToScreen(true)
    T:EnableMouse(true)
    T:RegisterForDrag("LeftButton")
    T:SetScript("OnDragStart", T.StartMoving)
    T:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        SC.char.timersPos = { p, rp, x, y }
    end)
    T:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    T:SetBackdropColor(0, 0, 0, 0.55)
    T:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    local title = T:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 6, -5)
    title:SetText("SpawnCamp")
    local pos = SC.char.timersPos
    if pos then
        T:ClearAllPoints()
        T:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end

local function Line(i)
    local l = lines[i]
    if l then return l end
    l = CreateFrame("Button", nil, T)
    l:SetSize(248, ROW_H - 2)
    l:SetPoint("TOPLEFT", 6, -18 - (i - 1) * ROW_H)
    l.bar = CreateFrame("StatusBar", nil, l)
    l.bar:SetAllPoints()
    l.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    l.bar:SetMinMaxValues(0, 1)
    l.bg = l:CreateTexture(nil, "BACKGROUND")
    l.bg:SetAllPoints()
    l.bg:SetColorTexture(1, 1, 1, 0.06)
    l.text = l.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.text:SetPoint("LEFT", 4, 0)
    l.text:SetPoint("RIGHT", -4, 0)
    l.text:SetJustifyH("LEFT")
    l.text:SetWordWrap(false)
    l:RegisterForDrag("LeftButton")
    l:SetScript("OnDragStart", function() T:StartMoving() end)
    l:SetScript("OnDragStop", function() T:GetScript("OnDragStop")(T) end)
    l:SetScript("OnClick", function(self)
        SC.char.selected = self.name
        SC.ShowWindow()
    end)
    lines[i] = l
    return l
end

local BAR = {
    up = { 0.2, 0.8, 0.2 }, window = { 0.9, 0.7, 0.1 }, late = { 0.9, 0.4, 0.1 },
    waiting = { 0.3, 0.45, 0.8 }, dead = { 0.4, 0.4, 0.4 }, none = { 0.25, 0.25, 0.25 },
}

function SC.RefreshTimers()
    if not SC.char then return end
    local show = {}
    if SC.char.showTimers then
        for _, n in ipairs(SC.char.order) do
            local m = SC.char.mobs[n]
            if m and m.hunting then show[#show + 1] = n end
        end
    end
    if #show == 0 then
        if T then T:Hide() end
        return
    end
    if not T then Build() end
    for i, n in ipairs(show) do
        local l = Line(i)
        local state, text, frac = SC.Status(n)
        local c = BAR[state] or BAR.none
        l.bar:SetStatusBarColor(c[1], c[2], c[3], 0.7)
        l.bar:SetValue((state == "up" or state == "window" or state == "late") and 1 or (frac or 0))
        l.text:SetText(n .. ": " .. SC.StatusColor(state) .. text .. "|r")
        l.name = n
        l:Show()
    end
    for i = #show + 1, #lines do lines[i]:Hide() end
    T:SetHeight(22 + #show * ROW_H)
    T:Show()
end

C_Timer.NewTicker(1, function()
    if T and T:IsShown() then pcall(SC.RefreshTimers) end
end)
