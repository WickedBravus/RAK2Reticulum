#!/bin/bash
set -e

# 1. NEW: PROPER USER AND DIRECTORY FETCHING
# Capture the invoking non-root user and absolute repository directory
# so paths and permissions are correct even when executed via sudo.
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~${REAL_USER}")
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================="
echo "   RAK2Reticulum Base Station Installer"
echo "================================================="

# Prompt for Regional Settings
read -p "Enter Frequency (e.g., 869.525): " FREQ_IN
read -p "Enter Bandwidth in kHz (125, 250, 500): " BW_IN
read -p "Enter Spreading Factor (7, 8, 9, 10, 11, 12): " SF_IN
read -p "Enter Coding Rate (type 1 for 4/5): " CR_IN

# Format parameters for Rust injection
#FREQ_HZ=$(echo "$FREQ_IN * 1000000" | bc | cut -d. -f1)
# Format parameters for Rust injection using awk (no external package required)
FREQ_HZ=$(awk "BEGIN {print int($FREQ_IN * 1000000)}")

case $BW_IN in
    125) BW_VAL=4 ;;
    250) BW_VAL=5 ;;
    500) BW_VAL=6 ;;
    *) echo "Invalid bandwidth."; exit 1 ;;
esac

echo "[+] Compiling dynamic configuration..."
sed -e "s/{{FREQ_HZ}}/${FREQ_HZ}/g" \
    -e "s/{{BW_VAL}}/${BW_VAL}/g" \
    -e "s/{{SF_VAL}}/${SF_IN}/g" \
    -e "s/{{CR_VAL}}/${CR_IN}/g" \
    "$REPO_DIR/src/main.rs.template" > "$REPO_DIR/src/main.rs"

echo "[+] Stopping any active bridge services..."
sudo systemctl stop lora-bridge 2>/dev/null || true

echo "[+] Enabling Hardware SPI Interface..."
sudo raspi-config nonint do_spi 0

echo "[+] Disabling conflicting factory LoRa services..."
sudo systemctl stop ttn-gateway 2>/dev/null || true
sudo systemctl disable ttn-gateway 2>/dev/null || true
sudo systemctl stop chirpstack-gateway-bridge 2>/dev/null || true
sudo systemctl disable chirpstack-gateway-bridge 2>/dev/null || true
sudo systemctl stop lora_pkt_fwd 2>/dev/null || true
sudo systemctl disable lora_pkt_fwd 2>/dev/null || true

# MODIFIED: Added 'git' to the apt install list, and changed $HOME to $USER_HOME
echo "[+] Installing Dependencies and Rust..."
sudo python3 -m pip install lxmf --break-system-packages
sudo python3 -m pip install RNS --break-system-packages
sudo apt update && sudo apt install -y build-essential clang libclang-dev bc git
if ! command -v cargo &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$USER_HOME/.cargo/env"
fi

# ==============================================================================
# 2. NEW: THE SEMTECH HAL VENDORING & PATCHES
# ==============================================================================
if [ ! -d "$REPO_DIR/sx1302_hal" ]; then
    echo "[+] sx1302_hal not found. Cloning official Semtech driver..."
    git clone https://github.com/Lora-net/sx1302_hal.git "$REPO_DIR/sx1302_hal"
    rm -rf "$REPO_DIR/sx1302_hal/.git"
fi

echo "[+] Compiling base sx1302_hal..."
cd "$REPO_DIR/sx1302_hal"
make clean || true
make

#############
#echo "[+] Applying Patch 1: Injecting missing tinymt32 object..."
#TINY_SRC_DIR=$(dirname $(find "$REPO_DIR/sx1302_hal" -name "tinymt32.c" | head -n 1))
#HEADER_DIR=$(dirname $(find "$REPO_DIR/sx1302_hal" -name "tinymt32.h" | head -n 1))

#cd "$TINY_SRC_DIR"
#gcc -I "$HEADER_DIR" -c tinymt32.c -o tinymt32.o
#ar rs "$REPO_DIR/sx1302_hal/libloragw/libloragw.a" tinymt32.o

echo "[+] Applying Patch 1: Injecting missing tinymt32 object..."

HAL_DIR="$REPO_DIR/sx1302_hal"
LIB_PATH="$HAL_DIR/libloragw/libloragw.a"

# Locate the source and header files.
TINY_SRC=$(find "$HAL_DIR" -type f -name "tinymt32.c" -print -quit)
TINY_HDR=$(find "$HAL_DIR" -type f -name "tinymt32.h" -print -quit)

# Verify that both files exist.
if [ -z "$TINY_SRC" ]; then
    echo "[ERROR] tinymt32.c not found under $HAL_DIR"
    exit 1
fi

if [ -z "$TINY_HDR" ]; then
    echo "[ERROR] tinymt32.h not found under $HAL_DIR"
    exit 1
fi

if [ ! -f "$LIB_PATH" ]; then
    echo "[ERROR] HAL library not found: $LIB_PATH"
    exit 1
fi

TINY_SRC_DIR=$(dirname "$TINY_SRC")
HEADER_DIR=$(dirname "$TINY_HDR")

# Compile the missing object.
gcc -I "$HEADER_DIR" -c "$TINY_SRC" -o "$TINY_SRC_DIR/tinymt32.o" || {
    echo "[ERROR] Failed to compile tinymt32.c"
    exit 1
}

# Inject the object into the HAL static library.
ar rs "$LIB_PATH" "$TINY_SRC_DIR/tinymt32.o" || {
    echo "[ERROR] Failed to update $LIB_PATH"
    exit 1
}

echo "[+] tinymt32 object successfully injected into libloragw.a"
#############

echo "[+] Applying Patch 1: Injecting missing tinymt32 object..."
TINY_SRC_DIR=$(dirname $(find "$REPO_DIR/sx1302_hal" -name "tinymt32.c" | head -n 1))
HEADER_DIR=$(dirname $(find "$REPO_DIR/sx1302_hal" -name "tinymt32.h" | head -n 1))

cd "$TINY_SRC_DIR"
gcc -I "$HEADER_DIR" -c tinymt32.c -o tinymt32.o
ar rs "$REPO_DIR/sx1302_hal/libloragw/libloragw.a" tinymt32.o
echo "[+] Applying Patch 2: STTS751 hardware spoof & idle segfault guard..."
cd "$REPO_DIR/sx1302_hal/libloragw"
cat << 'TEMP_EOF' > fake_temp.c
#include <stddef.h>

int stts751_configure(void) { 
    return 0; 
}

int stts751_get_temperature(float * temp) { 
    if (temp == NULL || (unsigned long)temp < 0x1000) {
        return -1; 
    }
    *temp = 30.0; 
    return 0; 
}
TEMP_EOF
gcc -c fake_temp.c -o loragw_stts751.o
ar rs libloragw.a loragw_stts751.o
# ==============================================================================

echo "[+] Compiling Native Bridge (This takes a few minutes)..."
cd "$REPO_DIR"
cargo build --release

# ==============================================================================
# 3. NEW: RETICULUM CONFIG AUTO-DEPLOYMENT
# ==============================================================================
RETICULUM_DIR="$USER_HOME/.reticulum"
sudo -u "${REAL_USER}" mkdir -p "$RETICULUM_DIR"

if [ -f "$RETICULUM_DIR/config" ]; then
    echo "[+] Backing up existing Reticulum config to config.bak..."
    cp "$RETICULUM_DIR/config" "$RETICULUM_DIR/config.bak"
fi

echo "[+] Deploying RAK2Reticulum interface configuration..."
cp "$REPO_DIR/reticulum-config.example" "$RETICULUM_DIR/config"
chown -R "${REAL_USER}:${REAL_USER}" "$RETICULUM_DIR"
# ==============================================================================

# ==============================================================================
# 4. NEW: DYNAMIC SYSTEMD TEMPLATE GENERATION
# Replaces the hardcoded 'cat << SVC_EOF' block so the service runs as the safe user
# ==============================================================================
echo "[+] Generating Systemd Service with Universal Reset (GPIO 17 & 25)..."
sed -e "s|__USER__|${REAL_USER}|g" \
    -e "s|__DIR__|${REPO_DIR}|g" \
    "$REPO_DIR/lora-bridge.service.template" | sudo tee /etc/systemd/system/lora-bridge.service > /dev/null

echo "[+] Starting Base Station..."
sudo systemctl daemon-reload
sudo systemctl enable --now lora-bridge

echo "================================================="
echo "[SUCCESS] Base Station Deployed and Hardware Awake!"
echo "Verify logs with: journalctl -u lora-bridge -f"
echo "================================================="
