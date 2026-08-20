# ARC - Advanced Ready Check

A lightweight raid/party overview panel for **World of Warcraft: Mists of Pandaria (client 5.4.8, Interface 50408)**. ARC pops open automatically on a ready check (or on demand via `/arc`) and gives you a clean, at-a-glance view of your group's readiness, consumables, raid buffs, item level, and durability - for groups of 5 to 25.

## Features

- **Auto-opens on Ready Check**, or toggle anytime with `/arc`.
- **Live roster table** sorted by role (Tank / Healer / DPS), showing per player:
  - Ready status (✓ / ✗ / ?)
  - Role and spec icons
  - Flask and Food presence
  - Four raid-buff categories: **Stam**ina, **Stat**s, **Crit**, **Mast**ery
  - Item level and durability
- **Hides automatically when you pull** (`PLAYER_REGEN_DISABLED`), so it's out of your way in combat. Toggle with `/arc autohide`.
- **Exact buff details on hover** - mouse over a player to see their real flask/food tooltip text (e.g. "+300 Intellect and 300 Stamina"), not just a generic icon.
- **"Announce Missing" button** - posts who's missing flask/food to raid/raid warning chat in one click.
- **Optional ElvUI skinning** - if ElvUI is loaded, ARC reskins itself to match automatically via ElvUI's own Skins API. Falls back to a clean ~70%-opacity default skin otherwise.
- **Draggable, lockable, and remembers its position** between sessions.

## Installation

1. Download or clone this repository.
2. Copy the folder into your WoW `Interface/AddOns/` directory so the path looks like:
   ```
   Interface/AddOns/ARC/ARC.toc
   Interface/AddOns/ARC/ARC.lua
   ```
3. Restart WoW (or `/reload`) and make sure **ARC** is checked in the AddOns list at the character-select screen.

## Usage

ARC opens automatically the moment a ready check starts. You can also control it manually:

| Command | Description |
|---|---|
| `/arc` | Show/hide the window |
| `/arc lock` | Lock the window in place (disables dragging) |
| `/arc unlock` | Unlock the window |
| `/arc reset` | Reset the window to its default position |
| `/arc autohide` | Toggle auto-hide when you enter combat (the pull). Default: **ON** |
| `/arc help` | List all commands in chat |

## How the data works

This section explains what's actually possible with the WoW 5.4.8 API, and why some numbers behave differently for different players.

- **Ready status, role, and buffs** (flask / food / raid buffs) are read directly off every unit in your group with `UnitBuff()`, `GetReadyCheckStatus()`, and `UnitGroupRolesAssigned()`. This is always accurate for **everyone**, whether or not they run ARC, because that data is visible to all group members.
- **Item level and durability of other players are not exposed by the WoW API.** Blizzard removed remote-durability access, and there's no reliable "true" item level call that accounts for reforging/upgrades on other units. So ARC gets this two different ways:
  - If the other player **also runs ARC**, their client reports its own 100%-accurate item level and durability to you over a hidden addon-message channel (prefix `ARC1`).
  - If they **don't run ARC**, ARC falls back to a live `/inspect` to estimate item level (shown with a leading `~`). Durability for non-ARC players can't be retrieved at all and shows as `-`.
- **Specialization** works the same way: instant and exact for yourself, via `/inspect` or addon comms for everyone else.

**In short: the more people in your raid running ARC, the more accurate everyone's numbers are.** This is standard behavior for ready-check tools of this era, not a bug.

## Known Limitations

- Buff name matching is done against the **English (enUS/enGB)** aura names. On a non-English client, translate the strings in the buff tables near the top of `ARC.lua` to match what `UnitBuff()` returns for you.
- Durability for players not running ARC is unavailable - this is a WoW API limitation, not something ARC can work around.
- Built and tested specifically against the MoP 5.4.8 API surface; it will **not** work unmodified on later client versions.
