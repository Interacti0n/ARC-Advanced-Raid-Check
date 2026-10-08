# ARC — Advanced Raid Check release checklist

1. Keep `ARC.toc`, `ARC.VERSION`, README and the first changelog section aligned
   at the version you intend to release (for example, **1.5.1** after 1.5.0).
   Review all changes and do not move an already-published version's tag.
   Verify the Advanced Raid Check display name. Keep the installation folder
   `ARC`, saved variables `ARC_DB`, slash commands and `ARC1` prefix unchanged.
2. Run both suites in [tests/README.md](../tests/README.md), parse every Lua file
   as Lua 5.1, and run `git diff --check`. Confirm the final **Passed** line;
   some developer Lua runners do not propagate assertion failures as exit codes.
3. Fully restart the original 5.4.8 WoW client. Test installation and the
   [in-game checklist](TESTING.md), including the linked
   [readiness checklist](READINESS_CHECKS.md#in-game-checklist-before-release).
   For releases containing session changes, also run the
   [session checklist](SESSION_REPORT.md#live-verification-checklist).
   Include two updated ARC clients, an old/no-ARC peer, and ElvUI on/off.
   Automated mocked tests are not a substitute for these live checks.
4. Review and commit/push the intended files, including `.github/workflows/release.yml`
   and both `scripts/*release.py` files. Do not force-push over other work. The
   workflow must be present on the commit you will tag. You can first use
   **Actions → Package ARC release → Run workflow** for a read-only preflight:
   it tests/builds but neither creates a release nor uploads assets.
5. In **Releases → Draft a new release**, select/create the matching `vX.Y.Z` tag
   on that commit. Leave the description empty to use ARC's changelog, or provide
   your own description / GitHub-generated notes to preserve them. Do not upload
   a ZIP manually. Click **Publish release**. A saved draft does not trigger it.
6. Wait for **Package ARC release** to finish successfully. It runs Lua 5.1 syntax
   checks, both addon suites and release-tool tests, validates tag/TOC/Core/README/
   changelog versions, then uploads `ARC-X.Y.Z.zip` and `ARC-X.Y.Z.zip.sha256`.
   The ZIP contains only the TOC-listed Lua modules, TOC, changelog and main license
   under `ARC/`. README/docs/tests/tooling are excluded. The third-party MIT notice
   remains embedded in `Core/ARC_Gear.lua`. Announce the release only after assets appear.

The release event packages the exact event commit, not a later moving `main`.
Validation has read-only permissions; only the separate upload job can write
release assets/notes, using the built-in `GITHUB_TOKEN`. No custom secret, PAT,
branch push, tag creation or automatic version bump is involved. The checkout
action is pinned to a verified commit and does not persist credentials.

The release is already published while Actions runs. A failing check prevents
uploads but does not unpublish the release. Fix failures and use **Re-run failed
jobs** for transient errors; source/version fixes should normally get a new tag.
An identical asset is skipped on retry. A different same-name asset (or one with
no verifiable digest) causes a failure without deleting/replacing the original.
Review such a collision manually. Partial uploads can be safely retried once
GitHub has returned digests for the completed files.

Installing the workflow does not alter existing releases, and a previously
published tag without these workflow/scripts cannot retroactively run it.
Keep 1.5.0 intact; use a new version for the next release.

For local packaging with Python 3.10+ (no third-party dependencies):

```sh
python -B -m unittest discover -s tests -p test_release.py -v
python -B scripts/package_release.py --tag vX.Y.Z
```

Replace `vX.Y.Z` with the actual matching version. Output goes into ignored
`build/`; omit `--tag` for local metadata-only validation. The generated
`release-notes.md` is for the GitHub description, not included in the ZIP.
Build outputs may be regenerated locally; published assets are never clobbered.

Trigger and upload behavior follow the official
[GitHub release-event documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release)
and [GitHub CLI upload documentation](https://cli.github.com/manual/gh_release_upload).

A local `candidate` ZIP is not a published release or proof of in-game testing.
Do not label the version verified on the server until the live checklist passes.

## Current 1.10.1 directory reorganization

Runtime code is organized under `Core/`, `UI/` and `Locales/`; TOC order and
compatibility identifiers remain unchanged. Run the normal Lua/stale-TOC suites
and the expanded release-tooling suite before committing. Actions syntax checks
must include all three folders, not just root Lua files. Verify that the ZIP
preserves the subfolders and still excludes README/docs/tests/tooling. Fully
restart the live client after moving files. Do not move or replace the already
published 1.10.0 tag/assets.

Local preflight on 2026-10-08 passed all 162 mocked ARC regression tests,
the optional-module/stale-TOC checks, syntax loading of all TOC modules and
the test harness, and all 11 release-tooling tests. The candidate ZIP contains
14 files with the new runtime subfolders and no docs/tests/tooling. Lua tests
ran through Fengari locally; native Lua 5.1 remains the Actions check. This is
not a published release or an in-game verification of the moved file paths.

## Previous 1.10.0 local preflight — 2026-10-08

- 162 mocked ARC regression tests passed, including join/activity/revival
  timing, reconnect/rejoin, same-named pets, runback/reload recovery, banner
  layout/colors, safe meta/flask checks, loot caching and localized options.
- Stale-TOC regression checks and all nine release-tooling tests passed.
- All twelve Lua files parsed locally with Fengari (Lua 5.3 semantics); native
  Lua 5.1 syntax/runtime verification remains required before publication.
- A local candidate ZIP was built and its minimal manifest verified: TOC,
  Lua modules, changelog and license only, without docs/tests/tooling.
- Core, TOC, README and changelog agree on 1.10.0. No release is published by
  this preflight. Real 5.4.8 raid/multi-client and ElvUI visual checks remain.

## Previous 1.9.1 local preflight — 2026-09-15

- 140 mocked regression tests passed, including fractional trash intervals,
  repeated accumulation, pack closure, short packs and stuck-combat cleanup.
- Stale-TOC checks, nine release-tooling tests and diff checks passed.
- Live raid verification remains pending; no release published by this preflight.

## Previous 1.9.0 local preflight — 2026-09-09

- 139 mocked ARC regression tests passed, including connection sampling, report expiry and inspect fallback, sender validation, consumable hover failures, pending profession gems and separate identical loot awards.
- The stale-TOC startup/event/update/command/raid-UI suite passed.
- All nine Python release-tooling tests passed, including minimal ZIP contents.
- `git diff --check` passed; Git only noted its configured LF/CRLF conversion.
- Version metadata is aligned at 1.9.0.
- User-reported local in-game testing passed; a full raid and multi-client test
  remains pending. This release does not claim full raid verification.
- Version 1.9.0 is approved for stable publication and subsequent maintenance.
