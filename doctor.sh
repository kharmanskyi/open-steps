#!/usr/bin/env bash
# Checks an Open Steps installation and prints what it found. Run it from
# anywhere:  bash doctor.sh
#
# The script follows the pack's own rule. It never says something is fine
# unless it looked. Anything it could not look at prints "not checked", and
# "not checked" is neither a pass nor a fault.
#
# Four labels, and they never mix in one line:
#   ok           it looked, and the thing is right
#   FAULT        it looked, and the thing is wrong
#   not checked  it could not look
#   fact         it looked, and there is nothing to judge
#
# Exit codes. Zero means no fault was found.
#   1  the skills
#   2  the routing block
#   3  the hooks
#   4  the kill switches
#   9  faults in more than one of those

set -uo pipefail

# Physical path on purpose. A plugin can be installed as a shortcut, and the
# check below compares this folder with the installed one.
PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGINS="$HOME/.claude/plugins"

faults=0
areas=""

ok()      { printf '  ok           %s\n' "$1"; }
fact()    { printf '  fact         %s\n' "$1"; }
unknown() { printf '  not checked  %s\n' "$1"; }
fault() { # $1 sentence  $2 area code
  printf '  FAULT        %s\n' "$1"
  faults=$((faults + 1))
  case " $areas " in *" $2 "*) ;; *) areas="$areas $2" ;; esac
}
section() { printf '\n%s\n' "$1"; }

area_name() {
  case "$1" in
    1) printf 'the skills' ;;
    2) printf 'the routing block' ;;
    3) printf 'the hooks' ;;
    4) printf 'the kill switches' ;;
    *) printf 'something unnamed' ;;
  esac
}

# --- what the pack expects ------------------------------------------------
# The list of skill names comes from the pack this script sits in, so a new
# skill needs no edit here. That list is the expectation. Everything measured
# below is read from the installed copy instead.
expected=()
for d in "$PACK"/skills/*/; do
  [ -d "$d" ] || continue
  expected+=("$(basename "$d")")
done

# --- finding the installed copy -------------------------------------------
# Never the folder this script sits in. A clone is not an installation, and
# reading the clone would be a check that can only pass.
json_first_name() { # $1 manifest -> the first name in it
  grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]*)"$/\1/'
}

# The marketplace the plugin came from. A marketplace holding one plugin keeps
# both manifests in the same folder; one holding several keeps its own a level
# above them. Read rather than assumed, so a fork under another name still
# builds the right key below.
market_name() { # $1 plugin folder  $2 plugin manifest -> the name, or nothing
  local mj name
  for mj in "$(dirname "$2")/marketplace.json" \
            "$1/../../.claude-plugin/marketplace.json"; do
    [ -r "$mj" ] || continue
    name="$(json_first_name "$mj")"
    if [ -n "$name" ]; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

install_candidates() {
  local km="$PLUGINS/known_marketplaces.json" loc p
  if [ -r "$km" ]; then
    # Recorded folders, one per marketplace. Windows records backslashes.
    grep -oE '"installLocation"[[:space:]]*:[[:space:]]*"[^"]+"' "$km" 2>/dev/null \
      | sed -E 's/.*"([^"]+)"$/\1/' | tr '\\' '/' | sed -E 's|/{2,}|/|g' \
      | while IFS= read -r loc; do
          printf '%s/.claude-plugin/plugin.json\n' "$loc"
          for p in "$loc"/plugins/*/.claude-plugin/plugin.json; do
            [ -f "$p" ] && printf '%s\n' "$p"
          done
        done
  fi
  [ -d "$PLUGINS" ] && find "$PLUGINS" -maxdepth 6 -type f -name plugin.json \
    -path '*/.claude-plugin/*' 2>/dev/null
}

INSTALL=""
PLUGIN_NAME=""
MARKET=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -Eq '"name"[[:space:]]*:[[:space:]]*"open-steps"' "$f" 2>/dev/null || continue
  root="$(cd "$(dirname "$f")/.." 2>/dev/null && pwd -P)" || continue
  # A marketplace manifest lives in a folder of the same shape. Only a plugin
  # brings the skills with it.
  [ -n "$root" ] && [ -d "$root/skills" ] || continue
  INSTALL="$root"
  PLUGIN_NAME="$(json_first_name "$f")"
  MARKET="$(market_name "$root" "$f")" || MARKET=""
  break
done < <(install_candidates)

printf 'Open Steps install check\n'

section "Where the pack is installed"
if [ -z "$INSTALL" ]; then
  fault "No installed copy of the pack was found. Claude Code cannot see it." 1
  fact "This script is running from $PACK."
elif [ "$INSTALL" = "$PACK" ]; then
  fact "This script is running from the installed copy, at $INSTALL."
else
  fact "This script is running from a clone, not from the installed copy."
  fact "The clone is at $PACK."
  fact "The installed copy is at $INSTALL. Everything below reads that one."
fi

# --- the skills -----------------------------------------------------------
section "Claude Code: the skills"
if [ -z "$INSTALL" ]; then
  unknown "There is no installed copy to read, so the skill files were not checked."
elif [ "${#expected[@]}" -eq 0 ]; then
  unknown "This script could not read the pack's own list of skills, so it cannot say what is missing."
else
  missing=""
  unreadable=""
  broken=""
  good=0
  for name in "${expected[@]}"; do
    f="$INSTALL/skills/$name/SKILL.md"
    if [ ! -e "$f" ]; then
      missing="$missing $name"
    elif [ ! -r "$f" ]; then
      unreadable="$unreadable $name"
    elif head -1 "$f" | grep -q '^---$' \
      && sed -n '2,/^---$/p' "$f" | grep -Eq "^name:[[:space:]]*$name[[:space:]]*$"; then
      good=$((good + 1))
    else
      # A broken header makes a skill fail without a word. The folder is still
      # there, so counting folders would pass on it.
      broken="$broken $name"
    fi
  done
  [ -n "$missing" ] && fault "These skills are not in the installed copy:$missing" 1
  [ -n "$broken" ] && fault "These skill files have a broken header, so the agent skips them:$broken" 1
  [ -n "$unreadable" ] && unknown "These skill files cannot be read:$unreadable"
  if [ -z "$missing" ] && [ -z "$broken" ] && [ -z "$unreadable" ]; then
    ok "All $good skills are installed and their headers are sound."
  fi
fi
# Switched on is a separate thing from installed. The settings file records it
# under the plugin's name and its marketplace, joined by an at sign. An
# installed copy with no entry is installed and not switched on, which is the
# case that leaves every skill file in place and the agent seeing none of them.
stf="$HOME/.claude/settings.json"
if [ -z "$INSTALL" ]; then
  unknown "There is no installed copy, so whether the plugin is switched on was not checked."
elif [ ! -e "$stf" ]; then
  unknown "There is no Claude Code settings file, so whether the plugin is switched on was not checked."
elif [ ! -r "$stf" ]; then
  unknown "The Claude Code settings file cannot be read, so whether the plugin is switched on was not checked."
elif [ -z "$PLUGIN_NAME" ] || [ -z "$MARKET" ]; then
  unknown "The name the settings file would record was not found, so whether the plugin is switched on was not checked."
else
  onkey="$PLUGIN_NAME@$MARKET"
  if grep -Eq "\"$onkey\"[[:space:]]*:[[:space:]]*true" "$stf"; then
    ok "The plugin is switched on. The settings file records $onkey as on."
  elif grep -Eq "\"$onkey\"[[:space:]]*:[[:space:]]*false" "$stf"; then
    fault "The plugin is installed but switched off. The settings file records $onkey as off." 1
  else
    fault "The plugin is installed but never switched on. The settings file has no entry for $onkey." 1
  fi
fi

# --- the routing block ----------------------------------------------------
routing_block() { # $1 file  $2 area code  $3 what to call the file
  local f="$1" area="$2" label="$3" missing="" name heading=0
  if [ ! -e "$f" ]; then
    fault "$label is not there, so the routing block is missing." "$area"
    return
  fi
  if [ ! -r "$f" ]; then
    unknown "$label cannot be read, so the routing block was not checked."
    return
  fi
  if [ "${#expected[@]}" -eq 0 ]; then
    unknown "This script could not read the pack's own list of skills, so $label was not checked."
    return
  fi
  # The skill names carry the routing, so they decide the fault. Someone who
  # wrote their own heading over the same table still routes every moment, and
  # faulting on that would cry wolf on a healthy install. The heading is still
  # what tells a whole block from a hand written one.
  grep -Fq '## These moments require a skill' "$f" && heading=1
  for name in "${expected[@]}"; do
    grep -Fq "$name" "$f" || missing="$missing $name"
  done
  if [ -n "$missing" ] && [ "$heading" -eq 0 ]; then
    fault "$label has no routing block. It does not name these skills:$missing" "$area"
  elif [ -n "$missing" ]; then
    fault "$label has a routing block, but it is cut short. Missing:$missing" "$area"
  elif [ "$heading" -eq 1 ]; then
    ok "$label has the whole routing block. All ${#expected[@]} skills are named in it."
  else
    ok "$label names all ${#expected[@]} skills. The pack's own heading is not there, so the wording is your own."
  fi
}

section "Claude Code: the routing block"
routing_block "$HOME/.claude/CLAUDE.md" 2 "Your Claude Code instructions file"
unknown "Whether the agent obeys the block is not on disk. This only checked that the words are there."

# --- the hooks ------------------------------------------------------------
section "Claude Code: the hooks"
if [ -z "$INSTALL" ]; then
  unknown "There is no installed copy to read, so the hooks were not checked."
else
  hj="$INSTALL/hooks/hooks.json"
  if [ ! -e "$hj" ]; then
    fault "The pack does not ask for its hooks. The file that declares them is missing." 3
  elif [ ! -r "$hj" ]; then
    unknown "The file that declares the hooks cannot be read."
  else
    miss=""
    grep -Fq '"SessionStart"' "$hj" || miss="$miss the start of a session"
    grep -Fq '"Stop"' "$hj" || miss="$miss the end of a session"
    grep -Fq 'session-start.sh' "$hj" || miss="$miss the start script"
    grep -Fq 'stop-report.sh' "$hj" || miss="$miss the stop script"
    if [ -n "$miss" ]; then
      fault "The hook file is incomplete. It does not name:$miss" 3
    else
      ok "The pack asks for both hooks and names both scripts."
    fi
  fi

  for s in session-start.sh stop-report.sh adapter.sh; do
    p="$INSTALL/hooks/$s"
    if [ ! -e "$p" ]; then
      fault "The hook file $s is missing from the installed copy." 3
    elif [ ! -r "$p" ]; then
      unknown "The hook file $s cannot be read."
    else
      ok "The hook file $s is in place."
    fi
  done

  # Both hooks read this one rather than run it, so it needs no runnable mark.
  fp="$INSTALL/hooks/fingerprint.sh"
  if [ ! -e "$fp" ]; then
    fault "Both hooks read one shared file. It is missing, so neither hook can work." 3
  elif [ ! -r "$fp" ]; then
    fault "Both hooks read one shared file. It cannot be read, so neither hook can work." 3
  else
    ok "The file both hooks read is in place."
  fi

  # The pack keeps that shared file unmarked on purpose. That makes it a free
  # test of the disk itself. If it comes back runnable here, this disk hands
  # out the runnable mark by itself, and the mark proves nothing about the two
  # hooks. Checked out with core.filemode set to false, that is what happens.
  if [ ! -r "$fp" ]; then
    unknown "Whether the hooks can run was not checked. The file that would have told us cannot be read."
  elif [ -x "$fp" ]; then
    unknown "Whether the hooks can run was not checked. This disk marks files runnable on its own."
  else
    notrun=""
    for s in session-start.sh stop-report.sh adapter.sh; do
      p="$INSTALL/hooks/$s"
      [ -r "$p" ] || continue
      [ -x "$p" ] || notrun="$notrun $s"
    done
    if [ -n "$notrun" ]; then
      fault "These hook files are not marked runnable, so they will not start:$notrun" 3
    else
      ok "Both hook files are marked runnable."
    fi
  fi

  fact "The hook file gives a path with a placeholder in it. Claude Code fills that in when it runs. This script does not."
  unknown "Whether Claude Code has connected the hooks to your sessions is not on disk. The sign is that no handover appears at the start of a session."
fi

# --- Codex ----------------------------------------------------------------
codex_commands() { # $1 config file -> one "event<tab>path" per line
  awk '
    /^\[\[hooks\.session_start/ { ev = "the start of a session"; next }
    /^\[\[hooks\.stop/          { ev = "the end of a session"; next }
    /^\[/                       { ev = ""; next }
    ev != "" && /^[[:space:]]*command[[:space:]]*=/ {
      if (match($0, /"[^"]*"/)) {
        print ev "\t" substr($0, RSTART + 1, RLENGTH - 2)
      }
    }
  ' "$1"
}

# Presence is decided by the pack's own things, not by the folder existing. A
# ~/.codex left behind by something else is not an install of this pack, and
# faulting on it would cry wolf. Half of the pack is a fault, because that
# silent gap is what this script hunts.
sdir="$HOME/.agents/skills"
agents="$HOME/.codex/AGENTS.md"
cfg="$HOME/.codex/config.toml"
here=0
if [ "${#expected[@]}" -gt 0 ]; then
  for name in "${expected[@]}"; do
    [ -r "$sdir/$name/SKILL.md" ] && here=1 && break
  done
  if [ "$here" -eq 0 ] && [ -r "$agents" ]; then
    for name in "${expected[@]}"; do
      grep -Fq "$name" "$agents" && here=1 && break
    done
  fi
fi
[ "$here" -eq 0 ] && [ -r "$agents" ] \
  && grep -Fq '## These moments require a skill' "$agents" && here=1
[ "$here" -eq 0 ] && [ -r "$cfg" ] \
  && grep -Eq 'session-start\.sh|stop-report\.sh' "$cfg" && here=1

section "Codex"
if [ "$here" -eq 0 ]; then
  fact "Nothing from this pack is set up for Codex. There is nothing to check."
else
  if [ ! -d "$sdir" ]; then
    fault "The shared skills folder does not exist, so Codex has no skills from this pack." 1
  elif [ "${#expected[@]}" -eq 0 ]; then
    unknown "This script could not read the pack's own list of skills, so the Codex copies were not checked."
  else
    cmissing=""
    clinked=""
    cgood=0
    for name in "${expected[@]}"; do
      if [ ! -r "$sdir/$name/SKILL.md" ]; then
        cmissing="$cmissing $name"
        continue
      fi
      # A shortcut instead of a copy renames the skill. Codex takes the name
      # from the folder it lands in, so the routing block ends up pointing at
      # names that no longer exist.
      if [ -L "$sdir/$name" ]; then
        clinked="$clinked $name"
      else
        cgood=$((cgood + 1))
      fi
    done
    [ -n "$cmissing" ] && fault "These skills are not in the shared folder for Codex:$cmissing" 1
    [ -n "$clinked" ] && fault "These skills are shortcuts, not copies, so Codex gives them other names:$clinked" 1
    if [ -z "$cmissing" ] && [ -z "$clinked" ]; then
      ok "All $cgood skills are copied into the shared folder for Codex."
    fi
  fi

  routing_block "$agents" 2 "Your Codex instructions file"

  if [ ! -e "$cfg" ]; then
    fault "Codex has no settings file, so its hooks are not set up." 3
  elif [ ! -r "$cfg" ]; then
    unknown "The Codex settings file cannot be read."
  else
    cmiss=""
    grep -Eq '^\[\[hooks\.session_start' "$cfg" || cmiss="$cmiss the start of a session"
    grep -Eq '^\[\[hooks\.stop' "$cfg" || cmiss="$cmiss the end of a session"
    if [ -n "$cmiss" ]; then
      fault "The Codex settings file sets up no hook for:$cmiss" 3
    else
      ok "The Codex settings file sets up a hook at the start and at the end of a session."
    fi
    # The block in the documentation ships an example path. Pasted unchanged it
    # reads as correct and points at nothing, so every path gets looked up.
    seen=0
    while IFS="$(printf '\t')" read -r ev cmd; do
      [ -n "${cmd:-}" ] || continue
      seen=1
      case "$cmd" in
        */absolute/path/to/*)
          fault "The Codex settings still hold the example path for $ev. Put your own path there." 3
          continue
          ;;
      esac
      if [ -f "$cmd" ]; then
        ok "The file Codex runs at $ev is there."
      else
        fault "Codex runs a file that is not there at $ev: $cmd" 3
      fi
    done < <(codex_commands "$cfg")
    if [ "$seen" -eq 0 ] && [ -z "$cmiss" ]; then
      fault "The Codex settings name no file to run, so nothing happens." 3
    fi
  fi

  unknown "Whether you trusted the Codex hooks was not checked. An untrusted hook still runs, but it can no longer stop the session to ask for a report. The sign is that reports never appear."
fi

# --- the kill switches ----------------------------------------------------
switch() { # $1 name  $2 value  $3 1 if the name is set  $4 what it turns off
  if [ "$3" -eq 0 ]; then
    ok "$1 is not set. The pack still asks for $4."
  elif [ -z "$2" ]; then
    # The hooks test for a value, not for the name, so an empty one is off.
    ok "$1 is set but empty. The hooks read that as not set, so the pack still asks for $4."
  else
    fault "$1 is set to \"$2\". The pack no longer asks for $4." 4
  fi
}

section "The kill switches"
d_set=0
[ -n "${OPEN_STEPS_DISABLE+set}" ] && d_set=1
n_set=0
[ -n "${OPEN_STEPS_NO_SESSION_START+set}" ] && n_set=1
switch "OPEN_STEPS_DISABLE" "${OPEN_STEPS_DISABLE:-}" "$d_set" \
  "a report at the end of a session"
switch "OPEN_STEPS_NO_SESSION_START" "${OPEN_STEPS_NO_SESSION_START:-}" "$n_set" \
  "a handover at the start of a session"
fact "These were read from the terminal that ran this script. A different way of starting the agent can carry different settings."
fact "The shell recorded for this account is ${SHELL:-not recorded}."

section "The kill switches in your startup files"
# A weaker signal, kept apart on purpose. A name in one of these files can sit
# in a comment, or in a line that switches the pack back on. This script
# reports the mention, judges nothing, and never changes the exit code.
looked=0
hits=0
for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
         "$HOME/.zshrc" "$HOME/.zshenv"; do
  [ -e "$f" ] || continue
  if [ ! -r "$f" ]; then
    unknown "$f cannot be read."
    continue
  fi
  looked=1
  for v in OPEN_STEPS_DISABLE OPEN_STEPS_NO_SESSION_START; do
    if grep -Fq "$v" "$f"; then
      hits=$((hits + 1))
      fact "$f mentions $v. Open it and read that line yourself."
    fi
  done
done
if [ "$looked" -eq 0 ]; then
  unknown "No startup file was found to read."
elif [ "$hits" -eq 0 ]; then
  ok "No startup file mentions a kill switch."
fi

# --- the writing style ----------------------------------------------------
section "The writing style"
# Reported, never judged. The pack ships this style switched off on purpose,
# so whatever it says here is a fact about your setup and never a fault.
st="$HOME/.claude/settings.json"
if [ ! -e "$st" ]; then
  fact "There is no Claude Code settings file, so the pack's writing style is off."
elif [ ! -r "$st" ]; then
  unknown "The Claude Code settings file cannot be read."
else
  style="$(grep -oE '"outputStyle"[[:space:]]*:[[:space:]]*"[^"]*"' "$st" 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]*)"$/\1/')"
  if [ -z "$style" ]; then
    fact "The settings file sets no writing style, so the pack's style is off."
  else
    fact "The settings file sets the writing style to \"$style\"."
  fi
fi
unknown "A writing style can be set elsewhere too. This only read the settings file."

# --- other tools ----------------------------------------------------------
section "Other tools"
fact "Cursor and Gemini CLI run the hooks through hooks/adapter.sh, wired by hand; see docs/other-agents.md."

# --- the result -----------------------------------------------------------
section "Result"
if [ "$faults" -eq 0 ]; then
  printf '  No fault found.\n'
  printf '  Every line marked "not checked" is a thing this script could not look at.\n'
  printf '  Exit code 0.\n'
  exit 0
fi

# shellcheck disable=SC2086  # deliberate split: areas holds a list of codes
set -- $areas
if [ "$#" -gt 1 ]; then
  code=9
else
  code="$1"
fi

if [ "$faults" -eq 1 ]; then
  printf '  One fault, in %s.\n' "$(area_name "$1")"
elif [ "$#" -eq 1 ]; then
  printf '  %s faults, all in %s.\n' "$faults" "$(area_name "$1")"
else
  printf '  %s faults, in more than one place.\n' "$faults"
  for a in "$@"; do
    printf '  At least one is in %s.\n' "$(area_name "$a")"
  done
fi
printf '  Exit code %s.\n' "$code"
exit "$code"
