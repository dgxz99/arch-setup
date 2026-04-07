> 注意：该仓库基于上游项目修改维护，当前使用仓库为：`https://github.com/dgxz99/arch-setup.git`
> 上游仓库地址：`https://github.com/SHORiN-KiWATA/shorin-arch-setup.git`

## 使用方法

1. 安装一个archlinux系统

2. 登录之后从tty运行以下命令
   
   ```bash
   sudo pacman -Syu --noconfirm git
   git clone https://github.com/dgxz99/arch-setup.git
   cd arch-setup
   sudo bash install.sh
   ```

   一条命令版：

   ```bash
   sudo pacman -Syu --noconfirm git && git clone https://github.com/dgxz99/arch-setup.git && cd arch-setup && sudo bash install.sh
   ```

   也可以使用引导脚本：

   ```bash
   BRANCH=main bash strap.sh
   ```
