#!/bin/bash

# ==============================================================================
# 04-user.sh - User Account & Environment Setup (Compatible with detect_target_user)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

if ! command -v visudo >/dev/null 2>&1; then
    error "visudo is required to validate sudoers configuration."
    exit 1
fi

# ==============================================================================
# Phase 1: 用户识别与账户同步
# ==============================================================================
section "Phase 4" "User Account Setup"

# 强制清理用户缓存，避免上一次安装中选择的用户误用于当前机器。
rm -f /tmp/daguo_install_user
# 调用全局函数，确定目标用户
detect_target_user

# 检查系统是否已经真的创建了这个账户
if id "$TARGET_USER" &>/dev/null; then
    success "User '${TARGET_USER}' already exists in the system."
    SKIP_CREATION=true
else
    log "User '${TARGET_USER}' does not exist. Preparing for creation..."
    SKIP_CREATION=false
fi

# ==============================================================================
# Phase 2: 账户创建、权限与密码配置
# ==============================================================================
section "Step 2/4" "Account & Privileges"

if [ "$SKIP_CREATION" = true ]; then
    log "Ensuring $TARGET_USER belongs to 'wheel' group..."
    if groups "$TARGET_USER" | grep -q "\bwheel\b"; then
        success "User is already in 'wheel' group."
    else
        log "Adding user to 'wheel' group..."
        exe usermod -aG wheel "$TARGET_USER"
    fi
else
    log "Creating new user '${TARGET_USER}'..."
    # 使用 -m 创建家目录，-g wheel 加入特权组
    exe useradd -m -G wheel -s /bin/bash "$TARGET_USER"
    
    log "Setting password for ${TARGET_USER}..."
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"
    # passwd 必须交互运行
    passwd "$TARGET_USER"
    PASSWORD_STATUS=$?
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"
    
    if [ $PASSWORD_STATUS -eq 0 ]; then 
        success "Password set successfully."
    else 
        error "Failed to set password. Script aborted."
        exit 1
    fi
fi

# 1. 配置 Sudoers
log "Configuring sudoers..."

# A. 确保 wheel 组具备基础 sudo 权限 (需要密码)
WHEEL_SUDO_FILE="/etc/sudoers.d/10-${TARGET_USER}-wheel"
log "Installing wheel sudo rule via sudoers.d..."
cat << 'EOF' > "$WHEEL_SUDO_FILE"
# Daguo Setup: wheel group standard sudo access
%wheel ALL=(ALL:ALL) ALL
EOF
exe chmod 440 "$WHEEL_SUDO_FILE"

#==============================================================================
# B. 配置免密规则 (pacman, systemctl, sudoedit)
# SUDO_CONF_FILE="/etc/sudoers.d/20-${TARGET_USER}-nopasswd"
# log "Installing specialized NOPASSWD rules..."

# cat << EOF > "$SUDO_CONF_FILE"
# # Daguo Setup: Essential tools NOPASSWD for wheel group
# %wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/systemctl, /usr/bin/sudoedit
# EOF

# exe chmod 440 "$SUDO_CONF_FILE"
#==============================================================================

if visudo -cf /etc/sudoers >/dev/null 2>&1; then
    success "Sudo rules validated and installed."
else
    error "Sudoers validation failed. Rolling back drop-in files."
    rm -f "$WHEEL_SUDO_FILE" "$SUDO_CONF_FILE"
    exit 1
fi

# 2.配置 Faillock (防止输错密码锁定)
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

exe pacman -S --noconfirm --needed xdg-user-dirs

log "Generating directories (Downloads, Documents...)..."

# 1. 获取目标用户的真实 Home 目录路径
REAL_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# 2. 强制指定 HOME 环境变量运行更新命令
# 注意：这里加了 --force 确保即使配置文件已存在也能强制刷新目录结构
# LANG=en_US.UTF-8 确保目录名为英文
if exe runuser -u "$TARGET_USER" -- env LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 HOME="$REAL_HOME" xdg-user-dirs-update --force; then
    success "Directories created in $REAL_HOME."
else
    warn "Failed to generate standard directories."
fi

# ==============================================================================
# 4. 环境配置 (PATH 与 .local/bin)
# ==============================================================================
section "Step 4/4" "Environment Setup"

# 1. 创建 ~/.local/bin
# 关键点：使用 runuser 确保文件夹归属权是用户，而不是 root
LOCAL_BIN_PATH="$REAL_HOME/.local/bin"
log "Setting up user executable path: $LOCAL_BIN_PATH"

if exe runuser -u "$TARGET_USER" -- mkdir -p "$LOCAL_BIN_PATH"; then
    success "Directory ready."
else
    error "Failed to create ~/.local/bin"
fi

# 2. 配置全局 PATH (/etc/profile.d/)
PROFILE_SCRIPT="/etc/profile.d/user_local_bin.sh"
cat << 'EOF' > "$PROFILE_SCRIPT"
# Automatically add ~/.local/bin to PATH if it exists
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
EOF
exe chmod 644 "$PROFILE_SCRIPT"
success "PATH optimization script installed."

# ==============================================================================
# 完成
# ==============================================================================
success "User setup module for '${TARGET_USER}' completed."
echo ""
