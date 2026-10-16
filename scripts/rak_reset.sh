#!/bin/bash
PIN=17
echo "$PIN" > /sys/class/gpio/export 2>/dev/null || true
echo "out" > /sys/class/gpio/gpio$PIN/direction
echo "0" > /sys/class/gpio/gpio$PIN/value; sleep 0.1
echo "1" > /sys/class/gpio/gpio$PIN/value; sleep 0.1
echo "0" > /sys/class/gpio/gpio$PIN/value; sleep 0.1
echo "$PIN" > /sys/class/gpio/unexport 2>/dev/null || true
