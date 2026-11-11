#!/usr/bin/env bash
# The runner for Antigravity CLI: one measured run, as evals/run.sh asks for it.
#
# Called like every runner in this folder, inside a throwaway git repository:
#   evals/agents/antigravity.sh ARM MODEL PROMPT
# The contract is in evals/README.md, "Measuring another agent". The pack is
# installed for your user the way docs/other-agents.md says: the skills copied
# into ~/.gemini/config/skills/, the hooks in ~/.gemini/config/hooks.json. The
# routing block's place on Antigravity is AGENTS.md in each project, and the
# repository run.sh makes has none; the session-start hook hands the model the
# same routing table at the start of every run. What is measured is whether
# that install switches on by itself, so nothing here points Antigravity at a
# skill. Nothing is written in the folder the runner runs in either: run.sh's
# auth check runs it from wherever run.sh was started.
#
# What counts as opening a skill: a read of a pack skill's SKILL.md with one of
# Antigravity's file tools, read_file or view_file. Antigravity has no skill
# tool: the tool list its init event carries names none, and in the probe runs
# the agent opened a skill by reading its SKILL.md with read_file. A read is
# one step, reported when it starts and again when it ends, and it makes one
# Skill call, whose id is the step's index and the skill's name. A path counts
# when it ends in <skill>/SKILL.md, where <skill> is the name of a folder in
# this pack's skills/ that holds a SKILL.md, whatever folder the path runs
# through and whatever the tool calls the parameter that holds it.
# A read of the skills folder for your user goes through headless (seen in a
# run). A read Antigravity refused still counts, and is listed as refused:
# headless, nobody can grant a permission, and a read of another file outside
# the workspace ends in an ERROR step, "permission check failed" (seen in a
# run). The call is the choice, as on Gemini CLI, whose activation tool is not
# registered headless and whose call still counts.
# Not an opening: a listing or a search of the skills folder (list_dir,
# find_by_name, grep_search), a read under references/, a SKILL.md of a skill
# that is not this pack's, a write, and a shell command. Headless, Antigravity
# refuses every shell command unless a rule allows it, and the refusal is
# named in the result, not tied to the step, so a shell read could not be told
# from a refused one; in the probe runs no skill was opened that way.
#
# The run is headless with no permission rules, the way claude.sh's plain arm
# allows nothing. The first refused tool ends the run with no answer (seen in
# a run): the result line then carries an empty answer, and the scorer counts
# the call the model made before it. A report phrase usually reaches a git
# command after the skill is read, and that command is refused, so most of
# those runs end that way. A number in results-antigravity.md means
# this and no more.
#
# Read from real runs of Antigravity CLI (agy) 1.5.5 on macOS,
# `agy -p ... --output-format stream-json`: one JSON object per line, with an
# event of init (conversation_id; init: model, cwd, tools, permission_mode),
# step_update (step_index, state ACTIVE, DONE or ERROR, step_type, tool_name,
# tool_info: name, parameters, output, error) or result (status, response,
# denied_actions). A later build that renames these turns every run into a
# miss, never into a hit, so a column of zeros is the first thing to check
# after an upgrade. One third-party report says a Windows build rejects
# --output-format; not tried.
set -u -o pipefail
arm="$1" model="$2" prompt="$3"
# The quality arms need what Antigravity does not have headless: a way to
# allow a skill in one arm and turn every skill off in the other (claude.sh
# does it with --allowedTools and --disable-slash-commands). The premortem
# phase runs with the "with" arm, so it is left out too, and issue #49 asked
# for the activation and off-topic runs only.
case "$arm" in
  plain) ;;
  *) echo "antigravity.sh: the $arm arm is not run on Antigravity; use EVAL_ONLY=\"activation negatives\"" >&2
     exit 2 ;;
esac
PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The converter: Antigravity's own events pass through as they came, so the
# stream stays the whole transcript and the reading can be checked against
# it. The scorer reads only the three kinds of line the contract names, and
# skips the rest. It is given as -c because stdin is the stream. It is read
# with read, not $(cat <<...): bash 3.2, which macOS ships, parses a heredoc
# inside $( ) as script and trips on the quotes and parentheses in the Python.
IFS= read -r -d '' convert <<'PY' || true
import json
import os
import re
import sys

model, pack = sys.argv[1], sys.argv[2]
SKILLS = {d for d in os.listdir(os.path.join(pack, "skills"))
          if os.path.isfile(os.path.join(pack, "skills", d, "SKILL.md"))}
READERS = {"read_file", "view_file"}
# The folder right above a file named SKILL.md: SKILL.md.bak is another file.
SKILL_PATH = re.compile(r"(?:^|[\\/])([^\\/]+)[\\/]SKILL\.md$")


def emit(line):
    # Flushed line by line: a run the time cap kills keeps what it wrote.
    print(json.dumps(line), flush=True)


def opened(info):
    # The pack skill whose SKILL.md a read names, in any of its parameters.
    for value in (info.get("parameters") or {}).values():
        if isinstance(value, str):
            match = SKILL_PATH.search(value.strip())
            if match and match.group(1) in SKILLS:
                return match.group(1)
    return None


calls, denied = set(), []
for raw in sys.stdin:
    try:
        event = json.loads(raw)
    except ValueError:
        continue
    emit(event)
    kind = event.get("event", "")
    if kind == "init":
        # The model is the one the stream names, which is the one asked for.
        # A run that dies before this line has no init line, and the scorer
        # routes it by the file name run.sh gave it.
        emit({"type": "system", "subtype": "init",
              "model": (event.get("init") or {}).get("model") or model, "agent": "antigravity"})
    elif kind == "step_update":
        step = event.get("step_update") or {}
        if step.get("step_type") != "tool" or step.get("tool_name") not in READERS:
            continue
        name = opened(step.get("tool_info") or {})
        if not name:
            continue
        call = f"step_{step.get('step_index')}-{name}"
        if call not in calls:
            calls.add(call)
            emit({"type": "assistant", "message": {"role": "assistant", "content": [
                {"type": "tool_use", "id": call, "name": "Skill", "input": {"skill": name}}]}})
        if step.get("state") == "ERROR" and {"tool_name": "Skill", "tool_use_id": call} not in denied:
            denied.append({"tool_name": "Skill", "tool_use_id": call})
    elif kind == "result":
        result = event.get("result") or {}
        if result.get("status") == "SUCCESS":
            emit({"type": "result", "result": result.get("response") or "", "permission_denials": denied})
        # Any other status writes no result line: the run did not finish, and
        # the scorer counts it as unfinished rather than as an answer.
PY
# stdin from /dev/null, so the phrase arrives as cases.md has it. There is no
# turn cap to match claude.sh's --max-turns 12; run.sh's time cap per run is
# the limit here. pipefail carries agy's own exit status through the pipe, so
# a run that is not signed in fails run.sh's auth check.
agy -p "$prompt" --model "$model" --output-format stream-json </dev/null |
  python3 -c "$convert" "$model" "$PACK"
