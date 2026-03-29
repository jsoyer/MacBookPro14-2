#!/usr/bin/env bash
set -euo pipefail

# MacBook Pro 14,2 (2017) - Fedora 43 Setup Script
# This script installs and configures all drivers and tweaks.
# Run as root or with sudo.

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root: sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_VERSION="$(uname -r)"

echo "============================================"
echo "MacBook Pro 14,2 - Fedora Linux Setup"
echo "Kernel: ${KERNEL_VERSION}"
echo "============================================"
echo ""

# --- Prerequisites ---
echo "[1/9] Installing prerequisites..."
dnf install -y gcc kernel-devel make patch wget dkms

# --- Sound (Cirrus CS8409) ---
echo ""
echo "[2/9] Installing sound driver (Cirrus CS8409)..."
if lsmod | grep -q snd_hda_codec_cs8409; then
    echo "  -> Already loaded, skipping."
else
    if [[ -d /tmp/snd_hda_macbookpro ]]; then
        rm -rf /tmp/snd_hda_macbookpro
    fi
    git clone https://github.com/davidjo/snd_hda_macbookpro.git /tmp/snd_hda_macbookpro
    cd /tmp/snd_hda_macbookpro
    ./install.cirrus.driver.sh -i
    echo "  -> Installed via DKMS."
fi

# --- SPI (Touch Bar, Keyboard backlight, ALS) ---
echo ""
echo "[3/9] Installing SPI drivers (Touch Bar, backlight, ALS)..."
if dkms status | grep -q "applespi"; then
    echo "  -> Already installed via DKMS, skipping."
else
    if [[ -d /tmp/macbook12-spi-driver ]]; then
        rm -rf /tmp/macbook12-spi-driver
    fi
    git clone https://github.com/roadrunner2/macbook12-spi-driver.git /tmp/macbook12-spi-driver
    cp -r /tmp/macbook12-spi-driver /usr/src/applespi-0.1
    dkms install -m applespi -v 0.1
    echo "  -> Installed via DKMS."
fi

# --- FaceTime HD Camera ---
echo ""
echo "[4/9] Installing FaceTime HD camera..."
if dkms status | grep -q "facetimehd"; then
    echo "  -> Already installed via DKMS, skipping."
else
    dnf copr enable -y frgt10/facetimehd-dkms
    dnf install -y facetimehd
    echo "  -> Installed via Copr."
fi

# FaceTime firmware
if [[ -f /lib/firmware/facetimehd/firmware.bin ]]; then
    echo "  -> Firmware already present."
else
    if [[ -d /tmp/facetimehd-firmware ]]; then
        rm -rf /tmp/facetimehd-firmware
    fi
    git clone https://github.com/patjak/facetimehd-firmware.git /tmp/facetimehd-firmware
    cd /tmp/facetimehd-firmware
    make
    make install
    echo "  -> Firmware extracted and installed."
fi

# --- WiFi (Broadcom BCM43602) ---
echo ""
echo "[5/9] Configuring WiFi (Broadcom BCM43602)..."
cp "${SCRIPT_DIR}/config/modprobe/brcmfmac.conf" /etc/modprobe.d/brcmfmac.conf
cp "${SCRIPT_DIR}/config/networkmanager/wifi-powersave-off.conf" /etc/NetworkManager/conf.d/wifi-powersave-off.conf
echo "  -> Offloading disabled, power save off."

# WiFi resume after suspend
cp "${SCRIPT_DIR}/config/networkmanager/99-wifi-resume" /etc/NetworkManager/dispatcher.d/99-wifi-resume
chmod +x /etc/NetworkManager/dispatcher.d/99-wifi-resume
echo "  -> WiFi resume dispatcher installed."

# NVRAM (optional, uncomment if needed)
# MAC_ADDR=$(iw dev wlp2s0 info 2>/dev/null | grep addr | awk '{print $2}')
# if [[ -n "${MAC_ADDR}" ]]; then
#     cp "${SCRIPT_DIR}/firmware/brcm/brcmfmac43602-pcie.txt" "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt"
#     sed -i "s/macaddr=xx:xx:xx:xx:xx:xx/macaddr=${MAC_ADDR}/" "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt"
#     ln -sf "brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt" /lib/firmware/brcm/brcmfmac43602-pcie.txt
#     echo "  -> NVRAM installed with MAC ${MAC_ADDR}."
# fi

# --- Dracut (keyboard + facetimehd firmware in initramfs) ---
echo ""
echo "[6/9] Configuring dracut..."
cp "${SCRIPT_DIR}/config/dracut/keyboard.conf" /etc/dracut.conf.d/keyboard.conf
echo "  -> SPI keyboard dracut config installed."
cp "${SCRIPT_DIR}/config/dracut/facetimehd.conf" /etc/dracut.conf.d/facetimehd.conf
echo "  -> FaceTime HD firmware dracut config installed."
echo "  -> Run 'dracut --force' to rebuild initramfs."

# --- Lid close behavior ---
echo ""
echo "[7/9] Configuring lid close behavior..."
if grep -q "HandleLidSwitchExternalPower" /etc/systemd/logind.conf; then
    echo "  -> Already configured, skipping."
else
    cat >> /etc/systemd/logind.conf << 'EOF'

# MacBook Pro lid close on AC power
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
    echo "  -> logind.conf updated."
fi

# --- libinput quirks ---
echo ""
echo "[8/9] Installing libinput quirks..."
mkdir -p /etc/libinput
cp "${SCRIPT_DIR}/config/libinput/local-overrides.quirks" /etc/libinput/local-overrides.quirks
echo "  -> Touchpad quirks installed."

# --- keyd (ISO keyboard fix) ---
echo ""
echo "[9/9] Installing keyd (ISO keyboard key swap fix)..."
if command -v keyd &>/dev/null; then
    echo "  -> keyd already installed."
else
    dnf copr enable -y alternateved/keyd
    dnf install -y keyd
    echo "  -> keyd installed via Copr."
fi
mkdir -p /etc/keyd
cp "${SCRIPT_DIR}/config/keyd/default.conf" /etc/keyd/default.conf
systemctl enable --now keyd
echo "  -> keyd configured and enabled (KEY_GRAVE <-> KEY_102ND swap)."

echo ""
echo "============================================"
echo "Setup complete. A reboot is required."
echo ""
echo "After reboot, verify with:"
echo "  dkms status"
echo "  lsmod | grep -E 'applespi|facetimehd|cs8409'"
echo "  iw dev wlp2s0 get power_save"
echo "============================================"
