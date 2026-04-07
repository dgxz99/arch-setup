#!/usr/bin/env bash

# 收尾模块。
#
# 负责：
# - 缓存清理
# - 日志归档
# - 删除状态文件
# - 最终重启倒计时

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root
section 'Phase 99' 'Cleanup and Finalization'

clean_intermediate_snapshots() {
    # 清理中间快照，保留关键标记快照，避免快照数量持续膨胀。
    local config_name="$1"
    local start_marker='Before Daguo Setup'
    local keep_markers=('Before Desktop Environments' 'Before Niri Setup')

    if ! snapper -c "$config_name" list >/dev/null 2>&1; then
        return 0
    fi

    log "Scanning junk snapshots in: $config_name..."

    local start_id
    start_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$start_marker" | awk '{print $1}' | tail -n 1)
    
    if [ -z "$start_id" ]; then
        warn "Marker '$start_marker' not found in '$config_name'. Skipping cleanup."
        return
    fi
    
    local ids_to_keep=()
    for marker in "${keep_markers[@]}"; do
        local found_id
        found_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$marker" | awk '{print $1}' | tail -n 1)
        
        if [ -n "$found_id" ]; then
            ids_to_keep+=("$found_id")
            log "Found protected snapshot: '$marker' (ID: $found_id)"
        fi
    done
    
    local snapshots_to_delete=()

    local line id type skip keep
    # 使用 snapper list --columns number,type，按编号范围筛选待删快照。
    while IFS= read -r line; do
        id=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $2}')
        [[ ! "$id" =~ ^[0-9]+$ ]] && continue
        [[ "$id" -le "$start_id" ]] && continue

        skip=false
        for keep in "${ids_to_keep[@]}"; do
            if [[ "$id" == "$keep" ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == true ]] && continue

        if [[ "$type" == 'pre' || "$type" == 'post' || "$type" == 'single' ]]; then
            snapshots_to_delete+=("$id")
        fi
    done < <(snapper -c "$config_name" list --columns number,type | sed '1,2d')

    if [[ ${#snapshots_to_delete[@]} -gt 0 ]]; then
        log "Deleting ${#snapshots_to_delete[@]} intermediate snapshots in $config_name..."
        exe snapper -c "$config_name" delete "${snapshots_to_delete[@]}" || warn "Failed to delete part of snapshots in $config_name"
    else
        log "No intermediate snapshots to delete in $config_name."
    fi
}

log "Cleaning Pacman/Yay cache..."
# 用 pacman -Sc 做温和清理，保留最近缓存而非全删，兼顾磁盘空间与回滚便利。
exe pacman -Sc --noconfirm || true

# 清理 Pacman 可能残留的下载临时目录。
for dir in /var/cache/pacman/pkg/download-*/; do
    if [[ -d "$dir" ]]; then
        log "Cleaning residual directory: $dir"
        rm -rf "$dir"
    fi
done

# 清理 Btrfs 中间快照。
clean_intermediate_snapshots 'root'
clean_intermediate_snapshots 'home'

detect_target_user

VERIFY_LIST="/tmp/daguo_install_verify.list"
rm -f "$VERIFY_LIST"

# 最后再生成一次 GRUB 配置，确保主题、双系统、快照菜单都被纳入最终配置。
if command -v grub-mkconfig >/dev/null 2>&1; then
    # 清理完成后重建 grub.cfg，确保快照菜单、主题和双系统入口一致。
    exe env LANG=en_US.UTF-8 grub-mkconfig -o /boot/grub/grub.cfg || warn 'grub-mkconfig failed during cleanup.'
fi

log "Module 99 completed."
