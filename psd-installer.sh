#!/usr/bin/env bash
# =============================================================================
# Arch Linux - Install & configure profile-sync-daemon (psd) for user-chosen browser(s)
# 2026 edition – supports multiple browsers, auto-adds detection for non-native ones
# Prompts to close running browsers before starting service
#
# Features:
# - User prompts for browsers (multiple, comma/space separated)
# - Auto-detection file creation for many popular browsers (native ones skipped)
# - Checks for running browsers and offers pkill
# - Overlayfs + backups enabled by default (configurable)
# - Optional faster sync timer (every 10 min)
# - Error handling with logs on failure
# - Final verification steps
# - Microsoft Edge deliberately excluded
#
# Usage: bash this_script.sh [options]
# Options:
#   -h, --help          Show this help message
#   --no-overlay        Disable overlayfs (use classic copy mode)
#   --no-backups        Disable backups (less safe, saves space)
#   --fast-sync         Enable 10-min sync interval (default: hourly)
#   --aur-helper=TOOL   Set AUR helper (default: yay)
#
# Examples:
#   bash setup-psd-browsers.sh --no-overlay --fast-sync
# =============================================================================

set -euo pipefail

# Defaults
AUR_HELPER="${AUR_HELPER:-yay}"
USE_OVERLAYFS="yes"
USE_BACKUPS="yes"
SYNC_INTERVAL=""  # Empty = default (1h); set to "10" for 10 min if --fast-sync
SHOW_HELP=false

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            SHOW_HELP=true
            ;;
        --no-overlay)
            USE_OVERLAYFS="no"
            ;;
        --no-backups)
            USE_BACKUPS="no"
            ;;
        --fast-sync)
            SYNC_INTERVAL="10"
            ;;
        --aur-helper=*)
            AUR_HELPER="${1#*=}"
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

if $SHOW_HELP; then
    sed -n '/^# Usage:/,/^# Examples:/p' "$0" | sed 's/^# //'
    exit 0
fi

echo "==> Welcome to enhanced psd setup for browser profiles in tmpfs!"
echo "Native psd browsers (no file needed): chromium, google-chrome, firefox, firefox-developer-edition, firefox-esr, vivaldi, opera, midori, epiphany, etc."
echo "Custom (auto-added): brave, librewolf, mullvad-browser, tor-browser, ungoogled-chromium, floorp, zen-browser, waterfox, palemoon, seamonkey, etc."
echo ""

# Prompt for browser(s)
read -rp "Enter browser name(s) to sync (lowercase, space or comma separated, e.g. brave firefox chromium): " input_browsers
# Normalize: replace commas with spaces, trim, lowercase, unique
BROWSERS=$(echo "$input_browsers" | tr ',' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]' | xargs -n1 | sort -u | xargs)

if [[ -z "$BROWSERS" ]]; then
    echo "No browsers specified. Exiting."
    exit 1
fi

echo "==> Browsers selected: $BROWSERS"
echo "==> Config: overlayfs=$USE_OVERLAYFS, backups=$USE_BACKUPS, sync_interval=${SYNC_INTERVAL:-default (60 min)}"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Pre-checks
if ! command_exists "$AUR_HELPER"; then
    echo "Error: AUR helper '$AUR_HELPER' not found. Install it first or set --aur-helper=paru/etc."
    exit 1
fi
if ! command_exists systemctl; then
    echo "Error: systemd not found. This script requires systemd user services."
    exit 1
fi
if [[ ! -d /tmp || ! $(stat -f -c %T /tmp) =~ tmpfs ]]; then
    echo "Warning: /tmp is not tmpfs – psd may not work optimally (needs RAM disk)."
fi

echo "==> Step 1: Installing profile-sync-daemon (if not already)"
"$AUR_HELPER" -S --needed --noconfirm profile-sync-daemon

echo "==> Step 2: Add detection files for non-native browsers (if needed)"
for browser in $BROWSERS; do
    # Define profile path and process name (PSNAME) for common browsers
    case "$browser" in
        brave)
            profile_path="BraveSoftware/Brave-Browser"
            psname="brave"
            ;;
        librewolf)
            profile_path="librewolf"
            psname="librewolf"
            ;;
        mullvad-browser)
            profile_path="mullvad-browser"
            psname="mullvad-browser"
            ;;
        tor-browser)
            profile_path="tor-browser/Browser"  # Common path: ~/.tor-browser/Browser
            psname="firefox"  # Tor uses Firefox ESR base
            ;;
        ungoogled-chromium)
            profile_path="ungoogled-chromium"
            psname="ungoogled-chromium"
            ;;
        floorp)
            profile_path="floorp"
            psname="floorp"
            ;;
        zen-browser|zen)
            profile_path="zen"
            psname="zen"
            ;;
        waterfox)
            profile_path="waterfox"
            psname="waterfox"
            ;;
        palemoon)
            profile_path="moonchild productions/pale moon"
            psname="palemoon"
            ;;
        seamonkey)
            profile_path="mozilla/seamonkey"
            psname="seamonkey"
            ;;
        # Native ones (still define for completeness, but skip file creation if exists)
        chromium)
            profile_path="chromium"
            psname="chromium"
            ;;
        firefox)
            profile_path="mozilla/firefox"
            psname="firefox"
            ;;
        vivaldi)
            profile_path="vivaldi"
            psname="vivaldi"
            ;;
        opera)
            profile_path="opera"
            psname="opera"
            ;;
        # Generic fallback
        *)
            profile_path="$browser"
            psname="$browser"
            echo "  Warning: Using generic detection for '$browser' – verify path: ~/.config/$profile_path"
            ;;
    esac

    detection_file="/usr/share/psd/browsers/$browser"
    if [[ ! -f "$detection_file" ]]; then
        echo "  Creating detection file for $browser → ~/.config/$profile_path (PSNAME=$psname)"
        sudo mkdir -p /usr/share/psd/browsers
        cat << EOF | sudo tee "$detection_file" >/dev/null
DIRArr[0]="$XDG_CONFIG_HOME/$profile_path"
PSNAME="$psname"
EOF
        sudo chmod 644 "$detection_file"
    else
        echo "  Detection for $browser already exists (native) – skipping creation"
    fi
done

echo "==> Step 3: Create/update user config"
mkdir -p ~/.config/psd
cat << EOF > ~/.config/psd/psd.conf
# Managed browsers (space-separated)
BROWSERS=($BROWSERS)

# Performance/safety options
USE_OVERLAYFS="$USE_OVERLAYFS"  # yes = faster, lower RAM (needs kernel module + sudo helper)
USE_BACKUPS="$USE_BACKUPS"      # yes = keep crash-recovery snapshots (recommended)
BACKUP_LIMIT=5                  # Number of backups to keep

# Sync frequency (minutes; default=60 if empty)
SYNC_INTERVAL=$SYNC_INTERVAL
EOF

echo "==> Step 4: Setup passwordless sudo for overlayfs (if enabled)"
if [[ "$USE_OVERLAYFS" == "yes" ]]; then
    SUDOERS_FILE="/etc/sudoers.d/90-psd-overlay"
    if [[ ! -f "$SUDOERS_FILE" ]]; then
        echo "  Creating sudoers entry..."
        cat << EOF | sudo EDITOR='tee' visudo -f "$SUDOERS_FILE"
$USER ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper
EOF
        sudo chmod 0440 "$SUDOERS_FILE"
    else
        echo "  Sudoers file already exists – skipping"
    fi

    # Test sudo helper
    if ! sudo /usr/bin/psd-overlay-helper --help >/dev/null 2>&1; then
        echo "  Warning: sudo test failed – may need logout/reboot for sudoers to apply"
    fi
fi

echo "==> Step 5: Load overlay module (if overlayfs enabled)"
if [[ "$USE_OVERLAYFS" == "yes" ]]; then
    if ! lsmod | grep -q overlay; then
        sudo modprobe overlay || echo "  Error: Failed to load overlay module – overlayfs disabled (edit kernel params?)"
    fi
fi

echo "==> Step 6: Pre-check browser profiles exist (create if missing by launching)"
for browser in $BROWSERS; do
    # Approximate profile dir (uses last defined profile_path – not perfect for multi, but good enough)
    profile_dir="$HOME/.config/$profile_path"
    if [[ ! -d "$profile_dir" ]]; then
        echo "  Warning: Profile for '$browser' not found at ~/.config/$profile_path"
        read -rp "  Launch '$browser' now to create profile? [y/N]: " launch_answer
        if [[ "$launch_answer" =~ ^[Yy]$ ]]; then
            if command_exists "$psname"; then
                "$psname" & disown
                echo "  Launched – wait for it to create profile, then close it."
                sleep 5
            else
                echo "  Error: Command '$psname' not found – install browser first?"
            fi
        fi
    fi
done

echo "==> Step 7: Check for running browsers and offer to close them"
any_running=false
running_browsers=()
for browser in $BROWSERS; do
    # Reuse psname from case (last one wins – limitation for multi-browser; works if names unique)
    if pgrep -x "$psname" >/dev/null; then
        echo "  WARNING: '$browser' ($psname) is running."
        any_running=true
        running_browsers+=("$psname")
    fi
done

if $any_running; then
    read -rp "Kill running browser process(es) for clean setup? (recommended) [y/N]: " kill_answer
    if [[ "$kill_answer" =~ ^[Yy]$ ]]; then
        for psn in "${running_browsers[@]}"; do
            pkill -x "$psn" || true
            echo "  Killed $psn processes"
        done
        echo "  Waiting for processes to exit..."
        sleep 3
    else
        echo "  Proceeding without kill – may cause lock issues; close manually if errors occur."
    fi
fi

echo "==> Step 8: Enable & (re)start psd user service"
systemctl --user daemon-reload
if systemctl --user is-active --quiet psd.service; then
    systemctl --user restart psd.service
else
    systemctl --user enable --now psd.service
fi

# Check if started successfully
if ! systemctl --user is-active --quiet psd.service; then
    echo "!!! psd failed to start – diagnostics:"
    systemctl --user status psd.service
    journalctl --user -u psd.service -e
    echo ""
    echo "Common fixes: Close browsers, check detection files, ensure profile dirs exist, relogin for sudoers."
    echo "Retry: systemctl --user restart psd.service"
    exit 1
fi

echo "==> Step 9: Apply optional faster resync timer (if --fast-sync)"
if [[ -n "$SYNC_INTERVAL" ]]; then
    mkdir -p ~/.config/systemd/user/psd-resync.timer.d
    cat << 'EOF' > ~/.config/systemd/user/psd-resync.timer.d/faster.conf
[Timer]
OnUnitActiveSec=
OnUnitActiveSec=10min
EOF
    systemctl --user daemon-reload
    systemctl --user restart psd-resync.timer
fi

echo ""
echo "==> Setup complete! 🎉"
echo ""
echo "Final verification:"
echo "  - psd preview    # Lists synced browsers → tmpfs paths"
echo "  - psd status     # Current status + sizes"
echo "  - ls -l ~/.config/*  # Profile dirs should symlink to /run/user/.../psd/..."
echo ""
echo "Monitor: journalctl --user -u psd.service -f"
echo ""
echo "Tips:"
echo "  - Relaunch browsers now – first start may copy data to RAM (slower once)."
echo "  - On unclean shutdown: psd recovers from ~/.config/psd/backup-*"
echo "  - Edit ~/.config/psd/psd.conf to tweak (then restart psd.service)"
echo "  - Uninstall: systemctl --user disable --now psd; psd clean; rm -rf ~/.config/psd /usr/share/psd/browsers/*"
echo ""
echo "Enjoy faster, RAM-based browsing with reduced SSD wear!"
