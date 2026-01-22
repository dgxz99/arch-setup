#!/bin/bash

# ==============================================================================
# Shorin Arch Setup - 主安装程序 (v1.1)
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

# --- 退出时的全局清理 ---
# 定义清理函数，删除临时存储用户名的文件
cleanup() {
    rm -f "/tmp/shorin_install_user"
}
# 设置 trap ，在脚本退出 (EXIT) 时自动执行 cleanup 函数
trap cleanup EXIT

# --- 全局陷阱 (退出时恢复光标) ---
# 定义退出清理函数，确保光标恢复显示 (因为脚本中可能会隐藏光标)
cleanup_on_exit() {
    tput cnorm
}
# 追加 trap，确保退出时也执行恢复光标的操作
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
banner1() {
cat << "EOF"
   _____ __  ______  ____  _____   __
  / ___// / / / __ \/ __ \/  _/ | / /
  \__ \/ /_/ / / / / /_/ // //  |/ / 
 ___/ / __  / /_/ / _, _// // /|  /  
/____/_/ /_/\____/_/ |_/___/_/ |_/   
EOF
}

banner2() {
cat << "EOF"
  ██████  ██   ██  ██████  ███████ ██ ███    ██ 
  ██      ██   ██ ██    ██ ██   ██    ██ ██  ██ 
  ███████ ███████ ██    ██ ██████  ██ ██ ██  ██ 
       ██ ██   ██ ██    ██ ██   ██ ██ ██  ██ ██ 
  ██████  ██   ██  ██████  ██   ██ ██ ██   ████ 
EOF
}

banner3() {
cat << "EOF"
   ______ __ __   ___   ____   ____  _   _ 
  / ___/|  |  | /   \ |    \ |    || \ | |
 (   \_ |  |  ||     ||  D  ) |  | |  \| |
  \__  ||  _  ||  O  ||    /  |  | |     |
  /  \ ||  |  ||     ||    \  |  | | |\  |
  \    ||  |  ||     ||  .  \ |  | | | \ |
   \___||__|__| \___/ |__|\_||____||_| \_|
EOF
}

# 显示 Banner 的函数
show_banner() {
    clear  # 清屏
    local r=$(( $RANDOM % 3 ))  # 生成 0-2 的随机数
    echo -e "${H_CYAN}"         # 设置颜色为高亮青色
    # 根据随机数选择一个 banner 显示
    case $r in
        0) banner1 ;;
        1) banner2 ;;
        2) banner3 ;;
    esac
    echo -e "${NC}"             # 重置颜色
    # 显示版本信息
    echo -e "${DIM}   :: Arch Linux Automation Protocol :: v1.1 ::${NC}"
    echo ""
}

# --- 桌面环境选择菜单 ---
select_desktop() {
    show_banner  # 显示标题
    
    # 1. 定义选项数组 (显示名称|内部ID)
    # 使用 | 分隔显示文本和脚本内部使用的标识符
    local OPTIONS=(
        "No Desktop |none"
        "Shorin's Niri |niri"
        "KDE Plasma |kde"
        "GNOME |gnome"
        "Quickshell: End4--illogical-impulse (Hyprland)|end4"
        "Quickshell: DMS--DankMaterialShell (Niri or Hyprland)|dms"
        "Quickshell: Caelestia (Hyprland)|caelestia"
    )
    
    # 2. 绘制菜单 (半开放式风格)
    # 定义分隔线
    local HR="──────────────────────────────────────────────────"
    
    echo -e "${H_PURPLE}╭${HR}${NC}"
    echo -e "${H_PURPLE}│${NC} ${BOLD}Choose your Desktop Environment:${NC}"
    echo -e "${H_PURPLE}│${NC}" # 空行分隔，用于美观

    local idx=1
    # 遍历选项数组进行显示
    for opt in "${OPTIONS[@]}"; do
        local name="${opt%%|*}"  # 截取 | 左边的内容作为显示名称
        # 打印选项编号和名称
        echo -e "${H_PURPLE}│${NC}  ${H_CYAN}[${idx}]${NC} ${name}"
        ((idx++))
    done
    echo -e "${H_PURPLE}│${NC}" # 空行分隔
    echo -e "${H_PURPLE}╰${HR}${NC}"
    echo ""
    
    # 3. 输入处理
    echo -e "   ${DIM}Waiting for input (Timeout: 2 mins)...${NC}"
    # 读取用户输入，超时时间 120 秒
    read -t 120 -p "$(echo -e "   ${H_YELLOW}Select [1-${#OPTIONS[@]}]: ${NC}")" choice
    
    # 检查是否超时或未输入
    if [ -z "$choice" ]; then
        echo -e "\n${H_RED}Timeout or no selection.${NC}"
        exit 1
    fi
    
    # 4. 验证输入并提取内部 ID
    # 检查输入是否为数字，且在有效范围内
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#OPTIONS[@]}" ]; then
        local selected_opt="${OPTIONS[$((choice-1))]}"  # 获取选中的数组元素
        export DESKTOP_ENV="${selected_opt##*|}"       # 截取 | 右边的内容作为内部 ID，并导出为环境变量
        log "Selected: ${selected_opt%%|*}"             # 记录日志
    else
        error "Invalid selection."
        exit 1
    fi
    sleep 0.5
}

# 显示系统诊断信息的仪表盘函数
sys_dashboard() {
    echo -e "${H_BLUE}╔════ SYSTEM DIAGNOSTICS ══════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Kernel${NC}   : $(uname -r)" # 显示内核版本
    echo -e "${H_BLUE}║${NC} ${BOLD}User${NC}     : $(whoami)"   # 显示当前用户 (应为 root)
    echo -e "${H_BLUE}║${NC} ${BOLD}Desktop${NC}  : ${H_MAGENTA}${DESKTOP_ENV^^}${NC}" # 显示选择的桌面环境 (转换为大写)
    
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
        done_count=$(wc -l < "$STATE_FILE")
        echo -e "${H_BLUE}║${NC} ${BOLD}Progress${NC} : Resuming ($done_count steps recorded)"
    fi
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- 主程序执行流程 ---

select_desktop   # 执行桌面选择
clear            # 清屏
show_banner      # 显示 Banner
sys_dashboard    # 显示仪表盘

# 动态构建模块列表
# 定义所有桌面环境都需要的核心模块
BASE_MODULES=(
    "00-btrfs-init.sh"          # BTRFS文件系统初始化 (快照等)
    "01-base.sh"                # 基础包安装
    "02-musthave.sh"            # 必备工具安装
    "02a-dualboot-fix.sh"       # 双系统修复 (如有时钟问题等)
    "03-user.sh"                # 用户创建与配置
    "03b-gpu-driver.sh"         # 显卡驱动安装
    "03c-snapshot-before-desktop.sh" # 安装桌面环境前的系统快照
)

# 根据选择的桌面环境 (DESKTOP_ENV) 添加特定模块
case "$DESKTOP_ENV" in
    niri)
        BASE_MODULES+=("04-niri-setup.sh")
        ;;
    kde)
        BASE_MODULES+=("04b-kdeplasma-setup.sh")
        ;;
    end4)
        BASE_MODULES+=("04e-illogical-impulse-end4-quickshell.sh")
        ;;
    dms)
        BASE_MODULES+=("04c-dms-quickshell.sh")
        ;;
    caelestia)
        BASE_MODULES+=("04g-caelestia-quickshell.sh")
        ;;
    gnome)
        BASE_MODULES+=("04d-gnome.sh")
        ;;
    none)
        log "Skipping Desktop Environment installation."
        ;;
    *)
        warn "Unknown selection, skipping desktop setup."
        ;;
esac

# 添加最后的通用模块：GRUB 主题和常用软件
BASE_MODULES+=("07-grub-theme.sh" "99-apps.sh")
# 将构建好的模块列表赋值给 MODULES 数组
MODULES=("${BASE_MODULES[@]}")

# 如果状态文件不存在，则创建它
if [ ! -f "$STATE_FILE" ]; then touch "$STATE_FILE"; fi

TOTAL_STEPS=${#MODULES[@]} # 计算总步数
CURRENT_STEP=0             # 初始化当前步数

log "Initializing installer sequence..."
sleep 0.5

# --- Reflector 镜像源优化 (支持状态记忆) ---
section "Pre-Flight" "Mirrorlist Optimization"

# [修改] 检查是否已经完成过 Reflector 步骤
if grep -q "^REFLECTOR_DONE$" "$STATE_FILE"; then
    echo -e "   ${H_GREEN}✔${NC} Mirrorlist previously optimized."
    echo -e "   ${DIM}   Skipping Reflector steps (Resume Mode)...${NC}"
else
    # --- 开始 Reflector 逻辑 ---
    log "Checking Reflector..."
    # 安装 reflector 工具
    exe pacman -S --noconfirm --needed reflector

    CURRENT_TZ=$(readlink -f /etc/localtime)
    # 设置 reflector 参数：最近24小时、最快10个、按分数排序、保存路径、详细输出
    REFLECTOR_ARGS="-a 24 -f 10 --sort score --save /etc/pacman.d/mirrorlist --verbose"

    # 检测是否为中国时区 (Shanghai)
    if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
        echo ""
        echo -e "${H_YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${H_YELLOW}║  DETECTED TIMEZONE: Asia/Shanghai                                ║${NC}"
        echo -e "${H_YELLOW}║  Refreshing mirrors in China can be slow.                        ║${NC}"
        echo -e "${H_YELLOW}║  Do you want to force refresh mirrors with Reflector?            ║${NC}"
        echo -e "${H_YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # 询问是否运行 Reflector (默认不运行，因为国内连接 reflector 经常超时)
        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector? [y/N] (Default No in 60s): ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi # 处理超时换行
        choice=${choice:-N}
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log "Running Reflector for China..."
            # 尝试运行 reflector 并指定国家为 China
            if exe reflector $REFLECTOR_ARGS -c China; then
                success "Mirrors updated."
            else
                warn "Reflector failed. Continuing with existing mirrors."
            fi
        else
            log "Skipping mirror refresh."
        fi
    else
        # 非中国时区，尝试自动检测位置优化
        log "Detecting location for optimization..."
        COUNTRY_CODE=$(curl -s --max-time 2 https://ipinfo.io/country)
        
        if [ -n "$COUNTRY_CODE" ]; then
            info_kv "Country" "$COUNTRY_CODE" "(Auto-detected)"
            log "Running Reflector for $COUNTRY_CODE..."
            # 尝试按国家代码优化
            if ! exe reflector $REFLECTOR_ARGS -c "$COUNTRY_CODE"; then
                warn "Country specific refresh failed. Trying global speed test..."
                # 失败则运行全球测速
                exe reflector $REFLECTOR_ARGS
            fi
        else
            warn "Could not detect country. Running global speed test..."
            exe reflector $REFLECTOR_ARGS
        fi
        success "Mirrorlist optimized."
    fi
    # --- 结束 Reflector 逻辑 ---

    # [修改] 记录成功状态，避免重复询问
    echo "REFLECTOR_DONE" >> "$STATE_FILE"
fi

# ---- 更新密钥环 keyring -----

section "Pre-Flight" "Update Keyring"

# 强制同步包数据库并更新 archlinux-keyring，防止签名错误
exe pacman -Sy
exe pacman -S --noconfirm archlinux-keyring

# --- 全局系统更新 ---
section "Pre-Flight" "System update"
log "Ensuring system is up-to-date..."

# 执行全面系统更新
if exe pacman -Syu --noconfirm; then
    success "System Updated."
else
    error "System update failed. Check your network."
    exit 1
fi

# --- 模块执行循环 ---
for module in "${MODULES[@]}"; do
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    # 检查模块脚本是否存在
    if [ ! -f "$script_path" ]; then
        error "Module not found: $module"
        continue
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

# ------------------------------------------------------------------------------
# 最终清理阶段
# ------------------------------------------------------------------------------
section "Completion" "System Cleanup"

# --- 1. 快照清理逻辑 ---
# 清理安装过程中产生的中间快照，只保留关键节点
clean_intermediate_snapshots() {
    local config_name="$1"     # 参数：snapper 配置名 (如 root, home)
    local start_marker="Before Shorin Setup" # 定义起始标记
    
    # 定义需要保留的快照描述白名单
    local KEEP_MARKERS=(
        "Before Desktop Environments"
        "Before Niri Setup"
    )

    # 如果没有该配置的 snapper 列表，直接返回
    if ! snapper -c "$config_name" list &>/dev/null; then
        return
    fi

    log "Scanning junk snapshots in: $config_name..."

    # 1. 获取起始点快照 ID
    local start_id
    start_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$start_marker" | awk '{print $1}' | tail -n 1)

    # 如果找不到起始标记，说明可能不是通过本脚本初始化的，跳过清理以防误删
    if [ -z "$start_id" ]; then
        warn "Marker '$start_marker' not found in '$config_name'. Skipping cleanup."
        return
    fi

    # 2. 解析白名单，获取需要保留的快照 ID (IDS_TO_KEEP)
    local IDS_TO_KEEP=()
    for marker in "${KEEP_MARKERS[@]}"; do
        local found_id
        found_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$marker" | awk '{print $1}' | tail -n 1)
        
        if [ -n "$found_id" ]; then
            IDS_TO_KEEP+=("$found_id")
            log "Found protected snapshot: '$marker' (ID: $found_id)"
        fi
    done

    local snapshots_to_delete=()
    
    # 3. 扫描并筛选需要删除的快照
    # 逐行读取 snapper list 输出
    while IFS= read -r line; do
        local id
        local type
        
        # Snapper 表格输出通常为: " 100 | pre    | ..."
        # awk $1=number, $3=type
        id=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $3}')

        if [[ "$id" =~ ^[0-9]+$ ]]; then
            # 只处理 ID 大于起始点的快照
            if [ "$id" -gt "$start_id" ]; then
                
                # --- 白名单检查 ---
                local skip=false
                for keep in "${IDS_TO_KEEP[@]}"; do
                    if [[ "$id" == "$keep" ]]; then
                        skip=true
                        break
                    fi
                done
                
                if [ "$skip" = true ]; then
                    continue
                fi
                # -----------------

                # [修改重点] 仅删除 pre 和 post 类型的自动快照
                # 这样可以保护用户手动创建的 (single) 快照
                if [[ "$type" == "pre" || "$type" == "post" ]]; then
                    snapshots_to_delete+=("$id")
                fi
            fi
        fi
    done < <(snapper -c "$config_name" list --columns number,type)

    # 4. 执行批量删除
    if [ ${#snapshots_to_delete[@]} -gt 0 ]; then
        log "Deleting ${#snapshots_to_delete[@]} junk snapshots in '$config_name'..."
        if exe snapper -c "$config_name" delete "${snapshots_to_delete[@]}"; then
            success "Cleaned $config_name."
        fi
    else
        log "No junk snapshots found in '$config_name'."
    fi
}
# --- 2. 执行清理 ---
log "Cleaning Pacman/Yay cache..."
exe pacman -Sc --noconfirm # 清理 pacman 缓存

# 对 root 和 home 配置执行快照清理
clean_intermediate_snapshots "root"
clean_intermediate_snapshots "home"

# --- 3. 删除安装文件 ---
# 如果脚本位于 /root/shorin-arch-setup，则视为安装后垃圾进行删除
if [ -d "/root/shorin-arch-setup" ]; then
    log "Removing installer from /root..."
    cd /
    rm -rfv /root/shorin-arch-setup
else
    log "Repo cleanup skipped (not in /root/shorin-arch-setup)."
    log "If you cloned this manually, please remove the folder yourself."
fi

# --- 4. 最终 GRUB 更新 ---
log "Regenerating final GRUB configuration..."
exe grub-mkconfig -o /boot/grub/grub.cfg

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
if [ -f "/tmp/shorin_install_user" ]; then
    FINAL_USER=$(cat /tmp/shorin_install_user)
else
    # 如果临时文件不存在，尝试从 passwd 猜一个 UID 1000 的用户
    FINAL_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
fi

# 如果找到了用户，将日志复制到该用户的 Documents 目录
if [ -n "$FINAL_USER" ]; then
    FINAL_DOCS="/home/$FINAL_USER/Documents"
    mkdir -p "$FINAL_DOCS"
    cp "$TEMP_LOG_FILE" "$FINAL_DOCS/log-shorin-arch-setup.txt"
    chown -R "$FINAL_USER:$FINAL_USER" "$FINAL_DOCS"
    echo -e "   ${H_BLUE}●${NC} Log Saved     : ${BOLD}$FINAL_DOCS/log-shorin-arch-setup.txt${NC}"
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
