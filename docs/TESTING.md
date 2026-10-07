# In-game verification checklist

Automated tests validate Lua behavior and release packaging, but they cannot
replace a live 5.4.8 client, a private server's APIs or visual inspection.

## Basic update check

1. Fully restart WoW after installing the update.
2. Confirm there is no Lua error and ARC reports the expected version.
3. Open `/arc options`, change scale and toggle the minimap button.
4. Verify the window with ElvUI both enabled and disabled when possible.
5. Switch English/Slovak/Czech, scroll every settings group and test opacity,
   random demo/exit and all three numeric trash limits. Verify a real ready
   check removes the preview and no demo player enters a session/export.

## Raid window and ready check

1. Start a ready check in a party or raid.
2. Verify automatic/manual opening, ready icons and the top verdict.
3. Confirm consumables and raid-buff source tooltips.
4. Check offline, dead, AFK, out-of-range and waiting row states.
5. Test **Ready** and **Not Ready**; buttons must disable after answering and
   when the check ends.
6. Enable `/arc manual on`, hide ARC and start another check. ARC must remain
   hidden but continue tracking. Restore with `/arc manual off`.
7. Right-click a player and test Whisper, Inspect, ARC Check and Remind.
8. Test **Announce Missing** only in the intended test group/channel.

## Standalone player check

1. Inspect a non-group player and open **ARC Check** from the title bar.
2. Repeat using `/arc check` and a compatible player context menu.
3. Confirm identity appears first and only problem/unverified items follow.
4. Hover each problem-item icon and compare the native tooltip with the actual
   inspected item, including gems, enchant and upgrades.
5. Change target during a request. ARC must never show the new target's gear
   under the old name.
6. Return to the original player and use **Refresh**.
7. Close the report while waiting and ensure no stale icon or tooltip remains.

## Gear policy and minimum item level

1. Change minimum ilvl with an exact number and save using Enter and Apply.
2. Verify empty input, values outside 400–600 and Escape cancellation.
3. Test a green-quality or old-tier gem, wrong primary stat, resilience/PvP
   power and a known PvP-oriented effect.
4. Test a weak enchant and a known PvP enchant.
5. Confirm accepted blue Perfect cuts, profession enchants, DK runeforges,
   hunter scopes, shields and caster off-hands.
6. Remove/fill the Living Steel Belt Buckle socket and test a valid and PvP gem.
7. Test normal and legendary metas on caster, physical, healer and tank specs.
8. With two ARC clients, confirm professions arrive after a report and that
   Blacksmithing sockets, Jewelcrafting gems and Enchanting rings update safely.
9. Unknown or uncached IDs must remain **Unverified**, never green OK.
10. An unavailable spec must not falsely reject a valid stat-specific meta;
    a known PvP meta must still fail. Try a wrong main-stat flask with known spec
    and check its icon, Flask total and reminder; unknown spec stays neutral.

## Readiness and session checks

Run the focused [readiness checklist](READINESS_CHECKS.md#in-game-checklist-before-release)
for talents, tank stances/Righteous Fury, pets, Growl, Sacrifice, Shaman imbues,
Healthstones and mixed-version peers.

For session reporting, follow the [session live checklist](SESSION_REPORT.md)
and specifically confirm a new session's 15-second join/seven-second activity
thresholds, retroactive threshold credit, excluded 30-second revival grace,
dead/offline exclusions, ghost runback continuity and reload during a boss.
Old saved sessions keep their original limits. Settings affect only new sessions.

## Developer checks

Run the mocked Lua regression suite described in [`../tests/README.md`](../tests/README.md),
the stale-TOC guard and the release-packaging tests. Finish with `git diff
--check`. These tests are not loaded by WoW.
