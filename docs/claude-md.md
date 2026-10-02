# Add the routing block

The routing block is a short set of lines for the file your tool reads as
standing instructions. It lives in [`docs/routing-block.md`](routing-block.md).
Copy it from there, so there is one copy of it to keep current. No installer
adds it for you. That file is yours, so you add the block once.

**Add this step.** Every published measurement was taken with this block in
place.

- On Claude Code it goes in `~/.claude/CLAUDE.md`, as
  [below](#on-claude-code-add-it-to-claudemd).
- On Codex CLI, Cursor CLI and Gemini CLI it goes in that tool's own
  instructions file.
  [`docs/other-agents.md`](other-agents.md#the-routing-block) has the file and
  the command for each.

## Why the block is there

A skill is **model-invoked**: the agent decides whether to load it. Two of the
moments the block names are easy for an agent to miss on its own. That is why
the block exists. No run has been made without the block, so how often they
are missed is not measured.

- Asking you to do something does not feel like a task to the agent, so
  `os-step-by-step` can get skipped and you get a wall of commands instead.
- Asking you a technical question feels like ordinary conversation, so
  `os-ask-simple` can get skipped and you get jargon with no recommendation.

The skill descriptions are written in a directive form ("ALWAYS invoke this
skill…"). On Claude Code (2026-09-12) they switched on in 98-100% of the test
runs on Sonnet 5 and Opus 5, and 85% on Haiku 4.5. On Codex CLI 0.157.1
(2026-09-28) the right skill was read in 75 of 75 runs; the details are in the
README, [On Codex CLI](../README.md#on-codex-cli). The evals do not compare
this form with other wordings. The block adds the part a description cannot:
a rule, and a table that says which moment maps to which skill.

## On Claude Code: add it to CLAUDE.md

From the clone, one command adds it, and it refuses to add it twice:

```bash
grep -q 'os-done-or-not' ~/.claude/CLAUDE.md 2>/dev/null || cat docs/routing-block.md >> ~/.claude/CLAUDE.md
```

Or paste it by hand, near the top: earlier instructions carry more weight than
later ones.

## Optional: the status line

Apart from the skills, this one line per reply removes the most common
confusion: not knowing whether the agent has finished. The same lines can go
in any tool's instructions file.

```markdown
## End every reply with a status line

Finish every response with exactly one of these, on its own last line, in the
language of the conversation:

- ✅ **Done.** Finished and verified.
- ⏸ **Waiting on you.** Blocked on me; name what is needed in ten words or fewer.
- ⏳ **Still working.** More steps are coming.
- ⚠️ **Done, with a caveat.** Finished, but something is unverified or risky.

Never claim ✅ for anything not actually verified. Use ⚠️ instead.
```

This belongs in the instructions file rather than in a skill for the same
reason: it has to hold for every reply, and a skill cannot guarantee that.

## The session-start hook does not replace this block

The session-start hook (`hooks/session-start.sh`) injects the same routing
table plus the last session's report at the start of every session, so a new
session begins oriented instead of re-exploring the repository. On Claude Code
the plugin wires it, so there is nothing to add by hand. On Codex CLI, Cursor
CLI and Gemini CLI you wire it yourself, as
[`docs/other-agents.md`](other-agents.md#the-hooks) shows.

Keep the block anyway. The hook speaks once, at the start. On Claude Code the
`CLAUDE.md` block is re-injected after the conversation is compacted, so in a
long session it is the copy that survives. They say the same thing on purpose.

To switch the hook off: `export OPEN_STEPS_NO_SESSION_START=1`.
