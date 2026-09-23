-- Zones.lua
-- Default monitored zone list. User-editable via the settings window.
-- Case-insensitive match against GetInstanceInfo() / GetZoneText().
--
-- The Forever Logs dungeon and raid roster. Where the site splits or renames
-- an instance (Dire Maul - East, Temple of Ahn'Qiraj, Hyjal Summit), the
-- client's own map name is listed as well, because that is what
-- GetInstanceInfo() returns inside. Both forms coexist harmlessly.

local _, FLC = ...

FLC.DEFAULT_ZONES = {}
for _, name in ipairs({
  -- Raids
  "Molten Core",
  "Onyxia's Lair",
  "Blackwing Lair",
  "Zul'Gurub",
  "Ruins of Ahn'Qiraj",
  "Temple of Ahn'Qiraj", "Ahn'Qiraj Temple",
  "The Crystal Vale",
  "The Tainted Scar",
  "Hyjal Summit", "Hyjal Crater",
  "The Barrow Deeps",

  -- World bosses
  "Azshara",                 -- Azuregos

  -- 5-man dungeons
  "Ragefire Chasm",
  "Deadmines",
  "Wailing Caverns",
  "Shadowfang Keep",
  "Blackfathom Deeps",
  "The Stockade", "Stormwind Stockade",
  "Gnomeregan",
  "Razorfen Kraul",
  "Scarlet Monastery",
  "Razorfen Downs",
  "Uldaman",
  "Zul'Farrak",
  "Maraudon",
  "Sunken Temple",
  "Blackrock Depths",
  "Blackrock Spire", "Lower Blackrock Spire", "Upper Blackrock Spire",
  "Dire Maul",
  "Scholomance",
  "Stratholme",

  -- WoW Forever dungeons
  "City of Dalaran",
  "Excavation Site: Wetlands",
  "Ruins of Lordaeron",
  "The Hall of Thanes",
}) do
  FLC.DEFAULT_ZONES[name] = true
end

-- Outdoor world-boss zones report instanceType "none", so the "Log raids and
-- world bosses" switch recognises them by name instead.
FLC.OUTDOOR_RAID_ZONES = {
  ["azshara"] = true,
  ["the tainted scar"] = true,
}
