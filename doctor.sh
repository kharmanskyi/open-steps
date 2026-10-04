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
# What it judges depends on which tools are on this machine and what of the
# pack each one holds. It reads files and changes nothing.
#   skills folders  ~/.agents/skills, shared by Codex, Cursor and Gemini CLI,
#                and each tool's own: ~/.codex/skills, ~/.cursor/skills and
#                ~/.gemini/skills. All four are read, and a copy in any of them
#                is checked: every skill, each with a sound header, and with
#                the references and scripts folders its source has. Part of
#                the pack is a fault. Shortcuts are a fault in a folder Codex
#                reads (the shared one, ~/.codex/skills) while Codex is judged;
#                otherwise they are a fact, and what the tool does with them is
#                "not checked".
#   found for another tool  a copy in a tool's own folder, a copy in the
#                shared folder while ~/.codex, ~/.cursor or ~/.gemini exists, a
#                Codex AGENTS.md that mentions the pack or a config.toml that
#                runs one of its hooks, or a Gemini CLI or Cursor whose routing
#                block or hooks file names it. A tool set up that way with no
#                copy of the skills in the shared folder or its own is a fault,
#                blamed on that tool.
#   Claude Code  a sign of it is the claude command on the PATH,
#                ~/.claude.json, or a plugins folder, settings file or
#                CLAUDE.md in ~/.claude. A bare ~/.claude does not count: the
#                hooks keep their reports under it on every tool. With no sign,
#                its parts print "not checked". With a sign, it is judged once
#                its files hold something of the pack (a registry entry, a copy
#                in its plugin cache, an entry for the plugin in its settings
#                file, the routing block in CLAUDE.md), or when the pack is not
#                found for another tool. Otherwise that it holds nothing of the
#                pack is a fact. A registered marketplace is not an install:
#                with no registry entry, the plugin cache is searched, never
#                the marketplace folders.
#   found for no tool  not found for another tool and no sign of Claude Code:
#                a fault when nothing of the pack is on the machine. A copy in
#                the shared folder with none of those tools here is "not
#                checked": a tool this script does not know may read it.
#   Codex        judged in full when ~/.codex exists and its AGENTS.md
#                mentions the pack or its config.toml runs one of the pack's
#                hooks, or ~/.codex/skills holds a copy, or the shared folder
#                holds one while there is no ~/.gemini or ~/.cursor and nothing
#                of the pack in Claude Code's files, which leaves Codex as the
#                one tool the copy can be for. In full means a copy of the
#                skills, the routing block in AGENTS.md, and hooks in
#                config.toml whose paths are files marked runnable, with
#                fingerprint.sh beside them. A hook is the pack's when its path
#                is under the installed copy or the clone, or its folder holds
#                fingerprint.sh and sits next to a skills folder of the pack. A
#                file of the same name from somewhere else is a fact, never a
#                fault, and so is a command that is not a path. A path through
#                ~ is "not checked". With a shared copy that could be for
#                another tool, and no Codex file that mentions the pack, that
#                is a fact.
#   Gemini CLI, Cursor  their routing block and the hook commands they name
#                are reported as facts. Four things are judged. The path in
#                front of adapter.sh: the example path from
#                docs/other-agents.md, or a path with no file, is a fault; a
#                path that is not a full path is "not checked". The event each
#                command sits under: SessionStart and AfterAgent on Gemini CLI,
#                sessionStart and stop on Cursor. The files adapter.sh needs
#                beside it. And the runnable mark, when a command runs
#                adapter.sh directly rather than through a shell.
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

# A registered marketplace is where a plugin comes from, not an install. Its
# folder, the one known_marketplaces.json records or the one under
# plugins/marketplaces, holds the plugin whether or not it was ever installed,
# and for a marketplace added from a local directory it is the clone itself.
# So the search reads the plugin cache, where an installed copy lives.
install_candidates() {
  [ -d "$PLUGINS/cache" ] && find "$PLUGINS/cache" -maxdepth 6 -type f -name plugin.json \
    -path '*/.claude-plugin/*' 2>/dev/null
}

# Claude Code runs the copy that installed_plugins.json names under
# installPath. The folder in known_marketplaces.json is where the plugin came
# from, and for a marketplace added from a local directory that folder is the
# clone itself, so a search that starts there reads the clone and says ok
# about files the running copy never received. The registry decides; the
# plugin cache is searched only when it has no entry to give.
registry_entry() { # -> two lines, the pack's key and its installPath, or nothing
  local reg="$PLUGINS/installed_plugins.json" m
  [ -r "$reg" ] || return 1
  # Flattened first: the file is pretty-printed today and a one-line copy must
  # read the same. The array after the key holds one object per scope; the
  # first is the copy this machine runs. Windows records backslashes.
  m="$(tr -d '\n' < "$reg" \
    | grep -oE '"open-steps@[^"]*"[[:space:]]*:[[:space:]]*\[[^]]*"installPath"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | head -1)"
  [ -n "$m" ] || return 1
  printf '%s\n' "$m" | sed -E 's/^"([^"]+)".*/\1/'
  # shellcheck disable=SC1003  # tr wants the backslash doubled, not quoted
  printf '%s\n' "$m" | sed -E 's/.*"installPath"[[:space:]]*:[[:space:]]*"([^"]+)"$/\1/' \
    | tr '\\' '/' | sed -E 's|/{2,}|/|g'
}

manifest_version() { # $1 manifest -> its version, or nothing
  grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]*)"$/\1/'
}

# --- what of the pack each tool holds -------------------------------------
# Everything is looked up before anything is printed: whether Claude Code is
# judged depends on whether the pack was found for another tool.
mentions_pack() { # $1 file -> true when it names a skill of the pack or has its heading
  local name
  [ -r "$1" ] || return 1
  grep -Fq '## These moments require a skill' "$1" && return 0
  [ "${#expected[@]}" -gt 0 ] || return 1
  for name in "${expected[@]}"; do
    grep -Fq "$name" "$1" && return 0
  done
  return 1
}

has_copy() { # $1 skills folder -> true when at least one skill of the pack is in it
  local name
  [ "${#expected[@]}" -gt 0 ] || return 1
  for name in "${expected[@]}"; do
    [ -r "$1/$name/SKILL.md" ] && return 0
  done
  return 1
}

header_sound() { # $1 a SKILL.md  $2 the skill's name -> true when the header is one the agent reads
  head -1 "$1" | grep -q '^---$' \
    && sed -n '2,/^---$/p' "$1" | grep -Eq "^name:[[:space:]]*${2}[[:space:]]*$"
}

path_state() { # $1 path -> example, here, gone or partial
  case "$1" in
    */path/to/*) printf 'example' ;;
    /*|[A-Za-z]:/*) if [ -f "$1" ]; then printf 'here'; else printf 'gone'; fi ;;
    *) printf 'partial' ;;
  esac
}

# A hook of this pack sits in the hooks folder of a copy of it: the installed
# copy, the clone, or a folder that holds fingerprint.sh with a skills folder
# of the pack beside it. A file of the same name from somewhere else is not
# this pack's hook, and taking it for one would judge a Codex nobody set up.
pack_hook() { # $1 path -> true when the file is this pack's hook
  local dir real
  dir="$(dirname "$1")"
  # The physical path, the way the installed copy and the clone are read: a
  # folder reached through a shortcut must compare equal to itself.
  real="$(cd "$dir" 2>/dev/null && pwd -P)" || real="$dir"
  case "$real/" in "$PACK"/*) return 0 ;; esac
  if [ -n "$INSTALL" ]; then
    case "$real/" in "$INSTALL"/*) return 0 ;; esac
  fi
  [ -e "$dir/fingerprint.sh" ] && has_copy "$dir/../skills"
}

# Codex sets its hooks in TOML. Each command string, in double or single
# quotes, under a session_start or stop table.
codex_commands() { # $1 config file -> one "event<tab>command" per line
  awk -v q="'" '
    /^\[\[hooks\.session_start/ { ev = "the start of a session"; next }
    /^\[\[hooks\.stop/          { ev = "the end of a session"; next }
    /^\[/                       { ev = ""; next }
    ev != "" && /^[[:space:]]*command[[:space:]]*=/ {
      if (match($0, /"[^"]*"/) || match($0, q "[^" q "]*" q)) {
        print ev "\t" substr($0, RSTART + 1, RLENGTH - 2)
      }
    }
  ' "$1"
}

# What a Codex hook command is. The first word is the file, or a shell with
# the file as its second word. Anything else is another hook, not a path.
codex_kind() { # $1 command -> "kind<tab>file<tab>direct", the kind one of ours, example, partial, foreign, gone or other
  local first second file direct=1
  read -r first second _ <<<"$1"
  case "$first" in
    bash|sh|*/bash|*/sh) file="$second"; direct=0 ;;
    */*) file="$first" ;;
    *) file="" ;;
  esac
  if [ -z "$file" ]; then
    printf 'other\t%s\t%s' "$1" "$direct"
    return
  fi
  case "$(path_state "$file")" in
    example) printf 'example\t%s\t%s' "$file" "$direct"; return ;;
    partial) printf 'partial\t%s\t%s' "$file" "$direct"; return ;;
  esac
  if pack_hook "$file"; then
    printf 'ours\t%s\t%s' "$file" "$direct"
    return
  fi
  case "$(basename "$file")" in
    session-start.sh|stop-report.sh)
      if [ -e "$file" ]; then
        printf 'foreign\t%s\t%s' "$file" "$direct"
      else
        printf 'gone\t%s\t%s' "$file" "$direct"
      fi ;;
    *) printf 'other\t%s\t%s' "$1" "$direct" ;;
  esac
}

codex_kinds() { # $1 config file -> one "kind<tab>file<tab>direct<tab>event" per line
  local ev cmd
  while IFS="$(printf '\t')" read -r ev cmd; do
    [ -n "${cmd:-}" ] || continue
    printf '%s\t%s\n' "$(codex_kind "$cmd")" "$ev"
  done < <(codex_commands "$1")
}

# Codex, Cursor and Gemini CLI read one shared skills folder, and each reads a
# folder of its own too. A copy in a tool's own folder is that tool's. A copy
# in the shared one does not say which of the three it was meant for.
sdir="$HOME/.agents/skills"
codex="$HOME/.codex"
agents="$codex/AGENTS.md"
cfg="$codex/config.toml"
gem="$HOME/.gemini"
cur="$HOME/.cursor"
shared=0
has_copy "$sdir" && shared=1
codex_own=0
has_copy "$codex/skills" && codex_own=1
cur_own=0
has_copy "$cur/skills" && cur_own=1
gem_own=0
has_copy "$gem/skills" && gem_own=1

# Whether the pack is set up for Codex, Gemini CLI or Cursor is read below,
# once the installed copy is known: a Codex hook counts only when its path is
# this pack's, and that test needs the installed copy.

# A sign of Claude Code is its command, ~/.claude.json, or the files this
# script reads for it below. A bare ~/.claude is not enough: the hooks write
# their reports under ~/.claude/open-steps on every tool, so a Gemini CLI
# machine grows one too.
CC=0
command -v claude >/dev/null 2>&1 && CC=1
for f in "$PLUGINS" "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md" \
         "$HOME/.claude.json"; do
  [ -e "$f" ] && CC=1
done
stf="$HOME/.claude/settings.json"

INSTALL=""
PLUGIN_NAME=""
MARKET=""
REG_PATH=""
DECIDED=""
if [ "$CC" -eq 0 ]; then
  DECIDED="absent"
elif entry="$(registry_entry)"; then
  REG_KEY="$(printf '%s\n' "$entry" | sed -n 1p)"
  REG_PATH="$(printf '%s\n' "$entry" | sed -n 2p)"
  f="$REG_PATH/.claude-plugin/plugin.json"
  if [ -f "$f" ] && grep -Eq '"name"[[:space:]]*:[[:space:]]*"open-steps"' "$f" 2>/dev/null \
      && root="$(cd "$REG_PATH" 2>/dev/null && pwd -P)" && [ -d "$root/skills" ]; then
    INSTALL="$root"
    # The key is the name the settings file records, marketplace included.
    PLUGIN_NAME="${REG_KEY%%@*}"
    MARKET="${REG_KEY#*@}"
    DECIDED="registry"
  else
    # The registry names a folder with no plugin in it. Searching on from here
    # would land on the clone and hide a broken install behind an ok.
    DECIDED="stale"
  fi
else
  DECIDED="search"
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
fi

# Codex is judged only where it is, and only once the pack is set up for it. A
# ~/.codex left behind by something else is not an install of this pack, and
# faulting on it would cry wolf. Half of the pack is a fault, because that
# silent gap is what this script hunts. The settings file counts once a hook
# it runs is this pack's, by its path and not by its name: a session-start.sh
# from some other pack does not make Codex an install of this one.
here=0
codex_hooks=""
if [ -d "$codex" ]; then
  mentions_pack "$agents" && here=1
  if [ -r "$cfg" ]; then
    codex_hooks="$(codex_kinds "$cfg")"
    printf '%s\n' "$codex_hooks" | grep -Eq "^(ours|example)"$'\t' && here=1
  fi
fi
# Gemini CLI and Cursor are set up for the pack when their routing block or
# their hooks file names it. Set up that way with no copy of the skills, the
# tool itself is the one to blame, and a Claude Code beside it with nothing of
# the pack is a fact.
gem_wired=0
if [ -d "$gem" ]; then
  mentions_pack "$gem/GEMINI.md" && gem_wired=1
  [ -r "$gem/settings.json" ] && grep -Eq 'adapter\.sh[^[:alnum:]]+gemini' "$gem/settings.json" && gem_wired=1
fi
cur_wired=0
[ -r "$cur/hooks.json" ] && grep -Eq 'adapter\.sh[^[:alnum:]]+cursor' "$cur/hooks.json" && cur_wired=1
# A copy in the shared folder counts as found for another tool only while a
# tool that reads that folder is here. With none of them, it is a copy nobody
# reads, and it must not excuse a Claude Code that is missing the plugin.
shared_read=0
if [ "$shared" -eq 1 ] && { [ -d "$codex" ] || [ -d "$cur" ] || [ -d "$gem" ]; }; then
  shared_read=1
fi
elsewhere=0
[ $((shared_read + codex_own + cur_own + gem_own + here + gem_wired + cur_wired)) -gt 0 ] && elsewhere=1

# Something of the pack in Claude Code's own files: an installed copy, a
# registry entry even when its folder is gone, an entry for the plugin in the
# settings file, or the routing block in CLAUDE.md.
ccpack=0
if [ "$CC" -eq 1 ]; then
  [ -n "$INSTALL" ] && ccpack=1
  [ "$DECIDED" = "stale" ] && ccpack=1
  [ -r "$stf" ] && grep -Eq '"open-steps@[^"]*"[[:space:]]*:' "$stf" && ccpack=1
  mentions_pack "$HOME/.claude/CLAUDE.md" && ccpack=1
fi
# Claude Code is judged the way Codex is: once its files hold something of the
# pack, or when the pack was found for no other tool, which leaves Claude Code
# the one place it could be. A Claude Code with none of it is a fact. CC is
# then 2.
if [ "$CC" -eq 1 ] && [ "$elsewhere" -eq 1 ] && [ "$ccpack" -eq 0 ]; then
  CC=2
  DECIDED="nopack"
fi

# 1: Codex's own files or its own skills folder hold the pack. 2: they do not,
# but the shared folder holds a copy, neither of the other two tools that read
# it is here, and the pack is not set up for Claude Code either, so that copy
# can be Codex's and nobody else's.
codex_judged=0
if [ -d "$codex" ]; then
  if [ "$here" -eq 1 ] || [ "$codex_own" -eq 1 ]; then
    codex_judged=1
  elif [ "$shared" -eq 1 ] && [ ! -d "$gem" ] && [ ! -d "$cur" ] && [ "$ccpack" -eq 0 ]; then
    codex_judged=2
  fi
fi

cc_skip() { # $1 the part, with its verb, as in "its hooks were"  $2 the part alone
  if [ "$CC" -eq 0 ]; then
    unknown "No sign of Claude Code was found, so $1 not checked."
  else
    fact "Nothing of the pack is set up for Claude Code, so there is nothing to judge in $2."
  fi
}

printf 'Open Steps install check\n'

section "Where the pack is installed"
case "$DECIDED" in
  registry) fact "Claude Code's plugin registry, installed_plugins.json, names the copy it runs: $REG_PATH." ;;
  stale)    fault "Claude Code's plugin registry, installed_plugins.json, names $REG_PATH as the installed copy, but there is no plugin there." 1 ;;
  absent)   unknown "No sign of Claude Code was found: no claude command on the PATH, no ~/.claude.json, and ~/.claude holds no plugins folder, settings file or CLAUDE.md. Its parts below were not checked." ;;
  nopack)   fact "Claude Code is here, and nothing of the pack is set up for it: no entry in its plugin registry, no copy in its plugin cache, no entry for the plugin in its settings file, and no routing block in ~/.claude/CLAUDE.md."
            fact "The pack was found for another tool, so Claude Code's parts below are not judged." ;;
  *)        fact "Claude Code's plugin registry, installed_plugins.json, has no entry for this pack, so the plugin cache was searched instead." ;;
esac
if [ -z "$INSTALL" ]; then
  case "$DECIDED" in
    stale|absent|nopack) ;;
    *) fault "No installed copy of the pack was found. Claude Code cannot see it." 1 ;;
  esac
  fact "This script is running from $PACK."
elif [ "$INSTALL" = "$PACK" ]; then
  fact "This script is running from the installed copy, at $INSTALL."
else
  fact "This script is running from a clone, not from the installed copy."
  fact "The clone is at $PACK."
  fact "The installed copy is at $INSTALL. Everything below reads that one."
  # Two versions on one machine are a fact about the update path, never a
  # fault: files reach the installed copy only when the version number moves.
  iv="$(manifest_version "$INSTALL/.claude-plugin/plugin.json")"
  cv="$(manifest_version "$PACK/.claude-plugin/plugin.json")"
  if [ -n "$iv" ] && [ -n "$cv" ] && [ "$iv" != "$cv" ]; then
    fact "The installed copy is version $iv and this clone is version $cv. Files move into the installed copy only when the version number changes: git pull, then claude plugin update open-steps@open-steps."
  fi
fi

# --- the skills -----------------------------------------------------------
section "Claude Code: the skills"
if [ "$CC" -ne 1 ]; then
  cc_skip "its skills were" "its skills"
elif [ -z "$INSTALL" ]; then
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
    elif header_sound "$f" "$name"; then
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
if [ "$CC" -ne 1 ]; then
  : # said once, in the line above
elif [ -z "$INSTALL" ]; then
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
# With "fact" in place of an area code, what would be judged is only reported.
bad()  { if [ "$2" = fact ]; then fact "$1"; else fault "$1" "$2"; fi; }
good() { if [ "$2" = fact ]; then fact "$1"; else ok "$1"; fi; }

routing_block() { # $1 file  $2 area code, or "fact"  $3 what to call the file
  local f="$1" area="$2" label="$3" missing="" name heading=0
  if [ ! -e "$f" ]; then
    bad "$label is not there, so the routing block is missing." "$area"
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
    bad "$label has no routing block. It does not name these skills:$missing" "$area"
  elif [ -n "$missing" ]; then
    bad "$label has a routing block, but it is cut short. Missing:$missing" "$area"
  elif [ "$heading" -eq 1 ]; then
    good "$label has the whole routing block. All ${#expected[@]} skills are named in it." "$area"
  else
    good "$label names all ${#expected[@]} skills. The pack's own heading is not there, so the wording is your own." "$area"
  fi
}

section "Claude Code: the routing block"
if [ "$CC" -ne 1 ]; then
  cc_skip "its instructions file was" "its instructions file"
else
  routing_block "$HOME/.claude/CLAUDE.md" 2 "Your Claude Code instructions file"
  unknown "Whether the agent obeys the block is not on disk. This only checked that the words are there."
fi

# --- the hooks ------------------------------------------------------------
section "Claude Code: the hooks"
if [ "$CC" -ne 1 ]; then
  cc_skip "its hooks were" "its hooks"
elif [ -z "$INSTALL" ]; then
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
      ok "The hook files session-start.sh, stop-report.sh and adapter.sh are marked runnable."
    fi
  fi

  fact "The hook file gives a path with a placeholder in it. Claude Code fills that in when it runs. This script does not."
  unknown "Whether Claude Code has connected the hooks to your sessions is not on disk. The sign is that no handover appears at the start of a session."
fi

# --- Codex ----------------------------------------------------------------
# The pack ships hooks/fingerprint.sh and hooks/hooks.json without the
# runnable mark on purpose, so either one is a free test of the disk a copy
# sits on. Marked runnable there, that disk hands out the mark by itself, as a
# checkout with core.filemode set to false does, and the mark proves nothing
# about the files that need it.
mark_means() { # $1 hooks folder -> yes, no when the disk marks every file, or none when no file there can tell
  local probe seen=0
  for probe in "$1/fingerprint.sh" "$1/hooks.json"; do
    [ -r "$probe" ] || continue
    seen=1
    [ -x "$probe" ] || { printf 'yes'; return 0; }
  done
  if [ "$seen" -eq 1 ]; then printf 'no'; else printf 'none'; fi
}

runs_direct() { # $1 file a tool runs directly  $2 the tool's name  $3 when it runs, or nothing
  local when="" name
  [ -n "$3" ] && when=" at $3"
  name="$(basename "$1")"
  case "$(mark_means "$(dirname "$1")")" in
    yes)
      if [ -x "$1" ]; then
        ok "$2 runs $name directly$when, and the file is marked runnable: $1"
      else
        fault "$2 runs $name directly$when, but the file is not marked runnable, so it will not start: $1" 3
      fi ;;
    no)  unknown "Whether $1 can run was not checked. This disk marks files runnable on its own." ;;
    *)   unknown "Whether $1 can run was not checked. No file beside it says whether this disk marks files runnable on its own." ;;
  esac
}

# A hook in the Codex settings that is not this pack's still gets its line:
# a file of the same name from some other pack, a command that is not a path,
# and a path this script cannot follow are facts about the settings file,
# whoever the install is for.
codex_hook_aside() { # $1 kind  $2 file, or the command  $3 when it runs
  case "$1" in
    other)   fact "The Codex settings also run $2 at $3. That is not a file of this pack, and it was not judged." ;;
    foreign) fact "The Codex settings run a file called $(basename "$2") at $3 that is not this pack's: $2. A hook of this pack sits in the hooks folder of a copy that also holds the skills." ;;
    gone)    unknown "Whether the file the Codex settings run at $3 was this pack's was not checked. It is not there: $2" ;;
    partial) unknown "The Codex settings give a path that is not a full path for $3, so whether that file is there was not checked: $2" ;;
  esac
}

codex_other_hooks() {
  local kind file direct ev
  [ -n "$codex_hooks" ] || return 0
  while IFS="$(printf '\t')" read -r kind file direct ev; do
    [ -n "$kind" ] || continue
    codex_hook_aside "$kind" "$file" "$ev"
  done <<<"$codex_hooks"
}

and_list() { # names -> "a", "a and b", "a, b and c"
  local out="" i=1 n
  for n in "$@"; do
    if [ "$i" -eq 1 ]; then
      out="$n"
    elif [ "$i" -eq "$#" ]; then
      out="$out and $n"
    else
      out="$out, $n"
    fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

skill_copy() { # $1 folder  $2 what to call it  $3 1 when Codex reads it  $4 the other tools that read it
  local dir="$1" label="$2" codex_reads="$3" others="$4" name missing="" linked="" broken="" bare="" n=0 sub
  for name in "${expected[@]}"; do
    if [ ! -r "$dir/$name/SKILL.md" ]; then
      missing="$missing $name"
      continue
    fi
    # A shortcut instead of a copy renames the skill. Codex takes the name
    # from the folder it lands in, so the routing block ends up pointing at
    # names that no longer exist.
    if [ -L "$dir/$name" ]; then
      linked="$linked $name"
    else
      n=$((n + 1))
    fi
    # A broken header makes a skill fail without a word, as in the Claude Code
    # part above. The folder is still there, so counting folders passes on it.
    header_sound "$dir/$name/SKILL.md" "$name" || broken="$broken $name"
    # Some skills read a file from a references or scripts folder of their own
    # while they run. A copy of the SKILL.md files alone leaves them nothing
    # to read.
    for sub in references scripts; do
      if [ -d "$PACK/skills/$name/$sub" ] && [ ! -d "$dir/$name/$sub" ]; then
        case " $bare " in *" $name "*) ;; *) bare="$bare $name" ;; esac
      fi
    done
  done
  [ -n "$missing" ] && fault "Part of the pack is in $label, but these skills are not:$missing" 1
  [ -n "$broken" ] && fault "These skill files in $label have a broken header, so the agent skips them:$broken" 1
  [ -n "$bare" ] && fault "These skills in $label were copied without the folders they need:$bare" 1
  # Blamed on Codex only while Codex is judged. A ~/.codex with nothing of the
  # pack in it, next to another tool that reads the folder, is not the reader
  # the copy was made for.
  if [ -n "$linked" ] && [ "$codex_reads" -eq 1 ] && [ "$codex_judged" -ne 0 ]; then
    fault "These skills in $label are shortcuts, not copies, so Codex gives them other names:$linked" 1
  elif [ -n "$linked" ]; then
    if [ "$codex_reads" -eq 1 ] && [ -d "$codex" ]; then
      fact "These skills in $label are shortcuts, not copies:$linked. Codex would give them other names, but the copy is not taken for a Codex install; the Codex part below says why."
    elif [ "$codex_reads" -eq 1 ]; then
      fact "These skills in $label are shortcuts, not copies:$linked. Codex would give them other names, and there is no $codex folder."
    else
      fact "These skills in $label are shortcuts, not copies:$linked."
    fi
    unknown "What $others do with a shortcut was not checked."
  fi
  if [ -z "$missing" ] && [ -z "$linked" ] && [ -z "$broken" ] && [ -z "$bare" ]; then
    if [ "$dir" = "$sdir" ]; then
      ok "All $n skills are copied into the shared skills folder, with sound headers and the folders they need."
    else
      ok "The pack's $n skills are copied into $label, with sound headers and the folders they need."
    fi
  fi
}

section "The skills folders of Codex, Cursor and Gemini CLI"
if [ "$CC" -eq 0 ]; then
  fact "$sdir is the shared skills folder, read by Codex, Cursor and Gemini CLI."
else
  fact "$sdir is the shared skills folder, read by Codex, Cursor and Gemini CLI. Claude Code does not read it; it runs the plugin's copy."
fi
fact "Each of those tools also reads a folder of its own, and this script looked in those three too: $codex/skills, $cur/skills and $gem/skills."
if [ "${#expected[@]}" -eq 0 ]; then
  unknown "This script could not read the pack's own list of skills, so these folders were not checked."
elif [ "$CC" -eq 0 ] && [ "$elsewhere" -eq 0 ]; then
  # With no sign of Claude Code either, nothing below would judge anything,
  # and a machine without the pack would read as sound. A shared copy is a
  # different case: a tool this script does not know may read that folder, so
  # the copy is checked, and who reads it is not.
  if [ "$shared" -eq 1 ]; then
    unknown "The pack's skills are in $sdir, but none of the tools this script knows reads them here: there is no $codex, $cur or $gem folder, and no sign of Claude Code. Another tool that reads that folder may be using the copy."
    skill_copy "$sdir" "the shared skills folder" 1 "Cursor and Gemini CLI"
  else
    fault "No copy of the pack was found for any tool. None of its skills are in $sdir, $codex/skills, $cur/skills or $gem/skills, and there is no sign of Claude Code." 1
  fi
elif [ $((shared + codex_own + cur_own + gem_own)) -eq 0 ]; then
  fact "No skills from this pack are in these four folders."
else
  if [ "$shared" -eq 1 ]; then
    skill_copy "$sdir" "the shared skills folder" 1 "Cursor and Gemini CLI"
    readers=()
    [ -d "$codex" ] && readers+=("Codex")
    [ -d "$cur" ] && readers+=("Cursor")
    [ -d "$gem" ] && readers+=("Gemini CLI")
    if [ "${#readers[@]}" -eq 0 ]; then
      fact "None of Codex, Cursor or Gemini CLI was found on this machine: there is no $codex, $cur or $gem folder. No tool this script knows reads the shared copy."
    else
      fact "Of the tools that read the shared skills folder, this machine has $(and_list "${readers[@]}")."
    fi
  else
    fact "No skills from this pack are in the shared skills folder."
  fi
  [ "$codex_own" -eq 1 ] && skill_copy "$codex/skills" "Codex's own skills folder, $codex/skills" 1 "Cursor"
  [ "$cur_own" -eq 1 ] && skill_copy "$cur/skills" "Cursor's own skills folder, $cur/skills" 0 "Cursor"
  [ "$gem_own" -eq 1 ] && skill_copy "$gem/skills" "Gemini CLI's own skills folder, $gem/skills" 0 "Gemini CLI"
fi

section "Codex"
if [ ! -d "$codex" ]; then
  fact "Codex was not found: there is no $codex folder. There is nothing to check for it."
elif [ "$codex_judged" -eq 0 ] && [ "$shared" -eq 1 ]; then
  others=()
  [ -d "$cur" ] && others+=("Cursor")
  [ -d "$gem" ] && others+=("Gemini CLI")
  if [ "${#others[@]}" -gt 0 ]; then
    fact "Codex shares the copy in the shared skills folder with $(and_list "${others[@]}"), so the copy is not taken for a Codex install. Neither $agents nor $cfg mentions the pack, so Codex has no routing block or hooks from it; docs/other-agents.md shows both."
  else
    fact "The copy in the shared skills folder may be for Codex, but the pack is set up for Claude Code, so the copy is not taken for a Codex install. Neither $agents nor $cfg mentions the pack, so Codex has no routing block or hooks from it; docs/other-agents.md shows both."
  fi
  codex_other_hooks
elif [ "$codex_judged" -eq 0 ]; then
  fact "Nothing from this pack is set up for Codex. There is nothing to check."
  codex_other_hooks
else
  if [ "$codex_judged" -eq 2 ]; then
    fact "There is no $gem or $cur folder, so of the three tools that read the shared skills folder, Codex is the one here. The copy there is taken for a Codex install, and Codex is checked in full."
  fi
  if [ "$shared" -eq 0 ] && [ "$codex_own" -eq 0 ] && [ "${#expected[@]}" -gt 0 ]; then
    fault "Codex is set up for this pack, but none of its skills are in the shared skills folder or in $codex/skills, so Codex has none of them." 1
  fi

  routing_block "$agents" 2 "Your Codex instructions file"

  if [ ! -e "$cfg" ]; then
    fault "Codex has no settings file, so its hooks are not set up." 3
  elif [ ! -r "$cfg" ]; then
    unknown "The Codex settings file cannot be read."
  else
    # Each event needs a table in the file and, in it, a hook that runs one of
    # this pack's files. A table with only other hooks in it is the same gap
    # as no table. A path this script cannot follow is neither a hook of the
    # pack nor a gap, so it holds the judgement back.
    has_start=0; grep -Eq '^\[\[hooks\.session_start' "$cfg" && has_start=1
    has_stop=0;  grep -Eq '^\[\[hooks\.stop' "$cfg" && has_stop=1
    ours_start=0; ours_stop=0; open_start=0; open_stop=0
    while IFS="$(printf '\t')" read -r kind file direct ev; do
      [ -n "$kind" ] || continue
      case "$kind" in
        ours|example|gone)
          if [ "$ev" = "the start of a session" ]; then ours_start=1; else ours_stop=1; fi ;;
        partial)
          if [ "$ev" = "the start of a session" ]; then open_start=1; else open_stop=1; fi ;;
      esac
    done <<<"$codex_hooks"
    cmiss=""
    [ "$has_start" -eq 1 ] || cmiss="the start of a session"
    [ "$has_stop" -eq 1 ] || cmiss="${cmiss:+$cmiss and }the end of a session"
    none=""
    [ "$has_start" -eq 1 ] && [ "$ours_start" -eq 0 ] && [ "$open_start" -eq 0 ] && none="the start of a session"
    [ "$has_stop" -eq 1 ] && [ "$ours_stop" -eq 0 ] && [ "$open_stop" -eq 0 ] && none="${none:+$none and }the end of a session"
    [ -n "$cmiss" ] && fault "The Codex settings file sets up no hook for $cmiss." 3
    [ -n "$none" ] && fault "The Codex settings file sets up a hook for $none, but it runs none of this pack's files there." 3
    if [ -z "$cmiss" ] && [ -z "$none" ]; then
      ok "The Codex settings file sets up a hook at the start and at the end of a session."
    fi
    # The block in the documentation ships an example path. Pasted unchanged it
    # reads as correct and points at nothing, so every path gets looked up.
    # Codex runs each file directly, so the file needs the runnable mark, and
    # both files read fingerprint.sh from their own folder.
    fpdirs=""
    while IFS="$(printf '\t')" read -r kind file direct ev; do
      [ -n "$kind" ] || continue
      case "$kind" in
        example)
          fault "The Codex settings still hold the example path for $ev. Put your own path there." 3 ;;
        gone)
          fault "Codex runs a file that is not there at $ev: $file" 3 ;;
        ours)
          if [ ! -f "$file" ]; then
            fault "Codex runs a file that is not there at $ev: $file" 3
            continue
          fi
          ok "The file Codex runs at $ev is there."
          if [ "$direct" -eq 1 ]; then
            runs_direct "$file" "Codex" "$ev"
          elif [ ! -x "$file" ]; then
            fact "The Codex settings run $(basename "$file") through a shell, so the file needs no runnable mark. It has none: $file"
          fi
          d="$(dirname "$file")"
          case " $fpdirs " in *" $d "*) continue ;; esac
          fpdirs="$fpdirs $d"
          if [ -e "$d/fingerprint.sh" ]; then
            ok "The file both hooks read, fingerprint.sh, is beside them in $d."
          else
            fault "The file Codex runs at $ev reads fingerprint.sh from its own folder, and that file is missing: $d/fingerprint.sh" 3
          fi ;;
        *) codex_hook_aside "$kind" "$file" "$ev" ;;
      esac
    done <<<"$codex_hooks"
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
if [ "$CC" -ne 1 ]; then
  cc_skip "its writing style was" "its writing style"
elif [ ! -e "$st" ]; then
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
[ "$CC" -eq 1 ] && unknown "A writing style can be set elsewhere too. This only read the settings file."

# --- Gemini CLI and Cursor ------------------------------------------------
# Their routing block and the hook commands they name are reported, not judged.
# Both run the hooks through hooks/adapter.sh, wired by hand as
# docs/other-agents.md shows, and this says nothing about whether the tool runs
# them. Four things about each command are judged. The path in front of
# adapter.sh, the way the Codex paths are: the documentation ships an example
# path, and pasted unchanged it reads as wired and points at nothing. The event
# the command sits under: on Gemini CLI a stop under SessionEnd runs and never
# asks, and Cursor's event names are case-sensitive. The files adapter.sh runs
# and reads from its own folder. And the runnable mark, when the command runs
# adapter.sh directly instead of through a shell.

# One pass over the file, flattened to a line, reading each JSON string in
# turn. A string followed by a colon is a key; an opening bracket pushes the
# last key seen, a closing one pops it. The string that holds the adapter
# command is reported with the nearest key above it that is not "hooks", which
# is the event. Pretty-printed or on one line reads the same.
adapter_entry() { # $1 hooks file  $2 tool as the adapter names it  $3 hook -> "event<tab>command", "-" for no event, or nothing
  tr -d '\n\r' < "$1" | awk -v tool="$2" -v hook="$3" '
    BEGIN { re = "adapter\\.sh[^A-Za-z0-9]+" tool "[^A-Za-z0-9]+" hook }
    {
      n = length($0); i = 1; depth = 0; key = ""
      while (i <= n) {
        c = substr($0, i, 1)
        if (c == "\"") {
          lit = ""; j = i + 1
          while (j <= n) {
            d = substr($0, j, 1)
            if (d == "\\") { lit = lit substr($0, j + 1, 1); j += 2; continue }
            if (d == "\"") break
            lit = lit d; j++
          }
          k = j + 1
          while (k <= n && substr($0, k, 1) ~ /[ \t]/) k++
          if (substr($0, k, 1) == ":") {
            key = lit
          } else {
            if (lit ~ re) {
              ev = "-"
              for (l = depth; l >= 1; l--) {
                if (stack[l] != "" && stack[l] != "hooks") { ev = stack[l]; break }
              }
              print ev "\t" lit
              exit
            }
            key = ""
          }
          i = j + 1
          continue
        }
        if (c == "[" || c == "{") { depth++; stack[depth] = key; key = ""; i++; continue }
        if (c == "]" || c == "}") { if (depth > 0) depth--; key = ""; i++; continue }
        if (c == ":" || c == " " || c == "\t") { i++; continue }
        key = ""; i++
      }
    }'
}

adapter_token() { # $1 command -> the word in it that ends in adapter.sh, as written
  printf '%s\n' "$1" | grep -oE "[^\"' ]*adapter\.sh" | head -1
}

plain_path() { # $1 path as written -> with forward slashes, one between each part
  # Windows records backslashes, doubled inside JSON.
  # shellcheck disable=SC1003  # tr wants the backslash doubled, not quoted
  printf '%s\n' "$1" | tr '\\' '/' | sed -E 's|/{2,}|/|g'
}

direct_run() { # $1 command  $2 the adapter word in it -> true when the command starts with that word, with no shell in front
  local cmd="$1"
  cmd="${cmd#"${cmd%%[! ]*}"}"
  case "$cmd" in "$2"*) return 0 ;; esac
  return 1
}

hook_path() { # $1 hooks file  $2 tool as the adapter names it  $3 the tool's name  $4 hook  $5 when it runs  $6 path
  [ -n "$6" ] || return 0
  case "$(path_state "$6")" in
    example) fault "$1 still holds the example path for adapter.sh $2 $4. Put your own path there." 3 ;;
    here)    ok "The file $3 runs at $5 is there." ;;
    gone)    fault "$3 runs a file that is not there at $5: $6" 3 ;;
    *)       unknown "$1 gives adapter.sh $2 $4 a path that is not a full path, so whether that file is there was not checked: $6" ;;
  esac
}

hook_event() { # $1 hooks file  $2 tool as the adapter names it  $3 the tool's name  $4 hook  $5 event found, "-" for none  $6 event it needs
  if [ "$5" = "-" ]; then
    fault "$1 names adapter.sh $2 $4 under no event, so $3 never runs it." 3
  elif [ "$5" != "$6" ] && [ "$4" = stop ]; then
    fault "$1 puts adapter.sh $2 stop under the $5 event, not under $6. A report is never asked for from there." 3
  elif [ "$5" != "$6" ]; then
    fault "$1 puts adapter.sh $2 session-start under the $5 event, not under $6. The handover never reaches the agent from there." 3
  fi
}

adapter_runs() { # $1 hooks file  $2 the tool's name  $3 adapter path  $4 1 when a command runs it directly
  local dir miss="" s
  [ "$(path_state "$3")" = here ] || return 0
  dir="$(dirname "$3")"
  for s in session-start.sh stop-report.sh fingerprint.sh; do
    [ -e "$dir/$s" ] || miss="$miss $s"
  done
  if [ -n "$miss" ]; then
    fault "adapter.sh runs session-start.sh and stop-report.sh from its own folder, and both read fingerprint.sh there. These are missing from $dir:$miss" 3
  else
    ok "The files adapter.sh needs are beside it in $dir: session-start.sh, stop-report.sh and fingerprint.sh."
  fi
  if [ "$4" -eq 1 ]; then
    runs_direct "$3" "$2" ""
  elif [ ! -x "$3" ]; then
    fact "$1 runs adapter.sh through a shell, so the file needs no runnable mark. It has none: $3"
  fi
}

hooks_fact() { # $1 hooks file  $2 tool as the adapter names it  $3 the tool's name  $4 event the start needs  $5 event the stop needs  $6 what the fact adds when both are wired
  local f="$1" t="$2" tool="$3" ws="$4" we="$5" note="$6"
  local entry miss="" named=0 bad=0 wrong=0 es="" ee="" ps="" pe="" ts="" te="" ds=0 de=0 p
  if [ ! -e "$f" ]; then
    fact "$f is not there, so no hooks from this pack are wired in it."
    return
  fi
  if [ ! -r "$f" ]; then
    unknown "$f cannot be read, so its hooks were not checked."
    return
  fi
  entry="$(adapter_entry "$f" "$t" session-start)"
  if [ -n "$entry" ]; then
    es="${entry%%$'\t'*}"
    ts="$(adapter_token "${entry#*$'\t'}")"
    ps="$(plain_path "$ts")"
    direct_run "${entry#*$'\t'}" "$ts" && ds=1
  fi
  entry="$(adapter_entry "$f" "$t" stop)"
  if [ -n "$entry" ]; then
    ee="${entry%%$'\t'*}"
    te="$(adapter_token "${entry#*$'\t'}")"
    pe="$(plain_path "$te")"
    direct_run "${entry#*$'\t'}" "$te" && de=1
  fi
  for p in "$ps" "$pe"; do
    [ -n "$p" ] || continue
    named=1
    case "$(path_state "$p")" in example|gone) bad=1 ;; esac
  done
  [ -n "$ps" ] || miss="$miss adapter.sh $t session-start,"
  [ -n "$pe" ] || miss="$miss adapter.sh $t stop,"
  [ -n "$ps" ] && [ "$es" != "$ws" ] && wrong=1
  [ -n "$pe" ] && [ "$ee" != "$we" ] && wrong=1
  [ "$wrong" -eq 1 ] && bad=1
  if [ "$named" -eq 0 ]; then
    fact "$f wires no hooks from this pack."
  elif [ -n "$miss" ]; then
    fact "$f wires part of the hooks. It does not name:${miss%,}."
  elif [ "$bad" -eq 0 ]; then
    fact "$f names both hook commands, adapter.sh $t session-start and adapter.sh $t stop$note."
  fi
  [ -n "$ps" ] && hook_event "$f" "$t" "$tool" session-start "$es" "$ws"
  [ -n "$pe" ] && hook_event "$f" "$t" "$tool" stop "$ee" "$we"
  if [ "$wrong" -eq 0 ] && [ -n "$ps" ] && [ -n "$pe" ]; then
    ok "Each hook command in $f sits under the event it needs: adapter.sh $t session-start under $ws, adapter.sh $t stop under $we."
  elif [ "$wrong" -eq 0 ] && [ -n "$ps" ]; then
    ok "The hook command in $f, adapter.sh $t session-start, sits under the event it needs, $ws."
  elif [ "$wrong" -eq 0 ] && [ -n "$pe" ]; then
    ok "The hook command in $f, adapter.sh $t stop, sits under the event it needs, $we."
  fi
  hook_path "$f" "$t" "$tool" session-start "the start of a session" "$ps"
  hook_path "$f" "$t" "$tool" stop "the end of a session" "$pe"
  # The adapter itself, once per file the commands name.
  if [ -n "$ps" ] && [ "$ps" = "$pe" ]; then
    [ "$de" -eq 1 ] && ds=1
    adapter_runs "$f" "$tool" "$ps" "$ds"
  else
    [ -n "$ps" ] && adapter_runs "$f" "$tool" "$ps" "$ds"
    [ -n "$pe" ] && adapter_runs "$f" "$tool" "$pe" "$de"
  fi
}

section "Gemini CLI"
if [ ! -d "$gem" ]; then
  fact "Gemini CLI was not found: there is no $gem folder. There is nothing to check for it."
else
  # Set up for the pack and holding none of its skills, Gemini CLI is the tool
  # to blame, the way Codex is above.
  if [ "$gem_wired" -eq 1 ] && [ "$shared" -eq 0 ] && [ "$gem_own" -eq 0 ] && [ "${#expected[@]}" -gt 0 ]; then
    fault "Gemini CLI is set up for this pack, but none of its skills are in the shared skills folder, $sdir, or in $gem/skills, so Gemini CLI has none of them." 1
  fi
  routing_block "$gem/GEMINI.md" fact "Your Gemini CLI instructions file"
  hooks_fact "$gem/settings.json" gemini "Gemini CLI" SessionStart AfterAgent ", and the AfterAgent event the stop needs"
fi

section "Cursor"
if [ ! -d "$cur" ]; then
  fact "Cursor was not found: there is no $cur folder. There is nothing to check for it."
else
  if [ "$cur_wired" -eq 1 ] && [ "$shared" -eq 0 ] && [ "$cur_own" -eq 0 ] && [ "${#expected[@]}" -gt 0 ]; then
    fault "Cursor is set up for this pack, but none of its skills are in the shared skills folder, $sdir, or in $cur/skills, so Cursor has none of them." 1
  fi
  hooks_fact "$cur/hooks.json" cursor "Cursor" sessionStart stop ""
  unknown "Cursor reads the routing block from AGENTS.md in each project, and can wire hooks per project too. Neither was checked here."
fi

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
