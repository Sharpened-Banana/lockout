local _, ns = ...

local Reset = ns.Reset

ns.RegisterCollector({
  name = "Instances",
  events = { "UPDATE_INSTANCE_INFO", "BOSS_KILL", "ENCOUNTER_END" },
  requires = { "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo", "RequestRaidInfo" },

  OnLogin = function() RequestRaidInfo() end,

  -- Kills only show up in the saved-instance data after a fresh request.
  OnEvent = function(event)
    if event == "BOSS_KILL" or event == "ENCOUNTER_END" then RequestRaidInfo() end
  end,

  Collect = function(_, record, now)
    local instances = {}
    for i = 1, GetNumSavedInstances() do
      local name, _, reset, difficultyID, locked, extended, _, isRaid, _, difficultyName,
        numEncounters, encounterProgress, _, mapID = GetSavedInstanceInfo(i)
      if (locked or extended) and mapID then
        local encounters = {}
        for e = 1, numEncounters or 0 do
          local bossName, _, killed = GetSavedInstanceEncounterInfo(i, e)
          encounters[e] = { name = bossName, killed = killed and true or false }
        end
        instances[mapID .. ":" .. difficultyID] = {
          name = name,
          mapID = mapID,
          difficultyID = difficultyID,
          difficultyName = difficultyName,
          isRaid = isRaid and true or false,
          resetAt = Reset.Absolute(now, reset),
          extended = extended and true or false,
          killed = encounterProgress,
          total = numEncounters,
          encounters = encounters,
        }
      end
    end
    record.instances = instances
  end,
})
