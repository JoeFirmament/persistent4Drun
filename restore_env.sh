#!/bin/bash

# 设置持久化目录路径 (相对于脚本自身位置)
PERSISTENT_DIR="$(dirname "$0")"

# 进入持久化目录
echo "Navigating to persistent directory: $PERSISTENT_DIR"
cd "$PERSISTENT_DIR" || { echo "Error: Failed to change directory to $PERSISTENT_DIR"; exit 1; }

# 定义目标虚拟环境的名称/路径
TARGET_VENV_DIR=".venv-combined-resolve" # 使用你想要的环境名称
VENV_ACTIVATE="$TARGET_VENV_DIR/bin/activate"
VENV_PIP="$TARGET_VENV_DIR/bin/pip" # 虚拟环境内部的 pip shim

# --- 环境设置 ---

# 检查目标虚拟环境是否已经存在并且看起来可用 (检查 activate 和 pip)
# 现在我们知道即使 activate 没有执行权限，pip 存在且可执行就基本说明环境可用
if [ -f "$VENV_ACTIVATE" ] && [ -x "$VENV_PIP" ]; then
    echo "Found existing virtual environment at ./$TARGET_VENV_DIR."
    ENV_STATUS="exists" # 标记环境状态
else
    # 如果环境不存在或不完整，则使用 python -m venv 创建它
    echo "Virtual environment not found or incomplete at ./$TARGET_VENV_DIR."
    echo "Creating a new virtual environment at ./$TARGET_VENV_DIR using '/opt/conda/bin/python -m venv'..."

    # 确保任何部分创建的目录被清理
    rm -rf "$TARGET_VENV_DIR"

    # 使用基础 python 解释器来创建 venv
    # 请确保这里的路径 '/opt/conda/bin/python' 是你的系统中基础 Python 的正确路径！
    BASE_PYTHON="/opt/conda/bin/python"

    if [ ! -x "$BASE_PYTHON" ]; then
        echo "Error: Base Python interpreter not found or not executable at $BASE_PYTHON."
        exit 1
    fi

    "$BASE_PYTHON" -m venv "$TARGET_VENV_DIR"
    VENV_CREATION_EXIT_CODE=$?

    if [ $VENV_CREATION_EXIT_CODE -ne 0 ]; then
         echo "Error: 'python -m venv' failed with exit code $VENV_CREATION_EXIT_CODE."
         exit 1
    fi

    # 重新检查关键文件是否已创建且可执行 (主要是 pip)
    if [ ! -f "$VENV_ACTIVATE" ] || [ ! -x "$VENV_PIP" ]; then
        echo "Error: Virtual environment creation with 'python -m venv' completed but key files (activate or pip) are missing or not executable."
        # 输出 bin 目录内容以帮助诊断
        echo "Contents of $TARGET_VENV_DIR/bin/ after creation:"
        ls -l "$TARGET_VENV_DIR/bin/"
        exit 1
    fi

    # 手动给 activate 脚本添加执行权限，因为 venv 可能不会自动设置
    echo "Ensuring execute permission on activate script..."
    chmod +x "$VENV_ACTIVATE"
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to set execute permission on $VENV_ACTIVATE."
        # 这通常不是致命错误，因为可以用 source 激活，但提示文件系统可能存在细微问题
    fi

    ENV_STATUS="created" # 标记环境状态为新建
    echo "Virtual environment created and checked."
fi

# --- 安装/更新依赖 ---

REQUIREMENTS_FILE="requirements_combined.txt" # 使用你的 requirements 文件名

if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "Checking/Installing/Updating dependencies from $REQUIREMENTS_FILE into ./$TARGET_VENV_DIR..."
    # 使用虚拟环境内部的 pip shim 来安装/更新依赖
    # 首先确保 uv 安装在环境中，以便后续安装利用 uv 的速度
    echo "Ensuring uv is installed in the virtual environment for faster package management..."
    # 使用环境内部的 pip 安装 uv 包
    "$VENV_PIP" install uv

     if [ $? -ne 0 ]; then
         echo "Error: Failed to install uv into the virtual environment."
         exit 1
     fi
     echo "uv installed in venv."


    # 现在使用环境内部的 pip 来安装你的项目依赖
    # 因为 uv 已经安装在环境中，这个 pip shim 会自动使用 uv 来执行安装
    "$VENV_PIP" install -r "$REQUIREMENTS_FILE"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to install/update dependencies from $REQUIREMENTS_FILE using venv pip."
        # 如果依赖安装失败，环境可能不可用，退出脚本
        exit 1
    fi
    echo "Dependency check/installation/update complete."
else
    echo "Warning: $REQUIREMENTS_FILE not found in $PERSISTENT_DIR. Skipping dependency installation/update."
fi

# --- 完成与激活指示 ---

echo ""
echo "Environment setup script finished."
if [ "$ENV_STATUS" = "exists" ]; then
    echo "The existing environment at ./$TARGET_VENV_DIR is ready."
elif [ "$ENV_STATUS" = "created" ]; then
    echo "A new environment has been created and set up at ./$TARGET_VENV_DIR."
fi
echo "To activate this environment in your current shell, run:"
echo "source ./$TARGET_VENV_DIR/bin/activate"
echo ""
echo "Once activated, you can run your python scripts."

exit 0 # 脚本成功执行完毕
