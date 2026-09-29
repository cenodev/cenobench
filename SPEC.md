# CENOBENCH — Benchmark Specification

Version 0.1 (draft) · Status: benchmark `dapp-lifecycle` v0.2.0 (10 evals)

---

## 0. TL;DR

cenobench measures how well AI models and agents actually **build, test, secure and audit
onchain applications**.

It is **execution-graded**. A model is handed a workspace and a prompt, it produces artifacts,
and the harness then builds and runs hidden tests against those artifacts. Pass/fail is
computed, not opined. Reports and reasoning are graded blind only where execution cannot decide.

Every benchmark is a suite of evals. Results are published as JSON cards: one card per
model + harness + skill configuration.

---

## 1. What is measured

Four tracks, in the order a dapp moves through its lifecycle:

| Track | id | Deliverable | How it is graded |
| --- | --- | --- | --- |
| **Build** | `build` | An implementation from a written spec | Hidden Foundry tests run against it |
| **Test** | `test` | A test suite for given code | Mutation kill: tests pass on the real code and fail on every seeded variant |
| **Secure** | `secure` | A fix for a vulnerable contract | Hidden exploit must fail, hidden behavior tests must pass |
| **Audit** | `audit` | A findings report for seeded bugs | Blind judge against an answer key; false positives penalized |

A fifth kind, `quiz`, exists for deterministic knowledge checks (calldata, selectors, token
decimals and other facts agents get wrong). Quiz evals live inside a track and count toward it.

---

## 2. Design principles

1. **Execute, don't admire.** If a claim can be run, run it. Hidden tests beat diff reading.
2. **Keyed to real mistakes.** Every eval names the mistake it targets in `source.mistake`.
3. **Discrimination is proven, not assumed.** Every `exec` eval ships an *unsolved* state, a
   *reference* solution and adversarial *mutants*. The self-test requires:
   **unsolved FAILS, reference PASSES, every mutant FAILS.**
4. **Hidden means hidden.** Tests, mutants and answer keys never enter the workspace before the
   model finishes. An executor that has read the rubric is not being measured.
5. **Frozen means frozen.** Interface files, mocks and build config are hash-checked after the
   run. Tampering to satisfy hidden tests fails the eval.
6. **Binary outcomes.** Each eval passes or fails. No partial credit. A run that crashes,
   times out or hits a quota wall is `dead`, not zero: dead and ungraded rows leave the
   denominator.
7. **Blind judging.** The judge sees evidence and conditions only — never the model or harness.
8. **One YAML per eval.** Adding an eval must not require touching Python. Fixtures live in a
   directory next to it.

---

## 3. Repository layout

```
cenobench/
├── benchmarks/
│   └── <benchmark>/
│       ├── benchmark.yaml                  # suite manifest
│       ├── evals/<track>/<id>.yaml         # one eval per file
│       └── fixtures/<fixture>/             # workspace/ hidden/ reference/ mutants/
├── results/<name>.json                     # one result card per run (committed)
├── results/index.json                      # rolled-up results for the site
├── benchmarks/index.json                   # rolled-up catalog for the site
├── run.py                                  # the harness
├── build.py                                # regenerates the two index files
├── RUN.md                                  # what an agent reads to score itself
└── SPEC.md                                 # this file
```

---

## 4. Benchmark manifest

`benchmarks/<benchmark>/benchmark.yaml`:

```yaml
id: dapp-lifecycle
name: Dapp Lifecycle
version: 0.1.0
desc: >
  Build, test, secure and audit onchain applications. Artifacts are executed, not read.
tracks:
  - id: build
    name: Build
    desc: Implement a dapp or protocol from a spec. Hidden Foundry tests decide.
  - id: test
    name: Test
    desc: Write a suite that catches real regressions. Seeded variants must die.
  - id: secure
    name: Secure
    desc: Fix a live vulnerability without breaking behavior. A hidden exploit decides.
  - id: audit
    name: Audit
    desc: Find what is actually wrong. False positives count against you.
```

The manifest is hashed into every result. Results run against an older manifest are shown
separately from current ones.

---

## 5. Eval schema

Every eval is one YAML file: `benchmarks/<benchmark>/evals/<track>/<id>.yaml`.

### 5.1 Common fields

| Field | Required | Notes |
| --- | --- | --- |
| `id` | yes | Unique, kebab-case, prefixed with the track: `build-01-erc4626-vault` |
| `benchmark` | yes | Benchmark id |
| `track` | yes | `build` \| `test` \| `secure` \| `audit` |
| `title` | yes | Short human title |
| `kind` | yes | `exec` \| `goal` \| `quiz` |
| `summary` | no | One-line description for the catalog; derived from the prompt if absent |
| `prompt` | yes | The exact text handed to the executor on stdin |
| `weight` | no | Default `1`; integer score weight |
| `timing` | no | Per-eval wall-clock override in seconds |
| `source` | yes | `{ mistake: "...", seen_in: "...", credit: "..." }` — which real mistake this targets |
| `fixture` | exec + goal | Fixture directory name under `benchmarks/<benchmark>/fixtures/` |
| `frozen` | no | Workspace-relative files the model must not modify (hash-checked) |
| `deliverable` | exec only | Workspace-relative artifact path that must exist after the run |
| `expect` | goal only | List of judge conditions; one verdict per condition |
| `expect` | goal only | List of judge conditions; one verdict per condition |
| `answer_key` | audit only | The seeded findings; documents ground truth and keeps conditions honest |
| `grader` | quiz only | Deterministic grader (see 5.4) |
| `checks` | no | `must_pass` / `must_fail` fixtures for `--self-test` (quiz evals) |

### 5.2 `kind: exec`

An executed artifact benchmark. The fixture directory supplies the world:

```
fixtures/<fixture>/
├── workspace/      # seeded into the temp workspace the model works in
├── hidden/         # injected after the model finishes, before tests run
├── reference/      # a full solution; must pass hidden tests
└── mutants/<n>/    # deliberate regressions; each must fail hidden tests
```

```yaml
id: build-01-erc4626-vault
benchmark: dapp-lifecycle
track: build
title: ERC-4626 style vault with tracked assets
kind: exec
prompt: |
  ...
fixture: build-01-erc4626-vault
frozen:
  - foundry.toml
  - src/MockERC20.sol
deliverable: src/Vault.sol
exec:
  runner: forge
  match: test/ceno/*.t.sol
  min_tests: 5
  timeout: 600
grading: exec
source:
  mistake: Using balanceOf(address(this)) as accounting, so a direct transfer moves the share price.
  seen_in: real agent output on vault tasks
```

**Lifecycle** (`grading: exec`):

1. Copy `fixtures/<fixture>/workspace/` to a fresh temp directory.
2. Run the executor with `prompt` on stdin, cwd = workspace, until timeout.
3. Snapshot the workspace; record the reply, changed files and durations.
4. Verify every `frozen` file still has its seed hash. Any change fails the eval.
5. Verify `deliverable` exists. Missing fails the eval.
6. Restore frozen files from the seed, copy `fixtures/<fixture>/hidden/` over the workspace.
7. Run `forge test --json` (or `exec.cmd` for `runner: command`).
8. Pass iff the command exits 0, the JSON parses, every test statuses `Success`, and the number
   of tests is at least `min_tests`.

**Lifecycle** (`grading: mutation`):

The same steps, except step 6 does not just inject hidden tests. The model's test files run
against several `src/` variants:

1. Against `fixtures/<fixture>/reference/` — all of the model's tests must pass.
2. Against each `fixtures/<fixture>/mutants/<n>/` — at least one of the model's tests must fail
   for every mutant.
3. `min_tests` is enforced on the reference run to reject empty or trivial suites.

A mutation eval passes only if the model's suite is green on the reference and kills every
mutant. This is the only way to grade test *quality* by execution.

### 5.3 `kind: goal`

A non-executable artifact, e.g. an audit report. The workspace is seeded from a fixture; the
judge — not execution — grades `expect` conditions on the reply and changed files.

```yaml
kind: goal
fixture: audit-01-seeded-defi
expect:
  - 'findings.json is valid JSON and every finding has id, title, severity, location, root_cause, impact, recommendation.'
  - 'Finds the missing access control on Oracle.setPrice and states the manipulation impact.'
  - 'No fabricated critical/high finding outside the seeded issues.'
answer_key:
  - id: oracle-access
    location: src/Oracle.sol
```

### 5.4 `kind: quiz` and deterministic graders

A textual answer graded by a deterministic grader, with a blind judge as the fallback when
`grader` is absent.

| `type` | Fields | Pass condition |
| --- | --- | --- |
| `exact` | `expect`, `case_sensitive` | Normalized answer-line equals `expect` |
| `regex` | `pattern`, `on: answer\|reply`, `case_sensitive` | Pattern matches |
| `regex_all` | `patterns[]` | Every pattern matches |
| `numeric` | `expect`, `tol` | Parsed number within tolerance |
| `bigint` | `expect` (decimal or `0x`) | Exact integer match, ambiguity rejected |
| `json` | `expect` | Parsed JSON deep-matches (strings: exact, `~` = substring, casefold) |
| `any_of` | `options[]` | First matching sub-grader wins |

Every deterministic eval must supply:

- `reference`: a canonical answer string that must pass.
- `checks.must_pass`: at least one phrasing variant that must pass.
- `checks.must_fail`: near-miss answers that must not pass (missing units, wrong case, etc.).

`--self-test` also builds negation probes ("Answer: not X") and requires they fail, so a
grader cannot pass on the phrase "this is not reentrancy".

---

## 6. The discrimination invariant

For every `exec` eval, `python3 run.py --self-test` enforces:

| State | Hidden tests must |
| --- | --- |
| `workspace/` as shipped (unsolved) | **fail** |
| `reference/` overlaid on workspace | **pass** |
| every `mutants/<n>/` overlaid on workspace | **fail** |

A mutant that survives a reference run means the hidden tests do not measure what the eval
claims. A reference that fails means the task is not solvable as specified. Both are build
failures and block the eval from entering the suite. CI runs `--self-test` on every change.

For `grading: mutation`, the same table applies with the gold test suite in
`fixtures/<fixture>/reference-tests/` taking the role of `hidden/`:

| State | Gold tests must |
| --- | --- |
| model suite empty / workspace as shipped | **fail** `min_tests` |
| gold tests vs `reference/` | **pass** |
| gold tests vs every mutant | **fail** |

---

## 7. Executor contract

An executor is any command that:

- reads the prompt on **stdin**;
- writes its reply on **stdout**;
- may write files into its **working directory**, which is a fresh temp workspace.

That is the entire interface. `run.py` ships presets for common harnesses and accepts any
command via `--cmd`, so a new agent framework can be scored without changing cenobench.

```
python3 run.py --name kimi-k2 --executor opencode --model openrouter/moonshotai/kimi-k2
python3 run.py --name my-agent --harness "my harness" --cmd 'my-agent --stdin'
python3 run.py --name kimi-k2+ceno-audit --executor opencode --model ... --skill ./skills/audit/SKILL.md
```

- Working directories are deleted after grading.
- Each eval gets a **fresh** workspace. No state leaks between evals.
- `--skill` installs a SKILL.md into every workspace (and appends an instruction to read it in
  `AGENTS.md` / `CLAUDE.md`) so the same model with and without a skill produce two cards;
  the delta is the point.
- A run that crashes, times out or hits a quota wall is recorded `dead` — not failed — and can
  be resumed with `--resume`.

---

## 8. Results format

One file per run: `results/<slug>.json`.

```json
{
  "name": "kimi-k2+vault-skill",
  "model": "kimi-k2",
  "harness": "opencode",
  "skill": "https://example.com/SKILL.md",
  "executor_cmd": "opencode run --model ...",
  "judge_cmd": "claude -p --model sonnet ...",
  "started": "2026-09-29T18:00:00+00:00",
  "benchmarks": {
    "dapp-lifecycle": {"version": "0.1.0", "manifest": "ab12cd34ef56"}
  },
  "tracks": {
    "build": {"pass": 2, "total": 2},
    "test": {"pass": 1, "total": 1},
    "secure": {"pass": 0, "total": 1},
    "audit": {"pass": 1, "total": 1}
  },
  "total": {"pass": 4, "total": 5},
  "rows": [
    {
      "id": "build-01-erc4626-vault",
      "benchmark": "dapp-lifecycle",
      "track": "build",
      "kind": "exec",
      "seconds": 412.7,
      "rc": 0,
      "reply": "...tail of stdout...",
      "files": ["src/Vault.sol"],
      "detail": "8 tests, 8 passed, 0 failed",
      "pass": true
    }
  ]
}
```

- `manifest` pins the eval set. Rows for evals no longer in the suite are dropped; a result
  whose manifest is stale is listed separately on the site.
- `rows` are sorted by id. Every exec row records which files changed and the hidden-test
  summary, so a surprising verdict can be audited by a human.
- `dead` / `ungraded` rows are excluded from `tracks` and `total` denominators.

---

## 9. Scoring

- Every eval carries a `weight` (default 1). An eval earns its weight when it passes, else 0.
- Track score = `100 × Σ(passed weight) / Σ(suite weight)` for that track. Overall score is the
  same fraction over the whole benchmark.
- **Skipping cannot raise a score.** Dead, ungraded and failed evals all contribute 0 to the
  numerator but stay in the denominator. A run that crashes on an eval scores lower than one
  that fails it honestly, so the reported number is never inflated by an incomplete run.
  `--resume` exists so crashes can be repaired, not ignored.
- `pass/total` counts are recorded alongside `score` so a card can be read either way.
- **Partial credit is secondary.** `subscore` records units inside one eval — hidden tests
  passed, mutants killed, audit conditions met. It appears in per-eval drill-downs and is used
  for tie-breaking insight, never for the headline score, so a model cannot farm easy
  assertions inside one large eval.
- The site ranks cards by overall score. Model, harness and skill are all part of the card's
  identity: one model can appear many times, and the deltas between cards are as interesting as
  the totals.

---

## 10. Adding an eval — checklist

1. Pick the track and the real mistake the eval targets.
2. Write `evals/<track>/<id>.yaml`.
3. For `exec`: build `fixtures/<fixture>/workspace/hidden/reference/mutants`. At least **two**
   mutants per eval. Mutants must be behavior changes, not just removed `require`s that revert
   anyway — they must change an observable outcome.
4. Run `python3 run.py --self-test`. It must be green: unsolved fails, reference passes, every
   mutant fails, quiz fixtures and negation probes pass.
5. Run the eval against at least one weak executor and confirm it fails (paper-solvable evals
   are not evals).
6. Run `python3 build.py` and commit the eval, fixtures and refreshed index.

An eval that cannot be failed by a real model today is too easy. An eval that a correct
implementation cannot pass is broken.

---

## 11. Security and sandboxing

- **v0.1 runs commands locally** in temp directories and is only safe for executors you trust
  and under a timeout. Executor replies and files are third-party code: do not run this on a
  host with secrets in reach.
- v0.2 adds `--sandbox docker`: a slim image with forge, node and python, workspace mounted,
  network disabled after a warm dependency cache, one container per eval.
- Hidden tests, mutants and answer keys must never be committed into a `workspace/` directory
  or referenced from `prompt`. `--self-test` fails an eval whose prompt contains a fixture path,
  the string `answer_key`, or a mutant directory name, as a tripwire.
- Judge prompts receive evidence only. Model and harness names are stripped from evidence.

---

## 12. Roadmap

- v0.1 — this spec, `dapp-lifecycle` first task set, harness, self-test.
- v0.2 — Docker sandbox, `results/` submission flow, site with cards and per-eval drill-down.
- v0.3 — second benchmark (ERC-4626 vaults; AMMs; lending markets; upgrades), rollup/indexer
  and frontend evals, and community-submitted evals.

### Non-goals

- Gas golf and bytecode-size puzzles: real but weakly correlated with shipping dapps.
- Subjective style reviews: the judge exists for reports and reasoning, not aesthetics.
- Multi-turn multi-agent orchestration: cenobench v0 scores a single executor turn per eval.
  Harness identity is recorded so agents and workflows can be compared, but an eval is one
  prompt.

---

## 13. Credits

The format — YAML evals, per-pillar scores, blind judge, manifest-pinned cards — is modelled on
[ethevals](https://ethevals.com) (MIT), which itself ports tasks from
[ethskills-evals](https://github.com/BuidlGuidl/ethskills-evals) and
[clawdbotatg/eth-evals](https://github.com/clawdbotatg/eth-evals). cenobench borrows the shape
and changes the measurement: hidden tests and mutants executed by the harness instead of
judged diffs.
