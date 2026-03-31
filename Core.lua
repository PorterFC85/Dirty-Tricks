--[[
================================================================================
Dirty Tricks - Core Module
================================================================================
Description:
    Automatically creates and manages macros for Tricks of the Trade (Rogue)
    and Misdirection (Hunter) that dynamically target your group's tank.
    
    Updates in real-time as group composition changes, ensuring your redirect
    abilities always go to the right tank with zero manual intervention.

Author: PorterFC85
Version: 2.0.8
Date: March 31, 2026

================================================================================
Copyright (c) 2026 Dirty Tricks
Licensed under the MIT License. See LICENSE for full text.
================================================================================
--]]

local ADDON_NAME = ...
local Addon = CreateFrame("Frame")

-- Simple class-check: only load behavior for Rogue or Hunter
local _, playerClass = UnitClass("player")
if playerClass ~= "ROGUE" and playerClass ~= "HUNTER" then
  -- keep saved vars but do not initialize behavior
  return
end

-- Ensure saved vars
if not SARDB then SARDB = { enabled = true, preferredTankName = nil } end
if type(SARDB.announcements) ~= "boolean" then
  SARDB.announcements = true
end
if type(SARDB.preferRaidParityTank) ~= "boolean" then
  SARDB.preferRaidParityTank = false
end

local wasInGroup = IsInGroup()
local wasInRaid = IsInRaid()
local lastAutoAnnouncedContext = nil
local addonLoadTime = GetTime()
local STARTUP_GRACE_PERIOD = 1 -- suppress announcements for 1 second after load
local DEFAULT_UPDATE_DELAY = 0.35
local RAID_SETTLE_DELAY = 1.2
local READY_CHECK_UPDATE_DELAY = 0.2
local raidSettleUntil = 0

local function GetGroupAnnouncementContext()
  if IsInDelve and IsInDelve() then
    if IsInGroup() then return "delve-party" end
    return "delve-solo"
  end
  if IsInRaid() then return "raid" end
  if IsInGroup() then return "party" end
  return "solo"
end

local function MarkRaidSettleWindow()
  if IsInRaid() then
    raidSettleUntil = GetTime() + RAID_SETTLE_DELAY
  else
    raidSettleUntil = 0
  end
end

-- Class color information
local CLASS_COLORS = {
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

-- Get WoW format for colored text
local function ColorizeText(text, r, g, b)
  return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

-- Get class color for a unit
local function GetClassColorForUnit(unitId)
  if not UnitExists(unitId) then return { r = 1, g = 1, b = 1 } end
  local _, class = UnitClass(unitId)
  return CLASS_COLORS[class] or { r = 1, g = 1, b = 1 }
end

-- Colors for addon messages
local ADDON_COLOR = { r = 0.3, g = 0.8, b = 0.3 } -- Green
local PROFILE_COLOR = { r = 0.8, g = 0.8, b = 0.3 } -- Yellow
local STATUS_COLOR = { r = 0.7, g = 0.7, b = 1 } -- Light blue

-- Chat notification helper: respects the announcements toggle.
-- Debug output and slash command responses should use print() directly.
local function NotifyPrint(msg)
  if type(SARDB) == "table" and SARDB.announcements then
    print(msg)
  end
end

-- Macro configuration
local MACRO_SPELLS = {
  { id = 57934, fallbackName = "Tricks of the Trade" },
  { id = 34477, fallbackName = "Misdirection" }
}
local MACRO_PREFIX = "Dirty "
local MACRO_TEMPLATE = "#showtooltip %s\n/cast "
local MACRO_TARGET_TEMPLATE = "[@%s,help,nodead]"
local MACRO_PET_TARGET_TEMPLATE = "[@pet]" -- Simpler conditional for pet targeting

local TANK_CLASSES = {
  WARRIOR = true,
  PALADIN = true,
  DEATHKNIGHT = true,
  DEMONHUNTER = true,
  MONK = true,
  DRUID = true
}

local TANK_SPEC_IDS = {
  [73] = true,  -- Warrior: Protection
  [66] = true,  -- Paladin: Protection
  [250] = true, -- Death Knight: Blood
  [581] = true, -- Demon Hunter: Vengeance
  [268] = true, -- Monk: Brewmaster
  [104] = true  -- Druid: Guardian
}

local DELVE_INSPECT_TIMEOUT = 1.5
local DELVE_INSPECT_MAX_RETRIES = 1

local delveInspectSpecByGUID = {}
local delveInspectPendingByGUID = {}
local delveInspectAttemptCountByGUID = {}
local delveInspectSessionKey = nil
local delveInspectRequestSerial = 0
local delveInspectLastTargetName = nil
local delveInspectLastResult = "idle"

local IsInDelve
local QueueDelveInspectScan
local RequestUpdateMacros

local function TrimString(value)
  if value == nil then return "" end
  if strtrim then return strtrim(value) end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GetSpellInfoSafe(spellId, fallbackName)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(spellId)
    if info and info.name then
      return info.name, info.iconID
    end
  end

  local name, _, icon = GetSpellInfo(spellId)
  if name then return name, icon end

  return fallbackName, nil
end

local function IsRaidUnitTank(unitId, raidIndex)
  if UnitGroupRolesAssigned(unitId) == "TANK" then
    return true
  end

  -- Fallback for raids where role assignments are incomplete.
  if GetRaidRosterInfo and raidIndex then
    local assignedRole = select(10, GetRaidRosterInfo(raidIndex))
    if assignedRole == "MAINTANK" then
      return true
    end
  end

  return false
end

local function GetRaidSubgroupForUnit(unitId, raidIndex)
  if not IsInRaid() or not GetRaidRosterInfo then return nil end

  local index = raidIndex
  if not index and UnitInRaid then
    index = UnitInRaid(unitId)
  end
  if not index then return nil end

  local subgroup = select(3, GetRaidRosterInfo(index))
  if type(subgroup) == "number" and subgroup > 0 then
    return subgroup
  end

  return nil
end

local function IsSameRaidParity(subgroupA, subgroupB)
  if not subgroupA or not subgroupB then return false end
  return (subgroupA % 2) == (subgroupB % 2)
end

local function IsTankClassUnit(unitId)
  if not UnitExists(unitId) then return false end
  local _, class = UnitClass(unitId)
  return class and TANK_CLASSES[class] or false
end

local function IsTankSpecId(specId)
  return specId and TANK_SPEC_IDS[specId] or false
end

local function GetPlayerSpecId()
  if not GetSpecialization or not GetSpecializationInfo then return nil end
  local specIndex = GetSpecialization()
  if not specIndex then return nil end
  local specId = GetSpecializationInfo(specIndex)
  if specId and specId > 0 then
    return specId
  end
  return nil
end

-- Returns true if at least one confirmed tank exists (player or a cached Delve inspect).
-- Used to short-circuit Delve inspect scanning once a tank is known.
local function HasConfirmedDelveTank()
  if IsTankSpecId(GetPlayerSpecId()) then return true end
  for _, cachedSpecId in pairs(delveInspectSpecByGUID) do
    if IsTankSpecId(cachedSpecId) then return true end
  end
  return false
end

local function GetOtherPlayerCountInParty()
  if not IsInGroup() or IsInRaid() then return 0 end

  local count = 0
  for i = 1, GetNumSubgroupMembers() do
    local unitId = "party" .. i
    if UnitExists(unitId) and UnitIsPlayer(unitId) then
      count = count + 1
    end
  end

  return count
end

local function ShouldScanDelveInspects()
  if not IsInDelve() then return false end
  if not IsInGroup() or IsInRaid() then return false end
  return GetOtherPlayerCountInParty() > 0
end

local function GetDelveInspectSessionKey()
  if not IsInDelve() then return nil end

  local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
  if instanceType ~= "scenario" then return nil end

  return table.concat({
    tostring(instanceID or 0),
    tostring(difficultyID or 0),
    tostring(name or "unknown")
  }, ":")
end

local function GetActiveDelveInspectPending()
  for guid, pending in pairs(delveInspectPendingByGUID) do
    if pending then
      return guid, pending
    end
  end
  return nil, nil
end

local function GetDelveInspectRetryCount()
  local retries = 0
  for _, attempts in pairs(delveInspectAttemptCountByGUID) do
    if attempts and attempts > 1 then
      retries = retries + (attempts - 1)
    end
  end
  return retries
end

local function ClearDelveInspectPending(guid)
  local pending = delveInspectPendingByGUID[guid]
  delveInspectPendingByGUID[guid] = nil
  return pending
end

local function PruneDelveInspectState()
  local activeGuids = {}
  local hadPendingRemoval = false
  for i = 1, GetNumSubgroupMembers() do
    local unitId = "party" .. i
    if UnitExists(unitId) and UnitIsPlayer(unitId) then
      local guid = UnitGUID(unitId)
      if guid then
        activeGuids[guid] = true
      end
    end
  end

  for guid in pairs(delveInspectSpecByGUID) do
    if not activeGuids[guid] then
      delveInspectSpecByGUID[guid] = nil
    end
  end
  for guid in pairs(delveInspectPendingByGUID) do
    if not activeGuids[guid] then
      delveInspectPendingByGUID[guid] = nil
      hadPendingRemoval = true
    end
  end
  for guid in pairs(delveInspectAttemptCountByGUID) do
    if not activeGuids[guid] then
      delveInspectAttemptCountByGUID[guid] = nil
    end
  end

  if hadPendingRemoval and ClearInspectPlayer then
    ClearInspectPlayer()
  end
end

local function ResetDelveInspectState()
  local hadPending = false
  for guid in pairs(delveInspectPendingByGUID) do
    hadPending = true
    delveInspectPendingByGUID[guid] = nil
  end

  for guid in pairs(delveInspectSpecByGUID) do
    delveInspectSpecByGUID[guid] = nil
  end
  for guid in pairs(delveInspectAttemptCountByGUID) do
    delveInspectAttemptCountByGUID[guid] = nil
  end

  delveInspectLastTargetName = nil
  delveInspectLastResult = "idle"

  -- Only clear inspect if this addon previously requested one.
  if hadPending and ClearInspectPlayer then
    ClearInspectPlayer()
  end
end

local function SyncDelveInspectSession()
  local sessionKey = GetDelveInspectSessionKey()

  if not sessionKey or not IsInGroup() or IsInRaid() then
    if delveInspectSessionKey then
      delveInspectSessionKey = nil
      ResetDelveInspectState()
    end
    return false
  end

  if delveInspectSessionKey ~= sessionKey then
    delveInspectSessionKey = sessionKey
    ResetDelveInspectState()
  end

  return true
end

local function HandleDelveInspectTimeout(guid, requestSerial)
  local pending = delveInspectPendingByGUID[guid]
  if not pending or pending.requestSerial ~= requestSerial then
    return
  end

  ClearDelveInspectPending(guid)
  delveInspectLastTargetName = pending.unitName or delveInspectLastTargetName

  if ClearInspectPlayer then
    ClearInspectPlayer()
  end

  if SyncDelveInspectSession() and ShouldScanDelveInspects() and (delveInspectAttemptCountByGUID[guid] or 0) <= DELVE_INSPECT_MAX_RETRIES then
    delveInspectLastResult = "timeout-retry"
  else
    delveInspectSpecByGUID[guid] = false
    delveInspectLastResult = "timeout-final"
  end

  QueueDelveInspectScan()
  RequestUpdateMacros(false, { delay = 0.05, bypassRaidSettle = true })
end

QueueDelveInspectScan = function()
  if not NotifyInspect or not CanInspect then return end
  if not SyncDelveInspectSession() or not ShouldScanDelveInspects() then
    return
  end

  if GetActiveDelveInspectPending() then
    return
  end

  -- If a tank spec is already confirmed (player or cached inspect), stop scanning.
  if HasConfirmedDelveTank() then
    delveInspectLastResult = "tank-found-scan-stopped"
    return
  end

  for i = 1, GetNumSubgroupMembers() do
    local unitId = "party" .. i
    if UnitExists(unitId) and UnitIsPlayer(unitId) and IsTankClassUnit(unitId) then
      local guid = UnitGUID(unitId)
      if guid and delveInspectSpecByGUID[guid] == nil and not delveInspectPendingByGUID[guid] and (delveInspectAttemptCountByGUID[guid] or 0) <= DELVE_INSPECT_MAX_RETRIES then
        if CanInspect(unitId) then
          delveInspectRequestSerial = delveInspectRequestSerial + 1
          local requestSerial = delveInspectRequestSerial
          delveInspectAttemptCountByGUID[guid] = (delveInspectAttemptCountByGUID[guid] or 0) + 1
          delveInspectLastTargetName = UnitName(unitId) or unitId
          delveInspectLastResult = "requested"
          delveInspectPendingByGUID[guid] = {
            unitId = unitId,
            unitName = delveInspectLastTargetName,
            requestedAt = GetTime(),
            requestSerial = requestSerial
          }
          NotifyInspect(unitId)
          C_Timer.After(DELVE_INSPECT_TIMEOUT, function()
            HandleDelveInspectTimeout(guid, requestSerial)
          end)
          return
        end
      end
    end
  end
end

local function FindPartyUnitByGUID(guid)
  if not guid then return nil end
  for i = 1, GetNumSubgroupMembers() do
    local unitId = "party" .. i
    if UnitExists(unitId) and UnitGUID(unitId) == guid then
      return unitId
    end
  end
  return nil
end

local function CountTableEntries(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

-- Find all tanks in current group (returns table of {name, unitId})
local function FindTanks()
  local alivePreferredTanks = {}
  local aliveOtherTanks = {}
  local deadPreferredTanks = {}
  local deadOtherTanks = {}
  local useRaidParityPreference = IsInRaid() and SARDB.preferRaidParityTank
  local playerRaidSubgroup = nil

  if useRaidParityPreference then
    playerRaidSubgroup = GetRaidSubgroupForUnit("player")
  end

  local function AddTank(unitId, raidIndex)
    local name = UnitName(unitId)
    if not name or name == "" then return false end

    local tankInfo = {
      name = name,
      unitId = unitId
    }

    local matchesPlayerParity = false
    if useRaidParityPreference and playerRaidSubgroup then
      local tankSubgroup = GetRaidSubgroupForUnit(unitId, raidIndex)
      matchesPlayerParity = IsSameRaidParity(playerRaidSubgroup, tankSubgroup)
    end

    -- Prioritize alive tanks, but keep dead tanks as backup
    if UnitIsDead(unitId) or UnitIsGhost(unitId) then
      if matchesPlayerParity then
        table.insert(deadPreferredTanks, tankInfo)
      else
        table.insert(deadOtherTanks, tankInfo)
      end
    else
      if matchesPlayerParity then
        table.insert(alivePreferredTanks, tankInfo)
      else
        table.insert(aliveOtherTanks, tankInfo)
      end
    end

    local totalCount = #alivePreferredTanks + #aliveOtherTanks + #deadPreferredTanks + #deadOtherTanks
    return totalCount >= 2
  end
  
  if IsInRaid() then
    -- Search raid members and support both assigned roles and MAINTANK fallback.
    local shouldEarlyExit = not (useRaidParityPreference and playerRaidSubgroup)
    for i = 1, GetNumGroupMembers() do
      local unitId = "raid" .. i
      if UnitExists(unitId) and IsRaidUnitTank(unitId, i) then
        if AddTank(unitId, i) and shouldEarlyExit then break end
      end
    end
  elseif IsInGroup() then
    -- Party units do not include the player, so include player explicitly.
    if UnitGroupRolesAssigned("player") == "TANK" then
      AddTank("player")
    end

    for i = 1, GetNumSubgroupMembers() do
      local unitId = "party" .. i
      if UnitExists(unitId) and UnitGroupRolesAssigned(unitId) == "TANK" then
        if AddTank(unitId) then break end
      end
    end

    -- Delve fallback: roles are not assigned inside Delves.
    -- Use spec-aware detection for real players when inspect data is available.
    local totalFound = #alivePreferredTanks + #aliveOtherTanks + #deadPreferredTanks + #deadOtherTanks
    if totalFound == 0 and IsInDelve() then
      local playerSpecId = GetPlayerSpecId()
      if IsTankSpecId(playerSpecId) or (not playerSpecId and IsTankClassUnit("player")) then
        AddTank("player")
      end

      for i = 1, GetNumSubgroupMembers() do
        local unitId = "party" .. i
        if UnitExists(unitId) and UnitIsPlayer(unitId) and IsTankClassUnit(unitId) then
          local guid = UnitGUID(unitId)
          local specId = guid and delveInspectSpecByGUID[guid] or nil
          if IsTankSpecId(specId) then
            AddTank(unitId)
          end
        end
      end
    end
  else
    return alivePreferredTanks
  end

  local orderedTanks = {}

  -- Preserve alive-before-dead behavior while preferring player's raid parity when enabled.
  for _, tank in ipairs(alivePreferredTanks) do
    table.insert(orderedTanks, tank)
  end
  for _, tank in ipairs(aliveOtherTanks) do
    table.insert(orderedTanks, tank)
  end
  for _, tank in ipairs(deadPreferredTanks) do
    table.insert(orderedTanks, tank)
  end
  for _, tank in ipairs(deadOtherTanks) do
    table.insert(orderedTanks, tank)
  end

  return orderedTanks
end

-- Check if player is in a Delve
IsInDelve = function()
  local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
  -- Delves use instance type "scenario"
  if instanceType == "scenario" then
    -- Check for Delve-specific difficulty IDs (208 for Delves in The War Within)
    -- Or check if the instance name contains "delve" or related keywords
    if difficultyID and difficultyID == 208 then
      return true
    end
    -- Fallback: check instance name for Delve keywords
    if name then
      local lowerName = name:lower()
      if lowerName:find("delve") or 
         lowerName:find("earthcrawl") or 
         lowerName:find("waterworks") or 
         lowerName:find("nightfall") or
         lowerName:find("mycomancer") or
         lowerName:find("sinkhole") or
         lowerName:find("kriegval") or
         lowerName:find("spiral") or
         lowerName:find("underkeep") then
        return true
      end
    end
  end
  return false
end

-- Find Delve companion (Brann, Valeera, etc.) in the current group
local function FindDelveCompanion()
  if not IsInDelve() then return nil end
  
  local groupType = (IsInRaid() and "raid") or (IsInGroup() and "party") or nil
  if not groupType then return nil end
  
  -- Known Delve companion names
  local companionNames = {
    "Brann Bronzebeard",
    "Valeera Sanguinar"
  }
  
  -- Search group members for a Delve companion
  for i = 1, GetNumGroupMembers() do
    local unitId = groupType .. i
    if UnitExists(unitId) then
      local name = UnitName(unitId)
      if name then
        for _, companionName in ipairs(companionNames) do
          if name == companionName then
            return {
              name = name,
              unitId = unitId
            }
          end
        end
      end
    end
  end
  
  return nil
end

-- Get current profile type string
local function GetProfileTypeString()
  if IsInRaid() then
    return "Raid"
  elseif IsInGroup() then
    if IsInDelve() then
      return "Delve"
    end
    return "Party"
  else
    -- Solo: check if hunter with pet
    if playerClass == "HUNTER" and UnitExists("pet") and not UnitIsDead("pet") then
      return "Solo with pet"
    end
    if IsInDelve() then
      return "Solo (Delve)"
    end
    return "Solo"
  end
end

-- Create or update macros
function UpdateMacros(shouldPrintMessage)
  local tanks = FindTanks()
  local profileType = GetProfileTypeString()
  local delveCompanion = FindDelveCompanion()
  
  -- Determine the current tank selection
  local currentSelectedTank = SARDB.preferredTankName
  if not currentSelectedTank and #tanks > 0 then
    currentSelectedTank = tanks[1].name
  end
  
  -- Special case: hunter with pet (always prefer pet over Delve companion)
  if not currentSelectedTank and playerClass == "HUNTER" then
    if UnitExists("pet") and not UnitIsDead("pet") then
      currentSelectedTank = "pet"
    end
  end
  
  -- Special case: Delve with no player tanks - use Delve companion
  -- For Hunters: ONLY if they have no pet
  -- For Rogues: Always use companion if no player tanks
  -- Note: Delves with NPC companions (Brann) show IsInGroup() as true, so we check for Delve + no tanks
  -- IMPORTANT: Only use companion if there are ZERO player tanks available
  if not currentSelectedTank and IsInDelve() and #tanks == 0 and delveCompanion then
    if playerClass == "ROGUE" then
      currentSelectedTank = delveCompanion.name
    elseif playerClass == "HUNTER" and (not UnitExists("pet") or UnitIsDead("pet")) then
      -- Only use Delve companion if hunter has no pet
      currentSelectedTank = delveCompanion.name
    end
  end
  
  -- Only print messages if explicitly requested or if the selection changed (but not during startup grace period)
  -- Auto announcements happen once per context transition: solo <-> party <-> raid.
  local isStartupPeriod = (GetTime() - addonLoadTime) < STARTUP_GRACE_PERIOD
  local currentAnnouncementContext = GetGroupAnnouncementContext()
  local contextChanged = (currentAnnouncementContext ~= lastAutoAnnouncedContext)
  local shouldAutoAnnounce = contextChanged and not isStartupPeriod
  local shouldPrintOutput = SARDB.announcements and (shouldPrintMessage or shouldAutoAnnounce)

  if shouldAutoAnnounce then
    -- Mark this context as announced immediately so we only auto-announce once per transition.
    lastAutoAnnouncedContext = currentAnnouncementContext
  end
  
  if shouldPrintOutput and currentSelectedTank then
    -- Show which tank is selected
    -- Determine class-specific verb
    local verb = (playerClass == "HUNTER") and "Misdirecting to:" or "Tricks to:"
    
    if SARDB.preferredTankName then
      -- User has set a preferred tank
      local preferredLabel = SARDB.preferredTankName
      if SARDB.preferredTankName == "focus" then
        preferredLabel = "Focus"
      elseif SARDB.preferredTankName == "target" then
        preferredLabel = UnitName("target") or "Target"
      end
      local msg = ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " " ..
                  ColorizeText(playerClass .. " - " .. verb, PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b) .. " " ..
                  ColorizeText(preferredLabel, 1, 1, 0.8)
      print(msg)
    elseif #tanks > 0 then
      -- Auto-detected tanks
      local tankNames = {}
      for _, tank in ipairs(tanks) do
        if tank and tank.name and tank.unitId then
          local color = GetClassColorForUnit(tank.unitId)
          table.insert(tankNames, ColorizeText(tank.name, color.r, color.g, color.b))
        end
      end
      if #tankNames > 0 then
        local msg = ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " " ..
                    ColorizeText(playerClass .. " - " .. verb, PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b) .. " " .. table.concat(tankNames, ", ")
        print(msg)
      end
    elseif currentSelectedTank == "pet" then
      -- Solo hunter with pet
      local petName = UnitName("pet") or "Pet"
      local msg = ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " " ..
                  ColorizeText(playerClass .. " - " .. verb, PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b) .. " " ..
                  ColorizeText(petName, 1, 1, 0.8)
      print(msg)
    elseif delveCompanion and currentSelectedTank == delveCompanion.name then
      -- Delve companion (Valeera, Brann, etc.)
      local msg = ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " " ..
                  ColorizeText(playerClass .. " - " .. verb, PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b) .. " " ..
                  ColorizeText(delveCompanion.name, 1, 1, 0.8)
      print(msg)
    end
    
  end
  
  for _, spellData in ipairs(MACRO_SPELLS) do
    -- Skip spells not relevant to this class
    local isRelevant = true
    if (playerClass == "ROGUE" and spellData.id == 34477) or (playerClass == "HUNTER" and spellData.id == 57934) then
      isRelevant = false
    end
    
    if isRelevant then
      local spellName, icon = GetSpellInfoSafe(spellData.id, spellData.fallbackName)
      if spellName then
        -- Build macro name
        local macroName = MACRO_PREFIX .. spellName

        -- Build macro body with conditional targeting
        local body = string.format(MACRO_TEMPLATE, spellName)

        -- Determine if we should use Delve companion (ONLY if no player tanks exist)
        -- For Hunters: also requires no pet
        local useDelveCompanion = false
        if IsInDelve() and #tanks == 0 and delveCompanion then
          if playerClass == "ROGUE" then
            useDelveCompanion = true
          elseif playerClass == "HUNTER" and (not UnitExists("pet") or UnitIsDead("pet")) then
            useDelveCompanion = true
          end
        end

        -- Special-case: Hunter with Misdirection
        -- Priority: Pet > Delve companion > tanks > player
        if spellData.id == 34477 and playerClass == "HUNTER" then
          -- Always prefer pet if available
          if UnitExists("pet") and not UnitIsDead("pet") then
            body = body .. MACRO_PET_TARGET_TEMPLATE
          elseif useDelveCompanion then
            -- No pet, in Delve, no player tanks - use companion
            body = body .. string.format(MACRO_TARGET_TEMPLATE, delveCompanion.unitId)
          else
            -- No pet, use regular tank targeting
            if SARDB.preferredTankName then
              body = body .. string.format(MACRO_TARGET_TEMPLATE, SARDB.preferredTankName)
            else
              for _, tank in ipairs(tanks) do
                if tank and tank.unitId then
                  body = body .. string.format(MACRO_TARGET_TEMPLATE, tank.unitId)
                end
              end
            end
          end
        -- Special-case: Rogue in Delve with no player tanks - target Delve companion
        elseif spellData.id == 57934 and useDelveCompanion then
          body = body .. string.format(MACRO_TARGET_TEMPLATE, delveCompanion.unitId)
        else
          -- If preferred tank is set, use that instead of auto-detection
          if SARDB.preferredTankName then
            if SARDB.preferredTankName == "focus" or SARDB.preferredTankName == "target" then
              body = body .. string.format(MACRO_TARGET_TEMPLATE, SARDB.preferredTankName)
            else
              body = body .. string.format(MACRO_TARGET_TEMPLATE, SARDB.preferredTankName)
            end
          else
            -- Add tank targets from auto-detection (includes dead tanks)
            -- The [@unit,help,nodead] conditional in macro will skip dead tanks automatically
            for _, tank in ipairs(tanks) do
              if tank and tank.unitId then
                body = body .. string.format(MACRO_TARGET_TEMPLATE, tank.unitId)
              end
            end
          end
        end

        -- Add player as fallback
        body = body .. string.format(MACRO_TARGET_TEMPLATE, "player")

        -- Complete the macro
        body = body .. " " .. spellName

        -- Get existing macro
        local existingMacro, _, existingBody = GetMacroInfo(macroName)

        -- Trim whitespace for comparison
        if existingBody then
          existingBody = existingBody:gsub("^%s+", ""):gsub("%s+$", "")
        end

        -- Create or update the macro - ONLY print on actual changes
        if not existingMacro then
          CreateMacro(macroName, icon, body)
          local msg = ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " " ..
                      ColorizeText("Created macro:", STATUS_COLOR.r, STATUS_COLOR.g, STATUS_COLOR.b) .. " " ..
                      macroName .. " " .. ColorizeText("(" .. profileType .. ")", PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b)
          NotifyPrint(msg)
        elseif existingBody ~= body then
          EditMacro(macroName, macroName, icon, body)
          local msg = ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " " ..
                      ColorizeText("Macro updated:", STATUS_COLOR.r, STATUS_COLOR.g, STATUS_COLOR.b) .. " " ..
                      macroName .. " " .. ColorizeText("(" .. profileType .. ")", PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b)
          NotifyPrint(msg)
        end
      end
    end
  end
end

-- Event frame for group changes
local updateTimer = nil
local updateQueued = false
local pendingPrint = false
local pendingBypassRaidSettle = false
local pendingDelay = nil

local function RunQueuedUpdate()
  if not SARDB.enabled then return end
  if InCombatLockdown and InCombatLockdown() then
    updateQueued = true
    return
  end

  local now = GetTime()
  if IsInRaid() and not pendingBypassRaidSettle and raidSettleUntil > now then
    local waitTime = raidSettleUntil - now
    updateTimer = C_Timer.After(waitTime, function()
      updateTimer = nil
      RunQueuedUpdate()
    end)
    return
  end

  updateQueued = false
  local shouldPrint = pendingPrint
  pendingPrint = false
  pendingBypassRaidSettle = false
  UpdateMacros(shouldPrint)
end

RequestUpdateMacros = function(shouldPrint, options)
  options = options or {}
  pendingPrint = pendingPrint or shouldPrint
  pendingBypassRaidSettle = pendingBypassRaidSettle or options.bypassRaidSettle

  local requestedDelay = options.delay
  if type(requestedDelay) ~= "number" or requestedDelay < 0 then
    requestedDelay = DEFAULT_UPDATE_DELAY
  end

  if not pendingDelay or requestedDelay < pendingDelay then
    pendingDelay = requestedDelay
  end

  if updateTimer then return end

  local delay = pendingDelay or DEFAULT_UPDATE_DELAY
  pendingDelay = nil

  updateTimer = C_Timer.After(delay, function()
    updateTimer = nil
    RunQueuedUpdate()
  end)
end

local function HandleGroupStateTransition()
  local inGroup = IsInGroup()
  local inRaid = IsInRaid()

  if wasInGroup and not inGroup then
    -- Forced targets are group-scoped; clear them when returning to solo.
    if SARDB.preferredTankName then
      SARDB.preferredTankName = nil
    end
  end

  if inRaid and (not wasInRaid) then
    MarkRaidSettleWindow()
  elseif (not inRaid) and wasInRaid then
    raidSettleUntil = 0
  end

  wasInGroup = inGroup
  wasInRaid = inRaid
end

local function HandleInspectReady(guid)
  if not guid then return end

  -- Ignore inspect completions that were not initiated by our Delve scan.
  local pending = delveInspectPendingByGUID[guid]
  if not pending then
    return
  end

  -- Delve-only inspect logic should never run outside Delves.
  if not SyncDelveInspectSession() or not ShouldScanDelveInspects() then
    ClearDelveInspectPending(guid)
    return
  end

  ClearDelveInspectPending(guid)
  delveInspectLastTargetName = pending.unitName or delveInspectLastTargetName

  local unitId = FindPartyUnitByGUID(guid)
  if unitId and GetInspectSpecialization then
    local specId = GetInspectSpecialization(unitId)
    if specId and specId > 0 then
      delveInspectSpecByGUID[guid] = specId
      delveInspectLastResult = "ready:" .. tostring(specId)
    else
      delveInspectSpecByGUID[guid] = false
      delveInspectLastResult = "ready:none"
    end
  else
    delveInspectSpecByGUID[guid] = false
    delveInspectLastResult = "ready:missing"
  end

  if ClearInspectPlayer then
    ClearInspectPlayer()
  end

  QueueDelveInspectScan()
  RequestUpdateMacros(false, { delay = 0.05, bypassRaidSettle = true })
end

DirtyTricksRequestUpdateMacros = RequestUpdateMacros

Addon:RegisterEvent("GROUP_JOINED")
Addon:RegisterEvent("GROUP_ROSTER_UPDATE")
Addon:RegisterEvent("PLAYER_ENTERING_WORLD")
Addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
Addon:RegisterEvent("PLAYER_REGEN_ENABLED")
Addon:RegisterEvent("PLAYER_ALIVE")
Addon:RegisterEvent("PLAYER_UNGHOST")
Addon:RegisterEvent("UNIT_PET")
Addon:RegisterEvent("READY_CHECK")
Addon:RegisterEvent("INSPECT_READY")
Addon:SetScript("OnEvent", function(self, event, ...)
  HandleGroupStateTransition()

  if event == "GROUP_JOINED" or event == "GROUP_ROSTER_UPDATE" then
    MarkRaidSettleWindow()
    if SyncDelveInspectSession() then
      PruneDelveInspectState()
    end
    QueueDelveInspectScan()
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    if SyncDelveInspectSession() then
      PruneDelveInspectState()
    end
    QueueDelveInspectScan()
  elseif event == "INSPECT_READY" then
    HandleInspectReady(...)
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    if updateQueued then
      RunQueuedUpdate()
    end
    return
  end
  
  -- Delay update slightly after player releases/resurrects and runs back
  -- to avoid flickering during death/release/resurrect transitions
  if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    C_Timer.After(0.5, function()
      RequestUpdateMacros(false)
    end)
    return
  end

  if event == "READY_CHECK" then
    -- Ready check is often close to pull time; run a quick refresh without extra settle delay.
    RequestUpdateMacros(false, { delay = READY_CHECK_UPDATE_DELAY, bypassRaidSettle = true })
    return
  end

  RequestUpdateMacros(false)
end)

-- Slash commands
SLASH_SAR1 = "/dirtytricks"
SlashCmdList["SAR"] = function(msg)
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  local profileType = GetProfileTypeString()
  
  -- If no command given, open settings dialog
  if cmd == "" then
    if DirtyTricksSettingsDialog then
      if DirtyTricksSettingsDialog:IsShown() then
        DirtyTricksSettingsDialog:Hide()
      else
        DirtyTricksSettingsDialog:Show()
      end
    end
    return
  end
  
  if cmd == "toggle" then
    SARDB.enabled = not SARDB.enabled
    local status = SARDB.enabled and ColorizeText("Enabled", 0.3, 0.8, 0.3) or ColorizeText("Disabled", 1, 0.3, 0.3)
    print(ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " Addon " .. status)
    if SARDB.enabled then RequestUpdateMacros(true) end
  elseif cmd == "settank" and rest ~= "" then
    SARDB.preferredTankName = TrimString(rest)
    local msg = ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " " ..
                ColorizeText(playerClass .. " - " .. profileType, PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b) .. " | " ..
                ColorizeText("Preferred tank set to:", STATUS_COLOR.r, STATUS_COLOR.g, STATUS_COLOR.b) .. " " ..
                ColorizeText(SARDB.preferredTankName, 1, 1, 0.8)
    print(msg)
    RequestUpdateMacros(true)
  elseif cmd == "cleartank" then
    SARDB.preferredTankName = nil
    local msg = ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " " ..
                ColorizeText(playerClass .. " - " .. profileType, PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b) .. " | " ..
                ColorizeText("Using auto-detection", STATUS_COLOR.r, STATUS_COLOR.g, STATUS_COLOR.b)
    print(msg)
    RequestUpdateMacros(true)
  elseif cmd == "minimap" or cmd == "icon" then
    if DirtyTricks_ToggleMinimapIcon then
      DirtyTricks_ToggleMinimapIcon()
    else
      print(ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " Minimap icon not available.")
    end
  elseif cmd == "debug" then
    -- Debug information for troubleshooting
    print(ColorizeText("[Dirty Tricks Debug]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b))
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    print("  Instance: " .. ColorizeText(tostring(name or "None"), 1, 1, 0.8))
    print("  Type: " .. ColorizeText(tostring(instanceType or "none"), 1, 1, 0.8))
    print("  Difficulty: " .. ColorizeText(tostring(difficultyID or "none"), 1, 1, 0.8))
    print("  In Delve: " .. ColorizeText(tostring(IsInDelve()), 1, 1, 0.8))
    print("  In Group: " .. ColorizeText(tostring(IsInGroup()), 1, 1, 0.8))
    print("  Profile: " .. ColorizeText(profileType, 1, 1, 0.8))
    if playerClass == "HUNTER" then
      local hasPet = UnitExists("pet") and not UnitIsDead("pet")
      print("  Has Pet: " .. ColorizeText(tostring(hasPet), 1, 1, 0.8))
      if hasPet then
        print("  Pet Name: " .. ColorizeText(UnitName("pet") or "Unknown", 1, 1, 0.8))
      end
    end
    local tanks = FindTanks()
    local pendingGuid, pending = GetActiveDelveInspectPending()
    print("  Tanks Found: " .. ColorizeText(tostring(#tanks), 1, 1, 0.8))
    print("  Preferred Tank: " .. ColorizeText(tostring(SARDB.preferredTankName or "None"), 1, 1, 0.8))
    print("  Raid Parity Preference: " .. ColorizeText(tostring(SARDB.preferRaidParityTank), 1, 1, 0.8))
    print("  Delve Inspect Session: " .. ColorizeText(tostring(delveInspectSessionKey or "None"), 1, 1, 0.8))
    print("  Delve Inspect Pending: " .. ColorizeText(tostring(CountTableEntries(delveInspectPendingByGUID)), 1, 1, 0.8))
    print("  Delve Inspect Cached Specs: " .. ColorizeText(tostring(CountTableEntries(delveInspectSpecByGUID)), 1, 1, 0.8))
    print("  Delve Inspect Retries: " .. ColorizeText(tostring(GetDelveInspectRetryCount()), 1, 1, 0.8))
    print("  Delve Inspect Last Target: " .. ColorizeText(tostring(delveInspectLastTargetName or "None"), 1, 1, 0.8))
    print("  Delve Inspect Last Result: " .. ColorizeText(tostring(delveInspectLastResult), 1, 1, 0.8))
    if pendingGuid and pending then
      local pendingAge = GetTime() - (pending.requestedAt or GetTime())
      print("  Active Inspect GUID: " .. ColorizeText(tostring(pendingGuid), 1, 1, 0.8))
      print("  Active Inspect Target: " .. ColorizeText(tostring(pending.unitName or pending.unitId or "Unknown"), 1, 1, 0.8))
      print("  Active Inspect Age: " .. ColorizeText(string.format("%.2fs", pendingAge), 1, 1, 0.8))
    end

    if IsInRaid() then
      local playerSubgroup = GetRaidSubgroupForUnit("player")
      if playerSubgroup then
        local parityLabel = ((playerSubgroup % 2) == 0) and "even" or "odd"
        print("  Player Raid Group: " .. ColorizeText(tostring(playerSubgroup) .. " (" .. parityLabel .. ")", 1, 1, 0.8))
      else
        print("  Player Raid Group: " .. ColorizeText("unknown", 1, 0.8, 0.3))
      end

      if #tanks > 0 then
        print("  Tank Order:")
        for i, tank in ipairs(tanks) do
          local raidIndex = UnitInRaid and UnitInRaid(tank.unitId) or nil
          local tankSubgroup = GetRaidSubgroupForUnit(tank.unitId, raidIndex)
          local subgroupText = tankSubgroup and tostring(tankSubgroup) or "?"
          print("    " .. i .. ". " .. ColorizeText(tank.name, 1, 1, 0.8) .. " (group " .. subgroupText .. ")")
        end
      end
    end
    
    -- Check for Delve companion
    if IsInDelve() then
      local companion = FindDelveCompanion()
      if companion then
        print("  Delve Companion: " .. ColorizeText(companion.name, 1, 1, 0.8))
        print("  Companion Unit ID: " .. ColorizeText(companion.unitId, 1, 1, 0.8))
        local role = UnitGroupRolesAssigned(companion.unitId)
        print("  Companion Role: " .. ColorizeText(role or "none", 1, 1, 0.8))
        
        -- Show if companion will be used
        local willUse = (#tanks == 0) and (playerClass == "ROGUE" or 
                        (playerClass == "HUNTER" and (not UnitExists("pet") or UnitIsDead("pet"))))
        if willUse then
          print("  Will Use Companion: " .. ColorizeText("YES (no player tanks)", 0.3, 1, 0.3))
        else
          if #tanks > 0 then
            print("  Will Use Companion: " .. ColorizeText("NO (player tank available)", 1, 0.8, 0.3))
          else
            print("  Will Use Companion: " .. ColorizeText("NO (conditions not met)", 1, 0.8, 0.3))
          end
        end
      else
        print("  Delve Companion: " .. ColorizeText("Not found", 1, 0.3, 0.3))
      end
    end
    
    -- Check what the macro actually contains
    local macroName = nil
    if playerClass == "ROGUE" then
      macroName = "Dirty Tricks of the Trade"
    elseif playerClass == "HUNTER" then
      macroName = "Dirty Misdirection"
    end
    if macroName then
      local _, _, body = GetMacroInfo(macroName)
      if body then
        print("  Current Macro:")
        for line in body:gmatch("[^\r\n]+") do
          print("    " .. ColorizeText(line, 0.8, 0.8, 1))
        end
      else
        print("  Macro: " .. ColorizeText("Not found", 1, 0.3, 0.3))
      end
    end
  elseif cmd == "help" then
    print(ColorizeText("[Dirty Tricks]", ADDON_COLOR.r, ADDON_COLOR.g, ADDON_COLOR.b) .. " Use " .. ColorizeText("/dirtytricks help", PROFILE_COLOR.r, PROFILE_COLOR.g, PROFILE_COLOR.b) .. " for commands")
  end
end

-- Initialize on load
RequestUpdateMacros(false)
