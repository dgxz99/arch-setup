#!/bin/bash
set -e
# ==============================================================================
# GNOME Setup Script (04d-gnome.sh)
# ==============================================================================
# 模块说明：GNOME 桌面环境安装
# ------------------------------------------------------------------------------
# GNOME 是简洁现代的桌面环境，注重用户体验和简化工作流
#
# 安装内容：
#   1. GNOME 核心组件 (gnome-desktop, gnome-control-center, gdm)
#   2. 常用应用 (Ghostty, Firefox, Nautilus, Celluloid)
#   3. 快捷键配置 (优化的键盘布局)
#   4. GNOME Shell 扩展 (平铺窗口、模糊效果等)
#   5. 输入法配置 (Fcitx5)
#   6. 点文件部署
#
# 特点：
#   - 自动配置快捷键
#   - 自动安装并启用 GNOME 扩展
#   - 集成 Fcitx5 输入法
# ==============================================================================

# 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 检查 utils 脚本
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

log "Initializing installation..."

check_root

# ==============================================================================
#  Identify User 
# ==============================================================================
# 识别目标用户
# TARGET_UID 用于后续 DBUS 配置

log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
TARGET_UID=$(id -u "$TARGET_USER") # 提前获取 UID，后续 DBUS 配置需要
HOME_DIR="/home/$TARGET_USER"

info_kv "Target User" "$TARGET_USER"
info_kv "Home Dir"    "$HOME_DIR"

# ==================================
# temp sudo without passwd
# ==================================
# 创建临时 sudo 免密码文件
# 安装过程中 AUR 包需要以普通用户身份运行 yay

SUDO_TEMP_FILE="/etc/sudoers.d/99_daguo_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

# 清理函数 - 结束时删除临时免密码文件
cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}

# 注册清理陷阱
trap cleanup_sudo EXIT INT TERM

#=================================================
# Step 1: Install base pkgs
#=================================================
# 第一步：安装基础包

# [桌面与核心组件]
# gnome-desktop: GNOME 桌面核心底层库
# gdm: GNOME Display Manager (登录管理器)
# gnome-control-center: 系统设置中心
# gnome-tweaks: GNOME 高级优化工具 (换主题/字体必装)
# gnome-software --> bazaar-git【yay】: 软件应用商店
# flatpak: 通用沙盒应用支持
# gnome-backgrounds: GNOME 默认壁纸集合

# [日常应用]
# ghostty: 现代 GPU 加速终端模拟器
# celluloid: GTK4 视频播放器 (基于 mpv)
# loupe: GNOME 图片查看器
# firefox: 网页浏览器

# [网络与系统工具]
# nm-connection-editor: 高级网络连接编辑器
# dnsmasq: 本地 DNS 缓存与 DHCP 服务
# gnome-keyring: 密码环 (保存 Wi-Fi 密码及应用凭证)
#
# [文件管理器与扩展支持]
# nautilus: GNOME 官方文件管理器核心
# nautilus-python: Python 扩展支持
# nautilus-open-any-terminal: 右键菜单"在终端打开"插件
# file-roller: 归档管理器 (解压缩支持)
# ffmpegthumbnailer: 视频缩略图生成器
# gvfs-smb: SMB 局域网共享支持
# gvfs-mtp: MTP 设备支持[USB手机]
# gvfs-gphoto2: 数码相机支持
# libgsf: 结构化文件支持 [用于生成旧版 MS Office 文档(.doc/.xls)和 EPUB 电子书的缩略图]
# gst-plugins-base / good / libav: GStreamer 多媒体与 FFmpeg 解码支持
#
# [字体]
# ttf-cascadia-code-nerd: 微软 Cascadia Code 编程字体 (含 Nerd Fonts 图标)

section "Step 1" "Install base pkgs"
log "Installing GNOME and base tools..."
if exe pacman -S --noconfirm --needed \
    gnome-desktop gdm gnome-control-center gnome-tweaks flatpak \
    ghostty celluloid loupe firefox \
    nm-connection-editor dnsmasq gnome-keyring \
    nautilus nautilus-python nautilus-open-any-terminal file-roller \
    ffmpegthumbnailer gvfs-smb gvfs-mtp gvfs-gphoto2 libgsf gst-plugins-base gst-plugins-good gst-libav \
    ttf-cascadia-code-nerd && \
   exe as_user yay -S --noconfirm --needed bazaar-git; then

        log "Packages installed successfully."

else
        log "Installation failed."
        return 1
fi


# 启用 GDM (GNOME Display Manager)
log "Enable gdm..."
exe systemctl enable gdm

#=================================================
# Step 2: Set default terminal
#=================================================
# 第二步：设置默认终端
# 将 Ghostty 设为 GNOME 默认终端

section "Step 2" "Set default terminal"
log "Setting GNOME default terminal to Ghostty..."

# 使用 sudo -u 切换用户，并启动临时 dbus-launch 以确保 gsettings 生效
sudo -u "$TARGET_USER" bash <<EOF
    # D-Bus Fix
    if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval \$(dbus-launch --sh-syntax)
        trap "kill \$DBUS_SESSION_BUS_PID" EXIT
    fi

    gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'
EOF

#=================================================
# Step 3: Set locale
#=================================================
# 第三步：设置区域
# 配置 AccountsService 使登录界面显示中文

section "Step 3" "Set locale"
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
section "Step 4" "Configure Shortcuts"
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
    P1=\$(add_custom 1 "openterminal" "ghostty" "<Super>t")
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
# "middleclickclose@paolo.tranquilli.gmail.com"    # 中键关闭标签
# "steal-my-focus-window@steal-my-focus-window"    # 窗口焦点窃取

section "Step 5" "Install Extensions"
log "Installing Extensions CLI..."

sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-extensions-cli extension-manager

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
# nautilus fix
#=================================================
# Nautilus NVIDIA/输入法修复
configure_nautilus_user
#=================================================
# Step 6: Input Method
#=================================================
# 第六步：输入法配置
# 配置 Fcitx5 环境变量

section "Step 6" "Input method"
log "Configure input method environment..."

# 定义 systemd 用户环境变量目录
ENV_DIR="/home/$TARGET_USER/.config/environment.d"
sudo -u "$TARGET_USER" mkdir -p "$ENV_DIR"

# 添加 Fcitx5 环境变量
sudo -u "$TARGET_USER" cat << EOT > "$ENV_DIR/fcitx5.conf"
# Fcitx5 Environment Variables (Wayland Optimized)
XMODIFIERS=@im=fcitx
QT_IM_MODULE=fcitx
# GLFW_IM_MODULE=ibus # (可选) 如果你玩 Minecraft 等基于 GLFW 的游戏，可以解开这行注释
EOT

#=================================================
# Dotfiles
#=================================================
# 点文件部署
# 复制 GNOME 配置文件到用户家目录
# 先复制 common (公共配置)，再复制 gnome (桌面特有配置)

section "Dotfiles" "Deploying dotfiles"
COMMON_DOTFILES_DIR=$PARENT_DIR/dotfiles/common
GNOME_DOTFILES_DIR=$PARENT_DIR/dotfiles/gnome

# 1. 确保目标目录存在
log "Ensuring .config exists..."
sudo -u $TARGET_USER mkdir -p $HOME_DIR/.config

# 2. 复制文件 (包含隐藏文件)
# 使用 /. 语法将源文件夹的*内容*合并到目标文件夹
# 先复制公共配置，再复制 GNOME 特有配置 (后者覆盖前者)
log "Copying common dotfiles..."
if [ -d "$COMMON_DOTFILES_DIR" ]; then
    cp -rf "$COMMON_DOTFILES_DIR/." "$HOME_DIR/"
else
    warn "Common dotfiles directory not found: $COMMON_DOTFILES_DIR"
fi

log "Copying GNOME dotfiles..."
if [ -d "$GNOME_DOTFILES_DIR" ]; then
    cp -rf "$GNOME_DOTFILES_DIR/." "$HOME_DIR/"
else
    warn "GNOME dotfiles directory not found: $GNOME_DOTFILES_DIR"
fi
# 创建模板文件
as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new"
sudo -u "$TARGET_USER" bash -c "echo '#!/bin/bash' > $HOME_DIR/Templates/new.sh"
sudo -u "$TARGET_USER" chmod +x "$HOME_DIR/Templates/new.sh"
# 3. 修复权限 (因为 cp 是 root 运行的)
# 明确修复 home 目录下的关键配置文件夹，避免权限问题
log "Fixing permissions..."
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.config
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.local

# ===  flatpak 权限  ====
# 允许 Flatpak 应用访问字体配置
if command -v flatpak &>/dev/null; then
    sudo -u "$TARGET_USER" flatpak override --user --filesystem=xdg-config/fontconfig
fi

# 4. 安装 Shell 工具
# thefuck: 命令纠错
# starship: 终端提示符
# eza: ls 替代品
# fish: 友好的 Shell
# zoxide: cd 替代品
# jq: JSON 处理工具
log "Installing shell tools..."
pacman -S --noconfirm --needed thefuck starship fish

log "Installation Complete! Please reboot."
cleanup_sudo