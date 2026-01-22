#!/bin/bash

# ==============================================================================
# 03-user.sh - User Creation & Configuration (Visual Fix)
# ==============================================================================
# 模块说明：用户账户创建与配置
# ------------------------------------------------------------------------------
# 此模块负责创建普通用户并配置 sudo 权限
#
# 主要功能：
#   1. 检测是否已存在 UID 1000 的用户（第一个普通用户）
#   2. 如果不存在，则交互式创建新用户
#   3. 配置 sudo 权限（通过 wheel 组）
#   4. 创建用户目录（Downloads, Documents 等）
#
# 注意：
#   - 用户名会保存到 /tmp/shorin_install_user 供后续脚本使用
#   - 如果用户已存在，只检查和配置权限，不重新创建
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# ------------------------------------------------------------------------------
# 1. User Detection / Creation Logic
# ------------------------------------------------------------------------------
# 第一步：用户检测 / 创建逻辑
# Linux 系统中，UID 1000 通常是第一个普通用户
# 如果 archinstall 已经创建了用户，则使用现有用户

section "Phase 3" "User Account Setup"

# 从 /etc/passwd 中查找 UID 为 1000 的用户
EXISTING_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
MY_USERNAME=""
SKIP_CREATION=false

if [ -n "$EXISTING_USER" ]; then
    # 已存在用户，直接使用
    info_kv "Detected User" "$EXISTING_USER" "(UID 1000)"
    log "Using existing user configuration."
    MY_USERNAME="$EXISTING_USER"
    SKIP_CREATION=true
else
    # 不存在用户，需要交互式创建
    warn "No standard user found (UID 1000)."
    
    while true; do
        echo ""
        # 使用 echo -n 打印普通提示，避免 read -p 的兼容性问题
        echo -ne "   Please enter new username: "
        read INPUT_USER
        
        # 去除可能误输入的空格
        INPUT_USER=$(echo "$INPUT_USER" | xargs)
        
        # 检查用户名是否为空
        if [[ -z "$INPUT_USER" ]]; then
            warn "Username cannot be empty."
            continue
        fi

        # [FIX] 分离打印和读取，确保变量和颜色正确显示
        echo -ne "   Create user '${BOLD}${INPUT_USER}${NC}'? [Y/n] "
        read CONFIRM
        
        # 默认为 Y（确认）
        CONFIRM=${CONFIRM:-Y}
        
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            MY_USERNAME="$INPUT_USER"
            break
        else
            log "Cancelled. Please re-enter."
        fi
    done
fi

# Export username for next scripts
# 导出用户名供后续脚本使用
# 其他模块会读取这个文件获取用户名
echo "$MY_USERNAME" > /tmp/shorin_install_user

# ------------------------------------------------------------------------------
# 2. Create User & Sudo
# ------------------------------------------------------------------------------
# 第二步：创建用户和配置 Sudo
# wheel 组是 Arch Linux 中默认的管理员组
# 加入 wheel 组的用户可以使用 sudo 执行管理员命令

section "Step 2/3" "Account & Privileges"

if [ "$SKIP_CREATION" = true ]; then
    # 用户已存在，检查权限
    log "Checking permissions for $MY_USERNAME..."
    # 检查用户是否已在 wheel 组
    if groups "$MY_USERNAME" | grep -q "\bwheel\b"; then
        success "User is already in 'wheel' group."
    else
        # 添加到 wheel 组
        log "Adding to 'wheel' group..."
        exe usermod -aG wheel "$MY_USERNAME"
    fi
else
    # 创建新用户
    # -m: 创建家目录
    # -g wheel: 主组设为 wheel
    log "Creating new user..."
    exe useradd -m -g wheel "$MY_USERNAME"
    
    # 设置密码
    log "Setting password for $MY_USERNAME..."
    # passwd 需要交互，直接运行
    passwd "$MY_USERNAME"
    if [ $? -eq 0 ]; then 
        success "Password set."
    else 
        error "Failed to set password."
        exit 1
    fi
fi

# Configure Sudoers
# 配置 Sudoers 文件
# /etc/sudoers 控制哪些用户/组可以使用 sudo
# 默认 %wheel ALL=(ALL:ALL) ALL 行被注释，需要取消注释
log "Configuring sudoers..."
if grep -q "^# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    # 取消注释
    exe sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    success "Uncommented %wheel in /etc/sudoers."
elif grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    # 已经启用
    success "Sudo access already enabled."
else
    # 添加新规则
    log "Appending %wheel rule..."
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    success "Sudo access configured."
fi

# ------------------------------------------------------------------------------
# 3. Generate User Directories
# ------------------------------------------------------------------------------
# 第三步：生成用户目录
# xdg-user-dirs 创建标准用户目录：
#   - ~/Downloads (下载)
#   - ~/Documents (文档)
#   - ~/Desktop (桌面)
#   - ~/Music (音乐)
#   - ~/Pictures (图片)
#   - ~/Videos (视频)
#   - ~/Templates (模板)
#   - ~/Public (公共)

section "Step 3/3" "User Directories"

exe pacman -Syu --noconfirm --needed xdg-user-dirs

log "Generating directories (Downloads, Documents...)..."

# 1. 获取目标用户的真实 Home 目录路径
REAL_HOME=$(getent passwd "$MY_USERNAME" | cut -d: -f6)

# 2. 强制指定 HOME 环境变量运行更新命令
# 注意：这里加了 --force 确保即使配置文件已存在也能强制刷新目录结构
# LANG=en_US.UTF-8 确保目录名为英文
if exe runuser -u "$MY_USERNAME" -- env LANG=en_US.UTF-8 HOME="$REAL_HOME" xdg-user-dirs-update --force; then
    success "Directories created in $REAL_HOME."
else
    warn "Failed to generate directories."
fi

log "Module 03 completed."