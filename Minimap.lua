--[[
================================================================================
Dirty Tricks - Minimap Icon
================================================================================
Minimap icon using LibDBIcon for consistent placement and styling.

Copyright (c) 2026 Dirty Tricks
Licensed under the MIT License. See LICENSE for full text.
================================================================================
--]]

local ADDON_NAME = ...

local _, playerClass = UnitClass("player")
if playerClass ~= "ROGUE" and playerClass ~= "HUNTER" then
  return
end

if not SARDB then SARDB = { enabled = true, preferredTankName = nil } end
if not SARDB.minimap then SARDB.minimap = { hide = false, angle = 225 } end

local ICON_TEXTURES = {
  ROGUE = "Interface\\Icons\\Ability_Rogue_TricksOfTheTrade",
  HUNTER = "Interface\\Icons\\Ability_Hunter_Misdirection"
}

local IconDB = LibStub("LibDataBroker-1.1"):NewDataObject("DirtyTricks", {
  type = "data source",
  text = "Dirty Tricks",
  icon = ICON_TEXTURES[playerClass] or "Interface\\Icons\\INV_Misc_QuestionMark",
  OnClick = function()
    if DirtyTricksSettingsDialog then
      if DirtyTricksSettingsDialog:IsShown() then
        DirtyTricksSettingsDialog:Hide()
      else
        DirtyTricksSettingsDialog:Show()
      end
    end
  end,
  OnTooltip = function()
    GameTooltip:AddLine("Dirty Tricks")
    GameTooltip:AddLine("Left-click: Settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: Hide icon", 0.8, 0.8, 0.8)
  end,
})

local function ToggleMinimapIcon()
  local hidden = SARDB.minimap.hide
  if hidden then
    LibStub("LibDBIcon-1.0"):Show("DirtyTricks")
  else
    LibStub("LibDBIcon-1.0"):Hide("DirtyTricks")
  end
  SARDB.minimap.hide = not hidden
end

function DirtyTricks_ToggleMinimapIcon()
  ToggleMinimapIcon()
end

function DirtyTricks_SetMinimapIconVisible(visible)
  if visible then
    LibStub("LibDBIcon-1.0"):Show("DirtyTricks")
    SARDB.minimap.hide = false
  else
    LibStub("LibDBIcon-1.0"):Hide("DirtyTricks")
    SARDB.minimap.hide = true
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addonName)
  if addonName ~= ADDON_NAME then return end
  
  local LibStub = _G.LibStub
  if not LibStub then
    print("[Dirty Tricks] LibStub not found")
    self:UnregisterEvent("ADDON_LOADED")
    return
  end
  
  local LibDBIcon = LibStub("LibDBIcon-1.0", true)
  if not LibDBIcon then
    print("[Dirty Tricks] LibDBIcon-1.0 not found")
    self:UnregisterEvent("ADDON_LOADED")
    return
  end
  
  local button = LibDBIcon:Register("DirtyTricks", IconDB, SARDB.minimap)
  if not button then
    -- Silent failure - icon may already be registered on reload
    self:UnregisterEvent("ADDON_LOADED")
    return
  end
  
  -- Override OnClick to handle right-click hide
  button:SetScript("OnClick", function(self, buttonName)
    if buttonName == "RightButton" then
      DirtyTricks_SetMinimapIconVisible(false)
      print("[Dirty Tricks] Minimap icon hidden. Use /sar minimap to show it again.")
    else
      IconDB:OnClick(buttonName)
    end
  end)
  
  self:UnregisterEvent("ADDON_LOADED")
end)
