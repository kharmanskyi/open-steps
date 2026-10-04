# Measured results

Written by `score.py` from the raw streams, so no number here is typed
by hand. The phrases are in [`cases.md`](cases.md).

Day `2026-10-04`, models Cursor (Auto). Every phrase asked 3 times per model.
Whether runs were sealed off from other sessions: not checked, these streams do not list their tools.

A column from a tool other than Claude Code carries the model its runner names, and what counts there as a skill switching on is defined in that runner, `evals/agents/<tool>.sh`.

## Did the right skill switch on by itself

| Skill | Cursor (Auto) |
|---|---|
| `os-done-or-not` | 11/12 |
| `os-whats-next` | 1/9 |
| `os-check-work` | 0/9 |
| `os-say-simple` | 0/9 |
| `os-step-by-step` | 0/9 |
| `os-ask-simple` | 0/9 |
| `os-what-could-go-wrong` | 0/9 |
| `os-big-picture` | 0/9 |
| **All phrases** | **12/75 (16%)** |
| Fired on an off-topic question | 0/9 |

## Phrase by phrase

| Skill | Phrase | Cursor (Auto) |
|---|---|---|
| `os-done-or-not` | The work is finished, are we done? Give me the report. | 3/3 |
| `os-done-or-not` | That's it for today. What happened? | 2/3 |
| `os-done-or-not` | Report, please. How did the session go? | 3/3 |
| `os-done-or-not` | We just finished the changes on this ticket. What's the status? | 3/3 |
| `os-whats-next` | What's next? What should we pick up now? | 1/3 |
| `os-whats-next` | What is left to do, anything I can pick up? | 0/3 |
| `os-whats-next` | What should we work on next? | 0/3 |
| `os-check-work` | Check the other sessions, how is our process going? | 0/3 |
| `os-check-work` | The other session says it finished. Check its work. | 0/3 |
| `os-check-work` | How are the other sessions doing? | 0/3 |
| `os-say-simple` | My agent in another session sent me this: "The retry storm was mitigated by idempotency-ke ... | 0/3 |
| `os-say-simple` | Here is the update I got: "Rebased onto main after the squash-merge invalidated ancestry; ... | 0/3 |
| `os-say-simple` | The reviewer wrote: "LGTM modulo the N+1 in the serializer; also the dedup belongs at the ... | 0/3 |
| `os-step-by-step` | I have to put a secret on the server. Tell me exactly what to do. | 0/3 |
| `os-step-by-step` | The registrar emailed that I must approve the domain change manually. Explain step by step ... | 0/3 |
| `os-step-by-step` | The setup doc says the database password must be set by me, not by the agent. I don't unde ... | 0/3 |
| `os-ask-simple` | The plan suggests adding a message queue for emails. Is this worth doing, or would somethi ... | 0/3 |
| `os-ask-simple` | Should we add a queue here or is that overkill? What would you pick? | 0/3 |
| `os-ask-simple` | You need a decision from me about the database. Ask me simply. | 0/3 |
| `os-what-could-go-wrong` | We are about to sign a three-year office lease with no break clause. What could go wrong? | 0/3 |
| `os-what-could-go-wrong` | Before we migrate the database this Saturday, poke holes in the plan: one four-hour window ... | 0/3 |
| `os-what-could-go-wrong` | We have decided to raise prices 20% for existing customers next month. Do a premortem on i ... | 0/3 |
| `os-big-picture` | What have we actually built here? Give me the whole picture of this project. | 0/3 |
| `os-big-picture` | Map this project for me - what is in it, and what is nobody using any more? | 0/3 |
| `os-big-picture` | Where are we with this project overall? Give me the big picture. | 0/3 |

## Report quality on the same messy input

Not run.

## What the premortem's report looks like

Not run.

