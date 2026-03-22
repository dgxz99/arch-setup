#!/bin/bash
set -e
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

# 检测是否已存在普通用户 (UID 1000)
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
    
    # 交互式输入用户名循环
    while true; do
        echo ""
        # 使用 echo -ne 配合颜色变量实现漂亮的输入提示
        echo -ne "   ${ARROW} ${H_YELLOW}Please enter new username:${NC} "
        read INPUT_USER
        
        # 去除前后空格
        INPUT_USER=$(echo "$INPUT_USER" | xargs)
        
        # 空值检查
        if [[ -z "$INPUT_USER" ]]; then
            warn "Username cannot be empty."
            continue
        fi

        # 确认提示
        echo -ne "   ${INFO} Create user '${BOLD}${H_CYAN}${INPUT_USER}${NC}'? [Y/n] "
        read CONFIRM
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
echo "$MY_USERNAME" > /tmp/daguo_install_user

# ------------------------------------------------------------------------------
# 2. Create User & Sudo
# ------------------------------------------------------------------------------
# 第二步：创建用户和配置 Sudo
# wheel 组是 Arch Linux 中默认的管理员组
# 加入 wheel 组的用户可以使用 sudo 执行管理员命令

section "Step 2/4" "Account & Privileges"

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
    exe useradd -m -g wheel -s /bin/bash "$MY_USERNAME"
    
    # 设置密码
    log "Setting password for $MY_USERNAME..."
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"
    # passwd 需要交互，直接运行 (必须要交互，不能用 exe 包装)
    passwd "$MY_USERNAME"
    PASSWORD_STATUS=$?
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"

    if [ $PASSWORD_STATUS -eq 0 ]; then 
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

# 配置 Faillock (防止输错密码锁定) [新增部分]
log "Configuring password lockout policy (faillock)..."
FAILLOCK_CONF="/etc/security/faillock.conf"

if [ -f "$FAILLOCK_CONF" ]; then
    # 使用 sed 匹配被注释的(# deny =) 或者未注释的(deny =) 行，统一改为 deny = 0
    # 正则解释: ^#\? 匹配开头可选的井号; \s* 匹配可选空格
    exe sed -i 's/^#\?\s*deny\s*=.*/deny = 0/' "$FAILLOCK_CONF"
    success "Account lockout disabled (deny=0)."
else
    # 极少数情况该文件不存在，虽然在 Arch 中默认是有这个文件的
    warn "File $FAILLOCK_CONF not found. Skipping lockout config."
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

section "Step 3/4" "User Directories"

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

# ==============================================================================
# 4. 环境配置 (PATH 与 .local/bin)
# ==============================================================================
section "Step 4/4" "Environment Setup"

# 1. 创建 ~/.local/bin
# 关键点：使用 runuser 确保文件夹归属权是用户，而不是 root
LOCAL_BIN_PATH="$REAL_HOME/.local/bin"

log "Creating user executable directory..."
info_kv "Target" "$LOCAL_BIN_PATH"

if exe runuser -u "$MY_USERNAME" -- mkdir -p "$LOCAL_BIN_PATH"; then
    success "Created directory (Ownership: $MY_USERNAME)"
else
    error "Failed to create ~/.local/bin"
fi

# 2. 配置全局 PATH (/etc/profile.d/)
PROFILE_SCRIPT="/etc/profile.d/user_local_bin.sh"
log "Configuring automatic PATH detection..."

# 写入配置脚本
cat << 'EOF' > "$PROFILE_SCRIPT"
# Automatically add ~/.local/bin to PATH if it exists
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
EOF

# 设置权限 (rw-r--r--)
exe chmod 644 "$PROFILE_SCRIPT"

if [ -f "$PROFILE_SCRIPT" ]; then
    success "PATH script installed to /etc/profile.d/"
    info_kv "Effect" "Requires re-login"
else
    warn "Failed to create profile.d script."
fi

# ==============================================================================
# 完成
# ==============================================================================
hr
success "Module 03 completed."
echo -e "   ${DIM}User '${MY_USERNAME}' is ready for Desktop Environment setup.${NC}"
echo ""