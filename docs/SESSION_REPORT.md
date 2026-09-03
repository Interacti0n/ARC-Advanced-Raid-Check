# ARC raid session reports

Session reports record compact raid-leader information without retaining the
raw combat log. Start one from the main-window or Options **Session Report**
button, or with `/arc session start`. The same report window can end the active
session and offers **Select All for Copy**. **Previous/Next** browses retained
reports and **Refresh** updates a live view. `/arc session` reopens the current
or most recently completed report; `/arc session end` saves it.

## Recorded data

- session start/end, instance and difficulty;
- join/leave attendance time and boss-pull participation per player;
- exact time observed with Blizzard's AFK flag;
- boss pulls, duration, success and first death/time from encounter/combat-log events;
- ready-check results and confirmed ARC issues at each completed check;
- number and duration of trash combats;
- estimated inactivity during trash, plus total deaths;
- tracked boss/trash combat and approximate time between combat.

The newest ten completed sessions are retained in `ARC_DB.sessions`; the oldest
is removed when the limit is exceeded. The active session is stored separately
and resumes after `/reload`. At session end ARC retains summaries, not every
combat-log event. Each session is capped at 200 pulls and 100 ready snapshots.

## AFK versus trash inactivity

`AFK flag` is the elapsed time between observed `PLAYER_FLAGS_CHANGED` states
while the unit reports AFK. It is the strongest signal available to an addon.

`trash inactive ~` is deliberately labelled as an estimate. While the local
player is in a non-boss combat, each group member gets a ten-second activity
timer. Damage, healing, successful spell casts, interrupts, dispels and spell
steals reset that timer. When ten seconds elapse, all ten seconds are credited
retroactively and inactivity continues accumulating until another qualifying
event. Visible permanent-pet activity is assigned to its owner. Dead and offline
players do not accumulate this metric.

The client does not expose another player's keyboard input, movement intent or
whether a player is physically present. A healer on harmless trash, a player
holding an assignment, crowd control, travel inside combat or combat-log range
can therefore create false positives. Treat this as a raid-review clue, never as
proof of AFK or as an automatic punishment signal.

## Compatibility and fallbacks

ARC uses the original MoP event arguments delivered with
`COMBAT_LOG_EVENT_UNFILTERED`, plus `ENCOUNTER_START`/`ENCOUNTER_END`. A private
server that omits encounter events cannot produce reliable boss pull/kill rows;
the report says no encounter events were recorded. Attendance and Blizzard AFK
tracking do not require other players to run ARC. Remote durability and other
owner-only readiness values keep their normal ARC-channel limitations.

The report never starts or ends automatically, changes raid settings, posts to
chat or uploads data. Copying requires the user to select the text and use the
normal operating-system copy shortcut.

## Live verification checklist

1. Start a grouped session, add/remove a member and verify their attendance.
2. Toggle `/afk` for a known interval, clear it and verify the AFK total.
3. Enter trash combat, remain inactive for over ten seconds, act, and verify the
   timer resets while preserving the already accumulated interval.
4. Repeat with a healer on harmless trash and a hunter pet to understand the
   estimate and confirm visible pet activity credits its owner.
5. Pull, wipe and kill a boss; verify duration, first death and success.
6. Complete ready checks with consumable/gear/AFK problems and inspect snapshots.
7. `/reload` during a session, resume it, then end and copy the report.
8. Verify the report with ElvUI enabled and disabled.
