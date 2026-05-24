# DL Research Toolbox

通用深度学习科研机器工具箱。目标是在一台新 Linux/GPU 机器上快速补齐常用命令行工具、网络代理入口、mihomo 运行脚本和远程实验辅助工具。

本仓库只包含项目无关的工具配置，不包含具体项目代码、数据集、模型权重、conda 环境、PyTorch/CUDA 安装包或任何代理节点凭据。

## 快速开始

```bash
git clone <your-repo-url> dl-research-toolbox
cd dl-research-toolbox

# 先查看会安装什么。
bash scripts/bootstrap.sh --dry-run

# 安装通用系统工具。非 root 用户会自动使用 sudo。
bash scripts/bootstrap.sh

# 安装 mihomo 到 ~/.local/opt/mihomo，并创建 ~/.local/bin/mihomo 链接。
bash scripts/mihomo-install.sh

# 准备 mihomo 配置。该模板不含任何节点或订阅。
mkdir -p ~/.config/mihomo
cp network/mihomo/config.yaml.example ~/.config/mihomo/config.yaml
$EDITOR ~/.config/mihomo/config.yaml

# 启动代理，然后在当前 shell 中启用代理环境变量。
bash scripts/mihomo-start.sh
source scripts/proxy-on.sh

# 检查机器工具、GPU、网络和 mihomo 状态。
bash scripts/check-machine.sh
bash scripts/mihomo-status.sh
```

关闭代理环境变量和 mihomo：

```bash
source scripts/proxy-off.sh
bash scripts/mihomo-stop.sh
```

## 包含内容

- `scripts/bootstrap.sh`：安装通用 Linux 科研 CLI，不安装 conda、PyTorch 或任何项目依赖。
- `scripts/mihomo-install.sh`：从 MetaCubeX/mihomo release 下载当前架构二进制。
- `scripts/mihomo-start.sh` / `mihomo-stop.sh` / `mihomo-status.sh`：用户态运行 mihomo。
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

源机器上发现的可迁移思路记录在 [docs/tool-inventory.md](docs/tool-inventory.md)。该文件只记录工具类别和路径形态，不记录任何敏感代理值。

## 安全检查

推送前建议运行：

```bash
git status --short
git grep -nE 'subscription|token|secret|password|passwd|cookie|Authorization|Bearer|proxy-provider|proxies:' -- .
```

真实 mihomo 配置和 `.env` 文件已在 `.gitignore` 中排除。更多说明见 [docs/security.md](docs/security.md)。
