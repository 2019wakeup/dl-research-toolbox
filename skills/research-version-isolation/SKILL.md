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

## Exclusive Scope For Research Projects

When a local project root is a research/deep-learning workspace, this skill owns the project memory and task system by itself. Do not run `remote-project-memory` in parallel for the same root. Generic remote memory is for non-research projects only.

This skill must initialize and maintain:

- root `info/` project memory;
- root `tasks/` task graph, frontier, event log, generated views, and progress log;
- `research/` domain memory and experiment records;
- upward synchronization from child repos or domain directories.

Research project indicators include datasets, model training/evaluation, papers, experiments, subject splits, checkpoints, `research/`, `data_raw/`, `features/`, or dataset access reports.

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

### Rule 1B: task graph is the source of truth

Root task state must be managed by a machine-readable task graph, not by an ad hoc Markdown todo list.

Required root task files:

- `tasks/task_graph.yaml`: canonical task nodes, statuses, lineage edges, evidence, exit conditions, blockers, and next actions.
- `tasks/task_events.jsonl`: append-only task events; one JSON object per meaningful task state change.
- `tasks/task_frontier.md`: generated session-entry view showing active next tasks, blocked tasks, recently completed tasks, recent events, and do-not-repeat warnings.
- `tasks/task_index.md`: generated task index.
- `tasks/views/`: generated views such as by-status and by-epic.
- `tasks/task_board.html`: generated static human-readable task board.
- `tasks/task_progress.md`: chronological human progress log; not the source of truth for current task state.

`tasks/task_list.md` may exist only as a compact legacy summary or pointer to `task_frontier.md`/`task_graph.yaml`.

Allowed task statuses:

- `backlog`
- `ready`
- `in_progress`
- `blocked`
- `review`
- `done`
- `dropped`

Allowed task edge types:

- `decomposes_to`
- `depends_on`
- `blocks`
- `enables`
- `continues`
- `supersedes`
- `validates`
- `produces`
- `uses`
- `related_to`

Every non-root task must have at least one lineage relation: `parent`, `depends_on`, an incoming edge, or an explicit `related_to` edge. No orphan tasks.

Terminal tasks (`done` or `dropped`) must include evidence unless they are purely administrative and the reason is recorded.

Every substantive task must include an `exit_condition`; a task is not done until the exit condition is satisfied by artifacts.

### Rule 1C: session bootstrap starts from the frontier

At the start of a new session in a research project:

1. Resolve the canonical memory root.
2. Read `tasks/task_frontier.md` if present.
3. Read `tasks/task_graph.yaml`.
4. Read recent entries from `tasks/task_events.jsonl`.
5. Read `info/project_summary.md`.
6. Match the user request to an existing task before creating a new task.

If the request continues existing work, update that existing task and append a `continues` event or edge. Do not create a duplicate task.

If a new task is required, attach it to a parent epic and add at least one relation (`depends_on`, `continues`, `related_to`, etc.) plus a clear exit condition and next action.

### Rule 1D: artifact before status claim

Every status claim must point to evidence:

- Data availability claims point to registry, manifest, checksums, validation reports, or file manifests.
- Experiment claims point to machine-readable experiment records.
- Code implementation claims point to scripts/tests/commits.
- Access blockers point to access notes, license files, request records, or source pages.

If evidence is missing, keep the task in `review`, `blocked`, or `in_progress`, not `done`.

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

## Executable Enforcement

Rules should be enforced with the bundled guard when the workspace is a Git repo.

Install a pre-commit hook from the target repo root:

```bash
bash <skill-dir>/scripts/install_research_hooks.sh .
```

Run manual checks any time:

```bash
python3 <skill-dir>/scripts/research_memory_guard.py --root . --init-root --rebuild-experiment-index
python3 <skill-dir>/scripts/research_memory_guard.py --root . --staged
```

The guard enforces:

- `.project-memory-root` and core `info/`/`tasks/` files;
- no accidental `info/`/`tasks/` memories in ordinary subdirectories;
- staged child/domain memory changes must include upward sync in root `tasks/`;
- experiment runs must use `research/experiments/<phase>/<series>/<run_id>/`;
- experiment runs must have required machine-readable files and be indexed in `research/experiments/index.jsonl`.

If the project has `scripts/project/task_graph.py`, use it to validate and render task views. Before ending any task-management or memory-governance work, this gate must pass:

```bash
python3 scripts/project/task_graph.py render
python3 scripts/project/task_graph.py gate
```

`gate` must fail on warnings such as orphan tasks, missing terminal evidence, active tasks without next actions, blocked tasks without blockers, missing evidence files, missing exit conditions, invalid frontier references, or stale rendered views.

If no task graph tool exists yet, create a minimal one before scaling task management. The v1 tool should validate node ids, statuses, edge endpoints, orphan tasks, terminal-task evidence, and missing evidence files; it should render `task_frontier.md`, `task_index.md`, `tasks/views/`, and `task_board.html`.

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
- root `tasks/task_graph.yaml`
- root `tasks/task_events.jsonl`
- root `tasks/task_frontier.md`
- root `tasks/task_index.md`
- root `tasks/task_board.html`
- root `tasks/task_list.md` as a legacy/generated pointer if needed
- root `tasks/task_progress.md`

These files must describe real facts, not aspirational status.

Minimal task graph node example:

```yaml
nodes:
  - id: DATASET-MDPE
    type: task
    parent: DATASET
    title: MDPE P0 archive acquisition and validation
    status: done
    priority: P0
    exit_condition:
      - expected byte sizes match
      - zipinfo passes
      - hashes and structure checks are recorded
      - registry is updated
    evidence:
      - reports/dataset_access_feature_smoke/mdpe_archive_integrity_summary.csv
    next_action: Use validated archives for bounded feature schema inspection.
edges:
  - from: DATASET-MDPE
    to: FEATURE-MDPE-SCHEMA
    type: enables
```

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
- then update the root task graph, task event log, generated frontier/index views, and summary/progress files with the resulting state
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
