#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
STATE_FILE="$PARENT_DIR/.install_progress"

source "$SCRIPT_DIR/00-utils.sh"

check_root

export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}

section "Phase 1" "Pre-Flight Checks"

# --- Reflector 镜像源优化 (支持状态记忆) ---
section "Step 1/3" "Mirrorlist Optimization"

if grep -q "^REFLECTOR_DONE$" "$STATE_FILE" 2>/dev/null; then
    echo -e "   ${H_GREEN}✔${NC} Mirrorlist previously optimized."
    echo -e "   ${DIM}   Skipping Reflector steps (Resume Mode)...${NC}"
else
    log "Checking Reflector..."
    exe pacman -S --noconfirm --needed reflector

    CURRENT_TZ=$(readlink -f /etc/localtime)
    REFLECTOR_ARGS="--protocol https -a 12 -f 10 --sort rate --save /etc/pacman.d/mirrorlist --verbose"

    if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
        echo ""
        echo -e "${H_YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${H_YELLOW}║  DETECTED TIMEZONE: Asia/Shanghai                                ║${NC}"
        echo -e "${H_YELLOW}║  Refreshing mirrors in China can be slow.                        ║${NC}"
        echo -e "${H_YELLOW}║  Do you want to force refresh mirrors with Reflector?            ║${NC}"
        echo -e "${H_YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""

        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector? [y/N] (Default No in 60s): ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi
        choice=${choice:-N}

        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log "Running Reflector for China..."
            if exe reflector $REFLECTOR_ARGS -c China; then
                success "Mirrors updated."
            else
                warn "Reflector failed. Continuing with existing mirrors."
            fi
        else
            log "Skipping mirror refresh."
        fi
    else
        log "Detecting location for optimization..."
        COUNTRY_CODE=$(curl -s --max-time 2 https://ipinfo.io/country)

        if [ -n "$COUNTRY_CODE" ]; then
            info_kv "Country" "$COUNTRY_CODE" "(Auto-detected)"
            log "Running Reflector for $COUNTRY_CODE..."
            if ! exe reflector $REFLECTOR_ARGS -c "$COUNTRY_CODE"; then
                warn "Country specific refresh failed. Trying global speed test..."
                exe reflector $REFLECTOR_ARGS
            fi
        else
            warn "Could not detect country. Running global speed test..."
            exe reflector $REFLECTOR_ARGS --latest 25
        fi
        success "Mirrorlist optimized."
    fi

    echo "REFLECTOR_DONE" >> "$STATE_FILE"
fi

section "Step 2/3" "Update Keyring"
exe pacman -Sy
exe pacman -S --noconfirm archlinux-keyring

section "Step 3/3" "System Update"
log "Ensuring system is up-to-date..."

if exe pacman -Syu --noconfirm; then
    success "System updated."
else
    error "System update failed. Check your network."
    exit 1
fi
