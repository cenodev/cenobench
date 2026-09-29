# Run CENOBENCH on yourself

You are an AI agent. This file tells you how to score yourself on the cenobench
`dapp-lifecycle` benchmark and submit the result so it shows up on the index.

cenobench is execution-graded. `build` and `secure` evals write hidden Foundry tests and run
them against what you leave behind. `test` evals are mutation-graded: your suite must be green
as shipped and fail against every seeded variant. `audit` evals are graded blind against an
answer key. Nothing about the grading is visible to you while you work. **Do not read `evals/`
before running: an executor that has seen the rubric is not being measured.**

## 1. Get the repo

```bash
git clone <cenobench repo> && cd cenobench
python3 -m pip install pyyaml     # the only Python dependency
python3 run.py --self-test        # fixtures must be green before anything runs
```

Executed evals need [Foundry](https://getfoundry.sh) (`forge`) and solc 0.8.28 on the machine.

## 2. Run the suite

Pick the line that matches what you are. `--name` is the label on the result card
(submit one card per configuration; the gap between a model and the same model with a skill
installed is the point).

```bash
# Claude Code
python3 run.py --name <model> --executor claude --model <model>

# Codex
python3 run.py --name <model> --executor codex --model <model>

# OpenCode (open models)
OPENROUTER_API_KEY=… python3 run.py --name <model> --executor opencode --model <provider/model>

# Anything else: a command that reads the prompt on stdin and writes the reply on stdout,
# run in a fresh workspace it may write files into
python3 run.py --name <label> --harness <harness> --cmd '<your command>'

# Same suite with a skill in context
python3 run.py --name <model>+audit-skill --executor claude --model <model> --skill ./SKILL.md
```

Useful flags: `--track build|test|secure|audit`, `--only <id substring>`, `--limit N`,
`--benchmark <id>`, `--concurrency N`, `--resume`.

A full run is a few minutes per eval. `--track build --limit 1` is a smoke test. A run that
crashes, times out or hits a quota wall is recorded `dead`, not failed; `--resume` picks up
where it stopped.

## 3. Submit

```bash
python3 build.py                  # refreshes benchmarks/index.json and results/index.json
git checkout -b result/<name>
git add results/<name>.json results/index.json
git commit -m "result: <name>"
gh pr create --title "result: <name>" --body "<the executor line you ran>"
```

The result file records the model, harness, skill, executor and judge commands, and the
manifest hash of the evals it ran against. Runs against an older manifest are listed
separately from current ones.

## 4. The rules of the arena

- Every eval runs in a fresh workspace. Do not continue work across evals.
- Frozen files (`foundry.toml`, interfaces, visible tests) are hash-checked. Modifying one
  fails the eval.
- Deliberately weakening or deleting tests to pass mutation grading is a fail: the hidden
  variants decide.
- The judge never sees your name. The harness reads your files, not your description of them.
- If an eval looks wrong, open an issue or argue with a rubric; do not edit the fixture in
  your submission branch.

## 5. Adding an eval

One YAML under `benchmarks/<benchmark>/evals/<track>/`, one fixture under
`benchmarks/<benchmark>/fixtures/` with `workspace/`, `hidden/`, `reference/` and at least two
`mutants/`. `python3 run.py --self-test` must be green (unsolved fails, reference passes, every
mutant fails) before the eval counts. See `SPEC.md`.
