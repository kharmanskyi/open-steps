---
description: >-
  Runs the Open Steps install check and reads the result back in plain words.
  Use it after installing the pack, when a report never appears, or when
  someone asks whether the install is sound. The script does the checking and
  sets the exit code. This command reports what the script printed and nothing
  else.
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/doctor.sh")'
---

# os-install-check

One job. Run the script, then say what it found. The script holds the truth.
This command adds nothing to it and takes nothing away.

## Language

The language the user speaks in this session, detected from the conversation.
Translate every label. File names, paths and setting names stay as they are.

## Step 1: run the script

```bash
bash "${CLAUDE_PLUGIN_ROOT}/doctor.sh"
```

Keep the exit code. The last line of the report needs it.

If the script does not run at all, say so and stop there. Never describe a
result you did not see.

## Step 2: read the result back

The script prints one label at the start of every line. Keep the four apart.

| Label | What it means | How to report it |
|---|---|---|
| `ok` | It looked, and the thing is right | Good news |
| `FAULT` | It looked, and the thing is wrong | Bad news, in full |
| `not checked` | It could not look | Neither. Say nobody looked |
| `fact` | It looked, and there is nothing to judge | Neither. Just say it |

Open with one sentence. The install is sound, or it is not. Take that from the
exit code, not from your reading of the lines.

Then up to three lists, in this order. Drop any list that is empty.

1. **What is wrong.** Every `FAULT` line. One line each, in the script's own
   words.
2. **What nobody looked at.** Every `not checked` line. Say plainly that it was
   not checked.
3. **What is in place.** Every `ok` line. Group them when there are many.

Add the `fact` lines where they help the reader. They are neither good news nor
bad.

Close with the exit code and what it means:

```
0  no fault found
1  the skills
2  the routing block
3  the hooks
4  the kill switches
9  faults in more than one of those
```

## Hard rules: these rules *are* the command

1. Report what the script printed. Add nothing to it.
2. Never soften a fault. A fault is reported in full, in its own line.
3. Never turn a "not checked" into a yes. Never turn it into a no either.
4. Never call the install sound while the exit code is not zero.
5. Decide nothing. Judge nothing. The script already did both.
6. Asked what to do next, repeat what the fault line says and stop there.
