#!/bin/bash

# ==============================================================================
# 07-grub-theme.sh - GRUB Bootloader Theming
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

section "Phase 7" "GRUB Theme Customization"

# ------------------------------------------------------------------------------
# 1. Install Theme Files
# ------------------------------------------------------------------------------
log "Installing CrossGrub theme..."

SOURCE_THEME="$PARENT_DIR/crossgrub"
# We can trust /boot/grub exists now because 02-musthave.sh handled the structure
DEST_DIR="/boot/grub/themes"
THEME_NAME="crossgrub"

if [ -d "$SOURCE_THEME" ]; then
    if [ ! -d "$DEST_DIR" ]; then
        cmd "mkdir -p $DEST_DIR"
        mkdir -p "$DEST_DIR"
    fi
    
    cmd "cp -r $SOURCE_THEME $DEST_DIR/"
    cp -r "$SOURCE_THEME" "$DEST_DIR/"
    
    if [ -d "$DEST_DIR/$THEME_NAME" ]; then
        success "Theme files installed to $DEST_DIR/$THEME_NAME"
    else
        error "Failed to copy theme files."
        exit 1
    fi
else
    error "Theme source not found at: $SOURCE_THEME"
    warn "Ensure 'crossgrub' folder exists in repo root."
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Configure /etc/default/grub
# ------------------------------------------------------------------------------
log "Configuring GRUB settings..."

GRUB_CONF="/etc/default/grub"
THEME_PATH="/boot/grub/themes/$THEME_NAME/theme.txt"

if [ -f "$GRUB_CONF" ]; then
    # Update or Append GRUB_THEME
    if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
        log "Updating existing GRUB_THEME..."
        sed -i "s|^GRUB_THEME=.*|GRUB_THEME=$THEME_PATH|" "$GRUB_CONF"
    else
        log "Adding GRUB_THEME..."
        echo "GRUB_THEME=$THEME_PATH" >> "$GRUB_CONF"
    fi
    
    # Enable graphical output
    if grep -q "^GRUB_TERMINAL_OUTPUT=\"console\"" "$GRUB_CONF"; then
        log "Enabling graphical terminal..."
        sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_CONF"
    fi
    
    success "Configuration updated."
else
    error "$GRUB_CONF not found."
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Apply Changes
# ------------------------------------------------------------------------------
log "Generating new GRUB configuration..."

cmd "grub-mkconfig -o /boot/grub/grub.cfg"
if grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1; then
    success "GRUB updated successfully."
else
    error "Failed to update GRUB."
fi

log "Module 07 completed."