#!/usr/bin/env python3
"""cenobench runner: execute evals against any agent, grade them, write results/<name>.json.

  python3 run.py --list
  python3 run.py --self-test
  python3 run.py --name fable --executor claude --model fable
  python3 run.py --name x --cmd 'my-agent --stdin' --judge-cmd 'claude -p --model sonnet'
  python3 run.py --name fable+skill --executor claude --model fable --skill ./skills/audit/SKILL.md

Executor contract: the prompt arrives on stdin, the reply is stdout, cwd is a fresh workspace
directory the executor may write files into.

Grading:
  kind: quiz   deterministic grader on the reply, or a blind judge
  kind: goal   blind judge on the files left behind and the reply
  kind: exec   the workspace is built and hidden Foundry tests are run against the artifact;
               grading: mutation means the model's test suite must kill every seeded mutant

--self-test enforces the discrimination invariant for every exec eval: the shipped workspace
must fail, the reference solution must pass, and every mutant must fail.
"""
import argparse, concurrent.futures as cf, datetime as dt, glob, hashlib, json, os, re, shutil, subprocess, sys, tempfile, time, urllib.request
import yaml

ROOT = os.path.dirname(os.path.abspath(__file__))
BENCHMARKS_DIR = os.path.join(ROOT, "benchmarks")
RESULTS_DIR = os.path.join(ROOT, "results")

EXEC_TIMEOUT = 1800
GOAL_TIMEOUT = 1800
JUDGE_TIMEOUT = 600
FORGE_TIMEOUT = 900
MAX_FILE_BYTES = 60_000
MAX_EVIDENCE_BYTES = 400_000
SKIP_NAMES = {".git", "node_modules", "out", "cache", "broadcast", ".cenobench", ".claude", ".codex", ".next", "dist"}
JUDGE_DEFAULT = "claude -p --model sonnet --strict-mcp-config --disallowedTools Bash,Edit,Write,WebFetch,WebSearch"
DEAD_RE = re.compile(r"spend limit|usage limit|hit your .*limit|not logged in|Please run /login|API Error", re.I)

# ------------------------------------------------------------------ discovery

def load_benchmarks():
    out = {}
    for manifest_path in sorted(glob.glob(os.path.join(BENCHMARKS_DIR, "*", "benchmark.yaml"))):
        bdir = os.path.dirname(manifest_path)
        b = yaml.safe_load(open(manifest_path))
        b["_dir"] = bdir
        b["_manifest_path"] = manifest_path
        b["_eval_files"] = sorted(glob.glob(os.path.join(bdir, "evals", "*", "*.yaml")))
        b["manifest"] = manifest(b)
        out[b["id"]] = b
    return out

def manifest(b):
    h = hashlib.sha256()
    for p in [b["_manifest_path"]] + b["_eval_files"]:
        h.update(os.path.relpath(p, b["_dir"]).encode())
        h.update(open(p, "rb").read())
    return h.hexdigest()[:12]

def load_evals(benchmark=None, track=None, only=None, limit=None, benchmarks=None):
    benchmarks = benchmarks or load_benchmarks()
    out = []
    for bid, b in benchmarks.items():
        if benchmark and bid != benchmark:
            continue
        for f in b["_eval_files"]:
            ev = yaml.safe_load(open(f))
            ev["_file"] = f
            ev["_benchmark"] = bid
            ev["_benchmark_obj"] = b
            ev["_eval_dir"] = os.path.dirname(f)
            ev["_fixture_dir"] = os.path.join(b["_dir"], "fixtures", ev.get("fixture", ""))
            if track and ev.get("track") != track:
                continue
            if only and not any(o in ev["id"] for o in only):
                continue
            out.append(ev)
    return out[:limit] if limit else out

def strip_internal(ev):
    return {k: v for k, v in ev.items() if not k.startswith("_")}

def result_path(name):
    return os.path.join(RESULTS_DIR, re.sub(r"[^a-z0-9+._-]", "-", name.lower()) + ".json")

# ------------------------------------------------------------------ deterministic graders
# Formats and semantics follow ethevals (MIT), which ports clawdbotatg/eth-evals (MIT).

def norm(t, casefold=True):
    t = (t or "").strip().strip("`*").strip()
    t = re.sub(r"\s+", " ", t).strip().rstrip(".").strip().strip("\"'*").strip()
    return t.casefold() if casefold else t

def lines(r): return [l.strip() for l in (r or "").strip().splitlines() if l.strip()]

def ans_line(r):
    found = None
    for l in (r or "").strip().splitlines():
        m = re.match(r"\s*[*#>\s]*answer\s*[:=]\s*(.+?)\s*$", l, re.I)
        if m: found = m.group(1)
    if found is None:
        m = re.search(r"answer\s*[:=]\s*(.+?)\s*$", r or "", re.I | re.M)
        if m: found = m.group(1)
    if found is not None: return found.strip().strip("*").strip()
    ls = lines(r); return ls[-1] if ls else ""

def extract_num(r):
    a = ans_line(r)
    for scope in (a, r or ""):
        nums = re.findall(r"-?\$?\d[\d,]*\.?\d*(?:e[+-]?\d+)?", scope, re.I)
        if nums:
            pick = nums[0] if scope is a else nums[-1]
            return float(pick.replace("$", "").replace(",", ""))
    return None

_INT_RE = re.compile(r"(?:0x[0-9a-fA-F][0-9a-fA-F_]*|(?<![\w-])-\d[\d_,]*|\d[\d_,]*)")
def extract_bigints(r):
    out = []
    for m in _INT_RE.finditer(r or ""):
        s = m.group(0).replace("_", "").replace(",", "")
        try: out.append(int(s, 16) if s.lower().startswith("0x") else int(s))
        except ValueError: pass
    return out

def jload(r):
    r = (r or "").strip()
    fenced = re.findall(r"```(?:json)?\s*(.*?)```", r, re.S)
    for c in ([fenced[-1]] if fenced else []) + [r]:
        c = c.strip()
        try: return json.loads(c)
        except Exception: pass
        for op, cl in (("{", "}"), ("[", "]")):
            i, j = c.find(op), c.rfind(cl)
            if 0 <= i < j:
                try: return json.loads(c[i:j + 1])
                except Exception: pass
    raise ValueError("no JSON found in response")

def jmatch(exp, got):
    if isinstance(exp, bool): return isinstance(got, bool) and exp == got
    if isinstance(exp, (int, float)):
        if isinstance(got, str):
            try: got = int(got, 16) if got.lower().startswith("0x") else float(got)
            except ValueError: return False
        return isinstance(got, (int, float)) and not isinstance(got, bool) and abs(exp - got) < 1e-6
    if isinstance(exp, str):
        if not isinstance(got, str): return False
        if exp.startswith("~"): return exp[1:].casefold() in got.casefold()
        return norm(exp) == norm(got)
    if isinstance(exp, list): return isinstance(got, list) and len(exp) == len(got) and all(jmatch(e, g) for e, g in zip(exp, got))
    if isinstance(exp, dict): return isinstance(got, dict) and all(k in got and jmatch(v, got[k]) for k, v in exp.items())
    if exp is None: return got is None
    return exp == got

_NEG_RE = re.compile(r"(?i)(?<![\w-])(not|isn'?t|aren'?t|doesn'?t|don'?t|won'?t|wasn'?t|weren'?t|never|cannot|can'?t|neither|nor|rather than|instead of|no longer|wrong|incorrect)(?![\w-])|!=|≠")

def grade_one(g, resp):
    t = g["type"]
    if t == "numeric":
        v = extract_num(resp); return v is not None and abs(v - g["expect"]) <= g.get("tol", 1e-6), f"got {v}"
    if t == "bigint":
        exp = g["expect"]
        if isinstance(exp, str): exp = int(exp, 16) if exp.lower().startswith("0x") else int(exp)
        a_ints = extract_bigints(ans_line(resp))
        if a_ints:
            if len(set(a_ints)) > 1: return False, f"ambiguous: multiple integers {sorted(set(a_ints))[:4]}"
            return a_ints[0] == exp, f"got {a_ints[0]}"
        r_ints = extract_bigints(resp)
        return bool(r_ints) and r_ints[-1] == exp, f"got {r_ints[-1] if r_ints else None}"
    if t == "exact":
        cf_ = not g.get("case_sensitive", False)
        cands = [norm(resp, cf_)]
        ls = lines(resp)
        if ls: cands.append(norm(ls[-1], cf_))
        cands.append(norm(ans_line(resp), cf_))
        return norm(g["expect"], cf_) in cands, f"got {cands[-1][:80]!r}"
    if t == "regex":
        scope = ans_line(resp) if g.get("on", "answer") == "answer" else resp
        return bool(re.search(g["pattern"], scope, 0 if g.get("case_sensitive") else re.I)), f"answer {scope[:80]!r}"
    if t == "regex_all":
        scope = ans_line(resp) if g.get("on", "answer") == "answer" else resp
        flags = 0 if g.get("case_sensitive") else re.I
        misses = [p for p in g["patterns"] if not re.search(p, scope, flags)]
        return not misses, (f"missing {misses[:3]}" if misses else "")
    if t == "json":
        got = jload(resp); ok = jmatch(g["expect"], got)
        return ok, "" if ok else f"got {json.dumps(got)[:120]}"
    if t == "any_of":
        details = []
        for sub in g["options"]:
            ok, d = grade_one(sub, resp)
            if ok: return True, ""
            details.append(d)
        return False, "; ".join(details)[:140]
    raise ValueError(f"unknown grader type {t}")

def grade_deterministic(ev, resp):
    try:
        ok, detail = grade_one(ev["grader"], resp)
        if ok and _NEG_RE.search(ans_line(resp)) and not _NEG_RE.search(ev.get("reference", "")):
            return False, f"negated answer line: {ans_line(resp)[:80]!r}"
        return ok, detail
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"[:140]

# ------------------------------------------------------------------ process plumbing

SCRUB = re.compile(r"^(CLAUDECODE$|CLAUDE_CODE_|ANTHROPIC_API_KEY$|CLAUDE_AGENT_|CODEX_)")
def child_env():
    nested = "CLAUDECODE" in os.environ
    env = {k: v for k, v in os.environ.items() if not SCRUB.match(k)}
    if nested: env.pop("ANTHROPIC_BASE_URL", None)
    return env

def run_cmd(cmd, stdin, cwd, timeout):
    t0 = time.time()
    try:
        p = subprocess.run(cmd, shell=True, input=stdin, capture_output=True, text=True, cwd=cwd, env=child_env(), timeout=timeout)
        return p.stdout, p.stderr, p.returncode, time.time() - t0
    except subprocess.TimeoutExpired as e:
        return (e.stdout or ""), f"timeout after {timeout}s", -1, time.time() - t0

EXECUTORS = {
    "claude": lambda model, variant: f"claude -p --model {model} --dangerously-skip-permissions --strict-mcp-config",
    "codex": lambda model, variant: (
        "codex exec "
        + (f"-c model_reasoning_effort={variant} " if variant else "")
        + f"--model {model} --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -o .ceno-reply.txt - >/dev/null 2>&1; cat .ceno-reply.txt"
    ),
    "opencode": lambda model, variant: (
        "opencode run " + (f"--variant {variant} " if variant else "") + f"--model {model}"
    ),
}

# ------------------------------------------------------------------ workspace + snapshot

def overlay(src, dst):
    shutil.copytree(src, dst, dirs_exist_ok=True)

def seed_workspace(ev, skill_text):
    ws = tempfile.mkdtemp(prefix="cenobench-")
    src = os.path.join(ev["_fixture_dir"], "workspace")
    if not os.path.isdir(src):
        raise FileNotFoundError(f"missing fixture workspace: {src}")
    overlay(src, ws)
    if skill_text:
        open(os.path.join(ws, "SKILL.md"), "w").write(skill_text)
        note = "Read SKILL.md in this directory before you start and follow it.\n"
        for f in ("CLAUDE.md", "AGENTS.md"):
            open(os.path.join(ws, f), "a").write(note)
    return ws, snapshot(ws)

def snapshot(ws):
    out = {}
    for base, dirs, files in os.walk(ws):
        dirs[:] = [d for d in dirs if d not in SKIP_NAMES]
        for f in files:
            if f in SKIP_NAMES: continue
            p = os.path.join(base, f); rel = os.path.relpath(p, ws)
            try:
                data = open(p, "rb").read(MAX_FILE_BYTES + 1)
            except OSError:
                continue
            out[rel] = data.decode("utf-8", "replace")[:MAX_FILE_BYTES]
    return out

def frozen_changes(ev, after):
    bad = []
    for rel in ev.get("frozen", []):
        original = os.path.join(ev["_fixture_dir"], "workspace", rel)
        current = os.path.join(ev["_result_ws"], rel)
        if os.path.isdir(original):
            continue
        want = open(original, "rb").read() if os.path.exists(original) else None
        got = open(current, "rb").read() if os.path.exists(current) else None
        if want != got:
            bad.append(rel)
    return bad

def restore_frozen(ev, ws):
    for rel in ev.get("frozen", []):
        src = os.path.join(ev["_fixture_dir"], "workspace", rel)
        dst = os.path.join(ws, rel)
        if os.path.exists(src):
            os.makedirs(os.path.dirname(dst) or ws, exist_ok=True)
            shutil.copy2(src, dst)

# ------------------------------------------------------------------ forge grading

def forge_test(ws, match=None, timeout=FORGE_TIMEOUT):
    cmd = ["forge", "test", "--json"]
    if match: cmd += ["--match-path", match]
    try:
        p = subprocess.run(cmd, cwd=ws, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"parsed": False, "tests": 0, "failed": 0, "rc": -1, "error": f"forge timeout after {timeout}s"}
    try:
        data = json.loads(p.stdout)
    except Exception:
        return {"parsed": False, "tests": 0, "failed": 0, "rc": p.returncode,
                "error": (p.stdout + p.stderr).strip()[:200] or "no test JSON"}
    tests, failed = 0, 0
    for suite in data.values():
        for name, r in suite.get("test_results", {}).items():
            tests += 1
            if r.get("status") != "Success": failed += 1
    return {"parsed": True, "tests": tests, "failed": failed, "rc": p.returncode, "error": ""}

def exec_base_ok(r, min_tests):
    return bool(r["parsed"]) and r["rc"] == 0 and r["failed"] == 0 and r["tests"] >= min_tests

def grade_exec(ev, ws, is_self_test=False):
    """Returns (pass, detail, subscore). Applies the discrimination invariant when is_self_test."""
    ex = ev.get("exec", {})
    match = ex.get("match")
    min_tests = ex.get("min_tests", 1)
    timeout = ex.get("timeout", FORGE_TIMEOUT)
    mutants = sorted(glob.glob(os.path.join(ev["_fixture_dir"], "mutants", "*")))
    fixture_ws = os.path.join(ev["_fixture_dir"], "workspace")
    reference = os.path.join(ev["_fixture_dir"], "reference")

    if ev.get("grading") == "mutation":
        if is_self_test and os.path.isdir(reference):
            overlay(reference, ws)
        base = forge_test(ws, match, timeout)
        base_ok = exec_base_ok(base, min_tests)
        killed, results = 0, []
        for m in mutants:
            restore_frozen(ev, ws)
            overlay(m, ws)
            r = forge_test(ws, match, timeout)
            killed_this = r["parsed"] and r["failed"] > 0 and r["tests"] >= 1
            killed += killed_this
            results.append(f"{os.path.basename(m)}={'kill' if killed_this else 'SURVIVES'}")
        ok = base_ok and killed == len(mutants) and len(mutants) > 0
        detail = f"base tests={base['tests']} failed={base['failed']}; mutants killed {killed}/{len(mutants)}"
        if results: detail += " [" + ", ".join(results) + "]"
        if not base["parsed"]: detail += f"; base error: {base['error'][:120]}"
        return ok, detail[:600], {"kind": "mutants", "pass": killed, "total": len(mutants), "base_ok": base_ok}

    if is_self_test and os.path.isdir(reference):
        overlay(reference, ws)
    hidden = os.path.join(ev["_fixture_dir"], "hidden")
    if os.path.isdir(hidden):
        overlay(hidden, ws)
    r = forge_test(ws, match, timeout)
    ok = exec_base_ok(r, min_tests)
    detail = f"hidden tests={r['tests']} failed={r['failed']}"
    if not r["parsed"]: detail += f"; {r['error'][:120]}"
    sub = {"kind": "hidden_tests", "pass": max(0, r["tests"] - r["failed"]), "total": r["tests"]}
    return ok, detail[:600], sub

# ------------------------------------------------------------------ self-test

TRIPWIRE = re.compile(r"fixtures/|answer_key|mutants/\w", re.I)
PROBE_WORDS = ["not", "definitely not"]

def self_test(evals):
    problems = 0
    def fail(ev, msg):
        nonlocal problems
        problems += 1
        print(f"FAIL  {ev['id']}: {msg}")

    if not shutil.which("forge"):
        print("FAIL  forge not found on PATH; executed evals cannot be self-tested")
        return False

    for ev in evals:
        if TRIPWIRE.search(ev.get("prompt", "")):
            fail(ev, "prompt leaks fixture paths or the answer key")
        kind = ev.get("kind")
        if kind == "quiz":
            if "grader" not in ev:
                if not ev.get("expect"): fail(ev, "quiz has neither grader nor expect")
                continue
            ok, d = grade_deterministic(ev, ev.get("reference", ""))
            if not ok: fail(ev, f"reference does not pass: {d}")
            for mp in ev.get("checks", {}).get("must_pass", []):
                ok, d = grade_deterministic(ev, mp)
                if not ok: fail(ev, f"must_pass {mp[:50]!r} did not pass: {d}")
            for mf in ev.get("checks", {}).get("must_fail", []):
                ok, d = grade_deterministic(ev, mf)
                if ok: fail(ev, f"must_fail {mf[:50]!r} passed")
            if not _NEG_RE.search(ev.get("reference", "")):
                for w in PROBE_WORDS:
                    probe = "Answer: " + w + " " + ans_line(ev.get("reference", ""))
                    ok, _ = grade_deterministic(ev, probe)
                    if ok: fail(ev, f"negation probe passed: {probe[:60]!r}")
        elif kind == "goal":
            if not ev.get("expect"): fail(ev, "goal eval has no expect conditions")
            if not os.path.isdir(os.path.join(ev["_fixture_dir"], "workspace")):
                fail(ev, "fixture workspace missing")
            for key in ev.get("answer_key", []):
                if not key.get("location") or not key.get("class"):
                    fail(ev, f"answer_key entry incomplete: {key}")
        elif kind == "exec":
            fixture = ev["_fixture_dir"]
            mutants = sorted(glob.glob(os.path.join(fixture, "mutants", "*")))
            if not os.path.isdir(os.path.join(fixture, "workspace")): fail(ev, "fixture workspace missing")
            if not os.path.isdir(os.path.join(fixture, "reference")): fail(ev, "fixture reference missing")
            if len(mutants) < 2: fail(ev, "exec eval needs at least 2 mutants")
            mutation = ev.get("grading") == "mutation"
            if not mutation and not os.path.isdir(os.path.join(fixture, "hidden")):
                fail(ev, "exec eval has no hidden tests")

            def case(name, overlays, expect_ok):
                ws = tempfile.mkdtemp(prefix=f"ceno-selftest-{ev['id']}-")
                try:
                    overlay(os.path.join(fixture, "workspace"), ws)
                    for o in overlays:
                        overlay(o, ws)
                    ok, detail, _sub = grade_exec(ev, ws, is_self_test=False)
                    if ok != expect_ok:
                        fail(ev, f"{name}: expected {'pass' if expect_ok else 'fail'}, got {'pass' if ok else 'fail'} ({detail})")
                finally:
                    shutil.rmtree(ws, ignore_errors=True)

            if mutation:
                case("unsolved", [], False)
                case("reference", [os.path.join(fixture, "reference")], True)
                for m in mutants:
                    case(f"mutant {os.path.basename(m)}", [os.path.join(fixture, "reference"), m], False)
            else:
                hidden = os.path.join(fixture, "hidden")
                case("unsolved", [hidden], False)
                case("reference", [os.path.join(fixture, "reference"), hidden], True)
                for m in mutants:
                    case(f"mutant {os.path.basename(m)}", [m, hidden], False)
        else:
            fail(ev, f"unknown kind {kind!r}")
    det = sum("grader" in e for e in evals)
    jud = sum(e.get("kind") in ("goal",) or ("grader" not in e and e.get("kind") == "quiz") for e in evals)
    ex = sum(e.get("kind") == "exec" for e in evals)
    print(f"{len(evals)} evals ({ex} exec, {jud} judged, {det} deterministic), {problems} problems")
    return problems == 0

# ------------------------------------------------------------------ judge

def judge(ev, evid, judge_cmd):
    exp = ev["expect"]
    prompt = "\n".join([
        "You are grading one run of a task by an AI agent. You do not know which model or harness produced it.",
        "Decide whether each numbered condition is satisfied by the evidence. Be strict: a condition passes only if the evidence shows it.",
        'Return only strict JSON: {"verdicts":[{"condition":1,"pass":true,"reason":"..."}]}',
        "", "TASK:", ev["prompt"], "", "EVIDENCE:", evid, "", "CONDITIONS:",
        *[f"{i + 1}. {c}" for i, c in enumerate(exp)],
    ])
    jd = os.path.join(tempfile.gettempdir(), "cenobench-judge"); os.makedirs(jd, exist_ok=True)
    out, err, rc, secs = run_cmd(judge_cmd, prompt, jd, JUDGE_TIMEOUT)
    s, e = out.find("{"), out.rfind("}")
    try:
        verdicts = json.loads(out[s:e + 1])["verdicts"]
        v = {int(x["condition"]): bool(x["pass"]) for x in verdicts}
        res = [v.get(i + 1, False) for i in range(len(exp))]
    except Exception as ex_:
        return None, [], f"judge output unusable: {ex_}; rc={rc} {err[-200:]}"
    reasons = {int(x["condition"]): str(x.get("reason", ""))[:200] for x in verdicts}
    return all(res), res, "; ".join(f"{i + 1}:{'pass' if r else 'FAIL'} {reasons.get(i + 1, '')}" for i, r in enumerate(res))[:600]

def evidence(ev, reply, seed, after):
    parts = []
    changed = {k: v for k, v in after.items() if seed.get(k) != v}
    if reply.strip():
        parts.append("REPLY (stdout):\n" + reply.strip())
    if changed:
        for k in sorted(changed):
            parts.append(f"FILE {k}:\n" + changed[k])
    elif ev.get("kind") == "goal":
        parts.append("(the executor wrote no files)")
    return ("\n\n".join(parts) or "(empty reply)")[:MAX_EVIDENCE_BYTES]

# ------------------------------------------------------------------ one eval

def run_one(ev, cmd, judge_cmd, skill_text):
    ws, seed = seed_workspace(ev, skill_text)
    timeout = ev.get("timing") or (GOAL_TIMEOUT if ev.get("kind") == "goal" else EXEC_TIMEOUT)
    reply, err, rc, secs = run_cmd(cmd, ev["prompt"], ws, timeout)
    after = snapshot(ws)
    changed = sorted(k for k in after if seed.get(k) != after[k])
    row = {"id": ev["id"], "benchmark": ev["_benchmark"], "track": ev.get("track"), "kind": ev.get("kind"),
           "seconds": round(secs, 1), "rc": rc, "reply": reply[-4000:], "files": changed}
    dead = rc != 0 or (len(reply.strip()) < 400 and DEAD_RE.search(reply))
    sub = None
    try:
        if dead:
            row.update(pass_=False, detail=(err or reply[-200:]).strip()[:200], dead=True)
        elif ev.get("kind") == "exec":
            ev["_result_ws"] = ws
            bad = frozen_changes(ev, after)
            deliverable = ev.get("deliverable")
            if bad:
                row.update(pass_=False, detail=f"frozen files modified: {bad}")
            elif deliverable and not os.path.exists(os.path.join(ws, deliverable)):
                row.update(pass_=False, detail=f"missing deliverable: {deliverable}")
            else:
                restore_frozen(ev, ws)
                ok, detail, sub = grade_exec(ev, ws, is_self_test=False)
                row.update(pass_=ok, detail=detail)
        elif "grader" in ev:
            ok, detail = grade_deterministic(ev, reply)
            sub = {"kind": "binary", "pass": int(ok), "total": 1}
            row.update(pass_=ok, detail=detail)
        else:
            ok, per, detail = judge(ev, evidence(ev, reply, seed, after), judge_cmd)
            sub = {"kind": "conditions", "pass": sum(per) if per else 0, "total": len(ev["expect"])}
            row.update(pass_=bool(ok), expects=per, detail=detail, ungraded=(ok is None))
    finally:
        shutil.rmtree(ws, ignore_errors=True)
    row["pass"] = row.pop("pass_")
    row["weight"] = ev.get("weight", 1)
    if sub is not None:
        row["subscore"] = sub
    return row

# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true"); ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--name", help="result label, e.g. sonnet-5, sonnet-5+audit-skill")
    ap.add_argument("--executor", choices=sorted(EXECUTORS)); ap.add_argument("--model")
    ap.add_argument("--variant", help="provider-specific reasoning effort, e.g. minimal, low, medium, high, xhigh; unset means the provider default, which is not recorded")
    ap.add_argument("--cmd", help="custom executor: prompt on stdin, reply on stdout")
    ap.add_argument("--harness", help="label for the card (defaults to --executor)")
    ap.add_argument("--skill", help="URL or path of a SKILL.md installed in every workspace")
    ap.add_argument("--judge-cmd", default=JUDGE_DEFAULT)
    ap.add_argument("--benchmark"); ap.add_argument("--track")
    ap.add_argument("--only", nargs="*", help="id substrings"); ap.add_argument("--limit", type=int)
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--resume", action="store_true", help="skip evals already graded in results/<name>.json")
    a = ap.parse_args()

    benchmarks = load_benchmarks()
    if a.list:
        for ev in load_evals(a.benchmark, a.track, a.only, a.limit, benchmarks):
            graded = "exec:" + (ev.get("grading") or "tests") if ev.get("kind") == "exec" else ("quiz" if "grader" in ev else "judge")
            print(f"{ev['id']:36} {ev['_benchmark']:16} {ev.get('track',''):7} {ev.get('kind',''):5} {graded:12} {ev.get('title','')}")
        return
    if a.self_test:
        sys.exit(0 if self_test(load_evals(a.benchmark, a.track, a.only, a.limit, benchmarks)) else 1)
    if not a.name: ap.error("--name is required for a run")
    cmd = a.cmd or (EXECUTORS[a.executor](a.model, a.variant) if a.executor and a.model else None)
    if not cmd: ap.error("give --executor and --model, or --cmd")

    evals = load_evals(a.benchmark, a.track, a.only, None, benchmarks)
    all_evals = load_evals(a.benchmark, None, None, None, benchmarks)
    if not self_test(evals): sys.exit("self-test failed; fix the evals before running")

    skill_text = None
    if a.skill:
        skill_text = urllib.request.urlopen(a.skill, timeout=30).read().decode() if a.skill.startswith("http") else open(a.skill).read()

    os.makedirs(RESULTS_DIR, exist_ok=True)
    out_path = result_path(a.name)
    prev = json.load(open(out_path)) if a.resume and os.path.exists(out_path) else None
    current = {e["id"] for e in all_evals}
    rows = {r["id"]: r for r in (prev or {}).get("rows", []) if not r.get("dead") and not r.get("ungraded") and r["id"] in current}
    todo = [e for e in evals if e["id"] not in rows]
    print(f"{a.name}: {len(todo)} evals to run, {len(rows)} kept\n  executor: {cmd}\n  judge:    {a.judge_cmd}")

    started = (prev or {}).get("started") or dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    tracks = sorted({e["track"] for e in all_evals if e.get("track")})

    def save():
        by = {}
        for t in tracks:
            rs = [r for r in rows.values() if r.get("track") == t]
            es = [e for e in all_evals if e.get("track") == t]
            w_total = sum(e.get("weight", 1) for e in es)
            w_pass = sum(r.get("weight", 1) for r in rs if r["pass"])
            by[t] = {"pass": sum(1 for r in rs if r["pass"]), "total": len(es),
                     "score": round(100 * w_pass / w_total, 1) if w_total else 0.0}
        w_total = sum(e.get("weight", 1) for e in all_evals)
        w_pass = sum(r.get("weight", 1) for r in rows.values() if r["pass"])
        doc = {"name": a.name, "model": a.model or a.name, "harness": a.harness or a.executor or "custom",
               "variant": a.variant,
               "skill": a.skill, "executor_cmd": cmd, "judge_cmd": a.judge_cmd, "started": started,
               "benchmarks": {bid: {"version": b.get("version"), "manifest": b["manifest"]}
                              for bid, b in benchmarks.items() if any(e["_benchmark"] == bid for e in all_evals)},
               "tracks": by,
               "total": {"pass": sum(1 for r in rows.values() if r["pass"]), "total": len(all_evals),
                         "score": round(100 * w_pass / w_total, 1) if w_total else 0.0},
               "rows": sorted(rows.values(), key=lambda r: r["id"])}
        json.dump(doc, open(out_path, "w"), indent=1)
    save()
    with cf.ThreadPoolExecutor(max_workers=a.concurrency) as pool:
        futs = {pool.submit(run_one, e, cmd, a.judge_cmd, skill_text): e for e in todo}
        for f in cf.as_completed(futs):
            r = f.result(); rows[r["id"]] = r; save()
            flag = "PASS" if r["pass"] else ("DEAD" if r.get("dead") else ("????" if r.get("ungraded") else "fail"))
            print(f"  {flag}  {r['id']:36} {r['seconds']:6.0f}s  {r.get('detail', '')[:110]}")
    doc = json.load(open(out_path))
    dead = sum(1 for r in doc["rows"] if r.get("dead") or r.get("ungraded"))
    print(f"\n{a.name}: score {doc['total']['score']}% ({doc['total']['pass']}/{doc['total']['total']})  "
          + "  ".join(f"{t} {v['pass']}/{v['total']} {v['score']}%" for t, v in doc["tracks"].items()))
    if dead: print(f"  {dead} dead or ungraded (rerun with --resume; not counted as failures)")
    print(f"wrote {os.path.relpath(out_path, ROOT)}; run `python3 build.py` to refresh the index")

if __name__ == "__main__":
    main()
