# ARC — Advanced Raid Check

ARC is a lightweight raid-preparation and ready-check addon for World of Warcraft: Mists of
Pandaria 5.4.8 (`Interface 50400`). It shows the group roster together with
ready status, role, specialization, consumables, raid buffs, upgrade-aware item
level, durability, missing gems/enchants, MoP PvE gem/enchant checks, empty
talent tiers, class buffs, tank stances, pets and reported Healthstone uses.
A visible raid-setup banner warns
about unexpected raid mode/size or loot settings.
The roster also identifies who is running ARC and which version they report.

Version 1.5.0 uses the name **Advanced Raid Check**, reflecting the broader raid,
gear and player-readiness checks. This is a display-name change: keep the addon
folder named `ARC`. `ARC.toc`, `/arc`, `ARC_DB`, frame identifiers and the `ARC1`
communication prefix remain unchanged. Existing settings, enabled-addon state
and compatible group reports do not need migration. Install over the same `ARC`
folder; do not keep a second renamed copy. Ready-check buttons, game events and
API names still refer to the game's ready-check feature, not the product name.

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
3. Fully exit WoW to the desktop and start the client again after updating.
   On this MoP client, `/reload` can retain the old TOC/file list and miss newly
   added modules. In particular, upgrading to 1.5.0 requires a full restart.
4. Enable **Load out of date AddOns** only if the server reports a different
   interface number despite using a 5.4.8 client.

ARC has no required external libraries. ElvUI integration is optional and is
detected automatically. When ElvUI is loaded, ARC adopts its transparent frame
template, media colors, fonts, buttons, row highlights and icon borders.

## Usage

By default the window opens automatically when a ready check begins. Enable
**Manual opening only** in Options or use `/arc manual on` to stop automatic
opening. `/arc manual off` restores it, and `/arc manual` toggles the mode.
Use `/arc` or left-click the minimap button to show or hide it manually.
Manual mode does not close an already-open window, stop ready-check tracking,
or suppress the standard Blizzard ready-check dialog. Combat auto-hide is a
separate setting and continues to apply if enabled.

**Ready** and **Not Ready** in the top-right corner answer your own active
ready check. They are disabled outside a check, after an answer or on expiry.
ARC never answers automatically; responding through the standard Blizzard
dialog is still supported. After a successful ARC response that dialog closes.

Hover a player row for details and right-click a row for
Whisper, Inspect, ARC Check and Remind actions. Hover the Stam, Stat, Crit or Mast header
to see the detected source of that raid buff.

Available commands:

- `/arc` — show or hide the window
- `/arc lock` — lock the window position
- `/arc unlock` — unlock the window position
- `/arc reset` — reset the window position
- `/arc autohide` — toggle hiding on combat start
- `/arc manual [on|off]` — toggle or explicitly set manual-only window opening
- `/arc minimap` — toggle the minimap button
- `/arc options` — open the options panel
- `/arc raid` — configure the expected raid mode/size and loot method
- `/arc check` — open a detailed check of the targeted player (no group required)
- `/arc help` — print the command list

Settings are saved account-wide in `ARC_DB`.

The options panel contains a numeric minimum item-level field (default **450**).
Type a whole number from **400 to 600**, then press **Enter** or **Apply** to
save. **Escape** cancels an edit. Invalid/empty input leaves the saved value
unchanged; typing alone does not change it. Raid gear results are invalidated
after a change and your own gear is rescanned. Individual items below the
threshold appear in the player tooltip and standalone report; an existing
standalone snapshot retains its original threshold until **Refresh**.

## Raid setup warning

Click the wide banner above the roster, use `/arc raid`, or select **Raid Setup
Checks** in Options. Choose the expected mode (**10/25 Normal/Heroic**, Raid
Finder or Flexible) and loot method from the selection menus. Settings save
immediately and can be disabled independently with **Not checked**; the checkbox
disables the entire raid-setup check. Both expectations initially remain unset
instead of guessing your server's preferred raid setup.

- **Red: RAID SETUP MISMATCH** shows the actual and expected values directly.
- **Amber: UNVERIFIED** means required API data is unavailable; **NOT CONFIGURED**
  asks you to choose expectations.
- **Green: OK** means the selected checks match. If only one setting is checked,
  this is explicitly labelled. Outside a raid, when disabled or in a PvP instance,
  the banner shows a neutral status.

Inside a raid instance, the actual instance difficulty takes precedence over
the selected raid difficulty. Outside it, the selected raid difficulty is used.
10/25 refers to the mode's capacity, not invited player count; bench players do
not create a mismatch. ARC never changes difficulty/loot, starts a ready check,
or sends chat automatically. The warning stays inside ARC and respects manual
opening and combat auto-hide settings.

## Talents, class buffs, tanks and pets

The **Talents** and **Self** roster columns show **red !N** for confirmed
problems, **yellow ?** for unverified data, **OK** for passed applicable checks,
and **-** when no check applies. Hover a row for the exact problems. The summary
counts affected players, not individual missing buffs/tiers. Standalone checks
also list these findings directly in separate Talents and Self / Tank / Pet sections;
healthy results remain hidden there.

**Talents:** require one selected talent in every unlocked tier of the active
build. Unlock levels come from the MoP class table, including DK-specific levels.
Own talents are read locally; others use a GUID-matched inspect response or a
current ARC report. Missing/partial API data is not treated as an empty tier.
Remote talent data older than 65 seconds becomes unverified until refreshed.
**Glyphs are not checked**, and talent choices are not ranked or optimized.

**Self checks:** the policy targets level-90 characters:

| Class | Required presence |
| --- | --- |
| Rogue | One lethal poison: Deadly or Wound; non-lethal poisons are optional |
| Shaman | Lightning Shield for Elemental/Enhancement, Water Shield for Restoration; temporary imbue on equipped weapons |
| Priest | Inner Fire or Inner Will |
| Druid | Symbiosis, only when in your group with an online non-druid partner; Guardian also needs Bear Form |
| Mage | Mage, Frost or Molten Armor; Frost also needs a living Water Elemental |
| Paladin | Any seal; Protection requires Righteous Fury, Holy/Retribution must turn it off |
| Death Knight | Blood requires Blood Presence; Unholy requires a living permanent pet |
| Warrior | Protection requires Defensive Stance |
| Monk | Brewmaster requires Stance of the Sturdy Ox |
| Hunter | Living permanent pet; its Growl autocast must be OFF |
| Warlock | Grimoire of Sacrifice selected: active Sacrifice buff required; otherwise a living permanent pet |

Visible aura checks work without ARC on the other player. Dead/offline units or
unavailable aura data do not produce missing-aura accusations. Unknown shaman
spec is unverified. Tank rules use the actual spec, not the manually assigned
group role. Solo/unknown-group druids in the city and all-druid groups
are not required to have Symbiosis. Below level 90, self-buff policy is skipped;
talent checks still respect each character's unlock levels.

**Tank stances/forms:** a visible correct aura can confirm presence without
another ARC. When the client does not expose that aura, the owner's updated ARC
reads the original MoP stance/form API. Only a current, same-spec report can
confirm a missing stance; hidden auras alone are not proof of an error.

**Pets:** a visible living/dead pet can be checked without another ARC, but
confirmed absence needs the owner's report. An unseen remote pet could simply
be out of range, so it stays **?**, not a false missing-pet warning. Own missing
pets while mounted/in a vehicle are unverified. Temporary guardians are not
required. Warlock talent choice comes from inspect or ARC (65-second freshness);
choosing Sacrifice without its buff is a failure, not a pet exemption by itself.

**Hunter Growl autocast requires the hunter's updated ARC.** It reads the entire
pet spellbook, with an action-bar fallback, so Growl need not occupy a bar slot.
The warning concerns enabled autocast, not manual use or cooldown. Reports are
bound to the pet GUID; changing pets cannot reuse the old pet's Growl result.
ARC never toggles pet abilities, summons pets or changes stances automatically.

**Shaman weapon imbues require the other player's updated ARC.** Legacy inspect
does not expose them. ARC reads its own temporary-enchant presence and shares
it, including with the window closed. Reports refresh at least every 15 seconds
while grouped and retain the existing two-second send throttle; imbue reports
expire after 30 seconds. Old peers remain compatible but provide no imbue data.
Shields/caster off-hands do not need an imbue. This is a presence check, **not**
verification of Windfury versus Flametongue/Earthliving: the original MoP API
does not return the enchant ID. Another temporary weapon enchant can satisfy it.

## Healthstones

The **HS** column shows the remaining reported uses (**1–3**), **red !0** for
missing/fully consumed, **yellow ?** for unverified, or **-** when not applicable.
It applies only to members of your current group with an online warlock supplier;
solo city checks and groups without a warlock do not demand a Healthstone.
The summary counts affected players, and missing/unverified Healthstones also
appear directly in the standalone Readiness section.

Inspect cannot read another player's bags: **their updated ARC is required**.
ARC counts Healthstone charges, not just items, and excludes bank contents.
If presence is known but charges are unavailable, it explicitly remains unverified.
This does not check cooldown or guarantee the item can be used immediately.
Pet, Growl, tank-form and Healthstone reports expire after 30 seconds and share
the existing 15-second grouped heartbeat and two-second minimum send interval.
Bag, pet, stance and talent changes also trigger refreshed reports. Older ARC
versions remain compatible; unavailable new fields stay unverified.

See [readiness implementation notes and test checklist](docs/READINESS_CHECKS.md).

## Individual player check

If `/arc check` reports that `ARC_PlayerCheck.lua` is not loaded, fully restart
WoW, not just `/reload` or logout. A log showing ARC 1.4.0 in the addon list but
`ARC.VERSION = "1.5.0"` in Lua is a sign of a cached old TOC. If a restart does
not help, verify that `ARC_PlayerCheck.lua` is beside `ARC.toc` and listed in it
before `ARC.lua`; reinstall the complete update and check the earliest Lua
error. Until the module loads, ARC keeps the raid UI working and explains why
the standalone check is unavailable, without repeated event/update errors.

Inspect another player and click **ARC Check** in the top-right title bar,
just left of the close button. The title leaves room for it, including long names.
Alternatively target them and use `/arc check`. They do not need ARC and do
not need to be in your group. Your own gear remains available in `/arc`.

**ARC Check** is also available in the player's right-click menu (target/focus
portrait or party/raid frame), including ElvUI frames that use the standard
player menu, and in ARC's own row menu. Opening the menu does not inspect anyone;
the check starts only when clicked. Offline/out-of-range players have a disabled
entry. The action remembers the chosen player and rechecks identity and range
on click, so a changed target cannot silently check someone else.
Name-only menus such as chat/friends offer the action only when the exact
name/realm resolves to a known target, focus, mouseover or group unit. ARC cannot
inspect an arbitrary chat/friends name without an available player unit.

The separate, draggable window starts with player name, class/level, spec/role,
guild and estimated upgraded item level. Below that, **Gear Check** shows only
problem equipment slots, with the item name and specific reasons. Healthy items
and zero counters are omitted; the normal inspect window already shows gear.
All findings are written directly in the window, with optional ElvUI styling.

Each equipped problem item has its actual icon before the red item name.
Hover the icon for the normal item tooltip, using the captured full item link
(including its gems, enchant and upgrade fields). Changing target never swaps
that tooltip to the new target's equipment. This is a snapshot: use **Refresh**
to check later changes. Empty slots have no item icon; unavailable icon data uses
a question mark. Closing/reusing a report clears its old item tooltips.

**Unverified** separates unavailable item/gem data, unknown enchant IDs and
unknown specializations from confirmed issues. Such a result is never green
OK; the raid Gear column uses `?` when there are no confirmed issues but some
checks remain unverified. Missing flask/food and reported repair needs appear
separately under **Readiness** as a snapshot, not as a gear failure. Healthy
consumables and passive buffs do not clutter the standalone report.

**Refresh** rechecks the same character, never a newly selected target. When
the original player is no longer available, the previous result remains a
clearly labelled snapshot. Select that player again before refreshing.
The standalone window does not add strangers to the raid roster or send chat.
Durability is unavailable through inspect; a recent ARC group report may be
shown if one already exists.

Manual checks take priority over ARC's raid queue. Background scans pause
while the Blizzard inspect window is open. Requests are GUID-checked, spaced
at least two seconds apart, and abort safely if another inspect replaces them.
Uncached equipment and gem data are retried locally after `INSPECT_READY`;
incomplete data is never marked as a passed check. Equipped ilvl can still be
shown while gem validation is pending. Close the window to cancel a request.

## PvE gem and enchant policy

Both the raid tooltip and standalone report use the same rules:

- Gems must be MoP-tier and at least **rare (blue) quality**, not green quality.
  Blue-quality Perfect cuts, Serpent's Eyes, cogwheels, Sha-touched gems and
  legendary metas are supported. Quality is not the gem/socket's physical color.
- Flag the wrong STR/AGI/INT, resilience, PvP power and known PvP-oriented meta
  effects. Legendary meta procs are checked for caster/physical or tank/healer
  applicability. Secondary-stat priorities and rating caps are not optimized.
- Check permanent enchants against an explicit top-tier MoP list, flag lower
  ranks, wrong main stats and PvP-oriented bonuses, and support profession
  alternatives, DK runeforges, hunter scopes, shields and caster off-hands.
- Unknown/custom IDs are **Unverified**, not automatically good or bad. Ring
  enchants are checked if present but not required without profession evidence.

"Top tier" means the approved highest-rank options for that slot/stat, not a
claim that one enchant is always best for every build. PvP-sourced cosmetic
variants with the same PvE effect (Spirit of Conquest/Bloody Dancing Steel)
are accepted; resilience/PvP-power enchants are not.

See [the exact policy, exceptions, sources and editing instructions](docs/GEAR_RULES.md).
The small catalog is bundled in ARC; there is no new runtime library or network
dependency.

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
  slots, obvious STR/AGI/INT mismatches, gem quality/tier and enchant policy.
  It does not judge secondary-stat weights/caps, socket bonuses, meta activation,
  profession ownership, trinket procs or whether an item came from a PvP vendor.
  An empty extra profession/buckle socket cannot be guaranteed if the client
  exposes only base-item sockets. Inserted gems in extra sockets are still checked.
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
- `ARC_PlayerCheck.lua` — inspect/context-menu actions and independent player report
- `ARC_Options.lua` — minimap button and Interface Options panel
- `ARC.lua` — event dispatch and slash commands
- `ARC.toc` — addon metadata and load order
- `changelog.txt` — release history
- `docs/GEAR_RULES.md` — PvE policy, data source and customization notes
- `docs/READINESS_CHECKS.md` — readiness rules, API/protocol notes and live-test checklist
- `docs/RELEASE_CHECKLIST.md` — release-candidate validation and packaging checklist
- `docs/WOWSIMS_LICENSE.txt` — MIT notice for the bundled catalog data

The load order in `ARC.toc` is significant. `ARC_Core.lua` must remain first
and `ARC.lua` must remain last.

## Quick verification checklist

After updating the addon:

1. Fully restart WoW after the update and confirm there is no Lua error.
2. Open `/arc options`, change the scale and toggle the minimap button.
3. Start a ready check in a party or raid.
4. Verify ready icons, consumables and raid-buff source tooltips.
5. Right-click another player and test Whisper or Inspect.
6. Test **Announce Missing** in the intended group channel.
7. Inspect a non-group player, click **ARC Check**, and confirm identity appears
   first, followed only by problem slots. A clean check should have no item list.
8. Change target during a check and verify it never displays the new player's
   gear under the old name. Return to the original player and use **Refresh**.
9. Test the detail window with ElvUI enabled and disabled, including closing
   the window while a check is waiting for data.
10. Enable `/arc manual on`, hide ARC and start a ready check. Confirm ARC
    stays hidden, then open it from the minimap and answer with **Ready** or
    **Not Ready**. Repeat with `/arc manual off` and check auto-opening.
11. Verify response buttons disable after answering and when the check ends.
12. Enter an exact minimum ilvl in Options, save with Enter/Apply, and test
    empty input, out-of-range values and Escape cancellation.
13. Check green/old gems, a wrong primary-stat gem, a PvP gem and a weak/PvP
    enchant. Compare findings with the actual item links/tooltips.
14. Check blue Perfect cuts, profession enchants, a DK runeforge and a hunter
    scope. Unknown/uncached data must stay Unverified, never green OK.
15. Follow the [readiness checklist](docs/READINESS_CHECKS.md#in-game-checklist-before-release)
    for tank stances/RF, pet death/dismissal, Growl autocast, Sacrifice, Healthstones,
    talent tiers and mixed-version peers before publishing the release.
16. Hover a problem item's icon and compare the native tooltip with its actual
    inspected item, including gems/enchant/upgrades. Change targets, refresh to
    an empty/healthy slot and close the report: no stale icon/tooltip should remain.
    Check the full **Talents** header and neighboring columns at your UI scale.

The mocked Lua regression suite and its limitations are described in
[`tests/README.md`](tests/README.md). These developer tests are not loaded by
WoW and do not replace in-game visual/API testing.

## Version

Current version: **1.5.0**

## Automatic release packaging

The **Package ARC release** GitHub Actions workflow runs when you click
**Publish release** (including a published prerelease, but not a saved draft).
It tests the tagged code with Lua 5.1, verifies matching versions, and attaches
`ARC-<version>.zip` plus its SHA-256 checksum to that release.

The installation ZIP contains **only** the TOC-listed `.lua` modules, `ARC.toc`,
`changelog.txt` and `LICENSE`, under a single `ARC/` directory. README, `docs/`,
tests and build tooling stay in the repository. The catalog's third-party MIT
notice is embedded in `ARC_Gear.lua` and remains in the distributed addon.

Before a new release, update the version in `ARC.toc`, `ARC_Core.lua`, this README
and the first section of `changelog.txt`, commit/push, then choose a matching tag
such as `v1.5.1`. The tagged commit must include the workflow and `scripts/`.
No private token or additional secret is needed; publishing uses GitHub's
repository-scoped `GITHUB_TOKEN`. The workflow must first be pushed to GitHub.

If the release description is empty, ARC fills it from that version's changelog
and adds installation instructions. User-written or GitHub-generated descriptions
are preserved. Existing identical assets are skipped on reruns; different assets
with the same name are never deleted or overwritten automatically.

**Actions → Package ARC release → Run workflow** runs a validation/build-only
preflight: it does not create a release or upload assets. A release is already
public while its packaging runs; failures leave it without a new ZIP, so confirm
the Actions run is green before announcing it. The published 1.5.0 release is
not changed or rebuilt retroactively by installing this workflow.

See the [release checklist](docs/RELEASE_CHECKLIST.md) for the exact steps.

## License

ARC is released under the [MIT License](LICENSE).
The embedded WoWSims-derived catalog retains its [MIT notice](docs/WOWSIMS_LICENSE.txt),
also included directly in `ARC_Gear.lua`.
