# 远程实验监控与管理最佳实践

在深度学习科研中，实验通常运行在远程 GPU 服务器上，且耗时较长。本指南介绍了如何利用 `tmux` 和 SSH 保持实验的稳定性与可监控性。

## 1. 远程环境初始化
每次连接新服务器时，应确保环境具备基础的自动化能力。建议在沙盒启动时运行初始化脚本，安装 `sshpass`、`tmux` 等工具，并配置 SSH 连接复用（ControlMaster），以减少频繁连接带来的延迟和开销。

## 2. 异步实验管理 (tmux)
长时间运行的训练任务必须在 `tmux` 会话中执行，以防止网络中断导致进程被杀。

### 会话命名规范
建议使用具有辨识度的名称：`dl_<project_name>_<experiment_id>`（例如：`dl_resnet_v1`）。

### 启动与守护
启动实验时，应将输出重定向至日志文件，并同时保持 `tmux` 会话活跃。
```bash
tmux new-session -d -s <session_name> "python train.py --config config.yaml 2>&1 | tee train.log"
```

## 3. 实验状态监控
监控应遵循“轻量化”和“按需”原则，避免频繁读取全量日志。

| 监控维度 | 推荐方法 | 频率建议 |
| :--- | :--- | :--- |
| **实时日志** | `tmux capture-pane -t <session> -p` 获取屏幕最后几行 | 预估时长的 50%, 80%, 95% 处各检查一次 |
| **硬件状态** | `nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv` | 启动后 5 分钟检查一次，确认显存未溢出 |
| **指标变化** | 查阅 WandB/TensorBoard 远程链接或读取日志中的 Loss 关键字 | 每小时或每个 Epoch 检查一次 |

## 4. 异常处理与恢复
- **显存溢出 (OOM)**：如果日志中出现 `OutOfMemoryError`，应检查 `nvidia-smi` 确认是否有僵尸进程占用显存，并尝试减小 Batch Size。
- **训练停滞**：若 Loss 连续多个检查点无变化，应通过 `tmux` 查看实时输出，确认是否进入死循环或数据加载阻塞。
- **网络中断**：由于使用了 `tmux`，网络重连后可通过 `tmux attach -t <session>` 恢复交互。

## 5. 自动化准则
- **零阻塞交互**：在脚本中使用 `-o StrictHostKeyChecking=no` 避免手动确认。
- **幂等性操作**：在创建会话或目录前，先检查其是否已存在。
- **结果回传**：实验结束后，使用 `rsync` 或 `scp` 将最优模型权重和关键日志同步至本地或备份路径。
