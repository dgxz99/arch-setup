#!/bin/bash

# ==============================================================================
# 02-init-boot-btrfs.sh - Pre-install Snapshot Safety Net (Root & Home)
# ==============================================================================
# 这是安装流程的第二个模块，负责在系统配置前创建 Btrfs 快照作为安全网

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

log "Starting Phase 2: System Snapshot Initialization..."

# 显示阶段标题
section "System Snapshot Initialization"

# ------------------------------------------------------------------------------
# 启动模式修正工具函数
# ------------------------------------------------------------------------------
# 为了保证 Btrfs 快照回滚时内核、initramfs 与 root 子卷尽量保持一致
# 这里统一将 UKI 路线切回传统的 /boot/vmlinuz + /boot/initramfs-*.img

# 处理配置文件的备份和恢复，确保修改前有干净的备份可用
restore_config_from_backup() {
    local file_path="$1"
    local backup_path="$2"
    local label="$3"

    if [ ! -f "$file_path" ]; then
        warn "$label not found at $file_path"
        return 1
    fi

    if [ ! -f "$backup_path" ]; then
        log "Backing up $label to $backup_path ..."
        exe cp "$file_path" "$backup_path" || return 2
        success "Original $label backed up."
    fi

    log "Restoring clean $label from backup before patching..."
    exe cp "$backup_path" "$file_path" || return 2
    return 0
}

# 将 mkinitcpio preset 从 UKI 输出切换回传统 initramfs 输出
convert_mkinitcpio_preset_to_initramfs() {
    local preset_path="$1"
    local preset_name
    local preset_backup

    preset_name="$(basename "$preset_path" .preset)"
    preset_backup="${preset_path}.bak"

    restore_config_from_backup "$preset_path" "$preset_backup" "${preset_name}.preset"
    case $? in
        1) return 0 ;;
        2) return 1 ;;
    esac

    log "Switching ${preset_name}.preset from UKI to initramfs images..."
    exe sed -i -E \
        -e "s|^PRESETS=.*|PRESETS=('default')|" \
        -e 's|^[[:space:]]*#?[[:space:]]*(default_uki=)|#\1|' \
        -e 's|^[[:space:]]*#?[[:space:]]*(fallback_uki=)|#\1|' \
        -e 's|^[[:space:]]*#?[[:space:]]*(fallback_config=)|#\1|' \
        -e 's|^[[:space:]]*#?[[:space:]]*(fallback_image=)|#\1|' \
        -e 's|^[[:space:]]*#?[[:space:]]*(fallback_options=)|#\1|' \
        "$preset_path" || return 1

    if grep -qE '^[[:space:]]*#?[[:space:]]*default_image=' "$preset_path"; then
        exe sed -i -E "s|^[[:space:]]*#?[[:space:]]*default_image=.*|default_image=\"/boot/initramfs-${preset_name}.img\"|" "$preset_path" || return 1
    else
        echo "default_image=\"/boot/initramfs-${preset_name}.img\"" >> "$preset_path"
    fi

    exe sed -i -E 's|^[[:space:]]*#?[[:space:]]*(default_options=)|#\1|' "$preset_path" || return 1

    success "${preset_name}.preset switched to initramfs outputs."
}

# 禁用 GRUB 的 UKI 生成器，避免重复的 UKI 条目干扰快照回滚
disable_uki_generator() {
    local uki_script="/etc/grub.d/15_uki"
    local uki_backup="/etc/grub.d/15_uki.bak"

    if [ ! -e "$uki_script" ]; then
        log "15_uki not present. Skipping UKI generator handling."
        return 0
    fi

    if [ ! -f "$uki_script" ]; then
        warn "$uki_script exists but is not a regular file. Skipping."
        return 0
    fi

    if [ ! -f "$uki_backup" ]; then
        log "Backing up 15_uki to $uki_backup ..."
        exe cp "$uki_script" "$uki_backup" || return 1
        success "Original 15_uki backed up."
    fi

    exe chmod -x "$uki_backup" || return 1

    if [ -x "$uki_script" ]; then
        log "Disabling executable bit on 15_uki to avoid duplicate UKI entries..."
        exe chmod -x "$uki_script" || return 1
        success "15_uki disabled."
    else
        log "15_uki already disabled."
    fi
}

# 禁用 kernel-install 的 UKI 模式，确保内核安装后不会自动生成 UKI 条目
disable_kernel_install_uki_mode() {
    local install_conf="/etc/kernel/install.conf"
    local install_backup="/etc/kernel/install.conf.bak"

    if [ ! -f "$install_conf" ]; then
        log "kernel-install config not present. Skipping."
        return 0
    fi

    restore_config_from_backup "$install_conf" "$install_backup" "kernel-install config"
    case $? in
        1) return 0 ;;
        2) return 1 ;;
    esac

    log "Disabling kernel-install UKI mode..."
    exe sed -i -E \
        -e 's|^[[:space:]]*(layout=uki)|#\1|' \
        -e 's|^[[:space:]]*(uki_generator=.*)|#\1|' \
        "$install_conf" || return 1

    success "kernel-install UKI mode disabled."
}

# 移除旧的 UKI 包
remove_uki_bundles() {
    local uki_dir="/efi/EFI/Linux"
    local found_any=false

    if [ ! -d "$uki_dir" ]; then
        log "UKI directory $uki_dir not present. Skipping cleanup."
        return 0
    fi

    while IFS= read -r uki_file; do
        [ -z "$uki_file" ] && continue
        found_any=true
        log "Removing obsolete UKI bundle: $uki_file"
        exe rm -f "$uki_file" || return 1
    done < <(find "$uki_dir" -maxdepth 1 -type f -name '*.efi' | sort)

    if [ "$found_any" = true ]; then
        success "Removed UKI bundles from $uki_dir."
    else
        log "No UKI bundles found under $uki_dir."
    fi
}

# 确保引导模式与快照兼容
ensure_snapshot_compatible_boot_mode() {
    local switched_any=false
    local initramfs_present=false

    section "Boot Mode Preparation" "Switching UKI systems to snapshot-compatible initramfs boot"

    if [ ! -d "/etc/mkinitcpio.d" ]; then
        warn "/etc/mkinitcpio.d not found. Skipping boot mode conversion."
        return 0
    fi

    mapfile -t PRESET_FILES < <(find /etc/mkinitcpio.d -maxdepth 1 -type f -name '*.preset' | sort)
    if [ ${#PRESET_FILES[@]} -eq 0 ]; then
        warn "No mkinitcpio preset files found. Skipping boot mode conversion."
        return 0
    fi

    for preset_path in "${PRESET_FILES[@]}"; do
        if grep -qE '^[[:space:]]*[[:alnum:]_]+_uki=' "$preset_path"; then
            convert_mkinitcpio_preset_to_initramfs "$preset_path" || exit 1
            switched_any=true
        fi
    done

    if [ -f "/etc/kernel/install.conf" ] && grep -qE '^[[:space:]]*(layout=uki|uki_generator=)' /etc/kernel/install.conf; then
        disable_kernel_install_uki_mode || exit 1
        switched_any=true
    fi

    if compgen -G "/boot/initramfs-*.img" > /dev/null; then
        initramfs_present=true
    fi

    if [ "$switched_any" = true ] || [ "$initramfs_present" = false ]; then
        log "Regenerating initramfs images for traditional boot flow..."
        exe mkinitcpio -P || exit 1
        success "Initramfs images regenerated."
    else
        log "Traditional initramfs images already present. Skipping mkinitcpio regeneration."
    fi

    disable_uki_generator || exit 1
    remove_uki_bundles || exit 1
    success "Snapshot-compatible boot mode is ready."
}

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
# 3. Prepare Snapshot-Compatible Boot Mode
# ------------------------------------------------------------------------------
ensure_snapshot_compatible_boot_mode

# ------------------------------------------------------------------------------
# 4. Create Initial Pristine Snapshot 创建初始快照
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
# 5. Btrfs Assistants & GRUB Snapshot Integration
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

log "Module 02 completed. Pure base system secured."
