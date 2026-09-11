# Running the pack on Codex, Cursor and Gemini CLI

Claude Code is what the pack is built and measured on. Everything here is the
second-best case: the skills carry over cleanly, the routing block carries over
cleanly, the hooks carry over on all three, unchanged on Codex and through
one adapter on Cursor and Gemini CLI.

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
subagent, and both are Claude Code behaviours. On these tools the `!` line
arrives as literal text, and the skill then says to read
`references/premortem-prompt.md` directly; whether the tool can dispatch a
fresh agent varies. None of this is verified here - expect this one skill to
run shallower than the other six.

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
| Cursor | works, through the adapter | asks, cannot insist: a follow-up message, through the adapter; interactive sessions only, headless never reaches it |
| Gemini CLI | works, through the adapter | works, through the adapter, on `AfterAgent`, where a stop can refuse |

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

Run on Cursor CLI, on Windows, in an interactive session; the details are
under "What was actually run". The desktop app and the other platforms are
read from Cursor's documentation, and headless runs of the CLI never reach
the stop hook, as below.

Cursor has the two events, `sessionStart` and `stop`, and reads JSON on stdin
like the others, but it answers only to JSON on stdout: plain text counts as a
hook failure. And its `stop` cannot block. The one thing a `stop` hook can do
is return a `followup_message`, which Cursor submits as the next user message
and carries on, at most `loop_limit` times per conversation (5 unless
configured). A Claude-style `{"decision": "block"}` is accepted and downgraded
to exactly that; exit code 2 blocks only the gate hooks, `preToolUse`,
`beforeShellExecution` and their siblings, never `stop`.

So the two scripts run here through `hooks/adapter.sh`, which runs them
unchanged and translates only what goes in and what comes out. There is one
copy of the hook logic, and the settings and kill switches above apply
because the scripts read them, not the adapter.

```text
hooks/adapter.sh cursor session-start   the handover, as {"additional_context": "..."}
hooks/adapter.sh cursor stop            the report request, as {"followup_message": "..."}
```

Three things it does beyond wrapping, each one a difference in Cursor's
contract rather than a choice:

- **Both events are keyed on `conversation_id`.** Cursor's `sessionStart`
  payload carries a `session_id`, its `stop` payload does not, and the
  baseline the start hook takes is keyed by session. A stop still reading
  `session_id` would fall back to the constant, fail to match the baseline,
  and silently take a new one instead of asking. `conversation_id` is on both.
- **Only a completed stop is asked for a report.** The `stop` payload says
  whether the turn `completed`, was `aborted` or hit an `error`. After an
  abort or an error the adapter answers `{}` without running the stop script,
  so the change stays pending for the next completed stop in the same
  conversation, and nobody gets a message submitted on their behalf right
  after pressing stop. A new chat is a new session start, which takes a
  fresh baseline over the tree as it stands; that is how the hooks behave
  everywhere, not something the adapter adds.
- **The working directory is `CURSOR_PROJECT_DIR`** when Cursor sets it, which
  it does on every hook. The scripts find the repository from there.

Wire it in `~/.cursor/hooks.json` (or `<project>/.cursor/hooks.json`),
replacing the path with your clone:

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      { "command": "/absolute/path/to/open-steps/hooks/adapter.sh cursor session-start", "timeout": 10 }
    ],
    "stop": [
      { "command": "/absolute/path/to/open-steps/hooks/adapter.sh cursor stop", "timeout": 10 }
    ]
  }
}
```

On Windows, put the shell in front, quoted:
`"\"C:/Program Files/Git/bin/bash.exe\" D:/path/to/open-steps/hooks/adapter.sh cursor stop"`,
and start Cursor from PowerShell or cmd. From a Git Bash shell the CLI reads
the bash-flavoured environment, runs its own PowerShell hook wrapper inside
bash, and every hook fails with exit code 2 before the adapter is reached.
The CLI writes a session log under the temp directory, in
`cursor-agent-logs-<user>/`, with one `cli.hook.executed` line per hook
carrying the exit code; that is where to look first if nothing seems to
happen. The desktop app has a Hooks output channel and a Hooks page under
Customize for the same purpose, per its documentation.

**What happens when the agent ignores the follow-up.** On Claude Code and
Codex the report is required: the stop is refused until it exists. Here it is
asked for. Cursor submits the request as the next message and the agent
normally writes the report, which lands outside the repository and so leaves
the fingerprint alone; the next stop is silent. If the agent stops again
without writing it, nothing forces the matter. The stop script records the
fingerprint when it asks, so the same change is never asked about twice: the
hook stays silent until new work lands, and the cooldown
(`OPEN_STEPS_COOLDOWN`, 15 minutes by default) applies from the last ask.
The adapter asks once per landed change and does not raise `loop_limit`;
Cursor's default of 5 stays as the outer ceiling. Should a conversation ever
reach it, Cursor drops the follow-up and the report is simply not written.
Either way the next session's handover carries whatever `latest.md` holds,
which may be an older report, with nothing to say a newer one was skipped.
That is the honest shape of a stop that cannot block, and it is what the row
in the table above means by "asks, cannot insist".

One thing to check first if nothing loads at all: `~/.agents/skills/` is read
directly, but the compatibility paths `~/.claude/skills/` and
`~/.codex/skills/` sit behind Cursor's "Include third-party Plugins, Skills,
and other configs" setting.

### Gemini CLI

Run on Gemini CLI 0.58.0 on Windows 11, interactive and headless; what was
watched is under "What was actually run" below. The rest of this section is
its documentation and its source, and says so where it matters.

Hooks live in `settings.json`, user-level `~/.gemini/settings.json` or
project-level `.gemini/settings.json`, under a `hooks` object keyed by event
name, on by default (`hooksConfig.enabled`). They read JSON on stdin and answer
with JSON on stdout. `SessionStart` takes `hookSpecificOutput.additionalContext`,
which the CLI adds to the conversation as a first turn.

The stop side needs the right event, and it is not the obvious one. `SessionEnd`
fires when the CLI exits, is best effort, is not waited for, and has all its
flow-control fields ignored, so a report can never be asked for from there.
`AfterAgent` is the one that matches: it fires after the model's final response
of each turn, and it takes `decision: "deny"` with a `reason`, which goes back
to the agent as the next prompt, with `stop_hook_active` set on that retry.
That is the shape of this pack's exit code 2 with the request on stderr, so on
Gemini CLI the stop keeps its refusal, unlike on Cursor.

`hooks/adapter.sh` does the translation, the same script Cursor uses:

```bash
hooks/adapter.sh gemini session-start    # {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":...}}
hooks/adapter.sh gemini stop             # {"decision":"deny","reason":...} when work landed, {} otherwise
```

Every Gemini payload carries `session_id`, and every hook gets
`GEMINI_SESSION_ID` in its environment; the adapter reads the payload and
falls back to the variable, so both events key the same baseline. The
working directory follows `GEMINI_PROJECT_DIR`, which the CLI sets on every
hook, then the payload's `cwd`. Wired in `~/.gemini/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "name": "open-steps-session-start",
      "command": "bash /path/to/open-steps/hooks/adapter.sh gemini session-start" }] }],
    "AfterAgent": [{ "hooks": [{ "type": "command", "name": "open-steps-stop-report",
      "command": "bash /path/to/open-steps/hooks/adapter.sh gemini stop" }] }]
  }
}
```

No `timeout` is set, so the CLI's default of 60 seconds applies (read in its
source; the field takes milliseconds). Leave it generous rather than tight:
the stop took under two seconds in a one-repository folder and up to eight in
a hub of 25 checkouts on the Windows machine this was run on, and
`stop-report.sh` records the request before the adapter can answer, so a hook
killed in between has marked a change as asked for that nobody heard. The run
itself used `"timeout": 10000`, which was enough for the throwaway repository.
On Windows the CLI runs every hook command through PowerShell, whatever shell
you sit in, so the command becomes
`$input | & 'C:\Program Files\Git\bin\bash.exe' 'D:/path/to/open-steps/hooks/adapter.sh' gemini stop`,
and the `$input |` matters: without it the payload never reaches bash. That
is the form that was run; the Unix form above is the same command without the
PowerShell wrapping and was not.

What happens after the refusal. The retry has the request as its prompt and
its `AfterAgent` arrives with `stop_hook_active` true; the adapter answers
`{}` to that one without running the stop script, whatever landed in it,
since denying the retry is the one way to loop. The report the retry writes
lives outside the repository, so the fingerprint is unchanged for the turns
after it too. The CLI has no cap of its own on denies beyond its turn budget
(read in its source, not tested to the limit); the stop script's own state is
what keeps it to one request per landed change, the same as everywhere else.

The one thing to know before wiring it: the reports folder,
`~/.claude/open-steps/reports/`, is outside Gemini's workspace, and Gemini's
file tools refuse to write outside the workspace directories while its shell
tool does not. Which one the agent reaches for is the model's choice. In the
interactive session it used the shell and the report landed. In the headless
one it used `write_file`, was refused, and took the refusal's own suggestion:
it wrote the report to Gemini's temp folder for the project,
`~/.gemini/tmp/<project>/latest.md`, where the next session's handover never
looks. So the gemini stop adds one sentence to the request, to save the
report with the shell tool and why; it went in after that run and was not
itself watched. Adding the reports folder as a workspace directory,
`--include-directories ~/.claude/open-steps/reports` or `/directory add` in a
session, should make `write_file` work as well; that flag is from Gemini's
documentation and was not run.

Also read in the source, not relied on: Gemini CLI 0.58 accepts plain text from
a hook too, exit 0 as a message shown to you and exit 2 as a refusal with the
text as the reason. So `stop-report.sh` unchanged would refuse on `AfterAgent`
as well. `session-start.sh` unchanged would not do what is wanted: its handover
would be shown to you, not handed to the model. The adapter is the wiring
that was run, on both events.

### What Gemini CLI loses

With the adapter wired, two things, both from how the CLI handles a session
and both read in its source rather than watched:

- `/clear` (also `/new`) starts a new session id and fires `SessionStart`
  again with `source: "clear"`. The baseline is retaken under the new id, so
  a change that was waiting out the cooldown is absorbed and never asked
  about. On Claude Code the id survives a clear and the pending report does
  not get lost.
- `AfterAgent` fires after a turn you cancelled too, and its payload has no
  status field to tell one from a finished turn. The request goes out, the
  retry does not run, and the stop script has already recorded the change as
  asked for; it comes up again only once something else lands after it.

Not checked: how reliably the skills fire from the routing block, since the
only skill watched firing was `os-done-or-not`, invoked from the stop's
request.

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
implements hooks, not from watching it happen.

On Cursor CLI 2026.09.02 on Windows 11, with the skills copied to
`~/.agents/skills/` and the adapter wired in `~/.cursor/hooks.json` as above,
an interactive session was started in a throwaway repository and asked to
append one line to a file. Cursor's own session log records the sequence:

```text
cli.hook.executed  hookStep=sessionStart  status=success  exitCode=0
[hooks] sessionStart additional_context received {"length":1971}
cli.hook.executed  hookStep=stop          status=success  exitCode=0
[hooks] Stop hook returned followup_message, queueing (loop 1)
cli.hook.executed  hookStep=stop          status=success  exitCode=0
```

The first stop, after the edit, came back with the report request and Cursor
submitted it as the next message in the transcript. The agent invoked
`os-done-or-not` and wrote `latest.md` under the reports folder. The second
stop, after the report, returned `{}` and the session ended: one request,
no loop. The handover that session received already carried the report of an
earlier run, 1971 characters against 854 for the bare routing table.

Two things came out of running it rather than reading about it. Print mode
(`agent -p`) and a prompt piped through stdin both count as headless, and
headless fires `sessionStart` only: the handover arrives, the stop hook is
never dispatched, so no report is asked for. And the Windows shell trap
above, which cost a first attempt.

Not run: the Cursor desktop app, project-level `.cursor/hooks.json`, and
Cursor on macOS or Linux. The contract is the same per Cursor's documentation,
but none of that was watched.

On Gemini CLI 0.58.0 on Windows 11, signed in with a Gemini API key, skills in
`~/.agents/skills/`, the routing block in `~/.gemini/GEMINI.md`, and the
adapter wired in `~/.gemini/settings.json` in the PowerShell form above, an
interactive session was started in a throwaway repository with
`--approval-mode yolo` and asked to append one line to a file. What the screen
showed, in order: `Executing Hook: open-steps-session-start` at startup; the
edit; `Executing Hook: open-steps-stop-report`; then

```text
⚠ Agent execution blocked: Work landed during this session (changed: os-gemini-live).
  Before finishing, use the os-done-or-not skill to produce the session report: ...
ℹ This request failed. Press F12 for diagnostics, ...
```

where the second line is how the CLI renders a blocked turn, since the retry
then ran. The retry activated `os-done-or-not`, wrote `latest.md` under the
reports folder through the shell tool, and the following `AfterAgent`
answered `{}`: the state file's fired-at stamp stayed at the first request and
`/quit` exited 0. One refusal, no loop. The handover a next session gets from
that repository then carries the report, 2180 characters against 1075 for
the bare routing block.

A first attempt in `auto_edit` mode went the same way up to the retry, which
then sat on a permission prompt to activate the skill; a person at the
keyboard answers it, the driver did not, so the report was never written. In
`yolo` it was. Headless (`gemini -p`, with `--yolo --skip-trust`) was run
too: `SessionStart` fired and took a baseline under a fresh session id,
`AfterAgent` fired and refused, the retry ran, `write_file` was refused for
the reports folder, and the agent wrote the report to
`~/.gemini/tmp/os-gemini-live/latest.md` instead, the project temp folder the
refusal named as allowed; a next session's handover from that repository does
not carry it. That is what the sentence about the shell tool in the request
is for. So unlike Cursor, headless reaches the stop hook here. One more thing
from running it: the
free tier's daily quota on the default model ran out after two interactive
sessions, and the headless run used a lighter model.

Not run: Gemini CLI on macOS or Linux, the project-level settings file,
`--include-directories`, and Google sign-in, which Google was refusing for
individual accounts on this version at the time.

## What does not come across

- **Activation is measured on Claude models only.** The figures in the README
  say nothing about how reliably these skills switch on inside another tool.
  No figure is quoted for those because none was measured.
- **`allowed-tools:` is Claude Code's field.** Other tools ignore it and ask
  for permission the way they normally do. Safer, just chattier.
- **Reports still land in `~/.claude/open-steps/reports/<project>/`.** The name
  says Claude; it is only a path, and one folder means every tool reads the
  same history.
