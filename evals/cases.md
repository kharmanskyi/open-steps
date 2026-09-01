# Test cases

Everything the measurement asks the agent, in one file. `run.sh` reads this
file directly, so a phrase you change here is the phrase the next run uses.
Scores go to [`results.md`](results.md), which is written by the scorer. Two
files, on purpose: a re-run can never overwrite your phrases.

One rule if you edit the tables: no `|` inside a phrase, it splits the cell.

## Should fire

Three phrases per skill, each asked three times. It counts as a hit only when
that exact skill switched on by itself, with nobody naming it.

| Skill | Phrase |
|---|---|
| os-done-or-not | The work is finished, are we done? Give me the report. |
| os-done-or-not | That's it for today. What happened? |
| os-done-or-not | Report, please. How did the session go? |
| os-whats-next | What's next? What should we pick up now? |
| os-whats-next | What is left to do, anything I can pick up? |
| os-whats-next | What should we work on next? |
| os-check-work | Check the other sessions, how is our process going? |
| os-check-work | The other session says it finished. Check its work. |
| os-check-work | How are the other sessions doing? |
| os-say-simple | My agent in another session sent me this: "The retry storm was mitigated by idempotency-key dedup at the gateway, and the reconcile worker now short-circuits instead of raising." I don't understand this answer. Say it simply. |
| os-say-simple | Here is the update I got: "Rebased onto main after the squash-merge invalidated ancestry; CI green except the flaky e2e lane; lockfile regenerated; feature flag still off pending grants." Too long and too technical. Say it again in plain words, bro. |
| os-say-simple | The reviewer wrote: "LGTM modulo the N+1 in the serializer; also the dedup belongs at the gateway, not the worker." What does this mean? |
| os-step-by-step | I have to put a secret on the server. Tell me exactly what to do. |
| os-step-by-step | The registrar emailed that I must approve the domain change manually. Explain step by step what I should do. |
| os-step-by-step | The setup doc says the database password must be set by me, not by the agent. I don't understand what to do. |
| os-ask-simple | The plan suggests adding a message queue for emails. Is this worth doing, or would something simpler do? |
| os-ask-simple | Should we add a queue here or is that overkill? What would you pick? |
| os-ask-simple | You need a decision from me about the database. Ask me simply. |
| os-what-could-go-wrong | We are about to sign a three-year office lease with no break clause. What could go wrong? |
| os-what-could-go-wrong | Before we migrate the database this Saturday, poke holes in the plan: one four-hour window, 50 million rows, and rollback is repointing back. |
| os-what-could-go-wrong | We have decided to raise prices 20% for existing customers next month. Do a premortem on it, what are we missing? |
| os-whats-built | What have we actually built here? Give me the whole picture of this project. |
| os-whats-built | Map this project for me - what is in it, and what is nobody using any more? |
| os-whats-built | Update the roadmap please, and tell me which parts have gone stale. |

## Should not fire

Ordinary questions with nothing to report and nothing to decide. Any skill
switching on here is a false fire.

| Off-topic phrase |
|---|
| What is the capital of France? |
| Write a haiku about the sea. |
| How many megabytes are in a gigabyte? |

## Report quality

The same messy engineer report, given to the agent twice over: once normally,
once with every skill switched off. The prompt goes first, the report after it.

### Prompt

```text
Say this again in plain words. I don't read code:
```

### Report

```text
Session wrap-up. Hotfix deployed: session TTL misconfig in auth middleware
caused 401 cascades after key rotation; patched the refresh path, invalidated
stale JWTs, redeployed api+web on a1b2c3d. p95 back to 180ms after the CDN
cache purge. Root cause: env drift between staging and prod after the 09-14
rollout; added a drift check to CI (e4f5a6b). Two flaky e2e specs quarantined
(known, tracked). Dependabot queue drained, lockfile regenerated, transitive
CVE closed via starlette bump. Tail: the feature flag stays off pending the
grants ceremony, so live users still see the old flow.
```
