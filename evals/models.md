# Model tiers

The one place a model tier is named. `score.py` reads this file for the
display names and the column order in `results.md`, so a new tier is one row
here and no code.

Row order is the column order: cheapest first, the way the table reads. That
is a stated rule of the table, not an accident of whichever run finished
first, which is why the order lives in a file a person edits rather than in
whatever the folder happens to hold.

A model that matches no row still scores. Its column is labelled by the id
the stream carries, so nothing is dropped, it just has no short name yet.

A stream from another tool carries that tool's name in front of the model,
`gemini-cli:gemini-2.5-pro`, and its row here does the same. A row without a
prefix is Claude Code's own and never fits a prefixed stream, so a Claude
model run through another tool shows under its raw `agent:model` label until
it gets a row of its own.

Two rules if you edit the table. No `|` inside a cell, it splits the cell.
And a row fits a stream when its text is anywhere in the model id, and the
first row that fits wins. So a newer id that contains an older one goes
directly above it: `claude-opus-5-5` contains `claude-opus-5`, and below that
row Opus 5.5 would be shown as Opus 5. A tier that is no longer measured
keeps its row, so an older day still scores under its own names.

## Tiers

| Matches | Shown as |
|---|---|
| claude-haiku-4-5 | Haiku 4.5 |
| claude-sonnet-5-5 | Sonnet 5.5 |
| claude-sonnet-5 | Sonnet 5 |
| claude-opus-5-5 | Opus 5.5 |
| claude-opus-5 | Opus 5 |
| codex:gpt-6-sol | GPT-6 Sol (Codex) |
| gemini-cli:gemini-3.5-flash-lite | Gemini 3.5 Flash Lite (Gemini CLI) |
| cursor:Auto | Cursor (Auto) |
