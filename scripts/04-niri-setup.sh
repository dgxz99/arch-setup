#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop, Dotfiles & User Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

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
# 1. Install Niri & Essentials
# ------------------------------------------------------------------------------
log "Step 1/9: Installing Niri and core components..."
pacman -S --noconfirm --needed niri xwayland-satellite xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome > /dev/null 2>&1
success "Niri core packages installed."

# ------------------------------------------------------------------------------
# 2. File Manager (Nautilus) Setup
# ------------------------------------------------------------------------------
log "Step 2/9: Configuring Nautilus and Terminal..."

pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus > /dev/null 2>&1

# Symlink Kitty to Gnome-Terminal (Safe Mode)
if [ -f /usr/bin/gnome-terminal ] && [ ! -L /usr/bin/gnome-terminal ]; then
    warn "/usr/bin/gnome-terminal is a real file. Skipping symlink."
else
    log "-> Symlinking kitty to gnome-terminal..."
    ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Patch Nautilus
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    log "-> Patching Nautilus .desktop file..."
    sed -i 's/^Exec=/Exec=env GSK_RENDERER=gl GTK_IM_MODULE=fcitx /' "$DESKTOP_FILE"
fi

# ------------------------------------------------------------------------------
# 3. Software Store
# ------------------------------------------------------------------------------
log "Step 3/9: Configuring Software Center..."
pacman -S --noconfirm --needed flatpak gnome-software > /dev/null 2>&1
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-modify flathub --url=https://mirror.sjtu.edu.cn/flathub > /dev/null 2>&1
success "Flatpak configured."

# ------------------------------------------------------------------------------
# [TRICK] NOPASSWD for yay
# ------------------------------------------------------------------------------
log "Configuring temporary NOPASSWD sudo access for '$TARGET_USER'..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 4. Install Dependencies (Split Strategy + Retry + Failure Report)
# ------------------------------------------------------------------------------
log "Step 4/9: Installing dependencies from niri-applist.txt..."

LIST_FILE="$PARENT_DIR/niri-applist.txt"
FAILED_PACKAGES=() # Initialize failure array

if [ -f "$LIST_FILE" ]; then
    mapfile -t PACKAGE_ARRAY < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | tr -d '\r')
    
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=""
        GIT_LIST=()

        # Sort packages
        for pkg in "${PACKAGE_ARRAY[@]}"; do
            if [ "$pkg" == "imagemagic" ]; then pkg="imagemagick"; fi
            
            if [[ "$pkg" == *"-git" ]]; then
                GIT_LIST+=("$pkg")
            else
                BATCH_LIST+="$pkg "
            fi
        done
        
        # --- Phase 1: Batch Install Standard Packages ---
        if [ -n "$BATCH_LIST" ]; then
            log "-> [Batch] Installing standard repository packages..."
            if runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                success "Standard packages installed."
            else
                warn "Batch install had issues. Attempting one-by-one with Retry..."
                for pkg in $BATCH_LIST; do
                    if runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                        :
                    else
                        warn "Failed to install '$pkg'. Retrying (Attempt 2/2)..."
                        if runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                             success "Installed '$pkg' on second attempt."
                        else
                             error "Failed to install '$pkg' after 2 attempts."
                             FAILED_PACKAGES+=("$pkg") # Record failure
                        fi
                    fi
                done
            fi
        fi

        # --- Phase 2: One-by-One Install Git Packages ---
        if [ ${#GIT_LIST[@]} -gt 0 ]; then
            log "-> [Slow] Installing ${#GIT_LIST[@]} '-git' packages individually..."
            for git_pkg in "${GIT_LIST[@]}"; do
                log "-> Compiling/Installing: $git_pkg ..."
                if runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                    success "Installed: $git_pkg"
                else
                    warn "Failed to install '$git_pkg'. Retrying (Attempt 2/2)..."
                    if runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                        success "Installed: $git_pkg (on retry)"
                    else
                        error "Failed to install: $git_pkg after 2 attempts."
                        FAILED_PACKAGES+=("$git_pkg") # Record failure
                    fi
                fi
            done
        fi
        
        # --- Report Generation Logic ---
        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            DOCS_DIR="$HOME_DIR/Documents"
            REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
            
            # Ensure Documents directory exists
            if [ ! -d "$DOCS_DIR" ]; then
                runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"
            fi
            
            log "Generating failure report..."
            # Print array to file
            printf "%s\n" "${FAILED_PACKAGES[@]}" > "$REPORT_FILE"
            # Give ownership to user
            chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
            
            echo -e "${RED}[ATTENTION] The following packages failed to install:${NC}"
            printf " - %s\n" "${FAILED_PACKAGES[@]}"
            echo -e "${YELLOW}A list has been saved to: $REPORT_FILE${NC}"
        else
            success "All dependencies installed successfully!"
        fi

    else
        warn "niri-applist.txt is empty."
    fi
else
    warn "niri-applist.txt not found. Skipping dependency installation."
fi

# ------------------------------------------------------------------------------
# 5. Clone Dotfiles
# ------------------------------------------------------------------------------
log "Step 5/9: Cloning and applying dotfiles..."

REPO_URL="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"
rm -rf "$TEMP_DIR"

log "-> Cloning repository..."
runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"

if [ -d "$TEMP_DIR/dotfiles" ]; then
    BACKUP_NAME="config_backup_$(date +%s).tar.gz"
    log "-> [BACKUP] Backing up existing ~/.config to ~/$BACKUP_NAME..."
    runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    
    log "-> Applying new dotfiles..."
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"
    success "Dotfiles applied."
else
    error "Directory 'dotfiles' not found in cloned repo."
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
# [CLEANUP] Remove temporary sudo permissions
# ------------------------------------------------------------------------------
log "Removing temporary NOPASSWD sudo access..."
rm -f "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 8. SwayOSD
# ------------------------------------------------------------------------------
log "Step 8/9: Installing SwayOSD..."
pacman -S --noconfirm --needed swayosd > /dev/null 2>&1
systemctl enable --now swayosd-libinput-backend.service > /dev/null 2>&1

# ------------------------------------------------------------------------------
# 9. Auto-Login & Niri Autostart
# ------------------------------------------------------------------------------
log "Step 9/9: Configuring Auto-login..."

if [ "$SKIP_AUTOLOGIN" = true ]; then
    echo -e "${YELLOW}[INFO] Existing Display Manager detected. Skipping TTY auto-login setup.${NC}"
else
    # 9.1 Getty
    GETTY_DIR="/etc/systemd/system/getty@tty1.service.d"
    mkdir -p "$GETTY_DIR"
    cat <<EOT > "$GETTY_DIR/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}
EOT

    # 9.2 Service File
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

    # 9.3 Manual Symlink
    log "-> Enabling niri-autostart.service (Manual Symlink)..."
    WANTS_DIR="$USER_SYSTEMD_DIR/default.target.wants"
    mkdir -p "$WANTS_DIR"
    ln -sf "../niri-autostart.service" "$WANTS_DIR/niri-autostart.service"

    # 9.4 Permission Fix (Surgical)
    chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.config/systemd"
    
    success "TTY Auto-login configured."
fi

log ">>> Phase 4 completed. REBOOT RECOMMENDED."