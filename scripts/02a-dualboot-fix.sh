#!/bin/bash

# ==============================================================================
# Script: 02a-dualboot-fix.sh
# Purpose: Auto-configure for Windows dual-boot (OS-Prober only).
# ==============================================================================
# 模块说明：Windows 双系统配置
# ------------------------------------------------------------------------------
# 此模块用于检测 Windows 并配置 GRUB 实现双系统启动
#
# 主要功能：
#   1. 检测系统是否安装了 GRUB
#   2. 使用 os-prober 检测 Windows 安装
#   3. 配置 GRUB 启用 os-prober
#   4. 重新生成 GRUB 配置文件
#
# 注意：
#   - 如果系统未检测到 GRUB，此模块会跳过
#   - 如果未检测到 Windows，此模块也会跳过
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# --- GRUB Installation Check ---
# GRUB 安装检查
# 检查 grub-mkconfig 命令和配置文件是否存在
# 如果系统使用其他引导程序（如 systemd-boot），则跳过
if ! command -v grub-mkconfig &>/dev/null || [ ! -f "/etc/default/grub" ]; then
    warn "GRUB is not detected. Skipping dual-boot configuration."
    exit 0
fi

# --- Helper Functions ---
# 辅助函数

# Sets a GRUB key-value pair.
# 设置 GRUB 配置的键值对
# 参数：
#   $1 - 配置键名（如 GRUB_DISABLE_OS_PROBER）
#   $2 - 配置值
# 逻辑：
#   1. 如果配置已被注释（# KEY=value），则取消注释并修改值
#   2. 如果配置已存在，则修改值
#   3. 如果配置不存在，则添加新行
set_grub_value() {
    local key="$1"
    local value="$2"
    local conf_file="/etc/default/grub"
    
    # 转义特殊字符，防止 sed 替换出错
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's,[\/&],\\&,g')

    # 检查是否为被注释的配置项
    if grep -q -E "^#\s*$key=" "$conf_file"; then
        exe sed -i -E "s,^#\s*$key=.*,$key=\"$escaped_value\"," "$conf_file"
    # 检查是否为已存在的配置项
    elif grep -q -E "^$key=" "$conf_file"; then
        exe sed -i -E "s,^$key=.*,$key=\"$escaped_value\"," "$conf_file"
    # 配置项不存在，添加新行
    else
        log "Appending new key: $key"
        echo "$key=\"$escaped_value\"" >> "$conf_file"
    fi
}

# --- Main Script ---
# 主脚本开始

section "Phase 2A" "Dual-Boot Configuration (Windows)"

# ------------------------------------------------------------------------------
# 1. Detect Windows
# ------------------------------------------------------------------------------
# 第一步：检测 Windows
# 使用 os-prober 工具扫描系统中的其他操作系统

section "Step 1/2" "System Analysis"

# 安装双系统检测工具
# os-prober: 检测其他操作系统
# exfat-utils: 支持 exFAT 文件系统（Windows 常用）
log "Installing dual-boot detection tools (os-prober, exfat-utils)..."
exe pacman -S --noconfirm --needed os-prober exfat-utils

# 运行 os-prober 检测 Windows
log "Scanning for Windows installation..."
WINDOWS_DETECTED=$(os-prober | grep -qi "windows" && echo "true" || echo "false")

if [ "$WINDOWS_DETECTED" != "true" ]; then
    log "No Windows installation detected by os-prober."
    log "Skipping dual-boot specific configurations."
    log "Module 02a completed (Skipped)."
    exit 0
fi

success "Windows installation detected."

# --- Check if already configured ---
# 检查是否已经配置过
# GRUB_DISABLE_OS_PROBER=false 表示已启用 os-prober
OS_PROBER_CONFIGURED=$(grep -q -E '^\s*GRUB_DISABLE_OS_PROBER\s*=\s*(false|"false")' /etc/default/grub && echo "true" || echo "false")

if [ "$OS_PROBER_CONFIGURED" == "true" ]; then
    log "Dual-boot settings seem to be already configured."
    echo ""
    echo -e "   ${H_YELLOW}>>> It looks like your dual-boot is already set up.${NC}"
    echo ""
fi

# ------------------------------------------------------------------------------
# 2. Configure GRUB for Dual-Boot
# ------------------------------------------------------------------------------
# 第二步：配置 GRUB 实现双系统启动
# 在 Arch Linux 中，GRUB 默认禁用 os-prober
# 需要手动启用才能检测到 Windows

section "Step 2/2" "Enabling OS Prober"

# 设置 GRUB_DISABLE_OS_PROBER=false 启用 os-prober
log "Enabling OS prober to detect Windows..."
set_grub_value "GRUB_DISABLE_OS_PROBER" "false"

success "Dual-boot settings updated."

# 重新生成 GRUB 配置文件
# 这会扫描所有分区并生成启动菜单
log "Regenerating GRUB configuration..."
if exe grub-mkconfig -o /boot/grub/grub.cfg; then
    success "GRUB configuration regenerated successfully."
else
    error "Failed to regenerate GRUB configuration."
fi

log "Module 02a completed."