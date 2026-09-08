# ARC — Advanced Raid Check: MoP PvE gear policy

The raid tooltip and standalone player check call the same analyzer in
`ARC_Gear.lua`. This is a conservative raid-policy check, not a simulation or
best-in-slot recommendation. The report shows confirmed problems first and
unverified checks separately. The full equipment list stays in Blizzard Inspect.

Problem-item rows include a captured item icon before the red item name.
Hover uses the original MoP `GameTooltip:SetHyperlink` with the full snapshot
link, retaining gems, enchant and upgrade fields. It never reads a new target's
inventory on hover. Empty slots have no icon; native tooltip data may still
depend on the client's cache. Refresh the report to capture changed equipment.

## Equipment type and weapon setup

- At level 50 and above, the eight primary armor slots must use the class armor
  specialization: cloth, leather, mail or plate. Cloaks, jewellery, trinkets and
  weapons are excluded. ARC reports a failure only when the client returns a
  recognized localized armor subtype.
- A loaded one-handed main-hand weapon requires an equipped off-hand item or
  second weapon. ARC does not report an empty off-hand while its inspect data is
  still loading, and two-handed or hunter ranged weapons remain valid alone.

## Gems

- Approved catalog: 186 MoP gem item IDs, including ordinary rare cuts, blue
  Perfect cuts, Serpent's Eyes, engineering cogwheels, Sha-touched gems and
  legendary metas. Rare means item quality 3, not socket color. Quality 4/5
  profession/legendary gems are not downgraded merely for not being blue.
- For known gems, check the catalog stats, with client item quality when
  available. Wrong STR/AGI/INT fails; a pure secondary-stat gem is not rejected
  merely for lacking the primary attribute. No stat weights or hit caps.
- Reject any PvP power/resilience, including hybrid gems with a useful main
  stat. The PvE policy also excludes these Primal Diamonds for their CC/reflection
  effects: Destructive 76890, Powerful 76891, Enigmatic 76892, Impassive 76893,
  Forlorn 76894. Tyrannical 95348 fails its PvP stats.
- Legendary meta applicability: Indomitable 95344 is tank, Courageous 95345
  healer, Capacitive 95346 physical and Sinister 95347 caster. Tanks may use
  their matching physical DPS meta and healers may use a matching caster meta.
  Normal top-tier alternatives are limited to matching STR/AGI/INT, healer and
  tank Primal Diamonds. Fleet and the PvP/CC metas are rejected. MoP Primal and
  legendary metas have no old color-count activation requirement; an empty or
  unreadable meta socket is handled by the normal missing/Unverified rules.
- For an uncatalogued gem with client item data, quality below 3 or gem ilvl
  below 90 identifies a weak/old tier. Available live stats can additionally
  identify wrong primary/PvP stats. Other uncatalogued gems remain Unverified.
- Never use raw nonzero gem fields from a legacy equipment link as gem item IDs.
  They prove a socket is filled, but `GetItemGem` resolves the actual item.
  A missing gem response is Unverified and retried within the inspect timeout,
  not reported as an empty socket or a valid gem.

## Enchants

`ENCHANT_RULE_DATA` contains 254 known effect IDs, including older and rejected
options, not 254 approved enchants. IDs are permanent enchant **effect IDs**
from the equipment link, not enchanting spell IDs or scroll item IDs.

`top = true` is an explicit ARC policy selection. It accepts the top MoP rank
for the chosen stat/slot, not one universal best enchant for every spec. For
example, mastery/crit/hit options are not ranked against primary-stat options
using a damage simulation. Multiple-stat enchants and adaptive Dancing Steel
must not fail simply because they can also provide another class's stat.

Supported top-tier families include:

- Greater shoulder inscriptions and stronger scribe-only Secret inscriptions.
- MoP bracer, chest, cloak, glove and boot stat enchants.
- Shadowleather/Angerhide/Ironscale leg armor and Greater spellthreads;
  corresponding highest profession reinforcements/spellthreads.
- Rank-3 fur linings and embroidery; optional greater ring enchants.
- Jade Spirit (INT), Dancing Steel (STR/AGI), River's Song (tank), hunter Scope
  of Doom, Major Intellect for caster off-hands/shields and Greater Parry shields.
- DK runeforges are a class-specific exception to expansion/rank age. They are
  not ranked against one another or rejected merely for pre-MoP spell IDs.

Known lower ranks fail, including ordinary shoulder inscriptions, weak leg
armor/spellthreads, Windsong, Elemental Force, Colossus and Mirror Scope. Those
can be usable in other contexts but are below this server's strict raid policy.
Missing permanent enchants follow the existing rare-or-better armor-slot rule.

PvP power/resilience enchants fail. Living Steel Weapon Chain is excluded by
the raid policy for its disarm-oriented effect. Spirit of Conquest (5124) and
Bloody Dancing Steel (5125) are accepted as PvE-effect equivalents of Jade
Spirit/Dancing Steel; PvP reward provenance alone is not a stat defect.

Rings are audited if enchanted and become required when Enchanting is confirmed
locally or by a fresh ARC profession report. Buckles, engineering tinkers and
optional added sockets are not substitutes for ordinary stat enchants.

## Belt buckle and profession bonuses

- A rare-or-better waist item at raid level (450+) must have one filled added
  Living Steel Belt Buckle socket beyond its base sockets. Because some 5.4.8
  cores cannot distinguish an unapplied buckle from an applied but empty added
  socket, both states use the confirmed finding **Missing or empty Living Steel
  Belt Buckle socket**. The inserted gem is checked by the normal top-tier MoP
  PvE policy, including primary/secondary usefulness and PvP rejection.
- ARC reads the local player's two primary professions and sends their numeric
  skill-line IDs through the backwards-compatible `F1` addon-channel extension.
  A fresh report lets another ARC client require only reliably visible bonuses:
  Blacksmithing wrist/hand sockets, two Jewelcrafting Serpent's Eyes,
  Enchanting ring enchants, Leatherworking fur lining, Tailoring embroidery and
  Inscription's Secret shoulder inscription.
- Profession-only gems, cogwheels and recognized enchant effects are identified
  directly from inspected gear. If a fresh ARC profession report contradicts
  that requirement, ARC reports it. With no profession report, ownership is not
  guessed and the otherwise-valid visible bonus remains accepted.
- Engineering tinkers can coexist with ordinary enchants and are exposed
  inconsistently by private-server item links. Recognized effects are validated,
  but a missing Engineering tinker is not a confirmed failure. Alchemy and
  gathering profession benefits are likewise not inferred from gear.

## Unverified and snapshot behavior

- `gear.scanned`: equipment/link/cache data is complete enough for equipped ilvl.
- `gear.validationPending`: gem data needs a bounded local retry, without
  another network inspect request. Ilvl is still displayed if equipment loaded.
- `gear.auditComplete`: equipment is loaded, spec known, and no policy checks
  are unverified. An issue-free result is green only in this state.
- Unknown/custom enchant or gem IDs do not receive invented ranks/stats.
  Raid Gear shows `?` for zero confirmed issues plus unverified checks, or `!N`
  for confirmed issues. The tooltip/detail explains what could not be checked.
- Findings are grouped per equipment slot. A bad gem/enchant counts once even
  when it violates several rules; its text includes all detected reasons.
- Missing flask/food and a reported durability below 100% are only a readiness
  snapshot, outside the gear verdict. No durability report means no invented
  durability failure. Healthy consumables/passive buffs are omitted in the detail.

## Limits

No secondary-stat optimization, spirit/haste/hit-cap advice, socket-color bonus
optimization, trinket proc evaluation or detection based solely on an item's
PvP vendor/source. Profession ownership is exact only for self or a fresh ARC
report; unsafe-to-infer bonuses remain neutral. Server-custom stat or ID changes
need explicit policy updates and in-game verification.

## Data source and maintenance

The compact name/stat records were adapted from the WoWSims MoP database at
commit `970d5cc4c8a3c7db0559020b481aaceda5c523f2`:

- [Database snapshot](https://github.com/wowsims/mop/blob/970d5cc4c8a3c7db0559020b481aaceda5c523f2/assets/database/db.json)
- [Stat and item-type schema](https://github.com/wowsims/mop/blob/970d5cc4c8a3c7db0559020b481aaceda5c523f2/proto/common.proto)
- [Source license](https://github.com/wowsims/mop/blob/970d5cc4c8a3c7db0559020b481aaceda5c523f2/LICENSE)

The source targets MoP Classic. ARC uses legacy item/effect IDs and its own
5.4.8 policy; it does not assume all Classic-specific spells/features apply.
The MIT copyright/permission notice is retained in `ARC_Gear.lua` and in
[`WOWSIMS_LICENSE.txt`](WOWSIMS_LICENSE.txt). This is bundled data, not a runtime
library, addon-channel dependency or online lookup.

To customize, edit `GEM_RULE_DATA` or `ENCHANT_RULE_DATA` in `ARC_Gear.lua`.
They are exposed as `ARC.GEAR_RULES.gems` / `.enchants`. Validate an actual
item link, the effect/item ID, slot and stats first. Enchant fields include
`top`, `stats`, `slot`, optional `kind`, `class`, `role` and `pvp`. Gem fields
include `quality`, `stats`, optional `primary`, `role` and `pvp`. Add a regression
fixture in `tests/player_check.lua`; never approve an unknown ID generically.
Policy changes require a UI reload and a new check/Refresh of old snapshots.
