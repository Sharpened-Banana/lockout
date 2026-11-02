local _, ns = ...

local Reset = ns.Reset

-- Quest-flagged bosses reset with the weekly reset.
local function questKills(list, now, weekly)
  local kills = {}
  for _, boss in ipairs(list) do
    if C_QuestLog.IsQuestFlaggedCompleted(boss.questID) then
      kills[boss.key] = { name = boss.name, resetAt = Reset.Absolute(now, weekly) }
    end
  end
  return kills
end

ns.RegisterCollector({
  name = "WorldBosses",
  events = { "UPDATE_INSTANCE_INFO", "QUEST_TURNED_IN" },
  requires = { "C_QuestLog.IsQuestFlaggedCompleted", "C_DateAndTime.GetSecondsUntilWeeklyReset" },

  Collect = function(_, record, now)
    local bosses = {}

    -- Saved-instance list, when this client exposes world bosses there.
    if GetNumSavedWorldBosses and GetSavedWorldBossInfo then
      for i = 1, GetNumSavedWorldBosses() do
        local name, worldBossID, reset = GetSavedWorldBossInfo(i)
        if worldBossID then
          bosses["wb" .. worldBossID] = { name = name, resetAt = Reset.Absolute(now, reset) }
        end
      end
    end

    local weekly = C_DateAndTime.GetSecondsUntilWeeklyReset()
    for key, kill in pairs(questKills(ns.Content.WORLD_BOSSES, now, weekly)) do
      bosses[key] = kill
    end

    record.worldBosses = bosses
    record.legacyBosses = questKills(ns.Content.LEGACY_WORLD_BOSSES, now, weekly)
  end,
})
