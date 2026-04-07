#!/bin/bash

# ==============================================================================
# Command Center - 常用维护指令集
# ==============================================================================

# 定义菜单选项
OPT_SAVE="快速存档 (quicksave)"
OPT_LOAD="快速读档 (quickload)"
OPT_MIRROR="更新镜像源 (mirror-update)"
OPT_SYSUP="更新系统 (sysup)"
OPT_SHORIN="更新Shorin's Niri (shorin-update)"
OPT_CLEAN="系统清理 (clean)"

# 生成菜单内容 (注意顺序：Sysup 在 Shorin 上面)
OPTIONS="$OPT_SAVE\n$OPT_LOAD\n$OPT_MIRROR\n$OPT_SYSUP\n$OPT_SHORIN\n$OPT_CLEAN"

# 调用 Fuzzel 显示菜单
SELECTED=$(echo -e "$OPTIONS" | fuzzel --dmenu \
    -p "Shorin指令 > " \
    --placeholder "命令可手动运行" \
    --placeholder-color 80808099)

# 根据选择执行命令
case "$SELECTED" in
    "$OPT_SAVE")
        # 后台静默执行
        ~/.local/bin/quicksave &
        ;;
    "$OPT_LOAD")
        # 后台静默执行
        ~/.local/bin/quickload &
        ;;
    "$OPT_MIRROR")
        # 打开终端，结束后按任意键退出
        kitty --single-instance --class command-center --title "更新镜像源" bash -c "~/.local/bin/mirror-update; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_SYSUP")
        # [新增] 系统更新，打开终端
        kitty --single-instance --class command-center --title "系统更新" bash -c "~/.local/bin/sysup; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_SHORIN")
        # [修改] 明确为 Shorin 更新，打开终端
        kitty --single-instance --class command-center --title "Shorin更新" bash -c "~/.local/bin/shorin-update; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_CLEAN")
        # 打开终端
        kitty --single-instance --class command-center --title "系统清理" bash -c "~/.local/bin/clean; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
esac
