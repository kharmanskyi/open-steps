#!/usr/bin/env python3
"""Score one day of Open Steps measurements. No AI judging anywhere.

    python3 evals/score.py --print ~/.claude/open-steps/evals/2026-08-24
    python3 evals/score.py ~/.claude/open-steps/evals/2026-08-24
    python3 evals/score.py --readme ~/.claude/open-steps/evals/2026-08-24

The first prints the table, the second also writes it to evals/results.md, the
third also rewrites the summary table in the main README, dated with the day
it came from. That last one is a flag and not a side effect because partial
days and foreign branches get scored all the time, and none of them belong on
the front page by accident. The transcripts sit outside the repository, one folder per day, holding every model
that ran that day. Which model a stream came from is read out of the stream
itself, so a renamed file cannot mislabel a column. Activation comes from the
tool-call log, report quality from plain string rules. The phrases come from
evals/cases.md.
"""
import json, pathlib, re, sys, collections

HERE = pathlib.Path(__file__).resolve().parent
CASES = HERE / "cases.md"
MODELS = HERE / "models.md"
README = HERE.parent / "README.md"
MARK_A = "<!-- numbers: score.py writes this table, edit the prose but not these rows -->"
MARK_B = "<!-- numbers: end -->"
HASH = re.compile(r"\b[0-9a-f]{7,40}\b")
JARGON = re.compile(r"\b(p95|TTL|JWT|middleware|lockfile|CVE|e2e|env drift|CDN)\b", re.I)
MARKERS = ("-act-", "-neg-", "-qual-")


def table(section, path=CASES):
    """The data rows of one markdown table in a file, as lists of cells."""
    rows, insec, seen = [], False, 0
    for line in path.read_text().splitlines():
        if line.startswith("## "):
            insec, seen = line == "## " + section, 0
            continue
        if not insec or not line.startswith("|"):
            continue
        seen += 1
        if seen > 2:  # first two rows are the header and its dashes
            rows.append([c.strip() for c in line.strip().strip("|").split("|")])
    return rows


def events(path):
    for line in path.read_text(errors="replace").splitlines():
        try:
            yield json.loads(line)
        except Exception:
            continue


def stream_model(path):
    for d in events(path):
        if d.get("type") == "system" and d.get("subtype") == "init":
            return d.get("model", "")
    return ""


def skill_calls(path):
    out = []
    for d in events(path):
        # A denied tool call is a system event whose "message" is a sentence,
        # not an object: {"subtype": "permission_denied", "tool_name": "Skill",
        # "message": "Execute skill: ..."}. Reading .content off a string
        # raises, and one such line ends the whole day's scoring.
        msg = d.get("message")
        if not isinstance(msg, dict):
            continue
        for b in msg.get("content") or []:
            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Skill":
                # A plugin install invokes a skill as `open-steps:os-done-or-not`;
                # a folder install says `os-done-or-not`. Score the name, not the
                # prefix, or every hit through the plugin counts as a miss.
                out.append(((b.get("input") or {}).get("skill", "")).split(":")[-1])
    return out


def quality(path):
    text = ""
    for d in events(path):
        if d.get("type") == "result":
            text = d.get("result") or ""
    return {
        "verdict": bool(re.search(r"fully done|safe to close", text, re.I)),
        "warn_row": "⚠" in text,
        "lines": len([l for l in text.splitlines() if l.strip()]),
        "hashes": len(HASH.findall(text)),
        "jargon": len(JARGON.findall(text)),
    }


# The tiers live in models.md, one row per tier, cheapest first. Row order is
# the column order. A missing file means an empty registry, and every model
# then shows under the id its stream carries, which is honest rather than fatal.
TIERS = [r for r in table("Tiers", MODELS)] if MODELS.exists() else []


def label(model):
    for match, shown in TIERS:
        if match in model:
            return shown
    return model


def rank(model):
    for i, (match, _) in enumerate(TIERS):
        if match in model:
            return (i, model)
    # After every registry row. With no rows at all there is no cheapest to
    # be last behind, so every model is unknown and its id decides the order.
    return (len(TIERS), model)


def read_day(folder):
    """Group every stream in the folder under the model that produced it."""
    files = sorted(folder.glob("*.jsonl"))
    found = {f: stream_model(f) for f in files}
    known = sorted({m for m in found.values() if m})

    def group(f):
        if found[f]:
            return found[f]
        # A run that died before it started has no model line in it. Route it by
        # the prefix run.sh put on the file, so a whole failed arm shows up as
        # misses instead of quietly disappearing from the count.
        tag = f.stem
        for marker in MARKERS:
            tag = tag.split(marker)[0]
        for m in known:
            if tag and tag in m:
                return m
        return tag or "unknown"

    runs = {}
    for f in files:
        r = runs.setdefault(group(f), {
            "phrase": collections.defaultdict(lambda: [0, 0]),
            "skill": collections.defaultdict(lambda: [0, 0, 0]),
            "neg": [0, 0],
            "qual": {"with": [], "without": []},
        })
        m = re.search(r"act-(\d+)-(os-[a-z-]+)-r\d+$", f.stem)
        if m:
            idx, want = int(m.group(1)), m.group(2)
            fired = skill_calls(f)
            hit = 1 if want in fired else 0
            r["phrase"][idx][0] += hit
            r["phrase"][idx][1] += 1
            r["skill"][want][0] += hit
            r["skill"][want][1] += 1
            r["skill"][want][2] += sum(1 for s in fired if s != want)
        elif re.search(r"neg-\d+-r\d+$", f.stem):
            r["neg"][1] += 1
            if skill_calls(f):
                r["neg"][0] += 1
        elif "qual-" in f.stem:
            r["qual"]["with" if "-with-" in f.stem else "without"].append(quality(f))
    return runs


def avg(rows, k):
    return sum(r[k] for r in rows) / max(len(rows), 1)


def pct(rows, k):
    return 100 * sum(1 for r in rows if r[k]) / max(len(rows), 1)


def ordered_skills(runs):
    """Skills in the order cases.md tests them, not alphabetical."""
    order, seen = [], set()
    for row in table("Should fire"):
        if row[0] not in seen:
            seen.add(row[0])
            order.append(row[0])
    tested = {s for r in runs.values() for s in r["skill"]}
    return [s for s in order if s in tested] + sorted(tested - seen)


def readme_table(runs):
    """The summary table the main README shows. Best skill first and the
    misses last, because the prose under it reads the misses as the important
    part. Ties are broken by the order cases.md tests the skills, so the sort
    is a stated rule, not an accident of the run."""
    models = sorted(runs, key=rank)
    cols = [runs[m] for m in models]
    head = " | ".join(label(m) for m in models)
    order = ordered_skills(runs)

    def hits(s):
        return sum(r["skill"].get(s, [0, 0, 0])[0] for r in cols)

    out = [f"| Skill | {head} |", "|" + "---|" * (len(cols) + 1)]
    for s in sorted(order, key=lambda s: (-hits(s), order.index(s))):
        cells = " | ".join(f"{r['skill'].get(s, [0, 0, 0])[0]}/{r['skill'].get(s, [0, 0, 0])[1]}" for r in cols)
        out.append(f"| `{s}` | {cells} |")
    phrases = len({i for r in cols for i in r["phrase"]})
    tot = []
    for r in cols:
        h = sum(v[0] for v in r["skill"].values())
        n = sum(v[1] for v in r["skill"].values())
        tot.append(f"**{100 * h // max(n, 1)}%**")
    out.append(f"| **All {phrases} phrases** | " + " | ".join(tot) + " |")
    out.append("| Fired on an off-topic question | "
               + " | ".join(f"{r['neg'][0]}/{r['neg'][1]}" for r in cols) + " |")
    return "\n".join(out)


def update_readme(folder, runs):
    """Rewrite the summary table in the main README, between its two markers,
    with the day it was measured on written above it, so a number can never
    wear the prose's date. Only that block: the prose and the figure around it
    belong to a person. No markers means no touch and a word about it, never a
    guess at where the table was supposed to go."""
    if not README.exists():
        return "README.md not found, left alone"
    text = README.read_text()
    if MARK_A not in text or MARK_B not in text:
        return "README.md has no table markers, left alone"
    a = text.index(MARK_A) + len(MARK_A)
    b = text.index(MARK_B)
    block = f"Measured on {folder.name}.\n\n" + readme_table(runs)
    new = text[:a] + "\n\n" + block + "\n\n" + text[b:]
    if new == text:
        return f"README.md already matches {folder.name}"
    README.write_text(new)
    return f"wrote the summary table into README.md, dated {folder.name}. The prose around it is not touched"


def report(folder, runs):
    """The whole day as one page: per skill, per phrase, then the quality arms."""
    models = sorted(runs, key=rank)
    cols = [runs[m] for m in models]
    head = " | ".join(label(m) for m in models)
    per = max((v[1] for r in cols for v in r["phrase"].values()), default=0)
    out = ["# Measured results", "",
           "Written by `score.py` from the raw streams, so no number here is typed",
           "by hand. The phrases are in [`cases.md`](cases.md).", "",
           f"Day `{folder.name}`, models {', '.join(label(m) for m in models)}. "
           f"Every phrase asked {per} times per model.", "",
           "## Did the right skill switch on by itself", "",
           f"| Skill | {head} |", "|" + "---|" * (len(cols) + 1)]
    for s in ordered_skills(runs):
        cells = " | ".join(f"{r['skill'].get(s, [0, 0, 0])[0]}/{r['skill'].get(s, [0, 0, 0])[1]}" for r in cols)
        out.append(f"| `{s}` | {cells} |")
    tot = []
    for r in cols:
        h = sum(v[0] for v in r["skill"].values())
        n = sum(v[1] for v in r["skill"].values())
        tot.append(f"**{h}/{n} ({100 * h // max(n, 1)}%)**")
    out.append("| **All phrases** | " + " | ".join(tot) + " |")
    out.append("| Fired on an off-topic question | "
               + " | ".join(f"{r['neg'][0]}/{r['neg'][1]}" for r in cols) + " |")

    out += ["", "## Phrase by phrase", "",
            f"| Skill | Phrase | {head} |", "|" + "---|" * (len(cols) + 2)]
    for i, row in enumerate(table("Should fire"), start=1):
        text = row[1] if len(row) > 1 else ""
        if len(text) > 90:
            text = text[:90].rstrip() + " ..."
        cells = " | ".join(f"{r['phrase'].get(i, [0, 0])[0]}/{r['phrase'].get(i, [0, 0])[1]}" for r in cols)
        out.append(f"| `{row[0]}` | {text} | {cells} |")

    arms = max((len(r["qual"]["with"]) for r in cols), default=0)
    out += ["", "## Report quality on the same messy input", "",
            "Same report, once normally and once with every skill switched off, "
            f"{arms} runs each.", "Small numbers, read them as a smoke test.", "",
            "| Model | pack | verdict block | warning row | lines | hashes | jargon |",
            "|---|---|---|---|---|---|---|"]
    for m, r in zip(models, cols):
        for arm in ("with", "without"):
            q = r["qual"][arm]
            if not q:
                continue
            out.append(f"| {label(m)} | {arm} | {pct(q, 'verdict'):.0f}% | "
                       f"{pct(q, 'warn_row'):.0f}% | {avg(q, 'lines'):.1f} | "
                       f"{avg(q, 'hashes'):.1f} | {avg(q, 'jargon'):.1f} |")
    return "\n".join(out) + "\n"


flags = [a for a in sys.argv[1:] if a.startswith("--")]
args = [a for a in sys.argv[1:] if not a.startswith("--")]
show_only, readme = "--print" in flags, "--readme" in flags
if (len(args) != 1 or not pathlib.Path(args[0]).is_dir()
        or set(flags) - {"--print", "--readme"} or (show_only and readme)):
    sys.exit("usage: score.py [--print | --readme] ~/.claude/open-steps/evals/<day>")
folder = pathlib.Path(args[0])
runs = read_day(folder)
if not runs:
    sys.exit(f"no .jsonl streams in {folder}")
text = report(folder, runs)
if not show_only:
    out = HERE / "results.md"
    out.write_text(text)
    print(f"wrote {out}")
    # The README is the front page. It changes on --readme only, never as a
    # side effect of scoring a partial day or a foreign branch.
    print(update_readme(folder, runs) if readme else "README.md not touched, --readme rewrites its table")
    print()
print(text)
