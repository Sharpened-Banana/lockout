local _, ns = ...

local Reset = ns.Reset

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

    -- Quest-flagged bosses reset with the weekly reset.
    local weekly = C_DateAndTime.GetSecondsUntilWeeklyReset()
    for _, boss in ipairs(ns.Content.WORLD_BOSSES) do
      if C_QuestLog.IsQuestFlaggedCompleted(boss.questID) then
        bosses[boss.key] = { name = boss.name, resetAt = Reset.Absolute(now, weekly) }
      end
    end

    record.worldBosses = bosses
  end,
})
