#!/usr/bin/env bash
# Activation and quality measurement for the Open Steps pack.
#
# Run it from the pack root, from YOUR terminal (headless claude needs your
# keychain for OAuth):   bash evals/run.sh
#
# What it does, in plain words:
#   1. one tiny run to check authentication works at all
#   2. asks each trigger phrase from cases.md 3 times in the real installed
#      setup and records which skill fired, if any
#   3. asks the off-topic phrases the same way (no skill should fire)
#   4. gives the same messy engineer report to the agent twice over: once
#      normally, once with every skill switched off, 3 times each
#   5. prints the score with evals/score.py (a plain script, no AI judging)
#
# Every case lives in evals/cases.md. Cost control: N_RUNS=3, cheapest model
# by default, ~60 short runs. Change N_RUNS to taste.
set -u
PACK="$(cd "$(dirname "$0")/.." && pwd)"
CASES="$PACK/evals/cases.md"
N_RUNS="${N_RUNS:-3}"
MODEL="${EVAL_MODEL:-haiku}"
PAR="${EVAL_PARALLEL:-5}"
# 240s cap per run. macOS ships no timeout command of its own (it usually
# arrives with Homebrew coreutils), so fall back to gtimeout, then to no cap.
if command -v timeout >/dev/null 2>&1; then LIMIT="timeout 240"
elif command -v gtimeout >/dev/null 2>&1; then LIMIT="gtimeout 240"
else LIMIT=""; fi
# A full sweep is 234 separate agent runs, so it is 234 transcripts. They live
# outside the repository, next to where the pack keeps its reports: one folder
# per day, every model in it, each file carrying its model in the name. Running
# one model again replaces that model's files and leaves the rest of the day
# alone. The scorer still reads the model out of the stream, not the name.
OUT="$HOME/.claude/open-steps/evals/$(date +%Y-%m-%d)"
mkdir -p "$OUT"

# --- readers for cases.md ------------------------------------------------
# table: prints the rows of one "## " section as tab-separated cells. The two
# first rows of a markdown table are the header and its dashes, so skip those.
table() {
  awk -v want="## $1" -F'|' '
    /^## / { insec = ($0 == want); rows = 0; next }
    !insec { next }
    /^\|/  { rows++; if (rows <= 2) next
             a = $2; b = $3
             gsub(/^[ \t]+|[ \t]+$/, "", a); gsub(/^[ \t]+|[ \t]+$/, "", b)
             print (b == "" ? a : a "\t" b) }
  ' "$CASES"
}
# block: prints the fenced code block under a "### " heading.
block() {
  awk -v want="### $1" '
    $0 == want  { f = 1; next }
    f && /^```/ { if (inb) exit; inb = 1; next }
    inb         { print }
  ' "$CASES"
}

echo "== 1/4 auth check =="
if ! claude -p --model "$MODEL" --max-turns 1 "say just: ok" </dev/null >/dev/null 2>&1; then
  echo "Authentication failed. Run this from your own terminal (not from an agent),"
  echo "and make sure 'claude -p \"say ok\"' works first."
  exit 1
fi
echo "auth ok"

# a tiny throwaway project so report skills have something real to look at
WORK="$(mktemp -d)"
( cd "$WORK" && git init -q && echo "# demo" > README.md && git add . \
  && git -c user.name=eval -c user.email=eval@local commit -qm "init" \
  && echo "print('hello')" > app.py && git add . \
  && git -c user.name=eval -c user.email=eval@local commit -qm "add app" )

run_one() { # $1 tag  $2 with|without  $3 prompt
  local tag="$MODEL-$1" arm="$2" prompt="$3"
  # The "without" arm turns every skill off, so the same agent answers unaided.
  # Plain string, not an array: macOS ships bash 3.2, where expanding an empty
  # array under `set -u` kills the subshell without a word. $LIMIT expands the
  # same deliberate way.
  local extra=""
  [ "$arm" = "without" ] && extra="--disable-slash-commands"
  ( cd "$WORK" && $LIMIT claude -p $extra --model "$MODEL" \
      --max-turns 12 --output-format stream-json --verbose \
      "$prompt" > "$OUT/$tag.jsonl" 2>"$OUT/$tag.err" </dev/null )
  # Keep an error file only when there was an error, so one lying around means
  # something to look at.
  [ -s "$OUT/$tag.err" ] || rm -f "$OUT/$tag.err"
  echo "done: $tag"
}

echo "== 2/4 activation ($(table 'Should fire' | wc -l | tr -d ' ') phrases x $N_RUNS runs) =="
i=0
while IFS=$'\t' read -r skill prompt; do
  [ -z "$skill" ] && continue
  i=$((i+1))
  for r in $(seq 1 "$N_RUNS"); do
    run_one "act-${i}-${skill}-r${r}" with "$prompt" &
    while [ "$(jobs -r | wc -l)" -ge "$PAR" ]; do sleep 1; done
  done
done <<EOF
$(table 'Should fire')
EOF
wait

echo "== 3/4 negatives =="
i=0
while IFS=$'\t' read -r prompt; do
  [ -z "$prompt" ] && continue
  i=$((i+1))
  for r in $(seq 1 "$N_RUNS"); do
    run_one "neg-${i}-r${r}" with "$prompt" &
    while [ "$(jobs -r | wc -l)" -ge "$PAR" ]; do sleep 1; done
  done
done <<EOF
$(table 'Should not fire')
EOF
wait

echo "== 4/4 quality, with vs without =="
QPROMPT="$(block Prompt)

$(block Report)"
for r in $(seq 1 "$N_RUNS"); do
  run_one "qual-with-r${r}" with "$QPROMPT" &
  run_one "qual-without-r${r}" without "$QPROMPT" &
  while [ "$(jobs -r | wc -l)" -ge "$PAR" ]; do sleep 1; done
done
wait

rm -rf "$WORK"
echo "== the day so far =="
python3 "$PACK/evals/score.py" --print "$OUT"
echo
echo "Transcripts: $OUT"
echo "When the day holds every model you want, publish it into evals/results.md:"
echo "  python3 evals/score.py $OUT"
