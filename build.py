#!/usr/bin/env python3
"""Roll benchmarks/ and results/ into the JSON files the site reads:
  benchmarks/index.json   the catalog: benchmarks, tracks, evals
  results/index.json      one row per run, with per-track scores and per-eval verdicts
Run after adding an eval or a result. Both files are committed."""
import datetime as dt, glob, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run import load_benchmarks, load_evals, ROOT

def summary(ev):
    if ev.get("summary"): return ev["summary"]
    t = " ".join(ev.get("prompt", "").split())
    return (t[:170] + "…") if len(t) > 170 else t

def label(name):
    """'kimi-k2+audit-skill' -> 'Kimi K2 + audit-skill'."""
    parts = name.split("+")
    return " + ".join([p.replace("-", " ").replace("_", " ").strip() for p in parts])

def main():
    benchmarks = load_benchmarks()
    evals = load_evals(benchmarks=benchmarks)
    generated = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")

    cat = {"generated": generated, "benchmarks": []}
    for bid, b in benchmarks.items():
        mine = [e for e in evals if e["_benchmark"] == bid]
        cat["benchmarks"].append({
            "id": bid, "name": b.get("name"), "version": b.get("version"), "desc": b.get("desc"),
            "manifest": b["manifest"],
            "tracks": [{"id": t["id"], "name": t.get("name"), "desc": t.get("desc"),
                        "count": sum(1 for e in mine if e.get("track") == t["id"])} for t in b.get("tracks", [])],
            "evals": [{"id": e["id"], "track": e.get("track"), "title": e.get("title"), "kind": e.get("kind"),
                       "graded": "mutation" if e.get("grading") == "mutation" else
                                 ("exec" if e.get("kind") == "exec" else ("deterministic" if "grader" in e else "judge")),
                       "summary": summary(e), "source": e.get("source", {}),
                       "fixture": e.get("fixture")} for e in mine],
        })
    json.dump(cat, open(os.path.join(ROOT, "benchmarks", "index.json"), "w"), indent=1)

    runs = []
    for f in sorted(glob.glob(os.path.join(ROOT, "results", "*.json"))):
        if f.endswith("index.json"): continue
        d = json.load(open(f))
        rows = [r for r in d.get("rows", []) if not r.get("dead") and not r.get("ungraded")]
        runs.append({k: d.get(k) for k in ("name", "model", "harness", "skill", "started", "benchmarks", "tracks", "total")}
                    | {"label": label(d["name"]), "file": os.path.relpath(f, ROOT),
                       "evals_run": len(rows), "verdicts": {r["id"]: bool(r["pass"]) for r in rows}})
    runs.sort(key=lambda r: -(r["total"]["pass"] if r.get("total") else 0))
    json.dump({"generated": generated, "benchmarks": {b["id"]: {"version": b.get("version"), "manifest": b["manifest"]}
                                                      for b in cat["benchmarks"]}, "runs": runs},
              open(os.path.join(ROOT, "results", "index.json"), "w"), indent=1)
    print(f"benchmarks/index.json: {len(evals)} evals across {len(benchmarks)} benchmarks")
    print(f"results/index.json: {len(runs)} runs")

if __name__ == "__main__":
    main()
