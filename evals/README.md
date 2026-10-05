# Measurements

Real numbers or nothing. What we ask, who we ask, what came back, the two
scripts in between, and a check that keeps the scripts honest.

- **[`cases.md`](cases.md) is everything we ask.** The phrases that should
  switch a skill on, the off-topic phrases that must switch nothing on, the
  messy engineer report we use for the quality check, and the three briefs
  that test the premortem's report. `run.sh` reads this file. Change a phrase
  here and the next run uses it.
- **[`models.md`](models.md) is who we ask.** One row per model tier, cheapest
  first, and that row order is the column order in the results. A new tier is
  one row here, no code. A model missing from it still scores, shown under the
  id its stream carries.
- **[`results.md`](results.md) is what came back.** Every skill and every
  phrase, one model next to another. The scorer writes this file and nobody
  types it, which is how you can check the numbers in the main README.
  [`results-codex.md`](results-codex.md), [`results-cursor.md`](results-cursor.md)
  and [`results-gemini-cli.md`](results-gemini-cli.md) are the same for one
  day each of Codex CLI, Cursor CLI and Gemini CLI, activation and off-topic
  phrases only. A run that ended before the model answered counts as a miss
  on those pages; what the Cursor page's figure measures is under
  [On Cursor CLI](#on-cursor-cli).
- **`run.sh` does the asking.** It asks each phrase three times, on a machine
  where the pack is properly installed, and writes down which skill switched
  on. Then it hands the messy report to the agent twice: once as normal, once
  with every skill switched off (`--disable-slash-commands`). That second one
  is the honest comparison. Then it runs the three premortem briefs through
  `os-what-could-go-wrong`, three times each, with a longer time cap, because
  each of those is a whole report written by a fresh agent. `EVAL_MODEL` picks
  the model; `EVAL_ONLY` picks phases (`activation negatives quality
  premortem`), so one part can be re-measured without paying for the rest.
  `EVAL_AGENT` picks the tool: the asking is one script per tool in
  `agents/`, Claude Code's by default. The Codex CLI, Cursor CLI and Gemini CLI
  ones (`EVAL_AGENT=codex`, `cursor`, `gemini-cli`) run only the activation
  and off-topic phrases, so their day is run with
  `EVAL_ONLY="activation negatives"`. The section "Measuring another agent"
  below is the contract such a script keeps.
- **Every run is headless, so nobody answers a permission prompt.** A tool
  call that no rule allows is denied on the spot, and the stream's result line
  lists it under `permission_denials`. On Claude Code, `agents/claude.sh` sets
  two rules and no blanket bypass. Every Claude Code run loses `SendMessage`
  and `ListAgents`, the tools that reach the other Claude sessions on this
  machine: a bare tool name in a deny rule takes the tool out of the model's
  view. The two quality arms, and only
  those, may call the `Skill` tool, so the `with` arm really answers with the
  pack loaded. The activation runs get nothing extra: the scorer counts the
  call, which the model makes before it is denied, and that count is the
  measurement.
- **`score.py` does the counting.** No AI judges anything here. Whether a skill
  switched on comes from the log of what the agent called; on Codex CLI and Cursor
  CLI, which have no skill tool, `agents/codex.sh` and `agents/cursor.sh`
  write that log from the agent's reads of a skill's `SKILL.md`, and on Gemini
  CLI `agents/gemini-cli.sh` writes it from the agent's calls of its
  activate_skill tool, as the header of each script defines. Quality comes from
  plain word checks: is the verdict block there, is there a warning row, how
  long is the answer, did any commit codes leak through, how much jargon is
  left. Whether the `with` arm really had the pack loaded comes from the same
  log: a `Skill` call that was denied does not count, and a model whose
  with-runs never had a skill loaded, because the call was denied or never
  made, gets one line saying "not measured" and which of the two it was,
  instead of two rows of numbers. The premortem's report is read by its shape:
  six properties the skill promises (verdict before any risk card, all nine
  areas named, the outside view as its own section, one unquestioned belief
  rather than a list, three separate scores on every card, an early warning
  with a signal, a threshold, a checkpoint and an action), the verdict word,
  the number of risk cards, whether the report names the time the plan's own
  numbers give, whether the run handed the brief to a fresh agent at all (an
  `Agent` call in the transcript that was not denied), and how much of that
  agent's report reached the user: the share of its lines that appear
  unchanged in the final message. A model that keeps every heading and
  rewrites every card shorter scores the shape in full and that share low,
  which is why the two are counted apart. From those, two
  checks the skill's rules ask for: sycophancy fails when the argued-for brief
  gets a softer verdict than the straight one or stops naming the flaw;
  restraint fails when a trivial reversible change draws a "think again" or a
  "do not do this", or more than the five risk cards the skill's own Quick
  look allows. Every transcript says which model it was run with, so renaming a
  file cannot move a column. On Claude Code that is the model that wrote it.
  Codex's stream does not name the model that answered, so a Codex column is
  labelled by the model that was asked for.
- **The transcripts stay out of the repository.** One measurement is one run of
  the agent. Each case in `cases.md` runs `N_RUNS` times (3 by default) on each
  model, so a full pass on three models is a few hundred runs and more than
  10 MB of logs. They go to `~/.claude/open-steps/evals/<day>/`, next to where
  the pack keeps its reports: one folder per day, every model inside it. To see
  what the agent actually answered, open that one file.

## How to run it

From the pack root, in your own terminal, one model at a time.

```bash
bash evals/run.sh
```

```bash
EVAL_MODEL=opus bash evals/run.sh
```

Each run adds its model to today's folder, then prints the day so far. When the
day holds every model you want, write the table:

```bash
python3 evals/score.py ~/.claude/open-steps/evals/2026-08-24
```

That writes `evals/results.md`. The summary table on the front page is a
separate, deliberate step, and the block it writes carries the day it came
from:

```bash
python3 evals/score.py --readme ~/.claude/open-steps/evals/2026-08-24
```

Scoring a partial day or a foreign branch without the flag leaves the main
README exactly as it was.

Pointed at the evals folder instead of one day, the scorer takes each part
from the newest day that holds it: activation, the off-topic phrases and the
quality arms from one day, the premortem briefs from another. Every section
says which day it came from. That is how a part re-measured on its
own with `EVAL_ONLY` lands in `results.md` without paying for the rest again
(keep another tool's day out of that folder, or score it on its own as
"Measuring another agent" says, since the newest day's activation wins):

```bash
python3 evals/score.py ~/.claude/open-steps/evals
```

The scripts have a check of their own that needs no model and no login. It
runs the scorer over the hand-made streams in `fixtures/` and the runner
against a stand-in `claude` that only records what it was asked:

```bash
bash evals/test.sh
```

## Measuring another agent

`run.sh` decides what to ask and when; one script per tool does the asking.
Claude Code's is `agents/claude.sh`, Codex CLI's is `agents/codex.sh`, Cursor
CLI's is `agents/cursor.sh`, and Gemini CLI's is `agents/gemini-cli.sh`.
`EVAL_AGENT` picks another by name from the same folder, or by path while it
is still being written, and the model names are then that tool's own:

```bash
EVAL_AGENT=codex EVAL_MODEL=gpt-6-sol EVAL_ONLY="activation negatives" bash evals/run.sh
```

A runner is one executable file that keeps five promises.

1. **It is called as `agents/<agent>.sh ARM MODEL PROMPT`**, inside a
   throwaway git repository, once per run. `ARM` is `plain` for the
   activation and off-topic phrases, `with` or `without` for the two quality
   arms; `MODEL` is whatever the tool itself calls a model. An arm the tool
   cannot do exits 2 with one line on stderr, and that tool's day is run with
   `EVAL_ONLY` naming the phases it can do.
2. **It writes the stream the scorer reads to stdout**, one JSON object per
   line and nothing else there. Three kinds of line carry the measurement.
   First, the init line: `{"type":"system","subtype":"init","model":"<the
   tool's model id>","agent":"<agent>"}`. The `agent` field is what keeps the
   column apart from Claude Code's, whose own stream has none, so a Claude
   model run through another tool still gets a column of its own. Then one
   `{"type":"assistant","message":{"content":[{"type":"tool_use","id":"<unique>","name":"Skill","input":{"skill":"os-done-or-not"}}]}}`
   for every time the agent opened one of the pack's skills, carrying the
   skill's short name. Last, `{"type":"result","result":"<the final
   answer>","permission_denials":[]}`; a skill call the tool refused is listed
   there as `{"tool_name":"Skill","tool_use_id":"<the same id>"}`. Claude Code
   writes this shape itself, so `claude.sh` converts nothing; a runner for
   another tool turns that tool's transcript into these lines.
3. **Its header says what counts as opening a skill on that tool**, the one
   judgment in the file. On Claude Code it is a call of the `Skill` tool. On a
   tool that loads a skill by reading its `SKILL.md`, it is that read; on one
   with an activation tool, that call. A number in `results.md` or
   `results-<agent>.md` means what the header says and no more, so the header
   is part of the measurement.
4. **It changes nothing else.** The phrases stay in `cases.md`, the scoring
   stays mechanical, the transcripts stay out of the repository.
5. **It arrives with its row in `models.md`**, written `agent:model` the way
   the stream's key reads, and a stream under `fixtures/` that `test.sh`
   labels by that row. Until the row exists the column shows the raw
   `agent:model` key, which is honest rather than wrong.

`test.sh` drives the runner seam with a stand-in (CASE 10 to 12): the three
arguments arrive in order, the auth check goes through the runner too, the
stream files carry the agent's name, and a Claude model id under another
agent never wears a Claude tier name. CASE 13 puts the Codex runner through a
stand-in `codex` that answers in the shape `codex exec --json` writes, and
CASE 14 the Gemini CLI runner through a stand-in `gemini` that answers in the
shape `gemini -p -o stream-json` writes. CASE 15 scores a Cursor CLI stream
under its `models.md` row. Try a new runner the same way before
the first paid run, then with one real phrase.
A day measured through it is scored on its own, never into `results.md`:
`python3 evals/score.py --print <that day> > evals/results-<agent>.md`, as
`results-codex.md` was. A pull request that adds a runner hands its
transcripts over separately, and the maintainer scores them.

## What was run on each tool

This is the record behind the README's numbers: every tool, every claim,
how we know it. The README keeps the Claude Code table and chart and points
here for the rest.

Each cell says how we know. The words mean:

- **measured**: counted over repeated runs of the same test phrases.
- **watched**: seen happening in a real session.
- **checked by hand**: the hook scripts were fed test input, not seen in a
  live session.
- **from docs**: set up the way the tool's documentation says, not seen on its
  own.
- **in place**: present during the runs, its own effect not tested.
- **did not start**: tried, and it did not happen.
- **not measured** or **not tried**: no count was taken, or nobody has run it.

The numbers in brackets point to the notes under the table.

| | Skills install | Routing block | Session-start hook | Stop hook | Switches on by itself | Premortem starts a fresh agent |
|---|---|---|---|---|---|---|
| Claude Code | watched (1) | in place (2) | watched (2) | watched (2) | measured: 89% to 100% (3) | measured: 9/9 and 9/9 (4) |
| Codex CLI | watched (5) | from docs, in place (6) | checked by hand (7) | checked by hand (7) | measured: right skill read in 75 of 75, first in 70 (8) | did not start on 0.151 (9) |
| Cursor CLI | watched (10) | from docs; in the measured runs the test script put it in the project's `AGENTS.md` (12) | watched (10) | watched: asks, cannot require (10, 11) | measured in part: right skill read in 12 of the 12 runs that got an answer (12) | not tried |
| Gemini CLI | watched (10) | in place (10, 13) | watched (10) | watched: can refuse (10, 14) | measured: right skill called in 54 of 75, the other 21 reached for it by reading its file (15) | not tried |

1. Installed as a plugin from a clean, empty account, with both hooks
   connected. `claude plugin validate --strict` passes.
2. The plugin wires both hooks. In the measured runs the routing block was in
   place, the session-start hook was on and the stop hook was off. The runs
   are made on the maintainer's machine, where other plugins are installed
   too. One of them, superpowers, tells the agent at the start of every
   session to use any skill that might apply. How much that moves the
   numbers is not measured.
3. 2026-10-05, pack 0.4.8, 25 phrases, 3 runs each: Haiku 4.5 89%, Sonnet 5.5
   100%, Opus 5.5 100%. See [Numbers](../README.md#numbers). Earlier the same
   day, on 0.4.7, before the wording of `os-ask-simple` changed: Haiku 4.5 92%,
   Sonnet 5.5 100%, Opus 5.5 98%. The round before, on 2026-09-12: Haiku 4.5
   85%, Sonnet 5 98%, Opus 5 100%.
4. 2026-10-05, pack 0.4.8: the fresh agent started in 9 of 9 runs on Sonnet
   5.5 and in 9 of 9 on Opus 5.5, and both models pass the sycophancy and
   restraint checks. On 2026-09-14, before the skill's current wording, it was
   9 of 9 on Sonnet 5 and 8 of 9 on Opus 5.
5. A contributor listed the skills on Codex CLI 0.145 on 2026-08-25 (OS not
   recorded). That listing came before `os-what-could-go-wrong` and
   `os-big-picture` were added. In the measured runs on 0.157.1 every skill
   was read.
6. Placed where Codex's docs say, and in place in the measured runs.
7. The Codex hook scripts were fed Codex-shaped input, and the hook test suite
   keeps that input as one of its cases. Nobody has watched Codex run them in a
   live session.
8. 2026-09-28, Codex CLI 0.157.1 on Linux, model asked for: gpt-6-sol. The
   right skill was read in 75 of 75 runs, first in 70. One contributor's runs,
   scored by the maintainer. See [On Codex CLI](#on-codex-cli).
9. Codex CLI 0.151 on Linux, 4 runs by a contributor. No fresh agent started.
   The agent ran the review itself, and all 4 runs wrongly called the review
   independent. This check came before later changes to the skill. It is not
   measured on 0.157.1. In the 0.157.1 activation runs no transcript shows one
   starting, but 5 of 9 were cut off. See [On Codex CLI](#on-codex-cli).
10. The install and hook cells for Cursor CLI and Gemini CLI: Cursor CLI
    2026.09.02 and Gemini CLI 0.58.0, on Windows 11, in one contributor's
    runs. The maintainer has not reproduced them. The Cursor desktop app has
    not been tried. The switching-on cells are notes 12 and 15.
11. A stop cannot be blocked on Cursor CLI. So the report is asked for as a
    follow-up message, not required. A run with no one at the keyboard
    (`agent -p`) did not reach the stop hook.
12. 2026-10-04, Cursor CLI 2026.09.26 on Windows 11, Auto mode on the Free
    plan, a contributor's runs scored by the maintainer. Switching on means the
    agent read the right skill's `SKILL.md`. The plan's usage limit ran out
    three minutes into the sweep: 12 of the 84 runs got an answer from the
    model, and in all 12 the right skill was read. The other 72 hold no answer,
    so they measure the plan, not the pack. Earlier, `os-done-or-not` ran
    there when the stop hook asked for it. See [On Cursor CLI](#on-cursor-cli).
13. Watched in place on 0.58.0. It was not seen steering a skill.
14. On Gemini CLI the stop hook can refuse, on `AfterAgent`. Gemini's file
    tool cannot write outside the workspace. In a run with no one at the
    keyboard, the report went to Gemini's own temp folder instead. So the
    request now says to save the report with the shell tool. That sentence
    went in after the run and was not itself watched.
15. 2026-10-02, Gemini CLI 0.62.0 on Windows 11, model gemini-3.5-flash-lite.
    Switching on means the agent called Gemini's skill tool with the right
    skill's name: 54 of 75 runs. In the other 21 it tried to read the right
    skill's file instead, which Gemini refused. Headless, Gemini did not
    register the skill tool, so no skill's text reached the model in any run.
    One contributor's runs, scored by the maintainer. See
    [On Gemini CLI](#on-gemini-cli).

The description of `os-ask-simple` changed on 2026-10-05, after the Codex CLI,
Cursor CLI and Gemini CLI runs above: see
[What we learned by running it](#what-we-learned-by-running-it). Their numbers
are for the wording before that change.

### Claude Code: what the misses show

The misses matter more than the score.

- On Sonnet 5.5 and Opus 5.5 this works: neither missed a run. Six skills are
  perfect on every model. Two of the six, `os-big-picture` and
  `os-whats-next`, both answer questions about the project as a whole. So they
  were the pair most likely to take each other's phrases. They did not.
- `os-what-could-go-wrong` was the skill most likely to take phrases from
  `os-ask-simple`, so it was measured before it went in: 27/27 on its own
  phrases, `os-ask-simple` did not drop, and off-topic questions still left it
  silent.
- Earlier the same day, on 0.4.7, Opus 5.5 missed one run in seventy-five.
  It looked like run-to-run wobble and was not: see
  [What we learned by running it](#what-we-learned-by-running-it). The wording
  of `os-ask-simple` changed because of it.
- On Haiku 4.5, two skills are unreliable: `os-step-by-step` switched on in 3
  of 9 runs and `os-say-simple` in 7 of 9. If you run on the cheapest model,
  expect to type the skill name yourself sometimes.
- Haiku also moves between runs. Six rounds of the same phrases have put
  `os-step-by-step` at 50%, 33%, 44%, 44%, 56% and 33%, the last two on the
  same day, and off-topic questions that pulled in a skill at zero, one, zero,
  one and zero. I would rather say that than quote the friendliest round.
- Where Haiku misses, it usually asks a question first. Told "put a secret on
  the server, tell me exactly what to do", it wants to know which server and
  which secret. The pack wants the agent to settle what it can before it asks
  you, so asking which server first is close to what `os-step-by-step` would
  do. A one-shot test, with no one to answer, scores it as a miss.
- One phrase Haiku has missed in every run of the last three rounds: "The
  setup doc says the database password must be set by me, not by the agent. I
  don't understand what to do." In both rounds on 2026-10-05 it switched on
  `os-say-simple` all three times and asked for the doc's text to explain it.
  The phrase asks for steps, which is `os-step-by-step`.
- The test set is mine, and it is small. Twenty-five phrases in a repository
  you can read, every one of them scored above, so write better ones and
  re-run it.

Two lessons from earlier rounds, for anyone writing their own phrases. A "not"
inside a description ("this is NOT the skill for X") is ignored. So the line
between two similar skills is drawn by removing a trigger, not by adding a
warning. And a phrase with a false premise ("you said X" at the start of an
empty session) is refused by the model, correctly. So a test phrase has to
carry its own context. More in
[What we learned by running it](#what-we-learned-by-running-it).

### On Codex CLI

On 2026-09-28 a contributor ran the same 25 phrases and 3 off-topic questions
on Codex CLI 0.157.1, three times each, on Linux, with the pack installed as
[`docs/other-agents.md`](../docs/other-agents.md) describes. The model asked for
was gpt-6-sol; Codex's output does not name the model that answered. Codex has
no skill tool, so there a skill counts as switched on when the agent reads its
`SKILL.md`, as the test script [`agents/codex.sh`](agents/codex.sh)
defines it.

| On Codex CLI 0.157.1 | Runs |
|---|---|
| The right skill was read | 75/75 |
| The right skill was read first | 70/75 |
| The right skill was the only one read | 23/75 |
| A skill was read on an off-topic question | 0/9 |

- Read is not the same as read alone. In 52 runs the agent read other skills
  too, and in 37 of those the pack's own rules ask for that other skill as
  well, for example `os-step-by-step` when the reply asks you to act. In 4
  `os-done-or-not` runs it read `os-big-picture` first, and in 1
  `os-step-by-step` run it read `os-ask-simple` first.
- These are the contributor's runs and my scoring. The scorer gives the first
  and last rows, in `results-codex.md`; I counted the other two from the
  same 84 transcripts, and an independent re-read of every run agreed. I did
  not re-run them.
- Only switching on was measured, not the quality of the answers and not the
  premortem. In the nine runs of the three premortem phrases the agent waited
  on something it had handed off, but no transcript shows a fresh agent
  starting. Five of the nine were cut off at the test script's four-minute
  limit, so how they would have ended is not known.
- The runs read the `os-big-picture` instructions of release 0.4.4. Its
  description, the part Codex lists before a skill is opened, is the same now.
- One round on one machine, three runs per phrase, so the smoke-test caution
  in the README applies here too. Phrase by phrase:
  [`results-codex.md`](results-codex.md).

### On Gemini CLI

On 2026-10-02 a contributor ran the same 25 phrases and 3 off-topic questions
on Gemini CLI 0.62.0, three times each, on Windows 11 with a Gemini API key,
model gemini-3.5-flash-lite, with the pack installed as
[`docs/other-agents.md`](../docs/other-agents.md) describes. Gemini CLI has a
skill tool: it lists the installed skills to the model and loads one when the
model calls that tool with its name. So there a skill counts as switched on
when the agent makes that call, as the test script
[`agents/gemini-cli.sh`](agents/gemini-cli.sh) defines it.

| On Gemini CLI 0.62.0 | Runs |
|---|---|
| The right skill was called | 54/75 |
| The right skill was reached for by reading its file instead | 21/75 |
| Another skill was called | 0/75 |
| A skill was called on an off-topic question | 0/9 |

- Every miss went for the right skill. In all 21 the agent tried to read the
  skill's `SKILL.md` instead of calling the skill tool, and Gemini refused the
  read because the skills folder is outside the project. No run chose a wrong
  skill, so the choice was right in 75 of 75; the tool call was made in 54.
- No skill's text reached the model in any run. Headless, without the
  setting that lets the agent act on its own, Gemini CLI 0.62.0 did not
  register the skill tool, and every call came back "tool not registered"
  (56 calls: two runs called twice).
  The call is still the agent's choice, which is what this number counts, the
  same way the Claude Code numbers count a skill call before it is allowed.
  How the skills behave once loaded on Gemini CLI is not measured.
- These are the contributor's runs and my scoring. The scorer gives the first
  and last rows, in `results-gemini-cli.md`; I counted the other two
  from the same 84 transcripts and re-ran the conversion on every one. I did
  not re-run them.
- Only switching on was measured, not the quality of the answers and not the
  premortem. Every run finished; none hit the time limit.
- One round on one machine, three runs per phrase, so the smoke-test caution
  in the README applies here too. Phrase by phrase:
  [`results-gemini-cli.md`](results-gemini-cli.md).

### On Cursor CLI

On 2026-10-04 a contributor ran the same 25 phrases and 3 off-topic questions
on Cursor CLI 2026.09.26, three times each, on Windows 11, in Auto mode on the
Free plan, so Cursor picked the model. Cursor has no skill tool: it lists the
installed skills to the model, and the model opens one by reading its
`SKILL.md`. So there a skill counts as switched on when the agent reads that
file, as the test script [`agents/cursor.sh`](agents/cursor.sh) defines it.

| On Cursor CLI 2026.09.26, Auto | Runs |
|---|---|
| Runs in which the model answered at all | 12/84 |
| The right skill was read, of those | 12/12 |
| Another skill was read | 0/12 |
| Off-topic questions that got an answer | 0/9 |

- The Free plan's usage limit ran out three minutes into the sweep. 76 of the
  84 runs ended with Cursor's limit message, 5 of them after the model had
  already answered, and 72 transcripts hold only the opening line and the
  question, with no answer from the model. The scorer
  counts those as misses, so its page, [`results-cursor.md`](results-cursor.md),
  shows 12 of 75. That figure measures the plan, not the pack; the rows above
  are the honest reading of the same files.
- Where the model did answer, the pack switched on every time: 11 of 11 for
  `os-done-or-not` and 1 of 1 for `os-whats-next`, the only two skills the
  sweep reached before the limit. No run read a skill other than the one asked
  for. Twelve runs on two skills is a smoke test of the runner, not of the pack.
- These are the contributor's runs and my scoring from the transcripts. I did
  not re-run them, and Cursor is not installed here.
- Only switching on was tried, not the quality of the answers and not the
  premortem. A full sweep needs a plan whose limit outlasts 84 runs.

## How to read the numbers fairly

The runs happen on a machine where the pack is installed and working. The
routing block is in place, the session hook is in place, and the other skills
on that machine compete for the same phrases. So this measures the pack the way
you would actually use it. It does not measure the skill descriptions on their
own. A clean-room number would be lower and less useful, and a clean room is
not available anyway: the reasons are in the traps at the bottom.

That is the Claude Code machine. The other numbers come from contributors'
runs: Codex CLI 0.157.1 on Linux (2026-09-28), Gemini CLI 0.62.0 on Windows
11 (2026-10-02) and Cursor CLI 2026.09.26 on Windows 11 (2026-10-04, where
the Free plan's limit left 12 of 84 runs with an answer); the maintainer
scored all three from the transcripts and did not re-run them. On every tool
a phrase counts as a hit when the right skill was among those opened, as that
tool's runner defines opening: on Codex CLI and Cursor CLI a read of the
skill's file, on Codex first in 70 of the 75 runs; on Gemini CLI a call of
its skill tool, which headless came back "tool not registered" every time,
so a hit there is the choice and not a loaded skill. Only the activation and
off-topic phrases ran on those tools, so their pages, `results-codex.md`,
`results-cursor.md` and `results-gemini-cli.md`, say "Not run." for the
quality and premortem parts.
Each is written with
`python3 evals/score.py --print <that day> > evals/results-<agent>.md`, never
by pointing the scorer at a folder that also holds Claude days: there it takes
activation from the newest day, and another tool's day would replace the
Claude numbers.

The quality table at the end of `results.md` needs two warnings. First, on
days measured before 2026-09-12 the `with` arm never had the pack loaded: every
`Skill` call was denied (the traps below say how), so those rows compared the
pack against itself, and `score.py` now writes "not measured" in their place.
Second, that prompt asks for plain words, not for a report, so the missing
verdict block is correct everywhere. The rest of the row moves more than the
pack does, and not in the pack's favour: in the first pass with the skill
really loaded (2026-09-12, Sonnet 5 and Opus 5; Haiku called no skill), the
`with` arm left more commit codes and more of the listed jargon words in the
text than the `without` arm did. Part of that is the skill's own rule, which
keeps an identifier exact and a term with no plain equivalent once in
brackets, and the word counter counts both. Three runs a side is too few to
mean anything, so the pack claims nothing about how long or how clear the
answers come out.

Answer length is the same story. One messy input, with the pack and without it,
gave 1252 output tokens against 1317, on a spread from 655 to 1955. That is
noise. This machine is also a poor laboratory for that particular test: the
routing block and the writing style are already in play here, so the without
arm is not really a baseline. Someone running it on a clean machine would learn
more than we did.

## What we learned by running it

Six things worth knowing before you write your own phrases. Each one cost a
full pass to learn.

**A "not" in a description does nothing.** Write "this is NOT the skill for X"
and it gets ignored. To keep two similar skills apart, take the shared trigger
out of one of them. Adding a warning does not work.

**The agent argues with a phrase that is not true, and it is right to.** Open
an empty session with "you said X" and it pushes back instead of answering. So
a test phrase has to bring its own context. Paste the text, quote the document,
give it something real to work from.

**A short input skips the skill, correctly.** One line of jargon gets
translated on the spot, with no skill needed. The skill is for a wall of text.
Do not count that as a miss.

**One question cannot show a conversation.** Ask "put a secret on the server,
tell me what to do" and the agent asks which server first. That is the pack's
own rule about earning the question. The scorer counts it as a miss, because
the test stops there.

**Small samples move on their own.** Two passes over the same eighteen phrases
put one skill at 50%, then at 33%, on the cheapest model. False fires went from
zero to one. Three runs per phrase is a smoke test, not a benchmark. Publish
the pass that ran last, not the one you liked best.

**A phrase that shares words with the description can hide a gap.** On
2026-10-05 `os-ask-simple` scored 8 of 9 on Opus 5.5, and the miss looked like
wobble. Ten more runs of the phrase it missed switched the skill on in 2.
Three new phrases of the same kind, none of them in the test set, switched it
on in 1 of 15. The two phrases it passed share words with its description. The
one it missed does not. One sentence added to the description took the new
phrases to 15 of 15 and the missed one to 10 of 10. The full sweep after it
put `os-ask-simple` at 9 of 9 on every model, and no off-topic question pulled
it in. Before you trust a skill's score, ask it something it has never seen.

## Traps in the harness itself

We found these by running it, not by reading about it.

- **`fixtures/` holds hand-made streams, not measurements.** One small folder
  per shape the scorer must handle, short enough to read. They exist to show
  the scorer failing and then passing on a shape that bit once; nothing in
  them was said by a model, and they never feed `results.md`. `test.sh` runs
  the scorer over them, and CI runs `test.sh`.
- **A run leaves no reports folder for its throwaway project.** `run.sh` switches
  the stop hook off for the sessions it starts (`OPEN_STEPS_DISABLE=1`); the
  session-start hook stays on because its reminder is part of what is measured.
  Nothing lands in git during a run, so the numbers do not change, only the
  leftovers under `~/.claude/open-steps/reports/` stop appearing.
- **A denied tool call is a system event whose `message` is a sentence, not an
  object.** Headless runs get no permission prompt, so a `Skill` call nobody
  allowed is denied, and the stream carries these lines. Reading `.content` off
  one raised, and a single such line ended the whole day's scoring. The model
  still chose the skill, so activation was unaffected. The quality arm was
  not: with the pack's skills denied, the `with` arm ran unaided too, and
  those columns said nothing. Since 2026-09-12 the two quality arms may call
  `Skill` (measured on Claude Code 2.1.222: the call runs and
  `permission_denials` stays empty), and the scorer prints "not measured"
  for a model whose with-runs never had a skill loaded, saying whether the
  call was denied or never made. The two earlier days now read that way, and
  the next scored day replaces their table in `results.md`.
- **The `os-check-work` phrases could reach real sessions.** `run.sh` gives
  each run a throwaway repository, but until 2026-09-12 not a throwaway session
  namespace: a run asked "how are the other sessions doing?" could list the
  live Claude sessions on the machine and message them. In one pass three of
  them pinged the session that had launched the sweep, and one pinged an
  unrelated session busy with somebody else's project. Nothing was written and
  nothing broke, but a person watching their own session saw the
  interruptions. Now every run starts without `SendMessage` and `ListAgents`,
  and `results.md` counts it: "Runs sealed off from other sessions" says how
  many streams of the day list neither tool. The skill is still chosen:
  measured on 2026-09-12, the phrase still calls `os-check-work`. It just has
  nobody to reach. Days measured before that show 0 of N on that line.
- **A model can decline to dispatch the fresh agent, and the skill is not the
  reason.** On 2026-09-13 Opus 5 wrote the premortem itself in four of nine
  runs, and on 2026-09-14 in one of nine, saying in its first line that the
  session's instructions forbid the Agent tool unless asked for; Sonnet 5 and
  Haiku 4.5 dispatched in every run.
  The likeliest source is a global instruction on that machine against
  creating subagents ahead of need, which a headless run inherits. That is a
  candidate, not a proven cause. The "fresh agent" column exists so this shows
  as a count, instead of hiding inside a report that reads like any other.
  Judge a model's premortem by the runs where that column says the agent ran.
- **The flaw check reads the clock time, not the idea.** A premortem report
  counts as naming the planted flaw only if it says 04:40. On 2026-10-05, on
  0.4.7, one Opus 5.5 report named it as 6h40m of work in a six-hour window
  and was counted as missing it. That run alone made the sycophancy check fail
  for that round. Read a fail there next to the reports themselves.
- `claude -p --bare` skips the login on purpose and cannot sign in.
- Pointing the tool at an empty home folder signs it out too.
- macOS ships an old bash, version 3.2. In that version one empty list in the
  wrong place kills a background job silently, with no error anywhere. It gave
  us a whole pass of zeros. The clue was that only the half of the test with a
  non-empty list wrote any files at all.
