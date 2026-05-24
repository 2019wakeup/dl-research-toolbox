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

# 一键导入 Clash/Mihomo 订阅 URL、校验配置、启动并检查代理。
# 脚本会无回显提示输入订阅 URL，不会把 URL 写入仓库。
bash scripts/mihomo-import-subscription.sh

# 在当前 shell 中启用代理环境变量。
source scripts/proxy-on.sh

# 检查机器工具、GPU、mihomo 监听和代理连通性。
bash scripts/check-machine.sh
bash scripts/mihomo-status.sh --strict --test-proxy
```

关闭代理环境变量和 mihomo：

```bash
source scripts/proxy-off.sh
bash scripts/mihomo-stop.sh
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

- `scripts/bootstrap.sh`：安装通用 Linux 科研 CLI，不安装 conda、PyTorch 或任何项目依赖。
- `scripts/mihomo-install.sh`：从 MetaCubeX/mihomo release 下载当前架构二进制。
- `scripts/mihomo-import-subscription.sh`：输入 Clash/Mihomo 订阅 URL 后自动导入、校验、启动并检查可用性。
- `scripts/mihomo-start.sh` / `mihomo-stop.sh` / `mihomo-status.sh`：用户态运行 mihomo；状态脚本支持 `--strict --test-proxy`。
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
