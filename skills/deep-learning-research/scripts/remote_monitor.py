import subprocess
import json
import argparse
import sys

def run_command(cmd):
    """
    执行本地或远程命令并返回输出。
    """
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "", "Command timed out", 1

def check_tmux_session(ssh_target, session_name):
    """
    检查远程服务器上是否存在指定的 tmux 会话。
    """
    cmd = f"ssh {ssh_target} 'tmux has-session -t {session_name} 2>/dev/null && echo exists || echo not_found'"
    stdout, _, _ = run_command(cmd)
    return stdout == "exists"

def get_tmux_last_lines(ssh_target, session_name, lines=10):
    """
    获取远程 tmux 会话的最后几行输出。
    """
    cmd = f"ssh {ssh_target} 'tmux capture-pane -t {session_name} -p | tail -n {lines}'"
    stdout, stderr, code = run_command(cmd)
    if code != 0:
        return f"Error capturing pane: {stderr}"
    return stdout

def get_gpu_status(ssh_target):
    """
    获取远程服务器的 GPU 使用情况。
    """
    cmd = f"ssh {ssh_target} 'nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits'"
    stdout, stderr, code = run_command(cmd)
    if code != 0:
        return f"Error getting GPU status: {stderr}"

    gpus = []
    for line in stdout.split('\n'):
        if not line.strip(): continue
        parts = [p.strip() for p in line.split(',')]
        gpus.append({
            "index": parts[0],
            "name": parts[1],
            "util_gpu": parts[2],
            "mem_used": parts[3],
            "mem_total": parts[4]
        })
    return gpus

def main():
    parser = argparse.ArgumentParser(description="远程深度学习任务监控工具")
    parser.add_argument("--target", required=True, help="SSH 目标 (如 user@host)")
    parser.add_argument("--session", help="tmux 会话名称")
    parser.add_argument("--action", choices=["check", "logs", "gpu", "full"], default="full", help="执行的操作")

    args = parser.parse_args()

    status = {"target": args.target}

    if args.action in ["check", "full"] and args.session:
        status["session_exists"] = check_tmux_session(args.target, args.session)

    if args.action in ["logs", "full"] and args.session:
        if status.get("session_exists", True):
            status["last_logs"] = get_tmux_last_lines(args.target, args.session)
        else:
            status["last_logs"] = "Session not found"

    if args.action in ["gpu", "full"]:
        status["gpu_info"] = get_gpu_status(args.target)

    print(json.dumps(status, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
