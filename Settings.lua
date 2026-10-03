-- Settings.lua
-- Two-tab settings window (Monitored Zones + Settings), minimap icon and the
-- /flc slash command.
--
--   +-----------------------------------------------+
--   |  [logo] Forever Logs Companion                |
--   |         v0.x · subtitle                       |
--   +-----------+-----------------------------------+
--   |  Zones     |                                   |
--   |  Settings  |   <active tab content>            |
--   +-----------+-----------------------------------+
--   |   /flc status footer                          |
--   +-----------------------------------------------+

local ADDON, FLC = ...
local UI = {}
FLC.UI = UI

local SLASH = "flc"

local function cfg() return FLC.db end

-- Registry of all checkboxes + their getters, used by refreshCheckboxes()
-- to re-sync state when the window reopens or a slash command flips a value.
UI.checkboxRefs = {}

local function makeCheckbox(parent, label, x, y, getFn, setFn)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb:SetSize(24, 24)
  local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
  text:SetText(label)
  cb:SetChecked(getFn())
  cb:SetScript("OnClick", function(self)
    setFn(self:GetChecked() and true or false)
  end)
  cb.label = text
  table.insert(UI.checkboxRefs, { cb = cb, getFn = getFn })
  return cb
end

function UI.refreshCheckboxes()
  for _, e in ipairs(UI.checkboxRefs) do
    e.cb:SetChecked(e.getFn() and true or false)
  end
end

-- Grey out dependent toggles (silent/dungeons/raids when auto is off) so it
-- is obvious they have no effect.
local function setCheckboxEnabled(cb, helpText, enabled)
  if enabled then
    cb:Enable()
    cb.label:SetTextColor(1, 0.82, 0)
    if helpText then helpText:SetTextColor(0.55, 0.55, 0.55) end
  else
    cb:Disable()
    cb.label:SetTextColor(0.5, 0.42, 0.18)
    if helpText then helpText:SetTextColor(0.35, 0.35, 0.35) end
  end
end

local function makeHelp(parent, anchor, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 29, -2)
  fs:SetWidth(340)
  fs:SetJustifyH("LEFT")
  fs:SetText("|cff888888" .. text .. "|r")
  return fs
end

local function currentZoneName()
  local zone = FLC.currentZone()
  if zone == "" then return "Unknown" end
  return zone
end

local function makeTab(parent, label, x, y, onClick)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(148, 28)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  btn:EnableMouse(true)

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
  bg:SetColorTexture(0, 0, 0, 0)
  btn.bg = bg

  local accent = btn:CreateTexture(nil, "OVERLAY")
  accent:SetSize(3, 22)
  accent:SetPoint("LEFT", btn, "LEFT", 0, 0)
  accent:SetColorTexture(0.31, 0.76, 1.0, 0)
  btn.accent = accent

  local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", btn, "LEFT", 12, 0)
  text:SetText(label)
  btn.text = text

  btn:SetScript("OnEnter", function(self)
    if not self.isActive then self.bg:SetColorTexture(1, 1, 1, 0.05) end
  end)
  btn:SetScript("OnLeave", function(self)
    if not self.isActive then self.bg:SetColorTexture(0, 0, 0, 0) end
  end)
  btn:SetScript("OnClick", onClick)
  return btn
end

local function activateTab(active, allTabs)
  for _, t in ipairs(allTabs) do
    if t == active then
      t.isActive = true
      t.bg:SetColorTexture(0.31, 0.76, 1.0, 0.12)
      t.accent:SetColorTexture(0.31, 0.76, 1.0, 1)
      t.text:SetTextColor(1, 1, 1, 1)
    else
      t.isActive = false
      t.bg:SetColorTexture(0, 0, 0, 0)
      t.accent:SetColorTexture(0.31, 0.76, 1.0, 0)
      t.text:SetTextColor(0.65, 0.65, 0.65, 1)
    end
  end
end

function UI.create()
  if UI.frame then return UI.frame end
  local f = CreateFrame("Frame", "ForeverLogsCompanion_SettingsFrame", UIParent, "BackdropTemplate")
  f:SetSize(580, 600)
  f:SetPoint("CENTER")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("DIALOG")
  f:Hide()
  -- Escape closes it, like any Blizzard panel.
  table.insert(UISpecialFrames, f:GetName())

  -- ---------- Header ----------
  local logo = f:CreateTexture(nil, "OVERLAY")
  logo:SetTexture(FLC.ICON)
  logo:SetSize(48, 48)
  logo:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -14)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", logo, "RIGHT", 10, 6)
  title:SetText("|cff66ccffForever Logs Companion|r")

  local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  subtitle:SetText("|cff888888v" .. FLC.VERSION .. "  ·  Auto /combatlog for Forever Logs|r")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

  local divider = f:CreateTexture(nil, "OVERLAY")
  divider:SetSize(540, 1)
  divider:SetPoint("TOP", f, "TOP", 0, -76)
  divider:SetColorTexture(0.4, 0.4, 0.4, 0.5)

  -- ---------- Sidebar ----------
  local sidebar = CreateFrame("Frame", nil, f)
  sidebar:SetSize(140, 480)
  sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -86)

  local vDivider = f:CreateTexture(nil, "OVERLAY")
  vDivider:SetSize(1, 470)
  vDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
  vDivider:SetColorTexture(0.4, 0.4, 0.4, 0.5)

  -- ---------- Settings page ----------
  local settingsPage = CreateFrame("Frame", nil, f)
  settingsPage:SetSize(388, 480)
  settingsPage:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 16, 0)

  local function sectionHeader(text, y)
    local h = settingsPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", settingsPage, "TOPLEFT", 4, y)
    h:SetText("|cffffd200" .. text .. "|r")
    local underline = settingsPage:CreateTexture(nil, "OVERLAY")
    underline:SetSize(360, 1)
    underline:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -3)
    underline:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    return h
  end

  local silentCb, silentHelp, dungeonsCb, dungeonsHelp, raidsCb, raidsHelp
  local refreshDependents

  -- ============== LOGGING ==============
  sectionHeader("LOGGING", -4)

  local autoCb = makeCheckbox(settingsPage, "Auto /combatlog on raid/dungeon zone entry", 4, -28,
    function() return cfg().auto_combatlog end,
    function(v)
      cfg().auto_combatlog = v
      if refreshDependents then refreshDependents() end
    end)
  makeHelp(settingsPage, autoCb,
    "On zone entry, a popup asks if you want to start /combatlog. On exit, a popup asks if you want to stop.")

  silentCb = makeCheckbox(settingsPage, "Silent auto-logging (skip start/stop prompts)", 4, -82,
    function() return cfg().silent end,
    function(v) cfg().silent = v end)
  silentHelp = makeHelp(settingsPage, silentCb,
    "Starts /combatlog silently on zone entry. Never auto-stops. Manually toggle /combatlog to stop.")

  dungeonsCb = makeCheckbox(settingsPage, "Log 5-man dungeons", 4, -126,
    function() return cfg().log_dungeons end,
    function(v)
      cfg().log_dungeons = v
      -- Apply where the player is standing right now.
      FLC.check(false)
    end)
  dungeonsHelp = makeHelp(settingsPage, dungeonsCb,
    "When off, 5-man dungeons are skipped. Raids and world bosses still log.")

  raidsCb = makeCheckbox(settingsPage, "Log raids and world bosses", 4, -170,
    function() return cfg().log_raids end,
    function(v)
      cfg().log_raids = v
      FLC.check(false)
    end)
  raidsHelp = makeHelp(settingsPage, raidsCb,
    "When off, raid instances and world-boss zones are skipped. Dungeons still log.")

  -- ============== INTERFACE ==============
  sectionHeader("INTERFACE", -224)

  makeCheckbox(settingsPage, "Show minimap icon", 4, -248,
    function() return not cfg().minimap_button.hide end,
    function(v)
      if v then FLC.Minimap.show() else FLC.Minimap.hide() end
    end)

  makeCheckbox(settingsPage, "Debug mode (verbose chat logging)", 4, -276,
    function() return cfg().debug end,
    function(v) cfg().debug = v end)

  -- silent + the two content gates are no-ops when auto is off.
  refreshDependents = function()
    local autoOn = cfg().auto_combatlog and true or false
    setCheckboxEnabled(silentCb, silentHelp, autoOn)
    setCheckboxEnabled(dungeonsCb, dungeonsHelp, autoOn)
    setCheckboxEnabled(raidsCb, raidsHelp, autoOn)
    if not autoOn then silentCb:SetChecked(false) end
  end
  refreshDependents()
  UI.refreshDependents = refreshDependents

  -- ---------- Monitored Zones page ----------
  local zonesPage = CreateFrame("Frame", nil, f)
  zonesPage:SetSize(388, 480)
  zonesPage:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 16, 0)

  local zoneRow = zonesPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  zoneRow:SetPoint("TOPLEFT", zonesPage, "TOPLEFT", 4, -8)
  zoneRow:SetText("Current zone:")

  local zoneText = zonesPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  zoneText:SetPoint("LEFT", zoneRow, "RIGHT", 6, 0)
  zoneText:SetText(currentZoneName())
  UI.zoneText = zoneText

  local addCurrent = CreateFrame("Button", nil, zonesPage, "UIPanelButtonTemplate")
  addCurrent:SetSize(110, 22)
  addCurrent:SetPoint("TOPRIGHT", zonesPage, "TOPRIGHT", -4, -4)
  addCurrent:SetText("Add Current")
  addCurrent:SetScript("OnClick", function()
    local zone = currentZoneName()
    if zone ~= "Unknown" then
      cfg().monitored_zones[zone] = true
      UI.refreshZones()
      FLC.say("Monitoring zone: " .. zone)
      FLC.check(false)
    end
  end)

  local zonesHelp = zonesPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  zonesHelp:SetPoint("TOPLEFT", zoneRow, "BOTTOMLEFT", 0, -8)
  zonesHelp:SetWidth(380)
  zonesHelp:SetJustifyH("LEFT")
  zonesHelp:SetText("|cff888888Entering one of these auto-starts /combatlog (when 'Auto /combatlog' is on). Removed zones stay removed across sessions.|r")

  local scrollFrame = CreateFrame("ScrollFrame", "ForeverLogsCompanion_ZoneScroll", zonesPage, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", zonesHelp, "BOTTOMLEFT", 0, -6)
  scrollFrame:SetSize(340, 300)

  local content = CreateFrame("Frame", nil, scrollFrame)
  content:SetSize(340, 300)
  scrollFrame:SetScrollChild(content)
  UI.zoneListContent = content

  local addLabel = zonesPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  addLabel:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 0, -10)
  addLabel:SetText("Add zone:")

  local addEdit = CreateFrame("EditBox", "ForeverLogsCompanion_AddZone", zonesPage, "InputBoxTemplate")
  addEdit:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
  addEdit:SetSize(180, 20)
  addEdit:SetAutoFocus(false)
  local function commit()
    local v = strtrim(addEdit:GetText() or "")
    if v ~= "" then
      cfg().monitored_zones[v] = true
      addEdit:SetText("")
      UI.refreshZones()
      FLC.say("Monitoring zone: " .. v)
      FLC.check(false)
    end
    addEdit:ClearFocus()
  end
  addEdit:SetScript("OnEnterPressed", commit)
  addEdit:SetScript("OnEscapePressed", function() addEdit:ClearFocus() end)

  local addBtn = CreateFrame("Button", nil, zonesPage, "UIPanelButtonTemplate")
  addBtn:SetSize(60, 22)
  addBtn:SetPoint("LEFT", addEdit, "RIGHT", 6, 0)
  addBtn:SetText("Add")
  addBtn:SetScript("OnClick", commit)

  local restoreBtn = CreateFrame("Button", nil, zonesPage, "UIPanelButtonTemplate")
  restoreBtn:SetSize(170, 22)
  restoreBtn:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -10)
  restoreBtn:SetText("Restore Default Zones")
  restoreBtn:SetScript("OnClick", function()
    local restored = FLC.restoreDefaultZones()
    UI.refreshZones()
    FLC.say("Restored " .. restored .. " default zone(s). Zones you added yourself were kept.")
  end)

  -- ---------- Tabs (Monitored Zones first, it is opened most) ----------
  local tabZones, tabSettings
  local allTabs = {}
  tabZones = makeTab(sidebar, "Monitored Zones", 0, -4, function()
    activateTab(tabZones, allTabs)
    zonesPage:Show()
    settingsPage:Hide()
  end)
  tabSettings = makeTab(sidebar, "Settings", 0, -36, function()
    activateTab(tabSettings, allTabs)
    settingsPage:Show()
    zonesPage:Hide()
  end)
  allTabs = { tabZones, tabSettings }

  function UI.openTab(name)
    if name == "settings" then
      activateTab(tabSettings, allTabs)
      settingsPage:Show()
      zonesPage:Hide()
    else
      activateTab(tabZones, allTabs)
      zonesPage:Show()
      settingsPage:Hide()
    end
  end
  UI.openTab("zones")

  -- ---------- Footer ----------
  local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
  status:SetText("|cffaaaaaaType|r /" .. SLASH .. " status |cffaaaaaain chat for the current logging state|r")

  UI.frame = f
  UI.zoneRows = {}
  return f
end

-- Rebuild the scrollable zone list from monitored_zones.
function UI.refreshZones()
  if not UI.zoneListContent then return end
  for _, row in ipairs(UI.zoneRows or {}) do
    row:Hide()
    row:SetParent(nil)
  end
  UI.zoneRows = {}

  local zones = {}
  for z, on in pairs(cfg().monitored_zones) do
    if on then zones[#zones + 1] = z end
  end
  table.sort(zones)

  local y = -2
  for _, zone in ipairs(zones) do
    local row = CreateFrame("Frame", nil, UI.zoneListContent)
    row:SetSize(340, 20)
    row:SetPoint("TOPLEFT", UI.zoneListContent, "TOPLEFT", 4, y)

    local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("LEFT", row, "LEFT", 4, 0)
    txt:SetText(zone)
    txt:SetJustifyH("LEFT")
    txt:SetWidth(290)

    local rm = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    rm:SetSize(22, 22)
    rm:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    local zoneCaptured = zone
    rm:SetScript("OnClick", function()
      -- false, not nil: login re-seeds every default whose key is nil, so a
      -- deleted key would come back. "Restore Default Zones" is the way back.
      cfg().monitored_zones[zoneCaptured] = false
      UI.refreshZones()
      FLC.say("Stopped monitoring zone: " .. zoneCaptured)
    end)

    UI.zoneRows[#UI.zoneRows + 1] = row
    y = y - 22
  end

  UI.zoneListContent:SetHeight(math.max(300, math.abs(y) + 4))
end

local function refreshAll()
  if UI.zoneText then UI.zoneText:SetText(currentZoneName()) end
  UI.refreshZones()
  UI.refreshCheckboxes()
  if UI.refreshDependents then UI.refreshDependents() end
end

function UI.toggle()
  local f = UI.create()
  if f:IsShown() then
    f:Hide()
  else
    refreshAll()
    f:Show()
  end
end

function UI.open(tab)
  local f = UI.create()
  UI.openTab(tab)
  refreshAll()
  f:Show()
end

-- Keep "Current zone:" live while the window is open.
FLC.onZoneChecked = function()
  if UI.frame and UI.frame:IsShown() and UI.zoneText then
    UI.zoneText:SetText(currentZoneName())
  end
end

-- ---------- Minimap icon (LibDBIcon) ----------
local M = {}
FLC.Minimap = M
local LDB_NAME = ADDON

local function buildTooltip(tt)
  tt:AddLine("|cff66ccffForever Logs Companion|r")
  tt:AddLine("v" .. FLC.VERSION, 0.7, 0.7, 0.7)
  tt:AddLine(" ")
  tt:AddDoubleLine("/combatlog",
    FLC.isLogging() and "|cff33ff33RECORDING|r" or "|cff888888off|r", 1, 1, 1)
  tt:AddDoubleLine("Advanced Combat Logging",
    GetCVar("advancedCombatLogging") == "1" and "|cff33ff33on|r" or "|cffff5555off|r", 1, 1, 1)
  tt:AddLine(" ")
  tt:AddLine("|cffaaaaaaClick:|r open settings")
  tt:AddLine("|cffaaaaaaDrag:|r reposition")
end

function M.start()
  local LibStub = _G.LibStub
  local LDB  = LibStub and LibStub("LibDataBroker-1.1", true)
  local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not LDB or not Icon then return end

  local launcher = LDB:GetDataObjectByName(LDB_NAME) or LDB:NewDataObject(LDB_NAME, {
    type = "launcher",
    text = "Forever Logs",
    icon = FLC.MEDIA_PATH .. "flame-32.tga",
    OnClick = function() UI.toggle() end,
    OnTooltipShow = buildTooltip,
  })
  if not Icon:IsRegistered(LDB_NAME) then
    Icon:Register(LDB_NAME, launcher, cfg().minimap_button)
  else
    Icon:Refresh(LDB_NAME, cfg().minimap_button)
  end
  -- Retail-style addon compartment, where the client has one.
  if Icon.AddButtonToCompartment and not (Icon.IsButtonInCompartment and Icon:IsButtonInCompartment(LDB_NAME)) then
    pcall(Icon.AddButtonToCompartment, Icon, LDB_NAME)
  end
end

function M.hide()
  cfg().minimap_button.hide = true
  local Icon = _G.LibStub and LibStub("LibDBIcon-1.0", true)
  if Icon then Icon:Hide(LDB_NAME) end
  FLC.say("Minimap icon hidden. Turn it back on from /" .. SLASH .. " settings.")
end

function M.show()
  cfg().minimap_button.hide = false
  local Icon = _G.LibStub and LibStub("LibDBIcon-1.0", true)
  if Icon then Icon:Show(LDB_NAME) end
end

FLC.onLoaded = function() M.start() end

-- ---------- Slash command ----------
local function onOff(v) return v and "|cff00ff00On|r" or "|cffaaaaaaOff|r" end

local function printHelp()
  local s = "/" .. SLASH
  FLC.say("commands:")
  print("  |cffffd200" .. s .. "|r              open window")
  print("  |cffffd200" .. s .. " settings|r     open window on Settings tab")
  print("  |cffffd200" .. s .. " zones|r        open window on Monitored Zones tab")
  print("  |cffffd200" .. s .. " status|r       show current state")
  print("  |cffffd200" .. s .. " trace [n]|r    why it did or didn't start logging")
end

SLASH_FOREVERLOGSCOMPANION1 = "/" .. SLASH
SLASH_FOREVERLOGSCOMPANION2 = "/foreverlogs"
SlashCmdList["FOREVERLOGSCOMPANION"] = function(msg)
  if not cfg() then return end
  msg = msg or ""
  local parts = {}
  for w in msg:gmatch("%S+") do parts[#parts + 1] = w end
  local cmd = (parts[1] or ""):lower()

  if cmd == "" or cmd == "gui" then
    UI.toggle()

  elseif cmd == "settings" or cmd == "zones" then
    UI.open(cmd)

  elseif cmd == "status" then
    local c = cfg()
    FLC.say("v" .. FLC.VERSION)
    print("Current zone: |cffe8e8e8" .. currentZoneName() .. "|r   /combatlog: " .. onOff(FLC.isLogging())
      .. " |cff888888(client reports " .. (FLC.clientReportsLogging() and "on" or "off") .. ")|r")
    print("Auto-log on zone entry: " .. onOff(c.auto_combatlog)
      .. "   Silent: " .. onOff(c.silent)
      .. "   Raids: " .. onOff(c.log_raids)
      .. "   Dungeons: " .. onOff(c.log_dungeons))
    print("Advanced Combat Logging: " .. onOff(GetCVar("advancedCombatLogging") == "1"))

  elseif cmd == "probe" then
    -- Why did /combatlog not start? Records everything that could block it,
    -- tries LoggingCombat(true), and re-reads the state over a few seconds.
    -- Saved to ForeverLogsCompanionDB.probes so it can be read after /reload.
    local p = { at = date("%Y-%m-%d %H:%M:%S"), zone = currentZoneName() }
    local inInst, itype = IsInInstance()
    p.inInstance, p.instanceType = inInst and true or false, tostring(itype)
    p.combatLockdown = InCombatLockdown() and true or false
    p.acl = GetCVar("advancedCombatLogging")
    p.loggingBefore = FLC.isLogging()
    p.slashCombatlog = type(SlashCmdList["COMBATLOG"])
    p.restrictions = {}
    local RA = _G.C_RestrictedActions
    if type(RA) == "table" and type(RA.GetAddOnRestrictionState) == "function"
        and Enum and Enum.AddOnRestrictionType then
      for name, id in pairs(Enum.AddOnRestrictionType) do
        local ok, st = pcall(RA.GetAddOnRestrictionState, id)
        p.restrictions[name] = ok and tostring(st) or ("err: " .. tostring(st))
      end
    else
      p.restrictions.api = "C_RestrictedActions.GetAddOnRestrictionState missing"
    end
    -- What the zone check sees, and the addon's own logging state, taken
    -- BEFORE the test call below changes anything.
    local D = FLC.describe
    local version, build = GetBuildInfo()
    p.build = tostring(version) .. "." .. tostring(build)
    local iname, itype2, diff, diffName, _, _, _, mapId = GetInstanceInfo()
    p.instanceInfo = table.concat({ D(iname), D(itype2), D(diff), D(diffName), D(mapId) }, " | ")
    p.zoneText = D(GetZoneText())
    p.listed = tostring(FLC.listState(currentZoneName()))
    p.clientBefore = FLC.clientReportsLogging()
    p.flags = "last=" .. tostring(FLC.lastLoggedZone) .. " ours=" .. tostring(FLC.startedByUs)
      .. " asked=" .. tostring(FLC.popupShownForZone) .. " pending=" .. tostring(FLC.pendingZone)

    local ok, r1 = pcall(LoggingCombat, true)
    p.callOk, p.callReturn = ok, tostring(r1)
    p.loggingImmediately = FLC.isLogging()

    local db = cfg()
    db.probes = db.probes or {}
    table.insert(db.probes, p)
    while #db.probes > 10 do table.remove(db.probes, 1) end

    FLC.say("probe in " .. p.zone .. " (" .. p.instanceType .. "), in combat: " .. tostring(p.combatLockdown))
    print("  logging before: " .. tostring(p.loggingBefore) .. "   ACL cvar: " .. tostring(p.acl)
      .. "   /combatlog handler: " .. p.slashCombatlog)
    local rs = {}
    for k, v in pairs(p.restrictions) do rs[#rs + 1] = k .. "=" .. v end
    table.sort(rs)
    print("  restrictions: " .. table.concat(rs, ", "))
    print("  client " .. p.build .. "   instance: " .. p.instanceInfo .. "   zone text: " .. p.zoneText
      .. "   on list: " .. p.listed)
    print("  state: client said " .. tostring(p.clientBefore) .. ", " .. p.flags)
    print("  LoggingCombat(true): ok=" .. tostring(ok) .. " returned=" .. tostring(r1)
      .. "   logging now: " .. tostring(p.loggingImmediately))
    for _, delay in ipairs({ 1, 3, 10 }) do
      C_Timer.After(delay, function()
        p["loggingAfter" .. delay .. "s"] = FLC.isLogging()
        print("  logging after " .. delay .. "s: " .. tostring(FLC.isLogging()))
      end)
    end

  elseif cmd == "trace" then
    -- The saved decision trace: why the last zone-ins did or did not start.
    local t = cfg().trace or {}
    local n = tonumber(parts[2]) or 15
    FLC.say("last " .. math.min(n, #t) .. " of " .. #t .. " trace lines:")
    for i = math.max(1, #t - n + 1), #t do print("  " .. t[i]) end

  elseif cmd == "debug" then
    cfg().debug = not cfg().debug
    FLC.say("Debug: " .. (cfg().debug and "on" or "off"))
    UI.refreshCheckboxes()

  elseif cmd == "zone" then
    local sub = (parts[2] or ""):lower()
    local name = table.concat(parts, " ", 3)
    local zones = cfg().monitored_zones
    if sub == "add" then
      if name == "" then name = currentZoneName() end
      zones[name] = true
      FLC.say("Added zone: " .. name)
      FLC.check(false)
    elseif sub == "remove" then
      -- Resolve case-insensitively against the keys present, then tombstone.
      local removed
      for zone in pairs(zones) do
        if zone:lower() == name:lower() then removed = zone; break end
      end
      removed = removed or name
      zones[removed] = false
      FLC.say("Removed zone: " .. removed .. " |cff888888(stays removed; /" .. SLASH .. " zone reset restores defaults)|r")
    elseif sub == "reset" then
      FLC.say("Restored " .. FLC.restoreDefaultZones() .. " default zone(s). Zones you added yourself were kept.")
    elseif sub == "list" then
      local list = {}
      for zone, on in pairs(zones) do if on then list[#list + 1] = zone end end
      table.sort(list)
      for _, zone in ipairs(list) do print("  - " .. zone) end
    else
      FLC.say("Usage: /" .. SLASH .. " zone add|remove|list|reset [name]")
    end
    UI.refreshZones()

  elseif cmd == "help" then
    printHelp()

  else
    FLC.say("Unknown: " .. cmd)
    printHelp()
  end
end
