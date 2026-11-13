---------------------------------------------------------
--  House kit - Window, settings page, launcher
--  Author: Dranged
---------------------------------------------------------
-- The pieces every DrangedAddons addon repeats: the main window shell, the
-- Options > AddOns page that points at it, and the LibDBIcon launcher.
-- Needs Theme.lua and Widgets.lua loaded first (same NS).

local ADDON, NS = ...
local UI = NS.UI

---------------------------------------------------------
--  SECTION: Window shell
---------------------------------------------------------
-- Centred, DIALOG strata, movable, clamped, closes on Esc, themed.
-- Dead centre on purpose: the user plays super-ultrawide at a low UI scale and
-- anything below centre hides behind their EllesmereUI player/castbar block.
-- opts: { name = global frame name (needed for Esc), title, width, height }
function UI.Window(opts)
    local f = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    f:SetSize(opts.width or 480, opts.height or 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop(NS.DEFAULT_BACKDROP)
    if opts.name then tinsert(UISpecialFrames, opts.name) end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    f.close = close

    f.nsTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.nsTitle:SetPoint("TOP", 0, -16)
    f.nsTitle:SetText(opts.title or ADDON)

    -- Content area below the 40px title bar; put widgets on f.body.
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 18, -44)
    f.body:SetPoint("BOTTOMRIGHT", -18, 16)

    f:Hide()
    NS.ThemeRegisterWindow(f)
    f:SetScript("OnShow", function(self)
        NS.ApplyTheme(self)
        UI.RefreshAll()
    end)
    return f
end

---------------------------------------------------------
--  SECTION: Options > AddOns page
---------------------------------------------------------
-- A short page with the icon, a line of text and a button that opens the
-- addon's own window. Call once; it registers at PLAYER_LOGIN.
function UI.RegisterSettingsPage(icon, slash, open)
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", function()
        if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
        local panel = CreateFrame("Frame")
        panel.name = ADDON
        local tex = panel:CreateTexture(nil, "ARTWORK")
        tex:SetSize(24, 24)
        tex:SetTexture(icon)
        tex:SetPoint("TOPLEFT", 16, -12)
        local title = UI.Text(panel, ADDON, "GameFontNormalLarge")
        title:SetPoint("LEFT", tex, "RIGHT", 6, 0)
        local text = UI.Text(panel, ADDON .. " has its own settings window."
            .. (slash and (" You can also open it with " .. slash .. ".") or ""))
        text:SetPoint("TOPLEFT", 16, -46)
        local btn = UI.Button(panel, "Open " .. ADDON, 160, 24, function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            open()
        end)
        btn:SetPoint("TOPLEFT", 16, -74)
        local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON)
        Settings.RegisterAddOnCategory(category)
    end)
end

---------------------------------------------------------
--  SECTION: Minimap launcher
---------------------------------------------------------
-- LibDBIcon button so minimap-collector addons can grab it.
-- opts: { icon, db = saved table for LibDBIcon ({ hide = false }),
--         onLeft, onRight, lines = extra tooltip lines }
function UI.Launcher(opts)
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (LDB and DBI) then return end
    local obj = LDB:NewDataObject(ADDON, {
        type = "launcher",
        text = ADDON,
        icon = opts.icon,
        OnClick = function(_, button)
            if button == "RightButton" and opts.onRight then opts.onRight() else opts.onLeft() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(ADDON)
            tt:AddLine("|cffffd100Click|r to open", 1, 1, 1)
            if opts.onRight then tt:AddLine("|cffffd100Right-click|r for settings", 1, 1, 1) end
            for _, line in ipairs(opts.lines or {}) do tt:AddLine(line, 1, 1, 1) end
            tt:AddLine("|cffffd100Drag|r to move this button", 1, 1, 1)
        end,
    })
    DBI:Register(ADDON, obj, opts.db)
    return obj
end

function UI.SetLauncherShown(db, on)
    db.hide = not on
    local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if not DBI then return end
    if on then DBI:Show(ADDON) else DBI:Hide(ADDON) end
end
