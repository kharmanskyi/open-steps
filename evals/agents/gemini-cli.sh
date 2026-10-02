#!/usr/bin/env bash
# The runner for Gemini CLI: one measured run, as evals/run.sh asks for it.
#
# Called like every runner in this folder, inside a throwaway git repository:
#   evals/agents/gemini-cli.sh ARM MODEL PROMPT
# The contract is in evals/README.md, "Measuring another agent". The pack is
# installed the way docs/other-agents.md says: the skills copied into
# ~/.agents/skills/, the routing block in ~/.gemini/GEMINI.md, the hooks in
# ~/.gemini/settings.json. What is measured is whether that install switches
# on by itself, so nothing here points Gemini at a skill.
#
# What counts as opening a skill: a call of Gemini's activate_skill tool with
# the name of one of this pack's skills. Gemini CLI lists every installed
# skill in its system prompt and tells the model to call that tool to get a
# skill's instructions, so the call is the choice, made once per skill. Its
# id is the call's own id, so the refusal below is matched to it. A name that
# is not a folder in this pack's skills/ with a SKILL.md in it is another
# skill and gives no line: the scorer counts the pack's skills only, and a
# stray one would count as a false fire on the off-topic phrases.
# Not an opening: a read of a SKILL.md with the file tool. The reports folder
# and the skills folder are outside the workspace, and Gemini's file tools
# refuse paths outside it (seen in the runs behind docs/other-agents.md), so
# a read never delivers the skill; and unlike Codex, Gemini has the
# activation tool, so a read is not how a skill is opened here.
#
# The run is headless without --yolo. In that mode Gemini CLI 0.62.0 does
# not register activate_skill, nor run_shell_command: the model, which still
# sees the skills and the tool's name in its prompt, calls it and gets
# "tool_not_registered" back (seen in a run, in the default and the plan
# approval modes alike). The call is still made, so
# it is counted, and the refusal is listed under permission_denials with the
# call's id, the way Claude Code lists a denied Skill call: claude.sh's
# plain arm allows nothing either, and its numbers count the call the model
# makes before it is denied. Any status but success on that call's result is
# listed as a refusal; a skill Gemini could not find is refused too. --yolo
# would let the skill load, and with it let the shell and file tools write
# into the throwaway repository that every run of the sweep shares, which is
# what claude.sh's deny list and codex.sh's read-only sandbox keep from
# happening. A number in results-gemini-cli.md means this and no more.
#
# Read from real runs of Gemini CLI 0.62.0, `gemini -p ... -o stream-json`:
# one JSON object per line, of type init (session_id, model), message (role,
# content, delta), tool_use (tool_name, tool_id, parameters), tool_result
# (tool_id, status, output, error), error (severity, message) and result
# (status, stats). Also read in its source, not seen in a run: a result with
# status "error" is written when the run fails. A later build that renames
# these turns every run into a miss, never into a hit, so a column of zeros
# is the first thing to check after an upgrade.
set -u -o pipefail
arm="$1" model="$2" prompt="$3"
# The quality arms need what Gemini CLI does not have headless: a way to
# allow a skill in one arm and turn every skill off in the other (claude.sh
# does it with --allowedTools and --disable-slash-commands). The premortem
# phase runs with the "with" arm, so it is left out too, and issue #38 asked
# for the activation and off-topic runs only.
case "$arm" in
  plain) ;;
  *) echo "gemini-cli.sh: the $arm arm is not run on Gemini CLI; use EVAL_ONLY=\"activation negatives\"" >&2
     exit 2 ;;
esac
PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The converter: Gemini's own events pass through as they came, so the stream
# stays the whole transcript and the reading can be checked against it. The
# scorer reads only the three kinds of line the contract names, and skips the
# rest. It is given as -c because stdin is the stream. It is read with read,
# not $(cat <<...): bash 3.2, which macOS ships, parses a heredoc inside $( )
# as script and trips on the quotes and parentheses in the Python.
IFS= read -r -d '' convert <<'PY' || true
import json
import os
import sys

model, pack = sys.argv[1], sys.argv[2]
SKILLS = {d for d in os.listdir(os.path.join(pack, "skills"))
          if os.path.isfile(os.path.join(pack, "skills", d, "SKILL.md"))}


def emit(line):
    # Flushed line by line: a run the time cap kills keeps what it wrote.
    print(json.dumps(line), flush=True)


calls, denied, answer = {}, [], []
for raw in sys.stdin:
    try:
        event = json.loads(raw)
    except ValueError:
        continue
    emit(event)
    kind = event.get("type", "")
    if kind == "init":
        # The model is the one the stream names, which is the one asked for.
        # A run that dies before this line has no init line, and the scorer
        # routes it by the file name run.sh gave it.
        emit({"type": "system", "subtype": "init", "model": event.get("model") or model, "agent": "gemini-cli"})
    elif kind == "tool_use" and event.get("tool_name") == "activate_skill":
        name = str((event.get("parameters") or {}).get("name", ""))
        call = str(event.get("tool_id", ""))
        if name in SKILLS:
            calls[call] = name
            emit({"type": "assistant", "message": {"role": "assistant", "content": [
                {"type": "tool_use", "id": call, "name": "Skill", "input": {"skill": name}}]}})
    elif kind == "tool_result" and event.get("tool_id") in calls and event.get("status") != "success":
        denied.append({"tool_name": "Skill", "tool_use_id": event["tool_id"]})
    elif kind == "message" and event.get("role") == "assistant":
        answer.append(event.get("content") or "")
    elif kind == "result" and event.get("status") == "success":
        emit({"type": "result", "result": "".join(answer), "permission_denials": denied})
    # A result with another status writes no result line: the run did not
    # finish, and the scorer counts it as unfinished rather than as an answer.
PY
# --skip-trust: the throwaway repository run.sh makes is not a trusted
# folder, and headless nobody answers the trust prompt. Untrusted, the CLI
# reads no settings or skills from the folder itself, and the pack is
# installed in the home folder, which it reads (the routing block and the
# skills were in every probe run). stdin from /dev/null: -p appends piped
# stdin to the prompt, and the phrase must arrive as cases.md has it.
#
# There is no turn cap to match claude.sh's --max-turns 12; run.sh's time cap
# per run is the limit here. pipefail carries gemini's own exit status
# through the pipe, so a failed sign-in fails run.sh's auth check.
gemini -p "$prompt" -m "$model" -o stream-json --skip-trust </dev/null |
  python3 -c "$convert" "$model" "$PACK"
