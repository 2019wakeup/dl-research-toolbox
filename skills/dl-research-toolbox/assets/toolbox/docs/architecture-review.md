# Architecture Review and Command Surface Plan

这份评审记录为什么工具箱需要一个统一入口，以及为什么当前优化选择“薄 CLI 门面”而不是重写脚本体系。

## 现状问题

1. 命令入口过多。README 和 Makefile 直接暴露了 `install.sh`、`doctor.sh`、`mihomo-*`、`proxy-*`、`web-*`、`install-codex-skills.sh` 等多个底层脚本，新用户需要先理解脚本家族再操作。
2. Makefile 只是脚本别名，没有形成任务模型。它能少打字，但不能回答“我现在应该运行哪个命令”。
3. 网络代理是横切关注点。setup、doctor、autostart、Web UI、Codex CLI 都依赖代理状态，但入口分散导致心智负担高。
4. 文档同时讲操作流程和底层排障，第一次使用时信息密度偏高。
5. 现有脚本已经积累了可用的安全边界：真实 Mihomo 配置不入库、冷启动优先本地 YAML、深度检查、AutoDL fallback。大重写容易破坏这些边界。

## 方案比较

### 方案 A：只整理 README

优点：

- 改动小。
- 不影响任何脚本。

缺点：

- 用户仍然要记多个底层命令。
- Web UI、Makefile、Codex skill 仍然没有统一任务入口。
- 架构松散的问题没有真正缓解。

结论：适合作为辅助，但不是主方案。

### 方案 B：重写成 Python CLI 包

优点：

- 可以有完整命令树、配置模型、错误类型和测试结构。
- 未来扩展性最好。

缺点：

- 冷启动机器上 Python 环境、包安装、代理本身可能还没好。
- 迁移成本高，容易把已验证的 Bash 安装路径打碎。
- 对“新机器先把网络跑起来”的目标不够保守。

结论：可以作为长期演进方向，不适合现在一次性切换。

### 方案 C：新增薄 CLI 门面，保留脚本为内部模块

优点：

- 新用户只需要记 `./toolbox`。
- 现有脚本继续作为稳定模块，风险低。
- 可以把常用任务命名成 `setup`、`status`、`doctor`、`check`、`autostart`。
- Makefile、README、Web UI、Codex skill 后续都可以收敛到同一命令面。
- 不引入新依赖，适合冷启动机器。

缺点：

- 底层脚本仍然存在，短期内不是彻底重构。
- 一些 shell 行为，例如“修改当前 shell 的代理变量”，仍然需要 `source scripts/proxy-on.sh`，CLI 只能提示或打印 exports。

结论：当前最优方案。

### 方案 D：命令 manifest + 生成器

优点：

- 可以从一个 YAML/JSON manifest 生成 README 命令表、Makefile、Web UI action table。
- 长期能减少重复维护。

缺点：

- 需要先稳定命令模型。
- 当前直接上 manifest 会增加一层抽象，让第一次维护更难。

结论：适合作为方案 C 之后的第二阶段。

## 已选方向

采用方案 C：新增根入口 `./toolbox`。

设计原则：

- 保留现有脚本，不破坏老命令。
- `./toolbox` 只做路由、帮助和少量组合任务。
- 高层命令按用户目标命名，而不是按文件名命名。
- 新手路径优先：`setup`、`proxy-only`、`status`、`doctor`、`check`。
- 排障路径仍可达：`mihomo start|stop|restart|status|check|best|import|install`。
- 代理环境变量保留显式边界：`./toolbox env` 解释当前 shell 状态，`./toolbox env exports` 可给自动化使用。

## 后续演进

1. 让 Web UI action table 调用 `./toolbox`，减少重复命令定义。
2. 给 `./toolbox` 增加机器可读输出，例如 `./toolbox status --json`。
3. 如果命令面稳定，再引入 manifest 生成 README/Makefile/Web UI 动作。
4. 长期再考虑 Python CLI，但必须保留无依赖冷启动路径。
