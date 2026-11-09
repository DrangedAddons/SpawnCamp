-- SpawnCamp minimap button (LibDBIcon, so minimap addons can collect it).
-- Click opens the window.

local ADDON, SC = ...

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBI = LibStub and LibStub("LibDBIcon-1.0", true)

SC.On("PLAYER_LOGIN", function()
    if not (LDB and DBI and SC.char) then return end
    local launcher = LDB:NewDataObject("SpawnCamp", {
        type = "launcher",
        text = "SpawnCamp",
        icon = SC.ICON,
        OnClick = function() SC.ToggleWindow() end,
        OnTooltipShow = function(tt)
            tt:AddLine("SpawnCamp")
            tt:AddLine("|cffffd100Click|r to open", 1, 1, 1)
            tt:AddLine("|cffffd100Drag|r to move this button", 1, 1, 1)
        end,
    })
    DBI:Register("SpawnCamp", launcher, SC.char.minimap)
end)
