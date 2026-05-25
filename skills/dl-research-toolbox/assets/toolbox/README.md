# DL Research Toolbox

通用深度学习科研机器工具箱。目标是在一台新 Linux/GPU 机器上快速补齐常用命令行工具、网络代理入口、mihomo 运行脚本和远程实验辅助工具。

本仓库只包含项目无关的工具配置，不包含具体项目代码、数据集、模型权重、conda 环境、PyTorch/CUDA 安装包或任何代理节点凭据。

## 准备 mihomo YAML 配置

新机器第一次配置网络时，优先准备一个本地 Clash/Mihomo YAML 文件，再传到新机器上。不要让新机器在代理启动前通过订阅 URL 下载配置，因为订阅地址本身可能无法直连。

这个 YAML 可以来自服务商提供的 Clash/Mihomo 配置导出，或在一台已有网络的机器上预先下载/转换得到。它应该是完整的 Clash/Mihomo YAML，不是 `ss://`、`vmess://`、`vless://`、`trojan://` 这类原始节点列表。

示例传输：

```bash
scp ./mihomo.yaml root@your-new-machine:/root/mihomo.yaml
```

之后在新机器上使用：

```bash
bash scripts/network-first-setup.sh --file /root/mihomo.yaml
```

真实 YAML 文件包含代理节点或订阅转换结果，只放在机器本地使用，不要提交到这个仓库。

## 快速开始

```bash
git clone <your-repo-url> dl-research-toolbox
cd dl-research-toolbox

# 先查看会安装什么。
bash scripts/bootstrap.sh --dry-run

# 网络优先：先安装 mihomo、导入本地 YAML、检查代理、配置自启，再运行完整 bootstrap。
# 冷启动机器推荐直接传 YAML 文件；订阅 URL 可能在代理启动前不可访问。
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml

# network-first 默认会配置 mihomo 自启；如需关闭：加 --no-autostart。
# network-first 会让 bootstrap 在脚本内部走代理；如果当前交互 shell 也要走代理：
source scripts/proxy-on.sh

# 检查机器工具、GPU、mihomo 监听和代理连通性。
bash scripts/check-machine.sh
bash scripts/mihomo-status.sh --strict --test-proxy
bash scripts/verify-proxy-deep.sh
```

快捷启动代理：

```bash
bash scripts/mihomo-start.sh
source scripts/proxy-on.sh
```

配置 mihomo 自启：

```bash
# network-first 已默认执行自启配置；手动安装或重装自启可运行：
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
bash scripts/mihomo-autostart.sh status

# 真正开机自启，适合正常 systemd 机器。
bash scripts/mihomo-autostart.sh install --mode system
```

关闭代理环境变量和 mihomo：

```bash
source scripts/proxy-off.sh
bash scripts/mihomo-stop.sh
```


## 网络优先原则

新机器上先运行：

```bash
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml
```

这个入口会按顺序执行：

1. 确保最小网络前置工具存在：`ca-certificates`、`curl`、`gzip`；
2. 优先安装 `mihomo`；
3. 从本地 YAML 导入 Clash/Mihomo 配置并校验；
4. 检查 `mixed-port`、controller、DNS 和代理出口；
5. 默认配置 mihomo 自启；
6. 在同一个脚本进程里 `source scripts/proxy-on.sh`；
7. 先安装 Codex CLI：`@openai/codex`；
8. 最后运行完整 `bootstrap.sh`，使 `apt`、`uv`、Python 包下载等后续操作走代理。

`--url` 仍然保留，但只建议在机器已经能直接访问订阅地址时使用。冷启动迁移时应先把 Clash/Mihomo YAML 文件传到新机器，再用 `--file` 导入。

如果已经有旧 mihomo 占用端口：

```bash
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml --replace-running
```

如果只想先配置网络，不跑完整 bootstrap：

```bash
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml --no-bootstrap
```

## 精简科研工具层

`bootstrap.sh` 会默认安装：

- 系统/CLI：`gh`、`git`、`git-lfs`、`npm`、`uv`、`tmux`、`curl`、`wget`、`aria2`、`jq`、`rg`、`fzf`、`htop`、`rsync`、`lsof` 等；
- Python venv：`~/.local/venvs/research-tools`；
- Python 包：`numpy`、`pandas`、`scipy`、`scikit-learn`、`matplotlib`、`tqdm`、`rich`、`pyyaml`、`pillow`、`opencv-python-headless`、`h5py`、`einops`、`tensorboard`、`huggingface-hub`、`datasets`、`gdown`、`nvitop`、`pytest`、`ruff`、`ipykernel`。

如不想安装 Python 工具层：

```bash
INSTALL_PYTHON_TOOLS=0 bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml
```

需要使用这个工具层时：

```bash
source ~/.local/venvs/research-tools/bin/activate
```

## 订阅导入

推荐传入本地 Clash/Mihomo YAML 文件。这样不依赖新机器在代理启动前访问订阅 URL：

```bash
bash scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml
```

无参数运行时也会提示输入本地 YAML 文件路径：

```bash
bash scripts/mihomo-import-subscription.sh
```

`--url` 只建议在机器已经能直接访问订阅地址时使用；冷启动机器不要依赖 URL 导入。

脚本会：

- 读取本地 YAML，或在显式 `--url` 时下载订阅内容；
- 识别 Clash/Mihomo YAML；
- 给缺少运行字段的订阅补上 `mixed-port`、`external-controller`、DNS、默认规则组和规则；
- 备份旧的 `~/.config/mihomo/config.yaml`；
- 运行 `mihomo -t -d ~/.config/mihomo` 校验配置；
- 启动 mihomo，并用 `mihomo-status.sh --strict --test-proxy` 检查监听和代理连通性。

如果当前机器已经有旧 mihomo 占用 `7890` 端口，使用：

```bash
bash scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml --replace-running
```

如果订阅是 `ss://`、`vmess://`、`vless://`、`trojan://` 这类原始节点列表，脚本会拒绝导入。请使用服务商提供的 Clash/Mihomo 订阅，或先在本地转换为 YAML。

## 包含内容

- `scripts/network-first-setup.sh`：推荐入口，先配置 mihomo 代理和默认自启，再安装 Codex CLI，最后运行完整 bootstrap，避免后续下载遇到网络问题。
- `scripts/install-codex-cli.sh`：通过 npm 安装 OpenAI Codex CLI 到 `~/.local/bin/codex`。
- `scripts/bootstrap.sh`：安装通用 Linux 科研 CLI、`gh`、`npm`、`uv`，并在 `~/.local/venvs/research-tools` 安装精简 Python 科研工具层；不安装 conda、PyTorch 或项目依赖。
- `requirements/research-tools.txt`：精简通用 Python 工具清单，覆盖数据处理、可视化、配置、下载、GPU 监控、测试和 lint。
- `scripts/mihomo-install.sh`：从 MetaCubeX/mihomo release 下载当前架构二进制。
- `scripts/mihomo-import-subscription.sh`：优先传入本地 Clash/Mihomo YAML，自动导入、校验、启动并检查可用性；URL 导入只作为显式可选路径。
- `scripts/mihomo-start.sh` / `mihomo-stop.sh` / `mihomo-status.sh`：用户态运行 mihomo；状态脚本支持 `--strict --test-proxy`。
- `scripts/mihomo-autostart.sh`：安装 systemd system/user service 或 profile fallback，实现 mihomo 自动启动。
- `scripts/verify-proxy-deep.sh`：深度验证代理是否覆盖 curl、git、npm、Codex CLI、uv 和 Python 科研工具层。
- `scripts/proxy-on.sh` / `proxy-off.sh`：在当前 shell 中开关 `127.0.0.1:7890` 代理变量。
- `scripts/network-turbo-on.sh`：在 AutoDL 机器上条件启用 `/etc/network_turbo`。
- `scripts/check-machine.sh`：检查常用工具、GPU、网络连通性和代理状态，不打印代理值。
- `scripts/tmux-research.sh`：创建或进入科研实验 tmux 会话。
- `network/mihomo/config.yaml.example`：mihomo 空配置模板，需要使用者自行填入节点或订阅转换结果。

## 明确排除

- 不提交 `~/.config/mihomo/config.yaml`、订阅链接、代理节点、secret、token、cookie。
- 不提交 conda 环境、pip freeze、PyTorch、CUDA wheel、驱动安装包。
- 不提交项目目录、数据集、模型权重、checkpoint、日志和实验产物。
- 不复制 AutoDL 内置 `/etc/network_turbo` 内容，只在存在时提供条件调用入口。

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
|-- README.md                         # 快速开始、网络优先原则、包含/排除范围
|-- Makefile                          # 常用脚本快捷入口
|-- requirements/
|   `-- research-tools.txt            # 精简通用 Python 科研工具层
|-- scripts/
|   |-- network-first-setup.sh        # 新机器首选入口：YAML 导入、代理、自启、Codex CLI、bootstrap
|   |-- bootstrap.sh                  # 通用 CLI、gh、npm、uv、Python 工具层安装
|   |-- install-codex-cli.sh          # Codex CLI 安装/修复
|   |-- mihomo-install.sh             # mihomo 二进制安装
|   |-- mihomo-import-subscription.sh # 本地 Clash/Mihomo YAML 导入、校验、启动、检查
|   |-- mihomo-start.sh               # 用户态启动 mihomo
|   |-- mihomo-stop.sh                # 停止 toolbox 启动的 mihomo
|   |-- mihomo-status.sh              # 监听、controller、代理出口检查
|   |-- mihomo-autostart.sh           # system/user/profile 自启配置
|   |-- verify-proxy-deep.sh          # GitHub、HF、PyPI、npm、git、uv、Codex 深度检查
|   |-- proxy-on.sh / proxy-off.sh    # 当前 shell 代理环境变量开关
|   |-- network-turbo-on.sh           # 条件启用 AutoDL /etc/network_turbo
|   `-- tmux-research.sh              # 通用远程实验 tmux 会话
|-- network/
|   `-- mihomo/
|       |-- config.yaml.example       # 空示例，不包含真实节点
|       `-- mihomo.env.example        # mihomo 环境变量示例
|-- docs/
|   |-- new-machine.md                # 新机器安装检查表
|   |-- script-usage.md               # 安装后脚本使用教程
|   |-- migration-engineering-notes.md# 迁移问题和处理规则
|   `-- security.md                   # 敏感信息排除和推送前检查
`-- skills/
    `-- dl-research-toolbox/
        |-- SKILL.md                  # Codex skill 工作流说明
        |-- scripts/install_toolbox.sh # 从 skill 安装/更新 toolbox
        |-- references/               # skill 运行时参考文档
        `-- assets/toolbox/           # skill 内置的仓库模板副本
```
