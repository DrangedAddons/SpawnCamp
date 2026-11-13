-- SpawnCamp minimap button: the house kit's launcher (LibDBIcon, so minimap
-- addons can collect it). Click opens the window, right-click the settings.

local ADDON, SC = ...

SC.On("PLAYER_LOGIN", function()
    if not SC.char then return end
    SC.UI.Launcher({
        icon = SC.ICON,
        db = SC.char.minimap,
        onLeft = function() SC.ToggleWindow() end,
        onRight = function() SC.OpenSettings() end,
    })
end)
