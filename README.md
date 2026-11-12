<div align="right">
  <strong>English</strong> | <a href="README.zh-CN.md">简体中文</a>
</div>

# Realtek `3274:9011` libfprint Driver & Explicit PAM Auth Mode Suite

Linux fingerprint driver and Wayland lock-screen authentication suite, originally developed and verified on the **MECHREVO Wujie 14 (2026, Intel Core Ultra 200V Lunar Lake)** running Arch Linux + Niri.

This repository contains two decoupled layers that can be used **together or independently**:

1. **Hardware Driver (`packages/libfprint-realtek-9011`)**  
   Adds Match-on-Chip (MoC) support for **`3274:9011 Generic Realtek USB2.0 Finger Print Bridge`** to `libfprint` (based on upstream `master` `6f9479c`, including upstream's recent `realtek` SSM error UAF fix).
2. **Explicit PAM & Swaylock Mode Selector (`packages/pam-auth-mode-selector`, `packages/swaylock-auth-mode`)**  
   Hardware-agnostic PAM module and `swaylock` patch that give you **mutually exclusive, instant switching between Fingerprint and Password** without 10-second PAM timeouts, accidental `pam_faillock` lockouts on wake keys, or polluting shared `system-auth` / `sudo` / `polkit-1` stacks.

---

## Why Explicit PAM Mode Selection?

Standard Linux PAM configurations (`auth sufficient pam_fprintd.so` placed ahead of `pam_unix.so`) suffer from annoying UX pitfalls on Wayland lockers and minimal greeters:

- **Blocking timeouts**: Typing a password while `pam_fprintd` is waiting for a finger blocks until the fingerprint scan times out or fails.
- **Accidental `pam_faillock` lockouts**: Pressing `Enter` or Space to wake the screen submits an empty password, quickly tripping `pam_faillock` (10-minute account lockout after 3 empty presses) unless global security settings are weakened.
- **Global stack pollution**: Adding `pam_fprintd` to `system-auth` hijacks `sudo`, `su`, `sshd`, and GUI `polkit` prompts.

### How This Suite Solves It

```text
User Input ──► pam_auth_mode_selector.so
                 ├── Token == ":fp" ──► pam_fprintd.so (1 try, 10s timeout; no silent fallback)
                 └── Normal password ─► Skips pam_fprintd immediately ──► pam_unix.so
```

- **`swaylock-auth-mode`** starts in **`Fingerprint`** mode (green indicator):
  - Press **`Enter`** → submits the internal `:fp` selector token and scans your finger (`Scanning` / `Not recognized`).
  - Press **`Tab` / `Shift+Tab`** → toggles between `Fingerprint` and `Password` modes.
  - **Type any character directly** → switches to `Password` mode automatically and preserves that first keystroke.
  - Press **`Esc`** in `Password` mode → clears the buffer and returns to `Fingerprint` mode.
  - The indicator automatically hides after 5 seconds of keyboard inactivity and reappears on activity.
- **`greetd`** (or any text greeter): type your password as usual, or type `:fp` and press `Enter` to authenticate via fingerprint.

---

## Repository Layout

| Path | Description | License |
| :--- | :--- | :--- |
| [`packages/libfprint-realtek-9011/`](packages/libfprint-realtek-9011/) | Arch `PKGBUILD` + clean patch adding `3274:9011` support to `libfprint` | `LGPL-2.1-or-later` |
| [`packages/pam-auth-mode-selector/`](packages/pam-auth-mode-selector/) | Standalone `pam_auth_mode_selector.so` PAM module + CLI tester | `MIT` |
| [`packages/swaylock-auth-mode/`](packages/swaylock-auth-mode/) | `swaylock 1.8.6+ (upstream master `701a352`)` with built-in `Fingerprint` / `Password` mode UI | `MIT` |
| [`scripts/`](scripts/) | Safe installer & rollback scripts for `/etc/pam.d/{swaylock,greetd}` | `MIT` |
| [`docs/protocol-3274-9011.md`](docs/protocol-3274-9011.md) | Reverse-engineered USB protocol & firmware state-machine notes | `MIT` |

---

## Installation (Arch Linux)

### Part 1: Realtek `3274:9011` Fingerprint Driver

Verify your USB device ID first:

```bash
lsusb | grep -i 3274:9011
# Expected: ID 3274:9011 Generic Realtek USB2.0 Finger Print Bridge
```

Build and install the patched `libfprint` package alongside `fprintd`:

```bash
sudo pacman -S --needed fprintd
cd packages/libfprint-realtek-9011
makepkg -si
```

Enroll and verify your fingerprint (12 press-and-release stages):

```bash
fprintd-enroll "$USER"
fprintd-verify "$USER"
```

> **Note**: Each enrollment stage advances after a full **press and release**. `3274:9011` is automatically excluded from `udev-hwdb` USB autosuspend by this package to prevent port-reset glitches on wake.

---

### Part 2: Explicit PAM Mode Selector & Swaylock UI (Works with Any `fprintd` Sensor)

1. **Build and install the PAM selector module:**

   ```bash
   cd packages/pam-auth-mode-selector
   makepkg -si
   ```

2. **(Optional, for Swaylock users) Build and install `swaylock-auth-mode`:**

   ```bash
   cd ../swaylock-auth-mode
   makepkg -si
   ```

3. **Configure PAM for `swaylock` and/or `greetd`:**

   The installer backs up existing files under `/var/backups/fprint-auth-mode/` (`0700`, root-only) and modifies **only** the specified targets (`system-auth`, `sudo`, `polkit-1`, and `sshd` remain untouched):

   ```bash
   cd ../..
   # Auto-detect installed targets (swaylock and/or greetd), or pass explicitly:
   sudo ./scripts/install-pam-auth-mode.sh
   ```

   For manual configuration on other distributions, place these two lines right before the password `auth` stack in `/etc/pam.d/swaylock` (or after `pam_nologin.so` in `/etc/pam.d/greetd`):

   ```pam
   auth       [success=ignore default=1] pam_auth_mode_selector.so
   auth       [success=done default=die] pam_fprintd.so max-tries=1 timeout=10
   ```

---

## Rollback / Uninstall

Restore original PAM configurations from backup:

```bash
sudo ./scripts/restore-pam-auth-mode.sh
```

Revert to stock Arch packages at any time:

```bash
sudo pacman -S libfprint swaylock
sudo pacman -Rns pam-auth-mode-selector
```

---

## Hardware Notes (MECHREVO Wujie 14 2026 / Lunar Lake)

- **Internal Speakers (Realtek ALC233, PCI SSID `c011:1d05` / Codec SSID `1d05:c011`)**: Upstream Linux kernels (e.g., `7.2+`) already include the `ALC233_FIXUP_WUJIE_SPEAKERS` quirk (`0x1b = 0x90170150`) for `c011:1d05` out of the box. No manual firmware patch is required on current kernels.
- **Panel Self Refresh (PSR2) vs. VRR under Niri**: Enabling unconditional `variable-refresh-rate` disables `PSR2` on the Lunar Lake eDP panel and significantly increases idle power draw. Keep VRR disabled or set to `on-demand` so `PSR2` + selective fetch remain active.

## License

- `pam-auth-mode-selector`, `scripts/`, and documentation: [MIT](LICENSE)
- `swaylock-auth-mode` patch: [MIT](LICENSE) (matching upstream `swaylock`)
- `libfprint-realtek-9011` patch: `LGPL-2.1-or-later` (matching upstream `libfprint`)
