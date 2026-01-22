#!/bin/bash

# ==============================================================================
# 01-base.sh - Base System Configuration
# ==============================================================================
# 这是安装流程的第一个配置模块，负责设置基础系统环境
#
# 主要功能：
#   1. 设置全局默认文本编辑器
#   2. 启用 multilib 仓库 (32位库支持)
#   3. 安装基础字体 (中文字体、Emoji、编程字体等)
#   4. 配置 archlinuxcn 仓库 (国内镜像源)
#   5. 安装 AUR 助手 (yay, paru)
#
# 注意：本模块需要 root 权限执行
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log "Starting Phase 1: Base System Configuration..."

# ------------------------------------------------------------------------------
# 1. Set Global Default Editor
# ------------------------------------------------------------------------------
# 第一步：设置全局默认文本编辑器
# EDITOR 环境变量被很多命令行工具使用，如 git commit、crontab -e、visudo 等
# 没有设置的话，默认可能是 vi，对新手不友好

section "Step 1/6" "Global Default Editor"

# 默认使用 vim
TARGET_EDITOR="vim"

# 检测系统中已安装的编辑器，按优先级选择：nvim > nano > vim
# command -v: 检查命令是否存在 (比 which 更可靠)
# &> /dev/null: 将标准输出和错误输出都重定向到空设备
if command -v nvim &> /dev/null; then
    TARGET_EDITOR="nvim"
    log "Neovim detected."
elif command -v nano &> /dev/null; then
    TARGET_EDITOR="nano"
    log "Nano detected."
else
    log "Neovim or Nano not found. Installing Vim..."
    # 如果 vim 也不存在，则安装 gvim (包含 vim 和剪贴板支持)
    if ! command -v vim &> /dev/null; then
        exe pacman -Syu --noconfirm gvim
    fi
fi

log "Setting EDITOR=$TARGET_EDITOR in /etc/environment..."

# /etc/environment 是系统级环境变量配置文件
# 所有用户登录时都会加载这个文件中的变量
if grep -q "^EDITOR=" /etc/environment; then
    # 如果已存在 EDITOR 设置，则替换它
    exe sed -i "s/^EDITOR=.*/EDITOR=${TARGET_EDITOR}/" /etc/environment
else
    # exe handles simple commands, for redirection we wrap in bash -c or just run it
    # For simplicity in logging, we just run it and log success
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

section "Step 2/6" "Multilib Repository"

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
    
    log "Refreshing database..."
    # 同步包数据库以获取新启用的 multilib 仓库内容
    exe pacman -Syu
    success "[multilib] enabled."
fi

# ------------------------------------------------------------------------------
# 3. Install Base Fonts
# ------------------------------------------------------------------------------
# 第三步：安装基础字体
# 没有字体的话，系统会显示方块/乱码
# 这里安装的字体包括：
#   - adobe-source-han-serif-cn-fonts: 思源宋体（中文衣线体）
#   - adobe-source-han-sans-cn-fonts: 思源黑体（中文无衣线体）
#   - noto-fonts-cjk: Google Noto 中日韩字体
#   - noto-fonts: Google Noto 基础字体
#   - noto-fonts-emoji: Emoji 表情字体
#   - ttf-jetbrains-mono-nerd: JetBrains Mono 编程字体 (Nerd Fonts 版，包含图标)

section "Step 3/6" "Base Fonts"

log "Installing adobe-source-han-serif-cn-fonts adobe-source-han-sans-cn-fonts noto-fonts-cjk, noto-fonts, emoji..."
# exe pacman -S --noconfirm --needed adobe-source-han-serif-cn-fonts adobe-source-han-sans-cn-fonts noto-fonts-cjk noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
exe pacman -S --noconfirm --needed noto-fonts-cjk noto-fonts noto-fonts-emoji ttf-cascadia-mono-nerd
log "Base fonts installed."

# 配置 TTY 控制台字体
# TTY 是 Linux 的虚拟终端 (Ctrl+Alt+F1~F6)
# 默认字体很小，在高分辨率显示器上几乎看不清
log "Installing terminus-font..."
# 安装 terminus-font 包
# Terminus 是一款清晰的位图字体，非常适合 TTY 使用
exe pacman -S --noconfirm --needed terminus-font

log "Setting font for current session..."
# setfont 用于设置当前 TTY 的字体
# ter-v28n: Terminus 字体，28 像素高，n 表示正常粗细
exe setfont ter-v28n

log "Configuring permanent vconsole font..."
# /etc/vconsole.conf 是控制台配置文件
# 设置 FONT 变量使字体在每次启动时自动应用
if [ -f /etc/vconsole.conf ] && grep -q "^FONT=" /etc/vconsole.conf; then
    # 如果已有 FONT 设置，则替换
    exe sed -i 's/^FONT=.*/FONT=ter-v28n/' /etc/vconsole.conf
else
    # 如果没有，则追加
    echo "FONT=ter-v28n" >> /etc/vconsole.conf
fi

log "Restarting systemd-vconsole-setup..."
# 重启 vconsole 服务以应用新配置
exe systemctl restart systemd-vconsole-setup

success "TTY font configured (ter-v24n)."
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

section "Step 4/6" "ArchLinuxCN Repository"

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
    success "Mirrors added."
fi

log "Installing archlinuxcn-keyring..."
# Keyring installation often needs -Sy specifically, but -Syu is safe too
# 安装 archlinuxcn 的 GPG 密钥环，用于验证软件包签名
exe pacman -Syu --noconfirm archlinuxcn-keyring
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

section "Step 5/6" "AUR Helpers"

log "Installing yay and paru..."
exe pacman -S --noconfirm --needed base-devel yay paru
success "Helpers installed."

# 模块完成
log "Module 01 completed."

