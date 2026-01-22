#!/bin/bash

# ==============================================================================
# 07-grub-theme.sh - GRUB Theming & Advanced Configuration
# ==============================================================================
# 模块说明：GRUB 主题和高级配置
# ------------------------------------------------------------------------------
# 此模块用于个性化 GRUB 引导程序的外观和行为
#
# 主要功能：
#   1. 配置 GRUB 记住上次选择的引导项
#   2. 优化内核启动参数 (禁用 watchdog 等)
#   3. 安装自定义 GRUB 主题
#   4. 添加关机/重启菜单项
#   5. 重新生成 GRUB 配置
#
# 包含的主题：
#   - CyberGRUB-2077: 赛博朋克风格
#   - crossgrub: 简洁像素风格
#   - minegrub: Minecraft 风格
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# ------------------------------------------------------------------------------
# 0. Pre-check: Is GRUB installed?
# ------------------------------------------------------------------------------
# 第零步：检查 GRUB 是否已安装
# 如果系统使用其他引导程序 (如 systemd-boot)，则跳过

if ! command -v grub-mkconfig >/dev/null 2>&1; then
    echo ""
    warn "GRUB (grub-mkconfig) not found on this system."
    log "Skipping GRUB theme installation."
    exit 0
fi

section "Phase 7" "GRUB Customization & Theming"

# --- Helper Functions (Moved from 02a) ---
# 辅助函数 (从 02a 移植)

# set_grub_value - 设置 GRUB 配置的键值对
# 参数: $1=键名, $2=值
# 处理三种情况: 被注释、已存在、不存在
set_grub_value() {
    local key="$1"
    local value="$2"
    local conf_file="/etc/default/grub"
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's,[\/&],\\&,g')

    if grep -q -E "^#\s*$key=" "$conf_file"; then
        # 取消注释并设置新值
        exe sed -i -E "s,^#\s*$key=.*,$key=\"$escaped_value\"," "$conf_file"
    elif grep -q -E "^$key=" "$conf_file"; then
        # 修改现有值
        exe sed -i -E "s,^$key=.*,$key=\"$escaped_value\"," "$conf_file"
    else
        # 添加新配置
        log "Appending new key: $key"
        echo "$key=\"$escaped_value\"" >> "$conf_file"
    fi
}

# manage_kernel_param - 管理内核启动参数
# 参数: $1=操作(add/remove), $2=参数
# 用于添加或移除 GRUB_CMDLINE_LINUX_DEFAULT 中的参数
manage_kernel_param() {
    local action="$1"
    local param="$2"
    local conf_file="/etc/default/grub"
    local line
    line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$conf_file")
    local params
    params=$(echo "$line" | sed -e 's/GRUB_CMDLINE_LINUX_DEFAULT=//' -e 's/"//g')
    local param_key
    # 提取参数键 (如 loglevel=5 的 loglevel)
    if [[ "$param" == *"="* ]]; then param_key="${param%%=*}"; else param_key="$param"; fi
    # 先移除已有的同名参数
    params=$(echo "$params" | sed -E "s/\b${param_key}(=[^ ]*)?\b//g")

    # 如果是添加操作，则追加参数
    if [ "$action" == "add" ]; then params="$params $param"; fi

    # 清理多余空格
    params=$(echo "$params" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    exe sed -i "s,^GRUB_CMDLINE_LINUX_DEFAULT=.*,GRUB_CMDLINE_LINUX_DEFAULT=\"$params\"," "$conf_file"
}

# ------------------------------------------------------------------------------
# 1. Advanced GRUB Configuration (Moved from 02a)
# ------------------------------------------------------------------------------
# 第一步：高级 GRUB 配置
# 配置 GRUB 的默认行为和内核参数

section "Step 1/5" "General GRUB Settings"

# 启用 GRUB 记住上次选择的引导项
# 对于双系统用户很有用
log "Enabling GRUB to remember the last selected entry..."
set_grub_value "GRUB_DEFAULT" "saved"
set_grub_value "GRUB_SAVEDEFAULT" "true"

# 配置内核启动参数
# 移除 quiet 和 splash 以显示详细启动信息
# loglevel=5: 显示更多内核日志
# nowatchdog: 禁用看门狗，加快启动速度
log "Configuring kernel boot parameters for detailed logs and performance..."
manage_kernel_param "remove" "quiet"
manage_kernel_param "remove" "splash"
manage_kernel_param "add" "loglevel=5"
manage_kernel_param "add" "nowatchdog"

# CPU Watchdog 禁用逻辑
# 根据 CPU 厂商黑名单相应的 watchdog 模块
CPU_VENDOR=$(LC_ALL=C lscpu | grep "Vendor ID:" | awk '{print $3}')
if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
    log "Intel CPU detected. Disabling iTCO_wdt watchdog."
    manage_kernel_param "add" "modprobe.blacklist=iTCO_wdt"
elif [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
    log "AMD CPU detected. Disabling sp5100_tco watchdog."
    manage_kernel_param "add" "modprobe.blacklist=sp5100_tco"
fi

success "Kernel parameters updated."

# ------------------------------------------------------------------------------
# 2. Detect Themes
# ------------------------------------------------------------------------------
# 第二步：检测可用主题
# 扫描 grub-themes 目录中的有效主题

section "Step 2/5" "Theme Detection"
log "Scanning for themes in 'grub-themes' folder..."

SOURCE_BASE="$PARENT_DIR/grub-themes"
DEST_DIR="/boot/grub/themes"

if [ ! -d "$SOURCE_BASE" ]; then
    warn "Directory 'grub-themes' not found in repo."
    exit 0
fi

# 查找所有包含 theme.txt 的目录
mapfile -t FOUND_DIRS < <(find "$SOURCE_BASE" -mindepth 1 -maxdepth 1 -type d | sort)
THEME_PATHS=()
THEME_NAMES=()

for dir in "${FOUND_DIRS[@]}"; do
    if [ -f "$dir/theme.txt" ]; then
        THEME_PATHS+=("$dir")
        THEME_NAMES+=("$(basename "$dir")")
    fi
done

if [ ${#THEME_NAMES[@]} -eq 0 ]; then
    warn "No valid theme folders found."
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Select Theme (TUI Menu)
# ------------------------------------------------------------------------------
# 第三步：选择主题 (TUI 菜单)
# 用户可以从检测到的主题中选择一个
# 60 秒超时默认选择第一个

section "Step 3/5" "Theme Selection"

if [ ${#THEME_NAMES[@]} -eq 1 ]; then
    # 只有一个主题，自动选择
    SELECTED_INDEX=0
    log "Only one theme detected. Auto-selecting: ${THEME_NAMES[0]}"
else
    # 计算菜单宽度并渲染
    TITLE_TEXT="Select GRUB Theme (60s Timeout)"
    MAX_LEN=${#TITLE_TEXT}
    for name in "${THEME_NAMES[@]}"; do
        ITEM_LEN=$((${#name} + 20))
        if (( ITEM_LEN > MAX_LEN )); then MAX_LEN=$ITEM_LEN; fi
    done
    MENU_WIDTH=$((MAX_LEN + 4))
    
    # 绘制菜单边框
    LINE_STR=""; printf -v LINE_STR "%*s" "$MENU_WIDTH" ""; LINE_STR=${LINE_STR// /─}

    echo -e "\n${H_PURPLE}╭${LINE_STR}╮${NC}"
    TITLE_PADDING_LEN=$(( (MENU_WIDTH - ${#TITLE_TEXT}) / 2 ))
    RIGHT_PADDING_LEN=$((MENU_WIDTH - ${#TITLE_TEXT} - TITLE_PADDING_LEN))
    T_PAD_L=""; printf -v T_PAD_L "%*s" "$TITLE_PADDING_LEN" ""
    T_PAD_R=""; printf -v T_PAD_R "%*s" "$RIGHT_PADDING_LEN" ""
    echo -e "${H_PURPLE}│${NC}${T_PAD_L}${BOLD}${TITLE_TEXT}${NC}${T_PAD_R}${H_PURPLE}│${NC}"
    echo -e "${H_PURPLE}├${LINE_STR}┤${NC}"

    # 显示主题选项
    for i in "${!THEME_NAMES[@]}"; do
        NAME="${THEME_NAMES[$i]}"
        DISPLAY_IDX=$((i+1))
        if [ "$i" -eq 0 ]; then
            COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${NAME} - ${H_GREEN}Default${NC}"
            RAW_STR=" [$DISPLAY_IDX] $NAME - Default"
        else
            COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${NAME}"
            RAW_STR=" [$DISPLAY_IDX] $NAME"
        fi
        PADDING=$((MENU_WIDTH - ${#RAW_STR}))
        PAD_STR=""; if [ "$PADDING" -gt 0 ]; then printf -v PAD_STR "%*s" "$PADDING" ""; fi
        echo -e "${H_PURPLE}│${NC}${COLOR_STR}${PAD_STR}${H_PURPLE}│${NC}"
    done
    echo -e "${H_PURPLE}╰${LINE_STR}╯${NC}\n"

    # 读取用户输入
    echo -ne "   ${H_YELLOW}Enter choice [1-${#THEME_NAMES[@]}]: ${NC}"
    read -t 60 USER_CHOICE
    if [ -z "$USER_CHOICE" ]; then echo ""; fi
    USER_CHOICE=${USER_CHOICE:-1}

    # 验证输入
    if ! [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 1 ] || [ "$USER_CHOICE" -gt "${#THEME_NAMES[@]}" ]; then
        log "Invalid choice or timeout. Defaulting to first option..."
        SELECTED_INDEX=0
    else
        SELECTED_INDEX=$((USER_CHOICE-1))
    fi
fi

THEME_SOURCE="${THEME_PATHS[$SELECTED_INDEX]}"
THEME_NAME="${THEME_NAMES[$SELECTED_INDEX]}"
info_kv "Selected" "$THEME_NAME"

# ------------------------------------------------------------------------------
# 4. Install & Configure Theme
# ------------------------------------------------------------------------------
# 第四步：安装和配置主题
# 复制主题文件到 /boot/grub/themes 并更新 GRUB 配置

section "Step 4/5" "Theme Installation"

# 确保目标目录存在
if [ ! -d "$DEST_DIR" ]; then exe mkdir -p "$DEST_DIR"; fi
# 删除已有的同名主题
if [ -d "$DEST_DIR/$THEME_NAME" ]; then
    log "Removing existing version..."
    exe rm -rf "$DEST_DIR/$THEME_NAME"
fi

# 复制主题文件
exe cp -r "$THEME_SOURCE" "$DEST_DIR/"

if [ -f "$DEST_DIR/$THEME_NAME/theme.txt" ]; then
    success "Theme installed."
else
    error "Failed to copy theme files."
    exit 1
fi

# 配置 GRUB 使用主题
GRUB_CONF="/etc/default/grub"
THEME_PATH="$DEST_DIR/$THEME_NAME/theme.txt"

if [ -f "$GRUB_CONF" ]; then
    # 设置 GRUB_THEME 变量
    if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
        exe sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
    elif grep -q "^#GRUB_THEME=" "$GRUB_CONF"; then
        exe sed -i "s|^#GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
    else
        echo "GRUB_THEME=\"$THEME_PATH\"" >> "$GRUB_CONF"
    fi
    
    # 注释掉控制台输出 (否则主题不生效)
    if grep -q "^GRUB_TERMINAL_OUTPUT=\"console\"" "$GRUB_CONF"; then
        exe sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_CONF"
    fi
    # 确保图形模式已配置
    if ! grep -q "^GRUB_GFXMODE=" "$GRUB_CONF"; then
        echo 'GRUB_GFXMODE=auto' >> "$GRUB_CONF"
    fi
    success "Configured GRUB to use theme."
else
    error "$GRUB_CONF not found."
    exit 1
fi

# ------------------------------------------------------------------------------
# 5. Add Shutdown/Reboot Menu Entries
# ------------------------------------------------------------------------------
# 第五步：添加关机/重启菜单项
# 在 GRUB 菜单中添加快捷的电源选项

section "Step 5/5" "Menu Entries & Apply"
log "Adding Power Options to GRUB menu..."

# 复制自定义菜单模板
cp /etc/grub.d/40_custom /etc/grub.d/99_custom
# 添加重启和关机选项
echo 'menuentry "Reboot"' {reboot} >> /etc/grub.d/99_custom
echo 'menuentry "Shutdown"' {halt} >> /etc/grub.d/99_custom

success "Added grub menuentry 99-shutdown"
# ------------------------------------------------------------------------------
# 6. Apply Changes
# ------------------------------------------------------------------------------
# 第六步：应用更改
# 重新生成 GRUB 配置文件

log "Generating new GRUB configuration..."

if exe grub-mkconfig -o /boot/grub/grub.cfg; then
    success "GRUB updated successfully."
else
    error "Failed to update GRUB."
    warn "You may need to run 'grub-mkconfig' manually."
fi

log "Module 07 completed."