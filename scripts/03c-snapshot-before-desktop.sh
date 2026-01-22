#!/bin/bash

# ==============================================================================
# 03c-snapshot-before-desktop.sh
# Creates a system snapshot before installing major Desktop Environments.
# ==============================================================================
# 模块说明：桌面环境安装前快照
# ------------------------------------------------------------------------------
# 此模块在安装桌面环境之前创建系统快照
#
# 为什么需要这个快照？
#   - 桌面环境安装会带来大量变化
#   - 如果安装出问题，可以快速回滚到这个状态
#   - 相当于一个"安全检查点"
#
# 功能：
#   1. 检查 Snapper 是否已安装
#   2. 为 root 分区创建快照 (如果配置存在)
#   3. 为 home 分区创建快照 (如果配置存在)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. 引用工具库
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# 2. 权限检查 - 创建快照需要 root 权限
check_root

section "Phase 3c" "System Snapshot"

# ==============================================================================

# create_checkpoint 函数
# 创建安全检查点快照
create_checkpoint() {
    # 快照描述，用于标识这个快照的用途
    local MARKER="Before Desktop Environments"
    
    # 0. 检查 snapper 是否安装
    # 如果用户没有安装 snapper，直接跳过
    if ! command -v snapper &>/dev/null; then
        warn "Snapper tool not found. Skipping snapshot creation."
        return
    fi

    # 1. Root 分区快照
    # 检查 root 配置是否存在 (00-btrfs-init.sh 创建)
    if snapper -c root get-config &>/dev/null; then
        # 检查是否已存在同名快照 (避免重复创建)
        # 如果用户重复运行安装脚本，不会创建多个同名快照
        if snapper -c root list --columns description | grep -Fqx "$MARKER"; then
            log "Snapshot '$MARKER' already exists on [root]."
        else
            log "Creating safety checkpoint on [root]..."
            # 使用默认类型 (single) 创建快照
            # single 表示这是一个独立的存档点，而非 pre/post 对
            snapper -c root create --description "$MARKER"
            success "Root snapshot created."
        fi
    else
        warn "Snapper 'root' config not configured. Skipping root snapshot."
    fi

    # 2. Home 分区快照 (如果存在 home 配置)
    # 如果用户为 home 配置了独立的 Snapper 配置，也创建快照
    if snapper -c home get-config &>/dev/null; then
        if snapper -c home list --columns description | grep -Fqx "$MARKER"; then
            log "Snapshot '$MARKER' already exists on [home]."
        else
            log "Creating safety checkpoint on [home]..."
            snapper -c home create --description "$MARKER"
            success "Home snapshot created."
        fi
    fi
}

# ==============================================================================
# 执行
# ==============================================================================

log "Preparing to create restore point..."
create_checkpoint

log "Module 03c completed."