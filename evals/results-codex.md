# Measured results

Written by `score.py` from the raw streams, so no number here is typed
by hand. The phrases are in [`cases.md`](cases.md).

Day `2026-09-28`, models GPT-6 Sol (Codex). Every phrase asked 3 times per model.
Whether runs were sealed off from other sessions: not checked, these streams do not list their tools.

A column from a tool other than Claude Code carries the model its runner names, and what counts there as a skill switching on is defined in that runner, `evals/agents/<tool>.sh`.

## Did the right skill switch on by itself

| Skill | GPT-6 Sol (Codex) |
|---|---|
| `os-done-or-not` | 12/12 |
| `os-whats-next` | 9/9 |
| `os-check-work` | 9/9 |
| `os-say-simple` | 9/9 |
| `os-step-by-step` | 9/9 |
| `os-ask-simple` | 9/9 |
| `os-what-could-go-wrong` | 9/9 |
| `os-big-picture` | 9/9 |
| **All phrases** | **75/75 (100%)** |
| Fired on an off-topic question | 0/9 |

## Phrase by phrase

| Skill | Phrase | GPT-6 Sol (Codex) |
|---|---|---|
| `os-done-or-not` | The work is finished, are we done? Give me the report. | 3/3 |
| `os-done-or-not` | That's it for today. What happened? | 3/3 |
| `os-done-or-not` | Report, please. How did the session go? | 3/3 |
| `os-done-or-not` | We just finished the changes on this ticket. What's the status? | 3/3 |
| `os-whats-next` | What's next? What should we pick up now? | 3/3 |
| `os-whats-next` | What is left to do, anything I can pick up? | 3/3 |
| `os-whats-next` | What should we work on next? | 3/3 |
| `os-check-work` | Check the other sessions, how is our process going? | 3/3 |
| `os-check-work` | The other session says it finished. Check its work. | 3/3 |
| `os-check-work` | How are the other sessions doing? | 3/3 |
| `os-say-simple` | My agent in another session sent me this: "The retry storm was mitigated by idempotency-ke ... | 3/3 |
| `os-say-simple` | Here is the update I got: "Rebased onto main after the squash-merge invalidated ancestry; ... | 3/3 |
| `os-say-simple` | The reviewer wrote: "LGTM modulo the N+1 in the serializer; also the dedup belongs at the ... | 3/3 |
| `os-step-by-step` | I have to put a secret on the server. Tell me exactly what to do. | 3/3 |
| `os-step-by-step` | The registrar emailed that I must approve the domain change manually. Explain step by step ... | 3/3 |
| `os-step-by-step` | The setup doc says the database password must be set by me, not by the agent. I don't unde ... | 3/3 |
| `os-ask-simple` | The plan suggests adding a message queue for emails. Is this worth doing, or would somethi ... | 3/3 |
| `os-ask-simple` | Should we add a queue here or is that overkill? What would you pick? | 3/3 |
| `os-ask-simple` | You need a decision from me about the database. Ask me simply. | 3/3 |
| `os-what-could-go-wrong` | We are about to sign a three-year office lease with no break clause. What could go wrong? | 3/3 |
| `os-what-could-go-wrong` | Before we migrate the database this Saturday, poke holes in the plan: one four-hour window ... | 3/3 |
| `os-what-could-go-wrong` | We have decided to raise prices 20% for existing customers next month. Do a premortem on i ... | 3/3 |
| `os-big-picture` | What have we actually built here? Give me the whole picture of this project. | 3/3 |
| `os-big-picture` | Map this project for me - what is in it, and what is nobody using any more? | 3/3 |
| `os-big-picture` | Where are we with this project overall? Give me the big picture. | 3/3 |

## Report quality on the same messy input

Not run.

## What the premortem's report looks like

Not run.

