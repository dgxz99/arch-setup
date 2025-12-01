#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop, Dotfiles & User Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

# --- Configuration ---
DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}

check_root

# --- Helper Function: Local Package Fallback ---
install_local_fallback() {
    local pkg_name="$1"
    local search_dir="$PARENT_DIR/compiled/$pkg_name"
    
    # Check if directory exists
    if [ ! -d "$search_dir" ]; then
        return 1
    fi
    
    # Find the first .pkg.tar.zst file
    local pkg_file=$(find "$search_dir" -maxdepth 1 -name "*.pkg.tar.zst" | head -n 1)
    
    if [ -f "$pkg_file" ]; then
        warn "Network install failed. Found local pre-compiled package."
        log "-> Installing from: ${BOLD}$(basename "$pkg_file")${NC}..."
        
        # Use yay -U to handle dependencies automatically
        # Note: We run as user so yay can resolve AUR deps if needed
        cmd "yay -U $pkg_file"
        if runuser -u "$TARGET_USER" -- yay -U --noconfirm "$pkg_file"; then
            success "Installed from local backup."
            return 0
        else
            error "Local package install failed."
            return 1
        fi
    else
        return 1
    fi
}

log ">>> Starting Phase 4: Niri Environment & Dotfiles Setup"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Step 0/9: Identify User"

DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
    log "-> Automatically detected target user: ${BOLD}$TARGET_USER${NC}"
else
    warn "Could not detect a standard user (UID 1000)."
    while true; do
        read -p "Please enter the target username: " TARGET_USER
        if id "$TARGET_USER" &>/dev/null; then
            break
        else
            warn "User '$TARGET_USER' does not exist."
        fi
    done
fi

HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"
info_kv "Home"   "$HOME_DIR"

# ------------------------------------------------------------------------------
# [SAFETY CHECK] Detect Existing Display Managers
# ------------------------------------------------------------------------------
log "[SAFETY CHECK] Checking for active Display Managers..."

DMS=("gdm" "sddm" "lightdm" "lxdm" "ly")
SKIP_AUTOLOGIN=false

for dm in "${DMS[@]}"; do
    if systemctl is-enabled "$dm.service" &>/dev/null; then
        info_kv "DM Detected" "$dm" "${H_YELLOW}(Active)${NC}"
        warn "TTY auto-login configuration will be SKIPPED to avoid conflicts."
        SKIP_AUTOLOGIN=true
        break
    fi
done

if [ "$SKIP_AUTOLOGIN" = false ]; then
    log "-> No active DM. TTY auto-login will be configured."
fi

# ------------------------------------------------------------------------------
# 1. Install Niri & Essentials (+ Firefox Policy)
# ------------------------------------------------------------------------------
section "Step 1/9" "Installing Niri Core & Essentials"

PKGS="niri xwayland-satellite xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome pciutils"
cmd "pacman -S $PKGS"
pacman -S --noconfirm --needed $PKGS > /dev/null 2>&1
success "Niri core packages installed."

# --- Firefox Extension Auto-Install (Pywalfox) ---
log "Configuring Firefox Enterprise Policies..."
FIREFOX_POLICY_DIR="/etc/firefox/policies"
cmd "mkdir -p $FIREFOX_POLICY_DIR"
mkdir -p "$FIREFOX_POLICY_DIR"

cat <<EOT > "$FIREFOX_POLICY_DIR/policies.json"
{
  "policies": {
    "Extensions": {
      "InstallOrUpdate": [
        "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"
      ]
    }
  }
}
EOT
success "Firefox Pywalfox policy applied."

# ------------------------------------------------------------------------------
# 2. File Manager (Nautilus) Setup (Smart GPU Env)
# ------------------------------------------------------------------------------
section "Step 2/9" "File Manager & GPU Config"

cmd "pacman -S nautilus ffmpegthumbnailer..."
pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus > /dev/null 2>&1

# Symlink Kitty
if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then
    cmd "ln -sf /usr/bin/kitty /usr/bin/gnome-terminal"
    ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Patch Nautilus (.desktop)
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    log "Detecting GPU configuration..."
    
    GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
    HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
    
    ENV_VARS="env GTK_IM_MODULE=fcitx"
    
    if [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ]; then
        info_kv "GPU Config" "Hybrid (Nvidia)" "-> Enabling GSK_RENDERER=gl"
        ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"
    else
        info_kv "GPU Config" "Standard" "-> Standard GTK vars only"
    fi
    
    cmd "sed -i ... $DESKTOP_FILE"
    sed -i "s/^Exec=/Exec=$ENV_VARS /" "$DESKTOP_FILE"
    success "Nautilus .desktop patched."
fi

# ------------------------------------------------------------------------------
# 3. Smart Network Optimization
# ------------------------------------------------------------------------------
section "Step 3/9" "Network Optimization"

pacman -S --noconfirm --needed flatpak gnome-software > /dev/null 2>&1
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Logic: CN_MIRROR env var OR Debug mode
IS_CN_ENV=false

if [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
    IS_CN_ENV=true
    if [ "$DEBUG" == "1" ]; then warn "DEBUG MODE ACTIVE"; fi
    
    log "Enabling China optimizations (Mirror/Proxy)..."
    
    # 1. Flatpak
    cmd "flatpak remote-modify flathub --url=ustc..."
    flatpak remote-modify flathub --url=https://mirrors.ustc.edu.cn/flathub
    
    # 2. GOPROXY
    cmd "export GOPROXY=https://goproxy.cn,direct"
    export GOPROXY=https://goproxy.cn,direct
    if ! grep -q "GOPROXY" /etc/environment; then
        echo "GOPROXY=https://goproxy.cn,direct" >> /etc/environment
    fi
    
    # 3. Git Mirror
    cmd "git config url.gitclone.com..."
    runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
    
    success "Optimizations Enabled."
else
    log "Using official sources."
fi

# ------------------------------------------------------------------------------
# [TRICK] NOPASSWD for yay
# ------------------------------------------------------------------------------
log "Configuring temporary sudo access..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 4. Install Dependencies
# ------------------------------------------------------------------------------
section "Step 4/9" "Installing Dependencies"

LIST_FILE="$PARENT_DIR/niri-applist.txt"
FAILED_PACKAGES=()

if [ -f "$LIST_FILE" ]; then
    mapfile -t PACKAGE_ARRAY < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | tr -d '\r')
    
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=""
        GIT_LIST=()

        for pkg in "${PACKAGE_ARRAY[@]}"; do
            [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
            
            # awww-git, waypaper-git etc. are allowed here.
            if [[ "$pkg" == *"-git" ]]; then
                GIT_LIST+=("$pkg")
            else
                BATCH_LIST+="$pkg "
            fi
        done
        
        # --- Phase 1: Batch Install ---
        if [ -n "$BATCH_LIST" ]; then
            log "Phase 1: Batch Install (Standard Pkgs)..."
            
            # Attempt 1
            if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                warn "Batch failed. Toggling Mirror and Retrying..."
                
                # Toggle Mirror
                if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                    runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                else
                    runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                fi
                
                # Attempt 2
                if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                    error "Batch install failed. Check logs."
                else
                    success "Batch installed (Retry)."
                fi
            else
                success "Batch installed."
            fi
        fi

        # --- Phase 2: Git Install (With Local Fallback) ---
        if [ ${#GIT_LIST[@]} -gt 0 ]; then
            log "Phase 2: Git Install (One-by-One)..."
            for git_pkg in "${GIT_LIST[@]}"; do
                cmd "yay -S $git_pkg"
                
                # Attempt 1
                if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                    warn "Failed. Toggling Mirror..."
                    
                    # Toggle Logic
                    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                    else
                        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                    fi
                    
                    # Attempt 2
                    if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                        
                        # --- [NEW] Local Package Fallback ---
                        warn "Network install failed for '$git_pkg'. Checking local compiled cache..."
                        if install_local_fallback "$git_pkg"; then
                            # Success via local file
                            :
                        else
                            error "Failed: $git_pkg (Network & Local both failed)"
                            FAILED_PACKAGES+=("$git_pkg")
                        fi
                    else
                        success "Installed $git_pkg (On Retry)"
                    fi
                else
                    success "Installed $git_pkg"
                fi
            done
        fi
        
        # --- Recovery Phase ---
        log "Running Recovery Checks..."
        
        # Waybar Recovery
        if ! command -v waybar &> /dev/null; then
            warn "Waybar missing. Installing stock package..."
            pacman -S --noconfirm --needed waybar > /dev/null 2>&1
        fi

        # Awww Recovery (Ultimate Check)
        # If install_local_fallback succeeded above, this should pass.
        # If it failed, we warn here and rely on Swaybg later.
        if ! command -v awww &> /dev/null; then
            warn "Awww not found. Will fallback to Swaybg in next step."
        fi

        # Failure Report
        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            DOCS_DIR="$HOME_DIR/Documents"
            REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
            if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
            printf "%s\n" "${FAILED_PACKAGES[@]}" > "$REPORT_FILE"
            chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
            warn "Some packages failed. List saved to: Documents/安装失败的软件.txt"
        fi
    fi
else
    warn "niri-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Clone Dotfiles
# ------------------------------------------------------------------------------
section "Step 5/9" "Deploying Dotfiles"

REPO_URL="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"
rm -rf "$TEMP_DIR"

log "Cloning repository..."
# Attempt 1
if ! runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then
    warn "Clone failed. Toggling Mirror..."
    # Toggle Logic
    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
    else
        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
    fi
    
    # Attempt 2
    if ! runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then
        error "Clone failed. Config deployment skipped."
    else
        success "Cloned successfully (Retry)."
    fi
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
    BACKUP_NAME="config_backup_$(date +%s).tar.gz"
    log "Backing up ~/.config..."
    runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    
    log "Applying dotfiles..."
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"
    success "Dotfiles applied."
    
    # Clean non-shorin config
    if [ "$TARGET_USER" != "shorin" ]; then
        OUTPUT_KDL="$HOME_DIR/.config/niri/output.kdl"
        if [ -f "$OUTPUT_KDL" ]; then
            log "Clearing output.kdl for generic user..."
            runuser -u "$TARGET_USER" -- truncate -s 0 "$OUTPUT_KDL"
        fi
    fi

    # Ultimate Fallback (Swaybg)
    if ! runuser -u "$TARGET_USER" -- command -v awww &> /dev/null; then
        warn "Awww not found. Switching backend to swaybg..."
        pacman -S --noconfirm --needed swaybg > /dev/null 2>&1
        SCRIPT_PATH="$HOME_DIR/.config/scripts/niri_set_overview_blur_dark_bg.sh"
        if [ -f "$SCRIPT_PATH" ]; then
            sed -i 's/^WALLPAPER_BACKEND="awww"/WALLPAPER_BACKEND="swaybg"/' "$SCRIPT_PATH"
            success "Switched to swaybg."
        fi
    fi
else
    warn "Dotfiles directory missing. Configuration skipped."
fi

# ------------------------------------------------------------------------------
# 6. Wallpapers
# ------------------------------------------------------------------------------
section "Step 6/9" "Wallpapers"
WALL_DEST="$HOME_DIR/Pictures/Wallpapers"

if [ -d "$TEMP_DIR/wallpapers" ]; then
    runuser -u "$TARGET_USER" -- mkdir -p "$WALL_DEST"
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/wallpapers/." "$WALL_DEST/"
    success "Wallpapers installed."
fi
rm -rf "$TEMP_DIR"

# ------------------------------------------------------------------------------
# 7. Drivers & Utils
# ------------------------------------------------------------------------------
section "Step 7/9" "Drivers & Tools"

# DDCUtil
cmd "yay -S ddcutil-service"
runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed ddcutil-service > /dev/null 2>&1
gpasswd -a "$TARGET_USER" i2c

# SwayOSD
cmd "pacman -S swayosd"
pacman -S --noconfirm --needed swayosd > /dev/null 2>&1
systemctl enable --now swayosd-libinput-backend.service > /dev/null 2>&1

success "Hardware tools configured."

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
section "Step 9/9" "Cleanup & Restore"

log "Removing temporary configs..."
rm -f "$SUDO_TEMP_FILE"
runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
sed -i '/GOPROXY=https:\/\/goproxy.cn,direct/d' /etc/environment

success "Cleanup done."

# ------------------------------------------------------------------------------
# 10. Auto-Login
# ------------------------------------------------------------------------------
section "Final" "Boot Configuration"

if [ "$SKIP_AUTOLOGIN" = true ]; then
    log "Existing DM detected. Auto-login skipped."
else
    log "Configuring TTY Auto-login..."
    
    GETTY_DIR="/etc/systemd/system/getty@tty1.service.d"
    mkdir -p "$GETTY_DIR"
    cat <<EOT > "$GETTY_DIR/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}
EOT

    USER_SYSTEMD_DIR="$HOME_DIR/.config/systemd/user"
    mkdir -p "$USER_SYSTEMD_DIR"
    cat <<EOT > "$USER_SYSTEMD_DIR/niri-autostart.service"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target

[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure

[Install]
WantedBy=default.target
EOT

    WANTS_DIR="$USER_SYSTEMD_DIR/default.target.wants"
    mkdir -p "$WANTS_DIR"
    ln -sf "../niri-autostart.service" "$WANTS_DIR/niri-autostart.service"
    
    chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.config/systemd"
    success "Auto-login configured."
fi

log "Module 04 completed."