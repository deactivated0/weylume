---
name: weylume-install
description: Autonomous installation, dependency provisioning, compilation, and configuration of Weylume (ultralight Wayland desktop shell for Arch Linux & Labwc, adaptable to Debian, Alpine, Fedora, openSUSE).
version: 1.0.0
author: Weylume Project
tags: [quickshell, wayland, labwc, desktop-shell, rust, linux, desktop-environment, ai-agent]
---

# ❄️ Weylume Installation & Operational Skill

This skill provides autonomous AI coding assistants (such as **OpenCode**, **Antigravity**, **Codex**, or **Claude Code**) with complete instructions to install, compile, configure, and maintain **Weylume** on any Linux system.

---

## 1. Overview & Architecture

**Weylume** is an ultra-fast, modern Wayland desktop environment and shell designed for **Labwc** (also supporting Hyprland, Sway, and Wayfire).

- **Frontend**: Quickshell (QtQuick 6 / QML) utilizing hardware-accelerated Wayland protocols (`wlr-layer-shell-unstable-v1`, `ext-workspace-v1`, `wlr-foreign-toplevel-management-unstable-v1`).
- **Native Backend**: `weylume-native`, a dedicated Rust daemon providing inotify filesystem watching, zero-overhead hardware and system metrics (`/proc`, sysfs), D-Bus NetworkManager and Bluetooth bindings, PAM lock screen handling, and systemd integration.
- **Resource Footprint**:
  - Combined Steady-State RAM: **~142 MB** (Labwc: ~37 MB, Quickshell: ~100 MB, weylume-native: ~5 MB).
  - Idle CPU Usage: **0.0% – 0.5%**.
- **Fresh Install Defaults**:
  - **Taskbar Dock**: Initialized with **0 pinned apps** (`pinned.json: []`).
  - **Start Menu**: Displays **only applications physically installed on the local machine** (via dynamic `DesktopEntries` inspection). No phantom, hardcoded, or dead app entries.

---

## 2. Distribution Compatibility Matrix

| Distribution | Compatibility Level | Notes |
|---|---|---|
| **Arch Linux** | **Tier 1 (Out-of-the-Box)** | Native development environment. Quickshell and Labwc installable via pacman / AUR. |
| **Debian / Ubuntu** | **Tier 2 (AI Adaptable)** | Labwc via `apt`, Quickshell built from source or third-party PPA. Requires standard dev libraries. |
| **Fedora** | **Tier 2 (AI Adaptable)** | Labwc in standard repos. Quickshell available via COPR or built from source. |
| **Alpine Linux** | **Tier 2 (AI Adaptable)** | Extremely lightweight pairing with Labwc. Requires `elogind` or `seatd` and standard dev tools. |
| **openSUSE** | **Tier 2 (AI Adaptable)** | Labwc in standard repos. Install Rust toolchain and Qt6 dev packages. |

---

## 3. Package Dependencies

### 3.1 Arch Linux (Recommended Out-of-the-Box)

```bash
# Core system packages, compositor, and Rust toolchain
sudo pacman -S --needed \
    labwc \
    rust \
    cargo \
    pkg-config \
    glib2 \
    systemd-libs \
    pipewire \
    wireplumber \
    networkmanager \
    bluez \
    bluez-utils \
    kitty \
    pcmanfm-qt \
    ttf-font-awesome \
    ttf-nerd-fonts-symbols \
    noto-fonts \
    noto-fonts-emoji \
    noto-fonts-cjk \
    power-profiles-daemon \
    wlr-randr \
    grim \
    slurp \
    wl-clipboard

# Quickshell (QtQuick 6 desktop shell framework from AUR)
paru -S --needed quickshell-git
# Or using yay:
# yay -S --needed quickshell-git
```

### 3.2 Debian / Ubuntu Adaptations

```bash
sudo apt update
sudo apt install -y \
    labwc \
    build-essential \
    cargo \
    rustc \
    pkg-config \
    libsystemd-dev \
    libudev-dev \
    libglib2.0-dev \
    libpipewire-0.3-dev \
    libwayland-dev \
    libpam0g-dev \
    kitty \
    fonts-font-awesome \
    fonts-noto-color-emoji \
    network-manager \
    wireplumber \
    pipewire \
    grim \
    slurp \
    wl-clipboard
```
> *Note for AI Agents:* Quickshell on Debian/Ubuntu can be compiled from source (`git clone https://git.outfoxxed.me/outfoxxed/quickshell && cmake -B build && cmake --build build --target install`).

### 3.3 Fedora Adaptations

```bash
sudo dnf install -y \
    labwc \
    cargo \
    rust \
    pkgconf-pkg-config \
    systemd-devel \
    libudev-devel \
    glib2-devel \
    pipewire-devel \
    wayland-devel \
    pam-devel \
    kitty \
    fontawesome-fonts \
    google-noto-emoji-fonts \
    NetworkManager \
    wireplumber \
    pipewire \
    grim \
    slurp \
    wl-clipboard
```

---

## 4. Step-by-Step Autonomous Installation Workflow

When asked to install or deploy Weylume, execute the following sequential pipeline:

### Step 1: Clone Repository
Clone the repository into the standard Quickshell user configuration directory:

```bash
TARGET_DIR="$HOME/.config/quickshell/weylume"

if [ -d "$TARGET_DIR/.git" ]; then
    echo "Weylume repository already exists at $TARGET_DIR. Pulling latest master..."
    git -C "$TARGET_DIR" pull --ff-only origin master
else
    mkdir -p "$(dirname "$TARGET_DIR")"
    git clone https://github.com/deactivated0/weylume.git "$TARGET_DIR"
fi

cd "$TARGET_DIR"
```

### Step 2: Build & Link the Native Rust Daemon
The native daemon handles filesystem monitoring, hardware sensors, and low-latency IPC:

```bash
cd "$TARGET_DIR"

# Build optimized release binary
cargo build --release --locked --manifest-path native/Cargo.toml

# Copy binary to repository root and ensure execution permission
cp native/target/release/weylume-native ./weylume-native
chmod +x ./weylume-native

# Validate test suite
cargo test --release --locked --manifest-path native/Cargo.toml
```

### Step 3: Ensure Clean State Defaults
Ensure fresh state files exist and default to 0 pinned apps:

```bash
cd "$TARGET_DIR"

# Initialize clean state if files do not exist
[ ! -f pinned.json ] && echo "[]" > pinned.json
[ ! -f start_favorites.json ] && echo "[]" > start_favorites.json
```

### Step 4: Configure Labwc Integration
Ensure Labwc keybindings and autostart are configured:

1. **Autostart** (`~/.config/labwc/autostart`):
```bash
mkdir -p "$HOME/.config/labwc"

# Ensure quickshell is started if not using systemd user service
if ! grep -q "quickshell" "$HOME/.config/labwc/autostart" 2>/dev/null; then
    cat << 'EOF' >> "$HOME/.config/labwc/autostart"
# Start Weylume Desktop Shell
systemctl --user start quickshell-weylume.service || qs -c weylume &
EOF
fi
```

2. **Keybindings** (`~/.config/labwc/rc.xml`):
Add standard bindings inside the `<keyboard>` section if not already present:
```xml
<!-- Weylume Desktop Shell Shortcuts -->
<keybind key="Super">
  <action name="Execute" command="qs -c weylume ipc call shell toggleStart" />
</keybind>
<keybind key="A-F4">
  <action name="Close" />
</keybind>
<keybind key="Super-a">
  <action name="Execute" command="qs -c weylume ipc call shell toggleQuick" />
</keybind>
<keybind key="Super-v">
  <action name="Execute" command="qs -c weylume ipc call shell toggleClipboard" />
</keybind>
<keybind key="Super-period">
  <action name="Execute" command="qs -c weylume ipc call shell toggleEmoji" />
</keybind>
<keybind key="Super-n">
  <action name="Execute" command="qs -c weylume ipc call shell toggleNotif" />
</keybind>
<keybind key="Print">
  <action name="Execute" command="qs -c weylume ipc call shell screenshot area" />
</keybind>
<keybind key="Super-l">
  <action name="Execute" command="qs -c weylume ipc call shell lock" />
</keybind>
<keybind key="C-S-n">
  <action name="Execute" command="qs -c weylume ipc call shell createFolder" />
</keybind>
```

### Step 5: Install & Enable Systemd User Service

```bash
mkdir -p "$HOME/.config/systemd/user"

cat << 'EOF' > "$HOME/.config/systemd/user/quickshell-weylume.service"
[Unit]
Description=Quickshell Weylume Desktop Shell
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/qs -c weylume
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now quickshell-weylume.service
```

---

## 5. Verification & Health Checks

Verify that Weylume is running properly:

```bash
# 1. Check systemd service status
systemctl --user status quickshell-weylume.service --no-pager

# 2. Check process tree and resource usage
ps -C qs,weylume-native,labwc -o pid,comm,pmem,pcpu,rss

# 3. Verify IPC responsiveness
qs -c weylume ipc call shell toggleStart
sleep 0.5
qs -c weylume ipc call shell toggleStart
```

---

## 6. IPC Command Reference

| Action | IPC Command | Description |
|---|---|---|
| Toggle Start Menu | `qs -c weylume ipc call shell toggleStart` | Opens / closes Start Menu |
| Toggle Quick Settings | `qs -c weylume ipc call shell toggleQuick` | Opens / closes Quick Settings |
| Toggle Audio Mixer | `qs -c weylume ipc call shell toggleMixer` | Opens / closes Audio Mixer flyout |
| Toggle Notification Center | `qs -c weylume ipc call shell toggleNotif` | Opens / closes Notification / Calendar panel |
| Toggle Clipboard History | `qs -c weylume ipc call shell toggleClipboard` | Opens / closes Clipboard History flyout |
| Toggle Emoji Picker | `qs -c weylume ipc call shell toggleEmoji` | Opens / closes Emoji Selector flyout |
| Create Folder on Desktop | `qs -c weylume ipc call shell createFolder` | Creates new unique folder with inline rename |
| Area Screenshot | `qs -c weylume ipc call shell screenshot "area"` | Interactive rectangle screen grab |
| Full Screenshot | `qs -c weylume ipc call shell screenshot "all"` | Full-screen capture to ~/Pictures/Screenshots |
| Lock Screen | `qs -c weylume ipc call shell lock` | Activates Wayland PAM lock screen |

---

## 7. Troubleshooting & Diagnostics

- **Quickshell crashes or exits with 127**:
  - Check if `quickshell` binary is in `/usr/bin/qs` or `~/.cargo/bin/qs`.
  - Run `qs -c weylume` directly in terminal to inspect QML errors.
- **Icons look broken or show default placeholders**:
  - Install Nerd Fonts or Font Awesome (`ttf-font-awesome`, `ttf-nerd-fonts-symbols`).
  - Run `fc-cache -fv`.
- **Audio mixer shows no devices**:
  - Ensure PipeWire and WirePlumber are active: `systemctl --user status wireplumber`.
- **Start Menu shows 0 apps**:
  - Verify that `.desktop` files exist in `/usr/share/applications` or `~/.local/share/applications`.
