#!/bin/bash

export SHELL=$(command -v bash)
# ==============================================================================
# Arch Setup - 主安装程序
# ==============================================================================

# 定义基础目录变量
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 获取脚本所在的当前目录的绝对路径
SCRIPTS_DIR="$BASE_DIR/scripts"                           # 存放子脚本的目录
STATE_FILE="$BASE_DIR/.install_progress"                  # 用于记录安装进度的状态文件，实现断点续传

# --- 加载可视化引擎与工具函数 ---
# 检查是否存在工具库脚本，如果存在则加载，否则报错退出
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# --- 全局退出清理 ---
# 退出时恢复光标，并删除临时缓存的目标用户名。
cleanup_on_exit() {
    if command -v tput >/dev/null 2>&1; then
        tput cnorm 2>/dev/null || true
    fi
    rm -f "/tmp/daguo_install_user"
}
trap cleanup_on_exit EXIT

# --- 环境变量设置 ---
# 如果 DEBUG 未定义，默认为 0；如果 CN_MIRROR (中国镜像源模式) 未定义，默认为 0
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}

# 检查是否以 root 权限运行 (函数定义在 00-utils.sh 中)
check_root
# 给予 scripts 目录下所有脚本执行权限
chmod +x "$SCRIPTS_DIR"/*.sh

# --- ASCII Banner 艺术字 ---
# 定义三个不同的 Banner 函数，用于显示不同的 ASCII 艺术标题
banner() {
cat <<'EOF'
  ██████   █████  ██████  ██    ██  ██████
  ██   ██ ██   ██ ██   ██ ██    ██ ██    ██
  ██   ██ ███████ ██   ██ ██    ██ ██    ██
  ██   ██ ██   ██ ██   ██ ██    ██ ██    ██
  ██████  ██   ██ ██████   ██████   ██████
EOF
}

# 显示 Banner 的函数
show_banner() {
    # 每次关键菜单前刷新画面，减少旧日志干扰阅读。
    clear
    echo -e "${H_CYAN}"
    banner
    echo -e "${NC}"
    echo -e "${DIM}   :: Arch Linux Personal Setup ::${NC}"
    echo
}

# --- 桌面环境选择菜单 ---
select_desktop() {
    if ! command -v fzf &> /dev/null; then
        echo -e "   ${DIM}Installing fzf for interactive menu...${NC}"
        pacman -Sy --noconfirm --needed fzf >/dev/null 2>&1
    fi

    # 当前两个桌面目标，后续扩展可继续按编号段添加。
    local MENU_ITEMS=(
        "GNOME|gnome"
        "Daguo DMS + Niri|dms-niri"
    )

    while true; do
        show_banner
        
        local fzf_list=()
        local idx=1
        for item in "${MENU_ITEMS[@]}"; do
            [[ -z "$item" ]] && continue
            
            local name="${item%%|*}"
            local val="${item##*|}"
            local colored_idx="${H_CYAN}[${idx}]${NC}"
            
            if [ $idx -lt 10 ]; then
                fzf_list+=("${colored_idx}   ${name}\t${val}\t${name}")
            else
                fzf_list+=("${colored_idx}  ${name}\t${val}\t${name}")
            fi
            ((idx++))
        done
        
        local selected
        selected=$(printf "%b\n" "${fzf_list[@]}" | sed '/^[[:space:]]*$/d' | fzf \
            --ansi \
            --delimiter='\t' \
            --with-nth=1 \
            --info=hidden \
            --layout=reverse \
            --border="rounded" \
            --border-label="  Select Desktop Environment  " \
            --border-label-pos=5 \
            --color="marker:cyan,pointer:cyan,label:yellow" \
            --header=" [J/K] Select | [Enter] confirm" \
            --pointer=">" \
            --bind 'j:down,k:up,ctrl-c:abort,esc:abort' \
        --height=~20)
        
        local fzf_status=$?
        
        if [ $fzf_status -eq 130 ]; then
            echo -e "\n   ${H_RED}>>> Installation aborted by user.${NC}"
            exit 130
        fi
        
        if [ -z "$selected" ]; then continue; fi

        export DESKTOP_ENV="$(echo "$selected" | awk -F'\t' '{print $2}')"
        local selected_name="$(echo "$selected" | awk -F'\t' '{print $3}')"

        log "Selected: ${selected_name}"
        sleep 0.5
        break
    done
}

# 可选模块统一放在 installer 中选择，避免把分支判断散落到各个模块内部。
select_optional_modules() {
    local OPTIONAL_MENU=(
        "Windows Dual Boot|80-dualboot.sh"
        "Flatpak Setup|81-flatpak.sh"
        "GRUB Theme|82-grub-theme.sh"
        "Common Apps|90-apps.sh"
    )
    
    show_banner
    
    local fzf_list=()
    for item in "${OPTIONAL_MENU[@]}"; do
        local name="${item%%|*}"
        local val="${item##*|}"
        fzf_list+=("  ${name}\t${val}")
    done
    
    # 核心修复：引入 --expect=ctrl-x,enter 来拦截按键动作
    local selected_raw
    selected_raw=$(printf "%b\n" "${fzf_list[@]}" | fzf \
        --multi \
        --delimiter='\t' \
        --with-nth=1 \
        --layout=reverse \
        --border="rounded" \
        --border-label="  Select Optional Modules  " \
        --border-label-pos=5 \
        --color="marker:cyan,pointer:cyan,label:yellow" \
        --header=" [TAB]: Toggle | [CTRL-X]: Skip All | [ENTER]: Confirm " \
        --pointer=">" \
        --expect=ctrl-x,enter \
        --bind 'start:select-all,ctrl-a:select-all,ctrl-d:deselect-all,ctrl-c:abort,esc:abort,j:down,k:up' \
    --height=~20)
    
    local fzf_status=$?
    if [ $fzf_status -eq 130 ]; then
        echo -e "\n   ${H_RED}>>> Installation aborted by user.${NC}"
        exit 130
    fi
    
    OPTIONAL_MODULES=()
    
    if [ -n "$selected_raw" ]; then
        # 解析 FZF 输出：第一行是按下的键，后面是选中的内容
        local key
        key=$(head -n 1 <<< "$selected_raw")
        local selected_items
        selected_items=$(sed '1d' <<< "$selected_raw")

        # 完美解决“回车默认选中光标项”的问题：用户直接按 Ctrl-X 即可退出并清空
        if [[ "$key" == "ctrl-x" ]]; then
            log "Skipping all optional modules..."
            sleep 0.5
        else
            if [ -n "$selected_items" ]; then
                # 利用 awk 过滤掉空行，防止产生空元素
                mapfile -t OPTIONAL_MODULES < <(echo "$selected_items" | awk -F'\t' '{if ($2 != "") print $2}')
            fi
        fi
    fi
}

# 显示系统诊断信息的仪表盘函数
sys_dashboard() {
    echo -e "${H_BLUE}╔════ SYSTEM DIAGNOSTICS ══════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Kernel${NC}   : $(uname -r)" # 显示内核版本
    echo -e "${H_BLUE}║${NC} ${BOLD}User${NC}     : $(whoami)"   # 显示当前用户 (应为 root)
    echo -e "${H_BLUE}║${NC} ${BOLD}Desktop${NC}  : ${H_CYAN}${DESKTOP_ENV^^}${NC}" # 显示选择的桌面环境 (转换为大写)
    
    # 根据网络模式显示状态
    if [ "$CN_MIRROR" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_YELLOW}CN Optimized (Manual)${NC}"
    elif [ "$DEBUG" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_RED}DEBUG FORCE (CN Mode)${NC}"
    else
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : Global Default"
    fi
    
    # 如果存在进度文件，显示已完成的步数
    if [ -f "$STATE_FILE" ]; then
        done_count=$(grep -c '\.sh$' "$STATE_FILE" 2>/dev/null || true)
        echo -e "${H_BLUE}║${NC} ${BOLD}Progress${NC} : Resuming ($done_count steps recorded)"
    fi
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- 主程序执行流程 ---

select_desktop          # 执行桌面选择
select_optional_modules # 执行可选模块选择
clear                   # 清屏
show_banner             # 显示 Banner
sys_dashboard           # 显示仪表盘

# 动态构建模块列表
# 定义所有桌面环境都需要的核心模块
MANDATORY_MODULES=(
    "01-preflight.sh"
    "02-btrfs-init.sh"
    "03-base.sh"
    "04-user.sh"
    "05-gpu-driver.sh"
    "06-audio-bluetooth-power.sh"
    "07-locale-input.sh"
    "08-snapshot-before-desktop.sh"
)

ALL_MODULES=("${MANDATORY_MODULES[@]}" "${OPTIONAL_MODULES[@]}")

# 根据选择的桌面环境 (DESKTOP_ENV) 添加特定模块
case "$DESKTOP_ENV" in
    gnome)
        ALL_MODULES+=("20-gnome.sh")
        ;;
    dms-niri)
        ALL_MODULES+=("30-dms-niri.sh")
        ;;
    *)
        error "Unknown desktop selection: $DESKTOP_ENV"
        exit 1
        ;;
esac

ALL_MODULES+=("95-verify.sh" "99-cleanup.sh")

# 按声明顺序去重，避免 sort -u 打乱安装阶段顺序。
MODULES=()
for module in "${ALL_MODULES[@]}"; do
    skip_module=false
    for added in "${MODULES[@]}"; do
        if [[ "$added" == "$module" ]]; then
            skip_module=true
            break
        fi
    done
    [[ "$skip_module" == true ]] && continue
    MODULES+=("$module")
done

if [ ! -f "$STATE_FILE" ]; then touch "$STATE_FILE"; fi

TOTAL_STEPS=${#MODULES[@]}
CURRENT_STEP=0

log "Initializing installer sequence..."
sleep 0.5

# --- 模块执行循环 ---
for module in "${MODULES[@]}"; do
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    # 检查模块脚本是否存在
    if [ ! -f "$script_path" ]; then
        error "Module not found: $module"
        exit 1
    fi

    # 检查点逻辑：如果状态文件中已有该模块记录，则自动跳过
    if grep -q "^${module}$" "$STATE_FILE"; then
        echo -e "   ${H_GREEN}✔${NC} Module ${BOLD}${module}${NC} already completed."
        echo -e "   ${DIM}   Skipping... (Delete .install_progress to force run)${NC}"
        continue
    fi

    # 显示当前正在执行的模块
    section "Module ${CURRENT_STEP}/${TOTAL_STEPS}" "$module"

    # 执行脚本
    bash "$script_path"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        # 成功：记录到状态文件
        echo "$module" >> "$STATE_FILE"
        success "Module $module completed."
    elif [ $exit_code -eq 130 ]; then
        # 用户中断 (Ctrl+C)
        echo ""
        warn "Script interrupted by user (Ctrl+C)."
        log "Exiting without rollback. You can resume later."
        exit 130
    else
        # 失败：记录错误日志并退出，但不记录到状态文件，以便重试
        write_log "FATAL" "Module $module failed with exit code $exit_code"
        error "Module execution failed."
        exit 1
    fi
done

# --- 完成 ---
clear
show_banner
echo -e "${H_GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_GREEN}║             INSTALLATION  COMPLETE                   ║${NC}"
echo -e "${H_GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# 删除进度记录文件
if [ -f "$STATE_FILE" ]; then rm "$STATE_FILE"; fi

# --- 归档日志 ---
log "Archiving log..."
# 获取最终的普通用户名
if [ -f "/tmp/daguo_install_user" ]; then
    FINAL_USER=$(cat /tmp/daguo_install_user)
else
    # 如果临时文件不存在，尝试优先取 sudo 发起用户，否则回退到 UID 1000 用户。
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        FINAL_USER="$SUDO_USER"
    else
        FINAL_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
    fi
fi

# 如果找到了用户，将日志复制到该用户的 Documents 目录
if [ -n "$FINAL_USER" ]; then
    FINAL_DOCS="/home/$FINAL_USER/Documents"
    mkdir -p "$FINAL_DOCS"
    cp "$TEMP_LOG_FILE" "$FINAL_DOCS/log-daguo-arch-setup.txt"
    chown -R "$FINAL_USER:$FINAL_USER" "$FINAL_DOCS"
    echo -e "   ${H_BLUE}●${NC} Log Saved     : ${BOLD}$FINAL_DOCS/log-daguo-arch-setup.txt${NC}"
fi

# --- 重启倒计时 ---
echo ""
echo -e "${H_YELLOW}>>> System requires a REBOOT.${NC}"

# 清空输入缓冲区
while read -r -t 0; do read -r; done

# 10秒倒计时
for i in {10..1}; do
    echo -ne "\r   ${DIM}Auto-rebooting in ${i}s... (Press 'n' to cancel)${NC}"
    
    # 监听键盘输入，超时1秒
    read -t 1 -n 1 input
    if [ $? -eq 0 ]; then
        if [[ "$input" == "n" || "$input" == "N" ]]; then
            echo -e "\n\n   ${H_BLUE}>>> Reboot cancelled.${NC}"
            exit 0
        else
            break
        fi
    fi
done

echo -e "\n\n   ${H_GREEN}>>> Rebooting...${NC}"
systemctl reboot
