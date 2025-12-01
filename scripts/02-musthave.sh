#!/bin/bash

# ==============================================================================
# 02-musthave.sh - Essential Software, Drivers & Locale
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log ">>> Starting Phase 2: Essential (Must-have) Software & Drivers"

# ------------------------------------------------------------------------------
# 1. Btrfs & Snapper Configuration (With GRUB Path Fix)
# ------------------------------------------------------------------------------
section "Step 1/8" "Filesystem & Snapshot Setup"

ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Btrfs filesystem detected."
    cmd "pacman -S snapper snap-pac btrfs-assistant"
    pacman -S --noconfirm --needed snapper snap-pac btrfs-assistant > /dev/null 2>&1
    success "Snapper tools installed."

    # --- GRUB Logic Start ---
    if [ -d "/boot/grub" ] || [ -f "/etc/default/grub" ]; then
        log "GRUB detected. Verifying directory structure..."

        # [FIX] Logic adjusted based on ESP mount point
        if [ -d "/efi/grub" ]; then
            # Scenario: ESP mounted at /efi
            log "-> Found /efi/grub. Checking /boot/grub symlink..."
            
            if [ ! -L "/boot/grub" ] || [ "$(readlink -f /boot/grub)" != "/efi/grub" ]; then
                warn "/boot/grub is not linked to /efi/grub. Fixing..."
                
                # Backup existing directory if it exists and is not a symlink
                if [ -d "/boot/grub" ] && [ ! -L "/boot/grub" ]; then
                    BACKUP_NAME="/boot/grub.bak.$(date +%s)"
                    cmd "mv /boot/grub $BACKUP_NAME"
                    mv /boot/grub "$BACKUP_NAME"
                    warn "Original /boot/grub backed up to $BACKUP_NAME"
                fi
                
                cmd "ln -sf /efi/grub /boot/grub"
                ln -sf /efi/grub /boot/grub
                success "Symlink /boot/grub -> /efi/grub created."
            else
                success "Structure is correct (/boot/grub -> /efi/grub)."
            fi
        else
            # Scenario: ESP mounted at /boot (or legacy), /efi/grub does not exist
            # /boot/grub should be the real directory. Do nothing.
            log "-> /efi/grub not found. Assuming standard /boot/grub layout."
        fi

        # --- Install grub-btrfs ---
        log "Configuring grub-btrfs snapshot integration..."
        cmd "pacman -S grub-btrfs inotify-tools"
        pacman -S --noconfirm --needed grub-btrfs inotify-tools > /dev/null 2>&1
        systemctl enable --now grub-btrfsd > /dev/null 2>&1
        success "grub-btrfs enabled."

        log "Configuring mkinitcpio (overlayfs)..."
        if grep -q "grub-btrfs-overlayfs" /etc/mkinitcpio.conf; then
            log "-> Hook already exists."
        else
            sed -i 's/^HOOKS=(\(.*\))/HOOKS=(\1 grub-btrfs-overlayfs)/' /etc/mkinitcpio.conf
            cmd "mkinitcpio -P"
            mkinitcpio -P > /dev/null 2>&1
            success "Initramfs regenerated."
        fi

        log "Regenerating GRUB configuration..."
        # Due to the fix above, we can now safely rely on /boot/grub/grub.cfg
        # regardless of where the ESP is.
        cmd "grub-mkconfig -o /boot/grub/grub.cfg"
        if grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1; then
            success "GRUB configuration updated."
        else
            warn "Failed to update GRUB config (check manually)."
        fi
    fi
    # --- GRUB Logic End ---
else
    log "Root filesystem is not Btrfs. Skipping Snapper setup."
fi

# ------------------------------------------------------------------------------
# 2. Audio & Video
# ------------------------------------------------------------------------------
section "Step 2/8" "Audio & Video"

cmd "pacman -S pipewire wireplumber..."
pacman -S --noconfirm --needed sof-firmware alsa-ucm-conf alsa-firmware > /dev/null 2>&1
pacman -S --noconfirm --needed pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack pavucontrol > /dev/null 2>&1

systemctl --global enable pipewire pipewire-pulse wireplumber > /dev/null 2>&1
success "Pipewire services enabled."

# ------------------------------------------------------------------------------
# 3. Locale
# ------------------------------------------------------------------------------
section "Step 3/8" "Locale Configuration"

if locale -a | grep -iq "zh_CN.utf8"; then
    success "Chinese locale (zh_CN.UTF-8) ready."
else
    log "Generating zh_CN.UTF-8..."
    sed -i 's/^#\s*zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    if locale-gen > /dev/null 2>&1; then
        success "Locale generated."
    else
        warn "Locale generation failed."
    fi
fi

# ------------------------------------------------------------------------------
# 4. Input Method
# ------------------------------------------------------------------------------
section "Step 4/8" "Input Method (Fcitx5)"

cmd "pacman -S fcitx5-im fcitx5-rime rime-ice..."
pacman -S --noconfirm --needed fcitx5-im fcitx5-rime rime-ice-pinyin-git fcitx5-mozc > /dev/null 2>&1

log "Configuring Rime defaults..."
target_dir="/etc/skel/.local/share/fcitx5/rime"
mkdir -p "$target_dir"
cat <<EOT > "$target_dir/default.custom.yaml"
patch:
  __include: rime_ice_suggestion:/
EOT
success "Fcitx5 configured."

# ------------------------------------------------------------------------------
# 5. Bluetooth
# ------------------------------------------------------------------------------
section "Step 5/8" "Bluetooth"
pacman -S --noconfirm --needed bluez blueman > /dev/null 2>&1
systemctl enable --now bluetooth > /dev/null 2>&1
success "Bluetooth enabled."

# ------------------------------------------------------------------------------
# 6. Power
# ------------------------------------------------------------------------------
section "Step 6/8" "Power Management"
pacman -S --noconfirm --needed power-profiles-daemon > /dev/null 2>&1
systemctl enable --now power-profiles-daemon > /dev/null 2>&1
success "PPD enabled."

# ------------------------------------------------------------------------------
# 7. Fastfetch
# ------------------------------------------------------------------------------
section "Step 7/8" "Fastfetch"
pacman -S --noconfirm --needed fastfetch > /dev/null 2>&1
success "Installed."

# ------------------------------------------------------------------------------
# 8. XDG Dirs
# ------------------------------------------------------------------------------
section "Step 8/8" "User Directories"
pacman -S --noconfirm --needed xdg-user-dirs > /dev/null 2>&1
success "xdg-user-dirs installed."

log "Module 02 completed."