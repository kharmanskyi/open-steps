# Measurements

Real numbers or nothing. Six files: what we ask, who we ask, what came back,
and the two scripts in between.

- **[`cases.md`](cases.md) is everything we ask.** The phrases that should
  switch a skill on, the off-topic phrases that must switch nothing on, and the
  messy engineer report we use for the quality check. `run.sh` reads this file.
  Change a phrase here and the next run uses it.
- **[`models.md`](models.md) is who we ask.** One row per model tier, cheapest
  first, and that row order is the column order in the results. A new tier is
  one row here, no code. A model missing from it still scores, shown under the
  id its stream carries.
- **[`results.md`](results.md) is what came back.** Every skill and every
  phrase, one model next to another. The scorer writes this file and nobody
  types it, which is how you can check the numbers in the main README.
- **`run.sh` does the asking.** It asks each phrase three times, on a machine
  where the pack is properly installed, and writes down which skill switched
  on. Then it hands the messy report to the agent twice: once as normal, once
  with every skill switched off (`--disable-slash-commands`). That second one
  is the honest comparison. `EVAL_MODEL` picks the model.
- **`score.py` does the counting.** No AI judges anything here. Whether a skill
  switched on comes from the log of what the agent called. Quality comes from
  plain word checks: is the verdict block there, is there a warning row, how
  long is the answer, did any commit codes leak through, how much jargon is
  left. Every transcript says which model wrote it, so renaming a file cannot
  move a column.
- **The transcripts stay out of the repository.** One measurement is one run of
  the agent, so a full pass over every phrase on three models is 234 runs and
  12 MB of logs. They go to `~/.claude/open-steps/evals/<day>/`, next to where
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

## How to read the numbers fairly

The runs happen on a machine where the pack is installed and working. The
routing block is in place, the session hook is in place, and the other skills
on that machine compete for the same phrases. So this measures the pack the way
you would actually use it. It does not measure the skill descriptions on their
own. A clean-room number would be lower and less useful, and a clean room is
not available anyway: the reasons are in the traps at the bottom.

The quality table at the end of `results.md` needs a warning. That prompt asks
for plain words, not for a report, so the missing verdict block is correct
everywhere. The rest of the row moves more than the pack does. In the last pass
the pack's own answers left more commit codes in the text than the unaided
answers did, on two models out of three. Three runs a side is too few to mean
anything, so the pack claims nothing about how long or how clear the answers
come out.

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

We found all three by running it, not by reading about it.

- **`fixtures/` holds hand-made streams, not measurements.** One small folder
  per shape the scorer must handle, short enough to read. They exist to show
  the scorer failing and then passing on a shape that bit once; nothing in
  them was said by a model, and they never feed `results.md`.
- **A denied tool call is a system event whose `message` is a sentence, not an
  object.** Headless runs get no permission prompt, so every `Skill` call in a
  sweep is denied and every stream carries these lines. Reading `.content` off
  one raised, and a single such line ended the whole day's scoring. The model
  still chose the skill, so activation is unaffected - but the quality arm is:
  with the pack's skills denied, the `with` arm is running unaided too, and
  those columns say nothing at all until a run permits them.
- `claude -p --bare` skips the login on purpose and cannot sign in.
- Pointing the tool at an empty home folder signs it out too.
- macOS ships an old bash, version 3.2. In that version one empty list in the
  wrong place kills a background job silently, with no error anywhere. It gave
  us a whole pass of zeros. The clue was that only the half of the test with a
  non-empty list wrote any files at all.
