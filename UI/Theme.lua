local _, ns = ...

-- Dark flat look shared by every Lockout frame. Colors are {r, g, b[, a]}.
local Theme = {
  bg = { 0.07, 0.07, 0.09, 0.95 },
  panel = { 0.11, 0.11, 0.14, 1 },
  border = { 0.2, 0.2, 0.25, 1 },
  accent = { 0.2, 0.6, 1 },
  green = { 0.3, 0.85, 0.4 },
  yellow = { 1, 0.82, 0.2 },
  grey = { 0.5, 0.5, 0.5 },
  ROW_H = 22,
  HEADER_H = 24,
  NAME_W = 190,
}
ns.Theme = Theme

Theme.TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Status markers as texture markup: the UI fonts have no dingbat or emoji glyphs.
Theme.Icon = {
  check = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t",
  vault = "|TInterface\\Icons\\INV_Misc_Bag_10:14|t",
  socket = "|TInterface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic:12|t",
}

local BACKDROP = { bgFile = Theme.TEXTURE, edgeFile = Theme.TEXTURE, edgeSize = 1 }

-- Flat fill with a 1px border. `frame` must be created with "BackdropTemplate".
function Theme.Backdrop(frame, color)
  local c = color or Theme.panel
  frame:SetBackdrop(BACKDROP)
  frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
  local b = Theme.border
  frame:SetBackdropBorderColor(b[1], b[2], b[3], b[4] or 1)
end

-- Class color for a class file token ("MAGE"), white when unknown.
function Theme.ClassColor(classFile)
  local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end
