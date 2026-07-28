# 14 — Working agreement

Written after a session that lost the better part of two hours to
avoidable confusion: a hung render diagnosed as a slow one, a broken
test shipped twice without being run, six commits of red CI nobody
noticed, and a finished capture that looked pending for eighteen hours
because it had nothing to say. None of those were hard problems. They
were process gaps. This file closes them.

## 1. Diagnose from evidence, not from timing

**Read the process output before forming a theory.** A capture that
runs long has a log; the log said `Parse Error` the first time it
happened. An hour of "optimisation" went into a performance story that
the first ten lines of that log would have falsified.

- A Godot scene whose script fails to parse runs with **no script at
  all** — no `_process`, so no `--quit-after`, so the job records an
  empty scene until the runner kills it. A "slow render" that is
  wildly out of proportion is almost always this.
- When CI or a capture fails, the first action is *fetch the log and
  quote it*, not adjust a parameter and retry.

## 2. Never ship a test you haven't seen pass

Test-only edits feel too trivial to verify. They are not: a broken test
is a broken signal, and it masks everything behind it. The crowd-cover
test was "fixed" twice while still asserting the wrong thing, because
`cover = 1 - d/r*0.5` gives a man standing exactly on the centre full
cover no matter how small the radius.

- Work the arithmetic by hand (or in a scratch script) before pushing
  a test change.
- Change **one** variable per assertion. The first version of that test
  moved the man *and* the distance and measured the difference of both.
- Check CI's verdict on the commit you just pushed. Red CI is not
  background noise.

## 3. Every job must announce that it finished

A run that completes silently is indistinguishable from one still
going. The capture workflow now writes a line to `demo/capture-log.md`
on **every** run — film or no film — so the branch always advances and
"done" is always visible.

## 4. Don't spend a render on a change that can't be seen

`python3 tools/capture_needed.py` inspects the diff against the paths
that can actually change a pixel (`src/presentation`, `src/sim`,
`src/world`, `data/`, `scenes/`, the capture workflow) and refuses
tests, docs, and tooling. Run it before bumping
`demo/capture-request.txt`. A capture is ~16 minutes of runner time;
an identical film is 16 minutes spent to learn nothing.

## 5. Waiting is delegated, never blocking

The main session does not sit in a poll loop — that is how status
updates get missed and questions go unanswered. Long waits (renders,
CI, deploys) go to a watcher agent, briefed to:

- poll with an `until` loop (never chained bare sleeps),
- stop the moment a run reaches a terminal state,
- and on failure, **fetch the log and quote the error lines verbatim**.

## 6. Recurring status is pre-scheduled, not chained

`ScheduleWakeup` holds exactly one slot, and any interruption — a
message, a completing agent — consumes it. A cadence built by
re-arming each turn dies silently the first time a turn forgets.

For "update me every N minutes", schedule the **whole series up front**
as independent one-shot triggers. Losing one turn then costs one
update, not the entire cadence.

## 7. Report state honestly, including elapsed time

"Expect it in 16 minutes" said about a run that finished yesterday is
worse than saying nothing. Check the clock and the commit timestamp
before reporting progress, and say plainly when an estimate has
expired.

## The loop, in order

1. Make a change.
2. Run the static pre-flight: `python3 tools/preflight_gd.py` (plus
   JSON/YAML parse and `res://` path checks). It catches the two parse
   errors headless Godot has caught for us the expensive way — `:=`
   that cannot infer a type, and a declaration shadowing a live one in
   an enclosing scope. Both cost a full CI cycle each; the script costs
   a second.
3. Push. **Read CI's verdict.**
4. `tools/capture_needed.py` → film only if it says so.
5. Delegate the wait; deliver the film with an honest read of what is
   good and what is not.
