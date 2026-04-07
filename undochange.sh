#!/bin/bash

# ==============================================================================
# undochange.sh - 统一回滚工具（基于 Btrfs Assistant）
# ==============================================================================
# 用法：
#   sudo ./undochange.sh full
#   sudo ./undochange.sh desktop
#
# 模式：
#   full    -> 回滚到 "Before Daguo Setup"
#   desktop -> 回滚到 "Before Desktop Environments"
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 颜色重置（无颜色）

MODE="${1:-full}"

case "$MODE" in
    full)
        TARGET_DESC="Before Daguo Setup"
        ;;
    desktop)
        TARGET_DESC="Before Desktop Environments"
        ;;
    *)
        echo -e "${RED}Usage: sudo ./undochange.sh [full|desktop]${NC}"
        exit 1
        ;;
esac

# 1. 检查是否为 root（必须以 root 身份运行）
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo ./undochange.sh [full|desktop])${NC}"
    exit 1
fi

# 2. 检查必要依赖（snapper 与 btrfs-assistant）
if ! command -v snapper &> /dev/null; then
    echo -e "${RED}Error: Snapper is not installed.${NC}"
    exit 1
fi

if ! command -v btrfs-assistant &> /dev/null; then
    echo -e "${RED}Error: btrfs-assistant is not installed.${NC}"
    echo "Cannot perform subvolume rollback."
    exit 1
fi

echo -e "${YELLOW}>>> Initializing Emergency Rollback (Target: '$TARGET_DESC')...${NC}"

# --- 辅助函数：回滚逻辑（来源：quickload） ---
# 参数：$1 = 子卷名称（例如 @ 或 @home），$2 = snapper 配置名（例如 root 或 home）
perform_rollback() {
    local subvol="$1"
    local snap_conf="$2"
    
    echo -e "Checking config: ${YELLOW}$snap_conf${NC} for subvolume: ${YELLOW}$subvol${NC}..."
    
    # 1. 获取 Snapper 快照 ID
    # 逻辑：列出快照 -> 根据描述过滤 -> 取最后一个匹配项 -> 获取其编号（ID）
    local snap_id
    snap_id=$(snapper -c "$snap_conf" list --columns number,description | grep -F "$TARGET_DESC" | tail -n 1 | awk '{print $1}')
    
    if [ -z "$snap_id" ]; then
        echo -e "${RED}  [SKIP] Snapshot '$TARGET_DESC' not found in config '$snap_conf'.${NC}"
        return 1
    fi
    
    echo -e "  Found Snapshot ID: ${GREEN}$snap_id${NC}"
    
    # 2. 映射到 btrfs-assistant 的索引（index）
    # 说明：根据子卷名称和 Snapper ID 在 btrfs-assistant 列表中查找对应的索引值
    local ba_index=$(btrfs-assistant -l | awk -v v="$subvol" -v s="$snap_id" '$2==v && $3==s {print $1}')
    
    if [ -z "$ba_index" ]; then
        echo -e "${RED}  [FAIL] Could not map Snapper ID $snap_id to Btrfs-Assistant index.${NC}"
        return 1
    fi
    
    # 3. 执行恢复（调用 btrfs-assistant 执行回滚）
    echo -e "  Executing rollback (Index: $ba_index)..."
    if btrfs-assistant -r "$ba_index"; then
        echo -e "  ${GREEN}Success.${NC}"
        return 0
    else
        echo -e "  ${RED}Restore command failed.${NC}"
        return 1
    fi
}

# --- 主流程 ---

# 3. 回滚根分区（关键步骤）
# 在 Arch 常见布局中，snapper 的 'root' 配置通常对应子卷 '@'
echo -e "${YELLOW}>>> Restoring Root Filesystem...${NC}"
if ! perform_rollback "@" "root"; then
    echo -e "${RED}CRITICAL FAILURE: Failed to restore root partition.${NC}"
    echo "Aborting operation to prevent partial system state."
    exit 1
fi

# 4. 回滚 /home（可选）
# 仅在存在 snapper 配置名为 'home' 时尝试回滚 home 子卷
if snapper list-configs | grep -q "^home "; then
    echo -e "${YELLOW}>>> Restoring Home Filesystem...${NC}"
    # 在 Arch 布局中，snapper 的 'home' 配置通常对应子卷 '@home'
    if ! perform_rollback "@home" "home"; then
        echo -e "${RED}CRITICAL FAILURE: Failed to restore home partition.${NC}"
        echo "Aborting operation to prevent partial system state."
        exit 1
    fi
else
    echo -e "No 'home' snapper config found, skipping home restore."
fi

# 5. 重新启动系统
echo -e "${GREEN}System rollback successful.${NC}"
echo -e "${YELLOW}Rebooting in 3 seconds...${NC}"
sleep 3
reboot
