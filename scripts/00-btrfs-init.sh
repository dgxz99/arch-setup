#!/bin/bash

# ==============================================================================
# 00-btrfs-init.sh - Pre-install Snapshot Safety Net (Root & Home)
# ==============================================================================
# 这是安装流程的第一个模块，负责在系统配置前创建 Btrfs 快照作为安全网
# 
# 主要功能：
#   1. 检测根分区( / )和 home分区( /home )是否为 Btrfs 文件系统
#   2. 安装并配置 Snapper 快照管理工具
#   3. 创建初始快照，以便在安装出错时可以回滚
#
# Btrfs 快照的优势：
#   - 几乎瞬时创建（使用 CoW 写时复制技术）
#   - 占用空间极小（只存储差异数据）
#   - 可以快速回滚到之前的系统状态
#
# Snapper 是 openSUSE 开发的快照管理工具，提供：
#   - 自动快照（可配置时间线）
#   - 手动快照管理
#   - 快照清理策略
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 获取脚本所在目录的绝对路径
source "$SCRIPT_DIR/00-utils.sh"                            # 加载工具函数库

# 检查是否以 root 权限运行（快照操作需要 root 权限）
check_root

# 显示阶段标题
section "Phase 0" "System Snapshot Initialization"

# ------------------------------------------------------------------------------
# 1. Configure Root (/)
# ------------------------------------------------------------------------------
# 第一步：配置根分区的快照功能

log "Checking Root filesystem..."
# 使用 findmnt 命令检测根分区的文件系统类型
# -n: 不打印表头
# -o FSTYPE: 只输出文件系统类型列
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

# 只有 Btrfs 文件系统才支持快照功能
if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Root is Btrfs. Installing Snapper..."
    # 安装 snapper（快照管理器）和 less（用于查看快照列表）
    # --needed: 如果已安装则跳过
    exe pacman -Syu --noconfirm --needed snapper less
    
    log "Configuring Snapper for Root..."
    # 检查是否已存在名为 "root" 的 snapper 配置
    if ! snapper list-configs | grep -q "^root "; then
        # 清理可能存在的 .snapshots 目录
        # Snapper 需要创建一个同名的子卷来存储快照
        if [ -d "/.snapshots" ]; then
            exe_silent umount /.snapshots
            exe_silent rm -rf /.snapshots
        fi
        
        # 为根分区创建 snapper 配置
        # -c root: 配置名称为 "root"
        # create-config /: 为 / 路径创建配置
        if exe snapper -c root create-config /; then
            success "Config 'root' created."
            
            # Apply Retention Policy
            # 设置快照保留策略，控制快照数量防止磁盘空间耗尽
            exe snapper -c root set-config \
                ALLOW_GROUPS="wheel" \                  # 允许 wheel 组用户管理快照
                TIMELINE_CREATE="no" \                  # 禁用自动时间线快照（节省空间）
                TIMELINE_CLEANUP="yes" \                # 启用时间线清理
                NUMBER_LIMIT="20" \                     # 普通快照最多保留 20 个
                NUMBER_LIMIT_IMPORTANT="5" \            # 重要快照最多保留 5 个
                TIMELINE_LIMIT_HOURLY="5" \             # 每小时快照保留 5 个
                TIMELINE_LIMIT_DAILY="7" \              # 每日快照保留 7 个
                TIMELINE_LIMIT_WEEKLY="0" \             # 不保留每周快照
                TIMELINE_LIMIT_MONTHLY="0" \            # 不保留每月快照
                TIMELINE_LIMIT_YEARLY="0"               # 不保留每年快照
        fi
    else
        log "Config 'root' already exists."
    fi
else
    # 如果不是 Btrfs，则跳过快照配置
    # 其他文件系统（如 ext4、xfs）不支持原生快照
    warn "Root is not Btrfs. Skipping Root snapshot."
fi

# ------------------------------------------------------------------------------
# 2. Configure Home (/home)
# ------------------------------------------------------------------------------
# 第二步：配置 /home 分区的快照功能
# 分离 /home 分区是 Linux 的最佳实践：
#   - 系统重装时可以保留用户数据
#   - 可以为用户数据单独设置备份策略
#   - 快照可以帮助恢复误删除的文件

log "Checking Home filesystem..."

# Check if /home is a mountpoint and is btrfs
# 检查 /home 是否是独立的 Btrfs 挂载点
# 有些安装方式会将 /home 作为根分区的一个子目录而非独立分区
if findmnt -n -o FSTYPE /home | grep -q "btrfs"; then
    log "Home is Btrfs. Configuring Snapper for Home..."
    
    # 检查是否已存在名为 "home" 的配置
    if ! snapper list-configs | grep -q "^home "; then
        # Cleanup .snapshots in home if exists
        # 清理可能存在的 .snapshots 目录
        if [ -d "/home/.snapshots" ]; then
            exe_silent umount /home/.snapshots
            exe_silent rm -rf /home/.snapshots
        fi
        
        # 为 /home 创建 snapper 配置
        if exe snapper -c home create-config /home; then
            success "Config 'home' created."
            
            # Apply same policy to home
            # 对 /home 应用相同的保留策略
            exe snapper -c home set-config \
                ALLOW_GROUPS="wheel" \
                TIMELINE_CREATE="no" \
                TIMELINE_CLEANUP="yes" \
                NUMBER_LIMIT="20" \
                NUMBER_LIMIT_IMPORTANT="5" \
                TIMELINE_LIMIT_HOURLY="5" \
                TIMELINE_LIMIT_DAILY="7" \
                TIMELINE_LIMIT_WEEKLY="0" \
                TIMELINE_LIMIT_MONTHLY="0" \
                TIMELINE_LIMIT_YEARLY="0"
        fi
    else
        log "Config 'home' already exists."
    fi
else
    # /home 不是独立的 Btrfs 分区，可能是：
    # 1. 根分区下的普通目录
    # 2. 其他文件系统（ext4 等）
    log "/home is not a separate Btrfs volume. Skipping."
fi

# ------------------------------------------------------------------------------
# 3. Create Initial Safety Snapshots
# ------------------------------------------------------------------------------
# 第三步：创建安装前的安全快照
# 这是整个安装过程的"安全网"——如果后续步骤出现问题，可以回滚到这个点
# 快照描述 "Before Shorin Setup" 会被 install.sh 中的清理函数识别

section "Safety Net" "Creating Initial Snapshots"

# Snapshot Root
# 为根分区创建快照
if snapper list-configs | grep -q "root "; then
    # 检查是否已存在同名描述的快照（支持断点续传，避免重复创建）
    if snapper -c root list --columns description | grep -q "Before Shorin Setup"; then
        log "Snapshot already created."
    else
        log "Creating Root snapshot..."
        # snapper create: 创建新快照
        # --description: 为快照添加可读的描述信息
        if exe snapper -c root create --description "Before Shorin Setup"; then
            success "Root snapshot created."
        else
            error "Failed to create Root snapshot."
            # 根分区快照是必需的，没有它就无法安全回滚
            warn "Cannot proceed without a safety snapshot. Aborting."
            exit 1
        fi
    fi
fi

# Snapshot Home
# 为 /home 分区创建快照
if snapper list-configs | grep -q "home "; then
    if snapper -c home list --columns description | grep -q "Before Shorin Setup"; then
        log "Snapshot already created."
    else
        log "Creating Home snapshot..."
        if exe snapper -c home create --description "Before Shorin Setup"; then
            success "Home snapshot created."
        else
            error "Failed to create Home snapshot."
            # This is less critical than root, but should still be a failure.
            # /home 快照虽然没有根分区那么关键，但为了数据安全仍然终止
            exit 1
        fi
    fi
fi

# 模块完成，系统现在有了安全快照，可以继续后续的安装步骤
log "Module 00 completed. Safe to proceed."