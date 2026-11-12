<div align="right">
  <a href="README.md">English</a> | <strong>简体中文</strong>
</div>

# Realtek `3274:9011` 指纹驱动与 PAM 显式认证模式切换套件

面向 **Realtek `3274:9011` Match-on-Chip 指纹传感器** 的 `libfprint` 驱动补丁，以及面向 Wayland（`swaylock` / `greetd`）的 **密码/指纹显式互斥切换套件**。首发开发并真机验证于 **机械革命 无界14 2026（Intel Core Ultra 200V Lunar Lake，Arch Linux + Niri）**。

本仓库的两个核心模块互相解耦，**既可成套安装，也可单独使用**：

1. **硬件驱动层（`packages/libfprint-realtek-9011`）**  
   为官方尚未支持的 **`3274:9011 Generic Realtek USB2.0 Finger Print Bridge`** 提供片上匹配（MoC）驱动（基于上游最新 `master` `6f9479c`，已包含上游近期针对 `realtek` 状态机内存释放 UAF 的修复）。所有特性均按 USB ID 隔离，不影响其他型号指纹头。
2. **PAM 与锁屏模式切换层（`packages/pam-auth-mode-selector`、`packages/swaylock-auth-mode`）**  
   不绑定任何笔记本品牌或指纹型号。解决 Linux 下传统 `pam_fprintd` 配置“想直接输密码却被指纹卡 10 秒超时”、“亮屏按回车误触空密码导致 `pam_faillock` 锁死账户 10 分钟”、“改动 `system-auth` 连累 `sudo`/`polkit` 弹窗”三大痛点。

---

## 为什么需要显式 PAM 模式切换？

常规教程一般把 `auth sufficient pam_fprintd.so` 直接插在密码认证前面，在 Wayland 锁屏和极简登录器下会有明显缺陷：

- **输密码被迫等指纹超时**：合盖外接显示器或手指湿了想直接输密码时，`pam_fprintd` 仍在阻塞等待按指纹，必须等超时才能落回密码验证。
- **亮屏按键误锁账户**：唤醒屏幕时随手敲回车/空格会提交空密码，连续 3 次就会触发默认 `pam_faillock` 锁定账户 10 分钟（除非去削弱全局 `faillock.conf` 安全阈值）。
- **污染全局 PAM 栈**：一旦写进 `system-auth`，`sudo`、`su`、`sshd` 和桌面 `polkit` 授权弹窗都会被强制拉起指纹等待。

### 本套件的工作机制

```text
用户输入 ──► pam_auth_mode_selector.so
              ├── 令牌为 ":fp" ──► 进入 pam_fprintd.so（单次 10 秒超时，失败直接结束本次尝试，不静默回退）
              └── 普通非空密码 ──► 直接跳过 pam_fprintd ──► 原样交给 pam_unix.so 立即验证密码
```

- **`swaylock-auth-mode` 锁屏交互**：
  - 锁屏默认处于 **`Fingerprint`（绿色指示环）**：按 **`Enter`** 后触摸传感器即可指纹解锁（状态显示 `Scanning` / `Not recognized`）。
  - 按 **`Tab` / `Shift+Tab`**：在 `Fingerprint` 与 `Password`（紫色指示环）之间即时切换，并自动清空输入缓冲。
  - **直接敲任意字符**：在指纹模式下直接打字会自动切入 `Password` 模式，且**第一个字符不会丢失**。
  - 按 **`Esc`**：在密码模式下清空输入并退回 `Fingerprint` 模式。
  - 键盘无操作 5 秒后指示环自动隐藏，按键或切换模式时重新显现。
- **`greetd` 登录界面**：直接输入密码走密码登录；输入 `:fp` 回车后按压手指走指纹登录（`:fp` 标记绝不会被当作密码校验）。

---

## 目录结构

| 路径 | 说明 | 许可证 |
| :--- | :--- | :--- |
| [`packages/libfprint-realtek-9011/`](packages/libfprint-realtek-9011/) | 支持 `3274:9011` 的 `libfprint` Arch `PKGBUILD` 与干净补丁 | `LGPL-2.1-or-later` |
| [`packages/pam-auth-mode-selector/`](packages/pam-auth-mode-selector/) | 独立的 `pam_auth_mode_selector.so` PAM 模块及命令行测试工具 | `MIT` |
| [`packages/swaylock-auth-mode/`](packages/swaylock-auth-mode/) | 带锁屏内指纹/密码模式切换指示器的 `swaylock 1.8.6+ (upstream master `701a352`)` | `MIT` |
| [`scripts/`](scripts/) | 仅针对 `/etc/pam.d/{swaylock,greetd}` 的带备份安装与一键还原脚本 | `MIT` |
| [`docs/protocol-3274-9011.md`](docs/protocol-3274-9011.md) | `3274:9011` USB 批量传输协议与固件状态机差异说明 | `MIT` |

---

## 安装步骤（Arch Linux）

### 第一步：安装 `3274:9011` 指纹驱动

先确认本机指纹传感器的 USB ID：

```bash
lsusb | grep -i 3274:9011
# 预期输出：ID 3274:9011 Generic Realtek USB2.0 Finger Print Bridge
```

编译并安装驱动包与 `fprintd`：

```bash
sudo pacman -S --needed fprintd
cd packages/libfprint-realtek-9011
makepkg -si
```

录入并验证指纹（共 12 次按压采集）：

```bash
fprintd-enroll "$USER"
fprintd-verify "$USER"
```

> **提示**：每次采集需完成一次完整的**按下并抬起**才会计入下一阶段。本包已按上游规范将 `3274:9011` 注册至 `data/autosuspend.hwdb`（`ID_AUTOSUSPEND=1`），传感器在空闲 2 秒后自动进入低功耗挂起并在发起指纹识别时自动唤醒。

---

### 第二步：安装 PAM 模式切换器与 Swaylock（适用于任意 `fprintd` 指纹设备）

1. **编译安装 PAM 选择器模块：**

   ```bash
   cd packages/pam-auth-mode-selector
   makepkg -si
   ```

2. **（可选，Swaylock 用户）编译安装 `swaylock-auth-mode`：**

   ```bash
   cd ../swaylock-auth-mode
   makepkg -si
   ```

3. **写入 PAM 配置（自动备份，不触碰 `system-auth` / `sudo` / `polkit-1` / `sshd`）：**

   ```bash
   cd ../..
   # 自动检测已安装的 swaylock / greetd，也可手动传参指定（如仅指定 swaylock）
   sudo ./scripts/install-pam-auth-mode.sh
   ```

   如果使用其他发行版手动配置，只需在 `/etc/pam.d/swaylock` 的 `auth include login` 之前（或 `/etc/pam.d/greetd` 的 `pam_nologin.so` 之后）加入以下两行：

   ```pam
   auth       [success=ignore default=1] pam_auth_mode_selector.so
   auth       [success=done default=die] pam_fprintd.so max-tries=1 timeout=10
   ```

---

## 回滚与卸载

一键恢复安装前自动备份的原始 PAM 文件（备份位于 `/var/backups/fprint-auth-mode/`）：

```bash
sudo ./scripts/restore-pam-auth-mode.sh
```

随时切回 Arch 官方仓库原版软件包：

```bash
sudo pacman -S libfprint swaylock
sudo pacman -Rns pam-auth-mode-selector
```

---

## 同机型补充笔记（机械革命 无界14 2026 / Lunar Lake）

- **内置扬声器（Realtek ALC233，PCI SSID `c011:1d05`）**：当前新版主线内核（如 `7.2+`）已在 `snd-hda-codec-alc269` 中原生内置针对 `c011:1d05` 的 `ALC233_FIXUP_WUJIE_SPEAKERS`（`0x1b = 0x90170150`），升级内核后即可直接出声，无需再手动配置 `patch=` 固件覆盖。
- **Niri 下的屏幕自刷新（PSR2）省电贴士**：在 Lunar Lake eDP 面板上无条件开启 `variable-refresh-rate` 会导致驱动禁用面板 `PSR2`，大幅拉高空闲功耗。建议关闭全局 VRR 或设为 `on-demand` 以保持 `PSR2` 生效。

## 开源许可

- `pam-auth-mode-selector`、`scripts/` 及文档：[MIT](LICENSE)
- `swaylock-auth-mode` 补丁：[MIT](LICENSE)（与上游 `swaylock` 一致）
- `libfprint-realtek-9011` 补丁：`LGPL-2.1-or-later`（与上游 `libfprint` 一致）
