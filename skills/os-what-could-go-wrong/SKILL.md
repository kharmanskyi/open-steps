---
name: os-what-could-go-wrong
description: >-
  ALWAYS invoke this skill before anything hard to undo gets agreed to - a
  contract, a purchase, a migration, a launch, a price change, a
  reorganisation - and whenever the user asks "what could go wrong", "what are
  we missing", "poke holes in this", or for a premortem or a red team, in any
  language. Assumes the decision already failed and works backwards to find
  out why, in a fresh agent that had no hand in making it. Sweeps nine areas
  and shows what each produced, including the empty ones. Ends on one verdict:
  go ahead, go but fix these first, try it small first, think again, do not do
  this.
allowed-tools:
  - "Read(~/.claude/open-steps/**)"
  - "Bash(bash ${CLAUDE_SKILL_DIR}/scripts/prompt.sh)"
---

# os-what-could-go-wrong

Assume it already failed, then work backwards to find out why - while there is
still time to change it. The attack runs in a fresh agent that had no part in
the decision, because an agent that helped shape one reviews it far too
gently: it defends its own reasoning, and it misses the thing that kills the
plan out of politeness.

`os-ask-simple` screens a choice before the user picks one. This one runs
after the choice is made and before it can no longer be taken back.

## Language

Write in the language the user speaks in this session, detected from the
conversation. Names, figures and identifiers stay as they are. The fresh
agent cannot see this conversation, so the language travels in the handover.

## Step 1 - write down what is actually being decided

Find the decision first. Given as text or a document, that is it. Asked at the
end of a discussion, it is the decision the discussion arrived at, and say
which one you took it to be. If neither, ask which decision to attack.

Then fill every line. This is the only thing the fresh agent will ever see.

```
DECISION BRIEF
What will be done: three to seven sentences
What it is for: the problem it solves, and what success looks like, measured
  wherever it can be
The main moves: the money, the people, the systems, the dates
What is fixed: the constraints, plus the surrounding facts that matter
Who it lands on: who and what is affected if this goes wrong
What cannot be undone: which parts are one-way
When we would know: the date success or failure actually gets judged
What we know: facts from documents, data, the repository, past incidents,
  each with where it came from
What we are assuming: every gap nobody could close, written as an assumption
```

Close the gaps in this order, and stop as soon as a gap is closed.

1. **Look it up yourself.** Documents, data, the repository, the last report
   in `~/.claude/open-steps/reports/`, what went wrong last time.
2. **Ask, but earn the ask.** Only a gap where guessing wrong would change the
   verdict, one question at a time through `os-ask-simple`, three at most.
   Nobody there to answer, or an answer that would not move the verdict -> 3.
3. **Write the guess down as a guess.** Put the assumed value in its line,
   mark it `(assumed)`, and repeat it under "What we are assuming".

The brief states facts and open questions. It never makes the case for the
decision: a brief that argues gets a report that agrees.

## Step 2 - hand it to an agent that had no part in it

Pick the depth, say which in one line, and carry on; the user can change it.

| Depth | When |
|---|---|
| **Full** | Hard to undo, or being wrong costs money, trust or data beyond one team |
| **Quick** | Reversible, and cheap to be wrong about, whoever it touches |

When in doubt, Full. The cost of a full look is a few minutes; the cost of a
quick look at a one-way door is the door.

Dispatch one fresh agent, not several: in Claude Code, a general-purpose
agent; elsewhere, whatever starts with an empty context. Send it four things
and nothing else: the analysis prompt copied exactly from the bottom of this
skill, `MODE: Full` or `MODE: Quick`, `LANGUAGE: <the language above>`, and the
brief. Never send an instruction to run this skill: the fresh session would
load it and start over.

If no fresh agent can be started, run the prompt yourself with the same MODE,
LANGUAGE and brief. The prompt says you did not help make this decision; for
you that is false, so work from the brief alone and attack your own reasoning
hardest. Never call the result independent.

## Step 3 - give it to the user straight

The user never sees what the agent returned: a tool result is visible only to
you. So your final message is that report, copied whole, first line to last.
One line goes before it: the depth, and whether a fresh agent ran (if not,
name your tool and say this session wrote the report). Anything of your own
comes after it, never instead of it: no summary in its place, no "details
above", no reassurance the analysis did not earn, no dropped card because the
user seemed committed. Bad news that arrives late is worth nothing.

Then offer to turn the "Fix before you commit" list into real things: edits to
the plan, tickets, an owner and a date per item, a reminder for each early
warning. "Go ahead" is delivered just as plainly.

## Hard rules

1. **The agent that helped decide does not attack the decision when a fresh
   one can.** Dispatch one every time, even with it all in context. Skipping
   it changes the answer. Only a tool that cannot start one takes the fallback.
2. **No quota of risks.** Publish what has a real chain behind it and nothing
   else. Three well-anchored risks beat seven padded ones, and "only two
   survived" is a finding worth saying out loud.
3. **The verdict is decided last and printed first.** Never make the reader
   assemble it from the risks.
4. **Every area of the sweep is accounted for**, including the ones that
   produced nothing. An area nobody mentions and an area nobody checked look
   the same to the reader.
5. **A skipped section keeps its one line saying why.**
6. **A lease and a database migration get the same treatment.** This is not a
   technical review; the nine areas apply to both, and the money and people
   ones are where technical decisions usually actually fail.
7. **"The plan is sound" is a legitimate answer** once the attack has run. It
   is never a substitute for running one.
8. **The final message is the report itself.** The user cannot see what the
   agent returned; a summary of it, however good, is not it.

## Known gotchas

- **No date to be judged by means no premortem.** Pick a date that fits the
  decision, and say you picked it.
- **Something reversible and cheap does not need this.** Quick look, or say so.
- **"Try it small first" is not a soft no.** Test unknowns before money moves.
- **The user may go ahead against all of it.** Note it once, set the tripwires
  up if they want them, and do not re-argue the report.

The reasoning behind these is in [`references/why-these-rules.md`](references/why-these-rules.md).

## The analysis prompt, verbatim

The block below is the whole of
[`references/premortem-prompt.md`](references/premortem-prompt.md), inlined
when this skill loads through `scripts/prompt.sh`, so no file has to be read
at dispatch time. If it shows a literal command instead, your tool does not
run inline commands: open that file next to this one and use its full text.

!`bash ${CLAUDE_SKILL_DIR}/scripts/prompt.sh`
