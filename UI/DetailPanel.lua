local _, ns = ...

-- Per-character panel docked to the right of the main window: header, equipment,
-- consumables (with watchlist editing), this week's summary and Forget.
local Theme, Content, Reset, Util, Watchlist = ns.Theme, ns.Content, ns.Reset, ns.Util, ns.Watchlist

local Detail = { editing = false, pools = {} }
ns.Detail = Detail

local PANEL_W, PAD, HEADER_H = 320, 10, 64
local INNER_W = PANEL_W - 2 * PAD
local LINE_H, ICON, GAP = 18, 16, 10
local WHEEL_PX = 3 * LINE_H
local M0 = 23 -- Mythic 0 difficulty
local EMPTY = ns.Rows.EMPTY
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local TEXT = { 0.9, 0.9, 0.9 }
local VAULT_ROWS = { { "Vault raid", "Raid" }, { "Vault dungeons", "Activities" }, { "Vault world", "World" } }

-- Model -------------------------------------------------------------------

local function trackText(e)
  if not e.track then return nil end
  if e.trackCur and e.trackMax then return e.track .. " " .. e.trackCur .. "/" .. e.trackMax end
  return e.track
end

-- Display model for one character; nil when the guid is unknown. Partial records yield empties.
function Detail.Model(guid, db, now, currentGuid, editing)
  local char = db.characters and db.characters[guid]
  if not char then return nil end
  local meta = char.meta or {}
  local label = meta.name or "?"
  if meta.realm then label = label .. "-" .. meta.realm end

  local equipment, stored = {}, char.equipment or {}
  for i, slot in ipairs(Content.EQUIP_SLOTS) do
    local row = { slot = slot, slotName = Content.SLOT_NAMES[slot] }
    local e = stored[slot]
    if e then
      row.link, row.itemID, row.ilvl, row.track = e.link, e.itemID, e.ilvl, trackText(e)
      row.missingEnchant = e.missingEnchant and true or false
      row.emptySockets = e.emptySockets or 0
    end
    equipment[i] = row
  end

  local raids, dungeons = 0, 0
  for _, inst in pairs(Reset.Active(char.instances, now)) do
    if inst.isRaid then raids = raids + 1 end
    if inst.difficultyID == M0 then dungeons = dungeons + 1 end
  end

  return {
    header = {
      label = label, classFile = meta.classFile, specID = meta.specID, level = meta.level,
      ilvl = meta.ilvl, ilvlEquipped = meta.ilvlEquipped, gold = meta.gold,
      lastSeen = meta.lastSeen and Util.Age(now - meta.lastSeen) or "never",
    },
    equipment = equipment,
    consumables = Watchlist.Groups(char, db, editing),
    week = {
      raids = raids, dungeons = dungeons,
      vault = Reset.Vault(char.vault, now), mplus = Reset.MythicPlus(char.mythicPlus, now),
    },
    canForget = guid ~= currentGuid,
  }
end

-- Watch an item (drop zone / item ID box). Returns true when the watchlist changed.
function Detail.AddItem(guid, itemID)
  local char = guid and ns.db.characters[guid]
  itemID = tonumber(itemID)
  if not char or not itemID or itemID <= 0 or itemID ~= math.floor(itemID) then return false end
  if not C_Item.GetItemInfoInstant(itemID) then return false end -- not a real item
  Watchlist.Set(char, itemID, true)
  ns.Fire("WATCHLIST_CHANGED")
  Detail:Refresh()
  return true
end

-- Widgets -----------------------------------------------------------------

local panel, scroll, content
local pools = Detail.pools

local function text(parent, justify, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function highlight(frame)
  local hl = frame:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
end

local function textButton(parent, label, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.label = text(b, "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(label)
  highlight(b)
  return b
end

-- Place a widget in the scrolled content at (x, y) from its top-left.
local function at(widget, x, y)
  widget:ClearAllPoints()
  widget:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
end

local function pool(kind, make) pools[kind] = { items = {}, used = 0, make = make } end

local function acquire(kind)
  local p = pools[kind]
  p.used = p.used + 1
  local w = p.items[p.used]
  if not w then
    w = p.make()
    p.items[p.used] = w
  end
  w:Show()
  return w
end

local function hideTooltip() GameTooltip:Hide() end

local function linkTooltip(self)
  if not self.link then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink(self.link)
  GameTooltip:Show()
end

local function itemTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(self.itemID)
  GameTooltip:Show()
end

local function onItemClick(self)
  local char = Detail.guid and ns.db.characters[Detail.guid]
  if not Detail.editing or not char then return end
  Watchlist.Set(char, self.itemID, self:GetChecked() and true or false)
  ns.Fire("WATCHLIST_CHANGED")
  Detail:Refresh()
end

local function makeEquipRow()
  local b = CreateFrame("Button", nil, content)
  b:SetSize(INNER_W, LINE_H)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(ICON, ICON)
  b.icon:SetPoint("LEFT")
  b.slotName = text(b)
  b.slotName:SetPoint("LEFT", ICON + 4, 0)
  b.slotName:SetWidth(70)
  b.ilvl = text(b, "RIGHT")
  b.ilvl:SetPoint("LEFT", ICON + 76, 0)
  b.ilvl:SetWidth(30)
  b.track = text(b)
  b.track:SetPoint("LEFT", ICON + 112, 0)
  b.track:SetWidth(70)
  b.marks = text(b)
  b.marks:SetPoint("LEFT", ICON + 186, 0)
  b.marks:SetPoint("RIGHT")
  highlight(b)
  b:SetScript("OnEnter", linkTooltip)
  b:SetScript("OnLeave", hideTooltip)
  return b
end

local function makeItemRow()
  local b = CreateFrame("CheckButton", nil, content)
  b:SetSize(INNER_W, LINE_H)
  -- The box is textures on the row itself (a child frame's backdrop would cover the tick).
  local border, fill, a = Theme.border, Theme.panel, Theme.accent
  b.boxBorder = b:CreateTexture(nil, "BACKGROUND")
  b.boxBorder:SetColorTexture(border[1], border[2], border[3], 1)
  b.boxBorder:SetSize(12, 12)
  b.boxBorder:SetPoint("LEFT")
  b.boxFill = b:CreateTexture(nil, "BORDER")
  b.boxFill:SetColorTexture(fill[1], fill[2], fill[3], 1)
  b.boxFill:SetPoint("TOPLEFT", b.boxBorder, "TOPLEFT", 1, -1)
  b.boxFill:SetPoint("BOTTOMRIGHT", b.boxBorder, "BOTTOMRIGHT", -1, 1)
  local tick = b:CreateTexture(nil, "OVERLAY")
  tick:SetColorTexture(a[1], a[2], a[3], 1)
  tick:SetPoint("TOPLEFT", b.boxBorder, "TOPLEFT", 3, -3)
  tick:SetPoint("BOTTOMRIGHT", b.boxBorder, "BOTTOMRIGHT", -3, 3)
  b:SetCheckedTexture(tick)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(ICON, ICON)
  b.count = text(b, "RIGHT")
  b.count:SetPoint("RIGHT")
  b.count:SetWidth(40)
  b.name = text(b)
  highlight(b)
  b:SetMotionScriptsWhileDisabled(true) -- rows are disabled outside edit mode but keep tooltips
  b:SetScript("OnClick", onItemClick)
  b:SetScript("OnEnter", itemTooltip)
  b:SetScript("OnLeave", hideTooltip)
  return b
end

local function makeLine()
  local f = CreateFrame("Frame", nil, content)
  f:SetSize(INNER_W, LINE_H)
  f.left = text(f)
  f.left:SetPoint("LEFT")
  f.right = text(f, "RIGHT")
  f.right:SetPoint("RIGHT")
  return f
end

local function dropCursorItem()
  local kind, itemID = GetCursorInfo()
  if kind ~= "item" or not itemID then return end
  ClearCursor()
  Detail.AddItem(Detail.guid, itemID)
end

local function buildEditControls()
  local drop = CreateFrame("Button", nil, content, "BackdropTemplate")
  Theme.Backdrop(drop, Theme.panel)
  drop:SetSize(INNER_W, 32)
  local hint = text(drop, "CENTER", "GameFontDisableSmall")
  hint:SetPoint("CENTER")
  hint:SetText("Drop an item here to watch it")
  drop:SetScript("OnReceiveDrag", dropCursorItem)
  drop:SetScript("OnMouseUp", dropCursorItem)
  panel.dropZone = drop

  local box = CreateFrame("EditBox", nil, content, "BackdropTemplate")
  Theme.Backdrop(box, Theme.panel)
  box:SetSize(100, 20)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(9)
  box:SetFontObject(GameFontHighlightSmall)
  box:SetTextInsets(6, 6, 0, 0)
  local label = text(box, "RIGHT")
  label:SetPoint("RIGHT", box, "LEFT", -6, 0)
  label:SetText("Item ID")
  box:SetScript("OnEscapePressed", box.ClearFocus)
  box:SetScript("OnEnterPressed", function(self)
    Detail.AddItem(Detail.guid, tonumber(self:GetText()))
    self:SetText("")
    self:ClearFocus()
  end)
  panel.idBox = box
end

local function build()
  local main = ns.UI.frame
  panel = CreateFrame("Frame", nil, main, "BackdropTemplate")
  Theme.Backdrop(panel, Theme.bg)
  panel:SetWidth(PANEL_W)
  panel:SetPoint("TOPLEFT", main, "TOPRIGHT", 2, 0)
  panel:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT", 2, 0)
  panel:EnableMouse(true)
  panel:Hide()
  Detail.panel = panel

  panel.icon = panel:CreateTexture(nil, "ARTWORK")
  panel.icon:SetSize(40, 40)
  panel.icon:SetPoint("TOPLEFT", PAD, -PAD)
  panel.name = text(panel, "LEFT", "GameFontNormal")
  panel.name:SetPoint("TOPLEFT", PAD + 48, -PAD)
  panel.name:SetPoint("RIGHT", -30, 0)
  panel.info = text(panel)
  panel.info:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -3)
  panel.seen = text(panel)
  panel.seen:SetPoint("TOPLEFT", panel.info, "BOTTOMLEFT", 0, -3)

  panel.close = textButton(panel, "x", 26, 26)
  panel.close:SetPoint("TOPRIGHT")
  panel.close:SetScript("OnClick", function() Detail:Close() end)

  scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", PAD, -HEADER_H)
  scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(INNER_W, 1)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * WHEEL_PX)))
  end)

  pool("heading", function() return text(content, "LEFT", "GameFontNormal") end)
  pool("category", function()
    local fs = text(content)
    setColor(fs, Theme.accent)
    return fs
  end)
  pool("equip", makeEquipRow)
  pool("item", makeItemRow)
  pool("line", makeLine)

  panel.editButton = textButton(content, "Edit", 50, LINE_H)
  panel.editButton:SetScript("OnClick", function()
    Detail.editing = not Detail.editing
    if not Detail.editing then panel.idBox:ClearFocus() end
    Detail:Refresh()
  end)
  panel.empty = text(content, "LEFT", "GameFontDisableSmall")
  buildEditControls()

  panel.forget = textButton(content, "Forget character", 140, 22)
  setColor(panel.forget.label, { 1, 0.35, 0.35 })
  panel.forget:SetScript("OnClick", function()
    StaticPopup_Show("LOCKOUT_FORGET", Detail.label, nil, Detail.guid)
  end)
end

-- Rendering ---------------------------------------------------------------

local function heading(title, y)
  local fs = acquire("heading")
  at(fs, 0, y)
  fs:SetText(title)
  return y + LINE_H + 2
end

local function renderHeader(h)
  local icon = panel.icon
  local specIcon = h.specID and select(4, GetSpecializationInfoByID(h.specID))
  local coords = h.classFile and CLASS_ICON_TCOORDS[h.classFile]
  if specIcon then
    icon:SetTexture(specIcon)
    icon:SetTexCoord(0, 1, 0, 1)
  elseif coords then
    icon:SetTexture(CLASS_ICONS)
    icon:SetTexCoord(unpack(coords))
  else
    icon:SetTexture(UNKNOWN_ICON)
    icon:SetTexCoord(0, 1, 0, 1)
  end

  panel.name:SetText(h.label)
  panel.name:SetTextColor(Theme.ClassColor(h.classFile))
  local info = {}
  if h.level then info[#info + 1] = "Level " .. h.level end
  if h.ilvl then info[#info + 1] = "iLvl " .. h.ilvl .. (h.ilvlEquipped and (" / " .. h.ilvlEquipped) or "") end
  panel.info:SetText(#info > 0 and table.concat(info, "  ·  ") or EMPTY)
  local gold = h.gold and (GetMoneyString(h.gold, true) .. "  ·  ") or ""
  panel.seen:SetText(gold .. "Last seen " .. h.lastSeen)
end

local function renderEquipment(list, y)
  y = heading("Equipment", y)
  for _, e in ipairs(list) do
    local b = acquire("equip")
    at(b, 0, y)
    b.link = e.link
    local icon = e.link and C_Item.GetItemIconByID(e.itemID or e.link)
    b.icon:SetTexture(icon)
    b.icon:SetShown(icon ~= nil)
    b.slotName:SetText(e.slotName or "")
    setColor(b.slotName, Theme.grey)
    b.ilvl:SetText(not e.link and EMPTY or e.ilvl and tostring(math.floor(e.ilvl)) or "?")
    b.track:SetText(e.track or "")
    local marks = {}
    if e.missingEnchant then marks[#marks + 1] = "|cffff4d4dNo enchant|r" end
    if (e.emptySockets or 0) > 0 then marks[#marks + 1] = Theme.Icon.socket .. "×" .. e.emptySockets end
    b.marks:SetText(table.concat(marks, " "))
    y = y + LINE_H
  end
  return y + GAP
end

local function fillItem(b, item, editing)
  b.itemID = item.itemID
  if editing then b:Enable() else b:Disable() end
  b:SetChecked(editing and item.shown)
  b.boxBorder:SetShown(editing)
  b.boxFill:SetShown(editing)
  local x = editing and 18 or 0
  b.icon:ClearAllPoints()
  b.icon:SetPoint("LEFT", x, 0)
  b.name:ClearAllPoints()
  b.name:SetPoint("LEFT", x + ICON + 4, 0)
  b.name:SetPoint("RIGHT", b.count, "LEFT", -4, 0)

  local dim = item.count == 0 or not item.shown
  b.icon:SetTexture(C_Item.GetItemIconByID(item.itemID) or UNKNOWN_ICON)
  b.icon:SetDesaturated(dim)
  b.name:SetText(C_Item.GetItemNameByID(item.itemID) or ("Item " .. item.itemID))
  b.count:SetText(tostring(item.count))
  local c = dim and Theme.grey or TEXT
  setColor(b.name, c)
  setColor(b.count, c)
end

local function renderConsumables(groups, y)
  local editing = Detail.editing
  local edit = panel.editButton
  edit:ClearAllPoints()
  edit:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
  edit.label:SetText(editing and "Done" or "Edit")
  y = heading("Consumables", y)

  panel.empty:SetShown(#groups == 0)
  if #groups == 0 then
    at(panel.empty, 0, y)
    panel.empty:SetText(editing and "Drop an item below or enter its ID." or "Nothing watched. Click Edit to add items.")
    y = y + LINE_H
  end
  for _, group in ipairs(groups) do
    local fs = acquire("category")
    at(fs, 0, y)
    fs:SetText(group.category)
    y = y + LINE_H
    for _, item in ipairs(group.items) do
      local b = acquire("item")
      at(b, 0, y)
      fillItem(b, item, editing)
      y = y + LINE_H
    end
  end

  panel.dropZone:SetShown(editing)
  panel.idBox:SetShown(editing)
  if editing then
    at(panel.dropZone, 0, y + 4)
    y = y + 40
    at(panel.idBox, 50, y)
    y = y + 24
  end
  return y + GAP
end

local function vaultText(activities, chest)
  local wanted = Enum.WeeklyRewardChestThresholdType[chest]
  local total, unlocked, best = 0, 0, 0
  for _, a in ipairs(activities) do
    if a.type == wanted then
      total = total + 1
      if (a.threshold or 0) > 0 and (a.progress or 0) >= a.threshold then unlocked = unlocked + 1 end
      best = math.max(best, a.rewardIlvl or 0)
    end
  end
  if total == 0 then return EMPTY end
  return unlocked .. "/" .. total .. (best > 0 and (" · " .. best) or "")
end

local function keyText(key)
  if not key or not key.level then return EMPTY end
  local ok, season = pcall(ns.Season.Get, ns.Season)
  local name
  for _, m in ipairs(ok and season and season.mplus or {}) do
    if m.challengeMapID == key.challengeMapID then name = m.name end
  end
  return "+" .. key.level .. (name and (" " .. name) or "")
end

local function renderWeek(week, y)
  y = heading("This week", y)
  local function line(left, right, color)
    local f = acquire("line")
    at(f, 0, y)
    f.left:SetText(left)
    setColor(f.left, Theme.grey)
    f.right:SetText(right)
    setColor(f.right, right == EMPTY and Theme.grey or color or TEXT)
    y = y + LINE_H
  end
  line("Raid lockouts", tostring(week.raids))
  line("Mythic 0 dungeons", tostring(week.dungeons))
  for _, v in ipairs(VAULT_ROWS) do line(v[1], vaultText(week.vault.activities, v[2])) end
  local mp = week.mplus
  line("Keystone", keyText(mp.key))
  line("Rating", mp.rating > 0 and tostring(math.floor(mp.rating + 0.5)) or EMPTY)
  line("Weekly best", mp.weeklyBest > 0 and ("+" .. mp.weeklyBest) or EMPTY)
  if week.vault.ready then line("Great Vault", "Reward waiting", Theme.green) end
  return y + GAP
end

function Detail:Refresh()
  if not panel or not self.guid or not panel:IsShown() then return end
  local model = Detail.Model(self.guid, ns.db, time(), UnitGUID("player"), self.editing)
  if not model then
    self:Close() -- forgotten or wiped
    return
  end
  self.label = model.header.label
  for _, p in pairs(pools) do p.used = 0 end

  renderHeader(model.header)
  local y = renderEquipment(model.equipment, 0)
  y = renderConsumables(model.consumables, y)
  y = renderWeek(model.week, y)
  panel.forget:SetShown(model.canForget)
  if model.canForget then
    at(panel.forget, 0, y)
    y = y + 26
  end
  content:SetHeight(y)

  for _, p in pairs(pools) do
    for i = p.used + 1, #p.items do p.items[i]:Hide() end
  end
end

-- Open/close keep the main window's selection in step with what the panel shows.
function Detail:Open(guid)
  local UI = ns.UI
  if not guid or not UI then return end
  if not (UI.frame and UI.frame:IsShown()) then UI:Show() end
  if not panel then build() end
  if guid ~= self.guid then
    self.editing = false
    scroll:SetVerticalScroll(0)
  end
  self.guid = guid
  panel:Show()
  UI:SetSelected(guid)
  self:Refresh()
end

function Detail:Close()
  self.guid, self.editing = nil, false
  if panel then
    panel.idBox:ClearFocus()
    panel:Hide()
  end
  if ns.UI then ns.UI:SetSelected(nil) end
end

function Detail:Toggle(guid)
  if guid and guid == self.guid and panel and panel:IsShown() then
    self:Close()
  else
    self:Open(guid)
  end
end

if StaticPopupDialogs then
  StaticPopupDialogs.LOCKOUT_FORGET = {
    text = "Forget %s? Their saved data will be removed.",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, guid)
      if ns.DB:Forget(guid) and Detail.guid == guid then Detail:Close() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
end

ns.On("DATA_UPDATED", function() Detail:Refresh() end)
