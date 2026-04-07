#!/bin/bash

# ==============================================================================
# 02-musthave.sh - Essential Software, Drivers & Locale
# ==============================================================================
# 这是必备软件安装模块，负责安装系统正常运行所需的基础软件
#
# 主要功能：
#   1. Btrfs 扩展工具和 GRUB 快照集成
#   2. 音频系统 (Pipewire) 配置
#   3. 中文语言区域设置
#   4. 输入法 (Fcitx5) 安装
#   5. 蓝牙硬件检测与配置
#   6. 电源管理
#   7. 系统信息工具 (Fastfetch)
#   8. Flatpak 配置
#
# 注意：本模块需要 root 权限执行
# ==============================================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 加载工具函数库
source "$SCRIPT_DIR/00-utils.sh"

# 检查 root 权限
check_root

log ">>> Starting Phase 2: Essential (Must-have) Software & Drivers"


# ------------------------------------------------------------------------------
# 7. Fastfetch
# ------------------------------------------------------------------------------
# 第七步：安装 Fastfetch
# Fastfetch 是一个快速的系统信息显示工具，类似 neofetch 但更快
# 用于在终端中显示系统 Logo、操作系统、内核版本等信息

section "Step 7/8" "Fastfetch"
# fastfetch: 快速系统信息工具，类似 neofetch 但更快
# gdu: 快速磁盘使用分析工具，替代传统的 du 命令
# btop: 现代化的系统监视器，替代 htop，显示 CPU、内存、磁盘等资源使用情况
# cmatrix: 终端中的“黑客雨”效果，增加一些趣味性
# lolcat: 彩色输出工具，可以让终端输出更炫酷
# sl: 经典的“火车过山洞”程序，输入 sl 会看到一列火车经过，增加一些乐趣
exe pacman -S --noconfirm --needed fastfetch gdu btop cmatrix lolcat sl
success "Fastfetch installed."


log "Module 02 completed."