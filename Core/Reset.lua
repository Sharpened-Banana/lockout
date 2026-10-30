local _, ns = ...

-- Pure expiry logic: stored weekly data is judged against `now`, never mutated.
local Reset = {}
ns.Reset = Reset

function Reset.Absolute(now, seconds)
  if seconds == nil then return nil end
  return now + seconds
end

function Reset.IsExpired(entry, now)
  if entry == nil then return true end
  if entry.resetAt == nil then return false end
  return now >= entry.resetAt
end

function Reset.Active(map, now)
  local out = {}
  for key, entry in pairs(map or {}) do
    if not Reset.IsExpired(entry, now) then out[key] = entry end
  end
  return out
end

function Reset.Vault(vault, now)
  vault = vault or {}
  local stored = vault.activities or {}
  if not Reset.IsExpired(vault, now) then
    return { ready = vault.unclaimed == true, activities = stored }
  end
  local ready = vault.unclaimed == true
  local activities = {}
  for i, a in ipairs(stored) do
    if a.progress and a.threshold and a.progress >= a.threshold then ready = true end
    local copy = {}
    for k, v in pairs(a) do copy[k] = v end
    copy.progress = 0
    copy.rewardIlvl = nil
    activities[i] = copy
  end
  return { ready = ready, activities = activities }
end

function Reset.MythicPlus(mp, now)
  mp = mp or {}
  local out = { rating = mp.rating or 0, seasonBest = mp.seasonBest or {} }
  if Reset.IsExpired(mp, now) then
    out.weeklyBest = 0
    out.runs = {}
  else
    out.key = mp.key
    out.weeklyBest = mp.weeklyBest or 0
    out.runs = mp.runs or {}
  end
  return out
end
