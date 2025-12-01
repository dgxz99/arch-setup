#!/bin/bash

# ==============================================================================
# Shorin Arch Setup - Main Installer (v3.1)
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"

# Source the visual engine
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# --- Environment Propagation ---
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}

check_root
chmod +x "$SCRIPTS_DIR"/*.sh

# --- ASCII Banners ---
banner1() {
cat << "EOF"
   _____ __  ______  ____  _____   __
  / ___// / / / __ \/ __ \/  _/ | / /
  \__ \/ /_/ / / / / /_/ // //  |/ / 
 ___/ / __  / /_/ / _, _// // /|  /  
/____/_/ /_/\____/_/ |_/___/_/ |_/   
EOF
}

banner2() {
cat << "EOF"
  ██████  ██   ██  ██████  ██████  ██ ███    ██ 
  ██      ██   ██ ██    ██ ██   ██ ██ ████   ██ 
  ███████ ███████ ██    ██ ██████  ██ ██ ██  ██ 
       ██ ██   ██ ██    ██ ██   ██ ██ ██  ██ ██ 
  ██████  ██   ██  ██████  ██   ██ ██ ██   ████ 
EOF
}

banner3() {
cat << "EOF"
   ______ __ __   ___   ____   ____  _   _ 
  / ___/|  |  | /   \ |    \ |    || \ | |
 (   \_ |  |  ||     ||  D  ) |  | |  \| |
  \__  ||  _  ||  O  ||    /  |  | |     |
  /  \ ||  |  ||     ||    \  |  | | |\  |
  \    ||  |  ||     ||  .  \ |  | | | \ |
   \___||__|__| \___/ |__|\_||____||_| \_|
EOF
}

show_banner() {
    clear
    local r=$(( $RANDOM % 3 ))
    echo -e "${H_CYAN}"
    case $r in
        0) banner1 ;;
        1) banner2 ;;
        2) banner3 ;;
    esac
    echo -e "${NC}"
    echo -e "${DIM}   :: Arch Linux Automation Protocol :: v3.1 ::${NC}"
    echo ""
}

# --- System Dashboard ---
sys_dashboard() {
    echo -e "${H_BLUE}╔════ SYSTEM DIAGNOSTICS ══════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Kernel${NC}   : $(uname -r)"
    echo -e "${H_BLUE}║${NC} ${BOLD}User${NC}     : $(whoami)"
    
    # Mirror Status
    if [ "$CN_MIRROR" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_YELLOW}CN Optimized (Manual)${NC}"
    elif [ "$DEBUG" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_RED}DEBUG FORCE (CN Mode)${NC}"
    else
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : Global Default"
    fi
    
    # Progress
    if [ -f "$STATE_FILE" ]; then
        done_count=$(wc -l < "$STATE_FILE")
        echo -e "${H_BLUE}║${NC} ${BOLD}Progress${NC} : Resuming ($done_count modules done)"
    fi
    
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- Main Execution ---

show_banner
sys_dashboard

# Module Definition (Order Adjusted)
MODULES=(
    "01-base.sh"        # Editor, Pacman, Fonts
    "02-musthave.sh"    # Audio, Input, Btrfs, Grub-Fix
    "03-user.sh"        # User creation
    "04-niri-setup.sh"  # Niri Desktop, Dotfiles, Recovery
    "07-grub-theme.sh"  # Grub Theming (Moved up)
    "99-apps.sh"        # Optional Common Apps (Moved to end)
)

if [ ! -f "$STATE_FILE" ]; then
    touch "$STATE_FILE"
fi

TOTAL_STEPS=${#MODULES[@]}
CURRENT_STEP=0

# Fake Loading Effect
log "Initializing installer sequence..."
sleep 0.5

for module in "${MODULES[@]}"; do
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    if [ ! -f "$script_path" ]; then
        error "Module not found: $module"
        continue
    fi

    # Using 'section' from 00-utils for consistent styling
    section "Module ${CURRENT_STEP}/${TOTAL_STEPS}" "$module"

    # Checkpoint Logic
    if grep -q "^${module}$" "$STATE_FILE"; then
        echo -e "   ${H_GREEN}✔${NC} Module previously completed."
        read -p "$(echo -e "   ${H_YELLOW}Skip this module? [Y/n] ${NC}")" skip_choice
        skip_choice=${skip_choice:-Y}
        
        if [[ "$skip_choice" =~ ^[Yy]$ ]]; then
            log "Skipping..."
            continue
        else
            log "Force re-running..."
            sed -i "/^${module}$/d" "$STATE_FILE"
        fi
    fi

    # Run Module
    bash "$script_path"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$module" >> "$STATE_FILE"
    else
        echo ""
        echo -e "${H_RED}╔════ CRITICAL FAILURE ════════════════════════════════╗${NC}"
        echo -e "${H_RED}║ Module '$module' failed with exit code $exit_code.${NC}"
        echo -e "${H_RED}║ Fix the issue and run ./install.sh to resume.${NC}"
        echo -e "${H_RED}╚══════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
done

# --- Completion ---

clear
show_banner

echo -e "${H_GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_GREEN}║             INSTALLATION  COMPLETE                   ║${NC}"
echo -e "${H_GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "   ${BOLD}System Status:${NC}"
echo -e "   ${H_BLUE}●${NC} Niri Desktop  : ${H_GREEN}Ready${NC}"
echo -e "   ${H_BLUE}●${NC} Dotfiles      : ${H_GREEN}Applied${NC}"
echo -e "   ${H_BLUE}●${NC} Bootloader    : ${H_GREEN}Themed${NC}"
echo ""

# Cleanup State
if [ -f "$STATE_FILE" ]; then
    rm "$STATE_FILE"
fi

# Reboot Logic
echo -e "${H_YELLOW}>>> System requires a REBOOT to initialize services.${NC}"

for i in {10..1}; do
    echo -ne "\r   ${DIM}Auto-rebooting in ${i} seconds... (Press 'n' to cancel)${NC}"
    read -t 1 -N 1 input
    if [[ "$input" == "n" || "$input" == "N" ]]; then
        echo -e "\n\n   ${H_BLUE}>>> Reboot cancelled.${NC}"
        echo -e "   Type ${BOLD}reboot${NC} when you are ready."
        exit 0
    fi
done

echo -e "\n\n   ${H_GREEN}>>> Rebooting system...${NC}"
reboot