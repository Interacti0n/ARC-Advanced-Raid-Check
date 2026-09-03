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
   [README checklist](../README.md#quick-verification-checklist), then the
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
   remains embedded in `ARC_Gear.lua`. Announce the release only after assets appear.

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

## Historical 1.5.0 local preflight — 2026-09-02

- 106 mocked ARC regression tests passed, including item tooltips and rename compatibility.
- The stale-TOC startup/event/update/command/raid-UI suite passed.
- All seven addon Lua modules and the test harness parsed as Lua 5.1.
- `git diff --check` passed; Git only noted its configured LF/CRLF conversion.
- Version metadata is aligned at 1.5.0.
- Live MoP 5.4.8 / ElvUI / two-client testing is **still required**.
- No release tag, push or GitHub publication was performed by this preflight.
