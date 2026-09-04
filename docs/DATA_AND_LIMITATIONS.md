# Data sources and limitations

ARC deliberately distinguishes a confirmed problem from missing information.
When a reliable answer cannot be obtained, the UI shows **Unverified** or `?`
instead of inventing a pass or failure. The deliberate exceptions are remote
**Self** and Healthstone checks: without usable ARC data they display `OK`
(skipped) to avoid false raid blockers, with the limitation stated in tooltips.

## What the WoW client provides

| Information | Other player needs ARC? | Important limitation |
| --- | --- | --- |
| Ready state, online/dead/AFK, role | No | Requires a resolvable unit |
| Visible buffs and consumables | No | Range and private-server aura behavior apply |
| Spec and equipped gear | No | Requires inspect range and a successful inspect |
| Upgrade-aware equipped item level | No | Estimated from inspected item links/tooltips |
| Gem/enchant/primary-stat policy | No | Item and gem data must be cached and inspectable |
| Empty talent tiers | Usually no | Requires fresh GUID-matched inspect data |
| Own durability | No | Read directly and accurately |
| Remote durability | **Yes** | Durability is private and is not exposed by inspect |
| Healthstone count/charges | **Yes** | Another player's bags cannot be inspected |
| Shaman weapon-imbue presence | **Yes** | Inspect does not expose temporary enchants |
| Hunter-pet Growl autocast | **Yes** | Another player's pet spellbook is private |
| Confirmed missing remote pet | **Yes** | An unseen pet may merely be out of range |
| Hidden stance/form confirmation | Sometimes | A visible aura can be checked without ARC |

## Inspect behavior

For players without ARC, specialization, equipment and item level come from the
inspect API. Requests are GUID-checked, separated by at least two seconds and
cancel safely if another inspect replaces them. Manual ARC Check requests take
priority over the background raid queue; background scans pause while the
Blizzard inspect window is open.

The item-level scanner reads the effective value shown by the item tooltip,
including MoP upgrades, and uses standard 16-slot equipment weighting. It is
displayed with `~` because remote inspect data can be unavailable or stale.
Uncached equipment and gem data are retried after `INSPECT_READY`; incomplete
data is not marked as passed.

## Addon-channel reports

ARC reports only information the sender can reliably read about itself. The
channel improves private-data checks and freshness; it does not grant access to
arbitrary character data or bypass inspect range.

Current clients share durability, talents and class-readiness fields such as
pet state, Growl autocast, stance/form, weapon imbues and Healthstones. Older
ARC versions remain compatible, but unavailable newer fields stay unverified.
The ARC column displays **Old** for a detected older client.

Grouped clients refresh relevant reports at least every 15 seconds, subject to
the existing two-second minimum send interval. Time-sensitive pet, stance,
weapon-imbue and Healthstone information expires after 30 seconds. Remote
talent information older than 65 seconds becomes unverified until refreshed.

## Gear-policy boundaries

ARC checks required equipped slots, minimum item level, obvious STR/AGI/INT
mismatches, sockets, gem tier/quality, known PvP stats and an explicit top-tier
MoP enchant catalog. It does not attempt to optimize secondary-stat weights or
caps, socket bonuses, meta activation, trinket procs, profession ownership or
the source/vendor of an item.

An empty additional profession or belt-buckle socket cannot always be detected
when the client exposes only the base item's sockets. Gems already inserted in
extra sockets are still validated. Unknown or custom gem/enchant IDs are
**Unverified**, not automatically accepted or rejected.

See [Gear rules](GEAR_RULES.md) for the exact policy.

## Aura and server-core differences

Aura checks primarily use locale-neutral spell IDs. English-name fallbacks are
retained for private-server cores that return incomplete aura data. An aura
that the client cannot currently observe is not treated as a confirmed missing
flask, food or class buff.

Private 5.4.8 server cores can implement API details differently. When a result
looks wrong, enable Lua errors with `/console scriptErrors 1`, reproduce it
after `/reload`, and compare it with the normal character/inspect tooltip. For
an update that added files, fully restart the game before diagnosing it.

## Durability and inactivity are different signals

Remote durability is exact only when self-reported by that player's ARC. ARC
does not estimate it from deaths or repair costs.

Session trash inactivity is intentionally approximate. It measures the absence
of recorded combat participation after the configured ten-second threshold; it
is not proof of real-world AFK behavior. See [Session reports](SESSION_REPORT.md).
