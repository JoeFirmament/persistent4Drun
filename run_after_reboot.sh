#!/bin/bash

# ==============================================================================
# 主环境设置脚本 (run_after_reboot.sh)
# 每次云环境重启后运行此脚本，负责：
# 1. 安装非持久化系统工具 (如 apt 包)
# 2. 确保 restore_env.sh 和 requirements_combined.txt 位于持久化目录
# 3. 调用持久化目录中的 restore_env.sh 脚本设置 Python 环境
# ==============================================================================

# Define color codes for better output visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'    # No Color

# Set TERM for color support, essential in some terminal environments
export TERM="xterm-256color"
echo -e "TERM is now: $TERM"

echo -e "${YELLOW}====================================================${NC}"
echo -e "${YELLOW}Starting comprehensive environment setup after restart...${NC}"
echo -e "${YELLOW}====================================================${NC}"

# --- Define Paths ---
# Absolute path to the persistent data directory on your cloud instance
PERSISTENT_DATA_PATH="/root/data/persistent" # !! 请确保这是你的实际持久化路径 !!

# The directory where THIS script (run_after_reboot.sh) is being executed from.
# We assume requirements_combined.txt and restore_env.sh are initially alongside THIS script.
SCRIPT_SOURCE_DIR="$(dirname "$0")"

# Source paths: Where the companion files are expected to be initially (next to this script)
RESTORE_SCRIPT_SOURCE="$SCRIPT_SOURCE_DIR/restore_env.sh"
REQUIREMENTS_SOURCE="$SCRIPT_SOURCE_DIR/requirements_combined.txt"

# Target paths: Where the companion files NEED to end up in the persistent storage
PERSISTENT_SETUP_SCRIPT_TARGET="$PERSISTENT_DATA_PATH/restore_env.sh"
REQUIREMENTS_TARGET="$PERSISTENT_DATA_PATH/requirements_combined.txt"


# --- System Package Installation (Non-Persistent) ---
# These tools are installed on the base system and are not persistent.

echo -e "${YELLOW}--- Updating apt package list ---${NC}"
# 执行 apt update，如果失败则警告但不退出（可能能安装部分缓存的包）
# 移除 > /dev/null 2>&1 让更新过程的输出可见，方便诊断源问题
apt-get update
if [ $? -ne 0 ]; then
    echo -e "${RED}Warning: apt-get update failed. Some system dependencies might not be installed from the latest sources.${NC}"
    echo -e "${RED}Please check your internet connection or apt sources. Continuing with potentially cached packages...${NC}"
else
    echo -e "${GREEN}apt-get package list updated.${NC}"
fi

# Optional: Upgrade existing packages. Can be time-consuming, uncomment if needed.
# echo -e "${YELLOW}--- Upgrading system packages ---${NC}"
# apt-get upgrade -y > /dev/null 2>&1
# if [ $? -ne 0 ]; then
#     echo -e "${RED}Warning: apt-get upgrade failed.${NC}"
# fi
# echo -e "${GREEN}System package upgrade complete.${NC}"


# Function: Check and install a system package quietly using apt
# Parameters: $1 - package name
# Checks if the package is installed using dpkg. If not, attempts to install it silently.
# Returns 0 on success (already installed or installed now), 1 on failure to install.
check_and_install_apt_package_quiet() {
    local PACKAGE_NAME="$1" # Use local to keep variable scope within function
    echo -e "${YELLOW}Checking and installing $PACKAGE_NAME...${NC}"

    # Use dpkg to check if the package is installed. This is reliable.
    dpkg -s "$PACKAGE_NAME" >/dev/null 2>&1
    if [ $? -eq 0 ]; then # dpkg -s returns 0 if package is installed
         echo -e "${GREEN}$PACKAGE_NAME package already installed.${NC}"
         return 0 # Package is installed, success
    fi

    # If dpkg didn't find it, attempt to install it.
    echo -e "${YELLOW}$PACKAGE_NAME not installed, attempting installation...${NC}"
    # Perform silent installation. Check exit code for success/failure.
    apt install -y "$PACKAGE_NAME" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to install $PACKAGE_NAME.${NC}"
        # Add specific warnings for critical packages if needed
        if [ "$PACKAGE_NAME" == "libgl1" ]; then
            echo -e "${RED}This might affect display or certain library functionalities required by your application.${NC}"
        fi
        return 1 # Installation failed
    else
        echo -e "${GREEN}$PACKAGE_NAME installed.${NC}"
        return 0 # Installation successful
    fi
}

# --- Call function to install necessary system tools ---
# Add or remove packages from this list as needed for your base system environment.

check_and_install_apt_package_quiet python3-pip # Provides system-level pip, sometimes useful
check_and_install_apt_package_quiet libgl1      # Resolves libGL.so.1 error, crucial for graphics or libraries depending on OpenGL (like parts of matplotlib or OpenCV)
check_and_install_apt_package_quiet curl
check_and_install_apt_package_quiet unzip
check_and_install_apt_package_quiet vim         # Example text editor - useful for debugging

# --- Install session management tool (screen or tmux) ---
# Highly recommended to install one to keep tasks running across disconnects.
# Defaulting to installing 'screen'. Uncomment the 'tmux' line if preferred.
check_and_install_apt_package_quiet screen
# check_and_install_apt_package_quiet tmux


echo -e "${GREEN}--- System package checks and installations complete ---${NC}"
echo ""


# --- Ensure Companion Files are in Persistent Directory ---
# This section checks if restore_env.sh and requirements_combined.txt exist in the persistent path.
# If not found there, it attempts to move them from the directory THIS script is run from.

echo -e "${YELLOW}--- Ensuring required files are in persistent storage ---${NC}"

# --- Validate Persistent Data Directory ---
# Check if the persistent data directory exists and is accessible (readable, writable, executable).
if [ ! -d "$PERSISTENT_DATA_PATH" ] || [ ! -r "$PERSISTENT_DATA_PATH" ] || [ ! -w "$PERSISTENT_DATA_PATH" ] || [ ! -x "$PERSISTENT_DATA_PATH" ]; then
    echo -e "${RED}Error: Persistent data directory not found or inaccessible at $PERSISTENT_DATA_PATH.${NC}"
    echo -e "${RED}Cannot proceed. Please check your volume mounting and permissions.${NC}"
    exit 1 # Fatal error: Persistent storage is unavailable
fi
echo -e "${GREEN}Persistent data directory found and accessible at $PERSISTENT_DATA_PATH.${NC}"


# --- Handle restore_env.sh ---
# Check if restore_env.sh exists in the persistent target location.
if [ ! -f "$PERSISTENT_SETUP_SCRIPT_TARGET" ]; then
    echo -e "${YELLOW}Persistent restore_env.sh not found in $PERSISTENT_DATA_PATH.${NC}"
    echo -e "${YELLOW}Checking if it exists alongside this script at $RESTORE_SCRIPT_SOURCE...${NC}"

    # If the file is NOT in the persistent directory, check if it's next to the running script.
    if [ -f "$RESTORE_SCRIPT_SOURCE" ]; then
        echo -e "${YELLOW}Found restore_env.sh next to this script. Moving to persistent storage...${NC}"
        # Use 'mv -f' to force the move, overwriting if a partial/old file exists at the target.
        # Use 'mkdir -p' to ensure the target directory exists (although PERSISTENT_DATA_PATH is checked above, this is safer if using subdirectories).
        # mkdir -p "$(dirname "$PERSISTENT_SETUP_SCRIPT_TARGET")" # Not needed here as target is root of persistent
        mv -f "$RESTORE_SCRIPT_SOURCE" "$PERSISTENT_SETUP_SCRIPT_TARGET"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to move restore_env.sh from $RESTORE_SCRIPT_SOURCE to $PERSISTENT_SETUP_SCRIPT_TARGET.${NC}"
            exit 1 # Fatal error: Cannot place the essential restore script
        fi
        echo -e "${GREEN}restore_env.sh successfully moved to $PERSISTENT_SETUP_SCRIPT_TARGET.${NC}"

        # Ensure the moved script has execute permissions.
        echo -e "${YELLOW}Ensuring execute permission on $PERSISTENT_SETUP_SCRIPT_TARGET...${NC}"
        chmod +x "$PERSISTENT_SETUP_SCRIPT_TARGET"
         if [ $? -ne 0 ]; then
            echo -e "${RED}Warning: Failed to set execute permission on $PERSISTENT_SETUP_SCRIPT_TARGET.${NC}"
         else
            echo -e "${GREEN}Execute permission set on $PERSISTENT_SETUP_SCRIPT_TARGET.${NC}"
         fi

    else
        # File is not in the persistent path AND not found next to the script - fatal error.
        echo -e "${RED}Error: Persistent restore_env.sh not found in $PERSISTENT_DATA_PATH AND not found next to this script ($RESTORE_SCRIPT_SOURCE).${NC}"
        echo -e "${RED}Cannot proceed. Please ensure 'restore_env.sh' is either in the persistent path or alongside 'run_after_reboot.sh' when you run it.${NC}"
        exit 1 # Fatal error: restore_env.sh is missing from both locations
    fi
else
    # File already exists in the persistent directory. Good.
    echo -e "${GREEN}Persistent restore_env.sh already exists in $PERSISTENT_DATA_PATH.${NC}"
    # Optional: Could add logic here to check if the source is newer and replace, but simple existence check is robust enough for this use case.
    # Ensure it's executable just in case permissions were lost on the persistent volume (unlikely but safe)
    chmod +x "$PERSISTENT_SETUP_SCRIPT_TARGET" > /dev/null 2>&1 || true # Try to set, ignore errors if it fails
fi


# --- Handle requirements_combined.txt ---
# Check if requirements_combined.txt exists in the persistent target location.
if [ ! -f "$REQUIREMENTS_TARGET" ]; then
     echo -e "${YELLOW}Persistent requirements_combined.txt not found in $PERSISTENT_DATA_PATH.${NC}"
     echo -e "${YELLOW}Checking if it exists alongside this script at $REQUIREMENTS_SOURCE...${NC}"

    # If the file is NOT in the persistent directory, check if it's next to the running script.
    if [ -f "$REQUIREMENTS_SOURCE" ]; then
        echo -e "${YELLOW}Found requirements_combined.txt next to this script. Moving to persistent storage...${NC}"
        mv -f "$REQUIREMENTS_SOURCE" "$REQUIREMENTS_TARGET"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to move requirements_combined.txt from $REQUIREMENTS_SOURCE to $REQUIREMENTS_TARGET.${NC}"
            exit 1 # Fatal error: Cannot place the requirements file
        fi # <-- CORRECTED: This was '}' in the previous version
        echo -e "${GREEN}requirements_combined.txt successfully moved to $REQUIREMENTS_TARGET.${NC}"
    else
        # File is not in the persistent path AND not found next to the script - fatal error.
        echo -e "${RED}Error: Persistent requirements_combined.txt not found in $PERSISTENT_DATA_PATH AND not found next to this script ($REQUIREMENTS_SOURCE).${NC}"
        echo -e "${RED}Cannot proceed. Please ensure 'requirements_combined.txt' is either already in the persistent path or located alongside 'run_after_reboot.sh' when you run it.${NC}"
        exit 1 # Fatal error: requirements_combined.txt is missing from both locations
    fi
else
    # File already exists in the persistent directory. Good.
    echo -e "${GREEN}Persistent requirements_combined.txt already exists in $PERSISTENT_DATA_PATH.${NC}"
    # Optional: Could add logic here to check if the source is newer and replace
fi


echo -e "${GREEN}--- Required files check and placement complete ---${NC}"
echo ""


# --- Persistent Python Environment Setup ---
# Call the restore_env.sh script located in the persistent storage to set up the Python environment.
# Note: We need to cd into the persistent directory to execute the script relative to its location.

echo -e "${YELLOW}--- Running persistent Python environment setup ---${NC}"
echo -e "${YELLOW}Changing to persistent directory: $PERSISTENT_DATA_PATH...${NC}"

# Change directory to the persistent location to execute the persistent script
# We already checked if the directory exists and is accessible above, so this cd should succeed.
cd "$PERSISTENT_DATA_PATH"

# Define the persistent setup script path relative to the current directory ($PERSISTENT_DATA_PATH)
# We are sure this file exists now because we handled its placement above.
PERSISTENT_SETUP_SCRIPT_RELATIVE="./restore_env.sh"

# Execute the persistent script. Its output will be shown as part of the main script's output.
"$PERSISTENT_SETUP_SCRIPT_RELATIVE"
PERSISTENT_SCRIPT_EXIT_CODE=$?

# Check the exit status of the persistent script. If it failed, the overall setup failed.
if [ $PERSISTENT_SCRIPT_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}Error: Persistent environment setup script failed with exit code $PERSISTENT_SCRIPT_EXIT_CODE.${NC}"
    echo -e "${RED}Your persistent Python environment might not be fully functional. Please review the output above for errors from restore_env.sh.${NC}"
    exit 1 # Persistent script failure is treated as a fatal error for the overall setup
else
    echo -e "${GREEN}Persistent environment setup script completed successfully.${NC}"
fi

echo -e "${GREEN}--- Persistent Python environment setup complete ---${NC}"
echo ""

# --- Final Instructions ---
# Provide instructions on how to activate the environment after the script finishes.

# Define the virtual environment name and the full path to the activate script.
TARGET_VENV_DIR=".venv-combined-resolve" # Must match the name used in restore_env.sh
# Construct the absolute path to the activate script in the persistent directory
VENV_ACTIVATE_FULL_PATH="$PERSISTENT_DATA_PATH/$TARGET_VENV_DIR/bin/activate"

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}Comprehensive setup script finished.${NC}"
echo -e "${GREEN}====================================================${NC}"
echo ""
echo "Your persistent Python environment is ready at: ${YELLOW}$PERSISTENT_DATA_PATH/$TARGET_VENV_DIR${NC}"
echo ""

# Check if the activate script exists before providing instructions.
# The restore_env.sh script should ensure this is created if it ran successfully.
if [ -f "$VENV_ACTIVATE_FULL_PATH" ]; then
    echo -e "${YELLOW}To activate the environment in your current shell, run:${NC}"
    echo -e "${GREEN}source $VENV_ACTIVATE_FULL_PATH${NC}" # Provide the absolute path for clarity
    echo ""
    echo -e "${YELLOW}Once activated, you can run your python scripts (e.g., python check_pytorch.py, yolo predict...).${NC}"
    echo -e "${YELLOW}Remember to use 'screen' or 'tmux' for long-running tasks!${NC}"
else
    echo -e "${RED}Warning: Could not locate the venv activate script at $VENV_ACTIVATE_FULL_PATH.${NC}"
    echo -e "${RED}Persistent environment setup might have failed despite the script indicating success.${NC}"
    echo -e "${RED}Please check the output from restore_env.sh above for potential errors.${NC}"
fi

echo ""
echo -e "${GREEN}Setup process complete. Proceed with environment activation.${NC}"

exit 0 # Main script completed successfully
