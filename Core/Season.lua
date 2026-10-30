local _, ns = ...

local Season = {}
ns.Season = Season

local function listInstances(isRaid, expansionName)
  local out = {}
  local i = 1
  while true do
    local journalID, name = EJ_GetInstanceByIndex(i, isRaid)
    if not journalID then break end
    -- The expansion-named entry is the world-boss pseudo-instance.
    if name ~= expansionName then
      local mapID = select(10, EJ_GetInstanceInfo(journalID))
      local bosses = 0
      while EJ_GetEncounterInfoByIndex(bosses + 1, journalID) do bosses = bosses + 1 end
      out[#out + 1] = { mapID = mapID, name = name, bosses = bosses }
    end
    i = i + 1
  end
  return out
end

local function build()
  local result = { raids = {}, dungeons = {}, mplus = {} }

  local expansionName = _G["EXPANSION_NAME" .. tostring(LE_EXPANSION_LEVEL_CURRENT)]
  local tier
  for i = 1, EJ_GetNumTiers() do
    if EJ_GetTierInfo(i) == expansionName then
      tier = i
      break
    end
  end

  if tier then
    local original = EJ_GetCurrentTier()
    EJ_SelectTier(tier)
    local ok, err = pcall(function()
      result.raids = listInstances(true, expansionName)
      result.dungeons = listInstances(false, expansionName)
    end)
    EJ_SelectTier(original)
    if not ok then error(err, 0) end
  end

  for _, challengeMapID in ipairs(C_ChallengeMode.GetMapTable() or {}) do
    local name, _, _, _, _, mapID = C_ChallengeMode.GetMapUIInfo(challengeMapID)
    if name then
      result.mplus[#result.mplus + 1] = { challengeMapID = challengeMapID, mapID = mapID, name = name }
    end
  end

  local seen = {}
  for _, d in ipairs(result.dungeons) do seen[d.mapID] = true end
  for _, m in ipairs(result.mplus) do
    if not seen[m.mapID] then
      seen[m.mapID] = true
      result.dungeons[#result.dungeons + 1] = { mapID = m.mapID, name = m.name }
    end
  end
  return result
end

-- Current-season columns, cached in ns.db.season per game build.
function Season.Get()
  local buildNumber = select(4, GetBuildInfo())
  local cache = ns.db.season
  if cache and cache.build == buildNumber and (#cache.raids > 0 or #cache.dungeons > 0) then
    return cache
  end
  local result = build()
  result.build = buildNumber
  ns.db.season = result
  return result
end
