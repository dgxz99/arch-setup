#!/bin/bash

# ==============================================================================
# 99-apps.sh - Common Applications (FZF Menu + Split Repo/AUR + Retry Logic)
# ==============================================================================
# 模块说明：通用应用程序安装
# ------------------------------------------------------------------------------
# 此模块是安装流程的最后一步，安装常用应用
#
# 主要功能：
#   1. FZF 交互式选择 - 用户可自定义要安装的应用
#   2. 智能分类 - 自动区分 Repo/AUR/Flatpak 应用
#   3. 并行安装 - 官方仓库批量安装
#   4. 重试逻辑 - AUR 包失败后自动重试
#   5. 后置配置 - Virt-Manager/Wine/Steam/LazyVim 等
#
# 支持的应用源：
#   - Repo: 官方仓库 (pacman)
#   - AUR:  用户仓库 (yay)
#   - Flatpak: Flathub 平台
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

# --- [配置] ---
# LazyVim 硬性依赖列表 - 从 niri-setup 移植
# neovim: 编辑器本体, ripgrep/fd: 快速搜索
# ttf-jetbrains-mono-nerd: 字体图标, git: 插件管理
LAZYVIM_DEPS=("neovim" "ripgrep" "fd" "ttf-jetbrains-mono-nerd" "git")

check_root

# 确保 FZF 已安装 - 用于交互式选择
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

# 捕捉 Ctrl+C 中断信号，显示取消提示
trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

# ------------------------------------------------------------------------------
# 0. Identify Target User & Helper
# ------------------------------------------------------------------------------
# 第零步：识别目标用户
# 用于后续以用户身份执行命令 (AUR 安装、配置文件等)

section "Phase 5" "Common Applications"

log "Identifying target user..."
# 优先检测 UID 1000 的用户 (通常是主用户)
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
else
    # 如果未检测到，请求手动输入
    read -p "   Please enter the target username: " TARGET_USER
fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# as_user - 以目标用户身份执行命令
# 用于 AUR 安装、gsettings 配置等不能以 root 运行的操作
as_user() {
  runuser -u "$TARGET_USER" -- "$@"
}

# ------------------------------------------------------------------------------
# 1. List Selection & User Prompt
# ------------------------------------------------------------------------------
# 第一步：应用列表选择
# 根据桌面环境选择对应的应用列表文件

# 根据桌面环境选择列表文件
# KDE 使用 kde-common-applist.txt，其他使用 common-applist.txt
if [ "$DESKTOP_ENV" == "kde" ]; then
    LIST_FILENAME="kde-common-applist.txt"
else
    LIST_FILENAME="common-applist.txt"
fi
LIST_FILE="$PARENT_DIR/$LIST_FILENAME"

# 初始化数组 - 用于分类存储应用
REPO_APPS=()      # 官方仓库应用
AUR_APPS=()       # AUR 应用
FLATPAK_APPS=()   # Flatpak 应用
FAILED_PACKAGES=() # 安装失败的应用
INSTALL_LAZYVIM=false  # LazyVim 安装标志

# 检查列表文件是否存在
if [ ! -f "$LIST_FILE" ]; then
    warn "File $LIST_FILENAME not found. Skipping."
    trap - INT
    exit 0
fi

# 检查列表是否为空 (排除注释和空行)
if ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
    warn "App list is empty. Skipping."
    trap - INT
    exit 0
fi

# 显示用户提示菜单
echo ""
echo -e "   Selected List: ${BOLD}$LIST_FILENAME${NC}"
echo -e "   ${H_YELLOW}>>> Do you want to install common applications?${NC}"
echo -e "   ${H_CYAN}    [ENTER] = Select packages${NC}"
echo -e "   ${H_CYAN}    [N]     = Skip installation${NC}"
echo -e "   ${H_YELLOW}    [Timeout 60s] = Auto-install ALL default packages (No FZF)${NC}"
echo ""

# 读取用户输入，60 秒超时
read -t 60 -p "   Please select [Y/n]: " choice
READ_STATUS=$?

SELECTED_RAW=""

# 情况 1: 超时 - 自动安装所有应用
if [ $READ_STATUS -ne 0 ]; then
    echo "" 
    warn "Timeout reached (60s). Auto-installing ALL applications from list..."
    # 排除注释行和空行，处理行内注释
    SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')

# 情况 2: 用户输入
else
    choice=${choice:-Y}
    if [[ "$choice" =~ ^[nN]$ ]]; then
        warn "User skipped application installation."
        trap - INT
        exit 0
    else
        clear
        echo -e "\n  Loading application list..."
        
        # 使用 FZF 进行交互式选择
        # --multi: 支持多选
        # --bind 'load:select-all': 默认全选
        # --preview: 显示应用说明
        SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | \
            sed -E 's/[[:space:]]+#/\t#/' | \
            fzf --multi \
                --layout=reverse \
                --border \
                --margin=1,2 \
                --prompt="Search App > " \
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
        
        # 用户取消选择
        if [ -z "$SELECTED_RAW" ]; then
            log "Skipping application installation (User cancelled selection)."
            trap - INT
            exit 0
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 2. Categorize Selection & Strip Prefixes (Includes LazyVim Check)
# ------------------------------------------------------------------------------
# 第二步：应用分类和前缀处理
# 根据应用名称前缀将其分到不同安装队列
#   - flatpak:xxx  -> Flatpak 应用
#   - AUR:xxx      -> AUR 应用
#   - 其他         -> 官方仓库应用

log "Processing selection..."

while IFS= read -r line; do
    # 提取应用名称 (切掉行内注释)
    raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
    [[ -z "$raw_pkg" ]] && continue

    # LazyVim 特殊处理 - 识别并添加依赖
    if [[ "${raw_pkg,,}" == "lazyvim" ]]; then
        INSTALL_LAZYVIM=true
        # 将 LazyVim 依赖添加到仓库队列
        REPO_APPS+=("${LAZYVIM_DEPS[@]}")
        info_kv "Config" "LazyVim detected" "Setup deferred to Post-Install"
        continue
    fi

    # 根据前缀分类
    if [[ "$raw_pkg" == flatpak:* ]]; then
        clean_name="${raw_pkg#flatpak:}"  # 移除 flatpak: 前缀
        FLATPAK_APPS+=("$clean_name")
    elif [[ "$raw_pkg" == AUR:* ]]; then
        clean_name="${raw_pkg#AUR:}"      # 移除 AUR: 前缀
        AUR_APPS+=("$clean_name")
    else
        REPO_APPS+=("$raw_pkg")
    fi
done <<< "$SELECTED_RAW"

info_kv "Scheduled" "Repo: ${#REPO_APPS[@]}" "AUR: ${#AUR_APPS[@]}" "Flatpak: ${#FLATPAK_APPS[@]}"

# ------------------------------------------------------------------------------
# [设置] 全局 SUDO 配置
# ------------------------------------------------------------------------------
# 为目标用户配置临时的 NOPASSWD 权限
# 这样 yay 安装 AUR 包时不需要重复输入密码
# 安装完成后会自动清理该配置

if [ ${#REPO_APPS[@]} -gt 0 ] || [ ${#AUR_APPS[@]} -gt 0 ]; then
    log "Configuring temporary NOPASSWD for installation..."
    SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_apps"
    echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
    chmod 440 "$SUDO_TEMP_FILE"
fi

# ------------------------------------------------------------------------------
# 3. Install Applications
# ------------------------------------------------------------------------------
# 第三步：安装应用
# 分三个阶段: A=官方仓库, B=AUR, C=Flatpak

# --- A. 官方仓库应用 (批量模式) ---
# 官方仓库应用使用 yay 批量安装，效率更高
if [ ${#REPO_APPS[@]} -gt 0 ]; then
    section "Step 1/3" "Official Repository Packages (Batch)"
    
    # 过滤已安装的应用
    REPO_QUEUE=()
    for pkg in "${REPO_APPS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            log "Skipping '$pkg' (Already installed)."
        else
            REPO_QUEUE+=("$pkg")
        fi
    done

    if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
        BATCH_LIST="${REPO_QUEUE[*]}"
        info_kv "Installing" "${#REPO_QUEUE[@]} packages via Pacman/Yay"
        
        # 使用 yay 批量安装
        # --answerdiff=None --answerclean=None: 自动跳过 diff 和 clean 提示
        if ! exe as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
            error "Batch installation failed. Some repo packages might be missing."
            # 将所有包记录为失败
            for pkg in "${REPO_QUEUE[@]}"; do
                FAILED_PACKAGES+=("repo:$pkg")
            done
        else
            success "Repo batch installation completed."
        fi
    else
        log "All Repo packages are already installed."
    fi
fi

# --- B. AUR 应用 (单独模式 + 重试) ---
# AUR 应用逐个安装，失败后自动重试
if [ ${#AUR_APPS[@]} -gt 0 ]; then
    section "Step 2/3" "AUR Packages "
    
    for app in "${AUR_APPS[@]}"; do
        if pacman -Qi "$app" &>/dev/null; then
            log "Skipping '$app' (Already installed)."
            continue
        fi

        log "Installing AUR: $app ..."
        install_success=false
        max_retries=1  # 最多重试一次
        
        # 重试循环
        for (( i=0; i<=max_retries; i++ )); do
            if [ $i -gt 0 ]; then
                warn "Retry $i/$max_retries for '$app' ..."
            fi
            
            if as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$app"; then
                install_success=true
                success "Installed $app"
                break
            else
                warn "Attempt $((i+1)) failed for $app"
            fi
        done

        if [ "$install_success" = false ]; then
            error "Failed to install $app after $((max_retries+1)) attempts."
            FAILED_PACKAGES+=("aur:$app")
        fi
    done
fi

# --- C. Flatpak 应用 (单独模式) ---
if [ ${#FLATPAK_APPS[@]} -gt 0 ]; then
    section "Step 3/3" "Flatpak Packages (Individual)"
    
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak info "$app" &>/dev/null; then
            log "Skipping '$app' (Already installed)."
            continue
        fi

        log "Installing Flatpak: $app ..."
        if ! exe flatpak install -y flathub "$app"; then
            error "Failed to install: $app"
            FAILED_PACKAGES+=("flatpak:$app")
        else
            success "Installed $app"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 4. Environment & Additional Configs (Virt/Wine/Steam/LazyVim)
# ------------------------------------------------------------------------------
# 第四步：环境配置和应用调优
# 根据安装的应用进行额外配置

section "Post-Install" "System & App Tweaks"

# --- [新] 虚拟化配置 (Virt-Manager) ---
# 检测是否安装了 virt-manager 且不在虚拟机内
if pacman -Qi virt-manager &>/dev/null && ! systemd-detect-virt -q; then
  info_kv "Config" "Virt-Manager detected"
  
  # 1. 安装完整依赖
  # iptables-nft 和 dnsmasq 是默认 NAT 网络必须的
  log "Installing QEMU/KVM dependencies..."
  pacman -S --noconfirm --needed qemu-full virt-manager swtpm dnsmasq 

  # 2. 添加用户组 (需要重新登录生效)
  # libvirt: 访问 libvirtd 服务
  # kvm/input: 访问 KVM 硬件加速和输入设备
  log "Adding $TARGET_USER to libvirt group..."
  usermod -a -G libvirt "$TARGET_USER"
  usermod -a -G kvm,input "$TARGET_USER"

  # 3. 开启服务
  log "Enabling libvirtd service..."
  systemctl enable --now libvirtd

  # 4. [修复] 强制设置 virt-manager 默认连接为 QEMU/KVM
  # 解决第一次打开显示 LXC 或无法连接的问题
  log "Setting default URI to qemu:///system..."
  
  # 编译 glib schemas (防止 gsettings 报错)
  glib-compile-schemas /usr/share/glib-2.0/schemas/

  # 强制写入 Dconf 配置
  # uris: 连接列表
  # autoconnect: 自动连接的列表
  as_user gsettings set org.virt-manager.virt-manager.connections uris "['qemu:///system']"
  as_user gsettings set org.virt-manager.virt-manager.connections autoconnect "['qemu:///system']"

  # 5. 配置网络 (Default NAT)
  # 启动默认的 NAT 网络，使虚拟机能够访问外网
  log "Starting default network..."
  sleep 3
  virsh net-start default >/dev/null 2>&1 || warn "Default network might be already active."
  virsh net-autostart default >/dev/null 2>&1 || true
  
  success "Virtualization (KVM) configured."
fi

# --- [新] Wine 配置和字体 ---
# 检测 Wine 并配置 Windows 字体
if command -v wine &>/dev/null; then
  info_kv "Config" "Wine detected"
  
  # 1. 安装 Gecko 和 Mono
  # Wine 的 IE 和 .NET 支持组件
  log "Ensuring Wine Gecko/Mono are installed..."
  pacman -S --noconfirm --needed wine wine-gecko wine-mono 

  # 2. 初始化 Wine (wineboot -u 在后台运行，不弹窗)
  # 创建默认的 Wine prefix 和注册表
  WINE_PREFIX="$HOME_DIR/.wine"
  if [ ! -d "$WINE_PREFIX" ]; then
    log "Initializing wine prefix (This may take a minute)..."
    # WINEDLLOVERRIDES 禁用弹窗
    as_user env WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
    # 等待完成
    as_user wineserver -w
  else
    log "Wine prefix already exists."
  fi

  # 3. 复制字体
  # 复制宋体等 Windows 字体到 Wine 的字体目录
  FONT_SRC="$PARENT_DIR/resources/windows-sim-fonts"
  FONT_DEST="$WINE_PREFIX/drive_c/windows/Fonts"

  if [ -d "$FONT_SRC" ]; then
    log "Copying Windows fonts from resources..."
    
    # 1. 确保目标目录存在 (以用户身份创建)
    if [ ! -d "$FONT_DEST" ]; then
        as_user mkdir -p "$FONT_DEST"
    fi

    # 2. 执行复制 (以目标用户身份复制，而不是 Root 复制后再 Chown)
    if sudo -u "$TARGET_USER" cp -rf "$FONT_SRC"/. "$FONT_DEST/"; then
        success "Fonts copied successfully."
    else
        error "Failed to copy fonts."
    fi

    # 3. 强制刷新 Wine 字体缓存
    # 杀死 wineserver 会强制 Wine 下次启动时重新扫描字体
    log "Refreshing Wine font cache..."
    if command -v wineserver &> /dev/null; then
        as_user env WINEPREFIX="$WINE_PREFIX" wineserver -k
    fi
    
    success "Wine fonts installed and cache refresh triggered."
  else
    warn "Resources font directory not found at: $FONT_SRC"
  fi
fi

# --- Lutris 游戏依赖 ---
# 为 Lutris 安装 32 位游戏库
if command -v lutris &> /dev/null; then 
    log "Lutris detected. Installing 32-bit gaming dependencies..."
    pacman -S --noconfirm --needed alsa-plugins giflib glfw gst-plugins-base-libs lib32-alsa-plugins lib32-giflib lib32-gst-plugins-base-libs lib32-gtk3 lib32-libjpeg-turbo lib32-libva lib32-mpg123  lib32-openal libjpeg-turbo libva libxslt mpg123 openal ttf-liberation
fi

# --- Steam 区域修复 ---
# 修复 Steam 的中文显示问题
STEAM_desktop_modified=false
NATIVE_DESKTOP="/usr/share/applications/steam.desktop"
if [ -f "$NATIVE_DESKTOP" ]; then
    log "Checking Native Steam..."
    # 检查是否已经补丁
    if ! grep -q "env LANG=zh_CN.UTF-8" "$NATIVE_DESKTOP"; then
        # 修改 .desktop 文件，强制使用中文区域
        exe sed -i 's|^Exec=/usr/bin/steam|Exec=env LANG=zh_CN.UTF-8 /usr/bin/steam|' "$NATIVE_DESKTOP"
        exe sed -i 's|^Exec=steam|Exec=env LANG=zh_CN.UTF-8 steam|' "$NATIVE_DESKTOP"
        success "Patched Native Steam .desktop."
        STEAM_desktop_modified=true
    else
        log "Native Steam already patched."
    fi
fi

# Flatpak 版 Steam 的区域修复
if flatpak list | grep -q "com.valvesoftware.Steam"; then
    log "Checking Flatpak Steam..."
    exe flatpak override --env=LANG=zh_CN.UTF-8 com.valvesoftware.Steam
    success "Applied Flatpak Steam override."
    STEAM_desktop_modified=true
fi

# --- [移植] LazyVim 配置 ---
# 如果用户选择了 LazyVim，克隆配置
if [ "$INSTALL_LAZYVIM" = true ]; then
  section "Config" "Applying LazyVim Overrides"
  NVIM_CFG="$HOME_DIR/.config/nvim"

  # 处理已存在的 nvim 配置
  if [ -d "$NVIM_CFG" ]; then
    BACKUP_PATH="$HOME_DIR/.config/nvim.old.apps.$(date +%s)"
    warn "Collision detected. Moving existing nvim config to $BACKUP_PATH"
    mv "$NVIM_CFG" "$BACKUP_PATH"
  fi

  # 克隆 LazyVim starter 配置
  log "Cloning LazyVim starter..."
  if as_user git clone https://github.com/LazyVim/starter "$NVIM_CFG"; then
    rm -rf "$NVIM_CFG/.git"  # 删除 .git 目录，变成独立配置
    success "LazyVim installed (Override)."
  else
    error "Failed to clone LazyVim."
  fi
fi

# --- 隐藏无用的桌面快捷方式 ---
# 在用户目录中创建覆盖文件，设置 NoDisplay=true
hide_desktop_file() {
    local source_file="$1"
    local filename=$(basename "$source_file")
    local user_dir="$HOME_DIR/.local/share/applications"
    local target_file="$user_dir/$filename"
  mkdir -p "$user_dir"
  if [[ -f "$source_file" ]]; then
      cp -fv "$source_file" "$target_file"
      chown "$TARGET_USER" "$target_file"
        # 设置 NoDisplay=true 隐藏桌面文件
        if grep -q "^NoDisplay=" "$target_file"; then
            sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$target_file"
        else
            echo "NoDisplay=true" >> "$target_file"
        fi
  fi
}

# 隐藏各种开发工具和系统工具的桌面文件
# 这些通常不需要在应用菜单中显示
section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
hide_desktop_file "/usr/share/applications/avahi-discover.desktop"
hide_desktop_file "/usr/share/applications/qv4l2.desktop"
hide_desktop_file "/usr/share/applications/qvidcap.desktop"
hide_desktop_file "/usr/share/applications/bssh.desktop"
hide_desktop_file "/usr/share/applications/org.fcitx.Fcitx5.desktop"
hide_desktop_file "/usr/share/applications/org.fcitx.fcitx5-migrator.desktop"
hide_desktop_file "/usr/share/applications/xgps.desktop"
hide_desktop_file "/usr/share/applications/xgpsspeed.desktop"
hide_desktop_file "/usr/share/applications/gvim.desktop"
hide_desktop_file "/usr/share/applications/kbd-layout-viewer5.desktop"
hide_desktop_file "/usr/share/applications/bvnc.desktop"
hide_desktop_file "/usr/share/applications/yazi.desktop"
hide_desktop_file "/usr/share/applications/btop.desktop"
hide_desktop_file "/usr/share/applications/vim.desktop"
hide_desktop_file "/usr/share/applications/nvim.desktop"
hide_desktop_file "/usr/share/applications/nvtop.desktop"
hide_desktop_file "/usr/share/applications/mpv.desktop"
hide_desktop_file "/usr/share/applications/org.gnome.Settings.desktop"

# --- Firefox 配置 ---
# 复制预设的 Firefox 配置
section "Config" "Firefox UI Customization"

if [ -d "$HOME_DIR/.mozilla" ]; then 
    log "Backing up existing .mozilla directory..."
    mv "$HOME_DIR/.mozilla" "$HOME_DIR/.mozilla.bak.$(date +%s)"
fi
    
mkdir -p "$HOME_DIR/.mozilla"
cp -rf "$PARENT_DIR/resources/firefox" "$HOME_DIR/.mozilla/"
chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.mozilla"

# ------------------------------------------------------------------------------
# [清理] 移除临时 SUDO 配置
# ------------------------------------------------------------------------------
# 安装完成后撤销 NOPASSWD 权限，保持系统安全

if [ -f "$SUDO_TEMP_FILE" ]; then
    log "Revoking temporary NOPASSWD..."
    rm -f "$SUDO_TEMP_FILE"
fi

# ------------------------------------------------------------------------------
# 5. Generate Failure Report
# ------------------------------------------------------------------------------
# 第五步：生成失败报告
# 如果有应用安装失败，生成报告文件供用户查看

if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
    
    if [ ! -d "$DOCS_DIR" ]; then as_user mkdir -p "$DOCS_DIR"; fi
    
    # 写入报告内容
    echo -e "\n========================================================" >> "$REPORT_FILE"
    echo -e " Installation Failure Report - $(date)" >> "$REPORT_FILE"
    echo -e "========================================================" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
    
    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
    
    echo ""
    warn "Some applications failed to install."
    warn "A report has been saved to:"
    echo -e "   ${BOLD}$REPORT_FILE${NC}"
else
    success "All scheduled applications processed successfully."
fi

# 重置中断信号处理
trap - INT

log "Module 99-apps completed."