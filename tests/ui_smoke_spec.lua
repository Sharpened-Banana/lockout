local loader = require("tests.loader")
local mock = require("tests.wow_mock")

-- Headless smoke test: frames cannot render, so this drives the handlers the UI wires
-- (through GetScript) and checks the state they leave behind.

local tooltipLines

local function install()
  UIParent = CreateFrame("Frame", "UIParent")
  GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
  GameTooltip.SetOwner = function() tooltipLines = {} end
  GameTooltip.AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end
  GameTooltip.AddDoubleLine = function(_, l, r) tooltipLines[#tooltipLines + 1] = l .. " | " .. r end
  C_ClassColor = {
    GetClassColor = function(classFile)
      if classFile == "SHAMAN" then return { r = 0, g = 0.44, b = 0.87 } end
    end,
  }
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
  -- Detail panel APIs
  C_Item = {
    GetItemIconByID = function() return 134400 end,
    GetItemNameByID = function() end,
    GetItemInfoInstant = function(id) return id end,
  }
  GetMoneyString = function(copper) return tostring(copper) end
  GetSpecializationInfoByID = function() end
  CLASS_ICON_TCOORDS = {}
  StaticPopupDialogs = {}
  StaticPopup_Show = function() end
end

local function seed(db, now)
  local T = Enum.WeeklyRewardChestThresholdType
  local encounters = {}
  for i = 1, 8 do encounters[i] = { name = "Boss" .. i, killed = i <= 4 } end
  db.characters["Player-1-0001"] = {
    meta = { name = "Thrall", realm = "Draenor", classFile = "SHAMAN", level = 80, ilvl = 640 },
    instances = {
      ["100:15"] = {
        name = "Alpha Keep", mapID = 100, difficultyID = 15, difficultyName = "Heroic", isRaid = true,
        resetAt = now + 86400, killed = 4, total = 8, encounters = encounters,
      },
      ["10:23"] = { mapID = 10, difficultyID = 23, resetAt = now + 86400 },
    },
    worldBosses = { wb7 = { name = "Zed", resetAt = now + 3600 } },
    vault = { resetAt = now + 86400, unclaimed = false, activities = {
      { type = T.Activities, index = 1, threshold = 1, progress = 1, rewardIlvl = 678 },
      { type = T.Raid, index = 1, threshold = 2, progress = 1 },
    } },
    mythicPlus = { resetAt = now + 86400, rating = 2456, key = { challengeMapID = 501, level = 12 }, seasonBest = { [501] = 12 } },
    delves = { updatedAt = now - 60, currencies = {} },
  }
  db.characters["Player-2-0002"] = {
    meta = { name = "Jaina", realm = "Silvermoon", classFile = "MAGE", level = 80, ilvl = 600 },
    mythicPlus = { rating = 1800 },
  }
  -- Partial record: never fully collected.
  db.characters["Player-3-0003"] = { meta = { name = "Fresh", level = 80 } }
  for i = 1, 25 do
    db.characters[string.format("Player-9-%04d", i)] = {
      meta = { name = string.format("Alt%02d", i), realm = "Draenor", classFile = "WARRIOR", level = 80, ilvl = 500 + i },
    }
  end
end

local function labels(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.label end
  return out
end

local function click(widget, ...)
  widget:GetScript("OnClick")(widget, ...)
end

describe("UI smoke", function()
  local ns, detail

  before_each(function()
    ns = loader.load(nil, install)
    ns.DB:Init(nil)
    seed(ns.db, mock.now)
    ns.db.settings.showLegacy = true
    -- Record row clicks on their way to the real detail panel.
    detail = {}
    local toggle = ns.Detail.Toggle
    ns.Detail.Toggle = function(self, guid)
      detail[#detail + 1] = guid
      return toggle(self, guid)
    end
  end)

  -- Show the window and give the grid a size, as the client's layout pass would.
  local function open()
    ns.UI:Show()
    local grid = ns.UI.grid
    grid.frame:GetScript("OnSizeChanged")(grid.frame, 800, 400)
    return grid
  end

  it("opens, registers for Esc and renders every tab", function()
    local grid = open()
    local found = false
    for _, name in ipairs(UISpecialFrames) do
      if name == "LockoutMainFrame" then found = true end
    end
    assert.is_true(found)
    assert.equals(ns.UI.frame, LockoutMainFrame)
    assert.is_true(LockoutMainFrame:IsShown())

    for _, name in ipairs(ns.TabOrder) do
      ns.UI:SelectTab(name)
      assert.equals(name, ns.UI.selectedTab)
      ns.UI:Refresh()
      assert.equals(28, #grid.rows)
    end
    -- default sort: ilvl descending
    assert.equals("Thrall", grid.slots[1].name:GetText())
    assert.equals("80", grid.slots[1].level:GetText())
    assert.equals("640", grid.slots[1].ilvl:GetText())
  end)

  it("fills tab cells from the tab models", function()
    local grid = open()
    ns.UI:SelectTab("Weekly")
    assert.equals(7, #grid.columns)
    assert.equals("+12 Crypt", grid.slots[1].cells[4].text:GetText())
    assert.equals("2456", grid.slots[1].cells[5].text:GetText())
    assert.equals("–", grid.slots[2].cells[4].text:GetText())

    ns.UI:SelectTab("Dungeons")
    assert.equals(1, #grid.columns)
    assert.equals("Crypt", grid.dataHeaders[1].label:GetText())
    assert.equals(ns.Theme.Icon.check .. " +12", grid.slots[1].cells[1].text:GetText())

    ns.UI:SelectTab("Raids")
    -- no season raids from the EJ stub; the legacy column comes from Thrall's lockout
    assert.equals(1, #grid.columns)
    assert.equals("H 4/8", grid.slots[1].cells[1].text:GetText())
    assert.equals("–", grid.slots[2].cells[1].text:GetText())
  end)

  it("unknown tab names are ignored", function()
    open()
    ns.UI:SelectTab("Nope")
    assert.equals("Raids", ns.UI.selectedTab)
  end)

  it("virtualizes rows with a recycled pool", function()
    local grid = open()
    local pool = math.ceil(grid.bodyHeight / ns.Theme.ROW_H) + 1
    assert.equals(pool, #grid.slots)
    assert.truthy(pool < #grid.rows)

    grid.vbar:GetScript("OnValueChanged")(grid.vbar, 5)
    assert.equals(5, grid.offset)
    assert.equals(grid.rows[6].label, grid.slots[1].name:GetText())

    -- mouse wheel scrolls up three rows
    grid.frame:GetScript("OnMouseWheel")(grid.frame, 1)
    assert.equals(2, grid.offset)
    -- clamped at both ends
    grid:ScrollTo(-4)
    assert.equals(0, grid.offset)
    grid:ScrollTo(1000)
    assert.equals(#grid.rows - math.floor(grid.bodyHeight / ns.Theme.ROW_H), grid.offset)

    -- slots past the end of the list hide
    ns.UI.filter:SetText("jai")
    ns.UI.filter:GetScript("OnTextChanged")(ns.UI.filter, true)
    assert.same({ "Jaina" }, labels(grid.rows))
    assert.equals(0, grid.offset)
    assert.is_true(grid.slots[1].left:IsShown())
    assert.is_false(grid.slots[2].left:IsShown())
    assert.is_false(grid.vbar:IsShown())
  end)

  it("filter is plain text", function()
    local grid = open()
    ns.UI.filter:SetText("%(")
    ns.UI.filter:GetScript("OnTextChanged")(ns.UI.filter, true)
    assert.equals(0, #grid.rows)
  end)

  it("current realm checkbox persists and filters", function()
    local grid = open()
    ns.UI.realmCheck:SetChecked(true)
    click(ns.UI.realmCheck)
    assert.is_true(ns.db.settings.currentRealmOnly)
    for _, row in ipairs(grid.rows) do assert.equals("Draenor", row.char.meta.realm) end
    assert.equals(26, #grid.rows)
    ns.UI.realmCheck:SetChecked(false)
    click(ns.UI.realmCheck)
    assert.is_false(ns.db.settings.currentRealmOnly)
    assert.equals(28, #grid.rows)
  end)

  it("sort header click toggles sort key and direction", function()
    local grid = open()
    click(grid.headers.level)
    assert.equals("level", ns.db.settings.sortKey)
    assert.is_true(ns.db.settings.sortDesc)
    click(grid.headers.level)
    assert.is_false(ns.db.settings.sortDesc)

    click(grid.headers.name)
    assert.equals("name", ns.db.settings.sortKey)
    assert.is_false(ns.db.settings.sortDesc)
    assert.equals("Alt01", grid.rows[1].label)
    click(grid.headers.name)
    assert.is_true(ns.db.settings.sortDesc)
    assert.equals("Thrall", grid.rows[1].label)

    click(grid.headers.ilvl)
    assert.equals("ilvl", ns.db.settings.sortKey)
    assert.is_true(ns.db.settings.sortDesc)
  end)

  it("star toggles a favorite and pins it to the top", function()
    local grid = open()
    local jaina = grid.slots[2]
    assert.equals("Jaina", jaina.name:GetText())
    click(jaina.star)
    assert.is_true(ns.db.settings.favorites["Player-2-0002"])
    assert.equals("Jaina", grid.rows[1].label)
    assert.is_true(grid.rows[1].favorite)
    click(grid.slots[1].star)
    assert.is_nil(ns.db.settings.favorites["Player-2-0002"])
    assert.equals("Thrall", grid.rows[1].label)
  end)

  it("row and cell clicks toggle the detail panel", function()
    local grid = open()
    click(grid.slots[1].left)
    assert.same({ "Player-1-0001" }, detail)
    assert.equals("Player-1-0001", ns.UI.selectedGuid)
    click(grid.slots[1].left)
    assert.is_nil(ns.UI.selectedGuid)
    click(grid.slots[2].cells[1])
    assert.same({ "Player-1-0001", "Player-1-0001", "Player-2-0002" }, detail)
    assert.equals("Player-2-0002", ns.UI.selectedGuid)
  end)

  it("row click without the detail module does not error", function()
    ns.Detail = nil
    local grid = open()
    click(grid.slots[1].left)
    assert.equals("Player-1-0001", ns.UI.selectedGuid)
    assert.equals("Player-1-0001", grid.selected)
    click(grid.slots[1].left)
    assert.is_nil(ns.UI.selectedGuid)
  end)

  it("detail panel keeps the grid selection in step", function()
    local grid = open()
    local function selected() return grid.slots[2].left.deco.selected:IsShown() end
    click(grid.slots[2].left)  -- Jaina
    local panel = ns.Detail.panel
    assert.is_true(panel:IsShown())
    assert.equals("Player-2-0002", ns.UI.selectedGuid)
    assert.equals("Player-2-0002", grid.selected)
    assert.is_true(selected())

    -- the panel's own close button clears the selection
    click(panel.close)
    assert.is_false(panel:IsShown())
    assert.is_nil(ns.UI.selectedGuid)
    assert.is_nil(grid.selected)
    assert.is_false(selected())

    -- the same row reopens it (no stale toggle state), and a second click closes it
    click(grid.slots[2].left)
    assert.is_true(panel:IsShown())
    assert.equals("Player-2-0002", grid.selected)
    click(grid.slots[2].cells[1])
    assert.is_false(panel:IsShown())
    assert.is_nil(grid.selected)

    -- forgetting the shown character closes the panel and drops the selection
    click(grid.slots[2].left)
    StaticPopupDialogs.LOCKOUT_FORGET.OnAccept(nil, "Player-2-0002")
    assert.is_false(panel:IsShown())
    assert.is_nil(ns.UI.selectedGuid)
    assert.is_nil(grid.selected)
    assert.equals(27, #grid.rows)
  end)

  it("lays out the grid on first show without a size event", function()
    ns.UI:Show()
    local grid = ns.UI.grid
    assert.truthy(grid.width > 0 and grid.height > 0)
    assert.truthy(#grid.slots > 0)
    assert.equals("Thrall", grid.slots[1].name:GetText())
  end)

  it("switching column sets scrolls back to the first column", function()
    local grid = ns.Grid.New(UIParent)
    -- Behave like the client slider: SetMinMaxValues clamps the value and reports the change.
    local hbar = grid.hbar
    hbar.SetMinMaxValues = function(self, lo, hi)
      self.lo, self.hi = lo, hi
      local v = self:GetValue()
      local clamped = math.max(lo, math.min(hi, v))
      if clamped ~= v then
        self:SetValue(clamped)
        self:GetScript("OnValueChanged")(self, clamped)
      end
    end
    local function cols(prefix, n)
      local out = {}
      for i = 1, n do out[i] = { key = prefix .. i, label = prefix .. i, width = 80 } end
      return out
    end
    grid:SetRows({})
    grid:Layout(400, 300)          -- data view is 400 - 2 - 190 - 8 = 200 wide
    grid:SetColumns(cols("a", 10)) -- 800 wide: max offset 600
    grid:Refresh()
    grid:ScrollHorizontal(500)
    assert.equals(500, hbar:GetValue())

    grid:SetColumns(cols("b", 6))  -- 480 wide: max offset 280, below the old value
    grid:Refresh()
    assert.equals(0, grid.hoffset)
    assert.equals(0, hbar:GetValue())
    assert.equals(0, grid.scroll:GetHorizontalScroll())
    assert.equals(280, hbar.hi)

    -- the same column keys keep the scroll position
    grid:ScrollHorizontal(100)
    grid:SetColumns(cols("b", 6))
    grid:Refresh()
    assert.equals(100, grid.hoffset)
  end)

  it("cell hover shows the cell tooltip", function()
    local grid = open()
    local cell = grid.slots[1].cells[1]
    cell:GetScript("OnEnter")(cell)
    assert.equals("Alpha Keep", tooltipLines[1])
    assert.equals("Heroic | resets in 1d 0h", tooltipLines[2])
    assert.equals("Boss1 | Killed", tooltipLines[3])
    assert.equals(10, #tooltipLines)
    cell:GetScript("OnLeave")(cell)
  end)

  it("tab buttons select their tab", function()
    local grid = open()
    click(ns.UI.tabButtons.Weekly)
    assert.equals("Weekly", ns.UI.selectedTab)
    assert.equals(7, #grid.columns)
  end)

  it("DATA_UPDATED refreshes only while shown", function()
    local grid = open()
    ns.db.characters["Player-1-0001"].meta.name = "Go'el"
    ns.Fire("DATA_UPDATED", "Character")
    assert.equals("Go'el", grid.slots[1].name:GetText())
    LockoutMainFrame:Hide()
    ns.db.characters["Player-1-0001"].meta.name = "Thrall"
    ns.Fire("DATA_UPDATED", "Character")
    assert.equals("Go'el", grid.slots[1].name:GetText())
    for _, line in ipairs(ns.log) do assert.is_nil(line:find("callback failed", 1, true)) end
  end)

  it("slash command toggles the window", function()
    SlashCmdList.LOCKOUT("")
    assert.is_true(LockoutMainFrame:IsShown())
    SlashCmdList.LOCKOUT("")
    assert.is_false(LockoutMainFrame:IsShown())
    SlashCmdList.LOCKOUT("")
    assert.is_true(LockoutMainFrame:IsShown())
  end)

  it("saves the window after moving and sizing and restores it", function()
    ns.db.settings.scale = 1.2
    open()
    local frame = ns.UI.frame
    assert.equals(1.2, frame:GetScale())
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 40, 500)
    ns.UI.titleBar:GetScript("OnDragStop")(ns.UI.titleBar)
    assert.same({ point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 40, y = 500, w = 900, h = 460 },
      ns.db.settings.window)

    frame:SetSize(700, 350)
    ns.UI.grip:GetScript("OnMouseUp")(ns.UI.grip)
    assert.equals(700, ns.db.settings.window.w)
    assert.equals(350, ns.db.settings.window.h)

    -- a fresh session restores it
    local saved = ns.db
    ns = loader.load(nil, install)
    ns.DB:Init(saved)
    ns.UI:Show()
    assert.equals(700, ns.UI.frame:GetWidth())
    assert.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 40, 500 }, { ns.UI.frame:GetPoint(1) })
  end)

  it("settings cog only when the settings module exists", function()
    ns.Settings = nil
    open()
    assert.is_nil(ns.UI.cog)

    local opened = 0
    ns = loader.load(nil, install)
    ns.DB:Init(nil)
    ns.Settings = { Open = function() opened = opened + 1 end }
    ns.UI:Show()
    click(ns.UI.cog)
    assert.equals(1, opened)
  end)

  it("class colors are nil safe", function()
    assert.same({ 0, 0.44, 0.87 }, { ns.Theme.ClassColor("SHAMAN") })
    assert.same({ 1, 1, 1 }, { ns.Theme.ClassColor("MAGE") })
    assert.same({ 1, 1, 1 }, { ns.Theme.ClassColor(nil) })
    C_ClassColor = nil
    assert.same({ 1, 1, 1 }, { ns.Theme.ClassColor("SHAMAN") })
  end)

  it("tab cell colors come from the theme", function()
    assert.equals(ns.Theme.green, ns.Rows.COLORS.green)
    assert.equals(ns.Theme.yellow, ns.Rows.COLORS.yellow)
  end)
end)

describe("Minimap and Settings", function()
  local ns, settingsLog

  -- A recording stand-in for the Blizzard Settings API.
  local function installSettings()
    settingsLog = { settings = {}, widgets = {} }
    Settings = {
      VarType = { Number = "number", Boolean = "boolean" },
      RegisterVerticalLayoutCategory = function(name)
        settingsLog.name = name
        return { GetID = function() return 77 end }
      end,
      RegisterAddOnSetting = function(_, variable, key, tbl, varType, label, default)
        local setting = { key = key, tbl = tbl, varType = varType, label = label, default = default }
        function setting:SetValueChangedCallback(fn) self.callback = fn end
        function setting:Set(value)
          self.tbl[self.key] = value
          self.callback(self, value)
        end
        settingsLog.settings[variable] = setting
        return setting
      end,
      CreateSliderOptions = function(min, max, step)
        return { min = min, max = max, step = step, SetLabelFormatter = function() end }
      end,
      CreateSlider = function(_, setting, options) settingsLog.widgets[setting.key] = options end,
      CreateCheckbox = function(_, setting) settingsLog.widgets[setting.key] = "checkbox" end,
      RegisterAddOnCategory = function() settingsLog.registered = true end,
      OpenToCategory = function(id) settingsLog.opened = id end,
    }
  end

  local function load(extra)
    ns = loader.load(nil, function()
      install()
      if extra then extra() end
    end)
    ns.DB:Init(nil)
    seed(ns.db, mock.now)
    return ns
  end

  local function tooltipFor()
    local lines = {}
    ns.Minimap.FillTooltip({ AddLine = function(_, text) lines[#lines + 1] = text end })
    return lines
  end

  it("summary counts ready and best key", function()
    local n = load()
    local now = mock.now
    n.db.characters = {
      a = { meta = { name = "Aria", level = 80 },
        vault = { resetAt = now + 100, unclaimed = true, activities = {} },
        mythicPlus = { resetAt = now + 100, key = { challengeMapID = 501, level = 10 } } },
      b = { meta = { name = "Bram", level = 80 },
        vault = { resetAt = now + 100, unclaimed = false, activities = {} },
        mythicPlus = { resetAt = now + 100, key = { challengeMapID = 502, level = 12 } } },
      -- expired key and below the minimum level: neither counts
      c = { meta = { name = "Cleo", level = 80 }, mythicPlus = { resetAt = now - 1, key = { challengeMapID = 503, level = 15 } } },
      d = { meta = { name = "Dale", level = 5 }, mythicPlus = { resetAt = now + 100, key = { challengeMapID = 504, level = 20 } } },
    }
    local summary = n.Minimap.Summary(n.db, now)
    assert.equals(1, summary.ready)
    assert.same({ level = 12, challengeMapID = 502, label = "Bram" }, summary.bestKey)

    n.db.characters = { a = { meta = { name = "Aria", level = 80 } } }
    summary = n.Minimap.Summary(n.db, now)
    assert.equals(0, summary.ready)
    assert.is_nil(summary.bestKey)
  end)

  it("loads without the minimap libraries or the Settings API", function()
    local n = load()
    n.Fire("DB_READY")
    local found = false
    for _, line in ipairs(n.log) do
      assert.is_nil(line:find("callback failed", 1, true))
      if line == "minimap libs missing" then found = true end
    end
    assert.is_true(found)
    assert.is_nil(n.Minimap.icon)
    n.Minimap.Apply()
    n.Settings:Open()
    SlashCmdList.LOCKOUT("config")
  end)

  it("config opens the settings category", function()
    local n = load(installSettings)
    n.Fire("DB_READY")
    assert.equals("Lockout", settingsLog.name)
    assert.is_true(settingsLog.registered)
    SlashCmdList.LOCKOUT("config")
    assert.equals(77, settingsLog.opened)
  end)

  it("settings write through and refresh the window", function()
    local n = load(installSettings)
    n.Fire("DB_READY")
    local min, scale = settingsLog.widgets.minLevel, settingsLog.widgets.scale
    assert.same({ 1, 90, 1 }, { min.min, min.max, min.step })
    assert.same({ 0.7, 1.5, 0.05 }, { scale.min, scale.max, scale.step })
    assert.equals("checkbox", settingsLog.widgets.showLegacy)

    n.UI:Show()
    local grid = n.UI.grid
    grid.frame:GetScript("OnSizeChanged")(grid.frame, 800, 400)
    assert.equals(28, #grid.rows)

    settingsLog.settings.Lockout_MinLevel:Set(81)
    assert.equals(81, n.db.settings.minLevel)
    assert.equals(1, #grid.rows) -- only the logged-in character is exempt from the level filter

    settingsLog.settings.Lockout_Scale:Set(1.25)
    assert.equals(1.25, n.db.settings.scale)
    assert.equals(1.25, n.UI.frame:GetScale())

    settingsLog.settings.Lockout_ShowLegacy:Set(false)
    assert.is_false(n.db.settings.showLegacy)
    for _, line in ipairs(n.log) do assert.is_nil(line:find("callback failed", 1, true)) end
  end)

  it("minimap checkbox inverts the saved hide flag", function()
    local shown = {}
    local n = load(function()
      installSettings()
      LibStub = function(name)
        if name == "LibDataBroker-1.1" then
          return { NewDataObject = function(_, _, obj) return obj end }
        end
        return {
          Register = function() end,
          Show = function(_, iconName) shown[#shown + 1] = "show " .. iconName end,
          Hide = function(_, iconName) shown[#shown + 1] = "hide " .. iconName end,
        }
      end
    end)
    n.Fire("DB_READY")
    local box = settingsLog.settings.Lockout_ShowMinimap
    assert.is_false(n.db.settings.minimap.hide)
    assert.is_true(box.tbl[box.key]) -- shown

    box:Set(false)
    assert.is_true(n.db.settings.minimap.hide)
    box:Set(true)
    assert.is_false(n.db.settings.minimap.hide)
    assert.same({ "hide Lockout", "show Lockout" }, shown)
  end)

  it("registers a launcher with click handlers and a tooltip", function()
    local created, registered
    local n = load(function()
      installSettings()
      LibStub = function(name)
        if name == "LibDataBroker-1.1" then
          return { NewDataObject = function(_, objName, obj) created = { name = objName, obj = obj }; return obj end }
        end
        return { Register = function(_, regName, obj, db) registered = { name = regName, obj = obj, db = db } end }
      end
    end)
    n.Fire("DB_READY")
    assert.equals("Lockout", created.name)
    assert.equals("launcher", created.obj.type)
    assert.equals("Interface\\Icons\\INV_Misc_Key_14", created.obj.icon)
    assert.equals("Lockout", registered.name)
    assert.equals(n.db.settings.minimap, registered.db)

    created.obj.OnClick(nil, "LeftButton")
    assert.is_true(LockoutMainFrame:IsShown())
    created.obj.OnClick(nil, "LeftButton")
    assert.is_false(LockoutMainFrame:IsShown())
    created.obj.OnClick(nil, "RightButton")
    assert.equals(77, settingsLog.opened)

    -- Thrall holds the only key (+12 Crypt) and the only vault is not ready
    local lines = {}
    created.obj.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
    assert.same({ "Lockout", "Vault ready: 0 characters", "Highest key: +12 Crypt (Thrall)" }, lines)
  end)

  it("tooltip omits the key line when nobody has one", function()
    local n = load()
    n.db.characters["Player-1-0001"].mythicPlus = nil
    assert.same({ "Lockout", "Vault ready: 0 characters" }, tooltipFor())
  end)
end)

