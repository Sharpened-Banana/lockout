std = "lua51"
max_line_length = false
exclude_files = { "Libs/", ".release/", ".superpowers/" }

globals = {
  "LockoutDB", "SLASH_LOCKOUT1", "SLASH_LOCKOUT2", "SlashCmdList",
  "LockoutMainFrame", "UISpecialFrames", "StaticPopupDialogs",
}

-- WoW API / globals used by the addon (extend as tasks use more).
read_globals = {
  "time", "date", "C_Timer", "CreateFrame", "InCombatLockdown", "Enum",
  "UnitGUID", "UnitName", "UnitClass", "UnitLevel", "GetRealmName",
  "ITEM_UPGRADE_TOOLTIP_FORMAT_STRING",
  -- Season
  "GetBuildInfo", "LE_EXPANSION_LEVEL_CURRENT", "C_ChallengeMode",
  "EJ_GetNumTiers", "EJ_GetTierInfo", "EJ_GetCurrentTier", "EJ_SelectTier",
  "EJ_GetInstanceByIndex", "EJ_GetInstanceInfo", "EJ_GetEncounterInfoByIndex",
}

-- Tests and the mock legitimately define WoW globals and busted-style helpers.
files["tests/"] = {
  std = "+busted",
  globals = { "assert", "describe", "it", "before_each" },
  allow_defined_top = true,
  ignore = { "111", "112", "113", "121", "122" },
}
