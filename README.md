# 计算云持久化 Python 环境设置指南

本指南介绍如何在云环境中设置一个带有特定持久化目录的 Python 环境，以便在每次重启后快速恢复您的项目依赖和工作环境。

本方案的核心是利用一个持久化存储卷来存放 Python 虚拟环境和项目文件，并通过一套自动化脚本在每次非持久化系统重启后重新链接和激活这个环境。

## 解决的问题

许多计算云环境提供非持久化的根文件系统 (Root Filesystem)。这意味着在机器重启后，`/` 目录下的绝大多数内容（包括通过 `apt` 安装的软件包、用户主目录下的文件、通过 `pip` 安装到系统 Python 中等的包）都会恢复到初始状态或丢失。

然而，通常会提供一个单独的持久化存储卷，挂载到 `/root/data/persistent` 或其他指定路径。这个目录下的内容在重启后会保留。

本方案旨在：

1.  将 Python 虚拟环境及其所有依赖安装到这个**持久化目录**中。
2.  提供一套脚本，在每次重启后自动进行必要的系统准备，并重新连接并校验持久化目录中的 Python 环境。
3.  确保您可以在重启后快速进入并使用之前配置好的 Python 环境。

## 文件结构

本方案涉及三个主要文件：

1.  `run_after_reboot.sh`: 主脚本，每次重启后运行的入口。
2.  `restore_env.sh`: 持久化脚本，存放于持久化目录中，负责 Python 环境的详细设置和依赖安装。
3.  `requirements_combined.txt`: 存放您的所有 Python 项目依赖列表。

您需要将这三个文件保存在一个可以通过 Git Clone 或其他方式在**每次重启后都能获取到**的**同一个临时目录**下（例如，将其放在一个 GitHub 仓库中，重启后克隆到 `/tmp/my_setup/`）。

**初始文件结构 (临时目录，例如克隆后在 `/tmp/my_setup/`)**
```shell
/tmp/my_setup/
├── run_after_reboot.sh
├── restore_env.sh
└── requirements_combined.txt
```

**最终文件结构 (持久化目录，例如 `/root/data/persistent/`)**

在成功运行 `run_after_reboot.sh` 脚本后，您的持久化目录 (`/root/data/persistent/`) 将包含以下结构（您的项目代码和数据也应存放在此）：
```shell
/root/data/persistent/
├── restore_env.sh          # 被主脚本移动/确保在此
├── requirements_combined.txt # 被主脚本移动/确保在此
├── .venv-combined-resolve/ # 由 restore_env.sh 创建的 Python 虚拟环境
│   ├── bin/                # 包含 activate, python, pip 等可执行文件/链接
│   ├── lib/                # 包含 Python 库文件, site-packages 等
│   └── ...
├── your_project_code/      # 您的项目代码 (示例)
├── your_data/              # 您的数据 (示例)
└── ...                     # 其他持久化文件
```

## 脚本说明

### `run_after_reboot.sh` (主启动脚本)

* **作用:** 这是您在每次云环境重启后需要运行的**第一个**脚本。它运行在**非持久化**的基础系统上。
* **职责:**
    1.  更新 `apt` 包列表。
    2.  安装一些必要的非持久化**系统工具** (例如 `curl`, `unzip`, `libgl1`, `screen` 等)。
    3.  检查关键文件 (`restore_env.sh` 和 `requirements_combined.txt`) 是否已存在于**持久化目录**中。
    4.  如果关键文件不在持久化目录中，它会尝试将**与 `run_after_reboot.sh` 放在同一个临时目录下的**这些文件**移动 (`mv`) 到持久化目录 (`/root/data/persistent/`)。
    5.  进入持久化目录。
    6.  执行持久化目录中的 `./restore_env.sh` 脚本。
    7.  在完成所有设置后，提供如何**激活**持久化 Python 环境的命令提示。
* **位置:** 应放在每次启动后都能方便获取和执行的临时位置（例如，每次从 Git 仓库克隆到 `/tmp/my_setup/`）。

### `restore_env.sh` (持久化环境脚本)

* **作用:** 这是存放于**持久化目录**中的脚本，由 `run_after_reboot.sh` 调用执行。它负责管理持久化的 Python 环境。
* **职责:**
    1.  检查 Python 虚拟环境目录 (`.venv-combined-resolve/`) 是否已存在且完整（通过检查关键文件如 `bin/pip`）。
    2.  如果虚拟环境不存在或不完整，使用 **`python -m venv`** 命令在当前目录（持久化目录）下创建它。
    3.  为创建的虚拟环境的 `bin/activate` 脚本手动添加执行权限 (解决了某些文件系统创建时权限不正确的问题)。
    4.  确保虚拟环境内安装了 `uv` 包（用于加速后续依赖安装）。
    5.  使用虚拟环境内的 `pip`（此时会自动调用 `uv`）根据 `requirements_combined.txt` 文件安装或更新所有 Python 依赖。
* **位置:** **必须**存放于你的持久化目录 (`/root/data/persistent/`) 中，并由 `run_after_reboot.sh` 脚本负责将其放置到此处（如果它不在的话）。

### `requirements_combined.txt`

* **作用:** 标准的 Python 依赖列表文件，列出了你的项目需要的所有 Python 包及其版本。
* **位置:** **必须**存放于你的持久化目录 (`/root/data/persistent/`) 中，并由 `run_after_reboot.sh` 脚本负责将其放置到此处（如果它不在的话）。

## 使用方法 (每次重启后)

请按照以下步骤在每次云环境重启后设置你的环境：

1.  **连接到你的云环境:** 使用 SSH 或其他方式连接到你的远程计算实例。

2.  **获取脚本文件:** 将包含 `run_after_reboot.sh`, `restore_env.sh`, 和 `requirements_combined.txt` 的仓库克隆或下载到一个**临时目录**。例如：
    ```bash
    # 连接后执行
    cd ~ # 进入你的用户主目录 (或任何临时位置)
    mkdir my_setup # 创建一个临时目录
    cd my_setup
    git clone your_repo_url . # 克隆你的仓库到当前目录
    # 或者手动上传这三个文件到这个临时目录
    ```

3.  **赋予脚本执行权限:** 导航到存放脚本的临时目录，给 `run_after_reboot.sh` 和 `restore_env.sh` 赋予执行权限：
    ```bash
    cd /path/to/your/temp/setup/directory # 进入你克隆/下载文件的目录
    chmod +x run_after_reboot.sh restore_env.sh
    ```

4.  **运行主设置脚本 (推荐使用 `screen` 或 `tmux`):** **强烈建议**在运行主脚本前启动一个终端会话管理工具（如 `screen` 或 `tmux`），以防止网络中断导致设置过程失败。
    ```bash
    # 在临时目录中执行以下命令
    # 启动 screen 会话
    screen
    # 或者启动 tmux 会话
    # tmux

    # 在 screen 或 tmux 会话内部，执行主脚本
    ./run_after_reboot.sh
    ```
    脚本会开始运行，它会先安装系统工具，然后检查并移动关键文件到 `/root/data/persistent/`，最后调用 `restore_env.sh` 来设置或检查 Python 虚拟环境和安装依赖。这个过程可能需要一些时间，特别是第一次安装依赖时。

    如果需要断开连接：
    * `screen`: 按下 `Ctrl+a`，然后按 `d` 分离会话。
    * `tmux` (默认): 按下 `Ctrl+b`，然后按 `d` 分离会话。
    之后重新连接，使用 `screen -r` 或 `tmux attach` 重新附着。

5.  **等待脚本完成并查看输出:** 观察脚本的输出，确保没有致命错误。脚本最后会提示设置完成，并提供激活 Python 环境的命令。

6.  **激活 Python 环境:** 脚本完成后，根据最后提供的提示，在你的**当前终端会话**中手动执行 `source` 命令来激活虚拟环境：
    ```bash
    # 在看到脚本结束提示后，手动执行
    source /root/data/persistent/.venv-combined-resolve/bin/activate
    ```
    成功激活后，你的终端提示符通常会显示虚拟环境的名称，例如 `(.venv-combined-resolve) your_username@your_hostname:...$`。

7.  **验证设置:** 环境激活后，你可以运行一些命令来验证是否一切正常：
    ```bash
    # 在激活的环境中执行
    python --version # 检查 Python 版本是否是虚拟环境中的
    pip list       # 查看安装的 Python 包列表 (应该包含你的依赖)
    yolo --version # 如果安装了 Ultralytics
    # 运行你的 PyTorch/YOLO/RKNN 测试脚本
    python check_pytorch.py # 如果你有这个脚本
    # yolo predict model=yolo11n.pt ... # 运行你的 YOLO 预测测试
    ```

8.  **运行你的任务:** 现在你可以在这个已激活的持久化 Python 环境中运行你的项目代码和计算任务了。对于长时间运行的任务，请务必在 `screen` 或 `tmux` 会话中启动它们。

## 故障排除 (Troubleshooting)

* **脚本无法执行:** 确保脚本文件 (`run_after_reboot.sh`, `restore_env.sh`) 有执行权限 (`chmod +x <script_name>`)。
* **`apt update` 或 `apt install` 失败:** 检查你的云实例的网络连接，或检查系统的 apt 软件源配置 (`/etc/apt/sources.list`)。
* **持久化目录错误 (`Persistent data directory not found or inaccessible`):** 检查你的持久化存储卷是否正确挂载到了 `/root/data/persistent/`，并确认 root 用户有读写执行权限。
* **`restore_env.sh` 报告错误:** 查看 `run_after_reboot.sh` 输出中包含的 `restore_env.sh` 的具体错误信息。常见的有：
    * **venv 创建失败 (`python -m venv` failed):** 可能磁盘空间不足（虽然我们之前排查过，但仍是可能），或者文件系统存在细微的不兼容问题。确保 `/root/data/persistent` 磁盘空间充足。
    * **依赖安装失败 (`Failed to install dependencies`):** 检查 `requirements_combined.txt` 语法是否有误，检查网络连接以确保可以从 PyPI 或镜像源下载，检查是否有复杂的依赖导致安装失败。
    * **RKNN/NPU 错误 (`cuInit failed` 等):** 这通常意味着 RKNN Toolkit 运行所需的**系统级别**驱动或运行时库缺失或未正确初始化。你需要将这些特定的 RKNN 系统依赖安装和设置命令添加到 `run_after_reboot.sh` 的系统安装部分。这些命令需要查阅你的 RKNN 硬件和软件版本的官方文档。
* **环境激活后 `command not found` (例如 `yolo`):** 确保你执行了 `source /root/data/persistent/.venv-combined-resolve/bin/activate` 命令。确认你的 Python 包确实安装在了 `.venv-combined-resolve` 环境中（可以通过 `cd /root/data/persistent/.venv-combined-resolve/bin` 查看 `pip` 和其他脚本是否存在）。
* **依赖安装很慢:** 这是在某些文件系统上写入大量文件时的正常现象，尤其是大型库如 PyTorch。`uv` 已经利用缓存加速了下载，但写入速度受限于文件系统性能。请耐心等待。

## 定制化

* **持久化路径:** 如果你的持久化目录不是 `/root/data/persistent`，请修改 `run_after_reboot.sh` 脚本顶部的 `PERSISTENT_DATA_PATH` 变量。
* **脚本获取目录:** 脚本假定 `restore_env.sh` 和 `requirements_combined.txt` 在运行 `run_after_reboot.sh` 时位于**同一目录**。
* **系统工具:** 根据需要修改 `run_after_reboot.sh` 脚本中 `check_and_install_apt_package_quiet` 的调用列表，添加或移除系统软件包。
* **Python 依赖:** 修改 `requirements_combined.txt` 文件来增删你的 Python 项目依赖。然后运行 `run_after_reboot.sh`，它会自动更新环境。
* **虚拟环境名称:** 如果你想更改虚拟环境的名称 (`.venv-combined-resolve`)，需要在 `restore_env.sh` 和 `run_after_reboot.sh` 中都修改 `TARGET_VENV_DIR` 变量。
* **RKNN 系统依赖:** **这是最可能需要你根据实际情况定制的部分。** 在 `run_after_reboot.sh` 的系统安装部分，找到安装 RKNN 运行时依赖的占位符位置，添加你从官方文档或厂商获取的实际安装命令。

注意所有脚本中没有包含：
To activate the environment in your current shell, run:
source /root/data/persistent/.venv-combined-resolve/bin/activate

Once activated, you can run your python scripts (e.g., python check_pytorch.py, yolo predict...).
Remember to use 'screen' or 'tmux' for long-running tasks!

这是因为虚拟环境和环境变量，只能由父传递给子， 执行两个脚本的时候实际上是调起两个子进程去执行的，所以在子进程内进入虚拟环境，退出后父进程是没有虚拟环境的。
换句话说，执行完之后的环境变量和虚拟环境，就消失了。 回到父进程，也就是你现在的 shell，什么都没有。

