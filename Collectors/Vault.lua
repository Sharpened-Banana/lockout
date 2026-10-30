local _, ns = ...

local Reset = ns.Reset

ns.RegisterCollector({
  name = "Vault",
  events = { "WEEKLY_REWARDS_UPDATE" },
  requires = {
    "C_WeeklyRewards.GetActivities", "C_WeeklyRewards.HasAvailableRewards",
    "C_DateAndTime.GetSecondsUntilWeeklyReset",
  },

  Collect = function(_, record, now)
    local types = Enum.WeeklyRewardChestThresholdType
    local wanted = { [types.Raid] = true, [types.Activities] = true, [types.World] = true }

    local list = {}
    for _, a in ipairs(C_WeeklyRewards.GetActivities() or {}) do
      if wanted[a.type] then
        local entry = { type = a.type, index = a.index, threshold = a.threshold, progress = a.progress, level = a.level }
        if a.progress >= a.threshold and C_WeeklyRewards.GetExampleRewardItemHyperlinks and C_Item then
          local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(a.id)
          if link then entry.rewardIlvl = C_Item.GetDetailedItemLevelInfo(link) end
        end
        list[#list + 1] = entry
      end
    end
    table.sort(list, function(a, b)
      if a.type ~= b.type then return a.type < b.type end
      return a.index < b.index
    end)

    record.vault = {
      resetAt = Reset.Absolute(now, C_DateAndTime.GetSecondsUntilWeeklyReset()),
      unclaimed = C_WeeklyRewards.HasAvailableRewards() and true or false,
      activities = list,
    }
  end,
})
