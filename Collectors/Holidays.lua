local _, ns = ...

local Reset = ns.Reset

-- Dungeon-finder holiday bosses (Headless Horseman, Coren Direbrew, ...). The game lists a
-- holiday dungeon only while its event is live, so no IDs are kept here. Rewards are the
-- first kill of each day, which resets with the daily reset.
ns.RegisterCollector({
  name = "Holidays",
  events = { "LFG_UPDATE_RANDOM_INFO", "LFG_COMPLETION_REWARD" },
  requires = {
    "GetNumRandomDungeons", "GetLFGRandomDungeonInfo", "GetLFGDungeonInfo",
    "GetLFGDungeonRewards", "RequestLFDPlayerLockInfo", "C_DateAndTime.GetSecondsUntilDailyReset",
  },

  OnLogin = function() RequestLFDPlayerLockInfo() end,

  -- A reward just landed; ask again so the next LFG_UPDATE_RANDOM_INFO carries doneToday.
  OnEvent = function(event)
    if event == "LFG_COMPLETION_REWARD" then RequestLFDPlayerLockInfo() end
  end,

  Collect = function(_, record, now)
    local resetAt = Reset.Absolute(now, C_DateAndTime.GetSecondsUntilDailyReset())
    local active, done = {}, {}

    for i = 1, GetNumRandomDungeons() do
      local dungeonID, listName = GetLFGRandomDungeonInfo(i)
      -- GetLFGDungeonInfo returns nothing until the dungeon data has loaded.
      local infoName, isHoliday = nil, nil
      if dungeonID then
        local info = { GetLFGDungeonInfo(dungeonID) }
        -- Random Timewalking also carries the holiday flag (it runs as a calendar event);
        -- isTimeWalker, the 18th return, tells it apart.
        infoName, isHoliday = info[1], info[15] and not info[18]
      end
      if isHoliday then
        local name = listName or infoName
        active[dungeonID] = { name = name, resetAt = resetAt }
        if GetLFGDungeonRewards(dungeonID) then
          done[dungeonID] = { name = name, resetAt = resetAt }
        end
      end
    end

    record.holidays = { active = active, done = done }
  end,
})
