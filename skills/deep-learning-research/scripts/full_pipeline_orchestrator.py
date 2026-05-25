import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Subset, Dataset
import numpy as np
import random
import argparse
import os
import sys

# 假设 smoke_test_template.py 位于同一目录下，可以直接导入其函数
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from smoke_test_template import set_seed, DummyDataset, run_smoke_test, run_overfit_test

class RealDataset(Dataset):
    """
    一个模拟的真实数据集加载器。
    在实际应用中，这里会加载您的真实数据。
    """
    def __init__(self, data_path, size=10000, input_shape=(1, 28, 28), num_classes=10):
        # 模拟加载大量数据
        print(f"Loading dataset from {data_path} with {size} samples...")
        self.size = size
        self.input_shape = input_shape
        self.num_classes = num_classes
        # 实际项目中，这里会是数据加载逻辑，例如从磁盘读取图像、文本等
        self.data = torch.randn(size, *input_shape) # 模拟数据
        self.labels = torch.randint(0, num_classes, (size,)) # 模拟标签

    def __len__(self):
        return self.size

    def __getitem__(self, idx):
        return self.data[idx], self.labels[idx]

def get_model(input_dim, output_dim):
    """
    返回一个简单的模型。
    在实际应用中，这里会加载您的实际模型架构。
    """
    return nn.Sequential(
        nn.Flatten(),
        nn.Linear(input_dim, 128),
        nn.ReLU(),
        nn.Linear(128, output_dim)
    )

def run_full_training(model, train_loader, val_loader, criterion, optimizer, device="cpu", num_epochs=10, checkpoint_interval=2):
    """
    执行全量训练，并在检查点进行随机小批量抽查。
    """
    model.to(device)

    print("开始全量训练...")
    for epoch in range(num_epochs):
        model.train()
        total_loss = 0
        for i, (inputs, targets) in enumerate(train_loader):
            inputs, targets = inputs.to(device), targets.to(device)

            optimizer.zero_grad()
            outputs = model(inputs)
            loss = criterion(outputs, targets)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()

            if (i + 1) % 100 == 0: # 每100步打印一次训练信息
                print(f"Epoch [{epoch+1}/{num_epochs}], Step [{i+1}/{len(train_loader)}], Loss: {loss.item():.4f}")

        avg_train_loss = total_loss / len(train_loader)
        print(f"Epoch [{epoch+1}/{num_epochs}] finished. Avg Train Loss: {avg_train_loss:.4f}")

        # 随机小批量抽查 (Checkpoint Design for Random Small-batch Checks)
        if (epoch + 1) % checkpoint_interval == 0:
            print(f"进行 Epoch {epoch+1} 的随机小批量抽查...")
            model.eval()
            with torch.no_grad():
                # 从验证集中随机抽取一个batch进行检查
                try:
                    sample_batch = next(iter(val_loader))
                except StopIteration:
                    print("验证集 DataLoader 为空，无法进行抽查。")
                    continue

                inputs, targets = sample_batch[0].to(device), sample_batch[1].to(device)
                outputs = model(inputs)
                val_loss = criterion(outputs, targets)
                print(f"  随机抽查 Loss: {val_loss.item():.4f}")
                # 可以在这里添加更多检查，例如预测准确率、梯度分布等
            model.train()

    print("全量训练完成！")

def main():
    parser = argparse.ArgumentParser(description="深度学习全流程编排工具")
    parser.add_argument("--data_path", type=str, default="./data", help="数据集路径")
    parser.add_argument("--config_path", type=str, default="./config.yaml", help="模型配置文件路径")
    parser.add_argument("--mode", type=str, choices=["smoke_test", "full_train"], default="smoke_test", help="运行模式：小规模冒烟测试或全量训练")
    parser.add_argument("--sample_size", type=int, default=16, help="冒烟测试时使用的数据样本大小")
    parser.add_argument("--num_epochs", type=int, default=5, help="全量训练的 Epoch 数量")
    parser.add_argument("--batch_size", type=int, default=32, help="训练批次大小")
    parser.add_argument("--lr", type=float, default=1e-3, help="学习率")
    parser.add_argument("--checkpoint_interval", type=int, default=1, help="全量训练时每隔多少个 Epoch 进行一次随机小批量抽查")

    args = parser.parse_args()

    set_seed()

    # 模拟加载配置
    # 在实际项目中，这里会解析 config.yaml 来获取模型、优化器、数据集等参数
    input_dim = 28 * 28
    output_dim = 10

    model = get_model(input_dim, output_dim)
    optimizer = optim.Adam(model.parameters(), lr=args.lr)
    criterion = nn.CrossEntropyLoss()
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    if args.mode == "smoke_test":
        print("\n--- 运行小规模冒烟测试 ---")
        # 使用 DummyDataset 进行冒烟测试
        dummy_dataset = DummyDataset(size=args.sample_size * 2, input_shape=(1, 28, 28), num_classes=10)
        dummy_loader = DataLoader(dummy_dataset, batch_size=args.sample_size, shuffle=True)

        # 冒烟测试
        run_smoke_test(model, dummy_loader, criterion, optimizer, device=device, num_steps=2)

        # 单批次过拟合测试
        single_batch = next(iter(dummy_loader))
        run_overfit_test(model, single_batch, criterion, optimizer, device=device)

        print("\n小规模冒烟测试完成。请根据测试结果调整模型、数据管道或训练参数，并确保其工程经验和代码规范已融入到全量运行脚本中。")

    elif args.mode == "full_train":
        print("\n--- 运行全量训练 ---")
        # 模拟加载真实数据集
        full_dataset = RealDataset(args.data_path, size=1000, input_shape=(1, 28, 28), num_classes=10) # 简化为1000个样本
        train_size = int(0.8 * len(full_dataset))
        val_size = len(full_dataset) - train_size
        train_dataset, val_dataset = torch.utils.data.random_split(full_dataset, [train_size, val_size])

        train_loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True)
        val_loader = DataLoader(val_dataset, batch_size=args.batch_size, shuffle=False) # 验证集不需要shuffle

        run_full_training(model, train_loader, val_loader, criterion, optimizer, device=device,
                          num_epochs=args.num_epochs, checkpoint_interval=args.checkpoint_interval)

        print("全量训练完成。")

if __name__ == "__main__":
    main()
