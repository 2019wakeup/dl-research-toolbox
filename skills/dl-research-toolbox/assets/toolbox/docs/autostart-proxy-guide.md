# Mihomo 自启与代理 Guide

这份文档给人看，目标是解释清楚：为什么代理有时“已经启动但 Codex 还是访问不了”，以及怎样把这件事配置成新 shell 无感可用。

## 这个问题是什么

Codex、GitHub、Hugging Face、PyPI、npm 要稳定可用，需要同时满足两件事：

1. `mihomo` 正在运行，并监听 `127.0.0.1:7890`。
2. 当前 shell 有代理环境变量，例如 `http_proxy`、`https_proxy`、`all_proxy`。

只满足第一点时，`curl -x http://127.0.0.1:7890 ...` 可能能通，但普通命令还是不走代理。只满足第二点时，命令会指向一个没启动的本地端口。工具箱的自启逻辑就是把这两件事绑定起来。

## 正常安装或修复

导入真实 Clash/Mihomo YAML 配置后运行：

```bash
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
bash scripts/mihomo-autostart.sh status
```

`--mode auto` 会自动选择当前机器能用的方式：

- 普通 systemd Linux 服务器：安装 system service。
- 有 systemd user manager 的机器：安装 user service。
- AutoDL/容器/SSH 镜像这类没有 systemd 的环境：安装 profile fallback。

默认还会安装 shell 代理环境 hook。root 机器上路径是：

```text
/etc/profile.d/99-dl-research-toolbox-proxy.sh
~/.bashrc
```

之后新登录 shell 和新交互 bash 会自动启动 `mihomo`，并自动设置代理变量。

## AutoDL 容器里的真实边界

一些 AutoDL 容器没有 systemd，PID 1 可能就是 `bash`，也没有 `cron`、`rc.local` 或 systemd user manager。这种环境里，容器内部不存在真正的开机服务管理器。

因此工具箱采用 profile fallback：

- 新 SSH/login shell 打开时自动启动 `mihomo`；
- `/etc/profile.d/99-dl-research-toolbox-proxy.sh` 自动设置代理变量；
- `~/.bashrc` 覆盖非登录交互 bash，例如很多 SSH、tmux 或 AutoDL 终端入口；
- 从这个 shell 启动的 Codex 和常见 CLI 工具会自动走代理，不需要手动 `source scripts/proxy-on.sh`。

这就是 AutoDL 场景下可实现的“无感自启”。它不能在任何 shell 出现之前提前运行，因为容器本身没有服务管理器。

## 验证

常规验证：

```bash
toolbox repair status
toolbox check
```

如果 `mihomo` 监听正常，但 GitHub/Hugging Face/PyPI 或 `codex doctor` 报网络失败，通常是当前 selector 里的出站节点不可达。先运行：

```bash
toolbox repair
```

它会刷新自启 hook、启动 mihomo、短扫并切换到可用节点，再复测 Codex 官方 doctor 和常用出口。

Codex ChatGPT 登录还需要额外验证。`api.openai.com` 可达只说明 API endpoint 可用；`codex login --device-auth` 还会访问 `chatgpt.com/backend-api/codex/deviceauth/usercode`。如果该 endpoint 被当前代理节点返回 `403 Forbidden` 或 Cloudflare challenge，运行：

```bash
toolbox codex-ready
```

这个命令会自动扫描 mihomo selector，并切到一个可以请求 Codex device code 的节点。它不会输出真实节点名，也不会打印一次性 device code。

远端/headless 机器优先使用官方 device-code 登录：

```bash
codex login --device-auth
```

登录后用官方诊断确认 Codex 自己看到的运行环境：

```bash
codex doctor --ascii --summary
```

如果新 shell 的 `codex doctor` 通过，但旧的 Codex TUI 仍然超时，优先怀疑旧进程是在代理 hook 修复前启动的。退出旧 TUI 后重新运行 `codex`。如果提示 app-server、MCP 或 `codex_apps` 相关超时，运行：

```bash
toolbox repair app-server
```

模拟一个干净 login shell：

```bash
env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" SHELL=/bin/bash \
  TERM=xterm-256color PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  bash -lc 'env | grep -i proxy | sort; curl -I -L --max-time 20 https://api.openai.com/v1/models; codex --version'
```

看到这些现象就说明链路正常：

- 代理变量指向 `http://127.0.0.1:7890`；
- `api.openai.com/v1/models` 在没有凭据时返回 `HTTP/2 401`，这代表网络传输可达；
- `codex --version` 能打印版本；
- `verify-proxy-deep.sh` 通过。

## 修复旧路径

如果之前安装过自启，但 hook 里写的是旧仓库路径，例如 `/root/dl-research-toolbox`，直接重跑：

```bash
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
```

脚本会刷新受管理的 hook block，不会因为“看见已有 block”就跳过。

## 临时关闭自动代理环境

如果只想让 `mihomo` 自启，但不想新 shell 自动继承代理变量：

```bash
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger --no-shell-env
```

需要代理时再手动开启：

```bash
source scripts/proxy-on.sh
```

## 不要提交真实配置

真实 Mihomo 配置包含节点或订阅转换结果，只能留在机器本地：

- `mihomo.yaml`
- `~/.config/mihomo/config.yaml`
- 订阅 URL
- token、cookie、SSH key

推送前检查：

```bash
git status --short
git grep -nE 'subscription|token|secret|password|passwd|cookie|Authorization|Bearer|proxy-provider|proxies:' -- .
```
