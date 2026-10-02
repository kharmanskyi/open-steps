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
  [`results-codex.md`](results-codex.md) is the same for one day of Codex
  CLI, activation and off-topic phrases only.
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
  `agents/`, Claude Code's by default. Codex CLI's (`EVAL_AGENT=codex`) can
  run only the activation and off-topic phrases, so its day is run with
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
  switched on comes from the log of what the agent called; on Codex, which has
  no skill tool, `agents/codex.sh` writes that log from the agent's reads of a
  skill's `SKILL.md`, as the header of that script defines. Quality comes from
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
Claude Code's is `agents/claude.sh`, and Codex CLI's is `agents/codex.sh`.
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
stand-in `codex` that answers in the shape `codex exec --json` writes. Try a
new runner the same way before the first paid run, then with one real phrase.
A day measured through it is scored on its own, never into `results.md`:
`python3 evals/score.py --print <that day> > evals/results-<agent>.md`, as
`results-codex.md` was. A pull request that adds a runner hands its
transcripts over separately, and the maintainer scores them.

## How to read the numbers fairly

The runs happen on a machine where the pack is installed and working. The
routing block is in place, the session hook is in place, and the other skills
on that machine compete for the same phrases. So this measures the pack the way
you would actually use it. It does not measure the skill descriptions on their
own. A clean-room number would be lower and less useful, and a clean room is
not available anyway: the reasons are in the traps at the bottom.

That is the Claude Code machine. The Codex CLI numbers come from one
contributor's runs on Linux (Codex CLI 0.157.1, 2026-09-28), which the
maintainer scored from the transcripts and did not re-run. On both tools a
phrase counts as a hit when the right skill was among those opened; on Codex
it was also the first one opened in 70 of the 75 runs. Only the activation and
off-topic phrases ran there, so that day's page, `results-codex.md`, says "Not
run." for the quality and premortem parts. It is written with
`python3 evals/score.py --print <that day> > evals/results-codex.md`, never by
pointing the scorer at a folder that also holds Claude days: there it takes
activation from the newest day, and a Codex day would replace the Claude
numbers.

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

Five things worth knowing before you write your own phrases. Each one cost a
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
- `claude -p --bare` skips the login on purpose and cannot sign in.
- Pointing the tool at an empty home folder signs it out too.
- macOS ships an old bash, version 3.2. In that version one empty list in the
  wrong place kills a background job silently, with no error anywhere. It gave
  us a whole pass of zeros. The clue was that only the half of the test with a
  non-empty list wrote any files at all.
