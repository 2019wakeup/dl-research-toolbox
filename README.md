# DL Research Toolbox

通用深度学习科研机器工具箱。目标是在一台新 Linux/GPU 机器上快速补齐常用命令行工具、网络代理入口、mihomo 运行脚本和远程实验辅助工具。

本仓库只包含项目无关的工具配置，不包含具体项目代码、数据集、模型权重、conda 环境、PyTorch/CUDA 安装包或任何代理节点凭据。

## 快速开始

```bash
git clone <your-repo-url> dl-research-toolbox
cd dl-research-toolbox

# 先查看会安装什么。
bash scripts/bootstrap.sh --dry-run

# 网络优先：先安装 mihomo、导入订阅并检查代理，再运行完整 bootstrap。
# 脚本会无回显提示输入订阅 URL，不会把 URL 写入仓库。
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml

# 也可以使用订阅 URL：bash scripts/network-first-setup.sh --url 'https://example.com/sub.yaml'
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
# 真正开机自启，适合正常 systemd 机器。
bash scripts/mihomo-autostart.sh install --mode system

# 或使用自动选择；无 systemd 时会退到 profile hook。
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
bash scripts/mihomo-autostart.sh status
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
3. 从本地 YAML 或订阅 URL 导入 Clash/Mihomo 配置并校验；
4. 检查 `mixed-port`、controller、DNS 和代理出口；
5. 在同一个脚本进程里 `source scripts/proxy-on.sh`；
6. 先安装 Codex CLI：`@openai/codex`；
7. 最后运行完整 `bootstrap.sh`，使 `apt`、`uv`、Python 包下载等后续操作走代理。

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
INSTALL_PYTHON_TOOLS=0 bash scripts/network-first-setup.sh
```

需要使用这个工具层时：

```bash
source ~/.local/venvs/research-tools/bin/activate
```

## 订阅导入

推荐交互导入，订阅 URL 不会回显：

```bash
bash scripts/mihomo-import-subscription.sh
```

也可以显式传入 URL，但这可能进入 shell history：

```bash
bash scripts/mihomo-import-subscription.sh --url 'https://example.com/sub.yaml'
```

脚本会：

- 下载订阅内容；
- 识别 Clash/Mihomo YAML；
- 给缺少运行字段的订阅补上 `mixed-port`、`external-controller`、DNS、默认规则组和规则；
- 备份旧的 `~/.config/mihomo/config.yaml`；
- 运行 `mihomo -t -d ~/.config/mihomo` 校验配置；
- 启动 mihomo，并用 `mihomo-status.sh --strict --test-proxy` 检查监听和代理连通性。

如果当前机器已经有旧 mihomo 占用 `7890` 端口，使用：

```bash
bash scripts/mihomo-import-subscription.sh --replace-running
```

如果订阅是 `ss://`、`vmess://`、`vless://`、`trojan://` 这类原始节点列表，脚本会拒绝导入。请使用服务商提供的 Clash/Mihomo 订阅，或先在本地转换为 YAML。

## 包含内容

- `scripts/network-first-setup.sh`：推荐入口，先配置 mihomo 代理，再安装 Codex CLI，最后运行完整 bootstrap，避免后续下载遇到网络问题。
- `scripts/install-codex-cli.sh`：通过 npm 安装 OpenAI Codex CLI 到 `~/.local/bin/codex`。
- `scripts/bootstrap.sh`：安装通用 Linux 科研 CLI、`gh`、`npm`、`uv`，并在 `~/.local/venvs/research-tools` 安装精简 Python 科研工具层；不安装 conda、PyTorch 或项目依赖。
- `requirements/research-tools.txt`：精简通用 Python 工具清单，覆盖数据处理、可视化、配置、下载、GPU 监控、测试和 lint。
- `scripts/mihomo-install.sh`：从 MetaCubeX/mihomo release 下载当前架构二进制。
- `scripts/mihomo-import-subscription.sh`：输入 Clash/Mihomo 订阅 URL 或传入本地 YAML 后自动导入、校验、启动并检查可用性。
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

## 当前源机器盘点

源机器上发现的可迁移思路记录在 [docs/tool-inventory.md](docs/tool-inventory.md)。迁移中的工程问题和处理规则记录在 [docs/migration-engineering-notes.md](docs/migration-engineering-notes.md)。安装后一系列脚本使用教程见 [docs/script-usage.md](docs/script-usage.md)。该文件只记录工具类别和路径形态，不记录任何敏感代理值。

## 安全检查

推送前建议运行：

```bash
git status --short
git grep -nE 'subscription|token|secret|password|passwd|cookie|Authorization|Bearer|proxy-provider|proxies:' -- .
```

真实 mihomo 配置和 `.env` 文件已在 `.gitignore` 中排除。更多说明见 [docs/security.md](docs/security.md)。
