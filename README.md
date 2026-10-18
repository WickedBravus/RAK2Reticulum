# RAK2Reticulum 📡

**Native Rust LoRa Bridge for Reticulum Network (SX1302 / SX1250)**

RAK2Reticulum is a lightweight, pure-Rust native bridge designed to directly interface industrial RAKwireless LoRa Base Stations with the [Reticulum Network](https://reticulum.network/). 

I used RAK Hotspot V2.0 Indoor with a fresh Pi OS Debian 13 Trixie install, my goal was to repurpose a capable piece of hardware that was sitting and collecting dust into something meaningful for the RF community.

By bypassing traditional, bloated LoRaWAN packet forwarders and bridging natively via UDP, this software transforms standard Raspberry Pi + RAK HAT setups into high-power, high-bandwidth Reticulum mesh routers capable of coordinating city-wide infrastructure.

---

## ✨ Core Capabilities

- **Native Reticulum Mesh:** Seamlessly route encrypted Reticulum traffic over industrial LoRa hardware without intermediate protocol translation.
- **The "Hardware Trap" Bypass:** Standard SX1302 firmwares lock demodulators to 125 kHz. This software explicitly awakens the internal **IF8 High-Speed Standalone Demodulator**, flawlessly unlocking `250 kHz` and `500 kHz` bandwidth reception for high-speed mesh configurations.
- **Maximum RF Power:** Safely drives the SX1250 RF front-ends to their maximum hardware-rated `27 dBm` output for extreme line-of-sight range.
- **Automated Deployment:** Features a dynamic bash installer that prompts for your specific regional settings (Frequency, Bandwidth, Spreading Factor, Coding Rate) and compiles a custom binary on the fly.
- **Low Overhead:** Written in Rust for memory safety, explicit Time-on-Air (ToA) transmission throttling to prevent hardware panics, and near-zero CPU overhead.

---

## 🛠 Hardware & Software Requirements

1. **Host Board:** Raspberry Pi (Zero W, 3, 4, or 5) running Raspberry Pi OS (Debian 13 Trixie recommended).
2. **LoRa Base Station HAT:** RAKwireless SX1302/SX1250 modules (e.g., **RAK2287**, **RAK5146**, or equivalent).
3. **Antenna:** A properly tuned 868/915 MHz LoRa Antenna. *(See safety warning below).*
4. **Dependencies:** The installer will automatically configure the OS and install `build-essential`, `clang`, `libclang-dev`, `bc`, `pinctrl` (for hardware resets), and the `Rust` toolchain.

---

## 🚀 Step-by-Step Installation

### 1. Enable SPI
Your Raspberry Pi requires hardware SPI enabled to communicate with the RAK HAT. *(Note: The installer script will attempt to enable this automatically, but you can verify it manually).*
```bash
sudo raspi-config
```
- Navigate to **Interface Options** -> **SPI** -> Select **Yes** to enable.
- **Reboot** your Pi.

### 2. Clone the Repository
Download the source code to your Raspberry Pi:
```bash
cd ~
git clone https://github.com/WickedBravus/RAK2Reticulum.git
cd RAK2Reticulum
```

### 3. Run the Automated Installer
Execute the installation wizard. It will install Rust, prompt you for your network's physical layer parameters, compile the bridge, and set it up as a background service.
```bash
chmod +x install.sh
./install.sh
```
**During setup, you will be prompted for:**
- **Frequency:** Standard mesh frequency in MHz. Check what your neighbors are using by visiting https://rmap.world/ 
- **Bandwidth:** Select `125`, `250`, or `500` kHz.
- **Spreading Factor:** Select `7` through `12`.
- **Coding Rate:** Typically `1` (which maps to 4/5).

In Rome, Italy, multiple Reticulum Nodes are running this configuration, so just replicate your neighbors so their devices can engage with your setup:

<img width="388" height="246" alt="image" src="https://github.com/user-attachments/assets/30345972-b394-467b-8680-f048c31511be" />

### 4. Configure Reticulum
Once installed, the Rust bridge will actively listen on UDP port `4242` and forward decrypted LoRa frames to UDP port `4243`. 

To turn your Base Station into a fully routing Mesh Node, replace the contents of your Reticulum configuration file (`~/.reticulum/config`) with the following topology. This enables Transport mode, connects the physical LoRa bridge, opens a local gateway for mobile devices (like iPhones), and connects you to the Global Testnet:

nano ~/.reticulum/config

```ini
[reticulum]
  # Enables this node to route traffic for other nodes in the Reticulum network.
  # Keep enabled to contribute to your local mesh network.
  enable_transport = True

  # Allows multiple programs to share a Reticulum instance.
  share_instance = Yes

  # Identifies the shared Reticulum instance.
  instance_name = default

[interfaces]

  # Link to the local RAK2Reticulum Rust Bridge
  # STRICT 255 MTU REQUIRED FOR PHYSICAL LORA LIMITS
  [[RustLoRaBridge]]
    type = UDPInterface
    interface_enabled = True
    listen_ip = 127.0.0.1
    listen_port = 4243
    forward_ip = 127.0.0.1
    forward_port = 4242
    mtu = 255
    bitrate = 6250

  # Accepts incoming TCP connections from iPhones/mobile apps on the local network
  [[iPhoneGateway]]
    type = TCPServerInterface
    interface_enabled = True
    listen_ip = 0.0.0.0
    listen_port = 4244

  # Connects this node to the global Reticulum Testnet routing hub, optional, set to True for live transmission demonstration purposes
  [[RNS Testnet StoppedCold]]
    type = TCPClientInterface
    enabled = yes
    interface_enabled = True
    target_host = rns.stoppedcold.com
    target_port = 4242
    mode = boundary

```

Restart your Reticulum daemon (`sudo systemctl restart rnsd` or run `rnsd` directly), and your Base Station will instantly become an active transponder on the mesh.

---

## 📊 Monitoring & Troubleshooting

The installer registers a `systemd` service named `lora-bridge` that boots automatically on startup. 

**View Live Mesh Traffic (RX/TX logs):**
```bash
journalctl -u lora-bridge -f
```

**Restart the Bridge:**
```bash
sudo systemctl restart lora-bridge
```

**Check Service Status:**
```bash
sudo systemctl status lora-bridge
```

---
## SX1302 HAL Compatibility Fix
The RAK Indoor Miner 2.0 does not include the STTS751 temperature sensor expected by parts of the standard Semtech SX1302 HAL. This can cause initialization failures or segmentation faults. Our installer patches the HAL to simulate a temperature reading and provide basic pointer checks. It also compiles and injects the missing tinymt32.o object into libloragw.a to resolve a build dependency. The modified HAL is stored in this repository and rebuilt during installation.


<img width="1085" height="266" alt="image" src="https://github.com/user-attachments/assets/cadbff7a-4b85-432c-95e2-62e5294235fb" />


## ⚠️ CRITICAL SAFETY WARNING
**NEVER power on your Raspberry Pi and RAK HAT without an antenna firmly attached.** 

Because this bridge is capable of driving the hardware at a full **27 dBm** of output power, transmitting without an attached antenna will cause the RF energy to reflect back into the circuit board, which will permanently destroy the SX1250 amplifiers in milliseconds.


