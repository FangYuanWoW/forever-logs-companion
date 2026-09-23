-- ForeverLogsCompanion.lua
-- Auto-toggles /combatlog on zone transitions and keeps Advanced Combat
-- Logging on, so the log carries gear, talents and stats (COMBATANT_INFO).
--
-- It never reads the combat log. It only switches the client's log writer,
-- the same thing typing /combatlog does.
--
-- Only main-zone changes (ZONE_CHANGED_NEW_AREA + PLAYER_ENTERING_WORLD)
-- drive auto-logging, so crossing sub-zones inside an instance never re-asks.
--
-- Coexistence: if logging is already on (you typed /combatlog, or another
-- addon started it) nothing is toggled. Only a session this addon started is
-- ever stopped.
--
-- A zone is logged when it is on the monitored list (Zones.lua defaults plus
-- whatever the player adds). A removed zone is stored as false so it stays
-- removed across sessions; "Restore Default Zones" brings the defaults back.

local ADDON, FLC = ...
_G.ForeverLogsCompanion = FLC

FLC.VERSION = "0.2.0"
FLC.MEDIA_PATH = "Interface\\AddOns\\ForeverLogsCompanion\\Media\\"
FLC.ICON = FLC.MEDIA_PATH .. "logo-128.tga"

local PREFIX = "|cff66ccffForever Logs|r: "

local DEFAULTS = {
  auto_combatlog = true,   -- auto-start /combatlog on monitored zone entry
  silent         = false,  -- skip the start/stop prompts; never auto-stops
  log_dungeons   = true,
  log_raids      = true,
  debug          = false,
}

local db

FLC.lastLoggedZone = nil
FLC.startedByUs = false
FLC.popupShownForZone = nil
FLC.pendingZone = nil

function FLC.say(msg) print(PREFIX .. msg) end
function FLC.debug(msg) if db and db.debug then print(PREFIX .. "|cff888888" .. msg .. "|r") end end

function FLC.isLogging()
  local ok, on = pcall(LoggingCombat)
  return ok and on and true or false
end

-- Returns pcall's ok + the error text when the call itself was refused.
local function setLogging(on)
  local ok, err = pcall(LoggingCombat, on)
  FLC.lastSetError = (not ok) and tostring(err) or nil
  return ok, err
end

-- The client only writes COMBATANT_INFO when this is on. Without it an
-- uploaded log has no specs, gear or item levels.
local function ensureAdvancedLogging()
  if GetCVar("advancedCombatLogging") == "1" then return end
  if pcall(SetCVar, "advancedCombatLogging", 1) and GetCVar("advancedCombatLogging") == "1" then
    FLC.say("Advanced Combat Logging turned on.")
  else
    FLC.say("|cffff5555Could not turn on Advanced Combat Logging.|r Enable it in Options > Network.")
  end
end

function FLC.currentZone()
  if IsInInstance() then
    local instanceName = GetInstanceInfo()
    if instanceName and instanceName ~= "" then return instanceName end
  end
  return GetZoneText() or ""
end

-- Case-insensitive lookup in the monitored list: true, false (removed), nil.
local function listState(name)
  if not name or not db then return nil end
  local lower = name:lower()
  local state
  for zone, on in pairs(db.monitored_zones) do
    if zone:lower() == lower then
      if on then return true end
      state = false
    end
  end
  return state
end

-- "raid", "dungeon", or nil (open world, a hand-added zone).
local function contentKind(zoneName)
  local _, instanceType = IsInInstance()
  if instanceType == "raid" then return "raid" end
  if instanceType == "party" then return "dungeon" end
  if zoneName and FLC.OUTDOOR_RAID_ZONES[zoneName:lower()] then return "raid" end
  return nil
end

local function blockedContentKind(zoneName)
  local kind = contentKind(zoneName)
  if kind == "dungeon" and not db.log_dungeons then return "dungeon" end
  if kind == "raid" and not db.log_raids then return "raid" end
  return nil
end

local function isMonitored(zoneName)
  return listState(zoneName) == true
end

local function resetState()
  FLC.startedByUs = false
  FLC.lastLoggedZone = nil
  FLC.popupShownForZone = nil
  FLC.pendingZone = nil
end

local CONTENT_LABEL = { raid = "a raid or world boss", dungeon = "a 5-man dungeon" }

-- Stops a session WE started when the zone is blocked by a content switch.
-- Returns true when blocked, so nothing else in check() runs.
local function enforceContentGate(zoneName)
  local blocked = blockedContentKind(zoneName)
  if not blocked then return false end
  if FLC.startedByUs and FLC.isLogging() then
    setLogging(false)
    FLC.say("Combat logging stopped: " .. zoneName .. " is " .. CONTENT_LABEL[blocked]
      .. ", and logging there is turned off.")
  else
    FLC.debug("Skipping " .. zoneName .. ": logging " .. CONTENT_LABEL[blocked] .. " is turned off.")
  end
  resetState()
  return true
end

function FLC.beginLogging(zoneName)
  ensureAdvancedLogging()
  if FLC.isLogging() then return end
  local ok, err = setLogging(true)
  if not ok then
    FLC.say("|cffff5555Could not start combat logging|r (" .. tostring(err) .. "). Type /combatlog to start it yourself.")
    return
  end
  FLC.lastLoggedZone = zoneName
  FLC.startedByUs = true
  -- The client may apply the switch a moment later, so confirm after a beat
  -- instead of reading the state back immediately.
  C_Timer.After(1, function()
    if FLC.isLogging() then
      FLC.say("Combat logging started for " .. zoneName .. ".")
    else
      FLC.startedByUs = false
      FLC.lastLoggedZone = nil
      FLC.say("|cffff5555Combat logging did not start|r for " .. zoneName
        .. ". Type /combatlog to start it yourself, and /flc probe to see why.")
    end
  end)
end

local function titleLine()
  return "|T" .. FLC.ICON .. ":32:32:0:0|t  |cff66ccffForever Logs Companion|r\n"
    .. "|cff555555------------------------------|r\n"
end

-- Ask BEFORE starting: the client opens a new dated log file on every
-- off->on switch, so start-then-decline would leave stub files behind.
StaticPopupDialogs["FOREVERLOGS_START_PROMPT"] = {
  text = "",
  button1 = "Start logging",
  button2 = "Not now",
  OnAccept = function()
    local zone = FLC.pendingZone
    FLC.pendingZone = nil
    if zone then FLC.beginLogging(zone) end
  end,
  OnCancel = function()
    FLC.pendingZone = nil
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- Leaving a monitored zone where we started logging: ask rather than
-- auto-stop, since players often keep logging between pulls and dungeons.
StaticPopupDialogs["FOREVERLOGS_STOP_PROMPT"] = {
  text = "",
  button1 = "Stop logging",
  button2 = "Keep logging",
  OnAccept = function()
    if FLC.isLogging() then
      setLogging(false)
      FLC.say("Combat logging stopped.")
    end
    resetState()
  end,
  OnCancel = function()
    -- Keep ownership so leaving the next monitored zone asks again.
    FLC.lastLoggedZone = nil
    FLC.popupShownForZone = nil
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function startLogging(zoneName, showPopup)
  if FLC.isLogging() then
    -- Already on (ours across zones, or started elsewhere): claim the zone
    -- without toggling anything.
    ensureAdvancedLogging()
    FLC.lastLoggedZone = zoneName
    FLC.debug("Combat log already on for " .. zoneName .. ".")
    return
  end
  if not db.auto_combatlog then return end

  if showPopup then
    if FLC.popupShownForZone == zoneName then return end
    FLC.popupShownForZone = zoneName
    FLC.pendingZone = zoneName
    StaticPopupDialogs["FOREVERLOGS_START_PROMPT"].text = titleLine()
      .. "Start |cffffd200/combatlog|r for:\n|cff00ffff" .. zoneName .. "|r\n\n"
      .. "Output: |cffaaaaaaLogs\\WoWCombatLog-*.txt|r"
    StaticPopup_Show("FOREVERLOGS_START_PROMPT")
    return
  end

  -- Silent mode, or a setting flipped while standing in the zone: both are
  -- an explicit choice by the player, so start without asking.
  FLC.beginLogging(zoneName)
end

function FLC.check(isMainZoneChange)
  if not db then return end
  local zone = FLC.currentZone()
  if zone == "" then return end

  if not enforceContentGate(zone) then
    local monitored = isMonitored(zone)
    if monitored and FLC.lastLoggedZone ~= zone then
      startLogging(zone, isMainZoneChange and not db.silent)
    elseif not monitored and FLC.lastLoggedZone and FLC.startedByUs
        and isMainZoneChange and not db.silent then
      StaticPopupDialogs["FOREVERLOGS_STOP_PROMPT"].text = titleLine()
        .. "Left monitored zone:\n|cff00ffff" .. FLC.lastLoggedZone .. "|r\n\n"
        .. "Stop |cffffd200/combatlog|r?"
      StaticPopup_Show("FOREVERLOGS_STOP_PROMPT")
    end
  end
  if FLC.onZoneChecked then FLC.onZoneChecked() end
end

function FLC.restoreDefaultZones()
  local restored = 0
  for zone, on in pairs(FLC.DEFAULT_ZONES) do
    if db.monitored_zones[zone] ~= on then
      db.monitored_zones[zone] = on
      restored = restored + 1
    end
  end
  return restored
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    ForeverLogsCompanionDB = ForeverLogsCompanionDB or {}
    db = ForeverLogsCompanionDB
    FLC.db = db
    for k, v in pairs(DEFAULTS) do
      if db[k] == nil then db[k] = v end
    end
    db.monitored_zones = db.monitored_zones or {}
    -- Seed defaults the player has not configured. A removed zone is stored
    -- as false, so it stays removed across sessions.
    for zone, on in pairs(FLC.DEFAULT_ZONES) do
      if db.monitored_zones[zone] == nil then db.monitored_zones[zone] = on end
    end
    -- LibDBIcon position/visibility, same shape the other companions use.
    db.minimap_button = db.minimap_button or { hide = false, minimapPos = 200 }
    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    if FLC.onLoaded then FLC.onLoaded() end
    return
  end
  FLC.check(true)
  -- PLAYER_ENTERING_WORLD can fire before instance info is ready behind the
  -- loading screen; look again shortly. popupShownForZone keeps it to one ask.
  C_Timer.After(2, function() FLC.check(true) end)
end)
