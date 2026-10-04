#!/usr/bin/env bash
# The runner for Cursor CLI: one measured run, as evals/run.sh asks for it.
#
# Called inside a throwaway git repository as:
#   evals/agents/cursor.sh ARM MODEL PROMPT
#
# Cursor does not emit Claude Code's Skill tool event. In Cursor's stream-json,
# opening a pack skill is a readToolCall whose path is:
#   ~/.agents/skills/os-*/SKILL.md
# Each completed read of one of those SKILL.md files is therefore converted to
# one synthetic Skill tool_use event for the scorer.
#
# The routing block is copied into AGENTS.md in the throwaway repository because
# Cursor reads project instructions there.
set -u
set -o pipefail

arm="$1"
model="$2"
prompt="$3"

case "$arm" in
  plain)
    ;;
  with|without)
    echo "cursor runner: arm '$arm' is not available" >&2
    exit 2
    ;;
  *)
    echo "cursor runner: unknown arm '$arm'" >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
routing="$repo_root/docs/routing-block.md"

if ! grep -q 'os-done-or-not' AGENTS.md 2>/dev/null; then
  cat "$routing" >> AGENTS.md
fi

agent_bin="${CURSOR_AGENT:-agent}"

run_cursor() {
  if [[ "$agent_bin" == *.cmd ]]; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$agent_bin")/cursor-agent.ps1" -p --trust --model "$model" --output-format stream-json "$prompt"
  else
    "$agent_bin" -p --trust --model "$model" --output-format stream-json "$prompt"
  fi
}

run_cursor |
python3 -c '
import json
import re
import sys

skill_path = re.compile(
    r"(?:^|[\\/])\.agents[\\/]skills[\\/](os-[^\\/]+)[\\/]SKILL\.md$",
    re.IGNORECASE,
)

for raw in sys.stdin:
    raw = raw.rstrip("\r\n")
    if not raw:
        continue

    try:
        event = json.loads(raw)
    except json.JSONDecodeError:
        print(raw, flush=True)
        continue

    if event.get("type") == "system" and event.get("subtype") == "init":
        event["agent"] = "cursor"
        print(json.dumps(event, separators=(",", ":")), flush=True)
        continue

    if event.get("type") == "tool_call" and event.get("subtype") == "completed":
        tool_call = event.get("tool_call") or {}
        read_call = tool_call.get("readToolCall") or {}
        args = read_call.get("args") or {}
        path = args.get("path")

        if isinstance(path, str):
            match = skill_path.search(path)
            if match:
                skill = match.group(1)
                converted = {
                    "type": "assistant",
                    "message": {
                        "role": "assistant",
                        "content": [{
                            "type": "tool_use",
                            "id": event.get("call_id", "cursor-skill"),
                            "name": "Skill",
                            "input": {"skill": skill},
                        }],
                    },
                }
                print(json.dumps(converted, separators=(",", ":")), flush=True)
                continue

    print(json.dumps(event, separators=(",", ":")), flush=True)
'
