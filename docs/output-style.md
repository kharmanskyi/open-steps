# The "Answer first" output style

This is a Claude Code setting. The pack does not wire it on Codex CLI, Cursor
CLI or Gemini CLI.

Optional. This is the piece aimed straight at long answers. Nobody has measured
whether it makes them shorter. The evals switch the skills on and off, never
this style, so the length test in [`evals/README.md`](../evals/README.md) says
nothing about it.

## What it fixes

You ask one small thing and get forty lines back, where every fact drags its own
provenance behind it: what was checked, what was checked instead, why the first
approach was wrong, what an old decision record said about it.

That is usually not chattiness. It is what happens when an agent is told never to
claim anything unverified: it starts *showing* proof rather than merely *having*
it. Telling it "be shorter" trades away the honesty. This style separates the
two instead: the answer comes first, and the evidence comes on request.

Before, a two-part question:

> I checked the raw vendor records rather than our own summary, and I confirm the
> earlier conclusion, but now with a caveat that matters more than the conclusion
> itself. In `/accounts` there is no name: the vendor returned exactly six
> fields… But the spike only probed three routes… (continues for thirty more
> lines)

After:

> No names. The vendor returns six fields and none of them is a name. But there
> is one endpoint we never opened; want me to check it, one request?
>
> Retry: the engine fetches 8 accounts at a time, so one pass does not cover 252.
> I'll file a ticket.
>
> Say the word for the measurements.

## Turn it on

The style ships with the Claude Code plugin. It does **not** switch itself on;
the next section says why.

- **Terminal:** run `/config`, choose **Output style**, pick **Answer first**.
- **Any Claude Code client:** set the field directly in `~/.claude/settings.json`:

```json
{
  "outputStyle": "Answer first"
}
```

It takes effect after `/clear` or in your next session, because the system prompt
is read once at session start.

## Why it does not switch itself on

Claude Code plugin output styles support `force-for-plugin: true`, which
applies the style automatically and, per the documentation, **overrides the
user's own `outputStyle` setting**.

This pack deliberately leaves it off. Someone who has chosen Explanatory, or
written their own style, should not lose it silently by installing an unrelated
pack. A pack whose whole premise is "do not surprise the person using it" does
not get to surprise them at install time.

If you are packaging this for a team that wants it on by default, add
`force-for-plugin: true` to the frontmatter of `output-styles/answer-first.md`.
It is one line. Tell people you did.

## What it does not cover

- **Subagents.** They run their own system prompt, so the style does not reach
  them. A long answer coming out of a delegated task is a separate problem.
- **Code behaviour.** The frontmatter sets `keep-coding-instructions: true`, so
  the built-in engineering instructions stay in place. Only the shape of replies
  changes.
- **Deliberate detail.** The style keeps full-length output for security
  problems, anything hard to undo, step-by-step instructions, and any time you
  ask for depth.

## Note when editing it

Changes to `SKILL.md` files take effect immediately. Changes to
`output-styles/` do not: run `/reload-plugins` or restart Claude Code.
