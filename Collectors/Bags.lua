local _, ns = ...

-- Carried bags only (backpack, bags 1-4, reagent bag). Bank and warband bank are never read.
local BAG_NAMES = { "Backpack", "Bag_1", "Bag_2", "Bag_3", "Bag_4", "ReagentBag" }

ns.RegisterCollector({
  name = "Bags",
  events = { "BAG_UPDATE_DELAYED" },
  requires = { "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo" },

  Collect = function(_, record, now)
    local scan = ns.Watchlist.ScanSet(ns.db)
    local counts = {}
    for _, name in ipairs(BAG_NAMES) do
      local bag = Enum.BagIndex[name]
      if bag then
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
          local info = C_Container.GetContainerItemInfo(bag, slot)
          if info and scan[info.itemID] then
            counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
          end
        end
      end
    end
    record.bags = { scannedAt = now, counts = counts }
  end,
})

-- Watchlist edits can add items to the scan set.
ns.On("WATCHLIST_CHANGED", function() ns.Schedule("Bags") end)
