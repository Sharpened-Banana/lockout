local loader = require("tests.loader")
local mock = require("tests.wow_mock")

local CURRENT, ALT, FRESH = "Player-1-0001", "Player-2-0002", "Player-3-0003"
local HELM_LINK = "|cffa335ee|Hitem:1001::::::::80:::::|h[Helm]|h|r"

local hyperlinks, popups, cursorCleared, cursor

local function install()
  hyperlinks, popups, cursorCleared, cursor = {}, {}, 0, nil
  UIParent = CreateFrame("Frame", "UIParent")
  GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
  GameTooltip.SetHyperlink = function(_, link) hyperlinks[#hyperlinks + 1] = link end
  C_ClassColor = { GetClassColor = function() end }
  IsShiftKeyDown = function() return false end
  GetBuildInfo = function() return "12.0.7", "66666", "Oct 1 2026", 120007 end
  LE_EXPANSION_LEVEL_CURRENT = 11
  EJ_GetNumTiers = function() return 0 end
  C_ChallengeMode = {
    GetMapTable = function() return { 501 } end,
    GetMapUIInfo = function(id)
      if id == 501 then return "Crypt", 501, 1800, 1, 2, 10 end
    end,
  }
  C_Item = {
    GetItemIconByID = function() return 134400 end,
    GetItemNameByID = function(id) if id == 2001 then return "Flask of Testing" end end,
    -- Items below 900000 exist; anything above is an unknown ID.
    GetItemInfoInstant = function(id) if type(id) == "number" and id < 900000 then return id end end,
  }
  GetMoneyString = function(copper) return tostring(copper) .. "c" end
  GetSpecializationInfoByID = function(id) if id == 262 then return 262, "Elemental", "", 136048 end end
  CLASS_ICON_TCOORDS = { SHAMAN = { 0.25, 0.49, 0.25, 0.5 } }
  StaticPopupDialogs = {}
  StaticPopup_Show = function(which, text, _, data)
    popups[#popups + 1] = { which = which, text = text, data = data }
  end
  GetCursorInfo = function() if cursor then return "item", cursor end end
  ClearCursor = function()
    cursor = nil
    cursorCleared = cursorCleared + 1
  end
end

local function fullRecord(now)
  local T = Enum.WeeklyRewardChestThresholdType
  return {
    meta = {
      name = "Jaina", realm = "Silvermoon", classFile = "MAGE", level = 80, specID = 63,
      ilvl = 640, ilvlEquipped = 638, gold = 123456, lastSeen = now - 7200,
    },
    equipment = {
      [1] = { link = HELM_LINK, itemID = 1001, ilvl = 645, track = "Hero", trackCur = 4, trackMax = 6,
        missingEnchant = true, emptySockets = 1 },
      [2] = { link = "|Hitem:1002|h[Neck]|h", itemID = 1002, ilvl = nil, missingEnchant = false, emptySockets = 0 },
    },
    instances = {
      ["100:15"] = { mapID = 100, difficultyID = 15, isRaid = true, resetAt = now + 3600 },
      ["101:16"] = { mapID = 101, difficultyID = 16, isRaid = true, resetAt = now + 3600 },
      ["102:14"] = { mapID = 102, difficultyID = 14, isRaid = true, resetAt = now - 1 },  -- expired
      ["10:23"] = { mapID = 10, difficultyID = 23, isRaid = false, resetAt = now + 3600 },
      ["11:23"] = { mapID = 11, difficultyID = 23, isRaid = false, resetAt = now - 1 },  -- expired
      ["12:2"] = { mapID = 12, difficultyID = 2, isRaid = false, resetAt = now + 3600 },  -- heroic, not M0
    },
    vault = { resetAt = now + 3600, unclaimed = true, activities = {
      { type = T.Raid, index = 1, threshold = 2, progress = 2, rewardIlvl = 671 },
      { type = T.Activities, index = 1, threshold = 1, progress = 0 },
    } },
    mythicPlus = { resetAt = now + 3600, rating = 2456.4, weeklyBest = 12,
      key = { challengeMapID = 501, level = 12 } },
    bags = { counts = { [2001] = 3 } },
    watchlist = { [2001] = true, [2002] = true },
  }
end

local function seed(db, now)
  db.characters[CURRENT] = { meta = { name = "Thrall", realm = "Draenor", classFile = "SHAMAN", level = 80, specID = 262 } }
  db.characters[ALT] = fullRecord(now)
  db.characters[FRESH] = { meta = { name = "Fresh" } }
end

local function click(widget, ...)
  widget:GetScript("OnClick")(widget, ...)
end

local function shown(kind, ns)
  local p = ns.Detail.pools[kind]
  local out = {}
  for i = 1, p.used do out[i] = p.items[i] end
  return out
end

describe("Detail model", function()
  local ns

  before_each(function()
    ns = loader.load(nil, install)
    ns.DB:Init(nil)
    seed(ns.db, mock.now)
  end)

  it("model of full record", function()
    local m = ns.Detail.Model(ALT, ns.db, mock.now, CURRENT)
    assert.same({
      label = "Jaina-Silvermoon", classFile = "MAGE", specID = 63, level = 80, ilvl = 640, ilvlEquipped = 638,
      gold = 123456, lastSeen = "2h ago",
    }, m.header)

    assert.equals(16, #m.equipment)
    assert.same({
      slot = 1, slotName = "Head", link = HELM_LINK, itemID = 1001, ilvl = 645, track = "Hero 4/6",
      missingEnchant = true, emptySockets = 1,
    }, m.equipment[1])
    assert.equals(2, m.equipment[2].slot)
    assert.is_nil(m.equipment[2].track)
    assert.is_nil(m.equipment[2].ilvl)
    assert.same({ slot = 3, slotName = "Shoulder" }, m.equipment[3])
    for i, slot in ipairs(ns.Content.EQUIP_SLOTS) do assert.equals(slot, m.equipment[i].slot) end

    assert.same({ { category = "Other", items = {
      { itemID = 2001, count = 3, shown = true },
      { itemID = 2002, count = 0, shown = true },
    } } }, m.consumables)

    assert.equals(2, m.week.raids)
    assert.equals(1, m.week.dungeons)
    assert.is_true(m.week.vault.ready)
    assert.equals(2, #m.week.vault.activities)
    assert.equals(2456.4, m.week.mplus.rating)
    assert.equals(12, m.week.mplus.key.level)
    assert.is_true(m.canForget)
  end)

  it("model of meta-only record", function()
    local m = ns.Detail.Model(FRESH, ns.db, mock.now, CURRENT)
    assert.equals("Fresh", m.header.label)
    assert.equals("never", m.header.lastSeen)
    assert.equals(16, #m.equipment)
    for i, row in ipairs(m.equipment) do
      assert.equals(ns.Content.EQUIP_SLOTS[i], row.slot)
      assert.truthy(row.slotName)
      assert.is_nil(row.link)
    end
    assert.same({}, m.consumables)
    assert.equals(0, m.week.raids)
    assert.equals(0, m.week.dungeons)
    assert.is_false(m.week.vault.ready)
    assert.equals(0, m.week.mplus.rating)

    -- an empty record (no meta at all) too
    ns.db.characters["Player-4-0004"] = {}
    local empty = ns.Detail.Model("Player-4-0004", ns.db, mock.now, CURRENT)
    assert.equals("?", empty.header.label)
    assert.equals(16, #empty.equipment)
  end)

  it("unknown guid has no model", function()
    assert.is_nil(ns.Detail.Model("Player-0-0000", ns.db, mock.now, CURRENT))
  end)

  it("editing lists hidden scan-set items", function()
    ns.db.characters[ALT].watchlist[2002] = false -- custom item, off, watched by nobody else
    local normal = ns.Detail.Model(ALT, ns.db, mock.now, CURRENT)
    assert.equals(1, #normal.consumables[1].items)
    local editing = ns.Detail.Model(ALT, ns.db, mock.now, CURRENT, true)
    assert.same({ itemID = 2002, count = 0, shown = false }, editing.consumables[1].items[2])
  end)

  it("cannot forget current", function()
    assert.is_false(ns.Detail.Model(CURRENT, ns.db, mock.now, CURRENT).canForget)
    assert.is_true(ns.Detail.Model(FRESH, ns.db, mock.now, CURRENT).canForget)
  end)

  it("edit add by id fires WATCHLIST_CHANGED", function()
    local fired = 0
    ns.On("WATCHLIST_CHANGED", function() fired = fired + 1 end)
    assert.is_true(ns.Detail.AddItem(FRESH, 3001))
    assert.is_true(ns.db.characters[FRESH].watchlist[3001])
    assert.equals(1, fired)

    -- unknown items, junk input and unknown characters are refused
    assert.is_false(ns.Detail.AddItem(FRESH, 999999))
    assert.is_false(ns.Detail.AddItem(FRESH, nil))
    assert.is_false(ns.Detail.AddItem(FRESH, 0))
    assert.is_false(ns.Detail.AddItem("Player-0-0000", 3001))
    assert.equals(1, fired)
    assert.is_nil(ns.db.characters[FRESH].watchlist[999999])
  end)
end)

describe("Detail panel", function()
  local ns, panel

  before_each(function()
    ns = loader.load(nil, install)
    ns.DB:Init(nil)
    seed(ns.db, mock.now)
    ns.UI:Show()
  end)

  local function open(guid)
    ns.Detail:Toggle(guid)
    panel = ns.Detail.panel
  end

  it("toggles open and closed for the same guid", function()
    open(ALT)
    assert.is_true(panel:IsShown())
    assert.equals(ALT, ns.Detail.guid)
    ns.Detail:Toggle(ALT)
    assert.is_false(panel:IsShown())
    assert.is_nil(ns.Detail.guid)
    -- a different guid switches instead of closing
    ns.Detail:Toggle(ALT)
    ns.Detail:Toggle(FRESH)
    assert.is_true(panel:IsShown())
    assert.equals(FRESH, ns.Detail.guid)
  end)

  it("docks to the right of the main window, 320 wide", function()
    open(ALT)
    assert.equals(320, panel:GetWidth())
    assert.same({ "TOPLEFT", LockoutMainFrame, "TOPRIGHT", 2, 0 }, { panel:GetPoint(1) })
    assert.same({ "BOTTOMLEFT", LockoutMainFrame, "BOTTOMRIGHT", 2, 0 }, { panel:GetPoint(2) })
  end)

  it("opens the main window when it is closed", function()
    LockoutMainFrame:Hide()
    open(ALT)
    assert.is_true(LockoutMainFrame:IsShown())
  end)

  it("renders header and equipment", function()
    open(ALT)
    assert.equals("Jaina-Silvermoon", panel.name:GetText())
    assert.equals("Level 80  ·  iLvl 640 / 638", panel.info:GetText())
    assert.equals("123456c  ·  Last seen 2h ago", panel.seen:GetText())

    local rows = shown("equip", ns)
    assert.equals(16, #rows)
    assert.equals("Head", rows[1].slotName:GetText())
    assert.equals("645", rows[1].ilvl:GetText())
    assert.equals("Hero 4/6", rows[1].track:GetText())
    assert.truthy(rows[1].marks:GetText():find("No enchant", 1, true))
    assert.truthy(rows[1].marks:GetText():find(ns.Theme.Icon.socket .. "×1", 1, true))
    assert.equals("?", rows[2].ilvl:GetText())   -- item not cached
    assert.equals("", rows[2].marks:GetText())
    assert.equals("–", rows[3].ilvl:GetText())   -- empty slot
    assert.is_false(rows[3].icon:IsShown())

    rows[1]:GetScript("OnEnter")(rows[1])
    assert.same({ HELM_LINK }, hyperlinks)
    rows[1]:GetScript("OnLeave")(rows[1])
    rows[3]:GetScript("OnEnter")(rows[3])   -- empty slot: no tooltip
    assert.equals(1, #hyperlinks)
  end)

  it("renders consumables and this week", function()
    open(ALT)
    local cats = shown("category", ns)
    assert.equals(1, #cats)
    assert.equals("Other", cats[1]:GetText())
    local items = shown("item", ns)
    assert.equals(2, #items)
    assert.equals("Flask of Testing", items[1].name:GetText())
    assert.equals("3", items[1].count:GetText())
    assert.equals("Item 2002", items[2].name:GetText())
    assert.same({ ns.Theme.grey[1], ns.Theme.grey[2], ns.Theme.grey[3] }, { items[2].count:GetTextColor() })

    local lines = {}
    for _, f in ipairs(shown("line", ns)) do lines[f.left:GetText()] = f.right:GetText() end
    assert.equals("2", lines["Raid lockouts"])
    assert.equals("1", lines["Mythic 0 dungeons"])
    assert.equals("1/1 · 671", lines["Vault raid"])
    assert.equals("0/1", lines["Vault dungeons"])
    assert.equals("–", lines["Vault world"])
    assert.equals("+12 Crypt", lines["Keystone"])
    assert.equals("2456", lines["Rating"])
    assert.equals("+12", lines["Weekly best"])
    assert.equals("Reward waiting", lines["Great Vault"])
  end)

  it("meta-only record renders without error", function()
    open(FRESH)
    assert.equals(16, #shown("equip", ns))
    assert.equals(0, #shown("item", ns))
    assert.is_true(panel.empty:IsShown())
    assert.equals("Last seen never", panel.seen:GetText())
    for _, line in ipairs(ns.log) do assert.is_nil(line:find("failed", 1, true)) end
  end)

  it("edit mode toggles watchlist entries", function()
    local fired = 0
    ns.On("WATCHLIST_CHANGED", function() fired = fired + 1 end)
    open(ALT)
    assert.is_false(panel.dropZone:IsShown())
    assert.is_false(panel.idBox:IsShown())
    click(panel.editButton)
    assert.is_true(ns.Detail.editing)
    assert.equals("Done", panel.editButton.label:GetText())
    assert.is_true(panel.dropZone:IsShown())
    assert.is_true(panel.idBox:IsShown())

    local item = shown("item", ns)[2]
    assert.equals(2002, item.itemID)
    assert.is_true(item:GetChecked())
    item:SetChecked(false)
    click(item)
    assert.is_false(ns.db.characters[ALT].watchlist[2002])
    assert.equals(1, fired)
    -- still listed (unchecked, greyed) while editing although no other character watches it
    assert.equals(2, #shown("item", ns))
    assert.is_false(shown("item", ns)[2]:GetChecked())
    assert.same({ ns.Theme.grey[1], ns.Theme.grey[2], ns.Theme.grey[3] }, { shown("item", ns)[2].name:GetTextColor() })
    -- re-checking restores it
    shown("item", ns)[2]:SetChecked(true)
    click(shown("item", ns)[2])
    assert.is_true(ns.db.characters[ALT].watchlist[2002])
    assert.equals(2, fired)
    shown("item", ns)[2]:SetChecked(false)
    click(shown("item", ns)[2])

    click(panel.editButton)
    assert.is_false(ns.Detail.editing)
    assert.equals(1, #shown("item", ns))
    assert.is_false(panel.dropZone:IsShown())
  end)

  it("checkbox box is drawn on the row itself and shown only while editing", function()
    open(ALT)
    local item = shown("item", ns)[1]
    -- no child frame: a higher-level frame's backdrop would cover the row's checked texture
    assert.is_nil(item.box)
    assert.is_false(item.boxBorder:IsShown())
    assert.is_false(item.boxFill:IsShown())
    click(panel.editButton)
    item = shown("item", ns)[1]
    assert.is_true(item.boxBorder:IsShown())
    assert.is_true(item.boxFill:IsShown())
    assert.is_true(item:GetChecked())
  end)

  it("item rows do nothing outside edit mode", function()
    local fired = 0
    ns.On("WATCHLIST_CHANGED", function() fired = fired + 1 end)
    open(ALT)
    local item = shown("item", ns)[1]
    item:SetChecked(false)
    click(item)
    assert.is_true(ns.db.characters[ALT].watchlist[2001])
    assert.equals(0, fired)
  end)

  it("drop zone and item ID box add items", function()
    open(ALT)
    click(panel.editButton)
    cursor = 4001
    panel.dropZone:GetScript("OnReceiveDrag")(panel.dropZone)
    assert.is_true(ns.db.characters[ALT].watchlist[4001])
    assert.equals(1, cursorCleared)
    -- a click with nothing on the cursor is ignored
    panel.dropZone:GetScript("OnMouseUp")(panel.dropZone)
    assert.equals(1, cursorCleared)

    panel.idBox:SetText("4002")
    panel.idBox:GetScript("OnEnterPressed")(panel.idBox)
    assert.is_true(ns.db.characters[ALT].watchlist[4002])
    assert.equals("", panel.idBox:GetText())
    assert.equals(4, #shown("item", ns))
  end)

  it("forget asks, removes and closes", function()
    open(ALT)
    assert.is_true(panel.forget:IsShown())
    click(panel.forget)
    assert.same({ { which = "LOCKOUT_FORGET", text = "Jaina-Silvermoon", data = ALT } }, popups)
    local dialog = StaticPopupDialogs.LOCKOUT_FORGET
    assert.equals("Forget %s? Their saved data will be removed.", dialog.text)
    dialog.OnAccept(nil, ALT)
    assert.is_nil(ns.db.characters[ALT])
    assert.is_false(panel:IsShown())
    assert.is_nil(ns.Detail.guid)
    assert.is_nil(ns.UI.selectedGuid)
    assert.is_nil(ns.UI.grid.selected)
  end)

  it("hides forget for the current character", function()
    open(CURRENT)
    assert.is_false(panel.forget:IsShown())
    open(ALT) -- switch
    assert.is_true(panel.forget:IsShown())
  end)

  it("DATA_UPDATED refreshes the open panel", function()
    open(ALT)
    ns.db.characters[ALT].meta.name = "Proudmoore"
    ns.Fire("DATA_UPDATED", "Character")
    assert.equals("Proudmoore-Silvermoon", panel.name:GetText())
    for _, line in ipairs(ns.log) do assert.is_nil(line:find("callback failed", 1, true)) end
  end)

  it("header icon prefers the spec icon, then class coords", function()
    open(CURRENT)
    assert.equals(136048, panel.icon:GetTexture())
    assert.same({ 0, 1, 0, 1 }, { panel.icon:GetTexCoord() })
    ns.db.characters[CURRENT].meta.specID = nil
    ns.Detail:Refresh()
    assert.equals("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES", panel.icon:GetTexture())
    assert.same({ 0.25, 0.49, 0.25, 0.5 }, { panel.icon:GetTexCoord() })
    open(FRESH)
    assert.equals("Interface\\Icons\\INV_Misc_QuestionMark", panel.icon:GetTexture())
  end)
end)
