#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop, Dotfiles & User Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

# --- Debug Configuration ---
DEBUG=${DEBUG:-0}

check_root

log ">>> Starting Phase 4: Niri Environment & Dotfiles Setup"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Step 0/9: Identify User"

DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
    log "-> Automatically detected target user: $TARGET_USER"
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
log "-> Installing configurations for: $TARGET_USER ($HOME_DIR)"

# ------------------------------------------------------------------------------
# [SAFETY CHECK] Detect Existing Display Managers
# ------------------------------------------------------------------------------
log "[SAFETY CHECK] Checking for active Display Managers..."

DMS=("gdm" "sddm" "lightdm" "lxdm" "ly")
SKIP_AUTOLOGIN=false

for dm in "${DMS[@]}"; do
    if systemctl is-enabled "$dm.service" &>/dev/null; then
        echo -e "${YELLOW}[INFO] Detected active Display Manager: $dm${NC}"
        echo -e "${YELLOW}[INFO] Niri will be added to the session list in $dm.${NC}"
        echo -e "${YELLOW}[INFO] TTY auto-login configuration will be SKIPPED to avoid conflicts.${NC}"
        SKIP_AUTOLOGIN=true
        break
    fi
done

if [ "$SKIP_AUTOLOGIN" = false ]; then
    log "-> No active Display Manager detected. Will configure TTY auto-login."
fi

# ------------------------------------------------------------------------------
# 1. Install Niri & Essentials (+ Firefox Policy)
# ------------------------------------------------------------------------------
log "Step 1/9: Installing Niri, core components and pciutils..."
# Added pciutils for GPU detection later
pacman -S --noconfirm --needed niri xwayland-satellite xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome pciutils > /dev/null 2>&1
success "Niri core packages installed."

# --- [NEW] Firefox Extension Auto-Install (Pywalfox) ---
log "-> Configuring Firefox Enterprise Policies (Pywalfox)..."
FIREFOX_POLICY_DIR="/etc/firefox/policies"
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
success "Firefox policy created."

# ------------------------------------------------------------------------------
# 2. File Manager (Nautilus) Setup (Smart GPU Env)
# ------------------------------------------------------------------------------
log "Step 2/9: Configuring Nautilus and Terminal..."

pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus > /dev/null 2>&1

# Symlink Kitty
if [ -f /usr/bin/gnome-terminal ] && [ ! -L /usr/bin/gnome-terminal ]; then
    warn "/usr/bin/gnome-terminal is a real file. Skipping symlink."
else
    log "-> Symlinking kitty to gnome-terminal..."
    ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Patch Nautilus (.desktop)
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    log "-> Detecting GPU configuration for Nautilus environment variables..."
    
    # Default vars
    ENV_VARS="env GTK_IM_MODULE=fcitx"
    
    # Check for Dual GPU + Nvidia
    # 1. Count VGA/3D controllers
    GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
    # 2. Check for Nvidia
    HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
    
    if [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ]; then
        log "-> Dual GPU with Nvidia detected ($GPU_COUNT GPUs). Enabling GSK_RENDERER=gl..."
        ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"
    else
        log "-> Single GPU or non-Nvidia setup. Using standard GTK vars..."
    fi
    
    log "-> Patching Nautilus .desktop with: $ENV_VARS"
    sed -i "s/^Exec=/Exec=$ENV_VARS /" "$DESKTOP_FILE"
fi

# ------------------------------------------------------------------------------
# 3. Smart Network Optimization
# ------------------------------------------------------------------------------
log "Step 3/9: Configuring Network Sources..."

pacman -S --noconfirm --needed flatpak gnome-software > /dev/null 2>&1
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

log "-> Checking System Timezone..."
CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false

# Debug Override
if [ "$DEBUG" == "1" ]; then
    warn "DEBUG MODE ACTIVE: Forcing China network optimizations."
    CURRENT_TZ="Asia/Shanghai (Simulated)"
fi

if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
    IS_CN_ENV=true
    log "-> Detected Timezone: ${H_GREEN}Asia/Shanghai${NC}"
    log "-> Applying China optimizations..."
    
    flatpak remote-modify flathub --url=https://mirrors.ustc.edu.cn/flathub
    
    export GOPROXY=https://goproxy.cn,direct
    if ! grep -q "GOPROXY" /etc/environment; then
        echo "GOPROXY=https://goproxy.cn,direct" >> /etc/environment
    fi
    
    log "-> Enabling GitHub Mirror (gitclone.com)..."
    runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
    
    success "Optimizations Enabled."
else
    log "-> Using official sources."
fi

# ------------------------------------------------------------------------------
# [TRICK] NOPASSWD for yay
# ------------------------------------------------------------------------------
log "Configuring temporary NOPASSWD sudo access for '$TARGET_USER'..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 4. Install Dependencies
# ------------------------------------------------------------------------------
log "Step 4/9: Installing dependencies from niri-applist.txt..."

LIST_FILE="$PARENT_DIR/niri-applist.txt"
FAILED_PACKAGES=()

if [ -f "$LIST_FILE" ]; then
    mapfile -t PACKAGE_ARRAY < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | tr -d '\r')
    
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=""
        GIT_LIST=()

        for pkg in "${PACKAGE_ARRAY[@]}"; do
            if [ "$pkg" == "imagemagic" ]; then pkg="imagemagick"; fi
            
            # [Logic] We DO NOT skip awww-git here. We try to compile it first.
            if [[ "$pkg" == *"-git" ]]; then
                GIT_LIST+=("$pkg")
            else
                BATCH_LIST+="$pkg "
            fi
        done
        
        # --- Phase 1: Batch Install ---
        if [ -n "$BATCH_LIST" ]; then
            log "-> [Batch] Installing standard repository packages..."
            if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                if [ "$IS_CN_ENV" = true ]; then
                    warn "Batch install failed. Retrying Direct Connect..."
                    runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                    if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                        warn "Direct batch failed too. Moving to Split mode..."
                    else
                        success "Batch success (Direct Connection)."
                    fi
                else
                    warn "Batch failed. Moving to Split mode..."
                fi
            else
                success "Standard packages installed."
            fi
        fi

        # --- Phase 2: Git Install ---
        if [ ${#GIT_LIST[@]} -gt 0 ]; then
            log "-> [Slow] Installing '-git' packages..."
            for git_pkg in "${GIT_LIST[@]}"; do
                log "-> Installing: $git_pkg ..."
                if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                    warn "Install failed for '$git_pkg'. Toggling Git Mirror setting and Retrying..."
                    
                    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                    else
                        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                    fi
                    
                    if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                        error "Failed: $git_pkg"
                        FAILED_PACKAGES+=("$git_pkg")
                    else
                        success "Installed: $git_pkg (On Retry)"
                    fi
                else
                    success "Installed: $git_pkg"
                fi
            done
        fi
        
        # --- Recovery Phase ---
        log "Running Recovery Checks..."
        
        # Waybar Recovery
        if ! command -v waybar &> /dev/null; then
            warn "Waybar binary missing."
            log "-> Installing standard 'waybar' package..."
            pacman -S --noconfirm --needed waybar > /dev/null 2>&1 && success "Waybar recovered."
        fi

        # Awww Recovery (Local Binary Fallback -> User Space)
        if ! command -v awww &> /dev/null; then
            warn "Awww binary not found (AUR install failed)."
            
            LOCAL_BIN_AWWW="$PARENT_DIR/bin/awww"
            LOCAL_BIN_DAEMON="$PARENT_DIR/bin/awww-daemon"
            USER_BIN_DIR="$HOME_DIR/.local/bin"
            
            if [ -f "$LOCAL_BIN_AWWW" ] && [ -f "$LOCAL_BIN_DAEMON" ]; then
                log "-> Installing awww from LOCAL BINARIES to ${BOLD}~/.local/bin${NC}..."
                
                # Ensure dir exists as user
                runuser -u "$TARGET_USER" -- mkdir -p "$USER_BIN_DIR"
                
                # Copy as user (so permissions are correct)
                runuser -u "$TARGET_USER" -- cp "$LOCAL_BIN_AWWW" "$USER_BIN_DIR/awww"
                runuser -u "$TARGET_USER" -- cp "$LOCAL_BIN_DAEMON" "$USER_BIN_DIR/awww-daemon"
                
                # Make executable
                runuser -u "$TARGET_USER" -- chmod +x "$USER_BIN_DIR/awww" "$USER_BIN_DIR/awww-daemon"
                
                success "Awww recovered (User Space Binary)."
            else
                warn "Local binaries missing in $PARENT_DIR/bin. Will try Swaybg later."
            fi
        fi

        # Report
        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            DOCS_DIR="$HOME_DIR/Documents"
            REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
            if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
            printf "%s\n" "${FAILED_PACKAGES[@]}" > "$REPORT_FILE"
            chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
            echo -e "${RED}[ATTENTION] Failed packages list saved to: $REPORT_FILE${NC}"
        else
            success "All dependencies installed successfully!"
        fi

    else
        warn "niri-applist.txt is empty."
    fi
else
    warn "niri-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Clone Dotfiles
# ------------------------------------------------------------------------------
log "Step 5/9: Cloning and applying dotfiles..."

REPO_URL="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"
rm -rf "$TEMP_DIR"

log "-> Cloning repository..."

if ! runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then
    warn "Clone failed. Toggling Git Mirror setting and Retrying..."
    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
    else
        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
    fi
    
    if ! runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then
        error "Clone failed on both Mirror and Direct connection."
    else
        success "Repository cloned successfully (On Retry)."
    fi
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
    BACKUP_NAME="config_backup_$(date +%s).tar.gz"
    log "-> [BACKUP] Backing up ~/.config to ~/$BACKUP_NAME..."
    runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    
    log "-> Applying new dotfiles..."
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"
    success "Dotfiles applied."
    
    if [ "$TARGET_USER" != "shorin" ]; then
        OUTPUT_KDL="$HOME_DIR/.config/niri/output.kdl"
        if [ -f "$OUTPUT_KDL" ]; then
            log "-> Clearing output.kdl for generic user..."
            runuser -u "$TARGET_USER" -- truncate -s 0 "$OUTPUT_KDL"
        fi
    fi

    # --- [ULTIMATE FALLBACK] Check Awww status ---
    # Logic: If 'awww' is not in PATH (meaning yay failed AND local bin copy failed)
    # Check both system bin and user bin implicitly via command -v
    if ! runuser -u "$TARGET_USER" -- command -v awww &> /dev/null; then
        warn "Awww failed all install methods. Switching to swaybg..."
        pacman -S --noconfirm --needed swaybg > /dev/null 2>&1
        SCRIPT_PATH="$HOME_DIR/.config/scripts/niri_set_overview_blur_dark_bg.sh"
        if [ -f "$SCRIPT_PATH" ]; then
            sed -i 's/^WALLPAPER_BACKEND="awww"/WALLPAPER_BACKEND="swaybg"/' "$SCRIPT_PATH"
            success "Switched backend to swaybg."
        fi
    fi
else
    warn "Dotfiles directory missing. Configuration skipped."
fi

# ------------------------------------------------------------------------------
# 6. Wallpapers
# ------------------------------------------------------------------------------
log "Step 6/9: Setting up Wallpapers..."
WALL_DEST="$HOME_DIR/Pictures/Wallpapers"

if [ -d "$TEMP_DIR/wallpapers" ]; then
    runuser -u "$TARGET_USER" -- mkdir -p "$WALL_DEST"
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/wallpapers/." "$WALL_DEST/"
    success "Wallpapers installed."
fi
rm -rf "$TEMP_DIR"

# ------------------------------------------------------------------------------
# 7. DDCUtil
# ------------------------------------------------------------------------------
log "Step 7/9: Configuring ddcutil..."
runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed ddcutil-service > /dev/null 2>&1
gpasswd -a "$TARGET_USER" i2c

# ------------------------------------------------------------------------------
# 8. SwayOSD
# ------------------------------------------------------------------------------
log "Step 8/9: Installing SwayOSD..."
pacman -S --noconfirm --needed swayosd > /dev/null 2>&1
systemctl enable --now swayosd-libinput-backend.service > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [CLEANUP] Remove temporary configs
# ------------------------------------------------------------------------------
log "Step 9/9: Restoring configuration (Cleanup)..."

rm -f "$SUDO_TEMP_FILE"
runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
sed -i '/GOPROXY=https:\/\/goproxy.cn,direct/d' /etc/environment

success "Cleanup complete."

# ------------------------------------------------------------------------------
# 10. Auto-Login & Niri Autostart
# ------------------------------------------------------------------------------
log "Step 10/9: Configuring Auto-login..."

if [ "$SKIP_AUTOLOGIN" = true ]; then
    echo -e "${YELLOW}[INFO] Existing Display Manager detected. Skipping TTY auto-login setup.${NC}"
else
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
    
    success "TTY Auto-login configured."
fi

log ">>> Phase 4 completed. REBOOT RECOMMENDED."