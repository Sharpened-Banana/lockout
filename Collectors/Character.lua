local _, ns = ...

-- Spec API moved to C_SpecializationInfo; fall back to the old globals, nil when neither exists.
local function currentSpecID()
  local csi = C_SpecializationInfo
  local getSpec = csi and csi.GetSpecialization or GetSpecialization
  local getInfo = csi and csi.GetSpecializationInfo or GetSpecializationInfo
  local specIndex = getSpec and getSpec()
  if not specIndex or not getInfo then return nil end
  return (getInfo(specIndex))
end

ns.RegisterCollector({
  name = "Character",
  events = { "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_MONEY", "PLAYER_EQUIPMENT_CHANGED" },

  Collect = function(_, record, now)
    local ilvl, ilvlEquipped = GetAverageItemLevel()
    record.meta = {
      name = UnitName("player"),
      realm = GetRealmName(),
      classFile = select(2, UnitClass("player")),
      level = UnitLevel("player"),
      specID = currentSpecID(),
      ilvl = math.floor(ilvl or 0),
      ilvlEquipped = math.floor(ilvlEquipped or 0),
      gold = GetMoney(),
      lastSeen = now,
    }
  end,
})
