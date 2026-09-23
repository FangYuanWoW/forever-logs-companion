<div align="center">

<img src="docs/logo.png" alt="Forever Logs Companion" width="128" height="128" />

# Forever Logs Companion

**Automatic `/combatlog` for WoW Forever**

Starts combat logging when you enter a dungeon or raid, so every run is ready to upload to **[foreverlogs.gg](https://foreverlogs.gg)**.

[![Latest release](https://img.shields.io/github/v/release/FangYuanWoW/forever-logs-companion?color=1ea3c4)](https://github.com/FangYuanWoW/forever-logs-companion/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-e8e8e8)](LICENSE)

</div>

---

## What it does

- **Asks before it starts.** Entering a monitored dungeon or raid pops up
  *Start /combatlog?*. Say no and nothing is written.
- **Asks before it stops.** Leaving a zone where it started logging asks
  whether to stop or keep going (handy between pulls and dungeons).
- **Silent mode.** Skip both prompts: logging starts on zone entry and stays
  on until you turn it off yourself.
- **Turns on Advanced Combat Logging.** Without it the combat log has no gear,
  talents or stats, and your reports show no specs or item levels.
- **Leaves your own logging alone.** If you already typed `/combatlog`, it
  never switches it off.

It does not read the combat log or send anything anywhere. It only switches
the client's log writer on and off, the same as typing `/combatlog`.

## Install

1. Download the latest zip from
   [Releases](https://github.com/FangYuanWoW/forever-logs-companion/releases/latest).
2. Extract it into `World of Warcraft\<your client folder>\Interface\AddOns\`,
   so you end up with `Interface\AddOns\ForeverLogsCompanion\ForeverLogsCompanion.toc`.
3. Restart the game (or `/reload`).

Logs are written to the client's `Logs` folder as `WoWCombatLog-<date>.txt`.
Upload them at [foreverlogs.gg](https://foreverlogs.gg), or let the Forever Logs
Uploader do it for you.

## Settings

Type **`/flc`** or click the minimap icon.

| Tab | What's there |
|---|---|
| **Monitored Zones** | Your current zone, *Add Current*, add a zone by name, remove zones, *Restore Default Zones* |
| **Settings** | Auto `/combatlog` on zone entry, silent mode, log 5-man dungeons, log raids and world bosses, minimap icon |

Every dungeon and raid tracked on foreverlogs.gg is monitored out of the box.
If a zone doesn't prompt, stand inside it and click **Add Current**.

### Commands

| Command | |
|---|---|
| `/flc` | open the settings window |
| `/flc zones` / `/flc settings` | open on a specific tab |
| `/flc status` | current zone, logging state and settings |
| `/flc zone add [name]` | monitor a zone (current zone if no name) |
| `/flc zone remove <name>` | stop monitoring a zone |
| `/flc zone list` / `/flc zone reset` | list zones / restore the defaults |

## License

MIT - see [LICENSE](LICENSE). Bundles LibStub, CallbackHandler-1.0,
LibDataBroker-1.1 and LibDBIcon-1.0 under their own licenses.
