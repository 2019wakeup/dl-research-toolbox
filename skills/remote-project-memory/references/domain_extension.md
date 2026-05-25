# Remote Project Memory 领域扩展规范

`remote-project-memory` Skill 旨在提供一个通用的、持久化的项目记忆框架。为了支持不同领域（如深度学习科研）的特定记忆需求，同时避免核心 Skill 的耦合，本规范定义了领域扩展的机制。

## 1. 核心原则：通用性与可扩展性

-   **通用基础**：`remote-project-memory` 维护项目最核心的 `info/` 和 `tasks/` 结构，包含 `project_summary.md`, `project_goals.md`, `project_architecture.md`, `task_list.md`, `task_progress.md` 等通用文件。
-   **领域插件化**：特定领域的记忆（如深度学习的试错日志、模型结构）应以“插件”的形式，在项目根目录下创建独立的领域目录，或在现有 `info/` 和 `tasks/` 目录下创建领域子目录。
-   **松散耦合**：`remote-project-memory` 不应感知或硬编码任何特定领域的记忆结构。它只提供一个规范化的入口和维护机制，由领域 Skill 负责填充和管理其内部内容。

## 2. 领域扩展机制

领域 Skill 可以通过以下两种方式扩展 `remote-project-memory`：

### 2.1 独立领域目录 (推荐)

为特定领域创建项目根目录下的独立目录，例如 `dl_research/` 或 `ml_ops/`。这种方式提供了最大的灵活性和隔离性。

```
./
├── info/
├── tasks/
├── research/                    # 领域目录 (例如由 deep-learning-research 维护)
│   ├── trial_error_log.md       # 领域特有的试错日志
│   ├── task_tree.md             # 领域任务树，root tasks 只链接到这里
│   └── experiments/             # 分层实验记录，由实验 contract 管理
│       └── <phase_slug>/<series_slug>/<run_id>/
└── ml_ops/                      # 其他领域目录示例
    └── deployment_checklist.md
└── ...
```

**优点**：
-   **高度解耦**：领域记忆与核心记忆完全分离，互不影响。
-   **清晰边界**：每个领域有明确的责任范围。
-   **易于管理**：领域 Skill 可以完全控制其目录结构和文件内容。

**实施**：
-   领域 Skill 负责创建和维护其独立目录及其内部文件。
-   `remote-project-memory` 在初始化时，仅确保核心 `info/` 和 `tasks/` 目录存在。领域 Skill 可以在其初始化或任务开始时，检查并创建自己的领域目录。

### 2.2 `info/` 或 `tasks/` 下的领域子目录

在 `info/` 或 `tasks/` 目录下创建领域特定的子目录，例如 `info/dl_specific/` 或 `tasks/dl_experiments/`。

```
./
├── info/
│   ├── project_summary.md
│   ├── dl_specific/             # 深度学习特定信息子目录
│   │   └── hyperparameter_tuning_strategy.md
│   └── ...
├── tasks/
│   ├── task_list.md
│   ├── dl_experiments/          # 深度学习实验任务子目录
│   │   └── model_training_plan.md
│   └── ...
└── ...
```

**优点**：
-   **结构集中**：将所有信息或任务相关文件集中管理。

**缺点**：
-   **耦合度略高**：领域文件与核心文件在同一层级，可能导致命名冲突或管理混乱。

**实施**：
-   领域 Skill 负责创建和维护这些子目录及其内部文件。
-   `remote-project-memory` 仍不感知这些子目录的具体内容，仅提供父目录的创建。

## 3. 任务树与领域任务集成

`remote-project-memory` 提供的 `tasks/task_list.md` 应作为项目任务的**总览**。领域 Skill 可以在此文件中引用或链接到其内部更详细的任务树结构。

例如，`tasks/task_list.md` 中可以包含：

```markdown
# 项目任务列表

- [ ] 完成数据预处理 [见 research/task_tree.md]
- [ ] 训练 ResNet-50 模型 [见 research/experiments/<phase>/<series>/<run_id>/summary.json]
- [ ] 撰写实验报告
```

## 4. 协同工作机制

-   **`remote-project-memory` 的职责**：确保核心 `info/` 和 `tasks/` 目录及通用文件的存在，并提供更新这些通用文件的接口（例如，当用户提供新的项目总结时）。
-   **领域 Skill 的职责**：在 `remote-project-memory` 提供的基础框架上，创建和管理其领域特定的目录和文件，并负责填充和更新这些文件的内容。

通过这种方式，`remote-project-memory` 保持了其通用性和简洁性，而 `deep-learning-research` 则可以在此基础上构建其复杂的、领域特定的记忆管理系统，两者协同工作而互不耦合。


## 5. Upward Sync

领域目录或子仓库可以维护局部记忆，但不能成为根项目状态的替代品。每次领域记忆或子仓库任务发生实质变化后，必须向上同步到最近的项目记忆根：

- `tasks/task_list.md` 更新高层任务状态，并链接到领域任务树或实验目录；
- `tasks/task_progress.md` 追加同步记录，至少包含子路径、owner、branch/commit 或 run id、证据文件、当前状态和下一步；
- 根 `info/` 只记录全局事实，不复制完整领域日志。


## 6. 可执行约束

在科研仓库中，建议安装 `research-version-isolation` 的 hook guard。它会在 pre-commit 阶段阻止以下问题：

- 子目录意外创建独立 `info/`/`tasks/`；
- 修改 `research/` 或子仓库记忆但没有同步根 `tasks/`；
- 实验 run 平铺在 `research/experiments/` 下；
- 实验 run 缺少必要 JSON/JSONL contract。
