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
  reports or says "not checked". Never invents work and never deletes code.
allowed-tools:
  - "Read(~/.claude/open-steps/**)"
  - "Edit(ROADMAP.md)"
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
to churn on lines nobody changed.

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

## The shape

```
<!-- open-steps:begin -->
## What this is

<Three or four sentences. What the product does, who runs it, what it runs
on. No jargon - a reader who has never seen the code.>

## What is in it

| Feature | What it does | Stage | Last worked on | Signal |
|---|---|---|---|---|
| <plain name> | <one line> | live | 1 Sep | active |
| <plain name> | <one line> | not checked | 28 May | stable |

## Worth retiring

<One line each: what it is, how long unused, what would break. Empty is a
result - write "nothing found" and keep the heading.>

## What is next

- <item> - <source>

_Age and wiring measured <date>. Stage comes from session reports._
<!-- open-steps:end -->
```

`Stage` is one of: `building`, `built - not shipped`, `live`, `retired`, or
`not checked`. It cannot be read from code, so it comes from the reports, from
the user, or it says `not checked`.

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
- **The map going quiet is itself a signal** - a `Stage` column that is all
  `not checked` means the reports are not being written, not that the product
  is unknowable. Say so.
