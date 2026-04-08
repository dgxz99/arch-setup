#!/usr/bin/env bash

# ==============================================================================
# GNOME Setup Script
# ==============================================================================
# 模块说明：GNOME 桌面环境安装
# ------------------------------------------------------------------------------
# 安装内容：
#   1. GNOME 核心组件 (gnome-shell, gnome-control-center, gdm)
#   2. 常用应用 (Ghostty, Firefox, Nautilus, Celluloid)
#   3. 快捷键配置 (优化的键盘布局)
#   4. GNOME Shell 扩展 (平铺窗口、模糊效果等)
#   5. 输入法配置 (Fcitx5)
#   6. 点文件部署
# 特点：
#   - 自动配置快捷键
#   - 自动安装并启用 GNOME 扩展
#   - 集成 Fcitx5 输入法
# ==============================================================================

# 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root
section 'Desktop 20' 'GNOME Setup'

# 初始化 Verify 列表，后续安装的包会追加到这个列表中，安装完成后会进行验证。
VERIFY_LIST='/tmp/daguo_install_verify.list'
rm -f "$VERIFY_LIST"

configure_nautilus_user() {
    local sys_file="/usr/share/applications/org.gnome.Nautilus.desktop"
    local user_dir="$HOME_DIR/.local/share/applications"
    local user_file="$user_dir/org.gnome.Nautilus.desktop"

    if [ ! -f "$sys_file" ]; then
        return 0
    fi

    local need_modify=0
    local env_vars="env"
    local gpu_count
    local has_nvidia
    gpu_count=$(lspci | grep -E -i "vga|3d" | wc -l)
    has_nvidia=$(lspci | grep -E -i "nvidia" | wc -l)

    if [ "$gpu_count" -gt 1 ] && [ "$has_nvidia" -gt 0 ]; then
        env_vars="$env_vars GSK_RENDERER=gl"
        need_modify=1
        log "Detected hybrid NVIDIA graphics, injecting GSK_RENDERER=gl for Nautilus."

        local env_conf_dir="$HOME_DIR/.config/environment.d"
        if [ ! -f "$env_conf_dir/gsk.conf" ]; then
            mkdir -p "$env_conf_dir"
            echo "GSK_RENDERER=gl" > "$env_conf_dir/gsk.conf"
            chown -R "$TARGET_USER:$TARGET_USER" "$env_conf_dir"
            log "Added user environment override: $env_conf_dir/gsk.conf"
        fi
    fi

    if [ "$need_modify" -eq 1 ]; then
        mkdir -p "$user_dir"
        cp "$sys_file" "$user_file"
        chown "$TARGET_USER:$TARGET_USER" "$user_file"
        sed -i "s|^Exec=|Exec=$env_vars |" "$user_file"
        log "Generated Nautilus user override: $user_file"
    fi
}

# ==============================================================================
#  Identify User
# ==============================================================================
detect_target_user
TARGET_UID=$(id -u "$TARGET_USER")
info_kv 'Target User' "$TARGET_USER"
info_kv 'Target UID' "$TARGET_UID"

# ==================================
# temp sudo without passwd
# ==================================
SUDO_TEMP_FILE='/etc/sudoers.d/99_daguo_installer_temp'
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$TARGET_USER" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."
cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}

trap cleanup_sudo EXIT INT TERM

#=================================================
# Step 1: Install base pkgs
#=================================================
section 'Step 1/8' 'Install GNOME Core Packages'

# 桌面基础能力：会话、登录、设置中心、默认应用与常用桌面工具。
# - celluloid: 轻量级视频播放器，基于 mpv，界面简洁
# - loupe: 简单的屏幕放大工具，方便查看细节
# - nm-connection-editor: NetworkManager 连接编辑器，方便管理网络连接
# - dnsmasq: 轻量级 DNS 和 DHCP 服务器，在某些网络配置中可能需要
# - pacman-contrib: 包含 pactree 等工具，方便分析包依赖关系
GNOME_DESKTOP_PKGS=(
    gnome-shell
    gdm
    gnome-backgrounds
    gnome-control-center
    gnome-tweaks
    kitty
    firefox
    celluloid
    loupe
    nm-connection-editor
    dnsmasq
    pacman-contrib
)

# 文件与桌面集成：文件管理、缩略图、共享协议、归档与多媒体后端。
# - nautilus-open-any-terminal: 在 Nautilus 中添加 "在终端中打开" 选项，提升文件管理效率
# - file-roller: GNOME 的归档管理器，支持多种压缩格式
# - ffmpegthumbnailer: 为视频文件生成缩略图，提升 Nautilus 的预览体验
# - gvfs-smb: 让 Nautilus 支持 SMB 协议，方便访问 Windows 共享文件夹
# - gvfs-mtp: 让 Nautilus 支持 MTP 协议，方便访问手机等设备
# - gvfs-gphoto2: 让 Nautilus 支持 gphoto2 协议，方便访问相机等设备
# - libgsf: 提供对 Microsoft Office 文件格式的支持，增强 Nautilus 的预览功能
# - gnome-keyring: GNOME 的密码管理器，安全存储用户的密码和密钥
# - gst-plugins-base/good/libav: 提供多媒体支持，确保视频和音频文件能够在 GNOME 环境中正常播放
GNOME_FILE_PKGS=(
    nautilus
    nautilus-python
    nautilus-open-any-terminal
    file-roller
    ffmpegthumbnailer
    gvfs-smb
    gvfs-mtp
    gvfs-gphoto2
    libgsf
    gnome-keyring
    gst-plugins-base
    gst-plugins-good
    gst-libav
)

log "Installing GNOME desktop packages..."
exe pacman -S --noconfirm --needed "${GNOME_DESKTOP_PKGS[@]}"
printf '%s\n' "${GNOME_DESKTOP_PKGS[@]}" >> "$VERIFY_LIST"
success "GNOME desktop packages installed."

log "Installing GNOME file integration packages..."
exe pacman -S --noconfirm --needed "${GNOME_FILE_PKGS[@]}"
printf '%s\n' "${GNOME_FILE_PKGS[@]}" >> "$VERIFY_LIST"
success "GNOME file integration packages installed."

# 启用 GDM (GNOME Display Manager)
log "Enabling GDM..."
exe systemctl enable gdm.service
success "GDM enabled."

#=================================================
# Step 2: Set default terminal
#=================================================
# 第二步：设置默认终端
# 将 Kitty 设为 GNOME 默认终端
section "Step 2/8" "Set default terminal"
log "Setting GNOME default terminal to Kitty..."

# 使用 sudo -u 切换用户，并启动临时 dbus-launch 以确保 gsettings 生效
sudo -u "$TARGET_USER" bash <<EOF
    # D-Bus Fix
    if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval \$(dbus-launch --sh-syntax)
        trap "kill \$DBUS_SESSION_BUS_PID" EXIT
    fi
    
    gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'
EOF

#=================================================
# Step 3: Set locale
#=================================================
# 第三步：设置区域
# 配置 AccountsService 使登录界面显示中文
section "Step 3/8" "Set locale"
log "Configuring GNOME locale for user $TARGET_USER..."
ACCOUNT_FILE="/var/lib/AccountsService/users/$TARGET_USER"
ACCOUNT_DIR=$(dirname "$ACCOUNT_FILE")
# 确保目录存在
mkdir -p "$ACCOUNT_DIR"
# 设置语言为中文
cat > "$ACCOUNT_FILE" <<EOF
[User]
Languages=zh_CN.UTF-8
EOF

#=================================================
# Step 4: Configure Shortcuts
#=================================================
section "Step 4/8" "Configure Shortcuts"
log "Configuring shortcuts..."

# 使用 sudo -u 切换用户并注入 DBUS 变量以修改 dconf
sudo -u "$TARGET_USER" bash <<EOF
    # 在非图形化环境修改 dconf 必须手动启动 session bus
    if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ] || [ ! -e "\${DBUS_SESSION_BUS_ADDRESS#unix:path=}" ]; then
        echo "   -> Starting temporary D-Bus session for shortcuts..."
        eval \$(dbus-launch --sh-syntax)
        trap "kill \$DBUS_SESSION_BUS_PID" EXIT
    fi

    echo "   ➜ Applying shortcuts for user: $(whoami)..."

    # ---------------------------------------------------------
    # 1. org.gnome.desktop.wm.keybindings (窗口管理)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.desktop.wm.keybindings"
    
    # 基础窗口控制
    gsettings set \$SCHEMA close "['<Super>q']"
    gsettings set \$SCHEMA show-desktop "['<Super>d']"
    gsettings set \$SCHEMA toggle-fullscreen "['<Alt><Super>f']"
    gsettings set \$SCHEMA toggle-maximized "['<Super>f']"
    
    # 清理未使用的窗口控制键 
    gsettings set \$SCHEMA maximize "[]"
    gsettings set \$SCHEMA minimize "[]"
    gsettings set \$SCHEMA unmaximize "[]"

    # 切换与移动工作区 
    gsettings set \$SCHEMA switch-to-workspace-left "['<Shift><Super>q']"
    gsettings set \$SCHEMA switch-to-workspace-right "['<Shift><Super>e']"
    gsettings set \$SCHEMA move-to-workspace-left "['<Control><Super>q']"
    gsettings set \$SCHEMA move-to-workspace-right "['<Control><Super>e']"
    
    # 切换应用/窗口 
    gsettings set \$SCHEMA switch-applications "['<Alt>Tab']"
    gsettings set \$SCHEMA switch-applications-backward "['<Shift><Alt>Tab']"
    gsettings set \$SCHEMA switch-group "['<Alt>grave']"
    gsettings set \$SCHEMA switch-group-backward "['<Shift><Alt>grave']"
    
    # 清理输入法切换快捷键
    gsettings set \$SCHEMA switch-input-source "[]"
    gsettings set \$SCHEMA switch-input-source-backward "[]"

    # ---------------------------------------------------------
    # 2. org.gnome.shell.keybindings (Shell 全局)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.shell.keybindings"
    
    # 截图相关
    gsettings set \$SCHEMA screenshot "['<Shift><Control><Super>a']"
    gsettings set \$SCHEMA screenshot-window "['<Control><Super>a']"
    gsettings set \$SCHEMA show-screenshot-ui "['<Alt><Super>a']"
    
    # 界面视图
    gsettings set \$SCHEMA toggle-application-view "['<Super>g']"
    gsettings set \$SCHEMA toggle-quick-settings "['<Control><Super>s']"
    gsettings set \$SCHEMA toggle-message-tray "[]"

    # ---------------------------------------------------------
    # 3. org.gnome.settings-daemon.plugins.media-keys (媒体与自定义)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.settings-daemon.plugins.media-keys"

    # 辅助功能
    gsettings set \$SCHEMA magnifier "['<Alt><Super>0']"
    gsettings set \$SCHEMA screenreader "[]"

    # --- 自定义快捷键逻辑 ---
    # 定义添加函数
    add_custom() {
        local index="\$1"
        local name="\$2"
        local cmd="\$3"
        local bind="\$4"
        
        local path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom\$index/"
        local key_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:\$path"
        
        gsettings set "\$key_schema" name "\$name"
        gsettings set "\$key_schema" command "\$cmd"
        gsettings set "\$key_schema" binding "\$bind"
        
        echo "\$path"
    }

    # 重置列表以避免冲突
    gsettings set \$SCHEMA custom-keybindings "[]"

    # 构建自定义快捷键列表
    
    P0=\$(add_custom 0 "openbrowser" "firefox" "<Super>b")
    P1=\$(add_custom 1 "openterminal" "kitty" "<Super>t")
    P2=\$(add_custom 2 "missioncenter" "missioncenter" "<Super>grave")
    P3=\$(add_custom 3 "opennautilus" "nautilus" "<Super>e")
    P4=\$(add_custom 4 "editscreenshot" "gradia --screenshot" "<Shift><Super>s")
    P5=\$(add_custom 5 "gnome-control-center" "gnome-control-center" "<Control><Alt>s")

    # 应用列表 (已移除重复的 P6)
    CUSTOM_LIST="['\$P0', '\$P1', '\$P2', '\$P3', '\$P4', '\$P5']"
    gsettings set \$SCHEMA custom-keybindings "\$CUSTOM_LIST"
    
    echo "   ➜ Shortcuts synced with config files successfully."
EOF

#=================================================
# Step 5: Extensions
#=================================================
# 第五步：安装 GNOME Shell 扩展
# 使用 gnome-extensions-cli 工具从 extensions.gnome.org 安装扩展
section "Step 5/8" "Install Extensions"
log "Installing Extensions CLI..."
EXT_PKGS="gnome-extensions-cli gnome-shell-extension-manager"
echo "$EXT_PKGS" >> "$VERIFY_LIST"
sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None $EXT_PKGS
# 扩展列表 - 这些扩展将被安装并启用
EXTENSION_LIST=(
    "arch-update@RaphaelRochet"                      # Arch 更新指示器
    "aztaskbar@aztaskbar.gitlab.com"                 # 任务栏
    "blur-my-shell@aunetx"                           # Shell 模糊效果
    "caffeine@patapon.info"                          # 阻止休眠
    "clipboard-indicator@tudmotu.com"                # 剪贴板管理
    "color-picker@tuberry"                           # 取色器
    "desktop-cube@schneegans.github.com"             # 桌面立方体效果
    "fuzzy-application-search@mkhl.codeberg.page"    # 模糊搜索
    "lockkeys@vaina.lt"                              # 键盘锁指示器
    "tilingshell@ferrarodomenico.com"                # 平铺窗口管理
    "user-theme@gnome-shell-extensions.gcampax.github.com" # 用户主题
    "kimpanel@kde.org"                               # Fcitx5 输入法面板
    "rounded-window-corners@fxgn"                    # 圆角窗口
    "appindicatorsupport@rgcjonas.gmail.com"         # 系统托盘支持
    "CoverflowAltTab@palatis.blogspot.com"           # 3D 覆盖流样式的 Alt-Tab 切换
    "drive-menu@gnome-shell-extensions.gcampax.github.com" # 顶部面板U盘/移动硬盘弹出菜单
    "dash-to-dock@micxgx.gmail.com"                  # Dash to Dock
    "app-hider@lynith.dev"                           # 隐藏菜单中的App
)
log "Downloading extensions..."
sudo -u $TARGET_USER gnome-extensions-cli install "${EXTENSION_LIST[@]}" 2>/dev/null

# 启用扩展
section "Step 5.2" "Enable GNOME Extensions"
sudo -u "$TARGET_USER" bash <<EOF
    # D-Bus
    if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval \$(dbus-launch --sh-syntax)
        trap "kill \$DBUS_SESSION_BUS_PID" EXIT
    fi

    echo "   ➜ Activating extensions via gsettings (D-Bus Active)..."

    # 定义安全启用扩展的函数 (追加模式)
    enable_extension() {
        local uuid="\$1"
        local current_list=\$(gsettings get org.gnome.shell enabled-extensions)
        
        # 检查是否已经在列表中
        if [[ "\$current_list" == *"\$uuid"* ]]; then
            echo "   -> Extension \$uuid already enabled."
        else
            echo "   -> Enabling extension: \$uuid"
            # 如果列表为空 (@as [])，直接设置；否则追加
            if [ "\$current_list" = "@as []" ]; then
                gsettings set org.gnome.shell enabled-extensions "['\$uuid']"
            else
                new_list="\${current_list%]}, '\$uuid']"
                gsettings set org.gnome.shell enabled-extensions "\$new_list"
            fi
        fi
    }

    echo "   ➜ Activating extensions via gsettings..."

    # 启用需要的扩展
    declare -a ext_array=(
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "arch-update@RaphaelRochet"
        "blur-my-shell@aunetx"
        "caffeine@patapon.info"
        "clipboard-indicator@tudmotu.com"
        "color-picker@tuberry"
        "desktop-cube@schneegans.github.com"
        "fuzzy-application-search@mkhl.codeberg.page"
        "lockkeys@vaina.lt"
        "tilingshell@ferrarodomenico.com"
        "kimpanel@kde.org"
        "rounded-window-corners@fxgn"
        "appindicatorsupport@rgcjonas.gmail.com"
        "CoverflowAltTab@palatis.blogspot.com"
        "drive-menu@gnome-shell-extensions.gcampax.github.com"
        "dash-to-dock@micxgx.gmail.com"
        "app-hider@lynith.dev"
    )

    for ext in "\${ext_array[@]}"; do
        enable_extension "\$ext"
    done
EOF

# 编译扩展 Schema (防止报错)
log "Compiling extension schemas..."
# 先确保所有权正确
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.local/share/gnome-shell/extensions

# 编译每个扩展的 GSettings schema
sudo -u "$TARGET_USER" bash <<EOF
    EXT_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"
    
    echo "   ➜ Compiling schemas in \$EXT_DIR..."
    for dir in "\$EXT_DIR"/*; do
        if [ -d "\$dir/schemas" ]; then
            glib-compile-schemas "\$dir/schemas"
        fi
    done
EOF

#=================================================
# Step 6: Nautilus Fix & Input Method
#=================================================
section "Step 6/8" "Configure Nautilus and Input Method"
# Nautilus NVIDIA/输入法修复
configure_nautilus_user

# 输入法环境配置
log "Configure input method environment..."
if ! grep -q "fcitx" "/etc/environment" 2>/dev/null; then
    cat << EOT >> /etc/environment
XIM="fcitx"
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
XDG_CURRENT_DESKTOP=GNOME
EOT
fi

#=================================================
# Dotfiles
#=================================================
section "Step 7/8" "Deploying dotfiles"
DOTFILES_REPO_URL="${DAGUO_DOTFILES_REPO_URL:-https://github.com/dgxz99/linux-dotfiles.git}"
DOTFILES_PARENT_DIR="$HOME_DIR/.local/share"
DOTFILES_DIR="$DOTFILES_PARENT_DIR/daguo-linux-dotfiles"
DOTLINK_BIN="$DOTFILES_DIR/.local/bin/dotlink"

if ! command -v git >/dev/null 2>&1; then
    log "Installing git for dotfiles deployment..."
    exe pacman -S --noconfirm --needed git
fi

log "Preparing dotfiles repository..."
exe as_user mkdir -p "$DOTFILES_PARENT_DIR"

# 获取或更新 dotfiles 仓库
# 1. 如果目录存在且是 git 仓库，执行 pull 更新
# 2. 如果目录存在但不是 git 仓库，备份后重新克隆
# 3. 如果目录不存在，直接克隆
if [ -d "$DOTFILES_DIR/.git" ]; then
    log "Updating dotfiles repository..."
    # 使用 --ff-only 确保不会有意外的合并或历史重写，保持仓库干净
    exe as_user git -C "$DOTFILES_DIR" pull --ff-only
elif [ -e "$DOTFILES_DIR" ]; then
    BACKUP_DOTFILES_DIR="${DOTFILES_DIR}.bak.$(date +%s)"
    log "Existing non-git dotfiles directory detected. Moving to $BACKUP_DOTFILES_DIR"
    exe as_user mv "$DOTFILES_DIR" "$BACKUP_DOTFILES_DIR"
    log "Cloning dotfiles repository..."
    exe as_user git clone "$DOTFILES_REPO_URL" "$DOTFILES_DIR"
else
    log "Cloning dotfiles repository..."
    exe as_user git clone "$DOTFILES_REPO_URL" "$DOTFILES_DIR"
fi

if [ ! -f "$DOTLINK_BIN" ]; then
    error "dotlink not found in cloned dotfiles repository: $DOTLINK_BIN"
    exit 1
fi

# Git 在大多数情况下会保留已提交的可执行位，但这里仍显式修正一次，避免文件模式或文件系统差异导致执行失败。
exe chmod +x "$DOTLINK_BIN"

log "Linking dotfiles via dotlink..."
exe as_user "$DOTLINK_BIN" link
success "Dotfiles linked."

# 创建模板文件
as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new"
sudo -u "$TARGET_USER" bash -c "echo '#!/usr/bin/env bash' > $HOME_DIR/Templates/new.sh"
sudo -u "$TARGET_USER" chmod +x "$HOME_DIR/Templates/new.sh"

# 修复关键目录权限，避免后续用户态程序写配置失败。
log "Fixing permissions..."
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.config
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.local

# ===  flatpak 权限  ====
# 允许 Flatpak 应用访问字体配置
if command -v flatpak &>/dev/null; then
    sudo -u "$TARGET_USER" flatpak override --user --filesystem=xdg-config/fontconfig
fi

# 4. 安装终端常用工具
# - starship: 终端提示符
# - eza: ls 替代品
# - fish: 交互式 shell
# - zoxide: 智能目录跳转
# - jq: JSON 处理工具
# - timg: 终端图片查看器
# - imagemagick: 图像处理工具，提供 convert 命令
# - bat: cat 替代品，带语法高亮
log "Installing shell tools..."
SHELL_TOOLS_PKGS="starship eza fish zoxide jq timg imagemagick bat"
echo "$SHELL_TOOLS_PKGS" >> "$VERIFY_LIST"
exe pacman -S --noconfirm --needed $SHELL_TOOLS_PKGS
success "Shell tools installed."

# 隐藏无用的 .desktop 文件
section "Step 8/8" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
run_hide_desktop_file

log "Installation Complete! Please reboot."
cleanup_sudo
