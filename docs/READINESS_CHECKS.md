# Advanced Raid Check: raid setup, talents, class/tank/pet checks and Healthstones

These checks are implemented in the existing Core/UI/Options/Inspect modules.
No new TOC module, external library or automatic raid-setting changes are needed.
The PvE gem/enchant policy remains separate; a green Gear cell is not a claim
that Talents/Self or the raid setup also passed.

## API basis

ARC targets the original 5.4.8 client, not MoP Classic's modern API:

- [5.4.8 TalentFrameBase](https://github.com/Goldpaw/WoW_UI_Source_MoP/blob/master/FrameXML/TalentFrameBase.lua):
  18 talents, six tiers, three columns. `GetTalentInfo(index, inspect, nil, unit,
  classID)` returns name, texture, tier, column, selected, available. The nil
  talent-group argument asks for the active build, not the open UI's preview.
- [5.4.8 Constants](https://github.com/Goldpaw/WoW_UI_Source_MoP/blob/master/FrameXML/Constants.lua):
  class talent unlock levels; default 15/30/45/60/75/90, DK 56/57/58/60/75/90.
- [5.4.8 BuffFrame](https://github.com/Goldpaw/WoW_UI_Source_MoP/blob/master/FrameXML/BuffFrame.lua):
  temporary weapon enchants return presence, expiration, charges per hand.
  Off-hand presence is return **4**, not return 5; no enchant-ID field.
- [5.4.8 UnitPopup](https://github.com/Goldpaw/WoW_UI_Source_MoP/blob/master/FrameXML/UnitPopup.lua):
  actual instance difficulty versus selected `GetRaidDifficultyID()`.
- [5.4.8 PetActionBarFrame](https://github.com/Goldpaw/WoW_UI_Source_MoP/blob/master/FrameXML/PetActionBarFrame.lua)
  and [SpellBookFrame](https://github.com/Goldpaw/WoW_UI_Source_MoP/blob/master/FrameXML/SpellBookFrame.lua):
  `HasPetSpells`, pet spellbook slots and `GetSpellAutocast`; `GetPetActionInfo`
  returns name, subtext, texture, isToken, isActive, autoCastAllowed, autoCastEnabled.
- The installed MoP ElvUI `StanceBar.lua` uses `GetShapeshiftFormInfo` returning
  texture, **name**, active, castable. Its LibActionButton item counter uses
  `GetItemCount(item, includeBank, includeCharges)` for remaining uses.
- [WoWSims MoP warlock talents](https://github.com/wowsims/mop/blob/master/ui/core/talents/trees/warlock.json)
  identify Grimoire of Sacrifice at tier 5, column 3 (legacy talent index 15).
  The [warlock simulation](https://github.com/wowsims/mop/blob/master/sim/warlock/talents.go)
  registers its active aura as spell 108503, separately from choosing the talent.

Local installed MoP LibGroupInSpecT and ElvUI aura code were also checked for
legacy call shapes. Neither is a dependency and their implementation is not copied.

## Data handling

Talent scans require all three catalog records in an unlocked tier to match
their index/tier/column. Remote scans additionally require ARC's matched inspect
response and a loaded inspected spec. Missing or inconsistent records are unknown,
not zero selections. This cannot detect a private-server core that returns a
fully plausible but incorrect cached selection; in-game verification is necessary.
Talents do not hold up completion of an otherwise complete gear snapshot.

Self-buff spell IDs and localized names are matched against the visible helpful
aura scan. The policy checks persistent presence, not rotational procs or optimal
buff selection. Shaman shields depend on spec; unknown spec remains unknown.
Non-lethal poisons, Earth Shield on someone else, glyphs and temporary combat
procs are intentionally outside this policy. Tank/pet policies are below.
Self-buff rules only apply at level 90. Symbiosis is checked only for a known
member of our group with an online non-druid partner; partner range is not proven.
Remote Self checks run only when that player is detected on ARC. Without ARC,
the whole Self column is shown as green `OK` (skipped) instead of trusting an
incomplete remote aura list; the tooltip explicitly says it was skipped. This
avoids false missing seals and similar private-server aura omissions. The local
player remains fully checked.

`SELF_BUFF_RULES`, `SHAMAN_SHIELDS`, `SYMBIOSIS`, `TANK_BUFFS`, `RIGHTEOUS_FURY`
and `SACRIFICE` in `ARC_Core.lua` are the
editable policy. Verify actual 5.4.8 `UnitBuff` spell IDs before adding a rule.
The existing aura scanner retains both spell IDs and names, so a server's
localized spell-name fallback can still match an altered ID.

## Tank and pet policy

| Spec | Requirement |
| --- | --- |
| Protection paladin (66) | Righteous Fury (25780) present |
| Holy/Retribution paladin (65/70) | Righteous Fury absent |
| Blood DK (250) | Blood Presence (48263) |
| Protection warrior (73) | Defensive Stance (71) |
| Guardian druid (104) | Bear Form (5487) |
| Brewmaster monk (268) | Stance of the Sturdy Ox (115069) |
| Hunter, Frost mage (64), Unholy DK (252) | Living permanent pet |
| Warlock, Sacrifice selected | Active Grimoire of Sacrifice buff (108503) |
| Warlock, another/no tier-five choice | Living permanent pet; empty talents also fail Talents |

Use spec, never the manually assigned group role. Unknown spec/talent choice
is unverified. The policy intentionally does not prescribe secondary-stat
optimization, non-tank stances or pet species. Temporary guardians are not required.

A visible correct form aura confirms presence. Missing form auras are not
reliable negative evidence on all MoP clients. The owner instead reads the
legacy shapeshift API, matches the localized form name and reports active/inactive.
Only a fresh same-spec form report can confirm absence; offline/dead players
remain unverified. Mounted/in-vehicle local form reads are also unverified.
RF uses the normal aura check, including forbidden RF on non-Protection paladins.

Visible pet GUIDs and death state are read from `pet`, `partypetN`, `raidpetN`
or `targetpet`/`focuspet`/`mouseoverpet`. A visible pet overrides an older absence
report. No visible remote pet does **not** mean it is missing: only its owner's
fresh report can confirm that. Own absence while mounted/in a vehicle is unknown.
Warlock talent choice expires after 65 seconds and is bound to the inspected or
reported spec; Sacrifice's visible buff is still required when selected.

Hunter Growl (2649) is checked for **autocast enabled**, not recent casts or
cooldown. The owner's ARC searches the full pet spellbook, then its action bar.
A supported autocast ability with nil/false/0 enabled means OFF in the original
API; a missing ability/API means unknown. Remote Growl requires an owner report
for the same pet GUID. ARC never changes autocast, summons a pet or changes form.

## Healthstone policy

Check item 5512 in bags, excluding bank contents. Read item count first, then
`GetItemCount(5512, false, true)` for charges (0–3). Known item presence with
unavailable charge data remains unverified. A zero item count or zero remaining
charges is a confirmed problem. No cooldown or immediate-usability claim is made.

The HS check applies only when the subject is a GUID-matched member of our
current group and an online warlock is in that group. Supplier range or actual
ability to create a stone is not proven. Solo/non-group city checks and groups
without such a warlock show neutral `-`. Remote bags require updated ARC;
only a current ARC report can produce a confirmed missing `!0`. No ARC, an old
or expired report, and unavailable charge counts show green `OK` (skipped) so
private bag data cannot hold the raid verdict in an incomplete state. The
tooltip states when the value was not verified.

## Readiness wire extension

The original six caret-separated fields remain unchanged. Three optional fields
are appended: `R1`, six-character talent code, two-character weapon code.
The newer preparation extension appends another seven fields after those:
`P1`, pet code, Growl code, Sacrifice choice, Healthstone code, pet GUID, tank-form code.
Do not replace R1: earlier clients still read its talent/weapon fields.

- Talent code per tier: `1` selected, `0` confirmed empty, `x` locked, `?` unknown.
- Weapon code per hand: `1` temporary enchant present, `0` absent, `x` no applicable
  weapon (including shields/caster offhands), `?` unknown.
- Pet: `1` alive, `d` dead, `0` confirmed absent, `?` unknown.
- Growl: `1` autocast ON, `0` OFF, `?` unknown. GUID is required for alive/dead
  pet reports; `-` means unavailable. GUIDs are bounded and exclude markup/delimiters.
- Sacrifice: `1` selected, `0` not selected, `?` unverified; class/spec bound.
- Healthstone: `0`–`3` uses, `p` present but charge count unknown, `?` unavailable.
- Tank form: `1` active, `0` inactive, `?` unknown, bound to the payload's spec.
- Incoming code alphabet/length and message length (255 bytes) are validated.
  Sender identity comes from the game channel and must resolve to our group,
  never the payload's claimed player name. Invalid extensions do not manufacture
  passed checks; older clients still supply the original gear/durability data.
- Talent/Sacrifice freshness: 65 seconds. Weapon/preparation freshness: 30 seconds. While grouped,
  self reports refresh every 15 seconds, even with ARC hidden, and retain the
  existing 2-second minimum interval. No additional inspect is sent for imbues.
- Pet, bag, stance, aura and talent events mark the local report dirty. Incoming
  older R1-only/base reports clear preparation fields; they cannot renew P1 data.
  Existing inspect talent evidence may remain until its normal expiry.
- Weapon presence cannot tell Windfury from Flametongue, Earthliving, oils or
  another temporary enchant. No client/report means unknown, not missing.

## Roster refresh, expiry and reminders

The visible roster updates ready status, connection, death and visibility every
second. `UNIT_AURA` refreshes only the affected player immediately; roster/pet
events are likewise targeted. A full refresh remains every five seconds as a
safety net for private-server clients that omit an event. Inspect requests keep
their existing queue/rate limits. The footer reports completed versus total gear
scans and separately identifies waiting or unavailable players.

`PLAYER_FLAGS_CHANGED` updates AFK immediately. The name gains `(afk)`, the row
turns amber and AFK is a confirmed pull blocker. Offline and dead players are
also blockers. The top banner reports READY TO PULL only with no confirmed or
unverified findings; confirmed failures produce NOT READY and take color
priority, while otherwise unknown data produces CHECK INCOMPLETE. Raid setup
status remains on the banner's second line and can independently make it red.

Timed flask and food auras warn at five minutes remaining. They keep their real
icons but turn amber; missing remains red and unavailable remains unknown. The
summary's `Soon` count is per expiring consumable, not per player. Announcements
and private reminders distinguish missing from expiring effects.

Remind includes only confirmed personal findings: flask/food, completed gear
audit issues, empty talents, class/tank/pet readiness and Healthstone. It omits
unknown checks and sends no message when there are no confirmed findings.
ARC versions are compared as numeric `major.minor.patch`; malformed reports are
unverified, older clients are marked `Old`, and newer peers are not accused.

## In-game checklist before release

1. Open `/arc raid`; select your expected mode/size and loot. Deliberately choose
   a different expectation and confirm the red banner shows actual -> expected.
   Restore the expectation and confirm it clears. ARC must not alter game settings.
2. Verify actual difficulty inside an instance, selected difficulty outside,
   loot changes and reopening Options. Test with and without ElvUI. Confirm
   banner, summary, columns and ready-response buttons do not overlap at your scale.
   Fill a 25-player roster and verify mouse-wheel/scrollbar access at 0.6, 1.0
   and 1.5 scale on the smallest supported screen resolution.
   Toggle AFK and confirm the name, amber row and NOT READY verdict update
   without waiting for the five-second full refresh.
3. Leave an available talent tier empty, ready check and inspect it. Confirm a
   red Talents cell and the correct tier in the report. Fill it and repeat. Inspect
   someone without ARC, change targets mid-request, and test a partial cache.
4. Remove/reapply each supported self buff. Test both priest alternatives,
   shaman specs, rogue lethal poisons, mage armors and paladin seals. Verify
   missing glyphs do not appear as failures.
5. Test Symbiosis in a mixed-class group, an all-druid group and a solo city check.
6. On a shaman, independently remove main/off-hand imbues and check reports from
   a second updated ARC client. Equip a shield and confirm no off-hand imbue error.
   Close ARC, reapply/expire the imbue and wait for the next report (up to 15 sec).
7. Use an older/no-ARC peer and take an updated peer out of range/offline. Expired
   imbue reports must become unknown, not silently good or falsely missing.
   Confirm the old peer shows `Old`, its tooltip names the current version and
   the footer's inspect waiting/unavailable counts change as players move range.
   Test flask/food above and below five minutes and inspect the Remind whisper.
8. Test Protection paladin RF missing/present, then switch to Holy/Retribution:
   present RF must be red there. Changing only the group role must not change
   the spec-based rule. Test unknown spec and dead/offline states.
9. Switch Blood DK, Protection warrior, Guardian and Brewmaster in/out of their
   required presence/stance/form. Compare a second ARC's row and standalone
   snapshot; test aura-hidden and no-ARC cases (unknown without proof).
10. Dismiss, summon, kill and revive required permanent pets. Test hunter,
    Frost mage, Unholy DK and non-Sacrifice warlock. Test a mounted owner,
    remote/out-of-range pets, party and raid pet tokens, and a no-ARC owner.
11. Toggle hunter Growl autocast ON/OFF, remove Growl from the action bar and
    repeat. Change pets with different autocast settings. Old pet reports must
    not accuse the new pet; lack of API data must stay unknown.
12. Choose Sacrifice with no buff (red), cast it (clear), remove/expire the buff
    (red), then select Supremacy/Service and summon/dismiss the permanent pet.
    Repeat after a spec switch and with an inspected player without ARC.
13. In a group with a warlock, create/use all three Healthstone charges and
    verify HS 3/2/1/!0 on another ARC, including while the sender window is hidden.
    Test no stone, old/no ARC, expired reports, no-warlock groups and solo city
    checks. Do not treat cooldown as missing. Confirm HS and Self errors appear
    in the summary and as direct lines in the standalone report.

Automated tests validate Lua control flow and mocked widget state, not the live
client's network/cache behavior or exact rendered layout.
