# Project architecture

ARC is intentionally dependency-free at runtime. Optional ElvUI integration is
detected after load; the addon does not bundle or require Ace, LibStub or any
other library.

## Runtime modules

| File | Responsibility |
| --- | --- |
| `ARC_Core.lua` | Database defaults, roster, aura scanning and addon communication |
| `ARC_Gear.lua` | Upgrade-aware item level, item parsing and configurable gear rules |
| `ARC_Inspect.lua` | Inspect queue, specialization and remote equipment fallback |
| `ARC_UI.lua` | Main roster, tooltips, verdict banner and announcements |
| `ARC_PlayerCheck.lua` | Standalone report plus inspect/context-menu integration |
| `ARC_Session.lua` | Automatic session lifecycle, attendance, encounters, deaths and activity tables |
| `ARC_Options.lua` | Minimap button and Interface Options panel |
| `ARC.lua` | Event dispatch, update loop and slash commands |
| `ARC.toc` | Metadata, saved variables and module load order |

The order in `ARC.toc` is significant. `ARC_Core.lua` initializes the shared
table and must remain first; `ARC.lua` connects all modules and must remain
last. When adding a module, update the TOC and require a full client restart
during testing because the MoP client may cache the previous file list.

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
defaults are applied after guarded, incremental migrations in `ARC_Core.lua`.
Each migration advances the schema only after success and must be idempotent so
an interrupted step can safely run again. Unknown fields and session history
are preserved. If an older addon sees a newer schema, it keeps that version and
skips migration instead of downgrading or replacing the database.

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
WoWSims-derived catalog notice is embedded in `ARC_Gear.lua`, so the required
notice remains in the minimal package.

See [Release checklist](RELEASE_CHECKLIST.md) for packaging and publishing.
