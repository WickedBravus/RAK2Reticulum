#!/bin/bash
set -e

echo "================================================="
echo "   RAK2Reticulum Base Station Installer"
echo "================================================="

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

echo "[+] Installing Dependencies and Rust..."
sudo apt update && sudo apt install -y build-essential clang libclang-dev bc
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env

echo "[+] Compiling Native Bridge (This takes a few minutes)..."
cargo build --release

echo "[+] Generating Systemd Service with Universal Reset (GPIO 17 & 25)..."
cat << SVC_EOF | sudo tee /etc/systemd/system/lora-bridge.service > /dev/null
[Unit]
Description=Native RAK LoRa Bridge
After=network.target rnsd.service

[Service]
Type=simple
User=root
WorkingDirectory=$PWD

# Universal Hardware reset sequence (Covers both RAK hardware variants)
ExecStartPre=/usr/bin/pinctrl set 17 op dh
ExecStartPre=/usr/bin/pinctrl set 25 op dh
ExecStartPre=/bin/sleep 0.2
ExecStartPre=/usr/bin/pinctrl set 17 op dl
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
