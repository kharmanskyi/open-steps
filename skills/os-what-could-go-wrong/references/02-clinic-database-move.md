# Example 2 - moving a clinic database over one Saturday night

Source: an invented decision, written for this example. No real company,
nothing confidential, no third-party material. Both halves are real agent
output on the same facts, produced on 2026-09-13 with Claude Code 2.1.222 and
Opus 5, headless, from an empty folder. The BEFORE is what a general-purpose
agent answered with every skill switched off. The AFTER is what this skill
produced: the dispatching agent wrote the brief, a fresh agent attacked it, and
the report came back "as it came". Both are abridged wherever you see an
ellipsis, and punctuation is normalised to this repository's style; no wording
is changed.

Two notes on the source. The BEFORE opened with a line saying it could
not load this pack's skill - the maintainer's own instructions name it, so the
agent tried and was refused - and then answered on its own; that opening line
and the closing status line are left out, the answer between them is
untouched. The fresh agent in the AFTER checked PostgreSQL's documentation over
the web where Claude Code allowed it; two searches and two page fetches were
refused, and the report says so at its end.

Kept because it is the technical case. Example 1 is a lease, and this pack
says a lease and a database migration get the same treatment. It is also kept
for its words. Example 1 leaks specialist terms in its detail layer, and says
so. In this example the plain-words rule holds further down. The terms that
remain are listed at the end.

## The decision, as both were given it

> We run a subscription app for small medical clinics: 1,900 paying clinics,
> about $410,000 of monthly revenue, a team of 6 engineers and no dedicated
> database specialist. The database (Postgres 12, 640 GB) runs on a server we
> manage ourselves in one data centre, and the hosting company is ending that
> product line in November.
>
> The plan: move the database to a managed cloud database service (Postgres
> 16) this Saturday, 02:00-06:00 local time, announced to customers as a
> four-hour maintenance window. Steps: final full backup at 01:30, stop all
> writes at 02:00, copy the data with the cloud vendor's migration tool
> (measured at 3 hours 10 minutes on a copy of the data two weeks ago), switch
> the app's connection string to the new service, run our 40-check smoke test,
> reopen to customers at about 05:30. Rollback plan: if the smoke test fails
> before 05:00 we point the app back at the old server; after 05:00 we roll
> forward and fix problems on the new service.
>
> The engineer who ran the trial migration is on holiday from Friday; two other
> engineers have read the runbook. Clinics are closed on Sunday; Monday 08:00
> is the first heavy use. What is fixed: the host's November deadline, the
> window (already approved by marketing and announced), and the budget ($3,200
> a month for the new service, contract already signed). Success means Monday
> passes with fewer than 10 support tickets about the migration and query times
> at or below today's.

The BEFORE was asked "What could go wrong with this plan?", the AFTER "Do a
premortem on this plan."

## BEFORE - the same decision, no skill (~80 lines)

> **Short version: the schedule has no slack, and the rollback deadline lands
> before you can possibly know whether the migration worked.** Everything
> below is ordered by how badly it hurts.
>
> ### 1. The arithmetic doesn't close - this is the structural flaw
>
> 02:00 stop + 3h10m copy = 05:10. Your rollback deadline is 05:00. So on a
> nominal run you cross the point of no return *before the first smoke check
> executes*... **Fix:** tie the abort to a milestone, not a clock. "If the copy
> has not finished by 04:15, abort and point back at the old server." And take
> the backup Friday evening, not 01:30.
>
> ### 2. Monday performance fails for reasons the smoke test can't see
>
> A freshly restored Postgres has **no planner statistics**. Without a full
> `ANALYZE` after restore, Monday 08:00 gets sequential scans where you expect
> index scans - 10x-100x slower queries on a database that is otherwise
> perfectly correct... On top of that the new instance has a cold buffer
> cache...
>
> ### 3. Postgres 12 → 16 is four major versions, and you haven't checked what breaks
>
> - **Extensions.** Whatever you use (`pg_trgm`, `uuid-ossp`, PostGIS, anything
>   custom) must exist on the managed service at a compatible version...
> - **Collation.** If the vendor tool does a physical/binary copy and the
>   managed service runs a different glibc, text indexes arrive silently wrong -
>   wrong query results and unique constraints that don't hold, on
>   patient-name data... **Nobody on your team currently knows which mode the
>   tool uses.** Find out this week.
> - **Connection limits.** Managed Postgres caps `max_connections` by instance
>   size... Check whether the plan includes a pooler.
> - ...
>
> ### 4. What migration tools routinely don't carry over
>
> Roles, users and grants. Sequence positions (→ duplicate-key errors on the
> first Monday insert). Materialized view *contents*. Large objects. Event
> triggers. Each one is invisible to a read-only smoke test and lethal on
> Monday.
>
> ### 5. Rollback is a sentence, not a plan
>
> - It only works if the old server took **zero** writes after 02:00. "Stop
>   all writes" via app maintenance mode doesn't stop cron jobs, queue
>   workers, webhooks, or integrations writing on a side path...
> - How fast is "point the app back"? If it's a DNS name with a 3600s TTL, or
>   a config change requiring a deploy, your rollback costs 20-60 minutes you
>   don't have. Lower the TTL now.
> - ...
>
> ### 6. The person who has actually done this is gone
>
> Two engineers who *read* the runbook is not two engineers who *ran* it. At
> 04:30, when the tool emits an error the runbook doesn't cover, nobody in the
> room has seen it before...
>
> ### 7. You're treating one shot as mandatory when you have seven
>
> It's mid-September; the host's deadline is November. Sunday is a free day -
> clinics are closed - and your plan assigns it nothing...
>
> ## What I'd change
>
> ...
>
> 1. **Replace the stop-the-world copy with logical replication.** Stand
>    Postgres 16 up as a logical replica of the 12 this week; let it catch up
>    over several days... Caveat: tables without a primary key need `REPLICA
>    IDENTITY` set, and DDL isn't replicated - so freeze schema changes until
>    cutover...
> 2. **If you keep the current approach:** backup Friday evening;
>    abort-by-milestone at 04:15; `ANALYZE` and cache warm-up written into the
>    window as explicit steps.
> 3. ...
> 6. **Give Sunday a job:** verification, `ANALYZE`, load replay against real
>    Monday-shaped traffic - or the second attempt.

**What is wrong with it**

Less than in example 1, which is why it is worth reading. The arithmetic is
right, the recommendation is the same one the skill reached, and the tripwire
at 04:15 is real. What it lacks is the part a person who does not run
databases could act on or audit.

| Defect | Where |
|---|---|
| The verdict is a mood, not a decision | "The schedule has no slack" opens it and "What I'd change" closes it. Nowhere does it say think again, or go, or try it small; the reader infers the verdict from the tone |
| You cannot tell what was skipped | Seven sections, chosen by the writer. Nothing on the law around patient data, nothing on who gains from silence, nothing on customer trust. Considered and empty, or never looked at? Nothing says |
| Nothing is scored | Which failure is likeliest, which is worst and which you would not see coming are three questions. "Ordered by how badly it hurts" answers one of them, in prose |
| The load-bearing belief is never isolated | Every section attacks a symptom of the same belief - that this is a copying job - and none names it |
| The words are for an engineer | planner statistics, sequential scans, buffer cache, glibc, `max_connections`, pooler, `REPLICA IDENTITY`, DDL, a 3600s TTL: each one correct, none followed by what a clinic would see |
| The warnings are half actionable | "Abort at 04:15" can be handed to somebody. "Check whether the plan includes a pooler" is a question with no threshold, no checkpoint and no owner |

## AFTER - part one, the screen (26 lines)

> # What could go wrong - moving 640 GB of clinical records to managed PostgreSQL 16 overnight on 2026-09-19
>
> | | |
> |---|---|
> | **Verdict** | **Think again** |
> | **Why** | On the plan's own numbers the copy ends at 05:10 and the last moment to roll back is 05:00 - the rollback branch can never be used, because the smoke test cannot start before the deadline it is measured against. |
> | **Worst case** | Monday 2026-09-21, 08:00: 1,900 clinics start patient intake against a database that is slow, or sorting records wrongly, with no way back that does not delete Monday morning's clinical writes. Losing 5% of clinics costs about $20,500 a month, or $246,000 a year. |
>
> **The biggest risks** - worst expected damage first.
> 1. After 05:30 there is no way back. Writes made on the new service exist
>    nowhere else, so "point the app at the old server" on Monday silently
>    deletes every appointment, note and charge entered since. In practice the
>    team must fix forward no matter what they find. (risk 1)
> 2. The window does not fit the work. Copy measured 190 minutes;
>    writes-stopped to customers-in is 210 minutes. The copy alone ends at
>    05:10 - ten minutes past the plan's own rollback deadline - leaving 20
>    minutes for 40 checks. (risk 2)
> 3. Statistics do not travel with the data. A 640 GB database with no
>    statistics and a cold cache, hit by 1,900 clinics at 08:00 Monday, is the
>    single likeliest cause of the exact failure the team is measuring. (risk 3)
>
> **The thing nobody is questioning**
> That this is a copying job - that once the bytes are on the new service, the
> work is done. It is a behaviour change: same rows, different query planner,
> different sort order, different permissions.
>
> **Fix before you commit**
> - Move the cut-over to 2026-09-26 or 2026-10-03. Seven Saturdays fall before
>   November; six are spare. (risks 1, 2, 5)
> - Run one full dress rehearsal, end to end, with a stopwatch - backup
>   running, copy, connection switch, statistics, all 40 checks. Cost: about
>   two engineer-days. (risk 2)
> - Ask the vendor this week whether their migration tool supports continuous
>   replication. If yes, pre-copy days ahead so the Saturday window is minutes,
>   not hours. (risks 1, 2)
> - Put `ANALYZE` (or `vacuumdb --analyze-in-stages`) in the runbook as a
>   named, timed step before customers are readmitted. (risk 3)
> - Confirm in writing that the new vendor has a signed data-processing
>   agreement / BAA covering patient data, and confirm which country the data
>   lands in. The contract is already signed; check before the data moves, not
>   after. (risk 7)
> - Either the engineer who ran the trial is on the plan, paid and reachable,
>   or the date moves. (risk 5)
>
> **The decision, rewritten**
> Move the cut-over to Saturday 2026-10-03, which still leaves four spare
> Saturdays before the November host deadline. Pre-copy the 640 GB days in
> advance using continuous replication, so the Saturday window contains only:
> stop writes, wait for replication lag to hit zero, reset sequences, switch
> the connection string, run statistics, run the 40 checks plus a replay of
> real Monday-morning load... Before any of that, run one timed dress rehearsal
> against a fresh production snapshot; if that rehearsal does not finish
> everything by simulated 04:30, the plan is not ready for any Saturday yet.

The BEFORE reached the same recommendation. The difference is that a person
who has never run a database can read this screen, know what was decided, and
hand each fix to somebody with a risk number on it.

## AFTER - the outside view

> ### What usually kills decisions like this
>
> The class: a single-shot, overnight, cross-provider database cut-over with a
> customer-announced fixed window, run by generalists, with a major version
> jump bolted on. Decisions in this class usually die in six ordinary ways.
>
> - The copy runs longer in production than in rehearsal - contention,
>   network, a cold target - and the team blows through its abort point rather
>   than stop, because stopping feels like the failure.
> - The rollback plan is decorative. It exists on paper but becomes unusable
>   the moment users are readmitted, and nobody notices until they need it.
> - The work after the copy - statistics, index rebuild, cache warm-up,
>   sequence reset - is not in the timeline at all, because the timeline was
>   built around the copy.
> - The damage shows up on the first heavy-use day, not in the window, when
>   concurrency arrives.
> - The one person who has actually done it is unavailable.
> - Silent data problems - sort order, encoding, sequences - surface weeks
>   later, after backups of the good state have rotated out.
>
> ... All six are live here. What is **not** live: the usual "you should have
> done it in stages instead of a big bang" objection does not fully apply,
> because one database cannot be split across two providers for long. But the
> staging that *is* available for this class - pre-copying with change capture
> so the window holds only the switch - is not being used, and the brief gives
> no sign it was considered.

## AFTER - the record of the sweep

> ### What was checked
>
> - **Will people use it** - nothing credible. Clinics have no choice to make;
>   there is no adoption question... Worth five phone calls, not a risk card.
> - **Money** - produced part of risk 3. $3,200/month is 0.78% of monthly
>   revenue; the cost is not the risk. Sizing the new instance to fit a budget
>   described as "fixed" is.
> - **Building it** - produced risks 2 and 6.
> - **Running it day to day** - produced risks 1 and 4. Separately: the brief
>   never says monitoring, alerting or backups exist on the new service. On
>   Monday morning the team may have no graph to look at.
> - **The people involved** - produced risk 5.
> - **Things you depend on** - the vendor's support response time at 04:00 on a
>   Saturday is not stated; a basic support tier means no human until Monday...
> - **Legal and rules** - produced risk 7.
> - **People misusing it** - thin, and the only thing that is gameable is the
>   measurement itself: "fewer than 10 customer support tickets about the
>   migration" is judged by whoever classifies tickets, and the same team owns
>   the migration. A slow Monday classified as "general performance" scores a
>   pass. Fix the instrument, not the people: count all tickets Monday against
>   the four previous Mondays.
> - **What others do about it** - nothing credible. A rival practice-management
>   vendor gains a sales story from a public clinical-data incident, but the
>   effect is slow churn, already counted in risk 1's damage.

Nine lines, nine areas. Two of them produced nothing and say so; one found the
success measure itself was the thing that could be gamed, which no card in the
BEFORE was looking for.

## AFTER - one risk card, the most specialist topic in the report

Sort order is where a database engineer says "collation" and stops. This is
the card, in full, because it is the one that had to say what a clinic would
see.

> ### 4. Sort order changes and nobody notices [Running it day to day] - Fix before you commit
>
> - **How it happens:** Text comparison in PostgreSQL comes from the operating
>   system's collation library. The old self-managed server and the new
>   managed host will almost certainly not have the same version. When that
>   changes, text ordering changes: patient names sort differently, range
>   conditions on text return different rows, and indexes built under the old
>   order can disagree with the new one. The output is wrong answers, not error
>   messages. A clinic sees a patient list that is missing someone, or a search
>   that finds nothing. Nobody files a ticket saying "collation" - they file
>   nothing at all, or they file it in November.
> - **What we are assuming:** That data arriving byte-identical means queries
>   return the same answers. They do not, if the sort rules moved.
> - **What this is based on:** PostgreSQL 16 documentation, checked directly:
>   "A change in collation definitions can lead to corrupt indexes and other
>   problems because the database system relies on stored objects having a
>   certain sort order..."...
> - **How likely:** Medium for visible wrongness. A cross-major-version
>   migration must be logical, which means indexes are rebuilt on the target
>   under the target's rules - that removes the index-corruption case. It does
>   not remove the changed-ordering case, which is a real behaviour change with
>   no warning attached.
> - **How bad:** Severe. Wrong clinical record lists are worse than slow ones,
>   and the wrongness has been accumulating by the time anyone spots it.
> - **Would you see it coming:** Not until it is too late. There is no error, no
>   ticket, no alert. Weeks can pass.
> - **How it shows up:** Nothing on the night. Nothing Monday. Somewhere in
>   weeks two to six, one clinic reports a patient who "isn't in the system",
>   and the investigation finds it was never missing, just sorted out of the
>   page they were looking at.
> - **Early warning:** What to watch - run the same ten name-ordered and
>   text-range queries on both servers and compare row-for-row · When to worry -
>   any difference at all · When to check - during the rehearsal, and again on
>   the night before readmission · What to do then - if the sorts differ,
>   decide deliberately: rebuild affected indexes and accept the new order, or
>   match the old collation on the target.
> - **What to do about it:** Add a collation comparison to the rehearsal. Ask
>   the vendor which collation provider and version the new service uses, and
>   compare with the old server. What gets worse: if a rebuild is needed,
>   `REINDEX` on 640 GB runs for hours - another reason the copy cannot own the
>   whole window. **Fix before you commit** (the check is cheap; the rebuild, if
>   needed, changes the schedule).

Compare the BEFORE on the same topic: "text indexes arrive silently wrong -
wrong query results and unique constraints that don't hold". True, and a
clinic manager cannot picture it. "A clinic sees a patient list that is
missing someone" they can.

## Where the words stay plain, and where they do not

The rule at the top of the analysis prompt: where a term cannot be avoided,
say what the person would actually see happen. How the detail layer did on
the specialist ground this decision stands on:

| The specialist thing | What the report says instead, or next to it |
|---|---|
| Planner statistics | "every table looks like an unknown size, so the planner picks full table scans where it used to pick index lookups... Queries that took 50 ms take seconds, connections pile up, and the system either crawls or stops" |
| A cold cache | "the new machine's cache is empty, so the first reads all hit disk" |
| Collation | "patient names sort differently... A clinic sees a patient list that is missing someone, or a search that finds nothing" |
| Sequences | "sequences are not replicated and must be reset by hand at cut-over or Monday's inserts collide with existing IDs" |
| Sub-processor, DPA, BAA | "the cloud vendor becomes a sub-processor. That usually requires a signed data-processing agreement or business associate agreement, a defined hosting country, and notice to customers" |
| Rollback | "Executing the rollback deletes every clinical record entered on Monday morning across 1,900 clinics. So it will not be executed" |

Four terms remain bare: "replica identity" and "large objects" in the
mitigation line of risk 2, "95th-percentile query time" in the early warning
of risk 3, and "vCPU" beside RAM and disk throughput in the same card. Each
sits next to a sentence that does say what the person would see, so a reader
who skips the term loses the mechanism and keeps the consequence. Part one has
none. That is the residue, and it is smaller than example 1's, where the
outside view itself carries "dilapidations" and the sweep carries "escrow"
with nothing beside them.

## What this example changed

1. **The prompt now travels through a script.** The first attempt at this
   example never ran the skill: Claude Code 2.1.222 refuses an inline `cat` of
   a file outside the session's working directory, and a refused inline
   command aborts the whole skill. The agent wrote its own analysis and said
   the skill was blocked. That answer was honest, but it was not the skill's
   output. The prompt is now inlined through `scripts/prompt.sh`, which the
   same Claude Code version does not refuse; the run above is the one made
   after that change.
2. **Nothing in the report format changed.** On a technical decision the shape
   held as written: the verdict first, nine lines for nine areas, one card per
   surviving risk (seven survived), the cross-cutting findings each in their
   slot, and "What holds" naming the one measurement the team got right.
   Rule 6 - a lease and a database migration get the same treatment - is what
   this example measured, and the money and people areas produced risks 3
   and 5, which is where the rule says technical decisions usually fail.
3. **Evidence first, working as written.** The dispatching agent's brief gave a
   date for the end of PostgreSQL 12 support; the fresh agent checked it
   against postgresql.org and corrected it by a week, in the report, with the
   source named. A brief that argues gets a report that agrees; a brief that
   states a wrong fact gets it corrected, if the attacker is allowed to look.
