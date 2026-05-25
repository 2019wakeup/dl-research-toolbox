import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Subset, Dataset
import numpy as np
import random

def set_seed(seed=42):
    """
    固定随机种子，确保实验可复现。
    """
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False

class DummyDataset(Dataset):
    """
    一个简单的虚拟数据集，用于测试模型和数据管道。
    """
    def __init__(self, size=100, input_shape=(1, 28, 28), num_classes=10):
        self.size = size
        self.input_shape = input_shape
        self.num_classes = num_classes
        self.data = torch.randn(size, *input_shape)
        self.labels = torch.randint(0, num_classes, (size,))

    def __len__(self):
        return self.size

    def __getitem__(self, idx):
        return self.data[idx], self.labels[idx]

def run_smoke_test(model, train_loader, criterion, optimizer, device="cpu", num_steps=10):
    """
    执行小规模冒烟测试，验证模型是否能正常训练。
    """
    model.to(device)
    model.train()
    print(f"开始冒烟测试，运行 {num_steps} 个步数...")

    for i, (inputs, targets) in enumerate(train_loader):
        if i >= num_steps:
            break

        inputs, targets = inputs.to(device), targets.to(device)

        optimizer.zero_grad()
        outputs = model(inputs)
        loss = criterion(outputs, targets)
        loss.backward()
        optimizer.step()

        print(f"Step [{i+1}/{num_steps}], Loss: {loss.item():.4f}")

    print("冒烟测试成功完成！")

def run_overfit_test(model, batch_data, criterion, optimizer, device="cpu", threshold=1e-3, max_iters=200):
    """
    执行过拟合测试，验证模型是否能过拟合单批次数据。
    """
    model.to(device)
    model.train()
    inputs, targets = batch_data
    inputs, targets = inputs.to(device), targets.to(device)

    print("开始单批次过拟合测试...")
    for i in range(max_iters):
        optimizer.zero_grad()
        outputs = model(inputs)
        loss = criterion(outputs, targets)
        loss.backward()
        optimizer.step()

        if loss.item() < threshold:
            print(f"在第 {i+1} 次迭代中达到阈值 {threshold}，过拟合测试成功！")
            return True

        if (i + 1) % 50 == 0:
            print(f"Iter [{i+1}/{max_iters}], Loss: {loss.item():.6f}")

    print("过拟合测试未能在规定步数内达到阈值，请检查模型结构或学习率。")
    return False

if __name__ == "__main__":
    # 示例用法
    set_seed()

    # 定义一个极简模型
    model = nn.Sequential(
        nn.Flatten(),
        nn.Linear(28*28, 128),
        nn.ReLU(),
        nn.Linear(128, 10)
    )

    # 数据加载
    dataset = DummyDataset()
    loader = DataLoader(dataset, batch_size=16, shuffle=True)

    # 优化器和损失函数
    optimizer = optim.Adam(model.parameters(), lr=1e-3)
    criterion = nn.CrossEntropyLoss()

    # 1. 冒烟测试
    run_smoke_test(model, loader, criterion, optimizer)

    # 2. 过拟合测试
    single_batch = next(iter(loader))
    run_overfit_test(model, single_batch, criterion, optimizer)
