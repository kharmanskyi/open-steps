# Running the pack on Codex, Cursor and Gemini CLI

Claude Code is what the pack is built and measured on. Everything here is the
second-best case: the skills carry over cleanly, the routing block carries over
cleanly, the hooks carry over on one other tool and not yet on the rest.

What was run is marked as run. Everything else comes from a vendor's
documentation and is called out where it matters. Same rule the skills follow.

## The skills

A skill is a folder with a `SKILL.md` in it, and that format is now shared
across tools. Codex, Cursor and Gemini CLI all read one folder,
`~/.agents/skills/`, so a single command installs the pack into all three. Run
it from the folder holding the clone, the one that contains `open-steps/`:

```bash
mkdir -p ~/.agents/skills && cp -R open-steps/skills/os-* ~/.agents/skills/
```

Copies, so run it again after a `git pull` to update.

One skill carries over worse than the rest. `os-what-could-go-wrong` inlines
its analysis prompt with a `!` command and hands the attack to a fresh
subagent, and both are Claude Code behaviours. Measured on Codex CLI 0.151.0,
four runs with a real decision brief. The `!` line arrives as literal text and
the skill's own fallback works: Codex reads
`references/premortem-prompt.md` next to it. No fresh agent is dispatched. All
four runs called the review independent anyway, one wrote the whole report
twice, and one skipped a step the others took.

A fresh process is reachable, but not on defaults. A nested `codex exec` fails
to initialize inside the sandbox; the session reports that the dispatch failed
and calls the review independent in the same sentence. With approvals and the
sandbox bypassed it starts, about three minutes, with its own session id. What
went out was the brief plus an instruction to run the skill rather than the
four things step 2 names, so the fresh session loaded the skill and ran the
whole thing again, and the report appeared four times in one transcript.

Linking instead works and updates itself, but it renames the skills. Codex
resolves a symlink back to the clone and takes the namespace from the folder
it lands in, so `ln -sfn "$PWD"/open-steps/skills/os-* ~/.agents/skills/`
produces `open-steps:os-done-or-not` where a copy produces `os-done-or-not`.
The routing block uses the short names. Copy unless there is a reason not to.

Each tool also has its own folder, should the shared one ever be a problem:
`~/.codex/skills/`, `~/.cursor/skills/`, `~/.gemini/skills/`. Cursor also reads
`~/.claude/skills/` and `~/.codex/skills/`, though behind a setting covered
below. These per-tool paths come from each tool's documentation; the shared
folder is the one that was run.

## The routing block

The block in [`routing-block.md`](routing-block.md) does the same job here as
in `CLAUDE.md`: it turns the moments it names into an obligation rather than a
hint. Skills are model-invoked everywhere, so this matters everywhere.

One command per tool, from the folder holding the clone, safe to re-run:

| Tool | File | Command |
|---|---|---|
| Codex | `~/.codex/AGENTS.md` | `mkdir -p ~/.codex && grep -q 'os-done-or-not' ~/.codex/AGENTS.md 2>/dev/null \|\| cat open-steps/docs/routing-block.md >> ~/.codex/AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | `mkdir -p ~/.gemini && grep -q 'os-done-or-not' ~/.gemini/GEMINI.md 2>/dev/null \|\| cat open-steps/docs/routing-block.md >> ~/.gemini/GEMINI.md` |
| Cursor | `AGENTS.md` in the project root | `grep -q 'os-done-or-not' AGENTS.md 2>/dev/null \|\| cat open-steps/docs/routing-block.md >> AGENTS.md` |

Cursor's is per project because Cursor has no global `AGENTS.md`. Per its
documentation it reads `AGENTS.md` in the project root and in subdirectories,
and keeps cross-project preferences in User Rules, which is a settings screen
rather than a file this command can append to.

## The hooks

Here the tools stop agreeing. Both hooks are plain shell reading JSON on
standard input, so the interesting question is what each tool does with what
they return.

| Tool | Session start | Stop |
|---|---|---|
| Claude Code | works, wired by the plugin | works, wired by the plugin |
| Codex | works, script unchanged | works, script unchanged |
| Cursor | needs a JSON wrapper | cannot block a stop at all |
| Gemini CLI | needs a JSON wrapper | needs one too, on `AfterAgent` |

### Codex

Codex takes a `session_start` command hook's plain stdout as additional
context, and treats exit code 2 from a `stop` hook as "blocked", with stderr as
the reason. That is the same contract Claude Code uses, so both scripts run
unmodified. Only the wiring changes: Codex configures hooks in TOML, and there
is no `${CLAUDE_PLUGIN_ROOT}` outside a plugin, so the paths are absolute.

Add to `~/.codex/config.toml`, replacing the path with your clone:

```toml
[[hooks.session_start]]
[[hooks.session_start.hooks]]
type = "command"
command = "/absolute/path/to/open-steps/hooks/session-start.sh"
timeout_sec = 10

[[hooks.stop]]
[[hooks.stop.hooks]]
type = "command"
command = "/absolute/path/to/open-steps/hooks/stop-report.sh"
timeout_sec = 10
```

`codex doctor` reports `config.toml parse ok` when the shape is right.

Then trust them, and this part is not optional. Codex reviews newly added hooks
at startup and offers to trust them or to continue without trusting. A hook
that is not trusted still runs, but loses its control effects, which is exactly
the half that matters here: the stop hook's exit code 2 stops blocking and the
report is never asked for, quietly. If reports never appear, this is the first
thing to check.

The same environment variables apply, because they are read by the scripts
rather than by any tool: `OPEN_STEPS_COOLDOWN`, `OPEN_STEPS_MIN_FILES`,
`OPEN_STEPS_MAX_REPOS`, `OPEN_STEPS_DISABLE`, `OPEN_STEPS_MAX_REPORT_LINES`,
`OPEN_STEPS_NO_SESSION_START`.

### Cursor

Everything in this section is from Cursor's documentation. None of it was run.

Cursor has the two events, `sessionStart` and `stop`, in
`~/.cursor/hooks.json` or `<project>/.cursor/hooks.json`, shaped
`{"version": 1, "hooks": {"sessionStart": [{"command": "..."}]}}`. They read
JSON on stdin and must write JSON on stdout, where invalid JSON counts as a
hook failure. So `session-start.sh` needs its handover wrapped as
`{"additional_context": "..."}` rather than printed. Small adapter, not written
yet.

The stop side is a difference in kind rather than a wrapper. A `stop` hook
cannot block. Its one documented output is `followup_message`, which Cursor
submits as the next user message and then carries on, bounded by `loop_limit`.
A Claude-style `{"decision": "block"}` is accepted but downgraded to exactly
that. Exit code 2 does block, but only on the gate hooks, `preToolUse` and
`beforeShellExecution` and their siblings, never on `stop`. A port would ask
for the report through `followup_message` and would have to be tested on its
own terms.

One thing to check first if nothing loads at all: `~/.agents/skills/` is read
directly, but the compatibility paths `~/.claude/skills/` and
`~/.codex/skills/` sit behind Cursor's "Include third-party Plugins, Skills,
and other configs" setting.

### Gemini CLI

Everything in this section is from Gemini CLI's documentation. None of it was
run.

Hooks live in `settings.json`, user-level `~/.gemini/settings.json` or
project-level `.gemini/settings.json`, under a `hooks` object keyed by event
name. They read JSON on stdin and must write JSON on stdout, and the
documentation is blunt about it: a script must not print plain text to stdout
other than the final JSON. So the same wrapper Cursor needs applies here with a
different field name. `SessionStart` injects through
`hookSpecificOutput.additionalContext`.

The stop side needs the right event, and it is not the obvious one. `SessionEnd`
fires when the CLI exits, is best effort, is not waited for, and has all its
flow-control fields ignored, so a report can never be asked for from there.
`AfterAgent` is the one that matches: it fires once per turn after the model's
final response, and it does take `decision: "deny"` with a `reason`, where the
reason is sent to the agent as a new prompt asking for a correction. That is
the same shape as this pack's exit code 2 with the request on stderr.

So both hooks can be ported here too. Neither is ported yet.

### What those two lose

Until someone does that work, both tools get the skills and the routing block,
which is the part that changes what the agent says to you. What they lose is
the report at the end of a session, and the previous report in front of the
next one.

## What was actually run

On Codex CLI 0.145, in a throwaway home directory:

```bash
codex debug prompt-input | grep -o 'os-[a-z-]*' | sort -u
```

lists all six skill names, reaching the model with their descriptions intact.
This is also where the symlink naming difference above turned up.

Both hooks were then fed a Codex-shaped payload directly:

```bash
payload='{"session_id":"s1","cwd":"'"$PWD"'","model":"gpt-5","permission_mode":"default"}'
printf '%s' "$payload" | hooks/session-start.sh    # prints the handover, exits 0
printf '%s' "$payload" | hooks/stop-report.sh      # exits 2, report request on stderr
```

The second one needs an uncommitted change in the repository to have anything
to report. `hooks/test.sh` covers this shape as CASE 9, so it stays covered.

Not run: hooks firing inside a live Codex session, which needs a real turn
rather than a rendered prompt. The trust step above is read from how Codex
implements hooks, not from watching it happen. Not run at all: anything on
Cursor or Gemini CLI. Their paths and contracts here come from their own
documentation.

## What does not come across

- **Activation is measured on Claude models only.** The figures in the README
  say nothing about how reliably these skills switch on inside another tool.
  No figure is quoted for those because none was measured.
- **`allowed-tools:` is Claude Code's field.** Other tools ignore it and ask
  for permission the way they normally do. Safer, just chattier.
- **Reports still land in `~/.claude/open-steps/reports/<project>/`.** The name
  says Claude; it is only a path, and one folder means every tool reads the
  same history.
