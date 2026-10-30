local _, ns = ...

ns.RegisterCollector({
  name = "Character",
  events = { "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_MONEY", "PLAYER_EQUIPMENT_CHANGED" },

  Collect = function(_, record, now)
    local ilvl, ilvlEquipped = GetAverageItemLevel()
    local specIndex = GetSpecialization()
    record.meta = {
      name = UnitName("player"),
      realm = GetRealmName(),
      classFile = select(2, UnitClass("player")),
      level = UnitLevel("player"),
      specID = specIndex and GetSpecializationInfo(specIndex) or nil,
      ilvl = math.floor(ilvl or 0),
      ilvlEquipped = math.floor(ilvlEquipped or 0),
      gold = GetMoney(),
      lastSeen = now,
    }
  end,
})
