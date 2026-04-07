#!/usr/bin/env bash

# 音频、蓝牙、电源模块。
#
# 这些能力几乎对所有桌面都通用，因此单独放在一个中间层模块中。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root
section 'Phase 5' 'Audio, Bluetooth and Power'

# ------------------------------------------------------------------------------
# 1. Audio & Video
# ------------------------------------------------------------------------------
# 音视频系统配置
# 现代 Linux 使用 Pipewire 作为音频服务器，替代了传统的 PulseAudio
# Pipewire 的优势：
#   - 更低的延迟
#   - 更好的蓝牙音频支持
#   - 同时支持 PulseAudio 和 JACK 应用程序

section "Step 1/3" "Audio & Video"

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
log "Installing Pipewire stack..."
exe pacman -S --noconfirm --needed pipewire lib32-pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack

# 为所有用户启用 Pipewire 服务
# --global: 对所有用户生效，而不仅仅是当前用户
exe systemctl --global enable pipewire pipewire-pulse wireplumber
success "Audio setup complete."

# ------------------------------------------------------------------------------
# 2. Bluetooth (Smart Detection)
# ------------------------------------------------------------------------------
# 蓝牙配置 (智能检测)，不是所有电脑都有蓝牙硬件，所以先检测再安装

section "Step 2/3" "Bluetooth"

# Ensure detection tools are present
# 确保检测工具已安装
# usbutils: 提供 lsusb 命令
# pciutils: 提供 lspci 命令
log "Detecting Bluetooth hardware..."
exe pacman -S --noconfirm --needed usbutils pciutils

BT_FOUND=false

# 1.检查 USB 蓝牙设备 (大多数蓝牙适配器是 USB 接口)
if lsusb | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 2.检查 PCI/PCIe 蓝牙设备 (部分内置蓝牙是 PCI 设备)
if lspci | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 3.检查 rfkill 是否识别到蓝牙设备，rfkill 是 Linux 内核的无线设备开关工具
if rfkill list bluetooth >/dev/null 2>&1; then BT_FOUND=true; fi

if [ "$BT_FOUND" = true ]; then
    info_kv "Hardware" "Detected"

    # 安装 BlueZ 蓝牙协议栈
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
# 3. Power
# ------------------------------------------------------------------------------
# 电源管理
# power-profiles-daemon 提供简单的电源模式切换：
#   - 性能模式 (performance)
#   - 平衡模式 (balanced)
#   - 省电模式 (power-saver)
# GNOME 和 KDE 都能集成这个服务

section "Step 3/3" "Power Management"

exe pacman -S --noconfirm --needed power-profiles-daemon
exe systemctl enable --now power-profiles-daemon
success "Power profiles daemon enabled."

log "Phase 05 completed."