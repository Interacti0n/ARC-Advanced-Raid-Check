# Project architecture

ARC is intentionally dependency-free at runtime. Optional ElvUI integration is
detected after load; the addon does not bundle or require Ace, LibStub or any
other library.

## Runtime modules

| File | Responsibility |
| --- | --- |
| `Core/ARC_Core.lua` | Database defaults, roster, aura scanning and addon communication |
| `Locales/ARC_Localization.lua` | English fallback, locale selection and live UI refresh |
| `Locales/ARC_Locales_SK.lua` | Slovak translations |
| `Locales/ARC_Locales_CZ.lua` | Czech translations |
| `Core/ARC_Gear.lua` | Upgrade-aware item level, item parsing and configurable gear rules |
| `Core/ARC_Inspect.lua` | Inspect queue, specialization and remote equipment fallback |
| `UI/ARC_UI.lua` | Main roster, tooltips, verdict banner and announcements |
| `UI/ARC_PlayerCheck.lua` | Standalone report plus inspect/context-menu integration |
| `Core/ARC_Session.lua` | Automatic session lifecycle, attendance, encounters, deaths and activity tables |
| `UI/ARC_Options.lua` | Minimap button and Interface Options panel |
| `ARC.lua` | Event dispatch, update loop and slash commands |
| `ARC.toc` | Metadata, saved variables and module load order |

The order in `ARC.toc` is significant. `Core/ARC_Core.lua` initializes the shared
table and must remain first; `ARC.lua` connects all modules and must remain
last. When adding a module, update the TOC and require a full client restart
during testing because the MoP client may cache the previous file list.

Runtime files are grouped into `Core/`, `UI/` and `Locales/`; only the TOC and
event/command entry point stay at the root. Existing filenames, namespaces and
load order are preserved. `ARC_Session.lua` still owns its report UI as well as
tracking; this directory-only reorganization does not split or rewrite modules.
`docs/`, `tests/`, `scripts/` and `.github/` are repository-only support folders.

## Stable compatibility identifiers

Advanced Raid Check was previously named Advanced Ready Check. The user-facing
name changed, but these identifiers intentionally did not:

- addon directory and TOC basename: `ARC`
- saved-variable table: `ARC_DB`
- slash-command root: `/arc`
- addon-channel prefix: `ARC1`
- existing global/frame identifiers beginning with `ARC`

Keeping them stable preserves settings, enabled-addon state and communication
with compatible older clients.

## Saved-variable migrations

`ARC_DB.schemaVersion` is independent from the addon release version. Database
defaults are applied after guarded, incremental migrations in `Core/ARC_Core.lua`.
Each migration advances the schema only after success and must be idempotent so
an interrupted step can safely run again. Unknown fields and session history
are preserved. If an older addon sees a newer schema, it keeps that version and
skips migration instead of downgrading or replacing the database.
Schema 1 tags the legacy shape; schema 2 introduces `trashSettings` defaults
without rewriting session history. Each new session snapshots those limits.
Defensive presentation defaults reject invalid anchors and non-finite values
instead of passing them to frame APIs.

The language override is intentionally separate in the per-character
`ARC_CharDB.language` field. `auto` follows the game client when ARC has a
matching locale and otherwise falls back to canonical `enGB`; `enUS` shares
the same maintained English strings. Locale tables may omit a key safely
because the English source string is always used as the fallback.

## Communication model

The addon channel supplements unit and inspect APIs with self-reported private
data, including compact primary-profession IDs. It does not replace inspect for
equipment and does not trust missing fields as failures. Messages remain
sender-bound, freshness-limited and backward-compatible; unknown fields from
older peers stay unverified.

The caret-separated wire format remains uncompressed for legacy-client
compatibility and is normally far below the 255-byte MoP limit. ARC validates
that limit before sending, protects the private-server send API, suppresses
unchanged event-driven payloads and retains a 15-second heartbeat. Compression
or message chunking should only be introduced if a future protocol expansion
can no longer stay comfortably within that bound.

Readiness snapshots keep their original format. Session bonus rolls use a
separate compact `L1` message under the same `ARC1` prefix. Dispatch occurs
before readiness parsing, and the session module validates the channel sender,
matching local boss pull, item hyperlink and per-session limits.

See [Data sources and limitations](DATA_AND_LIMITATIONS.md) and
[Readiness checks](READINESS_CHECKS.md) for the public behavior and protocol
freshness rules.

## Distribution boundary

The GitHub repository contains documentation, tests and release tooling. The
installable ZIP contains only the TOC-listed `.lua` modules, `ARC.toc`,
`changelog.txt` and `LICENSE`, all below one `ARC/` directory. The
WoWSims-derived catalog notice is embedded in `Core/ARC_Gear.lua`, so the required
notice remains in the minimal package.
Packaging preserves the runtime subdirectories and accepts only unique ARC Lua
paths in the approved folders (plus root `ARC.lua`). Absolute/traversing paths,
case-colliding entries and symlinked path components are rejected. Unlisted Lua
files and obsolete copies at the root are never included.

See [Release checklist](RELEASE_CHECKLIST.md) for packaging and publishing.

## Session performance and preview isolation

Session combat identity is GUID-first; an unknown GUID is never reassigned by
name to a player. Pet evidence keeps trash detection alive but cannot credit its
owner. A restored encounter has a guarded missed-end fallback. The pull-history
cap still keeps an unrecorded runtime encounter so bosses cannot become trash.
Loot tooltip metadata is cached per exact item link; unresolved entries use a
rotating read budget and delayed retries. Preview uses a separate temporary
roster and pauses raid inspect work, without replacing saved or communicated
live state. It does not stop real session tracking or owner heartbeats.
# Connection-health reporting (1.9.0)

Core samples FPS at most once per second and publishes its interval average plus
guarded Home/World latency reads every 15 seconds. The cached H1 extension follows
F1 in readiness messages: H1^homeMs^worldMs^fps; -1 denotes unavailable values.
Existing sender binding, send throttling and the 255-byte guard still apply.
Older peers ignore trailing fields. Invalid values are discarded, and a report
without H1 clears previous remote health data. Measurements remain in memory.
Only the ARC cell color and its dedicated tooltip consume this data.
