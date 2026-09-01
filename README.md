# ARC — Advanced Ready Check

ARC is a lightweight ready-check overview for World of Warcraft: Mists of
Pandaria 5.4.8 (`Interface 50400`). It shows the group roster together with
ready status, role, specialization, consumables, raid buffs, upgrade-aware item
level, durability, missing gems/enchants and basic spec-appropriate gear checks.
The roster also identifies who is running ARC and which version they report.

Roster row states are color coded:

- strongly faded — offline
- soft red — dead or ghost
- soft grey — aura/required inspect data is out of range
- soft yellow — waiting for the first inspect result

Unavailable aura data is never counted as a missing flask or food and is
skipped by reminder/announcement actions.

## Installation

1. Copy the `ARC` directory into:
   `World of Warcraft/Interface/AddOns/`
2. The resulting path must contain `ARC/ARC.toc` (not `ARC/ARC/ARC.toc`).
3. Restart the client or run `/reload` after replacing addon files.
4. Enable **Load out of date AddOns** only if the server reports a different
   interface number despite using a 5.4.8 client.

ARC has no required external libraries. ElvUI integration is optional and is
detected automatically.

## Usage

The window opens automatically when a ready check begins. Use `/arc` to show
or hide it manually. Hover a player row for details and right-click a row for
Whisper, Inspect and Remind actions. Hover the Stam, Stat, Crit or Mast header
to see the detected source of that raid buff.

Available commands:

- `/arc` — show or hide the window
- `/arc lock` — lock the window position
- `/arc unlock` — unlock the window position
- `/arc reset` — reset the window position
- `/arc autohide` — toggle hiding on combat start
- `/arc minimap` — toggle the minimap button
- `/arc options` — open the options panel
- `/arc help` — print the command list

Settings are saved account-wide in `ARC_DB`.

The options panel also contains a configurable minimum item-level threshold
(default **450**). Individual items below it are reported in the player tooltip.

## Data accuracy and limitations

- Ready state, role and visible auras come directly from the WoW unit API.
- The local player's item level and durability are read directly and are
  accurate.
- Remote durability is not exposed by the client. It is available only when
  the other player also runs ARC and reports their own value through the addon
  channel. The row shows the lowest equipped-item durability; the tooltip also
  shows the average. Without ARC it is displayed as `N/A` rather than inventing
  an unreliable estimate.
- For players without ARC, item level and specialization use the inspect API.
  The item-level scanner reads the value shown by the item tooltip, including
  MoP item upgrades, and uses the standard 16-slot equipment weighting. It is
  still marked as an estimate (`~`) because inspect data can be unavailable or
  stale while a player is out of range.
- Gear inspection reports empty gem sockets, missing enchants on normally
  enchantable slots, items below the configured threshold, empty required
  slots, and obvious STR/AGI/INT mismatches for the inspected specialization.
  It deliberately does not judge secondary-stat priorities or trinket procs.
- Aura detection primarily uses locale-neutral spell IDs. English aura-name
  fallbacks are retained for private-server cores that return incomplete aura
  data.
- A server core may implement parts of the 5.4.8 API differently. If something
  is missing, first test with Lua errors enabled (`/console scriptErrors 1`),
  then `/reload` and repeat the ready check.

## Files

- `ARC_Core.lua` — database, roster, aura scanning and addon communication
- `ARC_Gear.lua` — upgrade-aware item level and configurable gear rules
- `ARC_Inspect.lua` — inspect queue, specialization and item-level fallback
- `ARC_UI.lua` — main window, rows, tooltips and announcements
- `ARC_Options.lua` — minimap button and Interface Options panel
- `ARC.lua` — event dispatch and slash commands
- `ARC.toc` — addon metadata and load order
- `changelog.txt` — release history

The load order in `ARC.toc` is significant. `ARC_Core.lua` must remain first
and `ARC.lua` must remain last.

## Quick verification checklist

After updating the addon:

1. Run `/reload` and confirm there is no Lua error.
2. Open `/arc options`, change the scale and toggle the minimap button.
3. Start a ready check in a party or raid.
4. Verify ready icons, consumables and raid-buff source tooltips.
5. Right-click another player and test Whisper or Inspect.
6. Test **Announce Missing** in the intended group channel.

## Version

Current version: **1.3.3**

## License

ARC is released under the [MIT License](LICENSE).
