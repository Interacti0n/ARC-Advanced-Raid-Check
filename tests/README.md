# ARC — Advanced Raid Check regression tests

Release-tool tests use Python 3.10+ and its standard library:

```sh
python -B -m unittest discover -s tests -p test_release.py -v
```

They cover exact minimal ZIP contents (no README/docs/tests), version/tag
validation, nested runtime folders, missing/unsafe/case-colliding manifest
entries, symlinked directories, unlisted-file exclusion, repeatable packaging, checksums,
changelog extraction, preserved release notes and safe asset collision/retry
behavior. GitHub calls are mocked; these tests never upload anything. The GitHub
Actions release workflow runs these plus both Lua suites before publishing assets.

Run from the addon root with Lua 5.1 or later:

```sh
lua tests/player_check.lua
lua tests/player_check.lua --stale-toc
```

If a native Lua runtime is unavailable, a developer-only Node alternative in
PowerShell is below. Fengari has no Lua file-reading API, so supply the actual
TOC text through a test-only environment variable:

```powershell
$env:ARC_TEST_TOC = Get-Content -Raw ARC.toc
npm exec --yes --package=fengari-node-cli -- fengari tests/player_check.lua
npm exec --yes --package=fengari-node-cli -- fengari tests/player_check.lua --stale-toc
```

Node, npm and Fengari are not addon dependencies and must not be added to the
TOC. The script loads the actual ARC modules in `ARC.toc` order against strict,
mocked WoW APIs, verifies the player-check entry and checks version agreement.
It checks:

- consistent Advanced Raid Check branding, unchanged settings/slash/prefix and countdown;
- English fallback, Slovak/Czech switching, format-argument parity, live UI
  refresh and per-character language storage;
- legacy, corrupt and newer saved-variable schemas without setting/history loss;
- compact inspect-header button anchors, long-title space, reopening and title-widget fallbacks;
- full Talents label/column width and the simplified talent tooltip;
- problem-item icons, captured full-link tooltips, target changes and no hover inspect requests;
- item/empty/healthy row reuse, tooltip ownership/cleanup and missing icon/API fallbacks;
- right-click menus: one-time hook, root player menus only and no inspect on open;
- disabled/unavailable menu actions, GUID pinning, reused dropdowns and exact name/realm resolution;
- ARC row actions and safe fallback when the optional detail module is missing;
- raid-setup defaults, saved expectations, option menus, red banner and live events;
- actual versus selected instance mode, 10/25 capacity, disabled/solo/PvP and unknown data;
- empty talent tiers, low-level/DK unlocks, cache failures, wrong GUIDs and stale reports;
- class self-buff alternatives, localization, dead/unavailable units and grouped Symbiosis;
- spec-aware shaman shields and the original three-values-per-hand weapon-enchant API;
- spec-based tank stances/forms, required/forbidden Righteous Fury and hidden aura safety;
- legacy stance tuples, same-spec freshness, pets by spec, pet death and mounted/vehicle exceptions;
- full pet-spellbook Growl autocast, action-bar fallback and same-pet-GUID reports;
- warlock tier-five Sacrifice choice versus active buff, non-Sacrifice pets and stale talents;
- Healthstone bag counts versus charges, group/supplier scope, expiry and red HS/report findings;
- validated P1 extensions and outgoing report round trips, with old R1 compatibility;
- backwards-compatible sender-bound readiness messages, report expiry and hidden-window refresh;
- addon-message size guards, failed server sends, duplicate suppression and heartbeat delivery;
- non-group reports with ordered identity, only problem slots and no roster insertion;
- cached gem IDs, low-level items, enchants and empty required slots;
- partial item caches, unavailable equipment and unknown specialization;
- target changes before sending, during inspection and after completion;
- manual priority, background suspension, external requests and cache clears;
- timeouts, retries, unavailable players, cancellation and late events;
- standalone and ElvUI widget paths, including lazily created rows.
- manual opening mode through commands, options and saved settings;
- ready/decline responses, double-click protection, expiry and failed API calls;
- numeric minimum-ilvl input, Enter/Apply, invalid values and Escape.
- clean reports, reused/hidden rows, long scrollable findings and separate readiness;
- rare/Perfect/profession/legendary gems, old and green gems, PvP hybrids/metas;
- belt-buckle enforcement, normal/legendary meta suitability and role exceptions;
- profession channel validation and reliably visible profession gear bonuses;
- wrong primary stats, legendary proc suitability and extra-socket gem validation;
- top/weak/PvP enchants, profession options, runeforges, scopes and off-hands;
- cold gem retries without another inspect or lost ilvl; unknown data cannot pass;
- hunter ranged weapon ilvl weighting.
- raid-session attendance, legacy ten-second intervals and configurable 15/7/30
  trash timing with retroactive threshold credit, excluded dead/offline/revival
  time, reconnect/rejoin, no double counting and no pet-owner credit;
- ghost runback continuity, live encounter reload, stale/missed ends, mismatched
  encounter IDs, pull-cap isolation, resets/wipes/kills and copyable reports;
- unknown-spec meta safety, wrong main-stat flasks, independent banner colors,
  wrapped banner spacing and data freshness hints;
- opacity, isolated 10-player preview, paused preview inspection, grouped
  scrolling ElvUI options, atomic timer validation and schema-two defaults.
- player-grouped session loot, boss attribution, epic-only trash, exact item
  tooltips, bonus-roll sync/deduplication and empty-roll limitations.
- bounded fair metadata retries, exact-link cache invalidation and delayed
  variant tooltips without rescanning resolved loot every second.
- stale TOC omitting the new module: one startup warning, safe world/inspect
  events and update ticks, actionable `/arc check` feedback, working raid UI,
  minimap and ready-check response buttons.

The `--stale-toc` run intentionally skips localization, `UI/ARC_PlayerCheck.lua`
and `Core/ARC_Session.lua` to model unavailable optional modules. It
verifies defensive behavior, not
that `/reload` can install new files or discover moved paths. Updates that move
files, including 1.10.1, require a full restart.

Passing this suite validates control flow, not Blizzard's actual network
behavior, private-server API differences or pixel-level rendering. Before
release, test the button placement, scrollable/wrapped text, refresh and
target changes inside the MoP client, both with and without ElvUI. Also verify
right-click menus on target/focus, party/raid frames and ARC rows; open a menu,
change target before clicking, and check offline/out-of-range behavior.
For the new readiness features, follow the in-game checklist in
[`docs/READINESS_CHECKS.md`](../docs/READINESS_CHECKS.md). No mocked suite proves
private-server spell visibility, real talent-cache completeness or dropdown skinning.
