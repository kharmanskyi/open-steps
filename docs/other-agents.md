# Open Steps on Codex CLI, Cursor CLI and Gemini CLI

This guide sets up Open Steps on Codex CLI, Cursor CLI and Gemini CLI. The
skills, the routing block and the two hooks are the same on every tool; only
the wiring differs. Setup has four parts:

1. Copy the skills into one shared folder. One command covers all three tools.
2. Add the routing block to each tool's instructions file.
3. Wire the two hooks in each tool's settings. On Codex CLI the hook scripts
   are wired as they are. On Cursor CLI and Gemini CLI they run through one
   adapter, `hooks/adapter.sh`.
4. Check the install with `doctor.sh`.

What was run on each tool is summed up in the README, in
[What was run on each tool](../README.md#what-was-run-on-each-tool). The runs
themselves are described under [What was actually run](#what-was-actually-run).
Where a step comes from a tool's documentation and was not run, this page says
so next to the step.

On this page, Codex means Codex CLI and Cursor means Cursor CLI. The Cursor
desktop app is named when it is meant.

## Before you start

Clone the repository, as in
[First, for any tool](../README.md#first-for-any-tool). Unless a step says
otherwise, every command below runs from the folder that holds the clone, the
one that contains `open-steps/`, not from inside the clone.

## The skills

A skill is a folder with a `SKILL.md` in it, and that format is shared across
tools. Codex, Cursor and Gemini CLI all read one folder, `~/.agents/skills/`,
so one command installs the skills for all three:

```bash
mkdir -p ~/.agents/skills && cp -R open-steps/skills/os-* ~/.agents/skills/
```

The command copies the files. To update, run `git pull` inside `open-steps/`,
then run the copy command again.

A link instead of a copy updates itself, but on Codex it renames the skills.
Codex follows the link back to the clone and takes the name from the folder it
lands in. So `ln -sfn "$PWD"/open-steps/skills/os-* ~/.agents/skills/` gives
`open-steps:os-done-or-not`, where a copy gives `os-done-or-not`. The routing
block uses the short names, so copy unless you have a reason not to.

Each tool also has a folder of its own, in case the shared one is ever a
problem: `~/.codex/skills/`, `~/.cursor/skills/` and `~/.gemini/skills/`.
Cursor also reads `~/.claude/skills/` and `~/.codex/skills/`, behind a setting
named under [Cursor CLI](#cursor-cli). These per-tool paths come from each
tool's documentation. The shared folder is the one that was run.

One skill leans on two Claude Code features: a `!` line that loads its
prompt, and a fresh agent that runs the review. The skill is
`os-what-could-go-wrong`. When the `!` line does not run, the skill reads the
same prompt from `references/premortem-prompt.md`, and on Codex CLI 0.151
that is what happened. In the same four runs no fresh agent started. The agent
ran the review itself, so that review was not independent. The skill has
changed since those runs, and they have not been re-run. On Codex CLI 0.157.1
this is not measured, and on Cursor and Gemini CLI it was not tried.

## The routing block

The block in [`routing-block.md`](routing-block.md) is meant to do the same
job on every tool: turn the moments it names into a rule rather than a hint.
Each of these tools lets the model decide whether to use a skill, so the block
is worth adding. It was in place during the measured runs on Codex CLI 0.157.1
and during the Gemini CLI run. No run without it was made, so its own effect
is not measured.

One command per tool. Each is safe to re-run:

| Tool | File | Command |
|---|---|---|
| Codex CLI | `~/.codex/AGENTS.md` | `mkdir -p ~/.codex && grep -q 'os-done-or-not' ~/.codex/AGENTS.md 2>/dev/null \|\| cat open-steps/docs/routing-block.md >> ~/.codex/AGENTS.md` |
| Cursor CLI | `AGENTS.md` in the project root | `grep -q 'os-done-or-not' AGENTS.md 2>/dev/null \|\| cat open-steps/docs/routing-block.md >> AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | `mkdir -p ~/.gemini && grep -q 'os-done-or-not' ~/.gemini/GEMINI.md 2>/dev/null \|\| cat open-steps/docs/routing-block.md >> ~/.gemini/GEMINI.md` |

Cursor's file is per project, because Cursor has no global `AGENTS.md`. Run
its command in the project root, with the path to your clone in place of
`open-steps/`. Per Cursor's documentation, it reads `AGENTS.md` in the project
root and in subdirectories. It keeps preferences for all projects in User
Rules, which is a settings screen, not a file a command can add to.

## The hooks

Both hooks are plain shell scripts. They read JSON on standard input. The
tools differ in what they do with the answer:

| Tool | Session start | Stop | Wired in |
|---|---|---|---|
| Claude Code | hands the handover to the model | refuses until the report exists | the plugin |
| Codex CLI | hands the handover to the model, per Codex's documentation | refuses with exit code 2 once the hooks are trusted, per Codex's documentation | `~/.codex/config.toml`, scripts unchanged |
| Cursor CLI | hands the handover to the model, through the adapter | asks with a follow-up message, cannot require the report | `~/.cursor/hooks.json`, through the adapter |
| Gemini CLI | hands the handover to the model, through the adapter | refuses on `AfterAgent`, through the adapter | `~/.gemini/settings.json`, through the adapter |

Whether each cell was watched, checked by hand or read in the documentation is
in the README table,
[What was run on each tool](../README.md#what-was-run-on-each-tool).

The settings are the same on every tool, because the scripts read them, not
the tool: `OPEN_STEPS_COOLDOWN`, `OPEN_STEPS_MIN_FILES`,
`OPEN_STEPS_MAX_REPOS`, `OPEN_STEPS_DISABLE`, `OPEN_STEPS_MAX_REPORT_LINES`
and `OPEN_STEPS_NO_SESSION_START`. The README lists what each one does.

### Codex CLI

#### Wiring

Per Codex's hook documentation, Codex takes the plain output of a
`session_start` command hook as added context. It treats exit code 2 from a
`stop` hook as "blocked", with the error output as the reason. That is the
same contract Claude Code uses, so per that documentation both scripts should
run unchanged. Only the wiring differs. Codex sets hooks in TOML, and there is
no `${CLAUDE_PLUGIN_ROOT}` outside a plugin, so the paths are full paths.

Add this to `~/.codex/config.toml`, with the path to your clone:

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

Then trust the hooks. Per Codex's hook documentation, Codex shows newly added
hooks at startup and offers to trust them or to go on without trusting them.
After that, run the pack's own check, as in
[Check the install](#check-the-install).

#### Limits

- **A hook you do not trust loses its control.** Per Codex's documentation, it
  still runs, but its exit code 2 no longer blocks. The stop then stays quiet
  and no report is asked for.
- **The premortem started no fresh agent on Codex CLI 0.151,** as
  [The skills](#the-skills) says.

#### If nothing happens

- If reports never appear, check the trust step first. `doctor.sh` cannot see
  whether you trusted the hooks.
- If Codex seems to ignore the hooks, run `codex doctor` to check the TOML.

### Cursor CLI

#### Wiring

Cursor has the two events, `sessionStart` and `stop`. It reads JSON on
standard input like the others, but it accepts only JSON on standard output.
Plain text counts as a hook failure. Its `stop` cannot block. The one thing a
`stop` hook can do is return a `followup_message`. Cursor sends it as the next
user message and carries on, at most `loop_limit` times per conversation (5
unless you set it). A `{"decision": "block"}` in the Claude Code style is
accepted and turned into that same follow-up. Exit code 2 blocks only the gate
hooks, such as `preToolUse` and `beforeShellExecution`, and never `stop`.

So on Cursor the two scripts run through `hooks/adapter.sh`. The adapter runs
them unchanged and translates only what goes in and what comes out. The hook
logic lives in one place, and the settings above still apply.

```text
hooks/adapter.sh cursor session-start   the handover, as {"additional_context": "..."}
hooks/adapter.sh cursor stop            the report request, as {"followup_message": "..."}
```

The adapter does three more things. Each one follows from how Cursor works:

- **Both events are matched by `conversation_id`.** Cursor's `sessionStart`
  payload has a `session_id`, but its `stop` payload does not. The start hook
  stores its snapshot of the repository under that id. A stop that read
  `session_id` would miss the snapshot and quietly take a new one instead of
  asking. `conversation_id` is on both events.
- **Only a completed turn is asked for a report.** The `stop` payload says
  whether the turn `completed`, was `aborted` or hit an `error`. After an
  abort or an error, the adapter answers `{}` and does not run the stop
  script. The change waits for the next completed turn in the same
  conversation. Nobody gets a message sent in their name right after pressing
  stop. A new chat is a new session start and takes a fresh snapshot, the
  same as on every tool.
- **The working folder is `CURSOR_PROJECT_DIR`** when Cursor sets it, which it
  does on every hook. The scripts find the repository from there.

Wire it in `~/.cursor/hooks.json`, or in `<project>/.cursor/hooks.json`, with
the path to your clone:

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

On Windows, put the shell in front, in quotes:
`"\"C:/Program Files/Git/bin/bash.exe\" D:/path/to/open-steps/hooks/adapter.sh cursor stop"`.
Start Cursor from PowerShell or cmd, not from Git Bash.

#### Limits

- **The stop asks and cannot require.** If the agent ignores the follow-up,
  the report is not written. The stop script records the change when it asks,
  so the same change is never asked about twice. The hook stays quiet until
  new work lands, and the cooldown (`OPEN_STEPS_COOLDOWN`, 15 minutes by
  default) counts from the last ask. The adapter does not raise `loop_limit`.
  If a conversation ever reaches it, Cursor drops the follow-up. Either way,
  the next session's handover shows the last report that was written, with
  nothing to say a newer one was skipped.
- **A headless run asks for no report.** In the headless runs tried, the stop
  hook never ran. See [Runs on Cursor CLI](#runs-on-cursor-cli).

#### If nothing happens

- **Read the session log first.** The CLI writes one under the temp folder, in
  `cursor-agent-logs-<user>/`. It has one `cli.hook.executed` line per hook,
  with the exit code. Per its documentation, the desktop app has a Hooks
  output channel and a Hooks page under Customize for the same purpose.
- **On Windows, check where you started Cursor.** Started from a Git Bash
  shell, the CLI runs its own PowerShell hook wrapper inside bash. Every hook
  then fails with exit code 2 before the adapter is reached.
- **If no skill loads at all,** check the setting "Include third-party
  Plugins, Skills, and other configs". Cursor reads `~/.agents/skills/`
  directly, but the paths `~/.claude/skills/` and `~/.codex/skills/` sit
  behind that setting.

### Gemini CLI

#### Wiring

Hooks live in `settings.json`: `~/.gemini/settings.json` for your user, or
`.gemini/settings.json` in a project. They go under a `hooks` object, keyed by
event name, and they are on by default (`hooksConfig.enabled`). They read JSON
on standard input and answer with JSON on standard output. `SessionStart`
takes `hookSpecificOutput.additionalContext`, which the CLI adds to the
conversation as a first turn.

The stop needs the right event, and it is not the obvious one. `SessionEnd`
fires when the CLI exits. It is best effort, the CLI does not wait for it, and
it ignores every field that could hold the session back. So a report can never
be asked for from there. `AfterAgent` is the one that fits. It fires after the
model's final answer in each turn. It takes `decision: "deny"` with a
`reason`, which goes back to the agent as the next prompt, with
`stop_hook_active` set on that retry. That matches the pack's exit code 2 with
the request as the reason, so on Gemini CLI the stop can refuse.

`hooks/adapter.sh` does the translation, the same script Cursor uses:

```bash
hooks/adapter.sh gemini session-start    # {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":...}}
hooks/adapter.sh gemini stop             # {"decision":"deny","reason":...} when work landed, {} otherwise
```

Every Gemini payload has a `session_id`, and every hook gets
`GEMINI_SESSION_ID` in its environment. The adapter reads the payload and
falls back to the variable, so both events match the same snapshot. The
working folder is `GEMINI_PROJECT_DIR`, which the CLI sets on every hook, and
then the payload's `cwd`. Wire it in `~/.gemini/settings.json`:

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
source; the field takes milliseconds). The run itself used
`"timeout": 10000`, which was enough for the throwaway repository. Keep it
generous. On the Windows machine it was run on, the stop took under two
seconds in a folder with one repository and up to eight in a folder of 25. `stop-report.sh` records the
request before the adapter answers, so a hook stopped in between marks a
change as asked about that nobody heard.

On Windows the CLI runs every hook command through PowerShell, whatever shell
you use. So the command becomes
`$input | & 'C:\Program Files\Git\bin\bash.exe' 'D:/path/to/open-steps/hooks/adapter.sh' gemini stop`.
The `$input |` matters: without it the payload never reaches bash. That is the
form that was run. The Unix form above is the same command without the
PowerShell part, and it was not run.

Read in the source and not relied on: Gemini CLI 0.58 also accepts plain text
from a hook, exit 0 as a message shown to you and exit 2 as a refusal with the
text as the reason. So `stop-report.sh` alone would refuse on `AfterAgent`
too. `session-start.sh` alone would not do the job: its handover would be
shown to you, not given to the model. The adapter is the wiring that was run,
on both events.

#### Limits

- **After a refusal, the retry is let through.** The retry has the request as
  its prompt, and its `AfterAgent` arrives with `stop_hook_active` set. The
  adapter answers `{}` to it without running the stop script, because denying
  the retry is the one way to loop. The report the retry writes lives outside
  the repository, so it changes nothing the hook looks at. The CLI has no cap
  of its own on refusals beyond its turn budget (read in its source, not
  tested to the limit). The stop script keeps it to one request per change,
  the same as on every tool.
- **The report has to be saved with the shell tool.** The reports folder,
  `~/.claude/open-steps/reports/`, is outside Gemini's workspace. Gemini's
  file tools refuse to write outside the workspace, and its shell tool does
  not. So the request on Gemini CLI adds one sentence: save the report with
  the shell tool, and why. That sentence went in after the runs and was not
  itself watched.
- **`/clear` can lose a pending report** (read in its source, not watched).
  `/clear`, and `/new`, starts a new session id and fires `SessionStart` again
  with `source: "clear"`. The snapshot is taken again under the new id, so a
  change that was waiting out the cooldown is never asked about. On Claude
  Code the id survives a clear.
- **A cancelled turn counts as a finished one** (read in its source, not
  watched). `AfterAgent` fires after a turn you cancelled too, and its payload
  cannot tell the two apart. The request goes out, the retry does not run, and
  the change is already recorded as asked about. It comes up again only when
  something else lands.

#### If nothing happens

- **If the report is missing,** look in `~/.gemini/tmp/<project>/latest.md`.
  The headless run tried saved it there, where the next session's handover
  does not look. Adding the reports folder to the workspace, with
  `--include-directories ~/.claude/open-steps/reports` or `/directory add` in
  a session, should let the file tool write there too. That comes from
  Gemini's documentation and was not run.
- **On Windows, check the `$input |` in front of the command.** Without it,
  the hook gets no payload.

## Check the install

From the folder that holds the clone, run:

```bash
bash open-steps/doctor.sh
```

It reads files and changes nothing. Each line is marked `ok`, `FAULT`,
`not checked` or `fact`. A `fact` is something it looked at and does not judge.

- **The skills:** it checks every copy it finds in `~/.agents/skills/` and in
  each tool's own folder.
- **Codex CLI:** once it can tell the install is for Codex, it checks the
  routing block in `~/.codex/AGENTS.md`. It checks that `~/.codex/config.toml`
  sets up both hooks and that each one points at a real file. A shared copy
  that could be for another tool, with no Codex file that mentions the pack,
  is reported as a fact. The `doctor.sh` header has the exact rule. It cannot
  see whether you trusted the hooks.
- **Cursor CLI and Gemini CLI:** it reports the routing block in `GEMINI.md`
  and the hook commands it finds, without judging them. It checks one thing:
  the path in front of `adapter.sh` is a real file and not the example path.
  It does not check Cursor's `AGENTS.md`, since that one sits in each project.

To update or remove the pack, see
[Codex CLI, Cursor CLI and Gemini CLI](../README.md#codex-cli-cursor-cli-and-gemini-cli)
in the README.

## What was actually run

This part is the record behind the README table. The Cursor CLI and Gemini CLI
runs are one contributor's, on Windows 11, and the maintainer has not
reproduced them. The Codex CLI listing, premortem runs and activation runs
were contributors' runs too.

### Runs on Codex CLI

On Codex CLI 0.145, on 2026-08-25, in a throwaway home folder, this command
listed every skill the pack had then, with its description intact:

```bash
codex debug prompt-input | grep -o 'os-[a-z-]*' | sort -u
```

That is also where the naming difference for linked skills turned up. The
listing has not been re-run since.

Both hooks were then given a Codex-shaped payload by hand:

```bash
payload='{"session_id":"s1","cwd":"'"$PWD"'","model":"gpt-5","permission_mode":"default"}'
printf '%s' "$payload" | hooks/session-start.sh    # prints the handover, exits 0
printf '%s' "$payload" | hooks/stop-report.sh      # exits 2, report request on stderr
```

The second one needs a change in the repository that is not committed yet, or
it has nothing to report. `hooks/test.sh` covers this shape as CASE 9, so it
stays covered.

On Codex CLI 0.151.0 on Linux, `os-what-could-go-wrong` was run four times
with a real decision brief. The `!` line arrived as plain text, and Codex read
`references/premortem-prompt.md` instead. No fresh agent started. All four
runs still called the review independent. One wrote the whole report twice,
and one skipped a step the others took. A nested `codex exec` failed to start
inside the sandbox, and that session reported the failure and called the
review independent in the same sentence. With approvals and the sandbox turned
off, the nested session started in about three minutes. It was handed the
brief and an instruction to run the skill, so it ran the skill again, and the
report appeared four times in one transcript.

On Codex CLI 0.157.1, on 2026-09-28, a contributor measured whether the right
skill switches on by itself, and the maintainer scored the transcripts. The
agent read every skill of the pack when asked a matching question. The
numbers and what they mean are in the README,
[On Codex CLI](../README.md#on-codex-cli). In those runs the agent waited on
work it had handed off, but no transcript shows a fresh agent starting, and 5
of the 9 transcripts were cut off.

Not watched on Codex: the hooks firing inside a live session. The runs of
2026-09-28 were real turns, but they recorded which skills were read, not the
hooks. The trust step comes from Codex's documentation.

### Runs on Cursor CLI

On Cursor CLI 2026.09.02 on Windows 11, the skills were copied to
`~/.agents/skills/` and the adapter was wired in `~/.cursor/hooks.json` as
above. An interactive session was started in a throwaway repository and asked
to add one line to a file. Cursor's own session log recorded this:

```text
cli.hook.executed  hookStep=sessionStart  status=success  exitCode=0
[hooks] sessionStart additional_context received {"length":1971}
cli.hook.executed  hookStep=stop          status=success  exitCode=0
[hooks] Stop hook returned followup_message, queueing (loop 1)
cli.hook.executed  hookStep=stop          status=success  exitCode=0
```

The first stop, after the edit, returned the report request, and Cursor sent
it as the next message. The agent used `os-done-or-not` and wrote `latest.md`
in the reports folder. The report was written outside the repository, so the
second stop returned `{}` and the session ended: one request, no loop. The
handover that session got already held the report of an earlier run, 1971
characters against 854 for the routing table alone.

Print mode (`agent -p`) and a prompt piped in were both tried. Both count as
headless, and both fired `sessionStart` only: the handover arrived, and the
stop hook never ran. A first attempt started from Git Bash failed on every
hook, which is how the Windows trap above was found.

Not run: the Cursor desktop app, a project-level `.cursor/hooks.json`, and
Cursor on macOS or Linux. Per Cursor's documentation, the contract is the same
there.

### Runs on Gemini CLI

On Gemini CLI 0.58.0 on Windows 11, signed in with a Gemini API key, the
skills were in `~/.agents/skills/`, the routing block in `~/.gemini/GEMINI.md`,
and the adapter wired in `~/.gemini/settings.json` in the PowerShell form
above. An interactive session was started in a throwaway repository with
`--approval-mode yolo` and asked to add one line to a file. The screen showed,
in order: `Executing Hook: open-steps-session-start` at startup, the edit,
`Executing Hook: open-steps-stop-report`, and then:

```text
⚠ Agent execution blocked: Work landed during this session (changed: os-gemini-live).
  Before finishing, use the os-done-or-not skill to produce the session report: ...
ℹ This request failed. Press F12 for diagnostics, ...
```

The second line is how the CLI shows a blocked turn; the retry then ran. The
retry used `os-done-or-not` and wrote `latest.md` in the reports folder with
the shell tool. The next `AfterAgent` answered `{}`. The state file kept the
time of the first request, and `/quit` exited 0. One refusal, no loop. The
handover a next session gets from that repository then held the report, 2180
characters against 1075 for the routing block alone.

A first attempt in `auto_edit` mode went the same way up to the retry. The
retry then waited on a permission prompt to use the skill. A person at the
keyboard would answer it, but the script driving the run did not, so no report
was written. In `yolo` mode it was.

Headless (`gemini -p`, with `--yolo --skip-trust`) was run too, on a lighter
model than the interactive run. `SessionStart` fired and took a snapshot under
a new session id. `AfterAgent` fired and refused, and the retry ran. The file
tool was refused for the reports folder, and the agent saved the report to
`~/.gemini/tmp/os-gemini-live/latest.md` instead, the temp folder the refusal
named as allowed. That run is why the request now says to use the shell tool.
Unlike on Cursor, a headless run reaches the stop hook here.

Not run: Gemini CLI on macOS or Linux, the project-level settings file, and
Google sign-in.

## What differs between the tools

- **Activation is measured on Claude Code and on Codex CLI.** On Codex CLI
  0.157.1 the right skill was read in 75 of 75 runs, first in 70. The details
  are in the README, [On Codex CLI](../README.md#on-codex-cli). On Cursor CLI
  and Gemini CLI no figure is given, because none was measured. The only skill
  seen switching on there is `os-done-or-not`, when the stop hook asked for
  it. Runners for them are open issues:
  [#40](https://github.com/kharmanskyi/open-steps/issues/40) Cursor,
  [#38](https://github.com/kharmanskyi/open-steps/issues/38) Gemini CLI.
- **Codex may shorten the descriptions.** Per Codex's skills documentation
  (https://developers.openai.com/codex/skills/, read 2026-09-27), the list of
  skills gets at most 2% of the context window, or 8,000 characters when the
  window size is unknown. When many skills are installed, their descriptions
  are shortened first. So on Codex, activation may drop when many other skills
  sit next to these. Not measured.
- **`allowed-tools:` is a Claude Code field.** Per their documentation, Codex,
  Cursor and Gemini CLI ignore it and ask for permission the way they normally
  do. So on those tools a step such as merging a pull request goes through the
  tool's own permission prompt. Not tested.
- **The answer-first writing style is a Claude Code setting.** The pack does
  not wire it on Codex, Cursor or Gemini CLI. See
  [output-style.md](output-style.md).
- **Reports land in `~/.claude/open-steps/reports/<project>/` on every tool.**
  The folder name says Claude, but it is only a path. Each tool is pointed at
  it, so they share one history.
