---
name: os-whats-built
description: >-
  ALWAYS invoke this skill when the user asks what the project contains or
  what state it is in as a whole - "what have we built", "what is in this
  project", "map the project", "what does this thing even do", "what is
  stale", "what can we delete", "update the roadmap" - in any language, and
  whenever a session report has just been written. This skill keeps one file,
  ROADMAP.md: a plain-language description of the product, every feature with
  how far it got, which parts nobody has touched, and what is queued next. Age
  and wiring are measured from git; how far a feature got comes from the
  reports or says "not checked". Where the project has a task tracker already
  connected, the skill offers to open the queued items as tickets and creates
  them only after the user says yes. Never invents work and never deletes code.
allowed-tools:
  - "Read(~/.claude/open-steps/**)"
  - "Edit(ROADMAP.md)"
  - "Bash(gh repo view *)"
  - "Bash(gh issue list *)"
  - "Bash(gh issue create *)"
---

# os-whats-built

Every other skill in this pack is one session wide. This one holds the
standing picture of the product: what it is, what is in it, what has gone
quiet, and what is queued. One file, `ROADMAP.md`, in the project itself -
where `os-whats-next` already looks for a backlog.

## Language

Write in the language the user speaks in this session, detected from the
conversation. Code, file names, paths and identifiers stay English.

## When to use

Two moments, one file.

| Moment | What you do |
|---|---|
| The user asks what is in the project, or there is no `ROADMAP.md` yet | The full pass: describe, census, signals, backlog |
| A session report was just written | The fold-in: update only the rows that session touched |

The fold-in is small on purpose. A report names one or two features; re-running
the whole census at the end of every session is waste, and it invites the file
to churn on lines nobody changed. The two measured columns are the exception -
they are re-measured every time, in both moments, because they cost seconds and
because a stale number that survived a fold-in is indistinguishable from a
fresh one.

## Step 1 - find the file, and never clobber it

`ROADMAP.md` in the project root. It may already exist and be somebody's own
work.

Everything this skill writes lives between two markers, and nothing outside
them is ever touched:

```
<!-- open-steps:begin -->
<!-- open-steps:end -->
```

No markers in an existing file → append the block at the end, leaving their
text alone. No file → create it with the block. **Never rewrite a line you did
not write.**

**A stored measurement is not a measurement.** A map that already exists was
true on the day it was written and has been decaying since. Never read `Last
worked on` or `Signal` out of the file and repeat them - not in this file, not
in an answer, not into a ticket. Re-run Steps 2 and 3; git answers in seconds,
and that is the whole cost of never being wrong about them. The only cells
carried forward are the ones nothing can measure: `Stage`, and the queue.

## Step 2 - the census, enumerated and never guessed

List the parts from the repository itself. A hand-written list of directories
misses whole subsystems - this is the most common way this skill produces a
confident, wrong map.

```bash
git ls-files | awk -F/ 'NF>1 {print $1}' | sort -u    # every top-level part
git ls-files | awk -F/ 'NF==1 {print}'                # and the loose files
```

Go one level deeper into anything that holds most of the code. Then per part,
two numbers, both measured:

```bash
git log -1 --format=%ad --date=short -- <path>              # last worked on
git log --oneline --since='6 months ago' -- <path> | wc -l  # how busy
```

## Step 3 - the two signals

Age alone says nothing. Finished code is quiet; so is abandoned code. Two
signals, and only their combination means anything.

| Signal | How you measure it |
|---|---|
| **Quiet** | No commits in six months, from Step 2 |
| **Wired in** | Something outside it reaches it |

Wiring is measured differently per kind of part, and the second row is the one
people forget:

```bash
# code the product imports (Python, JS, Go, …): who imports it
grep -rl "<module>" --include='*.py' <src-dirs> | grep -v "^<its-own-path>"

# a standalone part - a daemon, an app, firmware, a service:
# nothing imports it, so look for who builds, ships or documents it
grep -rl "<dir-name>" --include='*.sh' --include='*.yml' --include='*.toml' \
  --include='Makefile' --include='*.md' . | grep -v "^./<dir-name>"
```

| Quiet | Wired in | Signal to write | What it means |
|---|---|---|---|
| No | - | `active` | Being worked on |
| Yes | Yes | `stable` | Finished and in use. **Leave it alone** |
| Yes | No | `unused - N months` | The only real retire candidate |

**`stable` is the row that protects the user.** Most quiet code is still
imported by dozens of files. A map that flagged all of it would recommend
deleting a working product.

## Step 4 - the backlog, sourced and never invented

`os-whats-next` reads this file and its first rule is that it never invents
tasks. Neither do you. Every item names where it came from:

| Source | What to take from it |
|---|---|
| Session reports in `~/.claude/open-steps/reports/<project>/` | ⏳ deferred rows, "Anything needed from you", recorded debt |
| Step 3 | Each `unused` part, as one retire candidate |
| The user | Anything they add by hand, outside the markers or in |

Nothing else. A gap you noticed while reading the code is not a task; if it
matters, say it in the chat and let the user decide.

## Step 5 - the tracker, if there is one

The map holds the queue. A team that runs on a tracker will not read the map,
so the queue has to reach them where they already look. This step is an offer,
never an action taken quietly.

**Find it, never install it.** Cheapest first, and stop at the first hit:

```bash
gh repo view --json hasIssuesEnabled -q .hasIssuesEnabled   # GitHub Issues
```

Then a tracker already connected to this session - Linear, Notion, Jira,
whatever is available without asking anyone to set something up. Nothing
connected is a normal answer: write one line under "What is next" saying this
file is the tracker, and go to Step 6. Never suggest connecting one.

**Only queued items with a source.** Take the "What is next" rows from Step 4.
Nothing else in the map goes to a tracker - a `stable` feature is not a task,
and a retire candidate is a sentence for the user, not a ticket for a team.

**Search before you propose.** For each item, look for a ticket that already
covers it, open or closed:

```bash
gh issue list --search '<a few words from the item>' --state all \
  --json number,title,state
```

A duplicate ticket is the way this step fails. When the search is unavailable
or returns nothing usable, say the search did not run - never treat silence as
proof the ticket is missing.

**Ask, then create.** Show what is left as plain lines - what it is, where it
came from - and put the choice through `os-ask-simple`. On a yes, create those
tickets and nothing else. On anything else, the map keeps the items and the
tracker stays untouched.

**Never propose out of a stale row.** An item may only become a ticket when
this pass measured what it rests on. A retire candidate needs the wiring check
run today, not the one in the file; an item that came from a report needs that
report still to be the newest one. Where you cannot confirm it, leave it in the
map and say why in the chat. The tracker reaches people who never open this
file, and that is exactly who a stale row would mislead.

**Write the number back.** Each created ticket's number goes into its row in
"What is next". That is what stops the same item being proposed again next
session.

## Step 6 - plain words, before it is written

The map is read by the person who pays for the work, not by the person who
wrote it. Before the block goes into the file, put every sentence in it
through the `os-say-simple` rules: one sentence one idea, active voice, short
sentences, one word for one thing, no synonym rotation.

That covers the "What this is" paragraph, the "What it does" column, the
"Worth retiring" lines and the backlog items. It does not cover the measured
cells - `Stage`, `Signal`, `Last worked on`, ticket numbers and the dated
footer are exact strings and are copied, never reworded.

`os-say-simple`'s own hard rules carry over whole: add nothing, drop no bad
news, numbers and dates stay exact, a claim from a report stays a claim. This
pass changes the words. It never changes a fact.

## The shape

```
<!-- open-steps:begin -->
_Measured <date>. Stages are dated where they stand; anything undated in this
file is not measured._

## What this is

<Three or four sentences. What the product does, who runs it, what it runs
on. No jargon - a reader who has never seen the code.>

## What is in it

| Feature | What it does | Stage | Last worked on | Signal |
|---|---|---|---|---|
| <plain name> | <one line> | live (1 Sep) | 1 Sep | active |
| <plain name> | <one line> | not checked | 28 May | stable |

## Worth retiring

<One line each: what it is, how long unused, what would break. Empty is a
result - write "nothing found" and keep the heading.>

## What is next

- <item> - <source>
- <item> - <source> - #<ticket number, once one exists>

_Age and wiring measured <date>, fresh this pass. Stage comes from session
reports and is only as current as the date beside it._
<!-- open-steps:end -->
```

`Stage` is one of: `building`, `built - not shipped`, `live`, `retired`, or
`not checked`. It cannot be read from code, so it comes from the reports, from
the user, or it says `not checked`.

**And it carries the date it came from, always**: `live (12 Jul)`, not `live`.
That date is the only thing standing between this file and a confident lie.
The measured columns are re-measured on every pass and cannot go stale; `Stage`
can, silently, and the date is what makes the decay visible in the row itself
rather than in a footnote nobody reads. When the newest date in the column is
months behind the newest commit, the reports have stopped - say so in the chat,
in one line. `not checked` never takes a date.

## Hard rules - these rules *are* the skill

1. **Measured and assumed never mix.** `Last worked on` and `Signal` are git
   output, every time. `Stage` has no measurement - reports, or `not checked`.
2. **Enumerate, never guess.** The parts come from `git ls-files`. A list you
   typed from memory will miss a subsystem.
3. **Quiet is not dead.** Never call something a retire candidate without the
   wiring check. Quiet plus wired in is `stable`, and stable is fine.
4. **Never invent work.** Every backlog item names its source.
5. **Never clobber.** Only between the markers. Their file stays theirs.
6. **Recommend, never act.** This skill does not delete code, move files, or
   open a pull request. "Worth retiring" is a sentence, not an action.
7. **Plain words.** A feature is named as the user would say it, not as the
   folder is spelled. Paths belong in the technical detail of a report.
8. **One screen per section.** Twelve features and the map is a wall of text -
   group them and say you grouped them.
9. **A ticket is created only after an explicit yes.** Rule 6 covers the code;
   this covers everyone else's inbox. Searching a tracker is free, filling one
   is not, and no ticket is ever closed, edited or reordered by this skill.
10. **The plain-words pass never touches a measured cell.** Prose is rewritten,
    `Stage`, `Signal`, dates and ticket numbers are copied exactly.
11. **Re-measure, never quote.** `Last worked on` and `Signal` are measured on
    every pass, including the small fold-in. A number read back out of the file
    is a number about the past wearing today's date.
12. **Every claim carries its date or says it has none.** `Stage` is dated;
    `not checked` is honest. A map that cannot go visibly stale will go
    invisibly stale, and this pack's own rule is that a stale map is worse
    than no map.

## Known gotchas

- **Vendored code reads as abandoned.** A copied-in dependency has one commit,
  years old, and is not yours to retire. Vendor folders come off the map.
- **Generated and build output too** - anything the project rebuilds is not a
  feature.
- **git says last *touched*, not last *used*.** A part with no commits may run
  every day. That is why wiring is a separate signal, not a tiebreaker.
- **A renamed folder looks new.** `git log --follow` on a single file when a
  date looks wrong; a whole subsystem that moved will read as three months old
  on the day it moved.
- **A monorepo is not one product.** Several deployables → group the map by
  deployable, or the "what this is" paragraph becomes a lie of averages.
- **The same item proposed twice.** A ticket whose number never made it back
  into the row will be offered again next session, and the team gets two.
  Write the number back in the same pass that creates the ticket.
- **A closed ticket is still a match.** Search `--state all`. An item someone
  already did and closed should leave the map, not reopen as a new ticket.
- **No tracker is not a fault.** Plenty of projects run on the map alone. Say
  it in one line and never turn it into a recommendation to adopt one.
- **Plain words are not fewer facts.** A shorter "Worth retiring" line that
  drops what would break is worse than the long one.
- **The reports stopping does not stop the map.** The measured half keeps
  refreshing itself and looks healthy, while `Stage` quietly ages behind it.
  That is the failure this file is most likely to have: half-fresh, and
  therefore trusted whole. The dates in the `Stage` column are the only cure.
- **The map going quiet is itself a signal** - a `Stage` column that is all
  `not checked` means the reports are not being written, not that the product
  is unknowable. Say so.
