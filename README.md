# cenobench

**How well can AI actually build, test, secure and audit onchain applications?**

cenobench is a benchmark and a results index. Models, harnesses and skills are scored on four
tracks — **build**, **test**, **secure**, **audit** — and the artifacts they produce are
**executed**: hidden Foundry tests run against the code they leave behind, exploits are fired
at the fixes they ship, and seeded regressions decide whether their tests are worth anything.

No diff-reading. No vibes. If it can be run, cenobench runs it.

- `SPEC.md` — the benchmark specification: tracks, eval schema, execution model, scoring.
- `benchmarks/<benchmark>/evals/<track>/*.yaml` — the evals. `kind: exec` is an executed
  artifact task, `kind: goal` is an artifact judged blind, `kind: quiz` is a written answer.
- `benchmarks/<benchmark>/fixtures/` — workspaces, hidden tests, reference solutions and
  mutants. Every exec eval ships all four, and `--self-test` proves they discriminate.
- `run.py` — runs the suite against any executor and grades it.
- `build.py` — rolls evals and results into the two index files the site reads.
- `RUN.md` — what an agent reads to score itself and submit a result.

## Run it

```bash
python3 -m pip install pyyaml
python3 run.py --self-test          # fixtures must be green before anything runs
python3 run.py --list
python3 run.py --name sonnet-5 --executor claude --model sonnet
python3 run.py --name kimi-k2 --executor opencode --model openrouter/moonshotai/kimi-k2
python3 run.py --name model@xhigh --executor opencode --model provider/model --variant xhigh
python3 run.py --name model+audit-skill --executor claude --model m --skill ./skills/audit/SKILL.md
python3 build.py
```

Any command that takes the prompt on stdin, prints the reply on stdout and writes files into
its working directory is an executor (`--cmd`), so a new agent framework can be scored without
touching cenobench's code.

Requirements: Python 3.11+, [Foundry](https://getfoundry.sh) (`forge`) for executed evals,
solc 0.8.28 cached (the harness runs offline once fixtures have compiled once).

## cenobench is an index

cenobench aggregates blockchain benchmarks. Each benchmark keeps its own repo and harness;
cenobench ingests its result cards and publishes one point per configuration:

- `sources/<id>.yaml` — where a benchmark's results live, its temp-dir prefix, how to run it.
- `aggregate.py` — normalizes every source into `runs/<id>/<config>.json`, then writes
  `index.json`: one row per config with **mark** (equal-weight mean of benchmark scores) and
  **cost_usd** (executor-only, measured).
- Cost is measured from opencode's SQLite DB, which records per-step `cost`/`tokens` against
  the session's working directory (`/tmp/ethevals-*` vs the judge's `/tmp/ethevals-judge`).
  Harnesses that do not report usage produce `cost_usd: null` and are plotted as cost-unknown,
  never as zero.

- Reasoning effort is part of a card's identity. Pass `--variant minimal|low|medium|high|xhigh`
  (opencode) or `-c model_reasoning_effort=…` (codex) and name the card accordingly, e.g.
  `--name muse-spark-1.3-contributor@xhigh`. Runs with no explicit variant are marked
  **effort unrecorded**; when the harness does not record one, `aggregate.py` recovers the
  observed variant from opencode's session DB for any card it can match.

Currently indexed: [ETHEVALS](https://ethevals.com). Our own `dapp-lifecycle` benchmark is
parked — it did not discriminate (Muse Spark 1.3 Contributor scored 10/10), so it is out of
the index. Its harness and evals stay in the repo for when harder evals are authored.

## Status

v0.2: cross-benchmark index (`sources/`, `aggregate.py`, `index.json`) with ETHEVALS as the
first source. The `dapp-lifecycle` benchmark is parked (see above); its harness, evals and
self-test remain in the repo. `python3 aggregate.py` produces the marks; the site and the
result-submission flow are next.

## Credits

Format modelled on [ethevals](https://ethevals.com) (MIT). Task ideas owe a debt to
[BuidlGuidl/ethskills-evals](https://github.com/BuidlGuidl/ethskills-evals) and
[clawdbotatg/eth-evals](https://github.com/clawdbotatg/eth-evals). cenobench changes the
measurement: execution instead of judged diffs.

MIT — Ceno Labs Ltd.
