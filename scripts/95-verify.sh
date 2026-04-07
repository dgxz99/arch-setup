#!/usr/bin/env bash

# 验证模块
# Description:
#   1. 黑盒环境启发式验证 (dms / quickshell)。
#   2. 显式包发货单对账 (pacman -T)。
#   3. 用户配置文件/软链接部署完整性验证。
#   一旦任何一环发现缺失，立即中断并退出 (exit 1)。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

VERIFY_LIST='/tmp/daguo_install_verify.list'

check_root
section 'Phase 95' 'Verification'

# ==============================================================================
# 1. 清单统实验证 (发货单对账)
# ==============================================================================
if [ -f "$VERIFY_LIST" ]; then
    mapfile -t CHECK_PKGS < <(cat "$VERIFY_LIST" | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort -u)
    
    if [ ${#CHECK_PKGS[@]} -gt 0 ]; then
        log "Verifying ${#CHECK_PKGS[@]} explicit packages..."
        MISSING_PKGS=$(pacman -T "${CHECK_PKGS[@]}" 2>/dev/null)
        
        if [ -n "$MISSING_PKGS" ]; then
            echo ""
            error "SOFTWARE INSTALLATION INCOMPLETE!"
            echo -e "   ${DIM}The following packages failed to install:${NC}"
            echo "$MISSING_PKGS" | awk '{print "   \033[1;31m->\033[0m \033[1;33m" $0 "\033[0m"}'
            echo ""
            if declare -f write_log >/dev/null; then
                write_log "FATAL" "Missing packages: $(echo "$MISSING_PKGS" | tr '\n' ' ')"
            fi
            error "Cannot proceed with a broken desktop environment."
            echo -e "   ${H_YELLOW}>>> Exiting installer. Please check your network or AUR helpers. ${NC}"
            exit 1
        else
            success "All explicit packages successfully verified."
            rm -f "$VERIFY_LIST"
        fi
    fi
fi

# ==============================================================================
# 2. 配置文件部署验证
# ==============================================================================
log "Identifying target user for config audit..."
detect_target_user
if [[ -z "$TARGET_USER" ]]; then
    warn 'Could not detect target user. Skipping dotfiles audit.'
    exit 0
fi

HOME_DIR="/home/$TARGET_USER"
CONFIG_ERRORS=0
check_config_exists() {
    # -e 同时可识别常规文件/目录和有效软链接。
    local path="$1"
    if [[ ! -e "$path" ]]; then
        warn "$path is missing or broken"
        CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
    else
        log "[OK] $path"
    fi
}

log "Auditing dotfiles for ${DESKTOP_ENV^^}..."
case "$DESKTOP_ENV" in
    gnome)
        # GNOME 先做基础配置目录完整性检查。
        check_config_exists "$HOME_DIR/.config"
        check_config_exists "$HOME_DIR/.local/share"
        ;;
    dms-niri)
        # DMS+Niri 核心路径与壁纸目录检查。
        check_config_exists "$HOME_DIR/.config/niri"
        check_config_exists "$HOME_DIR/Pictures/Wallpapers"
        ;;
    *)
        log "No specific config checks mapped for $DESKTOP_ENV"
        ;;
esac

if [[ "$CONFIG_ERRORS" -gt 0 ]]; then
    echo ""
    error 'DOTFILES DEPLOYMENT FAILED!'
    write_log FATAL "Dotfiles audit failed. $CONFIG_ERRORS paths missing or broken."
    echo -e "   ${H_YELLOW}>>> Exiting installer. The repository clone or symlink step might have failed. ${NC}"
    exit 1
fi

success 'Configuration files and symlinks deployed correctly.'
exit 0

log "Module 95 completed."