local _, ns = ...

-- Curated default consumables for the current expansion (all quality ranks).
-- IDs must come from Wowhead/wago.tools for the live patch, with `-- Name (rank N)` comments.
local Consumables = {
  CATEGORIES = { "Flasks", "Potions", "Food", "Runes", "Oils" },

  -- [itemID] = category
  items = {
    -- needs IDs
  },
}
ns.Consumables = Consumables

function Consumables.CategoryOf(itemID)
  return Consumables.items[itemID] or "Other"
end
