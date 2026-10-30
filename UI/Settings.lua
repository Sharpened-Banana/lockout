local _, ns = ...

-- Blizzard Settings panel (Options > AddOns > Lockout).
local Settings_ = {}
ns.Settings = Settings_

local category

local function refresh()
  if ns.UI then ns.UI:Refresh() end
end

local function available()
  return Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
end

local function addSetting(variable, key, tbl, varType, label, default, onChange)
  local setting = Settings.RegisterAddOnSetting(category, variable, key, tbl, varType, label, default)
  setting:SetValueChangedCallback(function(_, value)
    if onChange then onChange(value) end
    refresh()
  end)
  return setting
end

local function addSlider(variable, key, label, tip, default, min, max, step)
  local setting = addSetting(variable, key, ns.db.settings, Settings.VarType.Number, label, default)
  local options = Settings.CreateSliderOptions(min, max, step)
  local fmt = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
  if fmt and options.SetLabelFormatter then options:SetLabelFormatter(fmt.Right) end
  Settings.CreateSlider(category, setting, options, tip)
end

local function addCheckbox(variable, key, tbl, label, tip, default, onChange)
  local setting = addSetting(variable, key, tbl, Settings.VarType.Boolean, label, default, onChange)
  Settings.CreateCheckbox(category, setting, tip)
end

local function register()
  if category then return end
  if not available() then
    ns.Log("settings API missing")
    return
  end
  local s = ns.db.settings
  category = Settings.RegisterVerticalLayoutCategory("Lockout")

  addSlider("Lockout_MinLevel", "minLevel", "Minimum character level",
    "Characters below this level are hidden.", 10, 1, 90, 1)
  addCheckbox("Lockout_ShowLegacy", "showLegacy", s, "Show other saved instances",
    "Include lockouts that are not part of the current season.", false)
  addSlider("Lockout_Scale", "scale", "Window scale", "Size of the Lockout window.", 1, 0.7, 1.5, 0.05)

  -- The saved flag is "hide"; the checkbox reads "show".
  local proxy = setmetatable({}, {
    __index = function() return not s.minimap.hide end,
    __newindex = function(_, _, show) s.minimap.hide = not show end,
  })
  addCheckbox("Lockout_ShowMinimap", "show", proxy, "Show minimap button",
    "Show the Lockout button on the minimap.", true, function() ns.Minimap.Apply() end)

  Settings.RegisterAddOnCategory(category)
end

function Settings_.Open()
  if not category then
    ns.Log("settings unavailable")
    return
  end
  Settings.OpenToCategory(category:GetID())
end

ns.On("DB_READY", register)
ns.RegisterSlash("config", function() Settings_:Open() end)
