#!/bin/bash

# ==============================================================================
# 00-utils.sh - The "TUI" Visual Engine (v4.0)
# ==============================================================================
# 这是核心工具库，提供：
#   1. 终端颜色和样式定义 (ANSI 转义码)
#   2. 美化输出函数 (日志、分隔线、进度显示等)
#   3. 命令执行器 (带视觉反馈的命令运行器)
#   4. 可复用的通用功能 (镜像选择、用户态执行等)
# ==============================================================================

# --- 1. 颜色与样式定义 (ANSI) ---
# 注意：这里定义的是字面量字符串，需要 echo -e 来解析
export NC='\033[0m'             # NC = No Color，重置所有样式
export BOLD='\033[1m'           # BOLD = 粗体/高亮
export DIM='\033[2m'            # DIM = 暗淡/降低亮度
export ITALIC='\033[3m'         # ITALIC = 斜体 (部分终端不支持)
export UNDER='\033[4m'          # UNDER = 下划线
export H_MAGENTA='\033[1;35m'   # 高亮洋红色 - 用于 EXEC 标签

# 常用高亮色
export H_RED='\033[1;31m'      # 高亮红色 - 用于错误信息
export H_GREEN='\033[1;32m'    # 高亮绿色 - 用于成功信息
export H_YELLOW='\033[1;33m'   # 高亮黄色 - 用于警告信息
export H_BLUE='\033[1;34m'     # 高亮蓝色 - 用于提示信息
export H_PURPLE='\033[1;35m'   # 高亮紫色 - 用于边框装饰
export H_CYAN='\033[1;36m'     # 高亮青色 - 用于命令和选项
export H_WHITE='\033[1;37m'    # 高亮白色 - 用于标题
export H_GRAY='\033[1;90m'     # 高亮灰色 - 用于次要信息

# 背景色 (用于标题栏)
export BG_BLUE='\033[44m'      # 蓝色背景
export BG_PURPLE='\033[45m'    # 紫色背景

# 符号定义
export TICK="${H_GREEN}✔${NC}"     # 绿色对勾 - 表示成功/完成
export CROSS="${H_RED}✘${NC}"      # 红色叉号 - 表示失败/错误
export INFO="${H_BLUE}ℹ${NC}"       # 蓝色信息图标
export WARN="${H_YELLOW}⚠${NC}"    # 黄色警告图标
export ARROW="${H_CYAN}➜${NC}"     # 青色箭头 - 表示正在进行

# 日志文件
export TEMP_LOG_FILE="/tmp/log-daguo-arch-setup.txt"
# 如果日志文件不存在，则创建它并设置权限为 666 (所有人可读写)
[ ! -f "$TEMP_LOG_FILE" ] && touch "$TEMP_LOG_FILE" && chmod 666 "$TEMP_LOG_FILE"


# --- 2. 基础工具 ---

# 检查是否以 root 权限运行：许多系统级操作 (如安装软件包、修改系统配置) 需要 root 权限
check_root() {
    # $EUID 是 Bash 内置变量，表示当前用户的有效用户 ID
    # root 用户的 EUID 为 0
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}   $CROSS CRITICAL ERROR: Script must be run as root.${NC}"
        exit 1
    fi
}
check_root

# as_user - 以指定用户身份执行命令
# 在 root 权限下运行脚本时，某些操作需要以普通用户身份执行
# 例如：配置用户的 dotfiles、安装 AUR 包等
# 用法: as_user <命令> [参数...]
# 注意: 需要先设置 $TARGET_USER 环境变量
as_user() {
  # runuser 是比 su 更安全的切换用户命令
  # -u 指定目标用户
  # -- 表示后面的内容都是要执行的命令
  runuser -u "$TARGET_USER" -- "$@"
}

# ==============================================================================
# detect_target_user - 识别目标用户 (支持 1-based 序号与回车默认选择)
# ==============================================================================
detect_target_user() {
    # 1. 缓存检查
    if [[ -f "/tmp/daguo_install_user" ]]; then
        TARGET_USER=$(cat "/tmp/daguo_install_user")
        HOME_DIR="/home/$TARGET_USER"
        export TARGET_USER HOME_DIR
        return 0
    fi
    
    log "Detecting system users..."
    
    # 2. 提取系统中所有普通用户 (UID 1000-60000)
    mapfile -t HUMAN_USERS < <(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd)
    
    # 3. 核心决策逻辑
    if [[ ${#HUMAN_USERS[@]} -gt 1 ]]; then
        echo -e "   ${H_YELLOW}>>> Multiple users detected. Who is the target?${NC}"
        
        local default_user=""
        local default_idx=""
        
        # 遍历用户，生成 1 开始的序号，并捕获当前 Sudo 用户作为默认值
        for i in "${!HUMAN_USERS[@]}"; do
            local mark=""
            local display_idx=$((i + 1))
            
            if [[ "${HUMAN_USERS[$i]}" == "${SUDO_USER:-}" ]]; then
                mark="${H_CYAN}*${NC}"
                default_user="${HUMAN_USERS[$i]}"
                default_idx="$display_idx"
            fi
            
            echo -e "       [${display_idx}] ${mark}${HUMAN_USERS[$i]}"
        done
        
        while true; do
            # 动态生成提示词
            if [[ -n "$default_user" ]]; then
                echo -ne "   ${H_CYAN}Select user ID [1-${#HUMAN_USERS[@]}] (Default ${default_idx}): ${NC}"
            else
                echo -ne "   ${H_CYAN}Select user ID [1-${#HUMAN_USERS[@]}]: ${NC}"
            fi
            
            read -r idx
            
            # 处理直接回车：如果有默认用户，直接采纳
            if [[ -z "$idx" && -n "$default_user" ]]; then
                TARGET_USER="$default_user"
                log "Defaulting to current user: ${H_CYAN}${TARGET_USER}${NC}"
                break
            fi
            
            # 验证输入是否为合法数字 (1 到 数组长度)
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#HUMAN_USERS[@]}" ]; then
                # 数组索引需要减 1 还原
                TARGET_USER="${HUMAN_USERS[$((idx - 1))]}"
                break
            else
                warn "Invalid selection. Please enter a valid number or press Enter for default."
            fi
        done
        
        elif [[ ${#HUMAN_USERS[@]} -eq 1 ]]; then
        TARGET_USER="${HUMAN_USERS[0]}"
        log "Single user detected: ${H_CYAN}${TARGET_USER}${NC}"
        
    else
        if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
            TARGET_USER="$SUDO_USER"
        else
            echo -ne "   ${H_YELLOW}No standard user found. Enter intended username:${NC} "
            read -r TARGET_USER
        fi
    fi
    
    # 4. 最终验证与持久化
    if [[ -z "$TARGET_USER" ]]; then
        error "Target user cannot be empty."
        exit 1
    fi
    
    echo "$TARGET_USER" > "/tmp/daguo_install_user"
    HOME_DIR="/home/$TARGET_USER"
    export TARGET_USER HOME_DIR
    
}

# 写入日志函数
# 参数1: 日志级别 (如 LOG, SUCCESS, ERROR, WARN 等)
# 参数2: 日志消息内容
write_log() {
    local clean_msg=$(echo -e "$2" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%H:%M:%S')] [$1] $clean_msg" >> "$TEMP_LOG_FILE"
}

# force_copy - 强制复制文件或目录，覆盖目标位置
# 参数1: 源路径 (文件或目录)
# 参数2: 目标目录
force_copy() {
    local src="$1"
    local target_dir="$2"
    
    if [[ -z "$src" || -z "$target_dir" ]]; then
        warn "force_copy: Missing arguments"
        return 1
    fi
    
    if [[ -d "${src%/}" ]]; then
        (cd "$src" && find . -type d) | while read -r d; do
            as_user rm -f "$target_dir/$d" 2>/dev/null
        done
    fi
    
    exe as_user cp -rf "$src" "$target_dir"
}

# --- 3. 视觉组件 (TUI Style) ---
# TUI = Text User Interface (文本用户界面)

# 绘制大标题 (Section)
# 用于标记脚本执行的主要阶段，使用 Unicode 边框字符绘制
# 参数1: 主标题文本
# 参数2: 副标题/描述文本
section() {
    local title="$1"
    local subtitle="$2"
    echo ""
    # 绘制带圆角的边框，使用 Unicode Box Drawing 字符
    # ╭ = 左上角, ╮ = 右上角, ╰ = 左下角, ╯ = 右下角, │ = 垂直线, ─ = 水平线
    echo -e "${H_PURPLE}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${H_PURPLE}│${NC} ${BOLD}${H_WHITE}$title${NC}"
    echo -e "${H_PURPLE}│${NC} ${H_CYAN}$subtitle${NC}"
    echo -e "${H_PURPLE}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
    # 同时写入日志文件
    write_log "SECTION" "$title - $subtitle"
}

# 绘制键值对信息
# 用于显示格式化的配置信息，如 "Kernel: 6.1.0"
# 参数1: 键名 (如 Kernel)
# 参数2: 值 (如 6.1.0)
# 参数3: 额外说明文本 (可选，显示为暗色)
info_kv() {
    local key="$1"
    local val="$2"
    local extra="$3"
    # %-15s 表示左对齐，宽度为 15 个字符
    printf "   ${H_BLUE}●${NC} %-15s : ${BOLD}%s${NC} ${DIM}%s${NC}\n" "$key" "$val" "$extra"
    write_log "INFO" "$key=$val"
}

# 普通日志
# 用于输出一般性的信息，带有箭头前缀
# 参数1: 日志消息
log() {
    echo -e "   $ARROW $1"
    write_log "LOG" "$1"
}

# 成功日志
# 用于输出操作成功的信息，带有绿色对勾前缀
# 参数1: 成功消息
success() {
    echo -e "   $TICK ${H_GREEN}$1${NC}"
    write_log "SUCCESS" "$1"
}

# 警告日志 (突出显示)
# 用于输出警告信息，使用黄色高亮显示以引起注意
# 警告表示可能存在问题，但不会阻止脚本继续执行
# 参数1: 警告消息
warn() {
    echo -e "   $WARN ${H_YELLOW}${BOLD}WARNING:${NC} ${H_YELLOW}$1${NC}"
    write_log "WARN" "$1"
}

# 错误日志 (非常突出)
# 用于输出严重错误信息，使用红色边框包围以强调
# 错误通常表示操作失败，可能需要用户干预
# 参数1: 错误消息
error() {
    echo -e ""
    echo -e "${H_RED}   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${H_RED}   ┃  ERROR: $1${NC}"
    echo -e "${H_RED}   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e ""
    write_log "ERROR" "$1"
}

# --- 4. 核心：命令执行器 (Command Exec) ---

# exe - 带视觉反馈的命令执行器
# 功能:
#   1. 在终端中显示即将执行的命令 (类似 shell 提示符)
#   2. 执行命令并捕获退出状态码
#   3. 根据执行结果显示 OK 或 FAIL
#   4. 将命令和结果记录到日志文件
# 用法: exe <命令> [参数...]
# 示例: exe pacman -S --noconfirm vim
exe() {
    # $* 将所有参数合并为一个字符串 (用于显示)
    local full_command="$*"
    
    # Visual: 显示正在运行的命令
    # 绘制命令执行框的顶部边框，包含 EXEC 标签
    echo -e "   ${H_GRAY}┌──[ ${H_MAGENTA}EXEC${H_GRAY} ]────────────────────────────────────────────────────${NC}"
    # 显示要执行的命令，前面加 $ 符号模拟 shell 提示符
    echo -e "   ${H_GRAY}│${NC} ${H_CYAN}$ ${NC}${BOLD}$full_command${NC}"
    
    # 将命令写入日志
    write_log "EXEC" "$full_command"
    
    # Run the command
    # $@ 将所有参数作为独立的参数传递给命令 (保留空格等特殊字符)
    "$@" 
    # $? 保存上一条命令的退出状态码
    local status=$?
    
    # 根据退出状态码显示结果
    if [ $status -eq 0 ]; then
        # 退出码 0 表示成功，显示绿色 OK
        echo -e "   ${H_GRAY}└──────────────────────────────────────────────────────── ${H_GREEN}OK${H_GRAY} ─┘${NC}"
    else
        # 非零退出码表示失败，显示红色 FAIL
        echo -e "   ${H_GRAY}└────────────────────────────────────────────────────── ${H_RED}FAIL${H_GRAY} ─┘${NC}"
        write_log "FAIL" "Exit Code: $status"
        # 返回失败状态码，让调用者可以处理错误
        return $status
    fi
}

# 静默执行
# 执行命令但不显示任何输出 (标准输出和标准错误都重定向到 /dev/null)
# 用于不需要用户关注的后台操作
# 用法: exe_silent <命令> [参数...]
exe_silent() {
    "$@" > /dev/null 2>&1
}

# --- 5. 可复用逻辑块 ---
# 这一部分定义了可以在多个脚本中复用的功能函数

# configure_nautilus_user - 配置 GNOME 文件管理器 (Nautilus) 的用户级设置
# 主要解决 NVIDIA 双显卡系统上 Nautilus 的兼容性问题:
#   1. GSK_RENDERER=gl: 强制使用 OpenGL 渲染器而非 Vulkan，解决某些 NVIDIA 驱动的渲染问题
#   2. GTK_IM_MODULE=fcitx: 启用 Fcitx 输入法支持
# 原理: 在用户目录创建一个覆盖系统配置的 .desktop 文件
configure_nautilus_user() {
  # 系统级 .desktop 文件路径
  local sys_file="/usr/share/applications/org.gnome.Nautilus.desktop"
  # 用户级应用程序目录 (~/.local/share/applications)
  local user_dir="$HOME_DIR/.local/share/applications"
  # 用户级 .desktop 文件路径
  local user_file="$user_dir/org.gnome.Nautilus.desktop"

  # 1. 检查系统文件是否存在
  if [ -f "$sys_file" ]; then

    local need_modify=0
    local env_vars="env"

    # --- 逻辑 1: Niri 检测 (输入法修复) ---
    if command -v niri >/dev/null 2>&1; then
        # 只要有 niri，就强制使用 fcitx 模块
        env_vars="$env_vars GTK_IM_MODULE=fcitx"
        need_modify=1
        log "检测到 Niri 环境，准备注入 GTK_IM_MODULE=fcitx"
    fi
    
    # --- 逻辑 2: 双显卡 NVIDIA 检测 (GSK 渲染修复) ---
    # 使用 lspci 列出所有 PCI 设备，过滤显卡 (VGA 或 3D 控制器)
    local gpu_count=$(lspci | grep -E -i "vga|3d" | wc -l)
    # 检测是否有 NVIDIA 显卡
    local has_nvidia=$(lspci | grep -E -i "nvidia" | wc -l)

    # 只有在双显卡且包含 NVIDIA 的情况下才应用修改
    # 这种配置通常是 Intel/AMD 核显 + NVIDIA 独显的笔记本
    if [ "$gpu_count" -gt 1 ] && [ "$has_nvidia" -gt 0 ]; then
        # 叠加 GSK 渲染变量
        env_vars="$env_vars GSK_RENDERER=gl"
        need_modify=1
        log "检测到双显卡 NVIDIA，准备注入 GSK_RENDERER=gl"

        # 额外操作: 创建 gsk.conf
        local env_conf_dir="$HOME_DIR/.config/environment.d"
        if [ ! -f "$env_conf_dir/gsk.conf" ]; then
            mkdir -p "$env_conf_dir"
            echo "GSK_RENDERER=gl" > "$env_conf_dir/gsk.conf"
            # 修复权限
            if [ -n "$TARGET_USER" ]; then
                chown -R "$TARGET_USER" "$env_conf_dir"
            fi
            log "已添加用户级环境变量配置: $env_conf_dir/gsk.conf"
        fi
    fi

    # --- 3. 执行修改 (如果命中了任意一个逻辑) ---
    if [ "$need_modify" -eq 1 ]; then
      
      # 准备目录并复制
      mkdir -p "$user_dir"
      cp "$sys_file" "$user_file"
      
      # 修复所有者
      if [ -n "$TARGET_USER" ]; then
          chown "$TARGET_USER" "$user_file"
      fi

      # 修改 Desktop 文件
      # env_vars 此时可能是:
      # - "env GTK_IM_MODULE=fcitx" (仅Niri)
      # - "env GSK_RENDERER=gl" (仅双显卡)
      # - "env GTK_IM_MODULE=fcitx GSK_RENDERER=gl" (两者都有)
      sed -i "s|^Exec=|Exec=$env_vars |" "$user_file"
      
      log "已生成 Nautilus 用户配置: $user_file (参数: $env_vars)"
      
    fi
  fi
  
}

# hide_desktop_file - 隐藏指定的桌面文件 (Desktop Entry)
# 通过在用户目录创建一个覆盖系统级 .desktop 文件，并添加 NoDisplay=true
# 来隐藏不需要的应用程序图标
hide_desktop_file() {
    local source_file="$1"
    local filename=$(basename "$source_file")
    local user_dir="$HOME_DIR/.local/share/applications"
    local target_file="$user_dir/$filename"
    
    mkdir -p "$user_dir"
    
    if [[ -f "$source_file" ]]; then
        cp -fv "$source_file" "$target_file"
        if grep -q "^NoDisplay=" "$target_file"; then
            sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$target_file"
        else
            echo "NoDisplay=true" >> "$target_file"
        fi
        chown "$TARGET_USER:" "$target_file"
    fi
}

# run_hide_desktop_file - 批量隐藏一系列不需要的桌面图标
run_hide_desktop_file() {
    
    local apps_to_hide=(
        "avahi-discover.desktop"
        "qv4l2.desktop"
        "qvidcap.desktop"
        "bssh.desktop"
        "org.fcitx.Fcitx5.desktop"
        "org.fcitx.fcitx5-migrator.desktop"
        "xgps.desktop"
        "xgpsspeed.desktop"
        "gvim.desktop"
        "kbd-layout-viewer5.desktop"
        "bvnc.desktop"
        "yazi.desktop"
        "btop.desktop"
        "vim.desktop"
        "nvim.desktop"
        "nvtop.desktop"
        "mpv.desktop"
        "org.gnome.Settings.desktop"
        "thunar-settings.desktop"
        "thunar-bulk-rename.desktop"
        "thunar-volman-settings.desktop"
        "clipse-gui.desktop"
        "waypaper.desktop"
        "xfce4-about.desktop"
        "cmake-gui.desktop"
        "assistant.desktop"
        "qdbusviewer.desktop"
        "linguist.desktop"
        "designer.desktop"
        "org.kde.drkonqi.coredump.gui.desktop"
        "org.kde.kwrite.desktop"
        "org.freedesktop.MalcontentControl.desktop"
        "org.gnome.Nautilus.desktop"
    )
    
    echo "正在隐藏不需要的桌面图标..."
    
    # 用一个 for 循环搞定所有调用
    for app in "${apps_to_hide[@]}"; do
        hide_desktop_file "/usr/share/applications/$app"
    done
    chown -R "$TARGET_USER:" "$HOME_DIR/.local/share/applications"
    
    echo "图标隐藏完成！"
}
