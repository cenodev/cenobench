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
python3 run.py --name model+audit-skill --executor claude --model m --skill ./skills/audit/SKILL.md
python3 build.py
```

Any command that takes the prompt on stdin, prints the reply on stdout and writes files into
its working directory is an executor (`--cmd`), so a new agent framework can be scored without
touching cenobench's code.

Requirements: Python 3.11+, [Foundry](https://getfoundry.sh) (`forge`) for executed evals,
solc 0.8.28 cached (the harness runs offline once fixtures have compiled once).

## Status

v0.1: benchmark `dapp-lifecycle` (build ×2, test ×1, secure ×1, audit ×1), the harness, the
discrimination self-test and the result indexes. `python3 run.py --self-test` is green. The
site and the result-submission flow are next.

## Credits

Format modelled on [ethevals](https://ethevals.com) (MIT). Task ideas owe a debt to
[BuidlGuidl/ethskills-evals](https://github.com/BuidlGuidl/ethskills-evals) and
[clawdbotatg/eth-evals](https://github.com/clawdbotatg/eth-evals). cenobench changes the
measurement: execution instead of judged diffs.

MIT — Ceno Labs Ltd.
