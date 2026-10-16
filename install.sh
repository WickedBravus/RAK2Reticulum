#!/bin/bash
set -e

echo "================================================="
echo "   RAK2Reticulum Base Station Installer"
echo "================================================="

read -p "Enter Frequency (e.g., 869.525): " FREQ_IN
read -p "Enter Bandwidth in kHz (125, 250, 500): " BW_IN
read -p "Enter Spreading Factor (7, 8, 9, 10, 11, 12): " SF_IN
read -p "Enter Coding Rate (type 1 for 4/5): " CR_IN

FREQ_HZ=$(echo "$FREQ_IN * 1000000" | bc | cut -d. -f1)

case $BW_IN in
    125) BW_VAL=4 ;;
    250) BW_VAL=5 ;;
    500) BW_VAL=6 ;;
    *) echo "Invalid bandwidth."; exit 1 ;;
esac

echo "[+] Configuring Rust Template..."
sed -e "s/{{FREQ_HZ}}/${FREQ_HZ}/g" \
    -e "s/{{BW_VAL}}/${BW_VAL}/g" \
    -e "s/{{SF_VAL}}/${SF_IN}/g" \
    -e "s/{{CR_VAL}}/${CR_IN}/g" \
    src/main.rs.template > src/main.rs

echo "[+] Installing Dependencies and Rust..."
sudo apt update && sudo apt install -y build-essential clang libclang-dev bc pinctrl
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env

echo "[+] Compiling Native Bridge..."
cargo build --release

echo "[+] Generating Systemd Service with GPIO 25 Reset..."
cat << SVC_EOF | sudo tee /etc/systemd/system/lora-bridge.service > /dev/null
[Unit]
Description=Native RAK LoRa Bridge
After=network.target rnsd.service

[Service]
Type=simple
User=root
WorkingDirectory=$PWD

# Hardware reset sequence on GPIO 25
ExecStartPre=/usr/bin/pinctrl set 25 op dh
ExecStartPre=/bin/sleep 0.2
ExecStartPre=/usr/bin/pinctrl set 25 op dl
ExecStartPre=/bin/sleep 0.2

# Main Executable
ExecStart=$PWD/target/release/rns-rak-native
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC_EOF

echo "[+] Starting Base Station..."
sudo systemctl daemon-reload
sudo systemctl enable --now lora-bridge

echo "================================================="
echo "[SUCCESS] Base Station Deployed and Hardware Awake!"
echo "Verify logs with: journalctl -u lora-bridge -f"
echo "================================================="
