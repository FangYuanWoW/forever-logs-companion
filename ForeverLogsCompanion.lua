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

FLC.VERSION = "0.2.2"
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

-- Safe tostring: after a client patch a value may arrive as a secret value an
-- addon cannot compare or print. Says so instead of erroring.
function FLC.describe(v)
  if _G.issecretvalue then
    local ok, secret = pcall(issecretvalue, v)
    if ok and secret then return "<secret " .. type(v) .. ">" end
  end
  local ok, s = pcall(tostring, v)
  return ok and s or "<unprintable>"
end

-- Decision trace, kept in SavedVariables (last TRACE_MAX lines, /flc trace)
-- so a zone-in that did nothing can be read back after logout. Always on; it
-- is a handful of lines per zone change.
local TRACE_MAX = 60
function FLC.trace(msg)
  FLC.debug(msg)
  if not db then return end
  db.trace = db.trace or {}
  table.insert(db.trace, string.format("%s %.1f %s", date("%H:%M:%S"), GetTime(), msg))
  while #db.trace > TRACE_MAX do table.remove(db.trace, 1) end
end

-- " restricted=Map:2,..." for every non-zero addon restriction, "" if none.
function FLC.restrictionSummary()
  local RA = _G.C_RestrictedActions
  local T = Enum and Enum.AddOnRestrictionType
  if not (RA and RA.GetAddOnRestrictionState and T) then return " restrictions=n/a" end
  local on = {}
  for name, id in pairs(T) do
    local ok, st = pcall(RA.GetAddOnRestrictionState, id)
    if not ok then on[#on + 1] = name .. ":err"
    elseif st ~= nil and st ~= 0 then on[#on + 1] = name .. ":" .. FLC.describe(st) end
  end
  table.sort(on)
  return #on > 0 and (" restricted=" .. table.concat(on, ",")) or ""
end

-- WHY THE ADDON KEEPS ITS OWN STATE, BRIEFLY: LoggingCombat() is not a
-- reliable read on WoW Forever. It lags every switch by seconds (10+ after a
-- /combatlog, ~5 after the addon's own call) and reads "off" for a while
-- after a /reload. Since client build 70124 the "Combat being logged" chat
-- line reaches addons as a secret value, so it cannot be used either. The
-- addon trusts its own successful call for KNOWN_FOR seconds (covering the
-- start retries), then the lagging but self-correcting read takes over.
-- Nothing is carried across a /reload.
local KNOWN_FOR = 35  -- seconds; longer than the last start retry
local known       -- true / false / nil
local knownAt = 0

local function setKnown(state)
  known = state
  knownAt = GetTime()
end

local function clientReportsLogging()
  local ok, on = pcall(LoggingCombat)
  return ok and on and true or false
end
FLC.clientReportsLogging = clientReportsLogging

function FLC.isLogging()
  if known ~= nil and GetTime() - knownAt < KNOWN_FOR then return known end
  return clientReportsLogging()
end

-- Direct call. It prints nothing in chat. Not a toggle, unlike /combatlog.
-- Returns pcall's ok + the error text when the call itself was refused.
local function setLogging(on)
  local ok, err = pcall(LoggingCombat, on)
  FLC.lastSetError = (not ok) and tostring(err) or nil
  if ok then setKnown(on) else setKnown(clientReportsLogging()) end
  return ok, err
end

-- Direct start, retried until the client confirms. Since client build 70205
-- an instance holds the "Map" addon restriction, and for a variable time
-- after the loading screen (about 10s in Ragefire Chasm) the client silently
-- ignores a start. Later ones work. Each retry while already logging only
-- writes another COMBAT_LOG_VERSION header into the same file, so retrying
-- is safe. The secure-button /combatlog this used to rely on no longer
-- starts anything under that restriction.
local START_RETRIES = { 3, 6, 10, 15, 20, 30 }
local CONFIRM_GRACE = 8  -- the read lags a real start by ~5s
local function directStart()
  local ok = setLogging(true)
  FLC.trace("direct LoggingCombat(true): ok=" .. tostring(ok) .. " err=" .. tostring(FLC.lastSetError)
    .. FLC.restrictionSummary())
  if not ok then return false end
  local done = false
  local function confirmed(delay)
    if done then return true end
    if known == false then done = true return true end  -- stopped meanwhile
    if clientReportsLogging() then
      done = true
      FLC.trace("start confirmed by client at +" .. delay .. "s")
      return true
    end
    return false
  end
  for _, delay in ipairs(START_RETRIES) do
    C_Timer.After(delay, function()
      if confirmed(delay) then return end
      local again = pcall(LoggingCombat, true)
      FLC.trace("start retry +" .. delay .. "s: ok=" .. tostring(again) .. FLC.restrictionSummary())
    end)
  end
  local last = START_RETRIES[#START_RETRIES] + CONFIRM_GRACE
  C_Timer.After(last, function()
    if confirmed(last) then return end
    FLC.trace("start never confirmed")
    FLC.say("|cffff5555Combat logging may not have started.|r Type /combatlog to start it yourself.")
  end)
  return true
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
FLC.listState = listState

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

FLC.resetState = resetState

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
    FLC.trace("Skipping " .. zoneName .. ": logging " .. CONTENT_LABEL[blocked] .. " is turned off.")
  end
  resetState()
  return true
end

local function titleLine()
  return "|T" .. FLC.ICON .. ":32:32:0:0|t  |cff66ccffForever Logs Companion|r\n"
    .. "|cff555555------------------------------|r\n"
end

local prompt         -- built on first use
local pendingPrompt  -- { mode, zone, text } waiting for combat to end

local function onStarted(zoneName)
  FLC.lastLoggedZone = zoneName
  FLC.startedByUs = true
  FLC.say("Combat logging started for " .. zoneName .. ".")
end

local function buildPrompt()
  local f = CreateFrame("Frame", "ForeverLogsCompanion_Prompt", UIParent, "BackdropTemplate")
  f:SetSize(340, 150)
  f:SetPoint("TOP", UIParent, "TOP", 0, -135)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:Hide()

  local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOP", f, "TOP", 0, -18)
  text:SetWidth(300)
  f.text = text

  -- Sets the wanted state directly. It used to be a secure button running
  -- /combatlog, which since client build 70205 prints "Combat being logged"
  -- inside an instance but starts nothing, and as a toggle on a lagging read
  -- could switch logging the wrong way.
  local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  go:SetSize(130, 22)
  go:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
  go:SetScript("OnClick", function()
    local mode, zone = f.mode, f.zone
    f:Hide()
    local want = (mode == "start")
    FLC.trace("prompt " .. tostring(mode) .. " click (isLogging=" .. tostring(FLC.isLogging())
      .. ", client=" .. tostring(clientReportsLogging()) .. ")" .. FLC.restrictionSummary())
    if want then
      if directStart() then
        onStarted(zone)
      else
        FLC.say("|cffff5555Combat logging did not start.|r Type /combatlog to start it yourself.")
      end
    else
      local ok = setLogging(false)
      FLC.trace("prompt stop LoggingCombat(false): ok=" .. tostring(ok) .. " err=" .. tostring(FLC.lastSetError))
      if ok then
        FLC.say("Combat logging stopped.")
        resetState()
      end
    end
  end)
  f.go = go

  local no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  no:SetSize(130, 22)
  no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
  no:SetScript("OnClick", function()
    if f.mode == "stop" then
      -- Keep ownership so leaving the next monitored zone asks again.
      FLC.lastLoggedZone = nil
      FLC.popupShownForZone = nil
    end
    FLC.pendingZone = nil
    f:Hide()
  end)
  f.no = no

  return f
end

-- mode "start" | "stop". A prompt raised mid-fight waits for combat to end,
-- so it never pops over a pull.
function FLC.showPrompt(mode, zone, text)
  -- Several zone checks fire per transition; ask once.
  if prompt and prompt:IsShown() and prompt.mode == mode and prompt.zone == zone then return end
  if pendingPrompt and pendingPrompt.mode == mode and pendingPrompt.zone == zone then return end
  if InCombatLockdown() then
    FLC.trace(mode .. " prompt for " .. tostring(zone) .. " deferred: in combat")
    pendingPrompt = { mode = mode, zone = zone, text = text }
    return
  end
  FLC.trace(mode .. " prompt shown for " .. tostring(zone))
  prompt = prompt or buildPrompt()
  prompt.mode, prompt.zone = mode, zone
  prompt.text:SetText(text)
  prompt.go:SetText(mode == "start" and "Start logging" or "Stop logging")
  prompt.no:SetText(mode == "start" and "Not now" or "Keep logging")
  prompt:SetHeight(math.max(130, prompt.text:GetStringHeight() + 70))
  prompt:Show()
end

function FLC.flushPendingPrompt()
  if pendingPrompt and not InCombatLockdown() then
    local p = pendingPrompt
    pendingPrompt = nil
    FLC.showPrompt(p.mode, p.zone, p.text)
  end
end

local function showStartPrompt(zoneName, note)
  FLC.popupShownForZone = zoneName
  FLC.pendingZone = zoneName
  FLC.showPrompt("start", zoneName, titleLine()
    .. "Start |cffffd200/combatlog|r for:\n|cff00ffff" .. zoneName .. "|r"
    .. (note and ("\n\n|cffaaaaaa" .. note .. "|r") or ""))
end

-- Direct start, for silent mode and settings toggles. Falls back to the
-- prompt only when the call itself is refused.
function FLC.beginLogging(zoneName)
  ensureAdvancedLogging()
  if FLC.isLogging() then
    FLC.trace("direct start skipped: already logging")
    return
  end
  if directStart() then
    onStarted(zoneName)
  else
    showStartPrompt(zoneName, "Combat logging could not be started automatically here.")
  end
end

local function startLogging(zoneName, showPopup)
  if FLC.isLogging() then
    -- Already on (ours across zones, or started elsewhere): claim the zone
    -- without toggling anything.
    ensureAdvancedLogging()
    FLC.lastLoggedZone = zoneName
    FLC.trace("no prompt for " .. zoneName .. ": already logging (known=" .. tostring(known)
      .. ", client=" .. tostring(clientReportsLogging()) .. ")")
    return
  end
  if not db.auto_combatlog then
    FLC.trace("no prompt for " .. zoneName .. ": auto-log is off")
    return
  end

  -- ASK FIRST: the client opens a new dated log file on every off->on
  -- switch, so start-then-decline would leave stub files behind. Only on a
  -- main zone change, and once per zone entry.
  if showPopup then
    if FLC.popupShownForZone == zoneName then
      FLC.trace("no prompt for " .. zoneName .. ": already asked this entry")
      return
    end
    ensureAdvancedLogging()
    showStartPrompt(zoneName)
    return
  end

  -- Silent mode, or a setting flipped while standing in the zone.
  FLC.beginLogging(zoneName)
end

function FLC.check(isMainZoneChange)
  if not db then return end
  local zone = FLC.currentZone()
  local _, instanceType = IsInInstance()
  FLC.trace("check(" .. tostring(isMainZoneChange) .. ") zone=" .. FLC.describe(zone)
    .. " type=" .. FLC.describe(instanceType) .. " listed=" .. tostring(listState(zone))
    .. " last=" .. tostring(FLC.lastLoggedZone) .. " known=" .. tostring(known)
    .. " client=" .. tostring(clientReportsLogging()) .. FLC.restrictionSummary())
  if zone == "" then return end

  if not enforceContentGate(zone) then
    local monitored = isMonitored(zone)
    -- "Once per zone entry": leaving the zone ends the entry, so walking back
    -- in asks again.
    if not monitored and isMainZoneChange then FLC.popupShownForZone = nil end
    if monitored and FLC.lastLoggedZone ~= zone then
      startLogging(zone, isMainZoneChange and not db.silent)
    elseif not monitored and FLC.lastLoggedZone and FLC.startedByUs
        and isMainZoneChange and not db.silent then
      -- Leaving a monitored zone where we started logging: ask rather than
      -- auto-stop, since players often keep logging between dungeons.
      FLC.showPrompt("stop", FLC.lastLoggedZone, titleLine()
        .. "Left monitored zone:\n|cff00ffff" .. FLC.lastLoggedZone .. "|r\n\n"
        .. "Stop |cffffd200/combatlog|r?")
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
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
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
    -- 0.2.1 saved the logging state across sessions; that is gone.
    db.log_state, db.log_state_clock = nil, nil
    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("ADDON_ACTION_BLOCKED")
    frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    local version, build = GetBuildInfo()
    FLC.trace("loaded v" .. FLC.VERSION .. " on client " .. tostring(version) .. "." .. tostring(build)
      .. " client=" .. tostring(clientReportsLogging()))
    if FLC.onLoaded then FLC.onLoaded() end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    FLC.flushPendingPrompt()
    return
  end
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if arg1 == ADDON then FLC.trace(event .. ": " .. FLC.describe(arg2)) end
    return
  end
  -- A client patch can make a zone API return a value the addon may not
  -- compare; trace the error rather than silently doing nothing.
  local function safeCheck()
    local ok, err = pcall(FLC.check, true)
    if not ok then FLC.trace("check error (" .. event .. "): " .. FLC.describe(err)) end
  end
  safeCheck()
  -- PLAYER_ENTERING_WORLD can fire before instance info is ready behind the
  -- loading screen; look again shortly. popupShownForZone keeps it to one ask.
  C_Timer.After(2, safeCheck)
end)
