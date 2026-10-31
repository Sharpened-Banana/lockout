local _, ns = ...

local Reset = ns.Reset

ns.RegisterCollector({
  name = "MythicPlus",
  events = { "CHALLENGE_MODE_COMPLETED", "BAG_UPDATE_DELAYED", "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "CHALLENGE_MODE_MAPS_UPDATE" },
  requires = {
    "C_MythicPlus.GetOwnedKeystoneChallengeMapID", "C_MythicPlus.GetOwnedKeystoneLevel",
    "C_MythicPlus.GetRunHistory", "C_PlayerInfo.GetPlayerMythicPlusRatingSummary",
    "C_DateAndTime.GetSecondsUntilWeeklyReset",
  },

  -- Run history and rating are only populated once the client has been asked for map info;
  -- the answer arrives asynchronously as CHALLENGE_MODE_MAPS_UPDATE.
  OnLogin = function()
    if C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
  end,

  Collect = function(_, record, now)
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local key
    if mapID then
      key = { challengeMapID = mapID, level = C_MythicPlus.GetOwnedKeystoneLevel() }
    end

    local runs, weeklyBest = {}, 0
    for _, run in ipairs(C_MythicPlus.GetRunHistory(false, true) or {}) do
      runs[#runs + 1] = { challengeMapID = run.mapChallengeModeID, level = run.level, completed = run.completed }
      -- Like the Great Vault row, every recorded run counts (completed == false means finished over time).
      if run.level and run.level > weeklyBest then weeklyBest = run.level end
    end

    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
    local seasonBest = {}
    for _, run in ipairs(summary and summary.runs or {}) do
      seasonBest[run.challengeModeID] = run.bestRunLevel
    end

    record.mythicPlus = {
      resetAt = Reset.Absolute(now, C_DateAndTime.GetSecondsUntilWeeklyReset()),
      key = key,
      runs = runs,
      weeklyBest = weeklyBest,
      rating = summary and summary.currentSeasonScore or 0,
      seasonBest = seasonBest,
    }
  end,
})
