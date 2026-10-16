#!/bin/bash
# Modern GPIO reset for Raspberry Pi OS (Bookworm/Trixie)

PIN=17

echo "Resetting RAK SX1302 on GPIO $PIN..."

if command -v pinctrl &> /dev/null; then
    # Modern Pi OS command
    pinctrl set $PIN op pn dl
    sleep 0.1
    pinctrl set $PIN op pn dh
    sleep 0.1
    pinctrl set $PIN op pn dl
    sleep 0.1
else
    echo "[!] pinctrl not found! Ensure you are running Raspberry Pi OS."
    exit 1
fi

echo "Hardware Reset Complete."
