#!/bin/bash
set -e
# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Restored FZF & Robust AUR)
# ==============================================================================
# 模块说明：Niri 桌面环境安装
# ------------------------------------------------------------------------------
# Niri 是一个现代的 Wayland 合成器，滚动平铺窗口布局
#
# 主要特点：
#   - 滚动平铺窗口管理 (非传统的平铺/浮动/堆叠)
#   - 纯 Wayland 实现，无 X11 支持
#   - 用 KDL (Cuddly Data Language) 配置
#
# 安装内容：
#   1. 核心组件 (niri, xdg-portal, fuzzel, kitty)
#   2. 文件管理器 (Nautilus)
#   3. 可选依赖 (FZF 交互选择)
#   4. 点文件配置 (智能递归软链接)
#   5. TTY 自动登录
#
# 注意：
#   - 如果已安装其他显示管理器 (SDDM/GDM 等)，会跳过自动登录
#   - 安装失败时会提供恢复选项
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

# 调试模式和中国镜像开关
DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}
# 恢复脚本路径 - 安装失败时用于回滚到桌面环境安装前
UNDO_SCRIPT="$PARENT_DIR/undochange.sh"

check_root

# --- [HELPER FUNCTIONS] ---


# 2. Critical Failure Handler (The "Big Red Box")
# 2. 严重失败处理器 ("大红框"警告)
# 当安装过程中出现严重错误时显示，提供三个选项：
#   1. 恢复快照 - 执行回滚脚本
#   2. 重试 - 重新运行安装脚本
#   3. 退出 - 立即停止
critical_failure_handler() {
  local failed_reason="$1"
  # 禁用 ERR trap 防止递归触发
  trap - ERR

  # 显示醒目的红色警告框
  echo ""
  echo -e "\033[0;31m################################################################\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                     #\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   Reason: $failed_reason\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   OPTIONS:                                                   #\033[0m"
  echo -e "\033[0;31m#   1. Restore snapshot (Undo changes & Exit)                  #\033[0m"
  echo -e "\033[0;31m#   2. Retry / Re-run script                                   #\033[0m"
  echo -e "\033[0;31m#   3. Abort (Exit immediately)                                #\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m################################################################\033[0m"
  echo ""

  while true; do
    read -p "Select an option [1-3]: " -r choice
    case "$choice" in
    1)
      # Option 1: Restore Snapshot
      # 选项 1: 执行恢复脚本回滚更改
      if [ -f "$UNDO_SCRIPT" ]; then
        warn "Executing recovery script..."
        bash "$UNDO_SCRIPT" desktop
        exit 1
      else
        error "Recovery script missing! You are on your own."
        exit 1
      fi
      ;;
    2)
      # Option 2: Re-run Script
      # 选项 2: 重新运行安装脚本
      # exec 替换当前进程，避免嵌套
      warn "Restarting installation script..."
      echo "-----------------------------------------------------"
      sleep 1
      exec "$0" "$@"
      ;;
    3)
      # Option 3: Exit
      # 选项 3: 直接退出
      warn "User chose to abort."
      warn "Please fix the issue manually before re-running."
      error "Installation aborted."
      exit 1
      ;;
    *) 
      echo "Invalid input. Please enter 1, 2, or 3." 
      ;;
    esac
  done
}

# 3. Robust Package Installation with Retry Loop
# 3. 健壮的包安装函数 (带重试机制)
# 用于安装单个包，如果失败会自动重试最多 3 次
# 参数：
#   $1 - 包名
#   $2 - 上下文 (如 "Repo" 或 "AUR")
ensure_package_installed() {
  local pkg="$1"
  local context="$2" # e.g., "Repo" or "AUR"
  local max_attempts=3
  local attempt=1
  local install_success=false

  # 1. Check if already installed
  # 1. 检查是否已安装
  if pacman -Q "$pkg" &>/dev/null; then
    return 0
  fi

  # 2. Retry Loop
  # 2. 重试循环
  while [ $attempt -le $max_attempts ]; do
    if [ $attempt -gt 1 ]; then
      warn "Retrying '$pkg' ($context)... (Attempt $attempt/$max_attempts)"
      sleep 3 # Cooldown 冷却时间，等待网络或镜像恢复
    else
      log "Installing '$pkg' ($context)..."
    fi

    # Try installation - 使用 yay 统一处理官方仓库和 AUR
    if as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
      install_success=true
      break
    else
      warn "Attempt $attempt/$max_attempts failed for '$pkg'."
    fi

    ((attempt++))
  done

  # 3. Final Verification
  # 3. 最终验证 - 确认包确实已安装
  if [ "$install_success" = true ] && pacman -Q "$pkg" &>/dev/null; then
    success "Installed '$pkg'."
  else
    # 安装失败，触发严重失败处理器
    critical_failure_handler "Failed to install '$pkg' after $max_attempts attempts."
  fi
}

section "Phase 30" "Niri Desktop Environment"

# ==============================================================================
# STEP 0: Safety Checkpoint
# ==============================================================================
# 第零步：安全检查点
# 启用 ERR trap - 当任何命令失败时触发失败处理器

# Enable Trap
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

# ==============================================================================
# STEP 1: Identify User & DM Check
# ==============================================================================
# 第一步：识别用户和检查显示管理器
# Niri 默认使用 TTY 自动登录，但如果已有 DM 则会冲突
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# DM Check - 检查是否已安装显示管理器
# 如果存在，则跳过 TTY 自动登录配置
# 注意：此版本比原始版多添加了 plasma-login-manager
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd" "plasma-login-manager")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
  if pacman -Q "$dm" &>/dev/null; then
    DM_FOUND="$dm"
    break
  fi
done

if [ -n "$DM_FOUND" ]; then
  # 检测到显示管理器，跳过自动登录
  info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
  SKIP_AUTOLOGIN=true
else
  # 询问用户是否启用 TTY 自动登录
  # 20 秒超时，默认启用
  read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
  [[ "${choice:-Y}" =~ ^[Yy]$ ]] && SKIP_AUTOLOGIN=false || SKIP_AUTOLOGIN=true
fi

# ==============================================================================
# STEP 2: Core Components
# ==============================================================================
# 第二步：核心组件
# 安装 Niri 运行所需的基本软件：
#   - niri: Wayland 合成器本体
#   - xdg-desktop-portal-gnome: 桌面集成接口 (文件选择、截图等)
#   - fuzzel: 应用程序启动器
#   - kitty: 终端模拟器
#   - firefox: 浏览器
#   - libnotify: 桃面通知库
#   - mako: Wayland 通知守护进程
#   - polkit-gnome: 权限认证代理
section "Step 1/9" "Core Components"
PKGS="niri xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome"
exe pacman -S --noconfirm --needed $PKGS

# Firefox 策略配置 - 预装扩展
log "Configuring Firefox Policies..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
# 通过策略文件预装 pywalfox 扩展 (用于主题色彩同步)
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR" && exe chmod 644 "$POL_DIR/policies.json"

# ==============================================================================
# STEP 3: File Manager
# ==============================================================================
# 第三步：文件管理器
# 安装 Nautilus：
#   - nautilus: GNOME 文件管理器 (主要)
#   - nautilus-open-any-terminal: 右键打开终端扩展
#   - ffmpegthumbnailer: 视频缩略图生成
#   - poppler-glib: PDF 渲染库
#   - webp-pixbuf-loader: WebP 图片支持
#   - file-roller: 压缩包管理器
#   - gvfs-smb: SMB/CIFS 网络共享支持
#   - gvfs-mtp: MTP 设备支持[USB手机]
#   - gvfs-gphoto2: 数码相机支持
#   - libgsf: 结构化文件支持 [用于生成旧版 MS Office 文档(.doc/.xls)和 EPUB 电子书的缩略图]
#   - gst-plugins-base: GStreamer 基础多媒体插件 [文件管理器调用音频/视频组件的核心依赖]
#   - gst-plugins-good: GStreamer 优质多媒体插件 [提供对 MP4、MKV、FLAC 等常见高质量音视频格式的读取和预览支持]
#   - gst-libav: GStreamer 影音解码器 [底层调用 FFmpeg，提供对 H.264/H.265 等复杂编码的全面解码，确保绝大多数视频都能正常刷出缩略图]

section "Step 2/9" "File Manager"
exe pacman -S --noconfirm --needed \
    nautilus \
    nautilus-open-any-terminal \
    ffmpegthumbnailer \
    poppler-glib \
    webp-pixbuf-loader \
    file-roller \
    gnome-keyring \
    gvfs-smb \
    gvfs-mtp \
    gvfs-gphoto2 \
    libgsf \
    gst-plugins-base gst-plugins-good gst-libav

# 创建 gnome-terminal 软链接指向 kitty
# 某些应用会硬编码调用 gnome-terminal，可以使用这样的方式将其重定向到 kitty
# if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then
#   exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
# fi
# 这里选择使用xdg-terminal-exec脚本来重定向终端调用，避免全局替换可能带来的兼容性问题
exe pacman -S --noconfirm --needed xdg-terminal-exec
XDG_TERM_LIST="$HOME/.config/xdg-terminals.list"
if ! grep -q "^kitty\.desktop$" "$XDG_TERM_LIST" 2>/dev/null; then
    echo "kitty.desktop" > "$XDG_TERM_LIST"
    echo "已将 Kitty 设置为 xdg-terminal-exec 默认终端"
fi

# Nautilus Nvidia/Input Fix
# Nautilus 的 NVIDIA/输入法修复
configure_nautilus_user

section "Step 3/9" "Temp sudo file"

# 创建临时 sudo 免密码文件 (AUR 安装需要)
SUDO_TEMP_FILE="/etc/sudoers.d/99_daguo_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."
# ==============================================================================
# STEP 5: Dependencies (RESTORED FZF)
# ==============================================================================
# 第四步：依赖包安装 (带 FZF 交互选择)
# 从 niri-applist.txt 读取预定义的包列表
# 用户可以通过 FZF 交互式选择要安装的包
section "Step 4/9" "Dependencies"
LIST_FILE="$PARENT_DIR/niri-applist.txt"

# 确保 fzf 已安装
command -v fzf &>/dev/null || pacman -S --noconfirm fzf >/dev/null 2>&1

if [ -f "$LIST_FILE" ]; then
  mapfile -t DEFAULT_LIST < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed 's/#.*//; s/AUR://g' | xargs -n1)

  if [ ${#DEFAULT_LIST[@]} -eq 0 ]; then
    warn "App list is empty. Skipping."
    PACKAGE_ARRAY=()
  else
    echo -e "\n   ${H_YELLOW}>>> Default installation in 60s. Press ANY KEY to customize...${NC}"

    if read -t 60 -n 1 -s -r; then
      # --- [RESTORED] Original FZF Selection Logic ---
      # --- [恢复的] 原始 FZF 选择逻辑 ---
      clear
      log "Loading package list..."

      # FZF 多选界面
      # --multi: 允许多选
      # --bind 'load:select-all': 加载时全选
      # --preview: 显示包描述
      SELECTED_LINES=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" |
        sed -E 's/[[:space:]]+#/\t#/' |
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
          --preview-window=right:50%:wrap:border-left \
          --color=dark \
          --color=fg+:white,bg+:black \
          --color=hl:blue,hl+:blue:bold \
          --color=header:yellow:bold \
          --color=info:magenta \
          --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
          --color=spinner:yellow)

      clear

      if [ -z "$SELECTED_LINES" ]; then
        warn "User cancelled selection. Installing NOTHING."
        PACKAGE_ARRAY=()
      else
        # 解析用户选择的包
        PACKAGE_ARRAY=()
        while IFS= read -r line; do
          raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
          clean_pkg="${raw_pkg#AUR:}"
          [ -n "$clean_pkg" ] && PACKAGE_ARRAY+=("$clean_pkg")
        done <<<"$SELECTED_LINES"
      fi
      # -----------------------------------------------
    else
      log "Auto-confirming ALL packages."
      PACKAGE_ARRAY=("${DEFAULT_LIST[@]}")
    fi
  fi

  # --- Installation Loop ---
  # --- 安装循环 ---
  # 分两阶段：
  #   1. 批量安装官方仓库包 (快速)
  #   2. 顺序安装 AUR 包 (需要编译，可能失败)
  if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
    BATCH_LIST=()
    AUR_LIST=()
    info_kv "Target" "${#PACKAGE_ARRAY[@]} packages scheduled."

    # 分类: AUR 包和官方仓库包
    for pkg in "${PACKAGE_ARRAY[@]}"; do
      # 修复拼写错误
      [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
      # AUR: 前缀的包加入 AUR 列表
      [[ "$pkg" == "AUR:"* ]] && AUR_LIST+=("${pkg#AUR:}") || BATCH_LIST+=("$pkg")
    done

    # 1. Batch Install Repo Packages
    # 1. 批量安装官方仓库包
    if [ ${#BATCH_LIST[@]} -gt 0 ]; then
      log "Phase 1: Batch Installing Repo Packages..."
      as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "${BATCH_LIST[@]}" || true

      # Verify Each - 逐一验证每个包是否安装成功
      for pkg in "${BATCH_LIST[@]}"; do
        ensure_package_installed "$pkg" "Repo"
      done
    fi

    # 2. Sequential AUR Install
    # 2. 顺序安装 AUR 包
    if [ ${#AUR_LIST[@]} -gt 0 ]; then
      log "Phase 2: Installing AUR Packages (Sequential)..."
      for pkg in "${AUR_LIST[@]}"; do
        ensure_package_installed "$pkg" "AUR"
      done
    fi

    # Waybar fallback
    # Waybar 回退安装，如果 waybar 不在列表中但配置文件需要，安装官方版本
    if ! command -v waybar &>/dev/null; then
      warn "Waybar missing. Installing stock..."
      exe pacman -S --noconfirm --needed waybar
    fi
  else
    warn "No packages selected."
  fi
else
  warn "niri-applist.txt not found."
fi

# ==============================================================================
# STEP 6: Dotfiles
# ==============================================================================
# 第五步：部署点文件
# 从本地 dotfiles 目录直接复制配置文件到用户家目录
# 先复制 common (公共配置)，再复制 niri (桌面特有配置)
section "Step 5/9" "Deploying Dotfiles"

# 配置文件目录
COMMON_DOTFILES_DIR="$PARENT_DIR/dotfiles/common"
NIRI_DOTFILES_DIR="$PARENT_DIR/dotfiles/niri"

# 1. 确保目标目录存在
log "Ensuring target directories exist..."
as_user mkdir -p "$HOME_DIR/.config"
as_user mkdir -p "$HOME_DIR/.local/share"
as_user mkdir -p "$HOME_DIR/.local/bin"

# 2. 备份现有配置
log "Backing up existing configs..."
if [ -d "$HOME_DIR/.config" ]; then
  as_user tar -czf "$HOME_DIR/config_backup_$(date +%s).tar.gz" -C "$HOME_DIR" .config 2>/dev/null || true
fi

# 3. 复制公共配置 (common)
log "Copying common dotfiles..."
if [ -d "$COMMON_DOTFILES_DIR" ]; then
  cp -rf "$COMMON_DOTFILES_DIR/." "$HOME_DIR/"
  success "Common dotfiles copied."
else
  warn "Common dotfiles directory not found: $COMMON_DOTFILES_DIR"
fi

# 4. 复制 Niri 特有配置 (后复制，覆盖公共配置中的同名文件)
log "Copying Niri dotfiles..."
if [ -d "$NIRI_DOTFILES_DIR" ]; then
  cp -rf "$NIRI_DOTFILES_DIR/." "$HOME_DIR/"
  success "Niri dotfiles copied."
else
  warn "Niri dotfiles directory not found: $NIRI_DOTFILES_DIR"
  critical_failure_handler "Niri dotfiles not found."
fi

# 5. 修复权限
log "Fixing permissions..."
chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.config"
chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.local"

# 确保 .local/bin 下的脚本有执行权限
if [ -d "$HOME_DIR/.local/bin" ]; then
  chmod -R +x "$HOME_DIR/.local/bin"
fi

# 6. 后处理
OUTPUT_KDL="$HOME_DIR/.config/niri/output.kdl"
if [ "$TARGET_USER" != "daguo" ]; then
  # 创建空的显示器配置文件 (需要用户自己配置)
  as_user touch "$OUTPUT_KDL"

  # 修复 GTK Bookmarks (替换用户名)
  BOOKMARKS_FILE="$HOME_DIR/.config/gtk-3.0/bookmarks"
  if [ -f "$BOOKMARKS_FILE" ]; then
    sed -i "s/daguo/$TARGET_USER/g" "$BOOKMARKS_FILE"
    log "Updated GTK bookmarks."
  fi
else
  # daguo 用户使用示例配置
  OUTPUT_EXAMPLE_KDL="$HOME_DIR/.config/niri/output-example.kdl"
  if [ -f "$OUTPUT_EXAMPLE_KDL" ]; then
    as_user cp "$OUTPUT_EXAMPLE_KDL" "$OUTPUT_KDL"
  fi
fi

# GTK Theme Symlinks (Fix internal links)
# GTK 主题软链接修复
GTK4="$HOME_DIR/.config/gtk-4.0"
THEME="$HOME_DIR/.local/share/themes/adw-gtk3-dark/gtk-4.0"
if [ -d "$GTK4" ] && [ -d "$THEME" ]; then
    as_user rm -f "$GTK4/gtk.css" "$GTK4/gtk-dark.css"
    as_user ln -sf "$THEME/gtk-dark.css" "$GTK4/gtk-dark.css"
    as_user ln -sf "$THEME/gtk.css" "$GTK4/gtk.css"
fi

# Flatpak overrides
# 允许 Flatpak 应用访问主题和字体
if command -v flatpak &>/dev/null; then
  as_user flatpak override --user --filesystem=xdg-data/themes
  as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
  as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
  as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
  as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
  as_user flatpak override --user --filesystem=xdg-config/fontconfig
fi

success "Dotfiles deployed."

# ==============================================================================
# STEP 7: Wallpapers
# ==============================================================================
# 第六步：壁纸配置
# 直接复制壁纸到用户 Pictures 目录
section "Step 6/9" "Wallpapers"

WALLPAPERS_SRC="$PARENT_DIR/wallpapers"
WALLPAPERS_DEST="$HOME_DIR/Pictures/Wallpapers"

if [ -d "$WALLPAPERS_SRC" ]; then
  log "Copying wallpapers..."
  as_user mkdir -p "$HOME_DIR/Pictures"
  # 删除旧的壁纸目录（可能是软链接）
  rm -rf "$WALLPAPERS_DEST"
  # 复制壁纸
  cp -rf "$WALLPAPERS_SRC" "$WALLPAPERS_DEST"
  chown -R "$TARGET_USER:$TARGET_USER" "$WALLPAPERS_DEST"
  success "Wallpapers copied."
else
  warn "Wallpapers directory not found: $WALLPAPERS_SRC"
fi

# 创建 Templates 模板文件 - 用于右键新建文件
as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new"
echo "#!/bin/bash" | as_user tee "$HOME_DIR/Templates/new.sh" >/dev/null
as_user chmod +x "$HOME_DIR/Templates/new.sh"

# === remove gtk bottom =======
# 移除 GTK 窗口底部标题栏按钮，保留关闭按鈕
as_user gsettings set org.gnome.desktop.wm.preferences button-layout ":close"
# ==============================================================================
# STEP 8: Hardware Tools
# ==============================================================================
# 第七步：硬件工具配置
# 配置一些硬件相关的服务和权限
section "Step 7/9" "Hardware"
# ddcutil - 显示器亮度控制工具，需要将用户加入 i2c 组
if pacman -Q ddcutil &>/dev/null; then
  gpasswd -a "$TARGET_USER" i2c
  # 加载 i2c-dev 内核模块
  lsmod | grep -q i2c_dev || echo "i2c-dev" >/etc/modules-load.d/i2c-dev.conf
fi
# swayosd - 屏幕显示指示器 (OSD)
if pacman -Q swayosd &>/dev/null; then
  systemctl enable --now swayosd-libinput-backend.service >/dev/null 2>&1
fi
success "Tools configured."

# ==============================================================================
# STEP 9: Cleanup & Auto-Login
# ==============================================================================
# 第八步：清理和配置自动登录
section "Final" "Cleanup & Boot"
# 删除临时 sudo 免密码文件
rm -f "$SUDO_TEMP_FILE"

# 用户 systemd 服务目录
SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/niri-autostart.service"
LINK="$SVC_DIR/default.target.wants/niri-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
  # 跳过自动登录配置 (如果存在其他 DM)
  log "Auto-login skipped."
  as_user rm -f "$LINK" "$SVC_FILE"
else
  log "Configuring TTY Auto-login..."
  # 配置 getty 自动登录 tty1
  mkdir -p "/etc/systemd/system/getty@tty1.service.d"
  echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"

  # 创建用户 systemd 服务 - 登录后自动启动 Niri
  as_user mkdir -p "$(dirname "$LINK")"
  cat <<EOT >"$SVC_FILE"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target
[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure
[Install]
WantedBy=default.target
EOT
  as_user ln -sf "../niri-autostart.service" "$LINK"
  chown -R "$TARGET_USER" "$SVC_DIR"
  success "Enabled."
fi

# 禁用 ERR trap
trap - ERR
log "Module 30 completed."
