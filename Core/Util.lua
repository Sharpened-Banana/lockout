local _, ns = ...

local Util = {}
ns.Util = Util

local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"

-- Turn a printf-style Blizzard format string into an anchored capture pattern.
function Util.FormatToPattern(fmt)
  local out, i, n = { "^" }, 1, #fmt
  while i <= n do
    local c = fmt:sub(i, i)
    if c == "%" then
      local nxt = fmt:sub(i + 1, i + 1)
      if nxt == "s" then
        out[#out + 1] = "(.-)"
        i = i + 2
      elseif nxt == "d" then
        out[#out + 1] = "(%d+)"
        i = i + 2
      elseif nxt == "%" then
        out[#out + 1] = "%%"
        i = i + 2
      else
        out[#out + 1] = "%%" -- stray "%": literal percent
        i = i + 1
      end
    else
      out[#out + 1] = c:match(MAGIC) and ("%" .. c) or c
      i = i + 1
    end
  end
  out[#out + 1] = "$"
  return table.concat(out)
end

-- item:itemID:enchantID:gem1:gem2:gem3:gem4:... -> numbers, empty fields as 0.
function Util.ParseItemLink(link)
  if type(link) ~= "string" then return nil end
  local body = link:match("item:([^|]*)")
  if not body then return nil end
  local fields = {}
  for field in (body .. ":"):gmatch("([^:]*):") do
    fields[#fields + 1] = tonumber(field) or 0
    if #fields == 6 then break end
  end
  return {
    itemID = fields[1] or 0,
    enchantID = fields[2] or 0,
    gems = { fields[3] or 0, fields[4] or 0, fields[5] or 0, fields[6] or 0 },
  }
end

function Util.Age(seconds)
  if seconds < 60 then return "just now" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
  return math.floor(seconds / 86400) .. "d ago"
end
