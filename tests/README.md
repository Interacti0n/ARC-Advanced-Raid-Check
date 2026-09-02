# ARC — Advanced Raid Check regression tests

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
- wrong primary stats, legendary proc suitability and extra-socket gem validation;
- top/weak/PvP enchants, profession options, runeforges, scopes and off-hands;
- cold gem retries without another inspect or lost ilvl; unknown data cannot pass;
- hunter ranged weapon ilvl weighting.
- stale TOC omitting the new module: one startup warning, safe world/inspect
  events and update ticks, actionable `/arc check` feedback, working raid UI,
  minimap and ready-check response buttons.

The `--stale-toc` run intentionally skips `ARC_PlayerCheck.lua` to model a MoP
client still using the old file list. It verifies defensive behavior, not
that `/reload` can install new files. Updating to 1.5.0 needs a full restart.

Passing this suite validates control flow, not Blizzard's actual network
behavior, private-server API differences or pixel-level rendering. Before
release, test the button placement, scrollable/wrapped text, refresh and
target changes inside the MoP client, both with and without ElvUI. Also verify
right-click menus on target/focus, party/raid frames and ARC rows; open a menu,
change target before clicking, and check offline/out-of-range behavior.
For the new readiness features, follow the in-game checklist in
[`docs/READINESS_CHECKS.md`](../docs/READINESS_CHECKS.md). No mocked suite proves
private-server spell visibility, real talent-cache completeness or dropdown skinning.
