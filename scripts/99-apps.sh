#!/bin/bash

# ==============================================================================
# 99-apps.sh - Common Applications Installation (Yay & Flatpak)
# ==============================================================================
# Features:
# - Install from common-applist.txt
# - Support 'yay' and 'flatpak' prefixes
# - Retry mechanism for stability
# - Ctrl+C to SKIP current app (Exit Code 130 handling)
# - Steam Chinese Locale Fix
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# --- Interrupt Handler ---
# Catch Ctrl+C (SIGINT), print message, and continue script execution
trap 'echo -e "\n${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping current item...${NC}"' INT

log ">>> Starting Phase 5: Common Applications Setup"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Step 0/4: Identify User"

DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
    log "-> Automatically detected target user: ${BOLD}$TARGET_USER${NC}"
else
    read -p "Please enter the target username: " TARGET_USER
fi

HOME_DIR="/home/$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. User Confirmation
# ------------------------------------------------------------------------------
echo ""
box_title "OPTIONAL: Common Applications" "${H_CYAN}"

echo -e "   This module reads from: ${BOLD}common-applist.txt${NC}"
echo -e "   Format: ${DIM}lines starting with 'flatpak:' use Flatpak, others use Yay.${NC}"
echo -e "   ${H_YELLOW}Tip: Press Ctrl+C during installation to skip a slow package.${NC}"
echo ""

read -p "$(echo -e ${H_YELLOW}"   Do you want to install these applications? [Y/n] "${NC})" choice
choice=${choice:-Y}

if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    log "User skipped application installation."
    trap - INT # Reset trap before exit
    exit 0
fi

hr

# ------------------------------------------------------------------------------
# 2. Parse App List
# ------------------------------------------------------------------------------
log "Step 2/4: Parsing application list..."

LIST_FILE="$PARENT_DIR/common-applist.txt"
YAY_APPS=()
FLATPAK_APPS=()
FAILED_PACKAGES=()

if [ -f "$LIST_FILE" ]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | tr -d '\r' | xargs)
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        if [[ "$line" == flatpak:* ]]; then
            app_id="${line#flatpak:}"
            FLATPAK_APPS+=("$app_id")
        else
            YAY_APPS+=("$line")
        fi
    done < "$LIST_FILE"
    
    log "-> Queue: ${BOLD}${#YAY_APPS[@]}${NC} Yay packages | ${BOLD}${#FLATPAK_APPS[@]}${NC} Flatpak packages."
else
    warn "File ${BOLD}common-applist.txt${NC} not found. Skipping."
    trap - INT
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Install Applications
# ------------------------------------------------------------------------------

# --- A. Install Yay Apps ---
if [ ${#YAY_APPS[@]} -gt 0 ]; then
    section "Step 3a/4" "Installing System Packages (Yay)"
    
    # Configure NOPASSWD
    SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_apps"
    echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
    chmod 440 "$SUDO_TEMP_FILE"
    
    BATCH_LIST="${YAY_APPS[*]}"
    log "Attempting batch install..."
    
    # Batch Attempt
    runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST
    batch_ret=$?
    
    if [ $batch_ret -eq 0 ]; then
        success "All system packages installed successfully."
    elif [ $batch_ret -eq 130 ]; then
        warn "Batch install interrupted by user. Switching to One-by-One mode to allow selective skipping..."
    else
        warn "Batch install failed. Switching to One-by-One mode..."
    fi
    
    # Fallback / Retry One-by-One
    if [ $batch_ret -ne 0 ]; then
        for pkg in "${YAY_APPS[@]}"; do
            cmd "yay -S $pkg"
            
            # Attempt 1
            if ! runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                ret=$?
                
                # Check if User Cancelled (130)
                if [ $ret -eq 130 ]; then
                    warn "Skipped '$pkg' (User Cancelled)."
                    continue # Skip retry, move to next app
                fi
                
                # Retry Attempt 2 (Only if not cancelled)
                warn "Failed to install '$pkg'. Retrying (Attempt 2/2)..."
                if ! runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                    ret_retry=$?
                    if [ $ret_retry -eq 130 ]; then
                        warn "Skipped '$pkg' during retry."
                    else
                        error "Failed to install: $pkg"
                        FAILED_PACKAGES+=("yay:$pkg")
                    fi
                else
                    success "Installed: $pkg (on retry)"
                fi
            else
                success "Installed: $pkg" 
            fi
        done
    fi
    
    rm -f "$SUDO_TEMP_FILE"
fi

# --- B. Install Flatpak Apps ---
if [ ${#FLATPAK_APPS[@]} -gt 0 ]; then
    section "Step 3b/4" "Installing Flatpak Packages"
    
    for app in "${FLATPAK_APPS[@]}"; do
        cmd "flatpak install $app"
        
        # Attempt 1
        if flatpak install -y flathub "$app" > /dev/null 2>&1; then
            success "Installed: $app"
        else
            ret=$?
            if [ $ret -eq 130 ]; then
                warn "Skipped '$app' (User Cancelled)."
                continue
            fi
            
            warn "Flatpak install failed for '$app'. Waiting 3s to Retry..."
            sleep 3
            
            # Attempt 2
            if flatpak install -y flathub "$app" > /dev/null 2>&1; then
                success "Installed: $app (on retry)"
            else
                ret_retry=$?
                if [ $ret_retry -eq 130 ]; then
                    warn "Skipped '$app' during retry."
                else
                    error "Failed to install Flatpak: $app"
                    FAILED_PACKAGES+=("flatpak:$app")
                fi
            fi
        fi
    done
fi

# ------------------------------------------------------------------------------
# 3.5 Generate Failure Report
# ------------------------------------------------------------------------------
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
    
    if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
    
    echo -e "\n--- Phase 5 (Common Apps) Failures ---" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
    
    echo -e "${H_RED}[ATTENTION]${NC} Some applications failed. Report updated at: ${BOLD}$REPORT_FILE${NC}"
else
    success "App installation phase completed."
fi

# ------------------------------------------------------------------------------
# 4. Steam Locale Fix
# ------------------------------------------------------------------------------
section "Step 4/4" "Game Environment Tweaks"

STEAM_desktop_modified=false

# Method 1: Native Steam
NATIVE_DESKTOP="/usr/share/applications/steam.desktop"
if [ -f "$NATIVE_DESKTOP" ]; then
    log "Checking Native Steam..."
    if ! grep -q "env LANG=zh_CN.UTF-8" "$NATIVE_DESKTOP"; then
        sed -i 's|^Exec=/usr/bin/steam|Exec=env LANG=zh_CN.UTF-8 /usr/bin/steam|' "$NATIVE_DESKTOP"
        sed -i 's|^Exec=steam|Exec=env LANG=zh_CN.UTF-8 steam|' "$NATIVE_DESKTOP"
        success "Patched Native Steam .desktop file."
        STEAM_desktop_modified=true
    else
        log "-> Native Steam already patched."
    fi
fi

# Method 2: Flatpak Steam
if echo "${FLATPAK_APPS[@]}" | grep -q "com.valvesoftware.Steam" || flatpak list | grep -q "com.valvesoftware.Steam"; then
    log "Checking Flatpak Steam..."
    flatpak override --env=LANG=zh_CN.UTF-8 com.valvesoftware.Steam
    success "Applied Flatpak Steam environment override."
    STEAM_desktop_modified=true
fi

if [ "$STEAM_desktop_modified" = false ]; then
    log "-> Steam not found. Skipping fix."
fi

# Reset Trap
trap - INT

log "Module 99-apps completed."