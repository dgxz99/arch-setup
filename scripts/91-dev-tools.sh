#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root
section "Optional 91" "Development Tools Config"

log "Identifying target user..."
detect_target_user
info_kv "Target" "$TARGET_USER"

M2_DIR="$HOME_DIR/.m2"
M2_SETTINGS="$M2_DIR/settings.xml"
UV_DIR="$HOME_DIR/.config/uv"
UV_CONFIG="$UV_DIR/uv.toml"
NPM_PREFIX_DIR="$HOME_DIR/.local"
DOCKER_CONFIG_DIR="/etc/docker"
DOCKER_CONFIG_FILE="$DOCKER_CONFIG_DIR/daemon.json"
NPM_AI_PACKAGES=(
    "@anthropic-ai/claude-code|Anthropic Claude Code CLI"
    "@openai/codex|OpenAI Codex CLI"
    "opencode-ai|OpenCode CLI"
)

backup_file_once() {
    local target="$1"
    if [ -f "$target" ] && [ ! -f "${target}.bak" ]; then
        exe as_user cp "$target" "${target}.bak"
    fi
}

backup_system_file_once() {
    local target="$1"
    if [ -f "$target" ] && [ ! -f "${target}.bak" ]; then
        exe cp "$target" "${target}.bak"
    fi
}

write_maven_settings() {
    log "Configuring Maven mirrors..."
    exe as_user mkdir -p "$M2_DIR"
    backup_file_once "$M2_SETTINGS"

    cat <<'EOF' > "$M2_SETTINGS"
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <mirrors>
    <mirror>
      <id>aliyun-public</id>
      <mirrorOf>central</mirrorOf>
      <url>https://maven.aliyun.com/repository/public</url>
    </mirror>
    <mirror>
      <id>huaweicloud-public</id>
      <mirrorOf>central</mirrorOf>
      <url>https://repo.huaweicloud.com/repository/maven/</url>
    </mirror>
    <mirror>
      <id>tencent-public</id>
      <mirrorOf>central</mirrorOf>
      <url>http://mirrors.cloud.tencent.com/nexus/repository/maven-public/</url>
    </mirror>
  </mirrors>
</settings>
EOF

    exe chown "$TARGET_USER:$TARGET_USER" "$M2_SETTINGS"
    success "Maven settings updated: $M2_SETTINGS"
}

write_uv_config() {
    log "Configuring uv..."
    exe as_user mkdir -p "$UV_DIR"
    backup_file_once "$UV_CONFIG"

    cat <<'EOF' > "$UV_CONFIG"
[[index]]
url = "https://pypi.tuna.tsinghua.edu.cn/simple"
default = true

link-mode = "clone"
EOF

    exe chown "$TARGET_USER:$TARGET_USER" "$UV_CONFIG"
    success "uv config updated: $UV_CONFIG"
}

configure_docker() {
    log "Configuring Docker..."
    exe mkdir -p "$DOCKER_CONFIG_DIR"
    backup_system_file_once "$DOCKER_CONFIG_FILE"

    cat <<'EOF' > "$DOCKER_CONFIG_FILE"
{
  "registry-mirrors": [
    "https://dockerproxy.net"
  ]
}
EOF

    exe chmod 644 "$DOCKER_CONFIG_FILE"
    exe systemctl restart docker
    success "Docker mirror updated: https://dockerproxy.net"
    if getent group docker >/dev/null 2>&1; then
        exe usermod -aG docker "$TARGET_USER"
        success "User '$TARGET_USER' added to docker group."
    fi
}

set_latest_java() {
    log "Checking installed Java environments..."

    if ! command -v archlinux-java >/dev/null 2>&1; then
        return 0
    fi

    mapfile -t java_envs < <(
        archlinux-java status 2>/dev/null | \
        tail -n +2 | \
        sed -E 's/^[[:space:]]+//; s/[[:space:]]+\(default\)$//' | \
        awk 'NF { print $1 }'
    )

    if [ ${#java_envs[@]} -eq 0 ]; then
        return 0
    fi

    local latest_java
    latest_java=$(printf "%s\n" "${java_envs[@]}" | sort -V | tail -n 1)
    info_kv "Java" "Latest detected" "$latest_java"
    exe archlinux-java set "$latest_java"
    success "Default Java set to $latest_java"
}

configure_npm() {
    log "Configuring global prefix and npm registry..."
    exe as_user npm config set prefix "$NPM_PREFIX_DIR"
    exe as_user npm config set registry https://registry.npmmirror.com
    success "npm user config updated."
}

maybe_install_ai_clis() {
    if ! command -v npm >/dev/null 2>&1; then
        return 0
    fi    

    local cli_entries=()
    local cli_count=${#NPM_AI_PACKAGES[@]}
    local item pkg desc
    for item in "${NPM_AI_PACKAGES[@]}"; do
        pkg="${item%%|*}"
        desc="${item##*|}"
        cli_entries+=("${pkg}\t# ${desc}")
    done

    echo ""
    echo -e "   ${H_YELLOW}>>> Do you want to CUSTOMIZE the AI CLI installation?${NC}"
    echo ""
    read -t 60 -p "   Please select [Y/n]: " choice
    local read_status=$?
    local selected_raw=""

    if [ $read_status -ne 0 ]; then
        echo ""
        warn "Timeout reached (60s). Auto-installing ALL AI CLIs..."
        selected_raw=$(printf "%b\n" "${cli_entries[@]}")
    else
        choice=${choice:-Y}
        if [[ "$choice" =~ ^[nN]$ ]]; then
            log "User chose to auto-install ALL AI CLIs without customization."
            selected_raw=$(printf "%b\n" "${cli_entries[@]}")
        else
            if ! command -v fzf >/dev/null 2>&1; then
                log "fzf not found. Installing all predefined AI CLIs."
                selected_raw=$(printf "%b\n" "${cli_entries[@]}")
            else
                clear
                echo -e "\n  Loading AI CLI list..."

                selected_raw=$(printf "%b\n" "${cli_entries[@]}" | \
                    fzf --multi \
                        --layout=reverse \
                        --border \
                        --margin=1,2 \
                        --prompt="Search AI CLI > " \
                        --pointer=">>" \
                        --marker="* " \
                        --delimiter=$'\t' \
                        --with-nth=1 \
                        --bind 'load:select-all' \
                        --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
                        --info=inline \
                        --header="[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL" \
                        --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
                        --preview-window=right:45%:wrap:border-left \
                        --color=dark \
                        --color=fg+:white,bg+:black \
                        --color=hl:blue,hl+:blue:bold \
                        --color=header:yellow:bold \
                        --color=info:magenta \
                        --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
                        --color=spinner:yellow)

                clear

                if [ -z "$selected_raw" ]; then
                    log "Skipping AI CLI installation (User cancelled selection)."
                    return 0
                fi
            fi
        fi
    fi

    local selected_packages=()
    while IFS= read -r line; do
        pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
        [[ -z "$pkg" ]] && continue
        selected_packages+=("$pkg")
    done <<< "$selected_raw"

    info_kv "Scheduled" "${#selected_packages[@]} of ${cli_count}" "npm AI CLI packages"

    for pkg in "${selected_packages[@]}"; do
        log "Installing npm package: $pkg"
        exe as_user npm install -g "$pkg"
    done

    success "Selected AI CLIs installed."
}

# --- maven, uv, docker, java, npm 配置 ---
section "Step 1/2" "Configuring Maven, uv, Docker, Java, npm"

if command -v mvn >/dev/null 2>&1; then
    write_maven_settings
fi

if command -v uv >/dev/null 2>&1; then
    write_uv_config
fi

if command -v docker >/dev/null 2>&1; then
    configure_docker
fi

if command -v java >/dev/null 2>&1 || command -v archlinux-java >/dev/null 2>&1; then
    set_latest_java
fi

if command -v npm >/dev/null 2>&1; then
    configure_npm
fi

# --- 可选安装 AI 相关 CLI 工具 ---
section "Step 2/2" "Optional AI CLI Installation"
maybe_install_ai_clis

success "Development tool post-config completed."
echo ""
