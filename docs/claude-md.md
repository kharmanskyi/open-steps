# Add this to your CLAUDE.md

**The pack does not fully work without this step.** No installer edits your
`CLAUDE.md` - that file is yours - so the block gets added once, by you.

From the clone, one command adds it (and refuses to add it twice):

```bash
grep -q 'os-done-or-not' ~/.claude/CLAUDE.md 2>/dev/null || cat docs/routing-block.md >> ~/.claude/CLAUDE.md
```

Or paste it by hand - near the top matters, earlier instructions carry more
weight than later ones. The block, also in
[`docs/routing-block.md`](routing-block.md):

```markdown
## These moments require a skill - not optional

Invoke the skill. Do not improvise the answer in its place.

| Moment | Skill |
|---|---|
| I ask what is next, what is left, or what is blocked | `os-whats-next` |
| **Any technical question you put to me, or any options you offer** | `os-ask-simple` |
| **Any message where you ask me to do something** - run a command, paste a value, approve, choose, test on a device | `os-step-by-step` |
| I ask about other sessions, or to accept work one of them finished | `os-check-work` |
| Work is finished, or I ask how it went | `os-done-or-not` |
| I say I did not understand, ask for simpler or shorter, or paste text asking what it means | `os-say-simple` |

Never offer me options without naming a recommendation, and never recommend
something you have not screened for future cost.

Reports live in `~/.claude/open-steps/reports/<project>/`. Read `latest.md`
before re-exploring a repository you have worked in before.
```

On another agent the same block goes in that agent's own instructions file
instead. [`docs/other-agents.md`](other-agents.md) has the file and the command
for each, and the hooks below are a separate matter on those tools.

## Why this is required and not a nicety

A skill is **model-invoked**: the agent decides whether to load it. Two of these
moments are ones the agent will not notice on its own.

- Asking you to do something does not feel like a task to the agent, so
  `os-step-by-step` gets skipped and you get a wall of commands instead.
- Asking you a technical question feels like ordinary conversation, so
  `os-ask-simple` gets skipped and you get jargon with no recommendation.

The skill descriptions are written in the directive form that measures best for
activation, and that is the dominant factor. The block adds the part a
description cannot: an obligation, and a table that says which moment maps to
which skill. It is also re-injected after the conversation is compacted, so it
survives long sessions.

## Optional: the status line

Independent of the skills, this one line per reply removes the most common
confusion - not knowing whether the agent has finished.

```markdown
## End every reply with a status line

Finish every response with exactly one of these, on its own last line, in the
language of the conversation:

- ✅ **Done.** - finished and verified.
- ⏸ **Waiting on you.** - blocked on me; name what is needed in ten words or fewer.
- ⏳ **Still working.** - more steps are coming.
- ⚠️ **Done, with a caveat.** - finished, but something is unverified or risky.

Never claim ✅ for anything not actually verified - use ⚠️ instead.
```

This belongs in `CLAUDE.md` rather than in a skill for the same reason: it has to
hold for every reply, and a skill cannot guarantee that.

## The session-start hook does not replace this block

The plugin already wires a SessionStart hook (`hooks/session-start.sh`): at
the start of every session it injects the same routing table plus the last
session's report, so a new session begins oriented instead of re-exploring
the repository. Nothing to add by hand - installing the plugin turned it on.

Keep the block anyway. The hook speaks once, at the start; the `CLAUDE.md`
block is re-injected after the conversation is compacted, so in a long
session it is the copy that survives. They say the same thing on purpose.

To switch the hook off: `export OPEN_STEPS_NO_SESSION_START=1`.
