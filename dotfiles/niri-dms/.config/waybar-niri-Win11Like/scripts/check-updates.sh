#!/bin/bash

# === 配置区域 ===
CACHE_FILE="$HOME/.cache/waybar-updates.json"
LOCK_FILE="/tmp/waybar-updates.lock"
MAX_LINES=50 
CHECK_INTERVAL=3600

# === 自动检测 AUR Helper ===
if command -v paru &> /dev/null; then
    AUR_HELPER="paru"
elif command -v yay &> /dev/null; then
    AUR_HELPER="yay"
else
    AUR_HELPER=""
fi

# === 生成 JSON 函数 (保持不变) ===
generate_json() {
    local updates=$1
    local count
    
    updates=$(echo "$updates" | grep -v '^\s*$' || true)
    
    if [ -z "$updates" ]; then
        count=0
        printf '{"text": "", "alt": "updated", "tooltip": "System is up to date"}\n'
        return
    else
        count=$(echo "$updates" | wc -l)
    fi

    local tooltip_text=""
    if [ "$count" -gt "$MAX_LINES" ]; then
        local remainder=$((count - MAX_LINES))
        local top_list=$(echo "$updates" | head -n "$MAX_LINES")
        local escaped_list=$(echo "$top_list" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' )
        tooltip_text="${escaped_list}----------------\\n<b>⚠️ ... and ${remainder} more updates</b>"
    else
        tooltip_text=$(echo "$updates" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | head -c -2)
    fi

    printf '{"text": "%s", "alt": "has-updates", "tooltip": "%s"}\n' "$count" "$tooltip_text"
}

# === 真正的检查逻辑 ===
perform_update_check() {
    # 1. 官方源
    local REPO_UPDATES=$(checkupdates 2>/dev/null)
    local STATUS=$?

    # 2. AUR 源
    local AUR_UPDATES=""
    if [ -n "$AUR_HELPER" ]; then
        AUR_UPDATES=$($AUR_HELPER -Qua 2>/dev/null)
    fi

    local ALL_UPDATES=""
    if [ $STATUS -eq 0 ] || [ $STATUS -eq 2 ]; then
        if [ -n "$REPO_UPDATES" ] && [ -n "$AUR_UPDATES" ]; then
            ALL_UPDATES="$REPO_UPDATES"$'\n'"$AUR_UPDATES"
        elif [ -n "$REPO_UPDATES" ]; then
            ALL_UPDATES="$REPO_UPDATES"
        else
            ALL_UPDATES="$AUR_UPDATES"
        fi
        
        # 写入缓存
        generate_json "$ALL_UPDATES" > "$CACHE_FILE"
    else
        # 检查失败时不覆盖缓存，防止写入错误数据
        return 1
    fi
}

# === 主控制逻辑 ===
run_check() {
    # 1. 检查缓存是否“新鲜”
    # 如果文件存在 且 修改时间在 CHECK_INTERVAL 秒以内
    if [ -f "$CACHE_FILE" ]; then
        local current_time=$(date +%s)
        local file_time=$(stat -c %Y "$CACHE_FILE")
        local age=$((current_time - file_time))
        
        # 如果缓存很新（例如小于检查间隔的 90%），直接读取并返回，不做任何操作
        if [ $age -lt $((CHECK_INTERVAL - 10)) ]; then
            cat "$CACHE_FILE"
            return
        fi
    fi

    # 2. 缓存过期，尝试获取锁进行更新
    # 使用 flock 打开锁文件（文件描述符 9）
    (
        # -x: 排他锁, -n: 非阻塞（如果被锁住直接失败，不等待）
        if flock -x -n 9; then
            # 拿到锁了！我是天选之子，我负责更新
            perform_update_check
        else
            # 没拿到锁，说明另一个 Waybar 正在检查。
            # 我们等待它完成 (最长等待 120秒)
            flock -x -w 120 9
            # 锁释放了，说明它检查完了，我们直接读它写好的缓存
        fi
    ) 9>"$LOCK_FILE"

    # 3. 最终输出缓存内容
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        printf '{"text": "...", "alt": "updated", "tooltip": "Checking..."}\n'
    fi
}

# === 信号处理 ===
trap 'rm -f "$CACHE_FILE"; run_check' SIGUSR1

# === 主循环 ===
while true; do
    run_check
    sleep "$CHECK_INTERVAL" &
    wait $!
done
