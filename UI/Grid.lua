local _, ns = ...

-- Generic character grid: a frozen name column on the left, data columns in a horizontal
-- ScrollFrame, and a fixed pool of row frames recycled by a vertical scroll offset.
local Theme = ns.Theme
local ROW_H, HEADER_H, NAME_W = Theme.ROW_H, Theme.HEADER_H, Theme.NAME_W

local BAR = 8          -- scroll bar thickness
local EDGE = 1         -- backdrop border, kept clear of children
local LEVEL_W, ILVL_W = 30, 40
local WHEEL_ROWS = 3   -- rows per wheel notch
local WHEEL_PX = 60    -- pixels per shift+wheel notch
local DEFAULT_COL_W = 80
local STAR_ATLAS = "auctionhouse-icon-favorite"
local SORT_ARROW = "Interface\\Buttons\\UI-SortArrow"
local WHITE = { 1, 1, 1 }
local TEXT = { 0.9, 0.9, 0.9 }

local Grid = {}
Grid.__index = Grid
ns.Grid = Grid

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function fill(parent, layer, c, alpha)
  local t = parent:CreateTexture(nil, layer)
  t:SetAllPoints()
  t:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
  return t
end

local function label(parent, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function newBar(parent, orientation)
  local bar = CreateFrame("Slider", nil, parent, "BackdropTemplate")
  Theme.Backdrop(bar, Theme.bg)
  bar:SetOrientation(orientation)
  bar:SetValueStep(1)
  bar:SetObeyStepOnDrag(true)
  local thumb = bar:CreateTexture(nil, "OVERLAY")
  local a = Theme.accent
  thumb:SetColorTexture(a[1], a[2], a[3], 0.6)
  if orientation == "VERTICAL" then thumb:SetSize(BAR, 40) else thumb:SetSize(40, BAR) end
  bar:SetThumbTexture(thumb)
  bar:SetMinMaxValues(0, 0)
  bar:SetValue(0)
  return bar
end

local function showTooltip(owner, title, lines)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(title or "", 1, 1, 1)
  for _, line in ipairs(lines or {}) do
    local c = line.color or TEXT
    if line.right then
      GameTooltip:AddDoubleLine(line.left or "", line.right, c[1], c[2], c[3], 1, 1, 1)
    else
      GameTooltip:AddLine(line.left or "", c[1], c[2], c[3], true)
    end
  end
  GameTooltip:Show()
end

local function hideTooltip() GameTooltip:Hide() end

-- Row background layers: zebra stripe, selection and hover tint.
local function decorate(frame)
  local a = Theme.accent
  local deco = {
    zebra = fill(frame, "BACKGROUND", WHITE, 0.03),
    selected = fill(frame, "BORDER", a, 0.25),
    hover = fill(frame, "ARTWORK", a, 0.12),
  }
  deco.hover:Hide()
  return deco
end

local function setHover(slot, on)
  slot.left.deco.hover:SetShown(on)
  slot.right.deco.hover:SetShown(on)
end

local function rowClicked(grid, slot)
  if slot.row and grid.onRowClick then grid.onRowClick(slot.row) end
end

local function hoverScripts(frame, slot)
  frame:SetScript("OnEnter", function() setHover(slot, true) end)
  frame:SetScript("OnLeave", function() setHover(slot, false) end)
end

-- Sort header; the arrow sits on the side away from the text.
local function headerButton(grid, parent, key, text, justify, inset)
  local b = CreateFrame("Button", nil, parent)
  b.label = label(b, justify)
  b.label:SetText(text)
  b.arrow = b:CreateTexture(nil, "OVERLAY")
  b.arrow:SetTexture(SORT_ARROW)
  b.arrow:SetSize(9, 8)
  if justify == "LEFT" then
    b.label:SetPoint("LEFT", inset, 0)
    b.label:SetPoint("RIGHT", -12, 0)
    b.arrow:SetPoint("RIGHT", -2, 0)
  else
    b.label:SetPoint("LEFT", 12, 0)
    b.label:SetPoint("RIGHT", -inset, 0)
    b.arrow:SetPoint("LEFT", 2, 0)
  end
  fill(b, "HIGHLIGHT", WHITE, 0.06)
  b:SetScript("OnClick", function()
    if grid.onHeaderClick then grid.onHeaderClick(key) end
  end)
  return b
end

local function newSlot(grid, i)
  local slot = { cells = {} }
  local y = -(i - 1) * ROW_H

  local left = CreateFrame("Button", nil, grid.frozenBody)
  left:SetSize(NAME_W, ROW_H)
  left:SetPoint("TOPLEFT", 0, y)
  left.deco = decorate(left)
  left:SetScript("OnClick", function() rowClicked(grid, slot) end)
  hoverScripts(left, slot)
  slot.left = left

  local star = CreateFrame("Button", nil, left)
  star:SetSize(14, 14)
  star:SetPoint("LEFT", 4, 0)
  star.icon = star:CreateTexture(nil, "ARTWORK")
  star.icon:SetAllPoints()
  star.icon:SetAtlas(STAR_ATLAS)
  star:SetScript("OnClick", function()
    if slot.row and grid.onStarClick then grid.onStarClick(slot.row) end
  end)
  hoverScripts(star, slot)
  slot.star = star

  slot.name = label(left, "LEFT")
  slot.name:SetPoint("LEFT", 22, 0)
  slot.name:SetPoint("RIGHT", -(LEVEL_W + ILVL_W), 0)
  slot.level = label(left, "RIGHT")
  slot.level:SetWidth(LEVEL_W - 4)
  slot.level:SetPoint("RIGHT", -ILVL_W, 0)
  slot.ilvl = label(left, "RIGHT")
  slot.ilvl:SetWidth(ILVL_W - 6)
  slot.ilvl:SetPoint("RIGHT", -6, 0)

  local right = CreateFrame("Frame", nil, grid.content)
  right:SetHeight(ROW_H)
  right:SetPoint("TOPLEFT", 0, y - HEADER_H)
  right.deco = decorate(right)
  slot.right = right
  return slot
end

local function cellButton(grid, slot)
  local b = CreateFrame("Button", nil, slot.right)
  b.text = label(b, "LEFT")
  b.text:SetPoint("LEFT", 6, 0)
  b.text:SetPoint("RIGHT", -6, 0)
  b:SetScript("OnEnter", function(self)
    setHover(slot, true)
    if self.tooltip then showTooltip(self, self.title, self.tooltip) end
  end)
  b:SetScript("OnLeave", function()
    setHover(slot, false)
    hideTooltip()
  end)
  b:SetScript("OnClick", function() rowClicked(grid, slot) end)
  return b
end

local function dataHeader(grid)
  local b = CreateFrame("Button", nil, grid.content)
  b.label = label(b, "LEFT")
  b.label:SetPoint("LEFT", 6, 0)
  b.label:SetPoint("RIGHT", -6, 0)
  b:SetScript("OnEnter", function(self) showTooltip(self, self.label:GetText()) end)
  b:SetScript("OnLeave", hideTooltip)
  return b
end

function Grid.New(parent)
  local self = setmetatable({
    columns = {}, rows = {}, slots = {}, dataHeaders = {}, colX = {},
    offset = 0, maxOffset = 0, hoffset = 0, maxHOffset = 0,
    width = 0, height = 0, bodyHeight = 0, needed = 0,
  }, Grid)

  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  Theme.Backdrop(f, Theme.panel)
  self.frame = f

  -- Frozen name column.
  local frozen = CreateFrame("Frame", nil, f)
  frozen:SetPoint("TOPLEFT", EDGE, -EDGE)
  frozen:SetPoint("BOTTOMLEFT", EDGE, BAR + EDGE)
  frozen:SetWidth(NAME_W)
  local divider = frozen:CreateTexture(nil, "OVERLAY")
  divider:SetColorTexture(unpack(Theme.border))
  divider:SetPoint("TOPRIGHT")
  divider:SetPoint("BOTTOMRIGHT")
  divider:SetWidth(1)

  local head = CreateFrame("Frame", nil, frozen)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:SetHeight(HEADER_H)
  fill(head, "BACKGROUND", Theme.bg)
  -- Header text lines up with the row text below it.
  self.headers = {
    name = headerButton(self, head, "name", "Character", "LEFT", 4),
    level = headerButton(self, head, "level", "Lvl", "RIGHT", 0),
    ilvl = headerButton(self, head, "ilvl", "iLvl", "RIGHT", 6),
  }
  self.headers.name:SetSize(NAME_W - 18 - LEVEL_W - ILVL_W, HEADER_H)
  self.headers.name:SetPoint("TOPLEFT", 18, 0)
  self.headers.level:SetSize(LEVEL_W, HEADER_H)
  self.headers.level:SetPoint("TOPRIGHT", -ILVL_W, 0)
  self.headers.ilvl:SetSize(ILVL_W, HEADER_H)
  self.headers.ilvl:SetPoint("TOPRIGHT", 0, 0)

  local body = CreateFrame("Frame", nil, frozen)
  body:SetPoint("TOPLEFT", 0, -HEADER_H)
  body:SetPoint("BOTTOMRIGHT")
  body:SetClipsChildren(true)
  self.frozenBody = body

  -- Horizontally scrolling data columns (header row included).
  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", NAME_W + EDGE, -EDGE)
  scroll:SetPoint("BOTTOMRIGHT", -(BAR + EDGE), BAR + EDGE)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  local headBg = content:CreateTexture(nil, "BACKGROUND")
  headBg:SetColorTexture(unpack(Theme.bg))
  headBg:SetPoint("TOPLEFT")
  headBg:SetPoint("TOPRIGHT")
  headBg:SetHeight(HEADER_H)
  self.scroll, self.content = scroll, content

  self.vbar = newBar(f, "VERTICAL")
  self.vbar:SetPoint("TOPRIGHT", -EDGE, -(HEADER_H + EDGE))
  self.vbar:SetPoint("BOTTOMRIGHT", -EDGE, BAR + EDGE)
  self.vbar:SetWidth(BAR)
  self.vbar:SetScript("OnValueChanged", function(_, v) self:ScrollTo(v) end)

  self.hbar = newBar(f, "HORIZONTAL")
  self.hbar:SetPoint("BOTTOMLEFT", NAME_W + EDGE, EDGE)
  self.hbar:SetPoint("BOTTOMRIGHT", -(BAR + EDGE), EDGE)
  self.hbar:SetHeight(BAR)
  self.hbar:SetScript("OnValueChanged", function(_, v) self:ScrollHorizontal(v) end)

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    if IsShiftKeyDown() then
      self:ScrollHorizontal(self.hoffset - delta * WHEEL_PX)
    else
      self:ScrollTo(self.offset - delta * WHEEL_ROWS)
    end
  end)
  f:SetScript("OnSizeChanged", function(_, w, h) self:Layout(w, h) end)
  return self
end

-- Columns {key, label, width}; a different key set scrolls back to the first column.
function Grid:SetColumns(cols)
  local keys = {}
  for i, col in ipairs(cols) do keys[i] = tostring(col.key) end
  local signature = table.concat(keys, "\1")
  if signature ~= self.signature then
    self.signature = signature
    self.hoffset = 0
  end
  self.columns = cols
end

function Grid:SetRows(rows) self.rows = rows end
function Grid:SetCellProvider(fn) self.cellProvider = fn end
function Grid:SetOnRowClick(fn) self.onRowClick = fn end
function Grid:SetOnHeaderClick(fn) self.onHeaderClick = fn end
function Grid:SetOnStarClick(fn) self.onStarClick = fn end
function Grid:SetSelected(guid) self.selected = guid end

function Grid:SetSort(key, desc)
  self.sortKey, self.sortDesc = key, desc
end

-- Size of the grid frame changed: grow the row pool to ceil(body / ROW_H) + 1 and redraw.
function Grid:Layout(w, h)
  self.width, self.height = w or 0, h or 0
  self.bodyHeight = math.max(0, self.height - 2 * EDGE - HEADER_H - BAR)
  self.needed = math.ceil(self.bodyHeight / ROW_H) + 1
  for i = #self.slots + 1, self.needed do self.slots[i] = newSlot(self, i) end
  self:Refresh()
end

function Grid:ScrollTo(offset)
  offset = clamp(math.floor(offset + 0.5), 0, self.maxOffset)
  if offset == self.offset then return end
  self.offset = offset
  self.vbar:SetValue(offset)
  self:Render()
end

function Grid:ScrollHorizontal(x)
  x = clamp(math.floor(x + 0.5), 0, self.maxHOffset)
  if x == self.hoffset then return end
  self.hoffset = x
  self.hbar:SetValue(x)
  self.scroll:SetHorizontalScroll(x)
end

local function layoutHeaders(self)
  local accent = Theme.accent
  for key, b in pairs(self.headers) do
    local active = key == self.sortKey
    local c = active and accent or Theme.grey
    b.label:SetTextColor(c[1], c[2], c[3])
    b.arrow:SetShown(active)
    if self.sortDesc then b.arrow:SetTexCoord(0, 0.5625, 0, 1) else b.arrow:SetTexCoord(0, 0.5625, 1, 0) end
  end

  for j, col in ipairs(self.columns) do
    local b = self.dataHeaders[j] or dataHeader(self)
    self.dataHeaders[j] = b
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.colX[j], 0)
    b:SetSize(col.width or DEFAULT_COL_W, HEADER_H)
    b.label:SetText(col.label or "")
    b.label:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    b:Show()
  end
  for j = #self.columns + 1, #self.dataHeaders do self.dataHeaders[j]:Hide() end
end

-- Recompute scroll ranges and column positions, then redraw.
function Grid:Refresh()
  self.maxOffset = math.max(0, #self.rows - math.floor(self.bodyHeight / ROW_H))
  self.offset = clamp(self.offset, 0, self.maxOffset)
  self.vbar:SetMinMaxValues(0, self.maxOffset)
  self.vbar:SetValue(self.offset)
  self.vbar:SetShown(self.maxOffset > 0)

  local x = 0
  self.colX = {}
  for j, col in ipairs(self.columns) do
    self.colX[j] = x
    x = x + (col.width or DEFAULT_COL_W)
  end
  local view = math.max(0, self.width - 2 * EDGE - NAME_W - BAR)
  self.maxHOffset = math.max(0, x - view)
  self.hoffset = clamp(self.hoffset, 0, self.maxHOffset)
  self.hbar:SetMinMaxValues(0, self.maxHOffset)
  self.hbar:SetValue(self.hoffset)
  self.hbar:SetShown(self.maxHOffset > 0)

  local contentW = math.max(x, view, 1)
  self.content:SetSize(contentW, HEADER_H + self.bodyHeight)
  self.scroll:SetHorizontalScroll(self.hoffset)
  for _, slot in ipairs(self.slots) do slot.right:SetWidth(contentW) end

  layoutHeaders(self)
  self:Render()
end

local function fillSlot(self, slot, row, index)
  local empty = ns.Rows.EMPTY
  local meta = row.char and row.char.meta or {}
  local even = index % 2 == 0
  local selected = row.guid == self.selected
  for _, part in ipairs({ slot.left, slot.right }) do
    part.deco.zebra:SetShown(even)
    part.deco.selected:SetShown(selected)
  end

  slot.star.icon:SetDesaturated(not row.favorite)
  slot.star.icon:SetAlpha(row.favorite and 1 or 0.25)
  slot.name:SetText(row.label ~= "" and row.label or "?")
  slot.name:SetTextColor(Theme.ClassColor(meta.classFile))
  slot.level:SetText(meta.level and tostring(meta.level) or empty)
  slot.level:SetTextColor(unpack(Theme.grey))
  slot.ilvl:SetText(meta.ilvl and tostring(math.floor(meta.ilvl)) or empty)

  for j, col in ipairs(self.columns) do
    local b = slot.cells[j] or cellButton(self, slot)
    slot.cells[j] = b
    local cell = self.cellProvider and self.cellProvider(row, col) or {}
    local text = cell.text or empty
    local c = cell.color or (text == empty and Theme.grey) or TEXT
    b.text:SetText(text)
    b.text:SetTextColor(c[1], c[2], c[3])
    b.tooltip, b.title = cell.tooltip, col.label
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.colX[j], 0)
    b:SetSize(col.width or DEFAULT_COL_W, ROW_H)
    b:Show()
  end
  for j = #self.columns + 1, #slot.cells do slot.cells[j]:Hide() end
end

-- Fill the pooled row frames from rows[offset + 1 ...].
function Grid:Render()
  for i, slot in ipairs(self.slots) do
    local index = self.offset + i
    local row = i <= self.needed and self.rows[index] or nil
    slot.row = row
    slot.left:SetShown(row ~= nil)
    slot.right:SetShown(row ~= nil)
    if row then fillSlot(self, slot, row, index) end
  end
end
