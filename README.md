# ARC — Advanced Raid Check

ARC is a lightweight raid-readiness addon for World of Warcraft: Mists of
Pandaria 5.4.8 (`Interface 50400`). It turns ready checks, inspection data and
raid activity into one clear view, without changing player settings or
answering ready checks automatically.

## Highlights

- ready state, role, spec, consumables, raid buffs and ARC version
- upgrade-aware item level, durability reports and detailed PvE gear checks
- talents, class self-buffs, tank stance, pets, Growl and Healthstone checks
- a clear **READY TO PULL**, **NOT READY** or **CHECK INCOMPLETE** verdict
- standalone **ARC Check** for a targeted player, even outside your group
- optional raid-session reports with pulls, attendance and trash inactivity
- 25-player scrolling roster and automatic optional ElvUI styling

## Install

1. Download the latest ZIP from [GitHub Releases](https://github.com/Interacti0n/ARC-Advanced-Raid-Check/releases/latest).
2. Extract it into `World of Warcraft/Interface/AddOns/` so the file is at
   `Interface/AddOns/ARC/ARC.toc`.
3. Fully exit WoW and start it again. On this MoP client, `/reload` may keep an
   old TOC file list after an update.

Keep the addon folder named `ARC`. ARC has no required external libraries;
ElvUI support is detected automatically.

## Quick start

- `/arc` or left-click the minimap icon — show/hide ARC
- `/arc options` or right-click the minimap icon — open settings
- `/arc check` — inspect the targeted player in a standalone report
- `/arc raid` — configure expected raid size/difficulty and loot method
- `/arc session start` / `/arc session end` — record a raid session
- `/arc help` — show every command

By default ARC opens when a ready check starts. Enable **Manual opening only**
in Options if you want to open it yourself. The **Ready** and **Not Ready**
buttons answer only your own active ready check.

## Documentation

| Document | Contents |
| --- | --- |
| [User guide](docs/USER_GUIDE.md) | Window, colors, commands, settings, ARC Check and common workflows |
| [Readiness checks](docs/READINESS_CHECKS.md) | Talents, class buffs, tanks, pets, Growl, Healthstones and protocol behavior |
| [Gear rules](docs/GEAR_RULES.md) | Item level, gems, enchants, primary stats and policy customization |
| [Session reports](docs/SESSION_REPORT.md) | Pulls, attendance, AFK flags and trash-inactivity tracking |
| [Data and limitations](docs/DATA_AND_LIMITATIONS.md) | What inspect, unit APIs and the ARC channel can and cannot provide |
| [Architecture](docs/ARCHITECTURE.md) | Module ownership, load order and compatibility identifiers |
| [Testing](docs/TESTING.md) | In-game release verification checklist |
| [Release checklist](docs/RELEASE_CHECKLIST.md) | Versioning, automated packaging and publishing |
| [Changelog](changelog.txt) | Release history |

## Compatibility notes

Players without ARC can still be inspected for spec, equipped gear and low
item level when they are in inspect range. Private data such as remote
durability, bags/Healthstones, weapon imbues and hunter-pet Growl autocast
requires their ARC report. To avoid false raid blockers on MoP private-server
cores, remote **Self** and Healthstone checks without usable ARC data are shown
as passed/skipped; their tooltips explain that they were not verified.

The product name is **Advanced Raid Check**, but technical identifiers remain
`ARC`, `ARC_DB` and `ARC1` for compatibility with existing settings and peers.

## Version

Current version: **1.6.0**

## License

ARC is released under the [MIT License](LICENSE). The embedded WoWSims-derived
catalog retains its [MIT notice](docs/WOWSIMS_LICENSE.txt), also included in
`ARC_Gear.lua`.
