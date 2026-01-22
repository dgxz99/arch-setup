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
# 1. Btrfs Extras & GRUB (Config was done in 00-btrfs-init)
# ------------------------------------------------------------------------------
# 第一步：Btrfs 扩展工具和 GRUB 快照集成
# 在 00-btrfs-init.sh 中已经初始化了基本的 Snapper 配置
# 这里安装额外的工具和配置 GRUB 集成

section "Step 1/8" "Btrfs Extras & GRUB"

# 检测根分区文件系统类型
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Btrfs filesystem detected."
    # 安装 Btrfs 相关工具：
    #   - snapper: 快照管理器
    #   - snap-pac: 在 pacman 操作前后自动创建快照
    #   - btrfs-assistant: 图形化 Btrfs 管理工具
    exe pacman -S --noconfirm --needed snapper snap-pac btrfs-assistant
    success "Snapper tools installed."

    # 检查并初始化 Snapper 配置
    log "Initializing Snapper 'root' configuration..."
    if ! snapper list-configs | grep -q "^root "; then
        # 如果 .snapshots 目录已存在但不是 Snapper 管理的，需要清理
        if [ -d "/.snapshots" ]; then
            warn "Removing existing /.snapshots..."
            exe_silent umount /.snapshots
            exe_silent rm -rf /.snapshots
        fi
        if exe snapper -c root create-config /; then
            success "Snapper config created."
            # 设置快照保留策略
            log "Applying retention policy..."
            exe snapper -c root set-config ALLOW_GROUPS="wheel" TIMELINE_CREATE="no" TIMELINE_CLEANUP="yes" NUMBER_LIMIT="10" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_LIMIT_HOURLY="5" TIMELINE_LIMIT_DAILY="7" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="0" TIMELINE_LIMIT_YEARLY="0"
            success "Policy applied."
        fi
    else
        log "Config exists."
    fi
    
    # 启用 Snapper 定时器，用于自动创建和清理快照
    exe systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

    # GRUB Integration
    # GRUB 集成：允许从 GRUB 菜单启动到快照
if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
        log "Checking GRUB..."
        
        # 查找 ESP (EFI 系统分区) 中的 GRUB 目录
         FOUND_EFI_GRUB=""
        
        # 1. 使用 findmnt 查找所有 vfat 类型的挂载点 (通常 ESP 是 vfat)
        # -n: 不输出标题头
        # -l: 列表格式输出
        # -o TARGET: 只输出挂载点路径
        # -t vfat: 限制文件系统类型
        # sort -r: 反向排序，这样 /boot/efi 会排在 /boot 之前（如果同时存在），优先匹配深层路径
        VFAT_MOUNTS=$(findmnt -n -l -o TARGET -t vfat)

        if [ -n "$VFAT_MOUNTS" ]; then
            # 2. 遍历这些 vfat 分区，寻找 grub 目录
            # 使用 while read 循环处理多行输出
            while read -r mountpoint; do
                # 检查这个挂载点下是否有 grub 目录
                if [ -d "$mountpoint/grub" ]; then
                    FOUND_EFI_GRUB="$mountpoint/grub"
                    log "Found GRUB directory in ESP mountpoint: $mountpoint"
                    break 
                fi
            done <<< "$VFAT_MOUNTS"
        fi

        # 3. 如果找到了位于 ESP 中的 GRUB 真实路径
        if [ -n "$FOUND_EFI_GRUB" ]; then
            
            # -e 判断存在, -L 判断是软链接 
            if [ -e "/boot/grub" ] || [ -L "/boot/grub" ]; then
                warn "Skip" "/boot/grub already exists. No symlink created."
            else
                # 5. 仅当完全不存在时，创建软链接
                # 这解决了某些系统上 GRUB 安装在 ESP 分区但 /boot/grub 不存在的问题
                warn "/boot/grub is missing. Linking to $FOUND_EFI_GRUB..."
                exe ln -sf "$FOUND_EFI_GRUB" /boot/grub
                success "Symlink created: /boot/grub -> $FOUND_EFI_GRUB"
            fi
        else
            log "No 'grub' directory found in any active vfat mounts. Skipping symlink check."
        fi
        # --- 核心修改结束 ---

        # 安装 grub-btrfs 和 inotify-tools
        # grub-btrfs: 在 GRUB 菜单中显示 Btrfs 快照，允许启动到快照
        # inotify-tools: 文件系统监控工具，grub-btrfsd 需要
        exe pacman -Syu --noconfirm --needed grub-btrfs inotify-tools
        # 启用 grub-btrfsd 服务，它会监控快照变化并自动更新 GRUB 菜单
        exe systemctl enable --now grub-btrfsd

        # 添加 overlayfs hook 到 mkinitcpio
        # 这允许从只读快照启动时使用 overlayfs 覆盖层
        if ! grep -q "grub-btrfs-overlayfs" /etc/mkinitcpio.conf; then
            log "Adding overlayfs hook to mkinitcpio..."
            # 在 HOOKS 数组末尾添加 grub-btrfs-overlayfs
            sed -i 's/^HOOKS=(\(.*\))/HOOKS=(\1 grub-btrfs-overlayfs)/' /etc/mkinitcpio.conf
            # 重新生成所有内核的 initramfs
            exe mkinitcpio -P
        fi

        log "Regenerating GRUB..."
        exe grub-mkconfig -o /boot/grub/grub.cfg
    fi
else
    log "Root is not Btrfs. Skipping Snapper setup."
fi

# ------------------------------------------------------------------------------
# 2. Audio & Video
# ------------------------------------------------------------------------------
# 第二步：音视频系统配置
# 现代 Linux 使用 Pipewire 作为音频服务器，替代了传统的 PulseAudio
# Pipewire 的优势：
#   - 更低的延迟
#   - 更好的蓝牙音频支持
#   - 同时支持 PulseAudio 和 JACK 应用程序

section "Step 2/8" "Audio & Video"

# 安装音频固件
# sof-firmware: Intel Sound Open Firmware，新款 Intel 笔记本需要
# alsa-ucm-conf: ALSA 用例管理器配置
# alsa-firmware: ALSA 固件
log "Installing firmware..."
exe pacman -S --noconfirm --needed sof-firmware alsa-ucm-conf alsa-firmware

# 安装 Pipewire 堆栈
# pipewire: 核心音频服务器
# wireplumber: Pipewire 的会话管理器
# pipewire-pulse: PulseAudio 兼容层
# pipewire-alsa: ALSA 兼容层
# pipewire-jack: JACK 兼容层 (专业音频应用需要)
# pavucontrol: PulseAudio 音量控制界面
log "Installing Pipewire stack..."
exe pacman -S --noconfirm --needed pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack pavucontrol

# 为所有用户启用 Pipewire 服务
# --global: 对所有用户生效，而不仅仅是当前用户
exe systemctl --global enable pipewire pipewire-pulse wireplumber
success "Audio setup complete."

# ------------------------------------------------------------------------------
# 3. Locale
# ------------------------------------------------------------------------------
# 第三步：语言区域配置
# Locale 决定了系统的语言、日期格式、数字格式等
# 中文用户需要启用 zh_CN.UTF-8

section "Step 3/8" "Locale Configuration"

# 检查中文区域是否已经激活
# locale -a: 列出所有可用的区域设置
if locale -a | grep -iq "zh_CN.utf8"; then
    success "Chinese locale (zh_CN.UTF-8) is active."
else
    # 如果未激活，则取消注释 /etc/locale.gen 中的 zh_CN.UTF-8 行
    log "Generating zh_CN.UTF-8..."
    sed -i 's/^#\s*zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    # locale-gen 根据 locale.gen 生成区域数据
    if exe locale-gen; then
        success "Locale generated."
    else
        error "Locale generation failed."
    fi
fi

# ------------------------------------------------------------------------------
# 4. Input Method
# ------------------------------------------------------------------------------
# 第四步：输入法安装
# Fcitx5 是现代的 Linux 输入法框架，支持中文、日文等多种语言
# fcitx5-im: Fcitx5 核心组件元包
# fcitx5-chinese-addons: 中文输入法插件 (包含拼音、五笔等)
# fcitx5-mozc: 日文输入法 (Mozc)

section "Step 4/8" "Input Method (Fcitx5)"

exe pacman -S --noconfirm --needed fcitx5-im fcitx5-chinese-addons fcitx5-mozc

success "Fcitx5 installed."

# ------------------------------------------------------------------------------
# 5. Bluetooth (Smart Detection)
# ------------------------------------------------------------------------------
# 第五步：蓝牙配置 (智能检测)
# 不是所有电脑都有蓝牙硬件，所以先检测再安装
# 这样可以避免在没有蓝牙硬件的系统上安装不必要的软件

section "Step 5/8" "Bluetooth"

# Ensure detection tools are present
# 确保检测工具已安装
# usbutils: 提供 lsusb 命令
# pciutils: 提供 lspci 命令
log "Detecting Bluetooth hardware..."
exe pacman -S --noconfirm --needed usbutils pciutils

BT_FOUND=false

# 1. Check USB
# 检查 USB 蓝牙设备 (大多数蓝牙适配器是 USB 接口)
if lsusb | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 2. Check PCI
# 检查 PCI/PCIe 蓝牙设备 (部分内置蓝牙是 PCI 设备)
if lspci | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 3. Check RFKill
# 检查 rfkill 是否识别到蓝牙设备
# rfkill 是 Linux 内核的无线设备开关工具
if rfkill list bluetooth >/dev/null 2>&1; then BT_FOUND=true; fi

if [ "$BT_FOUND" = true ]; then
    info_kv "Hardware" "Detected"

    # 安装 BlueZ 蓝牙協议栈
    log "Installing Bluez "
    exe pacman -S --noconfirm --needed bluez

    # 启用蓝牙服务
    exe systemctl enable --now bluetooth
    success "Bluetooth service enabled."
else
    info_kv "Hardware" "Not Found"
    warn "No Bluetooth device detected. Skipping installation."
fi

# ------------------------------------------------------------------------------
# 6. Power
# ------------------------------------------------------------------------------
# 第六步：电源管理
# power-profiles-daemon 提供简单的电源模式切换：
#   - 性能模式 (performance)
#   - 平衡模式 (balanced)
#   - 省电模式 (power-saver)
# GNOME 和 KDE 都能集成这个服务

section "Step 6/8" "Power Management"

exe pacman -S --noconfirm --needed power-profiles-daemon
exe systemctl enable --now power-profiles-daemon
success "Power profiles daemon enabled."

# ------------------------------------------------------------------------------
# 7. Fastfetch
# ------------------------------------------------------------------------------
# 第七步：安装 Fastfetch
# Fastfetch 是一个快速的系统信息显示工具，类似 neofetch 但更快
# 用于在终端中显示系统 Logo、操作系统、内核版本等信息

section "Step 7/8" "Fastfetch"

exe pacman -S --noconfirm --needed fastfetch
success "Fastfetch installed."

log "Module 02 completed."

# ------------------------------------------------------------------------------
# 9. flatpak
# ------------------------------------------------------------------------------
# 第九步：Flatpak 配置
# Flatpak 是一个跨发行版的应用程序打包格式
# 优势：
#   - 应用程序与系统库隔离，更安全
#   - 可以运行不同版本的同一应用
#   - Flathub 仓库有大量应用

exe pacman -S --noconfirm --needed flatpak
# 添加 Flathub 远程仓库
# --if-not-exists: 如果已存在则跳过
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 检测是否为中国用户，如果是则使用国内镜像
CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false
# 检查时区是否为上海，或手动设置了 CN_MIRROR 环境变量
if [[ "$CURRENT_TZ" == *"Shanghai"* ]] || [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
  IS_CN_ENV=true
  info_kv "Region" "China Optimization Active"
fi

if [ "$IS_CN_ENV" = true ]; then
  # 调用 00-utils.sh 中定义的 Flathub 镜像选择函数
  select_flathub_mirror
else
  log "Using Global Sources."
fi