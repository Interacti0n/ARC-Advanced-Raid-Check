# ARC — Advanced Raid Check 1.5.0 release checklist

1. Keep `ARC.toc`, `ARC.VERSION`, README and the newest changelog entry aligned
   at **1.5.0**. Review the complete working tree: this candidate contains all
   changes since 1.4.0, including the new `ARC_PlayerCheck.lua` module.
   Verify the Advanced Raid Check display name. Keep the installation folder
   `ARC`, saved variables `ARC_DB`, slash commands and `ARC1` prefix unchanged.
2. Run both suites in [tests/README.md](../tests/README.md), parse every Lua file
   as Lua 5.1, and run `git diff --check`. Confirm the final **Passed** line;
   some developer Lua runners do not propagate assertion failures as exit codes.
3. Fully restart the original 5.4.8 WoW client. Test installation and the
   [README checklist](../README.md#quick-verification-checklist), then the
   [readiness checklist](READINESS_CHECKS.md#in-game-checklist-before-release).
   Include two updated ARC clients, an old/no-ARC peer, and ElvUI on/off.
   Automated mocked tests are not a substitute for these live checks.
4. Package one top-level `ARC/` folder containing `ARC.toc`, every Lua file in
   its load order, `README.md`, `changelog.txt`, `LICENSE` and `docs/` (including
   `WOWSIMS_LICENSE.txt`). Do not include `.git`, tests, developer runtimes,
   SavedVariables, credentials or nested release archives. Open the ZIP and
   confirm `ARC/ARC.toc` and `ARC/ARC_PlayerCheck.lua` exist.
5. Review and commit the intended files, synchronize your branch without
   force-pushing over other work, and only after the live checks pass create
   the `v1.5.0` tag and GitHub release. Attach the matching ZIP, and include the
   v1.5.0 changelog and full-client-restart requirement in the release notes.

A local `candidate` ZIP is not a published release or proof of in-game testing.
Do not label the version verified on the server until the live checklist passes.

## Local preflight — 2026-09-02

- 106 mocked ARC regression tests passed, including item tooltips and rename compatibility.
- The stale-TOC startup/event/update/command/raid-UI suite passed.
- All seven addon Lua modules and the test harness parsed as Lua 5.1.
- `git diff --check` passed; Git only noted its configured LF/CRLF conversion.
- Version metadata is aligned at 1.5.0.
- Live MoP 5.4.8 / ElvUI / two-client testing is **still required**.
- No release tag, push or GitHub publication was performed by this preflight.
