local _, ns = ...

local Reset = ns.Reset

-- Dungeon-finder holiday bosses (Headless Horseman, Coren Direbrew, ...). No IDs are kept here:
-- what the dungeon finder offers decides what's live. Rewards are the first kill of each day,
-- which resets with the daily reset.

-- GetLFGDungeonInfo typeID of a random-queue entry. Every Random Timewalking Dungeon carries the
-- holiday flag too, and the 18th return (isTimeWalker) is false for them on 12.0.7.
local TYPEID_RANDOM = 6

-- The dungeon finder's own rule for showing an entry: inactive events are hidden.
local function isOffered(dungeonID)
  local _, availableForPlayer, hideIfNotJoinable = IsLFGDungeonJoinable(dungeonID)
  return availableForPlayer or not hideIfNotJoinable
end

ns.RegisterCollector({
  name = "Holidays",
  events = { "LFG_UPDATE_RANDOM_INFO", "LFG_COMPLETION_REWARD" },
  requires = {
    "GetNumRandomDungeons", "GetLFGRandomDungeonInfo", "GetLFGDungeonInfo", "IsLFGDungeonJoinable",
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
        infoName = info[1]
        isHoliday = info[15] and info[2] ~= TYPEID_RANDOM and isOffered(dungeonID)
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
