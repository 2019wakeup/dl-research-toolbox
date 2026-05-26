---
name: remote-project-memory
description: A skill for creating and maintaining a persistent, generic project memory on a remote host (e.g., GPU server). It establishes a foundational directory structure and core documents for project context (summary, goals, architecture, tasks, progress), designed for extensibility by domain-specific skills without tight coupling.
---

# Remote Project Memory

This skill guides the process of creating and maintaining a persistent, on-host project memory when working on a remote server. It ensures that critical, generic project information is always available in the project's working directory, serving as a single source of truth for the project's status, goals, and architecture.

## Scope Boundary With Research Projects

Do not run this skill alongside `research-version-isolation` for the same local project root. If the workspace is a research or deep-learning project, or if the user asks for research task governance, experiment tracking, dataset/version isolation, task graph management, or phase checkpoints, hand off to `research-version-isolation` and stop applying this skill's task/memory workflow.

This skill owns only generic, non-research remote project memory. `research-version-isolation` owns the full memory and task system for research repositories, including root `info/`, root `tasks/`, task graph, task frontier, event log, experiment records, and upward synchronization.

Research project indicators include any of:

- `research/`, `data_raw/`, `data_processed/`, `features/`, `checkpoints/`, or experiment output directories;
- dataset download/access reports;
- model training/evaluation scripts;
- `research/experiments/` or experiment records;
- user language such as research project, dataset, training run, baseline, paper, experiment, checkpoint, or subject split.

If a generic project later becomes a research project, migrate rather than duplicate: keep existing `info/` prose if useful, create the research task graph under `tasks/`, and record the handoff in `tasks/task_progress.md`.

## Core Principle: Foundational, Extensible, and Decoupled Memory

The primary goal is to establish a standardized, minimal directory structure and set of documents that serve as a **foundational memory layer** for any project. This layer is designed to be **extensible** by other domain-specific skills (like `deep-learning-research`) which can build upon this foundation by adding their specialized memory structures, without creating tight coupling with this core skill.

## Workflow

Upon connecting to a remote host to begin work on a project, follow these steps:

### 0. Resolve the Project Memory Root

First check whether the workspace should be handled by `research-version-isolation` using the scope boundary above. If yes, do not initialize or update this generic memory workflow.

Before creating files, identify the canonical project memory root. Search upward from the current directory for `.project-memory-root`, or for an existing `info/project_summary.md` plus `tasks/task_list.md`. If found, use that ancestor as the root. If multiple candidate roots exist, use the nearest one and mention the ambiguity.

Do not create separate `info/` and `tasks/` memories in arbitrary subdirectories. A subdirectory may have its own memory only when it is an independent child repository or explicitly defined domain workspace. In that case, its state must still be summarized upward into the parent/root memory.

### 1. Check and Initialize Core Structure

First, verify if the foundational `info/` and `tasks/` directories already exist in the canonical project root. If not, create them along with the standard set of Markdown files and a root marker.

```bash
mkdir -p info tasks
touch .project-memory-root info/project_summary.md info/project_goals.md info/project_architecture.md tasks/task_list.md tasks/task_progress.md
```

### 2. Initial Information Population

If these files are newly created and empty, you MUST ask the user for the initial project details to populate them. For example:

> "I've set up the foundational project memory structure on the remote host. Could you please provide the initial project summary, goals, and architecture so I can document them?"

### 3. Ongoing Maintenance of Core Memory

Throughout the entire lifecycle of the project, you MUST keep these core files updated:

-   **`info/project_summary.md`**: Update with high-level project overview, current status, and significant milestones.
-   **`info/project_goals.md`**: Refine or add new specific, measurable objectives as the project evolves.
-   **`info/project_architecture.md`**: Document major system design changes, component interactions, and data flow updates.
-   **`tasks/task_list.md`**: Maintain a comprehensive, high-level list of all project tasks. This can serve as an entry point for more detailed, domain-specific task management systems (e.g., task trees managed by `deep-learning-research`).
-   **`tasks/task_progress.md`**: Chronologically log significant progress updates, key decisions, and any major issues encountered.

Before ending a work session, ensure all core memory files are up-to-date to reflect the latest state of the project. If work happened in a child repository or domain directory, perform an upward sync: record the child path, owner, branch/commit if available, changed status, and next action in the parent/root `tasks/task_progress.md`, and update the high-level item in `tasks/task_list.md`.

## File Structure and Purpose

Here is the foundational file structure this skill establishes:

```
./
├── .project-memory-root          # Marker for the canonical memory root
├── info/
│   ├── project_summary.md       # High-level project overview
│   ├── project_goals.md         # Specific, measurable objectives
│   └── project_architecture.md  # System design, components, and data flow
└── tasks/
    ├── task_list.md             # Comprehensive list of all project tasks (can link to domain-specific task trees)
    └── task_progress.md         # Chronological log of progress and updates
```

## Source-of-Truth and Upward Sync Rules

- Root `info/` and `tasks/` are the canonical project overview and task index for the current memory root.
- Child repositories may keep repo-local `info/`, `tasks/`, or `research/` only for implementation-local facts. They do not replace the parent/root overview.
- Domain directories such as `research/` own detailed domain memory, but root `tasks/task_list.md` must link to the detailed task tree instead of duplicating it.
- After any child or domain memory change, update the nearest parent/root memory with a concise synchronization entry. Required fields: child path, owner, branch/commit or run id, status change, evidence artifact, and next action.
- When local memories disagree, prefer artifacts and machine-readable records, then current logs/code, then child memory, then root summary, then legacy prose.

## Research Repositories

For research repositories, use `research-version-isolation` instead of this skill. Do not pair both skills for the same project root.

## Non-Research Domain Extensions

This skill can be extended by non-research domain-specific skills when they only need generic project memory plus a namespaced domain directory.

For research or deep-learning projects, do not use this extension model. Use `research-version-isolation` as the sole memory/task governance skill for that project root.

For non-research domains, `remote-project-memory` does not manage domain-specific files directly; the owning skill must keep its own namespace synchronized into the generic root memory.
