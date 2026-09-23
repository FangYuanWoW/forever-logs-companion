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

FLC.VERSION = "0.2.1"
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

-- WHY THE ADDON TRACKS THE STATE ITSELF: on WoW Forever, LoggingCombat() is
-- not a reliable read. After a /combatlog toggle it keeps reporting the old
-- state for 10s or more, and after a /reload it reports "off" for a while
-- even though the log keeps writing. /combatlog is a toggle, so trusting a
-- false "off" would make the Start button switch logging OFF.
--
-- The client does announce every toggle in chat at once ("Combat being
-- logged to ...", "Combat logging disabled."), so that is the source of
-- truth. It is saved per client session: GetTime() counts from client start,
-- so a /reload (same session) keeps it, and a fresh client launch - which
-- always starts with logging off - discards it. LoggingCombat() is only asked
-- when nothing is known, and to read back the addon's own direct calls,
-- which it does reflect immediately.
local known  -- true / false / nil (nothing known this session)

local function setKnown(state)
  known = state
  if db then
    db.log_state = state
    db.log_state_clock = GetTime()
  end
end

-- Restores the saved state when this is the same client session (a /reload).
local function restoreKnown()
  local clock = db.log_state_clock
  if db.log_state ~= nil and clock and GetTime() >= clock then
    known = db.log_state
  else
    known = nil
    db.log_state, db.log_state_clock = nil, nil
  end
end

local function clientReportsLogging()
  local ok, on = pcall(LoggingCombat)
  return ok and on and true or false
end
FLC.clientReportsLogging = clientReportsLogging

function FLC.isLogging()
  if known ~= nil then return known end
  return clientReportsLogging()
end

local function isEnabledMessage(msg)
  if _G.COMBATLOGENABLED and msg == _G.COMBATLOGENABLED then return true end
  return msg:find("^Combat being logged") ~= nil
end

local function isDisabledMessage(msg)
  if _G.COMBATLOGDISABLED and msg == _G.COMBATLOGDISABLED then return true end
  return msg:find("^Combat logging disabled") ~= nil
end

-- CHAT_MSG_SYSTEM handler. pcall: under the Chat addon restriction the text
-- may arrive as a value an addon is not allowed to compare.
function FLC.onSystemMessage(msg)
  local ok, state = pcall(function()
    if type(msg) ~= "string" then return nil end
    if isEnabledMessage(msg) then return true end
    if isDisabledMessage(msg) then return false end
    return nil
  end)
  if ok and state ~= nil then
    setKnown(state)
    FLC.debug("chat says combat logging " .. (state and "on" or "off"))
  end
end

-- Direct call. It prints nothing in chat, but LoggingCombat() reflects it at
-- once, so record what the client reports right after.
-- Returns pcall's ok + the error text when the call itself was refused.
local function setLogging(on)
  local ok, err = pcall(LoggingCombat, on)
  FLC.lastSetError = (not ok) and tostring(err) or nil
  setKnown(clientReportsLogging())
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
    FLC.debug("Skipping " .. zoneName .. ": logging " .. CONTENT_LABEL[blocked] .. " is turned off.")
  end
  resetState()
  return true
end

-- WHY A SECURE BUTTON: WoW Forever's "Map" addon restriction (active inside
-- some instances) lets an addon call LoggingCombat(true) but the client undoes
-- it within a few seconds. /combatlog run by the PLAYER is not undone. So the
-- prompt's start/stop button is a SecureActionButton whose click runs
-- /combatlog exactly as if the player typed it. The direct call is still used
-- where the restriction is off (silent mode, settings toggles), and falls back
-- to the prompt when it gets undone.

local function mapRestricted()
  local RA = _G.C_RestrictedActions
  local T = Enum and Enum.AddOnRestrictionType
  if not (RA and RA.GetAddOnRestrictionState and T and T.Map) then return false end
  local ok, st = pcall(RA.GetAddOnRestrictionState, T.Map)
  return ok and st ~= nil and st ~= 0
end

local function titleLine()
  return "|T" .. FLC.ICON .. ":32:32:0:0|t  |cff66ccffForever Logs Companion|r\n"
    .. "|cff555555------------------------------|r\n"
end

-- Calls done(true) as soon as LoggingCombat() reads `want`, or done(false)
-- after `seconds` if it never does. Checks twice a second.
function FLC.waitForLogging(want, seconds, done)
  local tries = seconds * 2
  local function poll()
    if FLC.isLogging() == want then return done(true) end
    tries = tries - 1
    if tries <= 0 then return done(false) end
    C_Timer.After(0.5, poll)
  end
  C_Timer.After(0.5, poll)
end

local prompt         -- built on first use (out of combat)
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

  -- Secure: its click runs /combatlog as the player.
  local go = CreateFrame("Button", "ForeverLogsCompanion_PromptGo", f,
    "SecureActionButtonTemplate, UIPanelButtonTemplate")
  go:SetSize(130, 22)
  go:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
  go:SetAttribute("type", "macro")
  go:SetAttribute("macrotext", "/combatlog")
  -- Modern clients fire secure buttons on key-down OR key-up per the
  -- ActionButtonUseKeyDown setting; register both so a click fires once
  -- whichever it is. /combatlog is a toggle, so PreClick disarms the button
  -- when logging is already in the wanted state, and PostClick hides the
  -- prompt so a second phase of the same click lands nowhere.
  go:RegisterForClicks("AnyUp", "AnyDown")
  -- LoggingCombat() lags a /combatlog toggle, so the state check alone could
  -- re-arm a second phase of the same click; ignore any re-fire within 1s.
  local lastFired = 0
  go:SetScript("PreClick", function(self)
    if InCombatLockdown() then return end
    local want = (f.mode == "start")
    local armed = FLC.isLogging() ~= want and (GetTime() - lastFired) > 1
    self:SetAttribute("type", armed and "macro" or nil)
    if armed then lastFired = GetTime() end
  end)
  go:SetScript("PostClick", function()
    local mode, zone = f.mode, f.zone
    if not InCombatLockdown() then f:Hide() end
    local want = (mode == "start")
    -- Normally the chat line settles this at once; the wait only matters
    -- when that line is not recognised and LoggingCombat() has to catch up.
    FLC.waitForLogging(want, 15, function(ok)
      if mode == "start" then
        if ok then
          onStarted(zone)
        else
          FLC.say("|cffff5555Combat logging did not start.|r Type /combatlog to start it yourself.")
        end
      elseif ok then
        FLC.say("Combat logging stopped.")
        FLC.resetState()
      end
    end)
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
    if not InCombatLockdown() then f:Hide() end
  end)
  f.no = no

  return f
end

-- mode "start" | "stop". A frame holding a secure button cannot be shown or
-- hidden in combat, so a prompt raised mid-fight waits for combat to end.
function FLC.showPrompt(mode, zone, text)
  if InCombatLockdown() then
    pendingPrompt = { mode = mode, zone = zone, text = text }
    return
  end
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

-- Direct start, for silent mode and settings toggles. Where the Map
-- restriction would undo it, or if it gets undone anyway, ask for a click.
function FLC.beginLogging(zoneName)
  ensureAdvancedLogging()
  if FLC.isLogging() then return end
  local NEEDS_CLICK = "WoW Forever only lets you start logging here with a click."
  if mapRestricted() then
    showStartPrompt(zoneName, NEEDS_CLICK)
    return
  end
  local ok = setLogging(true)
  if not ok then
    showStartPrompt(zoneName, NEEDS_CLICK)
    return
  end
  -- The restriction undoes a direct start within ~3s; confirm after that.
  C_Timer.After(4, function()
    -- The Map restriction undoes a direct start without a chat line, and
    -- LoggingCombat() does show that reversal, so re-read it here.
    if FLC.isLogging() and not clientReportsLogging() then setKnown(false) end
    if FLC.isLogging() then
      onStarted(zoneName)
    else
      showStartPrompt(zoneName, NEEDS_CLICK)
    end
  end)
end

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

  -- ASK FIRST: the client opens a new dated log file on every off->on
  -- switch, so start-then-decline would leave stub files behind. Only on a
  -- main zone change, and once per zone entry.
  if showPopup then
    if FLC.popupShownForZone == zoneName then return end
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
  if zone == "" then return end

  if not enforceContentGate(zone) then
    local monitored = isMonitored(zone)
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
    restoreKnown()
    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    if FLC.onLoaded then FLC.onLoaded() end
    return
  end
  if event == "CHAT_MSG_SYSTEM" then
    FLC.onSystemMessage(arg1)
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    FLC.flushPendingPrompt()
    return
  end
  FLC.check(true)
  -- PLAYER_ENTERING_WORLD can fire before instance info is ready behind the
  -- loading screen; look again shortly. popupShownForZone keeps it to one ask.
  C_Timer.After(2, function() FLC.check(true) end)
end)
