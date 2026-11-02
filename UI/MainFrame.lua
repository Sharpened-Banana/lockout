local _, ns = ...

-- Main window: title bar, tab/filter toolbar and the character grid.
local Theme = ns.Theme

local UI = { tabButtons = {}, selectedTab = ns.TabOrder[1] }
ns.UI = UI

local TITLE_H, TOOLBAR_H, PAD = 26, 28, 8
local GRID_TOP, GRID_BOTTOM = TITLE_H + TOOLBAR_H + 4, PAD + 10
local DEFAULT_W, DEFAULT_H = 900, 460
local MIN_W, MIN_H = 740, 320 -- wide enough for five tabs beside the realm toggle and filter
local TAB_W = 86
local EMPTY_SEASON = { raids = {}, dungeons = {}, mplus = {} }

local frame, grid
local filterText = ""

local function settings() return ns.db.settings end

local function saveWindow()
  frame:SetUserPlaced(false) -- settings.window owns the position, not the client layout cache
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  settings().window = {
    point = point, relativePoint = relativePoint, x = x, y = y,
    w = frame:GetWidth(), h = frame:GetHeight(),
  }
end

-- A broken Encounter Journal must not take the window down with it.
local function currentSeason()
  local ok, season = pcall(ns.Season.Get, ns.Season)
  if ok and season then return season end
  ns.LogOnce("ui:season", "season lookup failed: %s", tostring(season))
  return EMPTY_SEASON
end

local function textButton(parent, text, w, h, font)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.label = b:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  b.label:SetPoint("CENTER")
  b.label:SetText(text)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  return b
end

local function styleTab(b, active)
  local c = active and { 1, 1, 1 } or Theme.grey
  b.label:SetTextColor(c[1], c[2], c[3])
  b.underline:SetShown(active)
end

local function onHeaderClick(key)
  local s = settings()
  if s.sortKey == key then
    s.sortDesc = not s.sortDesc
  else
    -- Names read best A→Z; numbers highest first.
    s.sortKey, s.sortDesc = key, key ~= "name"
  end
  UI:Refresh()
end

local function onStarClick(row)
  local favorites = settings().favorites
  favorites[row.guid] = not favorites[row.guid] or nil
  UI:Refresh()
end

-- The detail panel owns the selection while it exists: it sets it on open and clears it on close.
-- Rows that are not characters open the character of the clicked column, if any.
local function onRowClick(row, col)
  if row.heading then return end
  local guid = row.guid or (col and col.guid)
  if not guid then return end
  if ns.Detail then
    ns.Detail:Toggle(guid)
  else
    UI:SetSelected(UI.selectedGuid ~= guid and guid or nil)
  end
end

local function buildTitleBar()
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(TITLE_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() frame:StartMoving() end)
  bar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    saveWindow()
  end)
  UI.titleBar = bar

  local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", PAD + 2, 0)
  title:SetText("Lockout")

  local close = textButton(bar, "x", TITLE_H, TITLE_H)
  close:SetPoint("TOPRIGHT")
  close:SetScript("OnClick", function() frame:Hide() end)

  if ns.Settings then
    local cog = CreateFrame("Button", nil, bar)
    cog:SetSize(16, 16)
    cog:SetPoint("RIGHT", close, "LEFT", -4, 0)
    cog:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    cog:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
    cog:SetScript("OnClick", function() ns.Settings:Open() end)
    UI.cog = cog
  end
end

local function buildToolbar()
  local y = -TITLE_H
  for i, name in ipairs(ns.TabOrder) do
    local b = textButton(frame, ns.Tabs[name].title, TAB_W, TOOLBAR_H, "GameFontHighlightSmall")
    b:SetPoint("TOPLEFT", PAD + (i - 1) * (TAB_W + 4), y)
    local a = Theme.accent
    b.underline = b:CreateTexture(nil, "ARTWORK")
    b.underline:SetColorTexture(a[1], a[2], a[3], 1)
    b.underline:SetPoint("BOTTOMLEFT")
    b.underline:SetPoint("BOTTOMRIGHT")
    b.underline:SetHeight(2)
    b:SetScript("OnClick", function() UI:SelectTab(name) end)
    UI.tabButtons[name] = b
  end

  local filter = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
  Theme.Backdrop(filter, Theme.panel)
  filter:SetSize(140, 20)
  filter:SetPoint("TOPRIGHT", -PAD, y - (TOOLBAR_H - 20) / 2)
  filter:SetAutoFocus(false)
  filter:SetMaxLetters(32)
  filter:SetFontObject(GameFontHighlightSmall)
  filter:SetTextInsets(6, 6, 0, 0)
  local hint = filter:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 6, 0)
  hint:SetText("Filter names")
  filter:SetScript("OnEscapePressed", filter.ClearFocus)
  filter:SetScript("OnEnterPressed", filter.ClearFocus)
  filter:SetScript("OnTextChanged", function(self)
    filterText = self:GetText() or ""
    hint:SetShown(filterText == "")
    UI:Refresh()
  end)
  UI.filter = filter

  local check = CreateFrame("CheckButton", nil, frame, "BackdropTemplate")
  Theme.Backdrop(check, Theme.panel)
  check:SetSize(14, 14)
  local tick = check:CreateTexture(nil, "ARTWORK")
  local a = Theme.accent
  tick:SetColorTexture(a[1], a[2], a[3], 1)
  tick:SetPoint("TOPLEFT", 3, -3)
  tick:SetPoint("BOTTOMRIGHT", -3, 3)
  check:SetCheckedTexture(tick)
  local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", check, "RIGHT", 4, 0)
  text:SetText("Current realm")
  check:SetPoint("RIGHT", filter, "LEFT", -96, 0)
  check:SetHitRectInsets(0, -86, 0, 0) -- the label is clickable too
  check:SetScript("OnClick", function(self)
    settings().currentRealmOnly = self:GetChecked() and true or false
    UI:Refresh()
  end)
  UI.realmCheck = check
end

local function buildGrip()
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    saveWindow()
  end)
  UI.grip = grip
end

local function build()
  local s = settings()
  frame = CreateFrame("Frame", "LockoutMainFrame", UIParent, "BackdropTemplate")
  Theme.Backdrop(frame, Theme.bg)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(MIN_W, MIN_H)

  local w = s.window or {}
  frame:SetSize(math.max(w.w or DEFAULT_W, MIN_W), math.max(w.h or DEFAULT_H, MIN_H))
  local point = w.point or "CENTER"
  frame:SetPoint(point, UIParent, w.relativePoint or point, w.x or 0, w.y or 0)
  table.insert(UISpecialFrames, "LockoutMainFrame")
  UI.frame = frame

  buildTitleBar()
  buildToolbar()
  buildGrip()

  grid = ns.Grid.New(frame)
  grid.frame:SetPoint("TOPLEFT", PAD, -GRID_TOP)
  grid.frame:SetPoint("BOTTOMRIGHT", -PAD, GRID_BOTTOM)
  grid:SetOnHeaderClick(onHeaderClick)
  grid:SetOnStarClick(onStarClick)
  grid:SetOnRowClick(onRowClick)
  UI.grid = grid
end

function UI:Refresh()
  if not frame then return end
  local s = settings()
  frame:SetScale(s.scale or 1)
  for name, b in pairs(self.tabButtons) do styleTab(b, name == self.selectedTab) end
  self.realmCheck:SetChecked(s.currentRealmOnly and true or false)

  local tabName = self.selectedTab
  local tab = ns.Tabs[tabName]
  local ctx = { db = ns.db, season = currentSeason(), settings = s, now = time() }
  local rows = ns.Rows.Build(ns.db, {
    minLevel = s.minLevel, filter = filterText, realmOnly = s.currentRealmOnly, realm = GetRealmName(),
    favorites = s.favorites, sortKey = s.sortKey, sortDesc = s.sortDesc,
  })
  for _, row in ipairs(rows) do row.favorite = s.favorites[row.guid] and true or false end
  ctx.characters = rows
  if tab.Rows then rows = tab.Rows(ctx) end

  grid:SetRowHeader(tab.Rows and (tab.rowHeader or "") or nil)
  grid:SetColumns(tab.Columns(ctx))
  grid:SetRows(rows)
  grid:SetSort(s.sortKey, s.sortDesc)
  grid:SetSelected(self.selectedGuid)
  grid:SetCellProvider(function(row, col)
    local ok, cell = pcall(tab.Cell, tab.Rows and row or row.char, col, ctx)
    if ok and cell then return cell end
    ns.LogOnce("cell:" .. tabName, "%s cell failed: %s", tabName, tostring(cell))
    return { text = ns.Rows.EMPTY }
  end)
  grid:Refresh()
end

-- Highlight a row without rebuilding the grid.
function UI:SetSelected(guid)
  self.selectedGuid = guid
  if grid then
    grid:SetSelected(guid)
    grid:Render()
  end
end

-- OnSizeChanged may not have fired yet on first show: lay out from the current size.
local function ensureLayout()
  if grid.width > 0 and grid.height > 0 then return end
  local w, h = grid.frame:GetSize()
  if not w or w <= 0 or not h or h <= 0 then
    w, h = frame:GetWidth() - 2 * PAD, frame:GetHeight() - GRID_TOP - GRID_BOTTOM
  end
  grid:Layout(w, h)
end

function UI:SelectTab(name)
  if not ns.Tabs[name] then return end
  self.selectedTab = name
  self:Refresh()
end

function UI:Show()
  if not frame then build() end
  frame:Show()
  ensureLayout()
  self:Refresh()
end

function UI:Toggle()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    self:Show()
  end
end

ns.On("DATA_UPDATED", function()
  if frame and frame:IsShown() then UI:Refresh() end
end)

ns.RegisterSlash("", function() UI:Toggle() end)
