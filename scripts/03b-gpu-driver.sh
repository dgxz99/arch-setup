#!/bin/bash

# ==============================================================================
# 03b-gpu-driver.sh GPU Driver Installer 参考了cachyos的chwd脚本
# ==============================================================================
# 模块说明：显卡驱动自动安装
# ------------------------------------------------------------------------------
# 此模块自动检测系统中的显卡并安装对应驱动
#
# 支持的显卡：
#   - AMD: mesa + vulkan-radeon (AMDGPU 开源驱动)
#   - Intel: mesa + vulkan-intel (i915 开源驱动)
#   - NVIDIA: 根据显卡代数选择不同驱动
#     * Turing 及以上 (RTX/GTX 16): nvidia-open-dkms
#     * Pascal/Maxwell (GTX 10/9xx): nvidia-580xx-dkms
#     * Kepler (GTX 6xx/7xx): nvidia-470xx-dkms
#
# 特殊处理：
#   - 双显卡系统: 自动安装 nvidia-prime 和 switcheroo-control
#   - 自动检测已安装的内核并安装对应 headers
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 引用工具库
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

check_root

section "Phase 2b" "GPU Driver Setup"

# ==============================================================================
# 1. 变量声明与基础信息获取
# ==============================================================================
# 使用 lspci 检测系统中的所有 GPU 设备
# VGA: 传统显卡控制器
# 3D: 3D 加速器 (部分 NVIDIA 显卡)
# Display: 显示控制器
log "Detecting GPU Hardware..."

# 核心变量：存放 lspci 信息
# -mm: 机器可读格式，方便解析
GPU_INFO=$(lspci -mm | grep -E -i "VGA|3D|Display")
log "GPU Info Detected:\n$GPU_INFO"

# 状态变量初始化 - 记录检测到的显卡类型
HAS_AMD=false
HAS_INTEL=false
HAS_NVIDIA=false
GPU_NUMBER=0
# 待安装包数组 - libva-utils 用于验证硬件视频加速
PKGS=("libva-utils")
# ==============================================================================
# 2. 状态变更 & 基础包追加 (Base Packages)
# ==============================================================================
# 根据检测到的显卡类型添加对应的驱动包

# --- AMD 检测 --- -q 静默，-i忽略大小写
# AMD/ATI 显卡使用 AMDGPU 开源驱动，性能优秀
if echo "$GPU_INFO" | grep -q -i "AMD\|ATI"; then
    HAS_AMD=true
    info_kv "Vendor" "AMD Detected"
    # 追加 AMD 基础包
    # mesa: OpenGL 实现
    # xf86-video-amdgpu: Xorg DDX 驱动
    # vulkan-radeon: Vulkan 支持
    # gst-plugin-va: GStreamer 硬件解码插件
    # opencl-mesa: OpenCL 计算支持
    PKGS+=("mesa" "lib32-mesa" "xf86-video-amdgpu" "vulkan-radeon" "lib32-vulkan-radeon" "linux-firmware-amdgpu" "gst-plugin-va" "opencl-mesa" "lib32-opencl-mesa" "opencl-icd-loader" "lib32-opencl-icd-loader" )
fi

# --- Intel 检测 ---
# Intel 集显使用 i915 开源驱动
if echo "$GPU_INFO" | grep -q -i "Intel"; then
    HAS_INTEL=true
    info_kv "Vendor" "Intel Detected"
    # 追加 Intel 基础包 (保证能亮机，能跑基础桌面)
    # vulkan-intel: Intel ANV Vulkan 驱动
    # linux-firmware-intel: Intel 固件
    PKGS+=("mesa" "vulkan-intel" "lib32-mesa" "lib32-vulkan-intel" "gst-plugin-va" "linux-firmware-intel" "opencl-mesa" "lib32-opencl-mesa" "opencl-icd-loader" "lib32-opencl-icd-loader" )
fi

# --- NVIDIA 检测 ---
# NVIDIA 显卡需要闭源驱动，后续根据显卡代数选择
if echo "$GPU_INFO" | grep -q -i "NVIDIA"; then
    HAS_NVIDIA=true
    info_kv "Vendor" "NVIDIA Detected"
    # 追加 NVIDIA 基础工具包
    # 具体驱动在第 3 部分根据显卡型号选择
fi

# --- 多显卡检测 ---
# 统计检测到的 GPU 数量
GPU_COUNT=$(echo "$GPU_INFO" | grep -c .)

if [ "$GPU_COUNT" -ge 2 ]; then
    info_kv "GPU Layout" "Dual/Multi-GPU Detected (Count: $GPU_COUNT)"
    # vulkan-mesa-layers: 提供 vk-device-select 等 Vulkan 层
    # 允许用户选择使用哪块 GPU 运行应用
    PKGS+=("vulkan-mesa-layers" "lib32-vulkan-mesa-layers")

    # 如果是 NVIDIA + 其他显卡的组合 (如笔记本的 Intel+NVIDIA)
    if [[ $HAS_NVIDIA == true ]]; then 
        # nvidia-prime: PRIME 渲染卸载支持
        # switcheroo-control: D-Bus 服务，提供显卡切换 API
        PKGS+=("nvidia-prime" "switcheroo-control")
        # 修复 GTK4 在 NVIDIA 双显卡系统上的渲染问题
        # 强制使用 GL 渲染器而非 Vulkan
        if grep -q "GSK_RENDERER" "/etc/environment"; then
            echo 'GSK_RENDERER=gl' >> /etc/environment
        fi
    fi
fi
# ==============================================================================
# 3. Conditional 包判断 
# ==============================================================================
# 根据具体硬件型号添加额外的驱动包

# ------------------------------------------------------------------------------
# 3.1 Intel 硬件编解码判断
# ------------------------------------------------------------------------------
# Intel 有两个硬件视频加速驱动：
#   - intel-media-driver (iHD): 新架构 (Broadwell+)
#   - libva-intel-driver (i965): 旧架构
# 这里根据显卡型号判断应该使用哪个
if [ "$HAS_INTEL" = true ]; then
    # 检查是否为现代架构 (Broadwell 及更新)
    # Arc, Xe, UHD, Iris 都是现代 Intel 显卡系列
    # Raptor Lake, Alder Lake 等是 CPU 代号
    if echo "$GPU_INFO" | grep -q -E -i "Arc|Xe|UHD|Iris|Raptor|Alder|Tiger|Rocket|Ice|Comet|Coffee|Kaby|Skylake|Broadwell|Gemini|Jasper|Elkhart|HD Graphics 6|HD Graphics 5[0-9][0-9]\b"; then
        log "   -> Intel: Modern architecture matched (iHD path)..."
        # intel-media-driver: 新一代 iHD 驱动，支持 HEVC/VP9 等现代编码
        PKGS+=("intel-media-driver")
    else
        # 旧架构或未知型号，跳过以避免安装错误的驱动
        warn "   -> Intel: Legacy or Unknown model. Skipping intel-media-driver."
    fi
fi

# ------------------------------------------------------------------------------
# 3.2 NVIDIA 驱动版本与内核 Headers 判断
# ------------------------------------------------------------------------------
# NVIDIA 显卡根据架构代数选择不同的驱动：
#   - nvidia-open-dkms: Turing 及以上 (RTX 20/30/40, GTX 16)
#   - nvidia-580xx-dkms: Pascal/Maxwell (GTX 10/9xx)
#   - nvidia-470xx-dkms: Kepler (GTX 6xx/7xx)
# 后两者需要从 AUR 安装
if [ "$HAS_NVIDIA" = true ]; then
    # 获取第一块 NVIDIA 显卡的型号信息
    NV_MODEL=$(echo "$GPU_INFO" | grep -i "NVIDIA" | head -n 1)
    
    # 初始化一个标志位，只有匹配到支持的显卡才设为 true
    DRIVER_SELECTED=false

    # ==========================================================================
    #  nvidia-open - 开源内核模块 (推荐)
    # ==========================================================================
    # RTX 系列和 GTX 16 系列使用 NVIDIA 开源内核模块
    # 这是 NVIDIA 官方发布的开源驱动，性能接近闭源驱动
    if echo "$NV_MODEL" | grep -q -E -i "RTX|GTX 16"; then
        log "   -> NVIDIA: Modern GPU detected (Turing+). Using Open Kernel Modules."
        
        # 核心驱动包
        # nvidia-open-dkms: DKMS 包，自动为新内核编译模块
        # nvidia-utils: 用户空间工具和库
        # opencl-nvidia: NVIDIA OpenCL 支持
        # libva-nvidia-driver: NVIDIA VA-API 支持 (硬件视频解码)
        PKGS+=("nvidia-open-dkms" "nvidia-utils" "lib32-nvidia-utils" "opencl-nvidia" "lib32-opencl-nvidia" "libva-nvidia-driver" "vulkan-icd-loader" "lib32-vulkan-icd-loader" "opencl-icd-loader" "lib32-opencl-icd-loader")
        DRIVER_SELECTED=true

    # ==========================================================================
    # nvidia-580xx-dkms - Pascal/Maxwell 架构
    # ==========================================================================
    # GTX 10 系列和部分 GTX 9xx 系列
    # 需要从 AUR (archlinuxcn) 安装
    elif echo "$NV_MODEL" | grep -q -E -i "GTX 10|GTX 950|GTX 960|GTX 970|GTX 980|GTX 745|GTX 750|GTX 750 Ti|GTX 840M|GTX 845M|GTX 850M|GTX 860M|GTX 950M|GTX 960M|GeForce 830M|GeForce 840M|GeForce 930M|GeForce 940M|GeForce GTX Titan X|Tegra X1|NVIDIA Titan X|NVIDIA Titan Xp|NVIDIA Titan V|NVIDIA Quadro GV100"; then
        log "   -> NVIDIA: Pascal/Maxwell GPU detected. Using Proprietary DKMS."
        PKGS+=("nvidia-580xx-dkms" "nvidia-580xx-utils" "opencl-nvidia-580xx" "lib32-opencl-nvidia-580xx" "lib32-nvidia-580xx-utils" "libva-nvidia-driver" "vulkan-icd-loader" "lib32-vulkan-icd-loader" "opencl-icd-loader" "lib32-opencl-icd-loader" )
        DRIVER_SELECTED=true

    # ==========================================================================
    # nvidia-470xx-dkms - Kepler 架构
    # ==========================================================================
    # GTX 6xx/7xx 系列
    # 470xx 是 NVIDIA 为 Kepler 架构提供的最后一个驱动分支
    elif echo "$NV_MODEL" | grep -q -E -i "GTX 6[0-9][0-9]|GTX 760|GTX 765|GTX 770|GTX 775|GTX 780|GTX 860M|GT 6[0-9][0-9]|GT 710M|GT 720|GT 730M|GT 735M|GT 740|GT 745M|GT 750M|GT 755M|GT 920M|Quadro 410|Quadro K500|Quadro K510|Quadro K600|Quadro K610|Quadro K1000|Quadro K1100|Quadro K2000|Quadro K2100|Quadro K3000|Quadro K3100|Quadro K4000|Quadro K4100|Quadro K5000|Quadro K5100|Quadro K6000|Tesla K10|Tesla K20|Tesla K40|Tesla K80|NVS 510|NVS 1000|Tegra K1|Titan|Titan Z"; then

        log "   -> NVIDIA:  Kepler GPU detected. Using nvidia-470xx-dkms."
        PKGS+=("nvidia-470xx-dkms" "nvidia-470xx-utils" "opencl-nvidia-470xx" "vulkan-icd-loader" "lib32-nvidia-470xx-utils" "lib32-opencl-nvidia-470xx" "lib32-vulkan-icd-loader" "libva-nvidia-driver" "opencl-icd-loader" "lib32-opencl-icd-loader")
        DRIVER_SELECTED=true

    # ==========================================================================
    # others - 更旧的显卡
    # ========================================================================== 
    # Fermi 及更旧的架构已不受支持，需要手动处理
    else
        warn "   -> NVIDIA: Legacy GPU detected ($NV_MODEL)."
        warn "   -> Please manually install GPU driver."
    fi

    # ==========================================================================
    # headers - 内核头文件
    # ==========================================================================
    # DKMS 驱动需要内核头文件来编译模块
    # 自动检测已安装的内核并安装对应的 headers
    if [ "$DRIVER_SELECTED" = true ]; then
        log "   -> NVIDIA: Scanning installed kernels for headers..."
        
        # 1. 获取所有以 linux 开头的候选包
        #    排除 headers/firmware/api 等非内核包
        CANDIDATES=$(pacman -Qq | grep "^linux" | grep -vE "headers|firmware|api|docs|tools|utils|qq")

        for kernel in $CANDIDATES; do
            # 2. 验证：只有在 /boot 下存在对应 vmlinuz 文件的才算是真内核
            if [ -f "/boot/vmlinuz-${kernel}" ]; then
                HEADER_PKG="${kernel}-headers"
                log "      + Kernel found: $kernel -> Adding $HEADER_PKG"
                PKGS+=("$HEADER_PKG")
            fi
        done
    fi
fi

# ==============================================================================
# 4. 执行
# ==============================================================================
# 执行实际的包安装


# 获取 UID 1000 用户（普通用户）
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"

#--------------sudo temp file--------------------#
# 创建临时的 sudo 免密码文件
# 这是因为 yay 需要以普通用户身份运行，但安装过程中会调用 sudo
# 为了避免安装过程中反复输入密码，临时授予免密码权限
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

# 定义清理函数：无论脚本是成功结束还是意外中断(Ctrl+C)，都确保删除免密文件
# 这是重要的安全措施，防止免密码配置残留
cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
# 注册陷阱：在脚本退出(EXIT)或被中断(INT/TERM)时触发清理
trap cleanup_sudo EXIT INT TERM

if [ ${#PKGS[@]} -gt 0 ]; then
    # 数组去重 - 避免重复安装同一个包
    UNIQUE_PKGS=($(printf "%s\n" "${PKGS[@]}" | sort -u))
    
    section "Installation" "Installing Packages"
    log "Target Packages: ${UNIQUE_PKGS[*]}"
    
    # 执行安装
    # runuser -u: 以普通用户身份运行 yay
    # --answerdiff=None --answerclean=None: 自动回答 AUR 包的提示
    exe runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "${UNIQUE_PKGS[@]}"
    
    # 启用相关服务
    log "Enabling services (if supported)..."
    # nvidia-powerd: NVIDIA 电源管理服务 (RTX 30/40 系列)
    systemctl enable --now nvidia-powerd &>/dev/null || true
    # switcheroo-control: 双显卡切换服务
    systemctl enable switcheroo-control.service &>/dev/null || true
    success "GPU Drivers processed successfully."
else
    warn "No GPU drivers matched or needed."
fi

log "Module 02b completed."