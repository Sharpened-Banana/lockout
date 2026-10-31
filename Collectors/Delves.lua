local _, ns = ...

-- Currency quantities do not expire; the UI shows how old the snapshot is.
ns.RegisterCollector({
  name = "Delves",
  events = { "CURRENCY_DISPLAY_UPDATE" },
  requires = { "C_CurrencyInfo.GetCurrencyInfo" },

  Collect = function(_, record, now)
    local currencies = {}
    for _, currency in ipairs(ns.Content.DELVE_CURRENCIES) do
      local info = C_CurrencyInfo.GetCurrencyInfo(currency.id)
      if info then currencies[currency.id] = info.quantity end
    end
    record.delves = { updatedAt = now, currencies = currencies }
  end,
})
