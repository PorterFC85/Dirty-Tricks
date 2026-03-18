--[[
================================================================================
Dirty Tricks - Settings Module
================================================================================
Settings dialog popup for configuring addon preferences.
Provides UI for enabling/disabling the addon and setting preferred tank names.

Copyright (c) 2026 Dirty Tricks
Licensed under the MIT License. See LICENSE for full text.
================================================================================
--]]

local ADDON_NAME, ADDON_TABLE = ...

-- Get addon version - try modern API first, fall back to hardcoded
local function GetAddonVersion()
  local version = "2.0.3"
  
  -- Try new C_AddOns namespace
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or version
  end
  
  return version
end

local ADDON_VERSION = GetAddonVersion()

local function EnsureSavedVars()
  if type(SARDB) ~= "table" then
    SARDB = { enabled = true, preferredTankName = nil }
  end
  if type(SARDB.minimap) ~= "table" then
    SARDB.minimap = { hide = false, angle = 225 }
  end
  if type(SARDB.announcements) ~= "boolean" then
    SARDB.announcements = true
  end
end

EnsureSavedVars()

local function TrimString(value)
  if value == nil then return "" end
  if strtrim then return strtrim(value) end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Function to get current profile type
local function GetProfileType()
  if IsInRaid() then
    return "Raid"
  elseif IsInGroup() then
    return "Party"
  else
    -- Solo: check if hunter with pet
    local _, playerClass = UnitClass("player")
    if playerClass == "HUNTER" and UnitExists("pet") and not UnitIsDead("pet") then
      return "Solo with pet"
    end
    return "Solo"
  end
end

-- Function to get detected tanks (from Core.lua's FindTanks)
local function GetDetectedTanks()
  local tanks = {}

  local function AddTank(unitId)
    local name = UnitName(unitId)
    if not name or name == "" then return end
    table.insert(tanks, {
      name = name,
      class = select(2, UnitClass(unitId))
    })
  end
  
  if not IsInGroup() then
    -- Solo: check if hunter with pet
    local _, playerClass = UnitClass("player")
    if playerClass == "HUNTER" and UnitExists("pet") and not UnitIsDead("pet") then
      local petName = UnitName("pet")
      if petName then
        table.insert(tanks, {
          name = petName,
          class = "HUNTER"  -- Use pet's class which appears as hunter
        })
      end
    end
    return tanks
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unitId = "raid" .. i
      if UnitExists(unitId) and not UnitIsDead(unitId) then
        local isTank = UnitGroupRolesAssigned(unitId) == "TANK"
        if not isTank and GetRaidRosterInfo then
          local assignedRole = select(10, GetRaidRosterInfo(i))
          isTank = assignedRole == "MAINTANK"
        end

        if isTank then
          AddTank(unitId)
          if #tanks >= 2 then break end
        end
      end
    end
  else
    if UnitGroupRolesAssigned("player") == "TANK" and not UnitIsDead("player") then
      AddTank("player")
    end

    for i = 1, GetNumSubgroupMembers() do
      local unitId = "party" .. i
      if UnitExists(unitId) and UnitGroupRolesAssigned(unitId) == "TANK" and not UnitIsDead(unitId) then
        AddTank(unitId)
        if #tanks >= 2 then break end
      end
    end
  end
  
  return tanks
end

-- Function to get class color
local function GetClassColor(class)
  local classColors = {
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    DRUID = { r = 1.00, g = 0.49, b = 0.04 },
    EVOKER = { r = 0.33, g = 0.59, b = 0.33 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    MAGE = { r = 0.41, g = 0.80, b = 0.94 },
    MONK = { r = 0.00, g = 1.00, b = 0.59 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
    ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
    SHAMAN = { r = 0.14, g = 0.35, b = 1.00 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
  }
  return classColors[class] or { r = 1, g = 1, b = 1 }
end

-- Detect if ElvUI is present
local function IsElvUILoaded()
  if IsAddOnLoaded and IsAddOnLoaded("ElvUI") then return true end
  if _G.ElvUI then return true end
  return false
end

-- Best-effort: apply ElvUI-like styling to a frame by recoloring textures and fontstrings
local function ApplyElvUIStyle(frame)
  if not IsElvUILoaded() then return end
  -- Try to safely access ElvUI engine
  local ok, E = pcall(function() return _G.ElvUI and _G.ElvUI[1] end)

  -- Iterate regions and coerce colors similar to ElvUI's dark transparent panel
  for i = 1, select('#', frame:GetRegions()) do
    local region = select(i, frame:GetRegions())
    if region and region.SetColorTexture then
      region:SetColorTexture(0.06, 0.06, 0.06, 0.92)
    elseif region and region.GetObjectType and region:GetObjectType() == "FontString" then
      region:SetTextColor(0.92, 0.92, 0.92)
    end
  end

  -- Style children buttons/fontstrings where possible
  for i = 1, select('#', frame:GetChildren()) do
    local child = select(i, frame:GetChildren())
    if child and child.GetObjectType then
      local t = child:GetObjectType()
      if t == "Button" then
        -- Try to tint button textures; ignore errors
        pcall(function()
          if child.SetNormalTexture then
            -- no-op if ElvUI media not present; keep minimal change
            child:SetNormalTexture(nil)
          end
        end)
      elseif t == "FontString" then
        child:SetTextColor(0.92, 0.92, 0.92)
      elseif t == "EditBox" then
        -- ensure editbox text is readable
        if child.SetTextColor then child:SetTextColor(1, 1, 1) end
      end
    end
  end

  -- As a last step, try to call ElvUI's SetTemplate if available (protected call)
  if ok and E and type(E.SetTemplate) == "function" then
    pcall(function() E:SetTemplate(frame, "Transparent") end)
  end
end

-- Blizzard-like panel style (fallback)
local function ApplyBlizzardStyle(frame)
  for i = 1, select('#', frame:GetRegions()) do
    local region = select(i, frame:GetRegions())
    if region and region.SetColorTexture then
      region:SetColorTexture(0.05, 0.05, 0.05, 0.98)
    elseif region and region.GetObjectType and region:GetObjectType() == "FontString" then
      region:SetTextColor(1, 1, 1)
    end
  end
end

local function CreateSettingsDialog()
  EnsureSavedVars()
  local dialog = CreateFrame("Frame", "DirtyTricksSettingsDialog", UIParent)
  dialog:SetSize(420, 340)
  dialog:SetPoint("CENTER")
  dialog:SetFrameStrata("DIALOG")
  dialog:Hide()
  
  -- Background texture
  local bg = dialog:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.05, 0.98)
  
  -- Border texture
  local border = dialog:CreateTexture(nil, "BORDER")
  border:SetAllPoints()
  border:SetColorTexture(0.2, 0.2, 0.2, 1)
  border:SetSize(422, 342)
  border:SetPoint("CENTER", dialog, "CENTER")
  
  -- Make movable
  dialog:SetMovable(true)
  dialog:EnableMouse(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", function(self) 
    if self:IsMovable() then self:StartMoving() end
  end)
  dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  
  -- Title Bar
  local titleBg = dialog:CreateTexture(nil, "BACKGROUND")
  titleBg:SetSize(420, 30)
  titleBg:SetPoint("TOPLEFT")
  titleBg:SetColorTexture(0.2, 0.2, 0.2, 0.98)
  
  local titleText = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  titleText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -8)
  titleText:SetText("Dirty Tricks")
  titleText:SetTextColor(1, 1, 0)
  
  -- Version and Profile subtitle
  local subtitleText = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  subtitleText:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 6)
  subtitleText:SetText("v" .. (ADDON_VERSION or "0.1.0"))
  subtitleText:SetTextColor(0.8, 0.8, 0.8)

  -- Top-right close button (X)
  local topCloseBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
  topCloseBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)
  topCloseBtn:SetScript("OnClick", function()
    dialog:Hide()
  end)

  local function CreateDivider(yOffset)
    local line = dialog:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", 20, yOffset)
    line:SetPoint("TOPRIGHT", -20, yOffset)
    line:SetHeight(1)
  end
  
  -- Enable/Disable Checkbox
  local enableCheck = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
  enableCheck:SetPoint("TOPLEFT", 20, -50)
  enableCheck:SetChecked(SARDB.enabled)
  enableCheck:SetScript("OnClick", function(self)
    SARDB.enabled = self:GetChecked()
    print("[Dirty Tricks] Addon", SARDB.enabled and "Enabled" or "Disabled")
    if SARDB.enabled then
      if DirtyTricksRequestUpdateMacros then
        DirtyTricksRequestUpdateMacros(true)
      elseif UpdateMacros then
        UpdateMacros(true)
      end
    end
  end)
  
  local enableLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  enableLabel:SetPoint("LEFT", enableCheck, "RIGHT", 8, 0)
  enableLabel:SetText("Enable Addon")
  enableLabel:SetTextColor(1, 1, 1, 1)

  -- Minimap Icon Checkbox
  EnsureSavedVars()
  if type(SARDB.minimap) ~= "table" then
    SARDB.minimap = { hide = false, angle = 225 }
  end
  local minimapState = SARDB.minimap
  local minimapCheck = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
  minimapCheck:SetPoint("TOPLEFT", 20, -75)
  minimapCheck:SetChecked(not minimapState.hide)
  minimapCheck:SetScript("OnClick", function(self)
    EnsureSavedVars()
    local visible = self:GetChecked()
    if DirtyTricks_SetMinimapIconVisible then
      DirtyTricks_SetMinimapIconVisible(visible)
    else
      if type(SARDB.minimap) ~= "table" then
        SARDB.minimap = { hide = false, angle = 225 }
      end
      SARDB.minimap.hide = not visible
    end
  end)

  local minimapLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  minimapLabel:SetPoint("LEFT", minimapCheck, "RIGHT", 8, 0)
  minimapLabel:SetText("Show Minimap Icon")
  minimapLabel:SetTextColor(1, 1, 1, 1)

  -- Announcements Checkbox
  local announcementsCheck = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
  announcementsCheck:SetPoint("TOPLEFT", 20, -100)
  announcementsCheck:SetChecked(SARDB.announcements)
  announcementsCheck:SetScript("OnClick", function(self)
    SARDB.announcements = self:GetChecked()
  end)

  local announcementsLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  announcementsLabel:SetPoint("LEFT", announcementsCheck, "RIGHT", 8, 0)
  announcementsLabel:SetText("Enable Chat Announcements")
  announcementsLabel:SetTextColor(1, 1, 1, 1)

  CreateDivider(-110)
  
  -- Profile and Detected Tanks display
  local profileLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  profileLabel:SetPoint("TOPLEFT", 20, -130)
  profileLabel:SetText("Profile: " .. UnitClass("player") .. " - " .. GetProfileType())
  profileLabel:SetTextColor(0.8, 1.0, 0.8)
  
  local tanksLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tanksLabel:SetPoint("TOPLEFT", 20, -150)
  tanksLabel:SetText("Detected Tanks:")
  tanksLabel:SetTextColor(0.9, 0.9, 0.9)
    -- Detected tanks frame container
  local tanksFrame = CreateFrame("Frame", nil, dialog)
  tanksFrame:SetPoint("TOPLEFT", 20, -170)
  tanksFrame:SetSize(300, 60)
    -- Update label based on profile type
  local function UpdateTanksLabel()
    local profileType = GetProfileType()
    if profileType == "Solo with pet" then
      tanksLabel:SetText("Redirect Target:")
    else
      tanksLabel:SetText("Detected Tanks:")
    end
  end
  
  -- Detected Tanks display (with class colors)
  local tanksDisplay = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tanksDisplay:SetPoint("TOPLEFT", 150, -150)
  tanksDisplay:SetMaxLines(2)
  
  -- Update tanks display function
  local function UpdateTanksDisplay()
    local tanks = GetDetectedTanks()
    if #tanks == 0 then
      tanksDisplay:SetText("None detected")
      tanksDisplay:SetTextColor(0.7, 0.7, 0.7)
    else
      local tankText = ""
      for i, tank in ipairs(tanks) do
        local color = GetClassColor(tank.class)
        tankText = tankText .. (i > 1 and ", " or "") .. tank.name
      end
      tanksDisplay:SetText(tankText)
      -- Color the first tank's name
      local firstTank = tanks[1]
      local firstColor = GetClassColor(firstTank.class)
      tanksDisplay:SetTextColor(firstColor.r, firstColor.g, firstColor.b)
    end
  end
  
  -- Quick Select Label
  CreateDivider(-175)

  local quickLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  quickLabel:SetPoint("TOPLEFT", 20, -190)
  quickLabel:SetText("Quick Select:")
  quickLabel:SetTextColor(0.9, 0.9, 0.9)

  -- Quick Select Buttons
  local quickBtn1 = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
  quickBtn1:SetPoint("TOPLEFT", 20, -210)
  quickBtn1:SetSize(120, 22)
  quickBtn1:Hide()

  local quickBtn2 = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
  quickBtn2:SetPoint("LEFT", quickBtn1, "RIGHT", 10, 0)
  quickBtn2:SetSize(120, 22)
  quickBtn2:Hide()

  local targetBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
  targetBtn:SetPoint("LEFT", quickBtn2, "RIGHT", 10, 0)
  targetBtn:SetSize(80, 22)
  targetBtn:SetText("Target")

  -- Preferred Tank Label
  local tankLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tankLabel:SetPoint("TOPLEFT", 20, -240)
  tankLabel:SetText("Force Specific Tank (optional):")
  tankLabel:SetTextColor(1, 1, 1, 1)

  -- Tank Name Input Box
  local tankInput = CreateFrame("EditBox", "DirtyTricksTankInput", dialog, "InputBoxTemplate")
  tankInput:SetPoint("TOPLEFT", 20, -260)
  tankInput:SetSize(200, 20)
  tankInput:SetText(SARDB.preferredTankName or "")
  tankInput:SetAutoFocus(false)
  tankInput:SetTextColor(1, 1, 1, 1)

  local function SetPreferredTank(name)
    SARDB.preferredTankName = name
    tankInput:SetText(name or "")
    if name == "focus" then
      print("[Dirty Tricks] Preferred tank set to: Focus")
    elseif name == "target" then
      local targetName = UnitName("target") or "Target"
      print("[Dirty Tricks] Preferred tank set to: " .. targetName)
    elseif name and name ~= "" then
      print("[Dirty Tricks] Preferred tank set to: " .. name)
    else
      print("[Dirty Tricks] Preferred tank cleared")
    end
    if SARDB.enabled then
      if DirtyTricksRequestUpdateMacros then
        DirtyTricksRequestUpdateMacros(true)
      elseif UpdateMacros then
        UpdateMacros(true)
      end
    end
  end

  local function UpdateQuickSelectButtons()
    local tanks = GetDetectedTanks()
    if tanks[1] and tanks[1].name then
      quickBtn1:SetText(tanks[1].name)
      quickBtn1.tankName = tanks[1].name
      quickBtn1:Show()
    else
      quickBtn1:Hide()
    end

    if tanks[2] and tanks[2].name then
      quickBtn2:SetText(tanks[2].name)
      quickBtn2.tankName = tanks[2].name
      quickBtn2:Show()
    else
      quickBtn2:Hide()
    end
  end

  quickBtn1:SetScript("OnClick", function(self)
    if self.tankName then
      SetPreferredTank(self.tankName)
    end
  end)

  quickBtn2:SetScript("OnClick", function(self)
    if self.tankName then
      SetPreferredTank(self.tankName)
    end
  end)

  targetBtn:SetScript("OnClick", function()
    if UnitExists("target") and UnitIsFriend("player", "target") and not UnitIsDead("target") then
      SetPreferredTank("target")
    else
      print("[Dirty Tricks] Target is not a valid friendly unit.")
    end
  end)

  -- Update tanks when dialog opens
  dialog:SetScript("OnShow", function()
    EnsureSavedVars()
    UpdateTanksLabel()
    UpdateTanksDisplay()
    UpdateQuickSelectButtons()
    tankInput:SetText(SARDB.preferredTankName or "")
    if type(SARDB.minimap) ~= "table" then
      SARDB.minimap = { hide = false, angle = 225 }
    end
    minimapCheck:SetChecked(not SARDB.minimap.hide)
    announcementsCheck:SetChecked(SARDB.announcements)
  end)
  
  -- OK Button
  local okBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
  okBtn:SetPoint("BOTTOMLEFT", 20, 15)
  okBtn:SetSize(100, 24)
  okBtn:SetText("OK")
  okBtn:SetScript("OnClick", function()
    local name = TrimString(tankInput:GetText())
    if name ~= "" then
      SetPreferredTank(name)
    else
      SetPreferredTank(nil)
    end
    dialog:Hide()
  end)
  
  -- Clear Button
  local clearBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
  clearBtn:SetPoint("LEFT", okBtn, "RIGHT", 10, 0)
  clearBtn:SetSize(100, 24)
  clearBtn:SetText("Clear")
  clearBtn:SetScript("OnClick", function()
    tankInput:SetText("")
    SetPreferredTank(nil)
  end)
  
  -- Apply appropriate style: ELVUI if available, otherwise Blizzard-like
  if IsElvUILoaded() then
    ApplyElvUIStyle(dialog)
  else
    ApplyBlizzardStyle(dialog)
  end

  return dialog
end

-- Create the dialog after a short delay to ensure Core.lua loads first
local delayedInit = CreateFrame("Frame")
delayedInit:SetScript("OnEvent", function(self, event, addonName)
  if addonName ~= ADDON_NAME then return end
  if not DirtyTricksSettingsDialog then
    DirtyTricksSettingsDialog = CreateSettingsDialog()
  end
  delayedInit:UnregisterEvent("ADDON_LOADED")
end)
delayedInit:RegisterEvent("ADDON_LOADED")




