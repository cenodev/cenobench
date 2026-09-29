#!/usr/bin/env python3
"""Aggregate every benchmark's result cards into one index for the site.

  sources/<id>.yaml         where a benchmark's results live and how to normalize them
  runs/<id>/<config>.json   normalized per-benchmark cards (written here, committed)
  index.json                one point per config:
                              mark = equal-weight mean of benchmark scores
                              cost_usd = executor-only measured USD when available

Cost is measured from opencode's SQLite DB, which records per-step `cost` and `tokens`
alongside the session's working directory. Judge sessions (cwd .../…-judge) are excluded.
Runs from harnesses that do not report usage have `cost_usd: null` and are plotted as
cost-unknown rather than zero.
"""
import glob, json, os, re, sqlite3
from datetime import datetime, timezone
import yaml

ROOT = os.path.dirname(os.path.abspath(__file__))
SOURCES_DIR = os.path.join(ROOT, "sources")
RUNS_DIR = os.path.join(ROOT, "runs")
OPENCODE_DB = os.path.expanduser("~/.local/share/opencode/opencode.db")

def load_sources():
    out = []
    for f in sorted(glob.glob(os.path.join(SOURCES_DIR, "*.yaml"))):
        s = yaml.safe_load(open(f))
        s["_file"] = f
        s["_dir"] = os.path.normpath(os.path.join(ROOT, s.get("dir", ".")))
        out.append(s)
    return out

def track_scores(doc):
    raw = doc.get("tracks") or doc.get("pillars") or {}
    tracks = {}
    for tid, t in raw.items():
        score = t.get("score")
        if score is None:
            score = round(100 * t["pass"] / t["total"], 1) if t.get("total") else 0.0
        tracks[tid] = {"pass": t.get("pass"), "total": t.get("total"), "score": round(float(score), 1)}
    return tracks

def overall(doc):
    t = doc.get("total") or {}
    score = t.get("score")
    if score is None:
        score = round(100 * t["pass"] / t["total"], 1) if t.get("total") else 0.0
    return round(float(score), 1)

def parse_iso(s):
    try:
        return datetime.fromisoformat(s).timestamp()
    except Exception:
        return None

def current_manifest(source):
    spec = source.get("current_manifest")
    if not spec:
        return None
    path, _, key = spec.partition("#")
    try:
        d = json.load(open(os.path.normpath(os.path.join(ROOT, path))))
    except Exception:
        return None
    if key and isinstance(d.get("benchmarks"), list):
        for b in d["benchmarks"]:
            if b.get("id") == key:
                return b.get("manifest")
    return d.get("manifest")

def measure_cost(prefix, model, t0=None, t1=None):
    """Executor-only cost/tokens from opencode's DB: sessions under `prefix` for `model`,
    excluding judge sessions, created no later than t1."""
    if not os.path.exists(OPENCODE_DB):
        return None
    model = (model or "").split("@")[0]
    provider, model_id = (model.split("/", 1) + [""])[:2] if "/" in model else (None, model)
    try:
        con = sqlite3.connect(f"file:{OPENCODE_DB}?mode=ro", uri=True)
        rows = con.execute(
            "SELECT p.data, m.data FROM part p JOIN message m ON p.message_id = m.id "
            "WHERE p.data LIKE '%\"step-finish\"%'"
        ).fetchall()
        con.close()
    except sqlite3.Error:
        return None
    usd, hits = 0.0, 0
    variants = set()
    tokens = {"input": 0, "output": 0, "reasoning": 0, "cache_read": 0, "cache_write": 0}
    for pdata, mdata in rows:
        try:
            m = json.loads(mdata)
            p = json.loads(pdata)
        except Exception:
            continue
        cwd = (m.get("path") or {}).get("cwd") or ""
        if not cwd.startswith(prefix) or cwd.rstrip("/").endswith("judge"):
            continue
        if model_id and m.get("modelID") != model_id:
            continue
        if provider and m.get("providerID") != provider:
            continue
        t = (m.get("time") or {}).get("created")
        if t is None:
            continue
        t = t / 1000.0
        if t0 and t < t0 - 5:
            continue
        if t1 and t > t1 + 60:
            continue
        if m.get("variant"):
            variants.add(m["variant"])
        usd += float(p.get("cost") or 0)
        tk = p.get("tokens") or {}
        tokens["input"] += tk.get("input", 0)
        tokens["output"] += tk.get("output", 0)
        tokens["reasoning"] += tk.get("reasoning", 0)
        cache = tk.get("cache") or {}
        tokens["cache_read"] += cache.get("read", 0)
        tokens["cache_write"] += cache.get("write", 0)
        hits += 1
    if not hits:
        return None
    return {"usd": round(usd, 4), "scope": "executor", "source": "measured:opencode-db",
            "tokens": tokens, "steps": hits, "variants": sorted(variants)}

def normalize(doc, source, path):
    tracks = track_scores(doc)
    name = doc.get("name") or os.path.splitext(os.path.basename(path))[0]
    rows = [r for r in doc.get("rows", []) if not r.get("dead") and not r.get("ungraded")]
    rec = {
        "benchmark": source["id"],
        "benchmark_name": source.get("name", source["id"]),
        "config": name,
        "model": doc.get("model") or name,
        "harness": doc.get("harness"),
        "variant": doc.get("variant"),
        "skill": doc.get("skill"),
        "started": doc.get("started"),
        "manifest": doc.get("manifest") or ((doc.get("benchmarks") or {}).get(source["id"]) or {}).get("manifest"),
        "score": overall(doc),
        "tracks": tracks,
        "evals_run": len(rows),
        "verdicts": {r["id"]: bool(r["pass"]) for r in rows},
        "cost": None,
        "source_file": os.path.relpath(path, ROOT) if path.startswith(ROOT) else path,
    }
    prefix = source.get("temp_prefix")
    if prefix:
        t0 = parse_iso(doc.get("started"))
        try:
            t1 = os.path.getmtime(path)
        except OSError:
            t1 = None
        rec["cost"] = measure_cost(prefix, rec["model"], t0, t1)
    cur = source.get("_current_manifest")
    rec["stale"] = bool(cur and rec["manifest"] and rec["manifest"] != cur)
    rec["observed_variants"] = (rec["cost"] or {}).get("variants", [])
    return rec

def slug(name):
    return re.sub(r"[^a-z0-9+._-]", "-", name.lower())

def main():
    sources = load_sources()
    for s in sources:
        s["_current_manifest"] = current_manifest(s)
    os.makedirs(RUNS_DIR, exist_ok=True)
    configs = {}
    for s in sources:
        out_dir = os.path.join(RUNS_DIR, s["id"])
        os.makedirs(out_dir, exist_ok=True)
        newest = {}
        for f in sorted(glob.glob(os.path.join(s["_dir"], s["results_glob"]))):
            if f.endswith("index.json") or not f.endswith(".json"):
                continue
            try:
                doc = json.load(open(f))
            except Exception:
                continue
            if not doc.get("total"):
                continue
            name = doc.get("name") or ""
            started = doc.get("started") or ""
            if name not in newest or started > newest[name][1]:
                newest[name] = (f, started)
        for name, (f, _) in sorted(newest.items()):
            doc = json.load(open(f))
            rec = normalize(doc, s, f)
            json.dump(rec, open(os.path.join(out_dir, slug(name) + ".json"), "w"), indent=1)
            c = configs.setdefault(name, {"config": name, "model": rec["model"], "harness": rec["harness"],
                                          "skill": rec["skill"], "variant": rec["variant"], "benchmarks": {}})
            if not c.get("variant"):
                c["variant"] = rec["variant"] or (rec["observed_variants"][0] if len(rec["observed_variants"]) == 1 else None)
            c["benchmarks"][s["id"]] = {
                "name": rec["benchmark_name"],
                "score": rec["score"],
                "cost_usd": (rec["cost"] or {}).get("usd"),
                "cost_source": (rec["cost"] or {}).get("source"),
                "manifest": rec["manifest"],
                "stale": rec["stale"],
                "observed_variants": rec["observed_variants"],
                "file": os.path.relpath(os.path.join(out_dir, slug(name) + ".json"), ROOT),
            }
    out = []
    for name, c in configs.items():
        scores = [b["score"] for b in c["benchmarks"].values()]
        costs = [b["cost_usd"] for b in c["benchmarks"].values() if b["cost_usd"] is not None]
        c["mark"] = round(sum(scores) / len(scores), 1) if scores else None
        c["cost_usd"] = round(sum(costs), 4) if costs else None
        c["benchmarks_scored"] = len(scores)
        c["cost_complete"] = bool(c["benchmarks"]) and len(costs) == len(c["benchmarks"])
        c["stale"] = any(b.get("stale") for b in c["benchmarks"].values())
        out.append(c)
    out.sort(key=lambda c: (-(c["mark"] or 0), c["cost_usd"] if c["cost_usd"] is not None else 1e18))
    index = {"generated": datetime.now(timezone.utc).isoformat(timespec="seconds"), "configs": out}
    json.dump(index, open(os.path.join(ROOT, "index.json"), "w"), indent=1)
    print(f"index.json: {len(out)} configs")
    for c in out:
        print(f"  {c['config']:34} mark {c['mark']}  cost ${c['cost_usd']}  " +
              "  ".join(f"{bid} {b['score']}" for bid, b in sorted(c["benchmarks"].items())))

if __name__ == "__main__":
    main()
