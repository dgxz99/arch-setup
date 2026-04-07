#!/bin/bash

# ==============================================================================
# 01-btrfs-init.sh - Pre-install Snapshot Safety Net (Root & Home)
# ==============================================================================
# 这是安装流程的第一个模块，负责在系统配置前创建 Btrfs 快照作为安全网

# 主要功能：
#   1. 检测根分区( / )和 home分区( /home )是否为 Btrfs 文件系统
#   2. 安装并配置 Snapper 快照管理工具
#   3. 创建初始快照，以便在安装出错时可以回滚

# Btrfs 快照的优势：
#   - 几乎瞬时创建（使用 CoW 写时复制技术）
#   - 占用空间极小（只存储差异数据）
#   - 可以快速回滚到之前的系统状态

# Snapper 是 openSUSE 开发的快照管理工具，提供：
#   - 自动快照（可配置时间线）
#   - 手动快照管理
#   - 快照清理策略
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 获取脚本所在目录的绝对路径
source "$SCRIPT_DIR/00-utils.sh"                            # 加载工具函数库

# 检查是否以 root 权限运行（快照操作需要 root 权限）
check_root

log "Starting Phase 1: System Snapshot Initialization..."

# 显示阶段标题
section "System Snapshot Initialization"

# ------------------------------------------------------------------------------
# 0. Check Root Filesystem 检查根文件系统是否为 Btrfs
# ------------------------------------------------------------------------------
log "Checking Root filesystem..."
# 使用 findmnt 命令检测根分区的文件系统类型：-n: 不打印表头，-o FSTYPE: 只输出文件系统类型列
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

# 只有 Btrfs 文件系统才支持快照功能
if [ "$ROOT_FSTYPE" != "btrfs" ]; then
    warn "Root filesystem is not Btrfs ($ROOT_FSTYPE detected)."
    log "Skipping Btrfs snapshot initialization entirely."
    exit 0
fi

# ------------------------------------------------------------------------------
# 1. Configure Root (/) 配置根分区的快照功能
# ------------------------------------------------------------------------------
log "Installing Snapper..."
# 安装 snapper（快照管理器）：--needed: 如果已安装则跳过 --noconfirm: 不需要用户确认直接安装
exe pacman -Syu --noconfirm --needed snapper

log "Configuring Snapper for Root..."
# 检查是否已存在名为 "root" 的 snapper 配置
if ! snapper list-configs | grep -q "^root "; then
    # 清理可能存在的 .snapshots 目录，Snapper 需要创建一个同名的子卷来存储快照
    if [ -d "/.snapshots" ]; then
        exe_silent umount /.snapshots
        exe_silent rm -rf /.snapshots
    fi
    
    # 为根分区创建 snapper 配置；-c root: 配置名称为 "root"；create-config /: 为 / 路径创建配置
    if exe snapper -c root create-config /; then
        success "Config 'root' created."
        
        # 设置快照保留策略，控制快照数量防止磁盘空间耗尽
        #   - 允许 wheel 组用户管理快照
        #   - 启用自动时间线快照
        #   - 启用时间线清理
        #   - 普通快照最多保留个数
        #   - 快照没有最小年龄限制
        #   - 重要快照最多保留个数
        #   - 每小时快照保留个数
        #   - 每日快照保留个数
        #   - 不保留每周快照
        #   - 不保留每月快照
        #   - 不保留每年快照
        exe snapper -c root set-config ALLOW_GROUPS="wheel" TIMELINE_CREATE="yes" TIMELINE_CLEANUP="yes" NUMBER_LIMIT="10" NUMBER_MIN_AGE="0" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_LIMIT_HOURLY="3" TIMELINE_LIMIT_DAILY="0" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="0" TIMELINE_LIMIT_YEARLY="0"
    
        # 启用 Snapper 定时器，用于自动创建和清理快照
        exe systemctl enable --now snapper-cleanup.timer
        exe systemctl enable --now snapper-timeline.timer
    fi
fi

# ------------------------------------------------------------------------------
# 2. Configure Home (/home) 配置 /home 分区的快照功能
# ------------------------------------------------------------------------------
# 第二步：配置 /home 分区的快照功能
# 分离 /home 分区是 Linux 的最佳实践：
#   - 系统重装时可以保留用户数据
#   - 可以为用户数据单独设置备份策略
#   - 快照可以帮助恢复误删除的文件

if findmnt -n -o FSTYPE /home | grep -q "btrfs"; then
    log "Configuring Snapper for Home..."
    # 检查是否已存在名为 "home" 的配置
    if ! snapper list-configs | grep -q "^home "; then
        if [ -d "/home/.snapshots" ]; then
            exe_silent umount /home/.snapshots
            exe_silent rm -rf /home/.snapshots
        fi
        # 为 /home 创建 snapper 配置
        if exe snapper -c home create-config /home; then
            success "Config 'home' created."
            # 对 /home 应用相同的保留策略，控制快照数量防止磁盘空间耗尽
            exe snapper -c home set-config ALLOW_GROUPS="wheel" TIMELINE_CREATE="yes" TIMELINE_CLEANUP="yes" NUMBER_MIN_AGE="0" NUMBER_LIMIT="10" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_LIMIT_HOURLY="3" TIMELINE_LIMIT_DAILY="0" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="0" TIMELINE_LIMIT_YEARLY="0"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 3. Create Initial Pristine Snapshot 创建初始快照
# ------------------------------------------------------------------------------
section "Safety Net" "Creating Pristine Initial Snapshots"

# 为根分区创建快照
if snapper list-configs | grep -q "root "; then
    if ! snapper -c root list --columns description | grep -q "Before Daguo Setup"; then
        if exe snapper -c root create --description "Before Daguo Setup"; then
            success "Pristine Root snapshot created."
        else
            error "Failed to create Root snapshot."; exit 1
        fi
    fi
fi

# 为 /home 创建快照（如果存在 home 配置）
if snapper list-configs | grep -q "home "; then
    if ! snapper -c home list --columns description | grep -q "Before Daguo Setup"; then
        if exe snapper -c home create --description "Before Daguo Setup"; then
            success "Pristine Home snapshot created."
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 4. Btrfs Assistants & GRUB Snapshot Integration
# ------------------------------------------------------------------------------
section "Btrfs Snapshot Integration"

log "Installing advanced snapshot management tools..."

# btrfs-assistant: 图形化 Btrfs 快照管理工具，提供更友好的界面来浏览和恢复快照
# xorg-xhost: 允许非 root 用户访问 X 服务器，方便在图形环境下使用 btrfs-assistant
# grub-btrfs: 将 Btrfs 快照集成到 GRUB 菜单，允许在启动时选择快照进行恢复
# inotify-tools: 监控文件系统事件，辅助 grub-btrfs 实时更新 GRUB 菜单
# less: 方便查看日志和配置文件
exe pacman -S --noconfirm --needed btrfs-assistant xorg-xhost grub-btrfs inotify-tools less
success "Btrfs helper tools installed."

if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
    log "Integrating snapshots into GRUB menu..."
    
    # 重新计算 Btrfs 内部的 boot 路径
    SUBVOL_NAME=$(findmnt -n -o OPTIONS / | tr ',' '\n' | grep '^subvol=' | cut -d= -f2)
    if [ "$SUBVOL_NAME" == "/" ] || [ -z "$SUBVOL_NAME" ]; then
        BTRFS_BOOT_PATH="/boot/grub"
    else
        [[ "$SUBVOL_NAME" != /* ]] && SUBVOL_NAME="/${SUBVOL_NAME}"
        BTRFS_BOOT_PATH="${SUBVOL_NAME}/boot/grub"
    fi
    
    # 修改 grub-btrfs 的跨区搜索路径
    if [ -f "/etc/default/grub-btrfs/config" ]; then
        log "Patching grub-btrfs config for Btrfs search path..."
        sed -i "s|^#*GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME=.*|GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME=\"${BTRFS_BOOT_PATH}\"|" /etc/default/grub-btrfs/config
    fi
    
    # 开启监听服务并重新生成菜单（这次菜单里就会多出 Snapshots 选项了！）
    exe systemctl enable --now grub-btrfsd
    log "Regenerating GRUB Config with Snapshot entries..."
    exe grub-mkconfig -o /boot/grub/grub.cfg
    success "GRUB snapshot menu integration completed."
fi

log "Module 01 completed. Pure base system secured."