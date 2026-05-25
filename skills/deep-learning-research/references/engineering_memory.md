---
name: research-version-isolation
description: Establish strict repository boundaries, unique sources of truth, phase-by-phase version control, and machine-readable experiment tracking for research and deep-learning workspaces with nested repos, datasets, generated artifacts, and long-running experiments. Use when a user wants to clean up a dirty research workspace, define repo ownership, force each phase into its own versioned checkpoint, standardize experiment records, or keep project status and training runs auditable.
---

# Research Version Isolation

Use this skill when a research workspace has started mixing together:

- nested Git repositories
- raw datasets and generated features
- model repos and data-prep scripts
- runtime logs, caches, checkpoints, and handover bundles
- multiple competing status documents
- ad hoc experiments that are hard to reproduce

This skill is split into two layers:

1. `Governance Layer`: repository ownership, boundary cleanup, and unique sources of truth
2. `Experiment Layer`: phase-based version control, split/config/metrics/checkpoint contracts, and explicit exit conditions

The goal is not just to make `git status` readable. The goal is to make both project state and experiment state auditable.

## Non-negotiable rules

### Rule 1: unique source of truth

Every status claim must have exactly one owner.

- root workspace status: root `info/` and root `tasks/` at the canonical memory root
- child-repo implementation status: the child repo's own tracked files and repo-local memory
- domain research status: namespaced `research/` memory, linked from root `tasks/`
- model implementation status: the model repo itself
- experiment result status: machine-readable experiment records plus concise human summary

Subdirectory memories are allowed only for child repos or explicitly owned domain directories. They must synchronize upward after meaningful changes; they must not create competing project-wide status.

When sources disagree, resolve conflicts in this order:

1. actual artifacts and machine-readable experiment outputs
2. current logs and current code paths
3. current local memory files
4. legacy docs and handover text

In short: `artifact > current logs > local memory > legacy docs`.

### Rule 1A: upward memory synchronization is mandatory

When work happens below the root memory, update local memory first, then synchronize upward.

Required upward sync entry in the nearest parent/root `tasks/task_progress.md`:

- child path or domain path
- owner repo or domain owner
- branch and commit checkpoint when available
- run id or artifact path when relevant
- status change
- next action and next owner

Root `tasks/task_list.md` must remain a high-level index and link to child/domain detail. It must not duplicate full child task trees or experiment logs.

### Rule 2: every phase must have independent version control

This is a hard rule.

For every named phase:

- create or switch to a dedicated branch before substantial work
- land a dedicated commit checkpoint when the phase reaches its exit condition
- do not mix multiple phases into one commit if they can be meaningfully separated

If the workspace has multiple repos:

- governance or shared-script changes go in the root repo
- model or training changes go in the model repo
- data-pipeline implementation changes go in the repo that owns the pipeline

At minimum, each phase must leave behind:

- a branch name
- a commit checkpoint
- updated memory files
- a clear pointer to the next phase owner

### Rule 2A: multi-repo synchronization is asymmetric

This is a hard rule.

When a project spans a root governance repo and one or more child repos:

- the root repo only synchronizes global status, phase conclusions, shared scripts, and governance docs
- each child repo only commits implementation, experiment configs, experiment output indexes, and repo-local memory
- the root repo must not commit child-repo implementation details
- child repos must not become the source of truth for cross-project governance state

Required order for cross-repo progression:

1. child repo lands implementation or validation commit
2. root repo lands status-sync commit

The root repo records `what happened`.
The child repo records `how it was implemented`.

### Rule 3: experiment records are mandatory

Any real training or validation run must record, at minimum:

- subject split configuration
- epoch count
- checkpoint path
- metrics path
- best-model selection rule

These are mandatory even for small baseline runs.

### Rule 4: machine-readable experiment artifacts are mandatory

Each experiment run must produce machine-readable records. Do not rely on terminal logs alone.

Required files:

- `split.json`
- `run_config.json`
- `summary.json`
- `metrics.jsonl`
- `checkpoint_manifest.json`

Optional but recommended:

- `predictions.jsonl`
- `confusion_matrix.json`
- `notes.md`

For the exact field contract, read `references/experiment_contract.md`.

### Rule 5: every phase must have explicit exit conditions

No phase is “done” because the user or docs say so. A phase is done only when its exit conditions are satisfied.

Examples:

- boundary freeze phase: repo ownership is documented, root noise is reduced, and memory files agree with actual artifacts
- minimal training loop phase: data loader, model, train entrypoint, and checkpoint saving all work from the repo root
- smoke-test phase: forward, backward, and small overfit checks all pass
- baseline phase: subject-level split, multi-epoch training, checkpointing, and metrics recording all run end to end

## Governance Layer

### 1. Audit the workspace before editing

Collect:

- all nested `.git` directories
- all `.project-memory-root`, `info/`, `tasks/`, `task/`, and `research/` directories
- root `git ls-files`
- root `git status --short`
- key data/artifact coverage facts if the project has staged outputs

Do not start by editing code. First identify where boundaries are already broken.

### 2. Classify every major path

Assign each major directory to exactly one category:

- `root-governance`: root README, root memory, shared orchestration scripts
- `project-managed`: code/docs owned by the root repo because there is no child repo
- `child-repo`: nested Git repo with its own commit history
- `data-only`: raw datasets and downloaded bundles
- `runtime-output`: logs, caches, checkpoints, generated arrays, archives
- `handover-memory`: prompts, handover bundles, exported summaries

If a directory seems to belong to two categories, that is a boundary bug and must be resolved before scaling the project.

### 3. Land the boundary in files

At minimum, update or create:

- root `.gitignore`
- root `README.md`
- root `info/project_summary.md`
- root `info/project_goals.md`
- root `info/project_architecture.md`
- root `tasks/task_list.md`
- root `tasks/task_progress.md`

These files must describe real facts, not aspirational status.

### 4. Validate governance state

Run:

- `git status --short` in the root repo
- `git status --short` in each child repo that matters
- any local workspace audit script if present

The result should show:

- root noise dramatically reduced
- child repos isolated from parent repo noise
- only intentional source/doc changes left as tracked or trackable work

### 5. Multi-repo state synchronization

When implementation work happens in a child repo:

- first update and commit the child repo
- then update the root repo summary/progress files with the resulting state
- root repo entries should answer:
  - what changed
  - which child repo owns it
  - which branch/commit/checkpoint now represents that phase

## Experiment Layer

### 1. Before starting an experiment phase

You must define:

- phase name
- owning repo
- branch name
- exit condition
- split owner
- output directory

If any of these are unclear, stop and define them first.

### 2. Required run contract

Every non-trivial experiment must write:

- split config
- run config
- metric stream
- checkpoint manifest
- concise summary

Preferred directory shape is classified by phase and experiment series. Do not dump all runs directly under `research/experiments/` with long descriptive names.

```text
research/experiments/
├── index.jsonl
└── <phase_slug>/
    ├── README.md
    └── <series_slug>/
        ├── README.md
        └── <run_id>/
            ├── split.json
            ├── run_config.json
            ├── summary.json
            ├── metrics.jsonl
            ├── checkpoint_manifest.json
            └── notes.md
```

Use short stable slugs: `<phase_slug>` such as `phase-01-smoke`, `<series_slug>` such as `single-batch-overfit` or `baseline-resnet`, and `<run_id>` such as `20260526-1430-r01`. Put long descriptions, tags, and rationale inside `summary.json`, `run_config.json`, `notes.md`, and `index.jsonl`, not in directory names.

### 3. Subject-level split discipline

For subject-independent tasks, the split file must record:

- train subjects
- val subjects
- test subjects
- selection rationale or fold id

Do not permit hidden splits inside code if the task is supposed to be auditable.

### 4. Best-model rule

The best model rule must be explicit and stored in `run_config.json` and summarized in `summary.json`.

Examples:

- `best_model_metric = val_accuracy`
- `best_model_mode = max`
- `checkpoint_every = 1 epoch`

### 5. End-of-phase update

Before ending a phase:

- land the phase commit
- update canonical memory files
- record unresolved risks
- record which repo owns the next phase

If the phase spans multiple repos:

- child repo implementation commit lands first
- root repo synchronization commit lands second

## Research-specific rules

For ML and research workspaces, keep these strict:

1. Feature extraction scripts and training code must not silently depend on being run from each other's directories.
2. Experiment outputs should be reproducible from tracked code and tracked config, not from memory or terminal history.
3. Small-batch smoke-test paths should live in tracked code, and lessons from them should feed into full-run scripts.
4. Stage status by artifact coverage and experiment outputs, not by optimistic prose.

## Minimal checklist

- Root repo has a `.gitignore`
- Nested repos are isolated
- Root status docs agree with actual artifact counts
- One root task progress log exists
- Data and model phases have different owners
- Each phase has its own branch and commit checkpoint
- Each experiment has machine-readable split/config/metrics/checkpoint files
- Experiment hierarchy has phase/series/run classification and `research/experiments/index.jsonl`
- Child/domain memory changes have upward sync entries in root `tasks/task_progress.md`
- Phase exit conditions are defined before declaring progress

## Reference

Read `references/experiment_contract.md` when you need a concrete schema for split/config/metrics/checkpoint tracking.


## 5. 根记忆同步协议

`research/` 是深度学习领域记忆的事实源，但不是项目总览的替代品。每次完成阶段、实验 run、数据处理里程碑或重要试错结论后，必须同步到根记忆：

- `tasks/task_list.md`：只更新高层任务状态，并链接到 `research/task_tree.md` 或实验 run；
- `tasks/task_progress.md`：追加同步记录，包含 child/domain path、branch/commit、run id、关键 artifact、结论和下一步 owner；
- `info/project_summary.md`：仅在项目总体状态或里程碑变化时更新，不复制完整实验日志。

## 6. 实验目录分类规则

不要把所有小实验直接平铺到 `research/experiments/`。使用：

```text
research/experiments/<phase_slug>/<series_slug>/<run_id>/
```

- `phase_slug` 表示阶段，例如 `phase-01-smoke`、`phase-02-baseline`；
- `series_slug` 表示实验族，例如 `single-batch-overfit`、`baseline-resnet`、`ablation-window-size`；
- `run_id` 用短、可排序的唯一编号，例如 `20260526-1430-r01`；
- 长描述写入 `summary.json`、`run_config.json`、`notes.md` 和 `research/experiments/index.jsonl`。


## 7. Hook Guard

规则必须尽量可执行化。科研仓库应安装 `research-version-isolation` 的 hook guard：

```bash
bash <research-version-isolation-skill-dir>/scripts/install_research_hooks.sh .
```

提交前 guard 会检查根记忆、向上同步、实验目录层级和必需实验文件。无法自动推断的实验结论仍需人工写入 `tasks/task_progress.md` 和 `summary.json`，但 hook 会阻止遗漏同步。
