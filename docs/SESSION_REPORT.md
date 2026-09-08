# ARC raid session reports

Session reports record compact raid-leader information without retaining the
raw combat log. With automatic tracking enabled, entering a raid instance starts
a session and remaining outside it for 30 seconds finishes the session. Wipes,
release and `/reload` do not split it. Manual start/end commands remain available.

The report uses **Players**, **Bosses**, **Loot** and **Export** tabs. **Previous/Next**
browses retained reports, and the summary shows the current position as
**Session X / Y**. **Select All for Copy** appears only on Export. **Delete
Report** removes the selected completed report after confirmation; an active
session cannot be deleted.

## Recorded data

- session start/end, instance and difficulty;
- join/leave attendance time and boss-pull participation per player;
- online/offline time, eligible trash time and trash inactivity per player;
- boss pulls, duration, success and first death/time from encounter/combat-log events;
- boss, trash and other/unknown death totals, plus first-death counts;
- the number of completed ready checks, without retaining their issue lists;
- number and duration of trash combats;
- estimated inactivity during trash and its percentage of eligible trash time;
- boss item/token awards, successful and empty bonus rolls, and epic trash loot.

Completed sessions from the last fourteen days are retained in
`ARC_DB.sessions`; older entries are permanently removed. The active session is stored separately and resumes after
`/reload`. At session end ARC retains summaries, not every combat-log event.
Each session is capped at 200 pulls, 100 counted ready checks and 500 loot rows.

## Loot report

The **Loot** tab lists every session member, including players with no recorded
loot. Click a player to expand their rewards in chronological order. Each detail
shows time, boss/source, item and variant labels. Hovering the icon opens the
exact saved item hyperlink; Shift-click inserts that link into chat when the
client permits it. Export includes the same loot grouped by player.

After a recorded boss kill, ARC keeps that boss as the preferred loot source
until the next encounter starts. Once real trash combat has begun, only items
confirmed as epic are retained, but they remain attributed to the previous boss.
This intentionally favors keeping unusually late master-loot awards on the
correct boss; an epic trash drop between bosses may therefore appear under that
boss.
If item data is initially uncached, ARC retries it and keeps the trash row hidden
until epic quality is confirmed; unresolved trash rows are discarded when the
session ends. Before the first recorded kill, qualifying drops use `Trash` or
`Unknown source` normally.

ARC preserves the full hyperlink and scans its tooltip for Heroic, Warforged
and Thunderforged labels. Recorded encounter difficulty supplies the normal,
Heroic, Raid Finder or Flexible fallback. Warforged status is never guessed
from item level alone because ordinary upgrade levels can overlap it.

Successful bonus-loot item messages are visible through the normal localized
loot event. The local `BONUS_ROLL_STARTED`/`BONUS_ROLL_RESULT` events also let an
ARC client report its own item or `no item` result to peers. These compact `L1`
reports are sender-bound: a client can add a bonus result only for itself and a
boss kill that exists in the receiver's session. A player without ARC can still
have public item awards recorded, but an empty bonus roll is unknowable and is
not invented. Private-server cores that omit bonus-roll events simply provide
less bonus detail without breaking the rest of the session.

## Trash inactivity

`trash inactive ~` is deliberately labelled as an estimate. A trash window
starts when the combat log shows a real hostile exchange involving any group
member, even when the local ARC user never enters combat. Each member then gets
a five-second activity timer. Personal damage, healing, successful spell casts,
interrupts, dispels and spell steals reset it. When five seconds elapse, all
five seconds are credited retroactively and inactivity continues accumulating
until another qualifying event. Pet combat can prove that the pack is still
alive, but deliberately does not reset its owner's personal timer. Dead and
offline players do not accumulate this metric.

Tracked enemy deaths close a finished pack promptly. If a death, evade or
despawn event is unavailable, six seconds without real combat-log evidence
closes it automatically; a stuck combat flag alone never keeps the timer open.

The client does not expose another player's keyboard input, movement intent or
whether a player is physically present. A healer on harmless trash, a player
holding an assignment, crowd control, travel inside combat or combat-log range
can therefore create false positives. Treat this as a raid-review clue, never as
proof of AFK or as an automatic punishment signal.

## Compatibility and fallbacks

ARC uses the original MoP event arguments delivered with
`COMBAT_LOG_EVENT_UNFILTERED`, plus `ENCOUNTER_START`/`ENCOUNTER_END`. A private
server that omits encounter events cannot produce reliable boss pull/kill rows;
the report says no encounter events were recorded. Attendance and activity
tracking do not require other players to run ARC. Remote durability and other
owner-only readiness values keep their normal ARC-channel limitations.

Automatic tracking can be disabled in Options. It reacts only to entering or
leaving an actual raid instance, never changes raid settings, posts to chat or
uploads data. Manually ending an automatic session inside the raid suppresses a
restart until the player leaves and re-enters. Copying requires the user to use
the Export tab and the normal operating-system copy shortcut.

## Live verification checklist

1. Start a grouped session, add/remove a member and verify their attendance.
2. Enter trash combat, remain inactive for over five seconds, act, and verify the
   timer resets while preserving the already accumulated interval.
3. Repeat with a healer on harmless trash and a hunter pet to understand the
   estimate and confirm that pet-only activity does not credit its owner.
4. Pull, wipe and kill a boss; verify duration, first death and death categories.
5. Verify Players sorting and the green <=5%, yellow <=30%, red >30% thresholds.
6. Complete several ready checks and verify only their count is retained.
7. `/reload` during a session, then leave for 30 seconds and verify automatic end.
8. Loot a boss item and an epic trash item; verify lower-quality trash is absent.
9. Use a bonus roll with and without an item and compare a peer with/without ARC.
10. Expand a Loot player, hover the exact item, Shift-click it, and verify
    Heroic/Warforged labels against the real tooltip.
11. Verify Players, Bosses, Loot and Export with ElvUI enabled and disabled.
