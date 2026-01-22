# Shorin Arch Setup (Arch Linux 自动化配置协议) 项目文档

## 1. 项目概述

**Shorin Arch Setup** 是一个功能强大的 Arch Linux 自动化安装和配置套件。它旨在帮助用户在崭新的 Arch Linux 系统上，快速构建一个美观、功能完备且具备高容错率的工作环境。

本项目不仅仅是简单的软件安装脚本，它还引入了**快照回滚机制 (Snapper)**、**自动硬件检测**、**中国大陆镜像优化**以及**模块化设计**，确保安装过程安全、可控且适应性强。

### 主要亮点
*   **多桌面支持**：原生支持 **Niri** (平铺式窗口管理器)、**KDE Plasma**、**GNOME** 以及多种基于 **Quickshell/Hyprland** 的定制桌面 (End4, DMS, Caelestia)。
*   **安全优先**：基于 Btrfs 文件系统，利用 Snapper 在关键步骤前自动创建系统快照。若安装失败，可一键回滚。
*   **硬件适配**：自动检测 Intel、AMD、NVIDIA 显卡并安装对应驱动（支持混合显卡）。自动配置蓝牙、声卡和电源管理。
*   **本地化优化**：针对中国大陆用户优化，包括 Reflector 镜像源优选、Fcitx5 输入法配置、中文字体及特定软件源 (ArchLinuxCN) 配置。
*   **交互友好**：提供美观的 CLI 界面、FZF 模糊搜索菜单用于软件选择，以及详细的进度日志。

---

## 2. 核心工作流程

整个安装过程由 `install.sh` 脚本编排，按以下顺序执行：

1.  **引导与初始化**：检查 Root 权限，加载工具库，展示欢迎 Banner。
2.  **桌面选择**：用户从菜单中选择要安装的桌面环境（如 Niri, KDE 等）。
3.  **环境准备**：
    *   自动优化 Pacman 镜像源 (Reflector)，智能识别是否位于中国大陆。
    *   初始化 Pacman Keyring 并进行全系统更新。
4.  **模块化执行** (按顺序运行 `scripts/` 下的脚本)：
    *   **Btrfs 初始化**：配置 Root 和 Home 分区的 Snapper 快照策略。
    *   **基础配置**：设置默认编辑器 (Vim/Neovim)、安装基础字体、配置 ArchLinuxCN 源。
    *   **核心组件**：安装 GRUB 增强工具、Pipewire 音频、Locale (zh_CN)、Fcitx5 输入法、蓝牙及电源管理。
    *   **双系统修复** (可选)：如果检测到 Windows，自动配置 OS-Prober。
    *   **用户设置**：创建普通用户，配置 Sudo 权限及用户目录。
    *   **驱动安装**：自动识别 GPU 厂商并安装驱动 (支持 NVIDIA 私有驱动及 Prime)。
    *   **安全快照**：在安装桌面环境前创建 "Before Desktop Environments" 快照。
    *   **桌面环境安装**：根据第 2 步的选择，执行对应的桌面安装脚本 (如 `04-niri-setup.sh`)。
    *   **GRUB 主题**：安装并应用美观的 Bootloader 主题。
    *   **常用软件**：提供应用列表，允许用户通过 FZF 菜单选择安装常用软件 (浏览器、开发工具等)，支持 Repo、AUR 和 Flatpak。
5.  **收尾清理**：删除安装过程中的临时快照，清理缓存，保存安装日志，提示重启。

---

## 3. 文件与目录结构说明

```text
/
├── install.sh                  # [核心] 主安装入口脚本，负责流程控制和状态管理
├── strap.sh                    # 引导脚本，用于克隆仓库并启动 install.sh
├── undochange.sh               # [紧急] 回滚工具，用于将系统恢复到安装前状态
├── README.md                   # 简易使用说明
├── common-applist.txt          # 通用软件安装列表
├── *-applist.txt               # 特定桌面环境的专属软件列表 (如 kde-applist.txt)
├── exclude-dotfiles.txt        # 配置文件黑名单，用于在复制 dotfiles 时排除特定文件
├── scripts/                    # [模块] 包含所有具体执行步骤的脚本文件夹
│   ├── 00-utils.sh             # 通用工具函数库 (日志、颜色、错误处理)
│   ├── 00-btrfs-init.sh        # Btrfs 与 Snapper 初始化
│   ├── 01-base.sh              # 基础系统配置 (字体, 源,编辑器)
│   ├── 02-musthave.sh          # 核心必备组件 (音频, 输入法, 蓝牙)
│   ├── 02a-dualboot-fix.sh     # 双系统 GRUB 引导修复
│   ├── 03-user.sh              # 用户创建与权限配置
│   ├── 03b-gpu-driver.sh       # 显卡驱动自动安装逻辑
│   ├── 03c-snapshot...sh       # 桌面安装前的快照创建点
│   ├── 04-*.sh                 # 各类桌面环境的具体安装脚本 (Niri, KDE, Gnome 等)
│   ├── 07-grub-theme.sh        # GRUB 主题配置
│   └── 99-apps.sh              # 常用应用安装器
├── *-dotfiles/                 # 各桌面的预设配置文件 (配合安装脚本部署到 ~/.config)
├── grub-themes/                # GRUB 主题资源文件夹
└── resources/                  # 静态资源 (字体, Firefox 预设配置等)
```

---

## 4. 详细脚本功能解析

### A. 核心控制脚本
*   **`install.sh`**: 
    *   这是总指挥。它维护一个状态文件 `.install_progress`，支持**断点续传**（如果安装中断，重新运行会跳过已完成的模块）。
    *   包含中国大陆网络环境的自动判断逻辑，提示用户是否强制刷新镜像。
    *   负责最后的清理工作，包括智能删除安装过程中产生的“中间态”快照，只保留关键节点。

*   **`undochange.sh`**:
    *   救命稻草。如果系统挂了，root 运行此脚本可立即调用 Snapper 将系统回滚到 "Before Shorin Setup" 的状态。

### B. 基础与环境模块
*   **`00-btrfs-init.sh`**:
    *   检测根目录是否为 Btrfs。
    *   创建并配置 Snapper 的 `root` 和 `home` config。
    *   设置快照保留策略（防止快照占满磁盘）。
    *   创建初始快照 "Before Shorin Setup"。

*   **`01-base.sh`**:
    *   设置 `EDITOR` 环境变量。
    *   开启 `[multilib]` 32位软件库支持。
    *   安装中文字体 (Source Han Sans/Serif) 和终端字体 (Terminus)。
    *   配置 **ArchLinuxCN** 软件源及 Keyring。
    *   安装 AUR 助手 (`yay` 和 `paru`)。

*   **`02-musthave.sh`**:
    *   安装 `grub-btrfs`，实现直接从 GRUB 菜单启动到 Btrfs 快照。
    *   安装 **Pipewire** 全套音频栈。
    *   生成 `zh_CN.UTF-8` Locale。
    *   安装 **Fcitx5** 输入法框架及词库。
    *   智能检测蓝牙硬件，仅在有硬件时安装 Bluez。
    *   安装 `power-profiles-daemon` 电源管理。

*   **`02a-dualboot-fix.sh`**:
    *   安装 `os-prober`。
    *   检测是否存在 Windows 分区。
    *   修改 GRUB 配置开启 `GRUB_DISABLE_OS_PROBER=false`，确保能引导 Windows。

### C. 用户与驱动模块
*   **`03-user.sh`**:
    *   交互式询问用户名（如果检测到已存在 UID 1000 用户则复用）。
    *   创建用户并加入 `wheel` 组，配置 sudo 免密（或权限）。
    *   运行 `xdg-user-dirs-update` 生成下载、文档等标准目录。

*   **`03b-gpu-driver.sh`**:
    *   **智能识别**：解析 `lspci` 输出。
    *   **AMD**: 安装 `amdgpu`、Mesa、Vulkan。
    *   **Intel**: 区分新旧架构安装 `intel-media-driver` 或旧版驱动。
    *   **NVIDIA**: 极其复杂的判断逻辑。根据显卡代号（Turing, Pascal, Kepler 等）自动选择 `nvidia-open`、`nvidia-580xx` 或 `nvidia-470xx` 驱动。
    *   **双显卡**: 自动配置 Prime 和 Switcheroo。

### D. 桌面环境模块 (示例)
*   **`04-niri-setup.sh`**:
    *   安装 Niri (Wayland 合成器)、Fuzzel (启动器)、Waybar、Mako (通知) 等核心组件。
    *   从 Git 仓库拉取详细的 dotfiles 配置。
    *   配置 Firefox 策略。
    *   设置 TTY 自动登录。

*   **`06-kdeplasma-setup.sh` (或 04b)**:
    *   安装 Plasma Meta 包及核心应用 (Dolphin, Konsole)。
    *   配置 SDDM 显示管理器。
    *   部署 KDE 专属的配置文件到 `~/.config`。

### E. 应用与美化
*   **`07-grub-theme.sh`**:
    *   扫描 `grub-themes/` 目录。
    *   提供 TUI 菜单让用户选择主题。
    *   配置 GRUB 参数（如分辨率、隐藏启动信息以显示漂亮的开机动画）。

*   **`99-apps.sh`**:
    *   读取 `common-applist.txt`。
    *   提供 **FZF 多选菜单**，用户可勾选需要的软件。
    *   支持批量安装 Repo 软件，逐个尝试安装 AUR 软件（带重试机制）。
    *   特殊配置：
        *   **Wine**: 自动初始化 Wine 前缀并安装中文字体。
        *   **Virt-Manager**: 安装 KVM/QEMU 虚拟化环境并配置网络。
        *   **LazyVim**: 可选安装 Neovim 的 LazyVim 配置。
        *   **Firefox**: 注入自定义 UI 配置。

## 5. 使用指南

1.  **前提条件**：你需要一个已经安装好 Arch Linux 基础系统（Base System）的环境，并且已经配置好网络。
2.  **获取项目**：
    ```bash
    git clone https://github.com/SHORiN-KiWATA/shorin-arch-setup.git
    cd shorin-arch-setup
    ```
3.  **运行安装**：
    ```bash
    sudo bash install.sh
    ```
4.  **回滚** (如果需要)：
    ```bash
    sudo bash undochange.sh
    ```
