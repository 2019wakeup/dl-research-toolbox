# DL Research Toolbox

面向深度学习科研机器的轻量初始化工具箱。它把新 Linux/GPU 服务器上最容易卡住的一组通用准备工作收敛成一个可复用流程：先把网络代理跑起来，再安装科研常用 CLI、Codex CLI、`gh`、`npm`、`uv`、tmux、下载工具和一个精简 Python 工具层。

这个仓库刻意保持项目无关：不包含项目代码、数据集、模型权重、checkpoint、conda 环境、PyTorch、CUDA wheel、驱动安装包，也不保存任何真实代理节点或订阅凭据。

## 适合谁

- 经常开新 GPU 机器、AutoDL/云服务器/实验室服务器的人。
- 希望先解决 GitHub、Hugging Face、PyPI、npm 等下载链路，再开始科研项目配置的人。
- 想把一套通用机器初始化流程沉淀成仓库和 Codex skill，而不是每次手工复制命令的人。

## 最短路径

先在一台已有网络的机器上准备 Clash/Mihomo YAML 文件，再传到新机器。新机器上只需要记住一个入口：

```bash
git clone https://github.com/2019wakeup/dl-research-toolbox.git
cd dl-research-toolbox
bash install.sh --mihomo-yaml /root/mihomo.yaml
```

如果你把配置文件命名为 `mihomo.yaml` 并放在仓库目录或 `$HOME` 下，可以省掉参数：

```bash
bash install.sh
```

install.sh 默认会做统一体检；需要复查时运行：

```bash
bash scripts/doctor.sh
```

## 准备 mihomo YAML

新机器第一次配置网络时，推荐直接传本地 Clash/Mihomo YAML，不推荐让新机器在代理启动前访问订阅 URL。原因很简单：订阅地址本身也可能无法直连。

这个 YAML 应该是完整 Clash/Mihomo 配置，可以来自服务商导出的 Clash/Mihomo 配置，或在已有网络的机器上预先下载/转换得到。它不应该是 `ss://`、`vmess://`、`vless://`、`trojan://` 这类原始节点列表。

示例：

```bash
scp ./mihomo.yaml root@your-new-machine:/root/mihomo.yaml
```

真实 YAML 包含代理节点或订阅转换结果，只放在机器本地使用，不要提交进仓库。

## 默认会做什么

`install.sh` 是面向操作者的主入口，内部调用 `scripts/network-first-setup.sh`。默认顺序是：

1. 安装最小网络前置工具：`ca-certificates`、`curl`、`gzip`。
2. 安装 mihomo 到用户本地路径。
3. 从本地 YAML 导入配置，补齐必要运行字段并执行 `mihomo -t` 校验。
4. 启动 mihomo，检查监听、controller 和代理出口。
5. 默认配置 mihomo 自启，并为新 shell 安装代理环境 hook。
6. 在脚本进程内启用代理变量，后续登录/交互 shell 也会自动继承。
7. 先安装 Codex CLI，并补齐 Codex Linux sandbox 需要的 `bubblewrap`/`bwrap`。
8. 再安装通用科研 CLI、`gh`、`npm`、`uv` 和精简 Python 工具层。
9. 运行 `scripts/doctor.sh` 做统一体检。

常用变体：

```bash
# 只把网络和 Codex CLI 配好，不跑完整工具安装。
bash install.sh --mihomo-yaml /root/mihomo.yaml --no-bootstrap

# 旧 mihomo 进程占用端口时替换它。
bash install.sh --mihomo-yaml /root/mihomo.yaml --replace-running

# 不安装 Python research-tools venv。
bash install.sh --mihomo-yaml /root/mihomo.yaml --skip-python-tools

# 不配置开机/登录自启。
bash install.sh --mihomo-yaml /root/mihomo.yaml --no-autostart

# 只查看将要做什么。
bash install.sh --mihomo-yaml /root/mihomo.yaml --dry-run
```

## 自启与代理 Guide

- 给操作者看的说明：[docs/autostart-proxy-guide.md](docs/autostart-proxy-guide.md)
- 给 Codex/自动化看的运行手册：[docs/autostart-proxy-machine-guide.md](docs/autostart-proxy-machine-guide.md)

正常 systemd 机器会安装真正的 system/user service。AutoDL 这类没有 systemd 的容器会使用 profile/profile.d fallback：新 SSH/login shell 自动启动 mihomo，并自动设置 `http_proxy`、`https_proxy`、`all_proxy` 等变量。

## 安装内容

系统和 CLI 工具：

- `gh`、`git`、`git-lfs`
- `npm`、`uv`
- `tmux`、`curl`、`wget`、`aria2`
- `jq`、`rg`、`fzf`、`htop`、`rsync`、`lsof`

Python 工具层安装在 `~/.local/venvs/research-tools`，用于通用数据处理、下载、可视化、测试和 GPU 监控：

- `numpy`、`pandas`、`scipy`、`scikit-learn`
- `matplotlib`、`tqdm`、`rich`、`pyyaml`
- `pillow`、`opencv-python-headless`、`h5py`、`einops`
- `tensorboard`、`huggingface-hub`、`datasets`、`gdown`
- `nvitop`、`pytest`、`ruff`、`ipykernel`

激活方式：

```bash
source ~/.local/venvs/research-tools/bin/activate
```

## Web 控制台

有些服务器不支持 HTTP 内网穿透，或者不适合把控制面板暴露到公网。本仓库提供一个本地 Web 控制台，默认只监听服务器 `127.0.0.1`，通过 SSH 端口转发访问。

推荐方式是在本地机器也保留一份这个仓库，然后直接运行：

```bash
bash scripts/web-tunnel.sh
```

第一次运行时脚本会询问 SSH 目标、端口和远端仓库目录，并保存到本机 `~/.config/dl-research-toolbox/web-tunnel.env`。之后仍然是同一条命令，不需要再查 `user@server` 或端口。

如果要写进自动化脚本，也可以用非交互形式保存 profile：

```bash
bash scripts/web-tunnel.sh --target user@server --ssh-port 22 --remote-dir '~/dl-research-toolbox' --save-profile
```

这个 helper 会同时建立 SSH tunnel，并在远端启动 `scripts/web-ui.sh`。远端脚本会打印带 token 的本地访问地址。

如果只想用底层手动方式，也可以分两步。服务器上启动：

```bash
cd ~/dl-research-toolbox
bash scripts/web-ui.sh --port 8765
```

本地机器建立隧道：

```bash
ssh -N -L 8765:127.0.0.1:8765 user@server
```

控制台支持：

- 查看 mihomo 配置、PID 和运行状态；
- 启动、停止、重启 mihomo；
- 检查代理出口；
- 运行快速/完整体检；
- 查看或修复 mihomo 自启。

这个面板不执行任意命令，只调用仓库内固定脚本。默认生成随机 token；除非你明确知道风险，不要使用 `--host 0.0.0.0` 或 `--no-token`。

## 常用命令

```bash
# 一键安装/更新机器基础工具。
bash install.sh --mihomo-yaml /root/mihomo.yaml

# 一键体检。
bash scripts/doctor.sh

# 安装/更新仓库内打包的 Codex skills。
bash scripts/install-codex-skills.sh

# 本地一条命令启动 SSH tunnel 和远端 Web 控制台。
bash scripts/web-tunnel.sh

# 远端手动启动底层 Web 控制台。
bash scripts/web-ui.sh --port 8765

# 当前 shell 使用本地代理。
source scripts/proxy-on.sh

# 关闭当前 shell 的代理变量。
source scripts/proxy-off.sh

# 手动启动/停止 mihomo。
bash scripts/mihomo-start.sh
bash scripts/mihomo-stop.sh

# 探测并切换到可用的 mihomo 节点。
bash scripts/mihomo-select-best.sh

# 查看 mihomo 状态和代理出口。
bash scripts/mihomo-status.sh --strict --test-proxy

# 手动安装或修复自启。
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
bash scripts/mihomo-autostart.sh status
```

Make 快捷入口：

```bash
make setup
make doctor
make web-tunnel
make web
make mihomo-check
make mihomo-autostart-status
```

## 模板化和 skill 复用

仓库本身可以作为模板直接 fork，也可以通过 Codex skill 复用。`skills/dl-research-toolbox/assets/toolbox/` 是一份完整的轻量模板副本；`skills/dl-research-toolbox/scripts/install_toolbox.sh` 可以把它物化到新目录，或从 GitHub 拉取最新版本。

本仓库同时打包 5 个 Codex skill：

- `dl-research-toolbox`：新机器网络优先初始化、mihomo、CLI 工具、Codex CLI、Web 控制台。
- `dataset-download-network`：大数据集下载链路诊断、下载方式选择、镜像 manifest/hash 校验。
- `remote-project-memory`：非科研远程项目的唯一根记忆、任务列表和向上同步规则；遇到科研/深度学习项目时会让位给 `research-version-isolation`。
- `research-version-isolation`：科研仓库边界、版本隔离、任务图、实验记录 contract，以及可执行 hook guard。
- `deep-learning-research`：深度学习实验流程、小规模验证、实验档案和工程经验沉淀。

科研项目的任务管理现在由 `research-version-isolation` 独立负责，不再和 `remote-project-memory` 同时作用于同一个项目根目录。新 session 应先读 `tasks/task_frontier.md`、`tasks/task_graph.yaml` 和 `tasks/task_events.jsonl`，把用户请求匹配到已有任务，再决定是继续旧任务还是创建新任务。

`research-version-isolation` 要求科研项目用机器可读任务图作为 source of truth：

- `tasks/task_graph.yaml`：任务节点、状态、优先级、依赖/阻塞/验证边、证据、退出条件和下一步。
- `tasks/task_events.jsonl`：追加式任务事件日志。
- `tasks/task_frontier.md`、`tasks/task_index.md`、`tasks/views/`：生成给 agent 读的入口和索引。
- `tasks/task_board.html`：生成给人看的静态 HTML 任务板，可承载高对比度视图、任务图和中英说明。
- `tasks/task_progress.md`：按时间记录人类可读进度，但不再作为当前任务状态的唯一来源。

如果项目内有 `scripts/project/task_graph.py`，任务管理或项目记忆变更收尾前应运行：

```bash
python3 scripts/project/task_graph.py render
python3 scripts/project/task_graph.py gate
```

`gate` 应拦截孤立任务、缺少证据的终态任务、active 任务无 next action、blocked 任务无 blocker、缺少退出条件、证据文件不存在、frontier 引用错误，以及生成视图过期等问题。

从仓库安装或更新这些 skills：

```bash
bash scripts/install-codex-skills.sh
# 或只安装其中一个
bash scripts/install-codex-skills.sh --skill research-version-isolation
```

安装后重启需要使用这些技能的 Codex session。对于研究项目仓库，建议继续安装强制检查 hook：

```bash
bash skills/research-version-isolation/scripts/install_research_hooks.sh /path/to/research-repo
```

如果已经安装了 `dl-research-toolbox` skill，也可以用它物化工具箱模板：

```bash
bash ~/.codex/skills/dl-research-toolbox/scripts/install_toolbox.sh --path ~/dl-research-toolbox
bash ~/.codex/skills/dl-research-toolbox/scripts/install_toolbox.sh --path ~/dl-research-toolbox --network-first --mihomo-file /root/mihomo.yaml
```

为了降低操作者负担，本仓库把常见子任务收敛成少量稳定入口：

- `install.sh`：新机器配置主入口。
- `scripts/install-codex-skills.sh`：把仓库内打包的 Codex skills 同步到 `~/.codex/skills/`。
- `scripts/check-codex-sandbox.sh`：检查 Codex Linux sandbox 的 `bubblewrap` 前置项和容器 namespace 能力。
- `scripts/doctor.sh`：安装后统一体检入口（默认自动启用本地代理环境）。
- `scripts/mihomo-select-best.sh`：通过本地 controller 探测可用节点，并切换 selector 组；日志不输出真实节点名。
- `scripts/web-tunnel.sh`：本地侧 SSH tunnel helper，可保存目标后用一条命令启动远端 Web UI。
- `scripts/web-ui.sh`：远端本地 Web 控制台入口，通过 SSH 端口转发访问。

底层脚本仍然保留，方便排查和局部重跑。

## 明确不做

- 不安装 conda、mamba、PyTorch、TensorFlow、CUDA wheel 或项目依赖。
- 不提交或生成项目代码、数据集、模型权重、checkpoint、实验日志。
- 不提交真实 mihomo `config.yaml`、代理节点、订阅 URL、token、cookie、SSH key。
- 不复制 AutoDL 内置 `/etc/network_turbo`，只在存在时提供条件启用入口。

## 安全检查

推送前建议运行：

```bash
git status --short
git grep -nE 'subscription|token|secret|password|passwd|cookie|Authorization|Bearer|proxy-provider|proxies:' -- .
```

真实 mihomo 配置和 `.env` 文件已在 `.gitignore` 中排除。更多说明见 [docs/security.md](docs/security.md)。

## 文件树简介

```text
.
|-- install.sh                         # 一键安装入口：YAML、代理、自启、Codex CLI、bootstrap、doctor
|-- README.md                          # 项目定位、最快路径、命令说明、边界和文件树
|-- Makefile                           # 常用脚本快捷入口
|-- requirements/
|   `-- research-tools.txt             # 精简通用 Python 科研工具层
|-- scripts/
|   |-- network-first-setup.sh         # 网络优先底层入口
|   |-- doctor.sh                      # 统一体检入口（默认自动启用本地代理环境）
|   |-- web-tunnel.sh                  # 本地侧 SSH tunnel helper
|   |-- web-ui.sh                      # 远端本地 Web 控制台启动器
|   |-- toolbox-web.py                 # Web 控制台后端（Python 标准库）
|   |-- bootstrap.sh                   # 通用 CLI、gh、npm、uv、Python 工具层安装
|   |-- install-codex-cli.sh           # Codex CLI 安装/修复
|   |-- check-codex-sandbox.sh         # Codex bubblewrap/sandbox 前置项检查
|   |-- mihomo-install.sh              # mihomo 二进制安装
|   |-- mihomo-import-subscription.sh  # 本地 Clash/Mihomo YAML 导入、校验、启动、检查
|   |-- mihomo-start.sh                # 用户态启动 mihomo
|   |-- mihomo-stop.sh                 # 停止 toolbox 启动的 mihomo
|   |-- mihomo-status.sh               # 监听、controller、代理出口检查
|   |-- mihomo-autostart.sh            # system/user/profile 自启配置
|   |-- verify-proxy-deep.sh           # GitHub、HF、PyPI、npm、git、uv、Codex 深度检查
|   |-- proxy-on.sh / proxy-off.sh     # 当前 shell 代理环境变量开关
|   |-- network-turbo-on.sh            # 条件启用 AutoDL /etc/network_turbo
|   `-- tmux-research.sh               # 通用远程实验 tmux 会话
|-- network/
|   `-- mihomo/
|       |-- config.yaml.example        # 空示例，不包含真实节点
|       `-- mihomo.env.example         # mihomo 环境变量示例
|-- docs/
|   |-- new-machine.md                 # 新机器安装检查表
|   |-- script-usage.md                # 安装后脚本使用教程
|   |-- autostart-proxy-guide.md       # 给操作者看的 mihomo 自启和代理指南
|   |-- autostart-proxy-machine-guide.md # 给 Codex/自动化看的自启维护手册
|   |-- migration-engineering-notes.md # 迁移问题和处理规则
|   `-- security.md                    # 敏感信息排除和推送前检查
`-- skills/
    `-- dl-research-toolbox/
        |-- SKILL.md                   # Codex skill 工作流说明
        |-- scripts/install_toolbox.sh  # 从 skill 安装/更新 toolbox
        |-- references/                # skill 运行时参考文档
        `-- assets/toolbox/            # skill 内置的仓库模板副本
```
