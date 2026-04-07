#!/usr/bin/env bash

# 语言与输入法模块。
# 和桌面本身分离，避免 GNOME 与 Niri 各自重复处理 locale / fcitx5。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root
section 'Phase 7' 'Locale and Input Method'

# ------------------------------------------------------------------------------
# 1. Locale
# ------------------------------------------------------------------------------
# 语言区域配置：Locale 决定了系统的语言、日期格式、数字格式等，中文用户需要启用 zh_CN.UTF-8

section "Step 1/2" "Locale Configuration"

# 标记是否需要重新生成
NEED_GENERATE=false

# --- 1. 检测 en_US.UTF-8 ---
if locale -a | grep -iq "en_US.utf8"; then
    success "English locale (en_US.UTF-8) is active."
else
    log "Enabling en_US.UTF-8..."
    # 使用 sed 取消注释
    sed -i 's/^#\s*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    NEED_GENERATE=true
fi

# --- 2. 检测 zh_CN.UTF-8 ---
if locale -a | grep -iq "zh_CN.utf8"; then
    success "Chinese locale (zh_CN.UTF-8) is active."
else
    log "Enabling zh_CN.UTF-8..."
    # 使用 sed 取消注释
    sed -i 's/^#\s*zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    NEED_GENERATE=true
fi

# --- 3. 如果有修改，统一执行生成 ---
if [ "$NEED_GENERATE" = true ]; then
    log "Generating locales (this may take a moment)..."
    if exe locale-gen; then
        success "Locales generated successfully."
    else
        error "Locale generation failed."
    fi
else
    success "All locales are already up to date."
fi

# ------------------------------------------------------------------------------
# 2. Input Method
# ------------------------------------------------------------------------------
# 输入法安装
# Fcitx5 是现代的 Linux 输入法框架，支持中文、日文等多种语言
# fcitx5-im: Fcitx5 核心组件元包
# fcitx5-chinese-addons: 中文输入法插件 (包含拼音、五笔等)
# fcitx5-mozc: 日文输入法 (Mozc)
section "Step 2/2" "Input Method (Fcitx5)"
exe pacman -S --noconfirm --needed fcitx5-im fcitx5-rime rime-ice-git
success "Fcitx5 installed."

log "Module 07 completed."
