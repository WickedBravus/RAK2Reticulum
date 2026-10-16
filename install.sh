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

sed -e "s/{{FREQ_HZ}}/${FREQ_HZ}/g" -e "s/{{BW_VAL}}/${BW_VAL}/g" -e "s/{{SF_VAL}}/${SF_IN}/g" -e "s/{{CR_VAL}}/${CR_IN}/g" src/main.rs.template > src/main.rs

sudo apt update && sudo apt install -y build-essential clang libclang-dev bc
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
cargo build --release

sudo cp systemd/lora-bridge.service /etc/systemd/system/
sudo sed -i "s|{{USER}}|$USER|g" /etc/systemd/system/lora-bridge.service
sudo sed -i "s|{{DIR}}|$PWD|g" /etc/systemd/system/lora-bridge.service
sudo systemctl daemon-reload
sudo systemctl enable --now lora-bridge
echo "[SUCCESS] Base Station Deployed!"
