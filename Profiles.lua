--[[
================================================================================
Dirty Tricks - Profiles Module
================================================================================
Default profiles for addon behavior (future expansion).
Currently unused but reserved for per-character or per-spec customization.

Copyright (c) 2026 Dirty Tricks
Licensed under the MIT License. See LICENSE for full text.
================================================================================
--]]

-- Structure:
-- SARProfiles[class] = { solo = {...}, party = {...}, raid = {...} }

SARProfiles = SARProfiles or {}

SARProfiles.ROGUE = {
  solo = {
    preferRole = false,
    preferMainTank = false,
    preferredNames = {},
  },
  party = {
    preferRole = true,
    preferMainTank = true,
    preferredNames = {},
  },
  raid = {
    preferRole = true,
    preferMainTank = true,
    preferredNames = {},
  },
}

SARProfiles.HUNTER = {
  solo = {
    preferRole = false,
    preferMainTank = false,
    preferredNames = {},
  },
  party = {
    preferRole = true,
    preferMainTank = true,
    preferredNames = {},
  },
  raid = {
    preferRole = true,
    preferMainTank = true,
    preferredNames = {},
  },
}

-- Helper: get profile for current class and group state
function SAR_GetProfileFor(class)
  local pclass = class or select(2, UnitClass("player"))
  local profiles = SARProfiles[pclass]
  if not profiles then return nil end
  if IsInRaid() then return profiles.raid end
  if IsInGroup() then return profiles.party end
  return profiles.solo
end
