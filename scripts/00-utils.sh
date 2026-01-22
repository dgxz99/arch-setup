#!/bin/bash

# ==============================================================================
# 00-utils.sh - The "TUI" Visual Engine (v4.0)
# ==============================================================================
# 这是 Shorin Arch Setup 的核心工具库，提供：
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
export TEMP_LOG_FILE="/tmp/log-shorin-arch-setup.txt"
# 如果日志文件不存在，则创建它并设置权限为 666 (所有人可读写)
[ ! -f "$TEMP_LOG_FILE" ] && touch "$TEMP_LOG_FILE" && chmod 666 "$TEMP_LOG_FILE"

# --- 2. 基础工具 ---
# 这一部分定义了脚本运行所需的基础工具函数

# 检查是否以 root 权限运行
# 许多系统级操作 (如安装软件包、修改系统配置) 需要 root 权限
check_root() {
    # $EUID 是 Bash 内置变量，表示当前用户的有效用户 ID
    # root 用户的 EUID 为 0
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}   $CROSS CRITICAL ERROR: Script must be run as root.${NC}"
        exit 1
    fi
}

# 写入日志函数
# 参数1: 日志级别 (如 LOG, SUCCESS, ERROR, WARN 等)
# 参数2: 日志消息内容
write_log() {
    # Strip ANSI colors for log file
    local clean_msg=$(echo -e "$2" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%H:%M:%S')] [$1] $clean_msg" >> "$TEMP_LOG_FILE"
}

# --- 3. 视觉组件 (TUI Style) ---
# TUI = Text User Interface (文本用户界面)
# 这一部分定义了各种美化输出的函数，使脚本输出更加清晰美观

# 绘制分割线
# 使用 Unicode 字符 '─' 绘制一条横跨整个终端宽度的分割线
hr() {
    # %*s 表示使用指定宽度的空格填充
    # ${COLUMNS:-80} 获取终端宽度，默认为 80 列
    # tr ' ' '─' 将所有空格替换为横线字符
    printf "${H_GRAY}%*s${NC}\n" "${COLUMNS:-80}" '' | tr ' ' '─'
}

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

# 动态选择 Flathub 镜像源 (修复版：使用 echo -e 处理颜色变量)
# Flathub 是 Flatpak 应用程序的主要仓库
# 由于国内访问官方源速度较慢，提供国内镜像源选择
# 功能:
#   1. 显示一个交互式菜单让用户选择镜像源
#   2. 支持 60 秒超时，默认选择第一个 (SJTU)
#   3. 自动配置 flatpak remote
select_flathub_mirror() {
    # 1. 索引数组保证顺序
    # 镜像源名称数组
    local names=(
        "SJTU (Shanghai Jiao Tong)"            # 上海交通大学镜像
        "USTC (Univ of Sci & Tech of China)"   # 中国科学技术大学镜像
        "FlatHub Offical"                       # 官方源
    )
    
    # 对应的 URL 数组 (与 names 数组一一对应)
    local urls=(
        "https://mirror.sjtu.edu.cn/flathub"
        "https://mirrors.ustc.edu.cn/flathub"
        "https://dl.flathub.org/repo/"
    )

    # 2. 动态计算菜单宽度 (基于无颜色的纯文本)
    # 为了让菜单看起来整齐，需要计算所有选项中最长的文本
    local max_len=0
    local title_text="Select Flathub Mirror (60s Timeout)"
    
    # 首先以标题长度作为基准
    max_len=${#title_text}

    # 遍历所有选项名称，找出最长的
    for name in "${names[@]}"; do
        # 预估显示长度："[x] Name - Recommended"
        # +4 是 "[x] " 的长度，+14 是 " - Recommended" 的长度
        local item_len=$((${#name} + 4 + 14)) 
        if (( item_len > max_len )); then
            max_len=$item_len
        fi
    done

    # 菜单总宽度 = 最长内容 + 4 (左右边距各 2 个空格)
    local menu_width=$((max_len + 4))

    # --- 3. 渲染菜单 (使用 echo -e 确保颜色变量被解析) ---
    echo ""
    
    # 生成横线
    # printf -v 将输出存入变量而不是打印
    # %*s 生成指定宽度的空格
    local line_str=""
    printf -v line_str "%*s" "$menu_width" ""
    # 使用 Bash 字符串替换，将所有空格替换为横线字符
    line_str=${line_str// /─}

    # 打印顶部边框 (╭ + 横线 + ╮)
    echo -e "${H_PURPLE}╭${line_str}╮${NC}"

    # 打印标题 (计算居中填充)
    # 居中算法: 左边距 = (总宽度 - 文本宽度) / 2
    local title_padding_len=$(( (menu_width - ${#title_text}) / 2 ))
    # 右边距处理奇数宽度的情况
    local right_padding_len=$((menu_width - ${#title_text} - title_padding_len))
    
    # 生成填充空格
    local t_pad_l=""; printf -v t_pad_l "%*s" "$title_padding_len" ""
    local t_pad_r=""; printf -v t_pad_r "%*s" "$right_padding_len" ""
    
    # 打印居中的标题行
    echo -e "${H_PURPLE}│${NC}${t_pad_l}${BOLD}${title_text}${NC}${t_pad_r}${H_PURPLE}│${NC}"

    # 打印中间分隔线 (├ + 横线 + ┤)
    echo -e "${H_PURPLE}├${line_str}┤${NC}"

    # 打印选项
    # ${!names[@]} 获取数组的所有索引 (0, 1, 2...)
    for i in "${!names[@]}"; do
        local name="${names[$i]}"
        # 显示编号从 1 开始 (对用户更友好)
        local display_idx=$((i+1))
        
        # 1. 构造用于显示的带颜色字符串
        local color_str=""
        # 2. 构造用于计算长度的无颜色字符串
        # 需要两个版本是因为颜色转义码会影响字符串长度计算
        local raw_str=""

        # 第一个选项 (索引 0) 显示 "Recommended" 标签
        if [ "$i" -eq 0 ]; then
            raw_str=" [$display_idx] $name - Recommended"
            color_str=" ${H_CYAN}[$display_idx]${NC} ${name} - ${H_GREEN}Recommended${NC}"
        else
            raw_str=" [$display_idx] $name"
            color_str=" ${H_CYAN}[$display_idx]${NC} ${name}"
        fi

        # 计算右侧填充空格
        # 使用 raw_str (不含颜色码) 计算实际显示宽度
        local padding=$((menu_width - ${#raw_str}))
        local pad_str=""; 
        if [ "$padding" -gt 0 ]; then
            printf -v pad_str "%*s" "$padding" ""
        fi
        
        # 打印：边框 + 内容 + 填充 + 边框
        echo -e "${H_PURPLE}│${NC}${color_str}${pad_str}${H_PURPLE}│${NC}"
    done

    # 打印底部边框 (╰ + 横线 + ╯)
    echo -e "${H_PURPLE}╰${line_str}╯${NC}"
    echo ""

    # --- 4. 用户交互 ---
    local choice
    # 提示符
    # read -t 60: 设置 60 秒超时
    # read -p: 显示提示符
    # $(echo -e ...): 使用子 shell 解析颜色代码
    read -t 60 -p "$(echo -e "   ${H_YELLOW}Enter choice [1-${#names[@]}]: ${NC}")" choice
    # 如果 read 超时或被中断，$? 不为 0，打印换行符保持格式
    if [ $? -ne 0 ]; then echo ""; fi
    # 如果用户未输入 (直接回车)，默认选择 1
    choice=${choice:-1}
    
    # 验证输入：必须是数字，且在有效范围内
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#names[@]}" ]; then
        log "Invalid choice or timeout. Defaulting to SJTU..."
        choice=1
    fi

    # 将用户选择 (1-based) 转换为数组索引 (0-based)
    local index=$((choice-1))
    local selected_name="${names[$index]}"
    local selected_url="${urls[$index]}"

    log "Setting Flathub mirror to: ${H_GREEN}$selected_name${NC}"
    
    # 执行修改 (仅修改 flathub，不涉及 github)
    # flatpak remote-modify 命令用于修改远程仓库的配置
    if exe flatpak remote-modify flathub --url="$selected_url"; then
        success "Mirror updated."
    else
        error "Failed to update mirror."
    fi
}

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
    
    # 2. 显卡检测逻辑
    # 使用 lspci 列出所有 PCI 设备，过滤显卡 (VGA 或 3D 控制器)
    local gpu_count=$(lspci | grep -E -i "vga|3d" | wc -l)
    # 检测是否有 NVIDIA 显卡
    local has_nvidia=$(lspci | grep -E -i "nvidia" | wc -l)

    # 只有在双显卡且包含 NVIDIA 的情况下才应用修改
    # 这种配置通常是 Intel/AMD 核显 + NVIDIA 独显的笔记本
    if [ "$gpu_count" -gt 1 ] && [ "$has_nvidia" -gt 0 ]; then
      
      # 定义需要注入的环境变量
      # env 命令用于在指定环境变量下运行程序
      local env_vars="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"

      # 3. 准备用户目录并复制文件
      mkdir -p "$user_dir"
      cp "$sys_file" "$user_file"
      # 修改文件所有者为目标用户 (因为当前是 root 在操作)
      chown "$TARGET_USER" "$user_file"
      # 4. 修改用户目录下的文件
      # sed -i: 原地修改文件
      # 将 "Exec=" 替换为 "Exec=env GSK_RENDERER=gl GTK_IM_MODULE=fcitx "
      # 这样启动 Nautilus 时会自动带上这些环境变量
      sed -i "s|^Exec=|Exec=$env_vars |" "$user_file"
      
      log "已创建用户级 Nautilus 配置: $user_file"

      # 5. 添加用户级环境变量配置
      # environment.d 目录下的 .conf 文件会被 systemd 用户会话加载
      local env_conf_dir="$HOME_DIR/.config/environment.d"
      if [ ! -f "$env_conf_dir/gsk.conf" ]; then
          mkdir -p "$env_conf_dir"
          # 创建配置文件，设置 GSK_RENDERER 环境变量
          echo "GSK_RENDERER=gl" > "$env_conf_dir/gsk.conf"
          log "已添加用户级环境变量配置: $env_conf_dir/gsk.conf"
      fi
      
    fi
  fi
  
}
