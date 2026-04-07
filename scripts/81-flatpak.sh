#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root
section 'Optional 81' 'Flatpak Setup'

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