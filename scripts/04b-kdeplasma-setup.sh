#!/bin/bash

# ==============================================================================
# 06-kdeplasma-setup.sh - KDE Plasma Setup (FZF Menu + Robust Installation)
# ==============================================================================
# 模块说明：KDE Plasma 桌面环境安装
# ------------------------------------------------------------------------------
# KDE Plasma 是功能完善的现代桌面环境，提供高度可定制的用户体验
#
# 安装内容：
#   1. Plasma 核心组件 (plasma-meta, konsole, dolphin, kate)
#   2. 软件商店和 Flatpak 支持
#   3. 可选依赖 (FZF 交互选择)
#   4. 点文件配置
#   5. SDDM 显示管理器
#
# 特点：
#   - FZF 交互选择包
#   - 包安装失败重试机制
#   - 中国镜像自动检测
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}

check_root

# 确保 FZF 已安装 - FZF 用于交互式包选择
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

# 捕获 Ctrl+C 信号，显示取消消息而不是直接退出
trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

section "Phase 6" "KDE Plasma Environment"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
# 第零步：识别目标用户
# 寻找 UID 1000 的用户（第一个普通用户）

log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
if [ -n "$DETECTED_USER" ]; then TARGET_USER="$DETECTED_USER"; else read -p "Target user: " TARGET_USER; fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. Install KDE Plasma Base
# ------------------------------------------------------------------------------
# 第一步：安装 KDE Plasma 核心组件
# plasma-meta: KDE Plasma 元包，包含所有核心组件
# konsole: KDE 终端模拟器
# dolphin: KDE 文件管理器
# kate: KDE 文本编辑器
# qt6-multimedia-ffmpeg: Qt6 多媒体 FFmpeg 后端
# pipewire-jack: PipeWire 的 JACK 兼容层
# sddm: 显示管理器

section "Step 1/5" "Plasma Core"

log "Installing KDE Plasma Meta & Apps..."
KDE_PKGS="plasma-meta konsole dolphin kate firefox qt6-multimedia-ffmpeg pipewire-jack sddm"
exe pacman -S --noconfirm --needed $KDE_PKGS
success "KDE Plasma installed."

# ------------------------------------------------------------------------------
# 2. Software Store & Network (Smart Mirror Selection)
# ------------------------------------------------------------------------------
# 第二步：软件商店和网络配置 (智能镜像选择)
# Discover 是 KDE 的软件商店，支持 Flatpak
# flatpak-kcm: KDE 系统设置中的 Flatpak 模块

section "Step 2/5" "Software Store & Network"

log "Configuring Discover & Flatpak..."

exe pacman -S --noconfirm --needed flatpak flatpak-kcm
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# --- 网络检测逻辑 ---
# 通过时区或环境变量判断是否为中国用户
CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false

if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
    IS_CN_ENV=true
    info_kv "Region" "China (Timezone)"
elif [ "$CN_MIRROR" == "1" ]; then
    IS_CN_ENV=true
    info_kv "Region" "China (Manual Env)"
elif [ "$DEBUG" == "1" ]; then
    IS_CN_ENV=true
    warn "DEBUG MODE: Forcing China Environment"
fi

# --- 镜像配置 ---
if [ "$IS_CN_ENV" = true ]; then
    log "Enabling China Optimizations..."
    # 调用 00-utils.sh 中定义的镜像选择函数
    select_flathub_mirror
    success "Optimizations Enabled."
else
    log "Using Global Official Sources."
fi

# 创建临时 sudo 免密码文件 - 为 yay 安装 AUR 包提供权限
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 3. Install Dependencies (FZF Selection + Retry Logic)
# ------------------------------------------------------------------------------
# 第三步：安装依赖包 (FZF 选择 + 重试逻辑)
# 从 kde-applist.txt 读取预定义的包列表
# 用户可通过 FZF 交互选择，或 60 秒后自动全选

section "Step 3/5" "KDE Dependencies"

LIST_FILE="$PARENT_DIR/kde-applist.txt"
UNDO_SCRIPT="$PARENT_DIR/undochange.sh"

# --- 严重失败处理器 ---
# 当关键包安装失败时调用，提供恢复选项
critical_failure_handler() {
    local failed_pkg="$1"
    
    # 禁用 trap 防止循环触发
    trap - ERR
    
    echo ""
    echo -e "\033[0;31m################################################################\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                     #\033[0m"
    echo -e "\033[0;31m#   Package: $failed_pkg                                       #\033[0m"
    echo -e "\033[0;31m#   Status: Package not found after install attempt.           #\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   Would you like to restore snapshot (undo changes)?         #\033[0m"
    echo -e "\033[0;31m################################################################\033[0m"
    echo ""

    while true; do
        read -p "Execute System Recovery? [y/n]: " -r choice
        case "$choice" in 
            [yY][eE][sS]|[yY]) 
                # 执行恢复脚本
                if [ -f "$UNDO_SCRIPT" ]; then
                    warn "Executing recovery script: $UNDO_SCRIPT"
                    bash "$UNDO_SCRIPT"
                    exit 1
                else
                    error "Recovery script not found at: $UNDO_SCRIPT"
                    exit 1
                fi
                ;;
            [nN][oO]|[nN])
                warn "User chose NOT to recover. System might be in a broken state."
                error "Installation aborted due to failure in: $failed_pkg"
                exit 1
                ;;
            *)
                echo -e "\033[1;33mInvalid input. Please enter 'y' to recover or 'n' to abort.\033[0m"
                ;;
        esac
    done
}

# --- 安装验证函数 ---
# 检查包是否已成功安装
verify_installation() {
    local pkg="$1"
    if pacman -Q "$pkg" &>/dev/null; then return 0; else return 1; fi
}

if [ -f "$LIST_FILE" ]; then
    
    # 分类数组: 官方仓库包和 AUR 包
    REPO_APPS=()
    AUR_APPS=()

    # ---------------------------------------------------------
    # 3.1 Countdown Logic
    # ---------------------------------------------------------
    # 60 秒倒计时，用户可按键进入自定义选择
    if ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
        warn "App list is empty. Skipping."
    else
        echo ""
        echo -e "   Selected List: ${BOLD}$LIST_FILE${NC}"
        echo -e "   ${H_YELLOW}>>> Default installation will start in 60 seconds.${NC}"
        echo -e "   ${H_CYAN}>>> Press ANY KEY to customize selection...${NC}"

        if read -t 60 -n 1 -s -r; then
            USER_INTERVENTION=true
        else
            USER_INTERVENTION=false
        fi

        # ---------------------------------------------------------
        # 3.2 FZF Selection Logic
        # ---------------------------------------------------------
        # FZF 交互选择界面
        SELECTED_RAW=""

        if [ "$USER_INTERVENTION" = true ]; then
            clear
            echo -e "\n  Loading package list..."

            # 显示格式: 包名 <TAB> # 描述
            SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | \
                sed -E 's/[[:space:]]+#/\t#/' | \
                fzf --multi \
                    --layout=reverse \
                    --border \
                    --margin=1,2 \
                    --prompt="Search Pkg > " \
                    --pointer=">>" \
                    --marker="* " \
                    --delimiter=$'\t' \
                    --with-nth=1 \
                    --bind 'load:select-all' \
                    --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
                    --info=inline \
                    --header="[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL" \
                    --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
                    --preview-window=right:45%:wrap:border-left \
                    --color=dark \
                    --color=fg+:white,bg+:black \
                    --color=hl:blue,hl+:blue:bold \
                    --color=header:yellow:bold \
                    --color=info:magenta \
                    --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
                    --color=spinner:yellow)
            
            clear
            
            if [ -z "$SELECTED_RAW" ]; then
                warn "User cancelled selection. Skipping Step 3."
                # 空数组
            fi
        else
            # 超时，自动全选
            log "Timeout reached (60s). Auto-confirming ALL packages."
            # 模拟 FZF 输出格式
            SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')
        fi

        # ---------------------------------------------------------
        # 3.3 Categorize Selection
        # ---------------------------------------------------------
        # 分类选择的包: 官方仓库 vs AUR
        if [ -n "$SELECTED_RAW" ]; then
            log "Processing selection..."
            while IFS= read -r line; do
                # 提取包名 (TAB 之前的部分)
                raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
                [[ -z "$raw_pkg" ]] && continue
                
                # 修复拼写错误 (imagemagick)
                [ "$raw_pkg" == "imagemagic" ] && raw_pkg="imagemagick"

                # 识别 AUR 包 vs 官方仓库包
                if [[ "$raw_pkg" == AUR:* ]]; then
                    # AUR: 前缀的包
                    clean_name="${raw_pkg#AUR:}"
                    AUR_APPS+=("$clean_name")
                elif [[ "$raw_pkg" == *"-git" ]]; then
                    # 以 -git 结尾的包默认为 AUR 包
                    AUR_APPS+=("$raw_pkg")
                else
                    REPO_APPS+=("$raw_pkg")
                fi
            done <<< "$SELECTED_RAW"
        fi
    fi

    info_kv "Scheduled" "Repo: ${#REPO_APPS[@]}" "AUR: ${#AUR_APPS[@]}"

    # ---------------------------------------------------------
    # 3.4 Install Applications
    # ---------------------------------------------------------
    # 安装应用程序

    # --- A. 安装官方仓库包 (批量模式) ---
    if [ ${#REPO_APPS[@]} -gt 0 ]; then
        log "Phase 1: Batch Installing Repository Packages..."
        
        # 过滤已安装的包
        REPO_QUEUE=()
        for pkg in "${REPO_APPS[@]}"; do
            if ! pacman -Qi "$pkg" &>/dev/null; then
                REPO_QUEUE+=("$pkg")
            fi
        done

        if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
            # 批量安装
            exe runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "${REPO_QUEUE[@]}"
            
            # 验证循环 - 确认每个包都已安装
            log "Verifying batch installation..."
            for pkg in "${REPO_QUEUE[@]}"; do
                if ! verify_installation "$pkg"; then
                    warn "Verification failed for '$pkg'. Retrying individually..."
                    exe runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed "$pkg"
                    
                    if ! verify_installation "$pkg"; then
                        # 安装失败，触发失败处理器
                        critical_failure_handler "$pkg (Repo)"
                    else
                        success "Verified: $pkg"
                    fi
                fi
            done
            success "Batch phase verified."
        else
            log "All selected repo packages are already installed."
        fi
    fi

    # --- B. 安装 AUR 包 (顺序 + 重试) ---
    # AUR 包需要编译，可能失败，所以顺序安装并带重试
    if [ ${#AUR_APPS[@]} -gt 0 ]; then
        log "Phase 2: Installing AUR Packages (Sequential)..."
        log "Hint: Use Ctrl+C to skip a specific package download step."

        for aur_pkg in "${AUR_APPS[@]}"; do
            # 跳过已安装的包
            if pacman -Qi "$aur_pkg" &>/dev/null; then
                log "Skipping '$aur_pkg' (Already installed)."
                continue
            fi
            
            log "Installing AUR: $aur_pkg ..."
            install_success=false
            max_retries=2
            
            # 重试循环
            for (( i=0; i<=max_retries; i++ )); do
                if [ $i -gt 0 ]; then
                    warn "Retry $i/$max_retries for '$aur_pkg' in 3 seconds..."
                    sleep 3
                fi
                
                runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$aur_pkg"
                EXIT_CODE=$?

                # 处理 Ctrl+C 跳过
                if [ $EXIT_CODE -eq 130 ]; then
                    warn "Skipped '$aur_pkg' by user request (Ctrl+C)."
                    break # 跳过此包的重试
                fi

                if verify_installation "$aur_pkg"; then
                    install_success=true
                    success "Installed $aur_pkg"
                    break
                else
                    warn "Attempt $((i+1)) failed for $aur_pkg"
                fi
            done

            # 如果不是用户跳过且安装失败，触发失败处理器
            if [ "$install_success" = false ] && [ $EXIT_CODE -ne 130 ]; then
                critical_failure_handler "$aur_pkg (AUR)"
            fi
        done
    fi

else
    warn "kde-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 4. Dotfiles Deployment
# ------------------------------------------------------------------------------
# 第四步：点文件部署
# 将 kde-dotfiles 目录中的配置复制到用户家目录

section "Step 4/5" "KDE Config Deployment"

DOTFILES_SOURCE="$PARENT_DIR/kde-dotfiles"

if [ -d "$DOTFILES_SOURCE" ]; then
    log "Deploying KDE configurations..."
    
    # 1. 备份现有 .config
    BACKUP_NAME="config_backup_kde_$(date +%s).tar.gz"
    if [ -d "$HOME_DIR/.config" ]; then
        log "Backing up ~/.config to $BACKUP_NAME..."
        exe runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    fi
    
    # 2. 复制 .config 和 .local
    
    # --- 处理 .config ---
    if [ -d "$DOTFILES_SOURCE/.config" ]; then
        log "Merging .config..."
        if [ ! -d "$HOME_DIR/.config" ]; then mkdir -p "$HOME_DIR/.config"; fi
        
        # 复制配置文件
        exe cp -rf "$DOTFILES_SOURCE/.config/"* "$HOME_DIR/.config/" 2>/dev/null || true
        exe cp -rf "$DOTFILES_SOURCE/.config/." "$HOME_DIR/.config/" 2>/dev/null || true
        
        # 修复权限
        log "Fixing permissions for .config..."
        exe chown -R "$TARGET_USER" "$HOME_DIR/.config"
    fi

    # --- 处理 .local ---
    if [ -d "$DOTFILES_SOURCE/.local" ]; then
        log "Merging .local..."
        if [ ! -d "$HOME_DIR/.local" ]; then mkdir -p "$HOME_DIR/.local"; fi
        
        exe cp -rf "$DOTFILES_SOURCE/.local/"* "$HOME_DIR/.local/" 2>/dev/null || true
        exe cp -rf "$DOTFILES_SOURCE/.local/." "$HOME_DIR/.local/" 2>/dev/null || true
        
        log "Fixing permissions for .local..."
        exe chown -R "$TARGET_USER" "$HOME_DIR/.local"
    fi
    
    success "KDE Dotfiles applied and permissions fixed."
else
    warn "Folder 'kde-dotfiles' not found in repo. Skipping config."
fi

# ------------------------------------------------------------------------------
# 4.5 Deploy Resource Files (README)
# ------------------------------------------------------------------------------
# 部署资源文件 - 复制说明文档到桌面

log "Deploying desktop resources..."

SOURCE_README="$PARENT_DIR/resources/KDE-README.txt"
DESKTOP_DIR="$HOME_DIR/Desktop"

if [ ! -d "$DESKTOP_DIR" ]; then
    exe runuser -u "$TARGET_USER" -- mkdir -p "$DESKTOP_DIR"
fi

if [ -f "$SOURCE_README" ]; then
    log "Copying KDE-README.txt..."
    exe cp "$SOURCE_README" "$DESKTOP_DIR/"
    exe chown "$TARGET_USER" "$DESKTOP_DIR/KDE-README.txt"
    success "Readme deployed."
else
    warn "resources/KDE-README.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Enable SDDM (FIXED THEME)
# ------------------------------------------------------------------------------
# 第五步：启用 SDDM 显示管理器
# SDDM (Simple Desktop Display Manager) 是 KDE 推荐的显示管理器

section "Step 5/5" "Enable Display Manager"

# 设置 SDDM 主题为 Breeze
log "Configuring SDDM Theme to Breeze..."
exe mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=breeze
EOF
log "Theme set to 'breeze'."

# 启用 SDDM 服务 - 重启后生效
log "Enabling SDDM..."
exe systemctl enable sddm
success "SDDM enabled. Will start on reboot."

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
# 清理 - 删除临时 sudo 免密码文件

section "Cleanup" "Restoring State"
rm -f "$SUDO_TEMP_FILE"
success "Done."

log "Module 06 completed."