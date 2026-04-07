#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root
section 'Optional 81' 'Flatpak Setup'

select_flathub_mirror() {
    local names=(
        "SJTU (Shanghai Jiao Tong)"
        "USTC (Univ of Sci & Tech of China)"
        "FlatHub Offical"
    )

    local urls=(
        "https://mirror.sjtu.edu.cn/flathub"
        "https://mirrors.ustc.edu.cn/flathub"
        "https://dl.flathub.org/repo/"
    )

    local max_len=0
    local title_text="Select Flathub Mirror (60s Timeout)"
    max_len=${#title_text}

    for name in "${names[@]}"; do
        local item_len=$((${#name} + 4 + 14))
        if (( item_len > max_len )); then
            max_len=$item_len
        fi
    done

    local menu_width=$((max_len + 4))
    echo ""

    local line_str=""
    printf -v line_str "%*s" "$menu_width" ""
    line_str=${line_str// /─}

    echo -e "${H_PURPLE}╭${line_str}╮${NC}"

    local title_padding_len=$(( (menu_width - ${#title_text}) / 2 ))
    local right_padding_len=$((menu_width - ${#title_text} - title_padding_len))
    local t_pad_l=""
    local t_pad_r=""
    printf -v t_pad_l "%*s" "$title_padding_len" ""
    printf -v t_pad_r "%*s" "$right_padding_len" ""

    echo -e "${H_PURPLE}│${NC}${t_pad_l}${BOLD}${title_text}${NC}${t_pad_r}${H_PURPLE}│${NC}"
    echo -e "${H_PURPLE}├${line_str}┤${NC}"

    for i in "${!names[@]}"; do
        local name="${names[$i]}"
        local display_idx=$((i + 1))
        local color_str=""
        local raw_str=""

        if [ "$i" -eq 0 ]; then
            raw_str=" [$display_idx] $name - Recommended"
            color_str=" ${H_CYAN}[$display_idx]${NC} ${name} - ${H_GREEN}Recommended${NC}"
        else
            raw_str=" [$display_idx] $name"
            color_str=" ${H_CYAN}[$display_idx]${NC} ${name}"
        fi

        local padding=$((menu_width - ${#raw_str}))
        local pad_str=""
        if [ "$padding" -gt 0 ]; then
            printf -v pad_str "%*s" "$padding" ""
        fi

        echo -e "${H_PURPLE}│${NC}${color_str}${pad_str}${H_PURPLE}│${NC}"
    done

    echo -e "${H_PURPLE}╰${line_str}╯${NC}"
    echo ""

    local choice
    read -t 60 -p "$(echo -e "   ${H_YELLOW}Enter choice [1-${#names[@]}]: ${NC}")" choice
    if [ $? -ne 0 ]; then echo ""; fi
    choice=${choice:-1}

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#names[@]}" ]; then
        log "Invalid choice or timeout. Defaulting to SJTU..."
        choice=1
    fi

    local index=$((choice-1))
    local selected_name="${names[$index]}"
    local selected_url="${urls[$index]}"

    log "Setting Flathub mirror to: ${H_GREEN}$selected_name${NC}"
    if exe flatpak remote-modify flathub --url="$selected_url"; then
        success "Mirror updated."
    else
        error "Failed to update mirror."
    fi
}

# ------------------------------------------------------------------------------
# flatpak
# ------------------------------------------------------------------------------
# Flatpak 是一个跨发行版的应用程序打包格式
# 优势：
#   - 应用程序与系统库隔离，更安全
#   - 可以运行不同版本的同一应用
#   - Flathub 仓库有大量应用
exe pacman -S --noconfirm --needed flatpak
# 添加 Flathub 远程仓库
# --if-not-exists: 如果已存在则跳过
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 检测是否为中国用户，如果是则使用国内镜像
CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false
# 检查时区是否为上海，或手动设置了 CN_MIRROR 环境变量
if [[ "$CURRENT_TZ" == *"Shanghai"* ]] || [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
  IS_CN_ENV=true
  info_kv "Region" "China Optimization Active"
fi

if [ "$IS_CN_ENV" = true ]; then
  # 调用 00-utils.sh 中定义的 Flathub 镜像选择函数
  select_flathub_mirror
else
  log "Using Global Sources."
fi

log "Module 81 completed."
