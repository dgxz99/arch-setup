#!/bin/bash

# ==============================================================================
# 82-grub-theme.sh - GRUB Theming & Advanced Configuration
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

detect_grub_output_path() {
    if [ -d /boot/grub ]; then
        echo "/boot/grub/grub.cfg"
        return 0
    fi

    if [ -d /efi/grub ]; then
        echo "/efi/grub/grub.cfg"
        return 0
    fi

    return 1
}

if ! GRUB_OUTPUT="$(detect_grub_output_path)"; then
    echo ""
    warn "No supported GRUB directory found under /boot/grub or /efi/grub."
    log "Skipping GRUB theme installation."
    exit 0
fi

GRUB_DIR="$(dirname "$GRUB_OUTPUT")"

section "Phase 82" "GRUB Customization & Theming"

# --- Helper Functions ---

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

# cleanup_grub_theme - 清理旧的 GRUB 主题残留
cleanup_grub_theme() {
    local minegrub_found=false
    
    if [ -f "/etc/grub.d/05_twomenus" ] || [ -f "/boot/grub/mainmenu.cfg" ] || [ -f "/efi/grub/mainmenu.cfg" ]; then
        minegrub_found=true
        log "Found Minegrub artifacts. Cleaning up..."
        [ -f "/etc/grub.d/05_twomenus" ] && exe rm -f /etc/grub.d/05_twomenus
        [ -f "/boot/grub/mainmenu.cfg" ] && exe rm -f /boot/grub/mainmenu.cfg
        [ -f "/efi/grub/mainmenu.cfg" ] && exe rm -f /efi/grub/mainmenu.cfg
    fi
    
    if command -v grub-editenv >/dev/null 2>&1; then
        if grub-editenv - list 2>/dev/null | grep -q "^config_file="; then
            minegrub_found=true
            log "Unsetting Minegrub GRUB environment variable..."
            exe grub-editenv - unset config_file
        fi
    fi
    
    if [ "$minegrub_found" == "true" ]; then
        success "Minegrub double-menu configuration completely removed."
    fi
}

patch_grub_linux_titles() {
    local grub_linux="/etc/grub.d/10_linux"
    local grub_linux_bak="/etc/grub.d/10_linux.archsetup.bak"

    if [ ! -f "$grub_linux" ]; then
        warn "GRUB linux generator not found at $grub_linux"
        return 0
    fi

    if [ ! -f "$grub_linux_bak" ]; then
        log "Backing up original 10_linux to $grub_linux_bak ..."
        exe cp "$grub_linux" "$grub_linux_bak" || return 1
        success "Original 10_linux backed up."
    fi

    log "Restoring clean 10_linux from backup before patching..."
    exe cp "$grub_linux_bak" "$grub_linux" || return 1

    log "Patching 10_linux titles to include kernel names..."
    if ! perl -0pi -e '
        s/title="\$\(gettext_printf "%s, with Linux %s \(booster initramfs\)" "\$\{os\}" "\$\{version\}"\)"/title="\$(gettext_printf "%s (%s, booster initramfs)" "\${os}" "\${version}")"/g;
        s/title="\$\(gettext_printf "%s, with Linux %s \(fallback initramfs\)" "\$\{os\}" "\$\{version\}"\)"/title="\$(gettext_printf "%s (%s, fallback initramfs)" "\${os}" "\${version}")"/g;
        s/title="\$\(gettext_printf "%s, with Linux %s \(recovery mode\)" "\$\{os\}" "\$\{version\}"\)"/title="\$(gettext_printf "%s (%s, recovery mode)" "\${os}" "\${version}")"/g;
        s/title="\$\(gettext_printf "%s, with Linux %s" "\$\{os\}" "\$\{version\}"\)"/title="\$(gettext_printf "%s (%s)" "\${os}" "\${version}")"/g;
        s/echo "menuentry '\''\$\(echo "\$os" \| grub_quote\)'\'' \$\{CLASS\} \\\$menuentry_id_option '\''gnulinux-simple-\$boot_device_id'\'' \{" \| sed "s\/\^\/\$submenu_indentation\/"/simple_title="\$(gettext_printf "%s (%s)" "\${os}" "\${version}")"\n      echo "menuentry '\''\$(echo "\$simple_title" | grub_quote)'\'' \${CLASS} \\\$menuentry_id_option '\''gnulinux-simple-\$boot_device_id'\'' \{" | sed "s\/^\/\$submenu_indentation\/"/g;
    ' "$grub_linux"; then
        error "Failed to patch $grub_linux"
        return 1
    fi

    exe chmod 755 "$grub_linux" || return 1
    success "10_linux title patch applied."
}

write_power_entries() {
    local custom_file="/etc/grub.d/99_custom"

    if [ -f "$custom_file" ]; then
        exe rm -f "$custom_file"
    fi

cat <<'EOF' > "$custom_file"
#!/bin/sh
exec tail -n +3 $0

menuentry "Reboot" --class restart {
    reboot
}

menuentry "Shutdown" --class shutdown {
    halt
}
EOF

    exe chmod 755 "$custom_file"
}

# ------------------------------------------------------------------------------
# 1. Advanced GRUB Configuration
# ------------------------------------------------------------------------------
# 第一步：高级 GRUB 配置
# 配置 GRUB 的默认行为和内核参数
section "Step 1/6" "General GRUB Settings"

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
# 2. Sync Themes to System
# ------------------------------------------------------------------------------
# 第二步：同步主题到系统目录
# 扫描 resources/grub-themes 目录中的有效主题
section "Step 2/6" "Sync Themes to System Directory"

SOURCE_BASE="$PARENT_DIR/resources/grub-themes"
DEST_DIR="/usr/share/grub/themes"

# 确保目标目录存在
if [ ! -d "$DEST_DIR" ]; then
    exe mkdir -p "$DEST_DIR"
fi

# 从源目录复制主题到系统目录
if [ -d "$SOURCE_BASE" ]; then
    log "Syncing repository themes to $DEST_DIR..."
    for dir in "$SOURCE_BASE"/*; do
        if [ -d "$dir" ] && [ -f "$dir/theme.txt" ]; then
            THEME_BASENAME=$(basename "$dir")
            log "Installing $THEME_BASENAME to system..."
            # 如果系统中已存在同名主题，先删除再复制，确保更新到最新版本
            [ -d "$DEST_DIR/$THEME_BASENAME" ] && exe rm -rf "$DEST_DIR/$THEME_BASENAME"
            exe cp -r "$dir" "$DEST_DIR/"
        fi
    done
    success "Local themes installed to $DEST_DIR."
else
    warn "Directory 'resources/grub-themes' not found in repo. Only existing system themes available."
fi

log "Scanning $DEST_DIR for available themes..."
THEME_PATHS=()
THEME_NAMES=()

# 直接扫描这个干净的系统级目录，无需任何额外处理
mapfile -t FOUND_DIRS < <(find "$DEST_DIR" -mindepth 1 -maxdepth 1 -type d | sort 2>/dev/null || true)

for dir in "${FOUND_DIRS[@]:-}"; do
    if [ -n "$dir" ] && [ -f "$dir/theme.txt" ]; then
        DIR_NAME=$(basename "$dir")
        THEME_PATHS+=("$dir")
        THEME_NAMES+=("$DIR_NAME")
    fi
done

if [ ${#THEME_NAMES[@]} -eq 0 ]; then
    log "No valid local theme folders found."
fi

# ------------------------------------------------------------------------------
# 3. Select Theme (TUI Menu)
# ------------------------------------------------------------------------------
# 第三步：选择主题 (TUI 菜单)
# 用户可以从检测到的主题中选择一个，或者跳过主题安装
section "Step 3/6" "Theme Selection"

SKIP_THEME=false
SKIP_OPTION_NAME="No theme (Skip/Clear)"
SKIP_IDX=$((${#THEME_NAMES[@]} + 1))

TITLE_TEXT="Select GRUB Theme (60s Timeout)"
LINE_STR="───────────────────────────────────────────────────────"

echo -e "\n${H_PURPLE}╭${LINE_STR}${NC}"
echo -e "${H_PURPLE}│${NC}   ${BOLD}${TITLE_TEXT}${NC}"
echo -e "${H_PURPLE}├${LINE_STR}${NC}"

for i in "${!THEME_NAMES[@]}"; do
    NAME="${THEME_NAMES[$i]}"
    DISPLAY_NAME=$(echo "$NAME" | sed -E 's/^[0-9]+//')
    DISPLAY_IDX=$((i+1))
    
    if [ "$i" -eq 0 ]; then
        COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${DISPLAY_NAME} - ${H_GREEN}Default${NC}"
    else
        COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${DISPLAY_NAME}"
    fi
    echo -e "${H_PURPLE}│${NC} ${COLOR_STR}"
done

SKIP_COLOR_STR=" ${H_CYAN}[$SKIP_IDX]${NC} ${H_YELLOW}${SKIP_OPTION_NAME}${NC}"
echo -e "${H_PURPLE}│${NC} ${SKIP_COLOR_STR}"

echo -e "${H_PURPLE}╰${LINE_STR}${NC}\n"

echo -ne "   ${H_YELLOW}Enter choice [1-$SKIP_IDX]: ${NC}"
read -t 60 USER_CHOICE || true
if [ -z "${USER_CHOICE:-}" ]; then echo ""; fi
USER_CHOICE=${USER_CHOICE:-1}

if ! [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 1 ] || [ "$USER_CHOICE" -gt "$SKIP_IDX" ]; then
    log "Invalid choice or timeout. Defaulting to first option..."
    USER_CHOICE=1
fi

if [ "$USER_CHOICE" -eq "$SKIP_IDX" ]; then
    SKIP_THEME=true
    info_kv "Selected" "None (Clear Theme)"
else
    SELECTED_INDEX=$((USER_CHOICE-1))
    if [ -n "${THEME_NAMES[$SELECTED_INDEX]:-}" ]; then
        THEME_PATH="${THEME_PATHS[$SELECTED_INDEX]}/theme.txt"
        THEME_NAME="${THEME_NAMES[$SELECTED_INDEX]}"
        info_kv "Selected" "Local: $THEME_NAME"
    else
        warn "Selected theme index is invalid. Falling back to skip mode."
        SKIP_THEME=true
    fi
fi

# ------------------------------------------------------------------------------
# 4. Install & Configure Theme
# ------------------------------------------------------------------------------
# 第四步：安装和配置主题
section "Step 4/6" "Theme Configuration"

GRUB_CONF="/etc/default/grub"

if [ "$SKIP_THEME" == "true" ]; then
    log "Clearing GRUB theme configuration..."
    cleanup_grub_theme
    
    if [ -f "$GRUB_CONF" ]; then
        if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i 's|^GRUB_THEME=|#GRUB_THEME=|' "$GRUB_CONF"
            success "Disabled existing GRUB_THEME in configuration."
        else
            log "No active GRUB_THEME found to disable."
        fi
    fi
else
    cleanup_grub_theme
    
    if [ -f "$GRUB_CONF" ]; then
        if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
            elif grep -q "^#GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i "s|^#GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
        else
            echo "GRUB_THEME=\"$THEME_PATH\"" >> "$GRUB_CONF"
        fi
        
        if grep -q "^GRUB_TERMINAL_OUTPUT=\"console\"" "$GRUB_CONF"; then
            exe sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_CONF"
        fi
        
        if ! grep -q "^GRUB_GFXMODE=" "$GRUB_CONF"; then
            echo 'GRUB_GFXMODE=auto' >> "$GRUB_CONF"
        fi
        success "Configured GRUB to use theme: $THEME_NAME"
    else
        error "$GRUB_CONF not found."
        exit 1
    fi
fi

section "Step 4.5/6" "Patch Kernel Menu Titles"
patch_grub_linux_titles || exit 1

# ------------------------------------------------------------------------------
# 5. Add Shutdown/Reboot Menu Entries
# ------------------------------------------------------------------------------
# 第五步：添加关机/重启菜单项
# 在 GRUB 菜单中添加快捷的电源选项
section "Step 5/6" "Menu Entries"
log "Adding Power Options to GRUB menu..."

# 复制自定义菜单模板
write_power_entries

success "Added grub menuentry 99-shutdown"
# ------------------------------------------------------------------------------
# 6. Apply Changes
# ------------------------------------------------------------------------------
# 第六步：应用更改
# 重新生成 GRUB 配置文件
section "Step 6/6" "Apply Changes"
log "Generating new GRUB configuration..."
info_kv "GRUB Output" "$GRUB_OUTPUT"

if exe grub-mkconfig -o "$GRUB_OUTPUT"; then
    success "GRUB updated successfully."
else
    error "Failed to update GRUB."
    warn "You may need to run 'grub-mkconfig' manually."
    exit 1
fi

log "Module 82 completed."
