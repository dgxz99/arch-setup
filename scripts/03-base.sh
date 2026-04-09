#!/bin/bash

# ==============================================================================
# 03-base.sh - Base System Configuration
# ==============================================================================
# 负责设置基础系统环境
# 主要功能：
#   1. 设置全局默认文本编辑器
#   2. 启用 multilib 仓库 (32位库支持)
#   3. 安装基础字体 (中文字体、Emoji、编程字体等)
#   4. 配置 archlinuxcn 仓库 (国内镜像源)
#   5. 安装 AUR 助手 (yay, paru)
# 注意：本模块需要 root 权限执行
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log "Starting Phase 3: Base System Configuration..."
PACMAN_DB_NEEDS_REFRESH=false

# ------------------------------------------------------------------------------
# 1. Set Global Default Editor 设置全局默认文本编辑器
# ------------------------------------------------------------------------------
# EDITOR 环境变量被很多命令行工具使用，如 git commit、crontab -e、visudo 等，没有设置的话，默认可能是 vi，对新手不友好

section "Step 1/7" "Global Default Editor"

# 默认使用 vim
TARGET_EDITOR="vim"
# command -v: 检查命令是否存在 (比 which 更可靠)
# &> /dev/null: 将标准输出和错误输出都重定向到空设备
if ! command -v vim &> /dev/null; then
    exe pacman -S --noconfirm --needed vim
fi

log "Setting EDITOR=$TARGET_EDITOR in /etc/environment..."

# /etc/environment 是系统级环境变量配置文件
# 所有用户登录时都会加载这个文件中的变量
if grep -q "^EDITOR=" /etc/environment; then
    # 如果已存在 EDITOR 设置，则替换它
    exe sed -i "s/^EDITOR=.*/EDITOR=${TARGET_EDITOR}/" /etc/environment
else
    # 如果不存在，则追加一行
    echo "EDITOR=${TARGET_EDITOR}" >> /etc/environment
fi
success "Global EDITOR set to: ${TARGET_EDITOR}"

# ------------------------------------------------------------------------------
# 2. Enable 32-bit (multilib) Repository
# ------------------------------------------------------------------------------
# 第二步：启用 multilib 仓库
# multilib 提供 32 位库和软件包，运行某些程序需要：
#   - Steam 游戏平台 (很多游戏是 32 位的)
#   - Wine (运行 Windows 程序)
#   - 某些显卡驱动 (lib32-nvidia-utils 等)
# Arch Linux 默认不启用 multilib，需要手动开启

section "Step 2/7" "Multilib Repository"

# 检查 pacman.conf 中是否已启用 [multilib]
# ^\[multilib\]: 匹配行首的 [multilib] (需要转义方括号)
if grep -q "^\[multilib\]" /etc/pacman.conf; then
    success "[multilib] is already enabled."
else
    log "Uncommenting [multilib]..."
    # Uncomment [multilib] and the following Include line
    # 取消注释 [multilib] 和它下面的 Include 行
    # sed 地址范围 /\[multilib\]/,/Include/ 表示从 [multilib] 行到包含 Include 的行
    # 's/^#//': 删除行首的 # 号
    exe sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
    log "Refreshing package database for newly enabled multilib repository..."
    exe pacman -Sy --noconfirm || exit 1
    success "[multilib] enabled."
fi

# ------------------------------------------------------------------------------
# 3. Install Base Fonts
# ------------------------------------------------------------------------------
# 第三步：安装基础字体
# 没有字体的话，系统会显示方块/乱码
# 这里安装的字体包括：
#   - noto-fonts-cjk: Google Noto 中日韩字体
#   - noto-fonts: Google Noto 基础字体
#   - noto-fonts-emoji: Emoji 表情字体
#   - ttf-jetbrains-mono-nerd: JetBrains Mono 编程字体 (Nerd Fonts 版，包含图标)
#   - ttf-cascadia-mono-nerd: Cascadia Mono 编程字体 (Nerd Fonts 版，包含图标)
#   - ttf-liberation: Liberation 字体，常用的开源替代字体
#   - otf-font-awesome: Font Awesome 图标字体
#   - terminus-font: 适合 TTY 的位图字体
section "Step 3/7" "Base Fonts"

log "Installing noto-fonts-cjk, noto-fonts, emoji..."
exe pacman -S --noconfirm --needed noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-cascadia-mono-nerd otf-font-awesome || exit 1
success "Base fonts installed."

# 配置 TTY 控制台字体
log "Installing terminus-font..."
exe pacman -S --noconfirm --needed terminus-font || exit 1

log "Setting font for current session..."
# setfont 用于设置当前 TTY 的字体
# ter-v28n: Terminus 字体，28 像素高，n 表示正常粗细
exe setfont ter-v28n || exit 1

log "Configuring permanent vconsole font..."
# /etc/vconsole.conf 是控制台配置文件
# 设置 FONT 变量使字体在每次启动时自动应用
if [ -f /etc/vconsole.conf ] && grep -q "^FONT=" /etc/vconsole.conf; then
    exe sed -i 's/^FONT=.*/FONT=ter-v28n/' /etc/vconsole.conf
else
    echo "FONT=ter-v28n" >> /etc/vconsole.conf
fi

log "Restarting systemd-vconsole-setup..."
# 重启 vconsole 服务以应用新配置
exe systemctl restart systemd-vconsole-setup || exit 1

success "TTY font configured (ter-v28n)."
# ------------------------------------------------------------------------------
# 4. Configure archlinuxcn Repository
# ------------------------------------------------------------------------------
# 第四步：配置 archlinuxcn 仓库
# archlinuxcn 是由 Arch Linux 中文社区维护的第三方仓库
# 提供的软件包括：
#   - 国内常用软件（微信、QQ、网易云音乐等）
#   - AUR 助手（yay、paru）的预编译版本
#   - 其他常用工具
# 优势：不需要从 AUR 编译，下载速度快（国内镜像）

section "Step 4/7" "ArchLinuxCN Repository"

# 检查是否已配置 archlinuxcn
if grep -q "\[archlinuxcn\]" /etc/pacman.conf; then
    success "archlinuxcn repository already exists."
else
    log "Adding archlinuxcn mirrors to pacman.conf..."

    # 使用 heredoc 追加多个镜像源
    # 多个 Server 行可以提供冗余，当第一个不可用时自动尝试下一个
    # 包含的镜像源：
    #   - USTC: 中国科学技术大学
    #   - TUNA: 清华大学
    #   - HIT: 哈尔滨工业大学
    #   - Huawei Cloud: 华为云
    cat <<EOT >> /etc/pacman.conf

[archlinuxcn]
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.hit.edu.cn/archlinuxcn/\$arch
Server = https://repo.huaweicloud.com/archlinuxcn/\$arch
EOT
        PACMAN_DB_NEEDS_REFRESH=true
    success "Mirrors added."
fi

log "Installing archlinuxcn-keyring..."
# 安装 archlinuxcn 的 GPG 密钥环，用于验证软件包签名
if [ "$PACMAN_DB_NEEDS_REFRESH" = true ]; then
    log "Refreshing package database for newly enabled repositories..."
    exe pacman -Sy --noconfirm
fi
exe pacman -S --noconfirm --needed archlinuxcn-keyring
success "ArchLinuxCN configured."

# ------------------------------------------------------------------------------
# 5. Install AUR Helpers
# ------------------------------------------------------------------------------
# 第五步：安装 AUR 助手
# AUR (Arch User Repository) 是社区维护的软件包仓库
# 包含官方仓库没有的大量软件，如 google-chrome、visual-studio-code-bin 等
#
# AUR 助手可以自动化 AUR 包的下载、编译、安装过程：
#   - yay: 最流行的 AUR 助手，用 Go 语言编写
#   - paru: 功能更强大，用 Rust 语言编写，默认显示 PKGBUILD 审查
#
# base-devel: 基础开发工具包组 (编译 AUR 包必需)
#   包含: gcc, make, autoconf, automake, binutils, fakeroot, patch 等
#
# 注意：这里直接从 archlinuxcn 安装预编译版，不需要从 AUR 编译

section "Step 5/7" "AUR Helpers"

log "Installing yay and paru..."
exe pacman -S --noconfirm --needed base-devel yay paru
success "Helpers installed."

# ------------------------------------------------------------------------------
# 6. Configure NetworkManager Backend (iwd)
# ------------------------------------------------------------------------------
# 第六步：配置 NetworkManager 使用 iwd 作为 WiFi 后端
# NetworkManager 默认使用 wpa_supplicant 管理 WiFi 连接
# iwd (iNet Wireless Daemon) 是 Intel 开发的现代 WiFi 管理守护进程
#
# iwd 相比 wpa_supplicant 的优势：
#   - 更快的连接速度和更低的内存占用
#   - 更简洁的配置和更好的安全性
#   - 内置的网络配置存储（无需额外依赖）
#   - 支持现代 WiFi 功能（如 SAE/WPA3）
#
# impala: 一个基于 TUI 的 iwd 前端工具，方便在终端中管理 WiFi
#
# 注意：此配置仅在系统已安装 NetworkManager 时生效

section "Step 6/7" "Network Backend (iwd)"

# 检查 NetworkManager 是否已安装
# pacman -Qi: 查询本地已安装的包信息
if pacman -Qi networkmanager &> /dev/null; then
    log "NetworkManager detected. Proceeding with iwd backend configuration..."

    log "Configuring NetworkManager to use iwd backend..."
    # 安装 iwd 守护进程和 impala TUI 管理工具
    exe pacman -S --noconfirm --needed iwd impala
    # 启用 iwd 服务，使其开机自动启动
    exe systemctl enable iwd
    
    # 确保 NetworkManager 配置目录存在
    # conf.d 目录用于存放模块化配置文件
    if [ ! -d /etc/NetworkManager/conf.d ]; then
        exe mkdir -p /etc/NetworkManager/conf.d
    fi
    # 创建配置文件，指定 WiFi 后端为 iwd
    # [device] 节下的 wifi.backend 选项告诉 NetworkManager 使用 iwd 而非 wpa_supplicant
    cat <<'EOF' > /etc/NetworkManager/conf.d/iwd.conf
[device]
wifi.backend=iwd
EOF

    # 不立即重启 NetworkManager，避免断开当前网络连接
    # 配置将在下次重启后生效
    log "Notice: NetworkManager restart deferred. Changes will apply after reboot."
    success "Network backend configured (iwd)."
else
    log "NetworkManager not found. Skipping iwd configuration."
fi

# ------------------------------------------------------------------------------
# 7. Install Base CLI Utilities
# ------------------------------------------------------------------------------
# 第七步：安装基础命令行工具
# 这些工具对所有桌面都通用，放在 base 阶段统一提供：
#   - fastfetch: 系统信息展示
#   - gdu: 磁盘占用分析
#   - btop: 交互式资源监视器

section "Step 7/7" "Base CLI Utilities"

log "Installing base CLI utilities..."
exe pacman -S --noconfirm --needed fastfetch gdu btop
success "Base CLI utilities installed."

# 模块完成
log "Module 03 completed."
