# 🍎 MacBook Pro 14,2 — Linux on Fedora 43

> 🇬🇧 **English** | 🇫🇷 [Français](#-macbook-pro-142--linux-sur-fedora-43)

Complete guide to running **Fedora 43 / GNOME (Wayland)** on a **MacBook Pro 14,2** (2017 13" Touch Bar, Intel Kaby Lake).

All drivers, firmware, config files and an automated install script are included.

| 🖥️ Hardware | 📋 Details |
|---|---|
| Model | MacBook Pro 14,2 (2017, 13" Touch Bar) |
| CPU | Intel Kaby Lake |
| WiFi | Broadcom BCM43602 (`14e4:43ba`) |
| Audio | Cirrus CS8409 HDA codec |
| Camera | FaceTime HD (Broadcom) |
| Input | SPI keyboard, trackpad, Touch Bar |

---

## 📂 Repository Structure

```
MacBookPro14,2/
├── 📄 README.md                              # This guide (EN + FR)
├── 🔧 install.sh                             # Automated install script
├── config/
│   ├── bluetooth/main.conf.snippet           # 🔵 Bluez config for BLE devices
│   ├── dracut/keyboard.conf                  # ⌨️  SPI keyboard in initramfs
│   ├── dracut/facetimehd.conf                # 📷 FaceTime HD firmware in initramfs
│   ├── libinput/local-overrides.quirks       # 🖱️  Touchpad calibration
│   ├── logiops/logid.cfg                     # 🖱️  MX Master 3S gestures for GNOME
│   ├── modprobe/brcmfmac.conf               # 📶 Disable Broadcom offloading
│   ├── networkmanager/wifi-powersave-off.conf # 📶 Disable WiFi power save
│   ├── networkmanager/99-wifi-resume         # 📶 WiFi resume after suspend
│   ├── systemd/bluetooth-reconnect.service   # 🔵 BT reconnect after suspend
│   ├── keyd/default.conf                     # ⌨️  ISO keyboard key swap fix
│   └── systemd/logind.conf.snippet           # 💤 Lid close behavior
└── firmware/
    └── brcm/brcmfmac43602-pcie.txt          # 📶 WiFi NVRAM config
```

---

## ⚡ Quick Start

```bash
git clone https://github.com/<your-user>/MacBookPro14,2.git
cd MacBookPro14,2
sudo ./install.sh
sudo reboot
```

The install script handles: prerequisites, sound driver (DKMS), SPI drivers (DKMS), FaceTime HD camera (Copr + firmware extraction), WiFi config, dracut, lid close behavior, and libinput quirks.

---

## 🔊 1. Audio (Cirrus CS8409)

The MacBook Pro 2017 uses a Cirrus CS8409 HDA codec not natively supported by Linux. The [`snd_hda_macbookpro`](https://github.com/davidjo/snd_hda_macbookpro) project provides a patched driver.

### ✅ What works

- 🔈 Internal speakers (4-speaker stereo: L/R tweeter + L/R woofer)
- 🎧 Headphone jack output
- 🎤 Internal microphone (very low level — amplification needed via EasyEffects)

### ⚠️ Known limitations

- Hardware format: 2/4 channels, 44.1 kHz, S24_LE / S32_LE only
- Sound will NOT match macOS (no CoreAudio DSP filters)
- Suspend/resume: untested, hardware stays powered on

### 📦 Installation

```bash
sudo dnf install gcc kernel-devel make patch wget

git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro/

# Install via DKMS (recommended — auto-rebuilds on kernel update)
sudo ./install.cirrus.driver.sh -i
sudo reboot
```

The script auto-detects kernel version:
- `>= 6.17`: uses new kernel source layout (`hda/codecs/cirrus/`)
- `< 6.17`: redirects to `install.cirrus.driver.pre617.sh`

### 🔍 Verify

```bash
lsmod | grep cs8409
dkms status | grep snd_hda
pactl list sinks short
speaker-test -c 2
```

In GNOME Settings > Audio, select "Analogue Stereo Output" or "Analogue Stereo Duplex" for internal mic.

### 🗑️ Uninstall

```bash
sudo ./install.cirrus.driver.sh -r
```

---

## ⌨️ 2. Touch Bar, Keyboard Backlight & Ambient Light Sensor (SPI)

The MacBook Pro 14,2 uses an SPI bus for the Touch Bar, keyboard backlight, and ambient light sensor (ALS). The [`macbook12-spi-driver`](https://github.com/roadrunner2/macbook12-spi-driver) provides 4 kernel modules.

| Module | Function |
|---|---|
| `applespi` | 🔤 SPI keyboard & trackpad |
| `apple-ibridge` | 🔌 USB bridge to Touch Bar peripherals |
| `apple-ib-tb` | 📱 Touch Bar (display & buttons) |
| `apple-ib-als` | 💡 Ambient light sensor |

### ⚠️ Kernel 6.x compatibility

The upstream repo does not compile on kernel 6.x due to breaking API changes. A patch is included in this repository (`patches/0001-fix-kernel-6.x-api-changes.patch`) and is also available as a branch:

- 🔗 [jsoyer/macbook12-spi-driver `fix/kernel-6.x-api-compat`](https://github.com/jsoyer/macbook12-spi-driver/tree/fix/kernel-6.x-api-compat)

Changes: SPI delay API, IIO alloc API, EFI variable API, HID report_fixup signature, void platform_remove, header path updates. See [patch details](#-spi-driver-patch-details) at the bottom.

### 📦 Installation (DKMS)

```bash
sudo dnf install gcc kernel-devel make dkms

# Use the patched fork for kernel 6.x
git clone -b fix/kernel-6.x-api-compat https://github.com/jsoyer/macbook12-spi-driver.git
sudo cp -r macbook12-spi-driver /usr/src/applespi-0.1
sudo dkms install -m applespi -v 0.1
```

**Alternative (upstream, kernel < 6.x only):**

```bash
git clone https://github.com/roadrunner2/macbook12-spi-driver.git
```

**Alternative (Copr):**

```bash
dnf copr enable meeuw/macbook12-spi-driver-kmod
dnf install macbook12-spi-driver-kmod
```

### 🔑 Early boot (disk encryption password)

To have the keyboard available at the LUKS prompt:

```bash
# Copy config/dracut/keyboard.conf to /etc/dracut.conf.d/
sudo dracut --force
```

### 🔍 Verify

```bash
dkms status | grep applespi
lsmod | grep -E 'applespi|apple_ib|apple_ibridge'
```

### ⌨️ ISO keyboard fix (swapped `@#` and `<>` keys)

The `applespi` driver sends inverted keycodes for `KEY_GRAVE` (41) and `KEY_102ND` (86) on ISO keyboards. This swaps the `@#` key (left of `1`) with the `<>` key (next to left shift).

Fix using [`keyd`](https://github.com/rvaiya/keyd) (evdev-level remapper, works on Wayland):

```bash
# Build and install keyd (not packaged on Fedora)
sudo dnf install gcc make git
git clone https://github.com/rvaiya/keyd.git /tmp/keyd
cd /tmp/keyd && make && sudo make install

# Copy config and enable
sudo mkdir -p /etc/keyd
sudo cp config/keyd/default.conf /etc/keyd/default.conf
sudo systemctl enable --now keyd
```

> **Note:** `hwdb` rules do not work here because `applespi` does not emit `MSC_SCAN` events. XKB modifications are cached aggressively by GNOME Wayland and are unreliable for this fix.

### 📝 Notes

- Kernel >= 5.3 includes the keyboard/trackpad driver in mainline, but Touch Bar and ALS modules are NOT in mainline
- Do NOT use `noapic` in kernel parameters
- See [roadrunner2's gist](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7) for touchpad user-space tuning

---

## 📷 3. FaceTime HD Camera

The FaceTime HD camera uses a Broadcom chipset requiring proprietary Apple firmware extraction.

### 📦 Installation

```bash
# Step 1: Install driver via Copr
sudo dnf copr enable frgt10/facetimehd-dkms
sudo dnf install facetimehd

# Step 2: Extract Apple firmware
git clone https://github.com/patjak/facetimehd-firmware.git
cd facetimehd-firmware
sudo make
sudo make install

# Step 3: Include firmware in initramfs
sudo cp config/dracut/facetimehd.conf /etc/dracut.conf.d/facetimehd.conf
sudo dracut --force

# Step 4: Load
sudo modprobe facetimehd
```

The firmware extraction script downloads a slice of the macOS 10.11.5 DMG from Apple's CDN, extracts `AppleCameraInterface`, and pulls the firmware binary (SHA256-verified).

### 🔍 Verify

```bash
dkms status | grep facetimehd
lsmod | grep facetimehd
ls /lib/firmware/facetimehd/firmware.bin    # ~755 KB

# Test
cheese
# or
mpv av://v4l2:/dev/video0
```

---

## 📶 4. WiFi (Broadcom BCM43602)

| 🏷️ | Details |
|---|---|
| Chip | Broadcom BCM43602 (`14e4:43ba` rev 02) |
| Driver | `brcmfmac` |
| wpa_supplicant | v2.11 (known issues with Broadcom) |

> ⚠️ There is **NO** `clm_blob` for the BCM43602. The error `no clm_blob available` is cosmetic. Only the NVRAM `.txt` file can unlock additional channels.

### 🔧 Fix 1: Disable Broadcom offloading

Fixes WPA2/WPA3 authentication issues with wpa_supplicant 2.11.

```bash
# Or copy config/modprobe/brcmfmac.conf to /etc/modprobe.d/
echo "options brcmfmac feature_disable=0x82000" | sudo tee /etc/modprobe.d/brcmfmac.conf
```

### 🔧 Fix 2: Disable WiFi power save

Fixes disconnections after 10-15 min and high latency.

```bash
# Or copy config/networkmanager/wifi-powersave-off.conf to /etc/NetworkManager/conf.d/
cat << 'EOF' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
[connection]
wifi.powersave = 2
EOF
sudo systemctl restart NetworkManager
```

### 🔧 Fix 3: Install NVRAM config (may unlock 5GHz)

The NVRAM file `firmware/brcm/brcmfmac43602-pcie.txt` is included in this repo. You need to set your MAC address.

```bash
# Get your MAC
iw dev wlp2s0 info | grep addr

# Install with your MAC
sudo cp firmware/brcm/brcmfmac43602-pcie.txt \
  "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt"
sudo sed -i "s/macaddr=xx:xx:xx:xx:xx:xx/macaddr=YOUR:MA:CA:DD:RE:SS/" \
  "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt"
sudo ln -sf "brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt" \
  /lib/firmware/brcm/brcmfmac43602-pcie.txt

sudo reboot
```

After reboot, check if Band 2 (5GHz) appeared:

```bash
iw phy phy0 info | grep -A 5 "Band"
```

### 🔧 Fix 4: WiFi resume after suspend

```bash
# Copy config/networkmanager/99-wifi-resume to /etc/NetworkManager/dispatcher.d/
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-wifi-resume
```

### 📻 Router-side: force 5GHz to a low channel

If 5GHz remains invisible, set your router to a fixed channel: **36, 40, 44, or 48** (UNII-1 band). DFS channels (>100) are blocked.

### 🔄 Alternative: switch to iwd

```bash
sudo dnf install iwd
cat << 'EOF' | sudo tee /etc/NetworkManager/conf.d/iwd.conf
[device]
wifi.backend=iwd
EOF
sudo systemctl restart NetworkManager
```

### 🔌 Last resort: USB-C WiFi adapter

Plug-and-play chipsets on Fedora: `mt7921u`, `rtl8821cu`.

### 📊 Expected performance

| Scenario | Status |
|---|---|
| 📶 2.4GHz | ✅ Reliable after Fix 1 + Fix 2 |
| 📶 5GHz (ch 36-48) | ⚠️ OK with router on fixed low channel |
| 📶 5GHz (ch >100) | ❌ Blocked by CLM restriction |
| 🔒 WPA2 | ⚠️ 10-40 Mbps (vs 47+ on macOS) |
| 🔒 WPA3 | ❌ Unstable without Fix 1 |

---

## 🖱️ 5. Logitech MX Master 3S

### 🔵 Option A: Bluetooth (hi-res scroll, less stable)

**Configure bluez** — copy `config/bluetooth/main.conf.snippet` settings into `/etc/bluetooth/main.conf`.

**Pair via `bluetoothctl`** (not the GNOME GUI):

```bash
bluetoothctl
> power on
> agent on
> default-agent
> scan on
# Wait for "Logitech MX Master 3S", note the MAC address
> pair AA:BB:CC:DD:EE:FF
> trust AA:BB:CC:DD:EE:FF
> connect AA:BB:CC:DD:EE:FF
> scan off
> exit
```

If pairing fails, clear and retry:

```bash
sudo systemctl stop bluetooth
sudo rm -rf /var/lib/bluetooth/*
sudo systemctl start bluetooth
```

**Reconnect after suspend** — copy `config/systemd/bluetooth-reconnect.service` to `/etc/systemd/system/` and enable it.

### 🔌 Option B: Bolt USB receiver (more stable, no hi-res scroll)

Requires a USB-C adapter.

```bash
sudo dnf install solaar solaar-udev
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 🎛️ Gestures & button remapping (logiops)

```bash
sudo dnf install logiops
sudo systemctl enable --now logid
```

Copy `config/logiops/logid.cfg` to `/etc/logid.cfg`. Includes GNOME window management gestures on the thumb button.

### 🔄 Firmware update

Connect via Bolt (not Bluetooth):

```bash
sudo fwupdmgr refresh && sudo fwupdmgr update
```

---

## 💤 6. Lid Close Without Suspend (on AC Power)

Copy settings from `config/systemd/logind.conf.snippet` into `/etc/systemd/logind.conf`:

```ini
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

```bash
sudo systemctl restart systemd-logind
# ⚠️ May close your session. A reboot is safer.
```

If GNOME overrides:

```bash
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'suspend'
```

---

## 🔄 7. Post Kernel Update Maintenance

After each `dnf update` that updates the kernel, DKMS automatically rebuilds registered modules.

```bash
dkms status
# Should show for the new kernel:
# applespi/0.1 .............. installed
# facetimehd/0.6.13 ........ installed
# snd_hda_macbookpro/0.1 ... installed (if installed via -i)
```

If the sound driver was installed without DKMS:

```bash
cd snd_hda_macbookpro/
sudo ./install.cirrus.driver.sh
```

### 📋 Modified system files

| File | Purpose |
|---|---|
| `/etc/modprobe.d/brcmfmac.conf` | 📶 Disable WiFi offloading |
| `/etc/NetworkManager/conf.d/wifi-powersave-off.conf` | 📶 Disable WiFi power save |
| `/etc/NetworkManager/dispatcher.d/99-wifi-resume` | 📶 WiFi resume after suspend |
| `/etc/systemd/logind.conf` | 💤 Lid close behavior |
| `/etc/logid.cfg` | 🖱️ logiops MX Master 3S |
| `/etc/bluetooth/main.conf` | 🔵 Bluez config |
| `/etc/dracut.conf.d/keyboard.conf` | ⌨️ SPI keyboard in initramfs |
| `/etc/dracut.conf.d/facetimehd.conf` | 📷 FaceTime HD firmware in initramfs |
| `/etc/keyd/default.conf` | ⌨️ ISO keyboard key swap (keyd) |
| `/etc/libinput/local-overrides.quirks` | 🖱️ Touchpad calibration |
| `/lib/firmware/facetimehd/firmware.bin` | 📷 FaceTime HD firmware |

### 📦 Active Copr repos

| Repo | Purpose |
|---|---|
| `frgt10/facetimehd-dkms` | 📷 FaceTime HD camera module |

---

## 🔗 References & Credits

| Topic | Link |
|---|---|
| 🔊 Sound driver | [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) |
| 🔊 Sound guide | [Medium — Fix sound on Macs (Cirrus CS8409)](https://medium.com/@ranquetat/how-to-install-kernel-6-17-and-fix-sound-on-macs-cirrus-cs8409-running-linux-8641c1cf4d98) |
| ⌨️ SPI driver | [roadrunner2/macbook12-spi-driver](https://github.com/roadrunner2/macbook12-spi-driver) |
| ⌨️ SPI RPM spec | [pagure.io/fedora-macbook12-spi-driver-kmod](https://pagure.io/fedora-macbook12-spi-driver-kmod) |
| ⌨️ Full config gist | [roadrunner2's gist](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7) |
| 📷 Camera firmware | [patjak/facetimehd-firmware](https://github.com/patjak/facetimehd-firmware) |
| 📷 Camera DKMS Copr | [frgt10/facetimehd-dkms](https://copr.fedorainfracloud.org/coprs/frgt10/facetimehd-dkms/) |
| 📷 Camera kmod Copr | [mulderje/facetimehd-kmod](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/) |
| 📷 Camera wiki | [facetimehd wiki — Fedora](https://github.com/patjak/facetimehd/wiki/Installation#get-started-on-fedora) |
| 📶 WiFi NVRAM | [MikeRatcliffe's gist](https://gist.github.com/MikeRatcliffe/9614c16a8ea09731a9d5e91685bd8c80) |

---

## 🩹 SPI Driver Patch Details

The patch `patches/0001-fix-kernel-6.x-api-changes.patch` fixes the following kernel API breakages:

| File | Change | Kernel version |
|---|---|---|
| `applespi.c` | `delay_usecs` -> `delay.value` + `delay.unit` | 5.13+ |
| `applespi.c` | `asm/unaligned.h` -> `linux/unaligned.h` | 6.12+ |
| `applespi.c` | `efivar_entry_{get,set_safe}` -> `efi.{get,set}_variable` | 6.6+ |
| `applespi.c` | `no_llseek` -> `noop_llseek` | 6.8+ |
| `applespi.c` | `spi_driver.remove` returns `void` | 6.1+ |
| `apple-ibridge.c` | `hid_driver.report_fixup` returns `const __u8 *` | 6.12+ |
| `apple-ibridge.c` | `acpi_driver.ops.remove` returns `void` | 6.2+ |
| `apple-ibridge.c` | Remove `.owner` from `acpi_driver` | 6.4+ |
| `apple-ib-als.c` | `iio_device_alloc(size)` -> `iio_device_alloc(dev, size)` | 5.19+ |
| `apple-ib-als.c` | `iio_trigger_alloc(fmt)` -> `iio_trigger_alloc(dev, fmt)` | 5.19+ |
| `apple-ib-als.c` | `iio_dev->id` -> `iio_device_id(iio_dev)` | 5.19+ |
| `apple-ib-{als,tb}.c` | `platform_driver.remove` returns `void` | 6.1+ |

Tested on: Fedora 43, kernel 6.19.9-200.fc43.x86_64, MacBook Pro 14,2.

To apply manually:

```bash
cd macbook12-spi-driver
git apply /path/to/patches/0001-fix-kernel-6.x-api-changes.patch
```

---

## 📜 License

This repository is provided as-is for educational purposes. Individual drivers and firmware have their own licenses (GPL-2.0, proprietary Apple firmware).

---
---

# 🍎 MacBook Pro 14,2 — Linux sur Fedora 43

> 🇫🇷 **Français** | 🇬🇧 [English](#-macbook-pro-142--linux-on-fedora-43)

Guide complet pour faire tourner **Fedora 43 / GNOME (Wayland)** sur un **MacBook Pro 14,2** (2017 13" Touch Bar, Intel Kaby Lake).

Tous les drivers, firmwares, fichiers de config et un script d'installation automatise sont inclus.

| 🖥️ Materiel | 📋 Details |
|---|---|
| Modele | MacBook Pro 14,2 (2017, 13" Touch Bar) |
| CPU | Intel Kaby Lake |
| WiFi | Broadcom BCM43602 (`14e4:43ba`) |
| Audio | Codec HDA Cirrus CS8409 |
| Camera | FaceTime HD (Broadcom) |
| Peripheriques | Clavier SPI, trackpad, Touch Bar |

---

## 📂 Structure du depot

```
MacBookPro14,2/
├── 📄 README.md                              # Ce guide (EN + FR)
├── 🔧 install.sh                             # Script d'installation automatise
├── config/
│   ├── bluetooth/main.conf.snippet           # 🔵 Config bluez pour peripheriques BLE
│   ├── dracut/keyboard.conf                  # ⌨️  Clavier SPI dans l'initramfs
│   ├── dracut/facetimehd.conf                # 📷 Firmware FaceTime HD dans l'initramfs
│   ├── libinput/local-overrides.quirks       # 🖱️  Calibration du touchpad
│   ├── logiops/logid.cfg                     # 🖱️  Gestures MX Master 3S pour GNOME
│   ├── modprobe/brcmfmac.conf               # 📶 Desactivation offloading Broadcom
│   ├── networkmanager/wifi-powersave-off.conf # 📶 Desactivation power save WiFi
│   ├── networkmanager/99-wifi-resume         # 📶 WiFi apres suspend/resume
│   ├── systemd/bluetooth-reconnect.service   # 🔵 Reconnexion BT apres suspend
│   └── systemd/logind.conf.snippet           # 💤 Comportement fermeture du lid
└── firmware/
    └── brcm/brcmfmac43602-pcie.txt          # 📶 Config NVRAM WiFi
```

---

## ⚡ Demarrage rapide

```bash
git clone https://github.com/<votre-user>/MacBookPro14,2.git
cd MacBookPro14,2
sudo ./install.sh
sudo reboot
```

Le script gere : prerequis, driver son (DKMS), drivers SPI (DKMS), camera FaceTime HD (Copr + extraction firmware), config WiFi, dracut, comportement lid close et quirks libinput.

---

## 🔊 1. Son (Cirrus CS8409)

Le MacBook Pro 2017 utilise un codec HDA Cirrus CS8409 non supporte nativement par Linux. Le projet [`snd_hda_macbookpro`](https://github.com/davidjo/snd_hda_macbookpro) fournit un driver patche.

### ✅ Ce qui fonctionne

- 🔈 Haut-parleurs internes (4 HP stereo : tweeter + woofer L/R)
- 🎧 Sortie casque
- 🎤 Micro interne (niveau tres faible — amplification necessaire via EasyEffects)

### ⚠️ Limites connues

- Format hardware : 2/4 canaux, 44.1 kHz, S24_LE / S32_LE uniquement
- Le son ne sera PAS identique a macOS (pas de filtres DSP CoreAudio)
- Suspend/resume : non teste, le hardware reste alimente en permanence

### 📦 Installation

```bash
sudo dnf install gcc kernel-devel make patch wget

git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro/

# Installation via DKMS (recommande — recompile auto a chaque maj kernel)
sudo ./install.cirrus.driver.sh -i
sudo reboot
```

Le script detecte automatiquement la version du kernel :
- `>= 6.17` : nouvelle structure source (`hda/codecs/cirrus/`)
- `< 6.17` : redirige vers `install.cirrus.driver.pre617.sh`

### 🔍 Verification

```bash
lsmod | grep cs8409
dkms status | grep snd_hda
pactl list sinks short
speaker-test -c 2
```

Dans Parametres GNOME > Audio, selectionner "Analogue Stereo Output" ou "Analogue Stereo Duplex" pour le micro interne.

### 🗑️ Desinstallation

```bash
sudo ./install.cirrus.driver.sh -r
```

---

## ⌨️ 2. Touch Bar, Retro-eclairage clavier et Capteur de lumiere (SPI)

Le MacBook Pro 14,2 utilise un bus SPI pour la Touch Bar, le retro-eclairage du clavier et le capteur de lumiere ambiante (ALS). Le driver [`macbook12-spi-driver`](https://github.com/roadrunner2/macbook12-spi-driver) fournit 4 modules kernel.

| Module | Fonction |
|---|---|
| `applespi` | 🔤 Clavier SPI et trackpad |
| `apple-ibridge` | 🔌 Bridge USB vers les peripheriques Touch Bar |
| `apple-ib-tb` | 📱 Touch Bar (affichage et boutons) |
| `apple-ib-als` | 💡 Capteur de lumiere ambiante |

### ⚠️ Compatibilite kernel 6.x

Le repo upstream ne compile pas sur kernel 6.x a cause de changements d'API. Un patch est inclus dans ce depot (`patches/0001-fix-kernel-6.x-api-changes.patch`) et est aussi disponible en branche :

- 🔗 [jsoyer/macbook12-spi-driver `fix/kernel-6.x-api-compat`](https://github.com/jsoyer/macbook12-spi-driver/tree/fix/kernel-6.x-api-compat)

Changements : API SPI delay, API IIO alloc, API variables EFI, signature HID report_fixup, platform_remove void, chemins d'headers. Voir les [details du patch](#-details-du-patch-spi) en bas de page.

### 📦 Installation (DKMS)

```bash
sudo dnf install gcc kernel-devel make dkms

# Utiliser le fork patche pour kernel 6.x
git clone -b fix/kernel-6.x-api-compat https://github.com/jsoyer/macbook12-spi-driver.git
sudo cp -r macbook12-spi-driver /usr/src/applespi-0.1
sudo dkms install -m applespi -v 0.1
```

**Alternative (upstream, kernel < 6.x uniquement) :**

```bash
git clone https://github.com/roadrunner2/macbook12-spi-driver.git
```

**Alternative (Copr) :**

```bash
dnf copr enable meeuw/macbook12-spi-driver-kmod
dnf install macbook12-spi-driver-kmod
```

### 🔑 Boot anticipe (mot de passe chiffrement disque)

Pour avoir le clavier disponible au prompt LUKS :

```bash
# Copier config/dracut/keyboard.conf dans /etc/dracut.conf.d/
sudo dracut --force
```

### 🔍 Verification

```bash
dkms status | grep applespi
lsmod | grep -E 'applespi|apple_ib|apple_ibridge'
```

### ⌨️ Fix clavier ISO (touches `@#` et `<>` inversees)

Le driver `applespi` envoie des keycodes inverses pour `KEY_GRAVE` (41) et `KEY_102ND` (86) sur les claviers ISO. La touche `@#` (a gauche du `1`) est permutee avec la touche `<>` (a cote du shift gauche).

Fix avec [`keyd`](https://github.com/rvaiya/keyd) (remapper evdev, fonctionne sous Wayland) :

```bash
# Compiler et installer keyd (pas disponible en paquet sur Fedora)
sudo dnf install gcc make git
git clone https://github.com/rvaiya/keyd.git /tmp/keyd
cd /tmp/keyd && make && sudo make install

# Copier la config et activer
sudo mkdir -p /etc/keyd
sudo cp config/keyd/default.conf /etc/keyd/default.conf
sudo systemctl enable --now keyd
```

> **Note :** Les regles `hwdb` ne fonctionnent pas ici car `applespi` n'emet pas d'evenements `MSC_SCAN`. Les modifications XKB sont cachees agressivement par GNOME Wayland et ne sont pas fiables pour ce fix.

### 📝 Notes

- Le kernel >= 5.3 integre le driver clavier/trackpad en mainline, mais les modules Touch Bar et ALS ne sont PAS en mainline
- Ne PAS utiliser `noapic` dans les parametres kernel
- Voir le [gist de roadrunner2](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7) pour le tuning touchpad en user-space

---

## 📷 3. Camera FaceTime HD

La camera FaceTime HD utilise un chipset Broadcom necessitant l'extraction du firmware proprietaire Apple.

### 📦 Installation

```bash
# Etape 1 : Installer le driver via Copr
sudo dnf copr enable frgt10/facetimehd-dkms
sudo dnf install facetimehd

# Etape 2 : Extraire le firmware Apple
git clone https://github.com/patjak/facetimehd-firmware.git
cd facetimehd-firmware
sudo make
sudo make install

# Etape 3 : Inclure le firmware dans l'initramfs
sudo cp config/dracut/facetimehd.conf /etc/dracut.conf.d/facetimehd.conf
sudo dracut --force

# Etape 4 : Charger le module
sudo modprobe facetimehd
```

Le script d'extraction telecharge une tranche du DMG macOS 10.11.5 depuis les CDN Apple, extrait `AppleCameraInterface` et en tire le firmware binaire (verification SHA256).

### 🔍 Verification

```bash
dkms status | grep facetimehd
lsmod | grep facetimehd
ls /lib/firmware/facetimehd/firmware.bin    # ~755 Ko

# Tester
cheese
# ou
mpv av://v4l2:/dev/video0
```

---

## 📶 4. WiFi (Broadcom BCM43602)

| 🏷️ | Details |
|---|---|
| Puce | Broadcom BCM43602 (`14e4:43ba` rev 02) |
| Driver | `brcmfmac` |
| wpa_supplicant | v2.11 (problemes connus avec Broadcom) |

> ⚠️ Il n'existe **PAS** de `clm_blob` pour la BCM43602. L'erreur `no clm_blob available` est cosmetique. Seul le fichier NVRAM `.txt` peut debloquer des canaux supplementaires.

### 🔧 Fix 1 : Desactiver l'offloading Broadcom

Corrige les problemes d'authentification WPA2/WPA3 avec wpa_supplicant 2.11.

```bash
# Ou copier config/modprobe/brcmfmac.conf dans /etc/modprobe.d/
echo "options brcmfmac feature_disable=0x82000" | sudo tee /etc/modprobe.d/brcmfmac.conf
```

### 🔧 Fix 2 : Desactiver le power save WiFi

Corrige les deconnexions apres 10-15 min et la latence elevee.

```bash
# Ou copier config/networkmanager/wifi-powersave-off.conf dans /etc/NetworkManager/conf.d/
cat << 'EOF' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
[connection]
wifi.powersave = 2
EOF
sudo systemctl restart NetworkManager
```

### 🔧 Fix 3 : Installer la config NVRAM (peut debloquer le 5GHz)

Le fichier NVRAM `firmware/brcm/brcmfmac43602-pcie.txt` est inclus dans ce depot. Il faut y mettre votre adresse MAC.

```bash
# Recuperer votre MAC
iw dev wlp2s0 info | grep addr

# Installer avec votre MAC
sudo cp firmware/brcm/brcmfmac43602-pcie.txt \
  "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt"
sudo sed -i "s/macaddr=xx:xx:xx:xx:xx:xx/macaddr=VO:TR:EM:AC:AD:RS/" \
  "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt"
sudo ln -sf "brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt" \
  /lib/firmware/brcm/brcmfmac43602-pcie.txt

sudo reboot
```

Apres reboot, verifier si la Band 2 (5GHz) est apparue :

```bash
iw phy phy0 info | grep -A 5 "Band"
```

### 🔧 Fix 4 : WiFi apres suspend/resume

```bash
# Copier config/networkmanager/99-wifi-resume dans /etc/NetworkManager/dispatcher.d/
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-wifi-resume
```

### 📻 Cote routeur : forcer le 5GHz sur un canal bas

Si le 5GHz reste invisible, configurer le routeur sur un canal fixe : **36, 40, 44 ou 48** (bande UNII-1). Les canaux DFS (>100) sont bloques.

### 🔄 Alternative : passer a iwd

```bash
sudo dnf install iwd
cat << 'EOF' | sudo tee /etc/NetworkManager/conf.d/iwd.conf
[device]
wifi.backend=iwd
EOF
sudo systemctl restart NetworkManager
```

### 🔌 Dernier recours : adaptateur USB-C WiFi

Chipsets plug-and-play sur Fedora : `mt7921u`, `rtl8821cu`.

### 📊 Performances attendues

| Scenario | Statut |
|---|---|
| 📶 2.4GHz | ✅ Fiable apres Fix 1 + Fix 2 |
| 📶 5GHz (canaux 36-48) | ⚠️ OK avec routeur sur canal fixe bas |
| 📶 5GHz (canaux >100) | ❌ Bloque par restriction CLM |
| 🔒 WPA2 | ⚠️ 10-40 Mbps (vs 47+ sous macOS) |
| 🔒 WPA3 | ❌ Instable sans Fix 1 |

---

## 🖱️ 5. Logitech MX Master 3S

### 🔵 Option A : Bluetooth (scroll hi-res, moins stable)

**Configurer bluez** — copier les parametres de `config/bluetooth/main.conf.snippet` dans `/etc/bluetooth/main.conf`.

**Appairer via `bluetoothctl`** (pas le GUI GNOME) :

```bash
bluetoothctl
> power on
> agent on
> default-agent
> scan on
# Attendre "Logitech MX Master 3S" et noter l'adresse MAC
> pair AA:BB:CC:DD:EE:FF
> trust AA:BB:CC:DD:EE:FF
> connect AA:BB:CC:DD:EE:FF
> scan off
> exit
```

Si l'appairage echoue, nettoyer et recommencer :

```bash
sudo systemctl stop bluetooth
sudo rm -rf /var/lib/bluetooth/*
sudo systemctl start bluetooth
```

**Reconnexion apres suspend** — copier `config/systemd/bluetooth-reconnect.service` dans `/etc/systemd/system/` et l'activer.

### 🔌 Option B : Recepteur Bolt USB (plus stable, pas de scroll hi-res)

Necessite un adaptateur USB-C.

```bash
sudo dnf install solaar solaar-udev
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 🎛️ Gestures et remapping des boutons (logiops)

```bash
sudo dnf install logiops
sudo systemctl enable --now logid
```

Copier `config/logiops/logid.cfg` dans `/etc/logid.cfg`. Inclut les gestures GNOME de gestion des fenetres sur le bouton pouce.

### 🔄 Mise a jour firmware

Connecter via Bolt (pas Bluetooth) :

```bash
sudo fwupdmgr refresh && sudo fwupdmgr update
```

---

## 💤 6. Fermer le lid sans mise en veille (sur secteur)

Copier les parametres de `config/systemd/logind.conf.snippet` dans `/etc/systemd/logind.conf` :

```ini
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

```bash
sudo systemctl restart systemd-logind
# ⚠️ Peut fermer la session. Un reboot est plus sur.
```

Si GNOME override :

```bash
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'suspend'
```

---

## 🔄 7. Maintenance apres mise a jour kernel

Apres chaque `dnf update` qui met a jour le kernel, DKMS recompile automatiquement les modules enregistres.

```bash
dkms status
# Doit afficher pour le nouveau kernel :
# applespi/0.1 .............. installed
# facetimehd/0.6.13 ........ installed
# snd_hda_macbookpro/0.1 ... installed (si installe via -i)
```

Si le driver son a ete installe sans DKMS :

```bash
cd snd_hda_macbookpro/
sudo ./install.cirrus.driver.sh
```

### 📋 Fichiers systeme modifies

| Fichier | Role |
|---|---|
| `/etc/modprobe.d/brcmfmac.conf` | 📶 Desactive offloading WiFi |
| `/etc/NetworkManager/conf.d/wifi-powersave-off.conf` | 📶 Desactive power save WiFi |
| `/etc/NetworkManager/dispatcher.d/99-wifi-resume` | 📶 WiFi apres suspend |
| `/etc/systemd/logind.conf` | 💤 Comportement lid close |
| `/etc/logid.cfg` | 🖱️ logiops MX Master 3S |
| `/etc/bluetooth/main.conf` | 🔵 Config bluez |
| `/etc/dracut.conf.d/keyboard.conf` | ⌨️ Clavier SPI dans initramfs |
| `/etc/dracut.conf.d/facetimehd.conf` | 📷 Firmware FaceTime HD dans initramfs |
| `/etc/libinput/local-overrides.quirks` | 🖱️ Calibration touchpad |
| `/lib/firmware/facetimehd/firmware.bin` | 📷 Firmware FaceTime HD |

### 📦 Repos Copr actifs

| Repo | Usage |
|---|---|
| `frgt10/facetimehd-dkms` | 📷 Module camera FaceTime HD |

---

## 🔗 References et credits

| Sujet | Lien |
|---|---|
| 🔊 Driver son | [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) |
| 🔊 Guide son | [Medium — Fix sound on Macs (Cirrus CS8409)](https://medium.com/@ranquetat/how-to-install-kernel-6-17-and-fix-sound-on-macs-cirrus-cs8409-running-linux-8641c1cf4d98) |
| ⌨️ Driver SPI | [roadrunner2/macbook12-spi-driver](https://github.com/roadrunner2/macbook12-spi-driver) |
| ⌨️ Spec RPM SPI | [pagure.io/fedora-macbook12-spi-driver-kmod](https://pagure.io/fedora-macbook12-spi-driver-kmod) |
| ⌨️ Gist config complet | [gist de roadrunner2](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7) |
| 📷 Firmware camera | [patjak/facetimehd-firmware](https://github.com/patjak/facetimehd-firmware) |
| 📷 Camera DKMS Copr | [frgt10/facetimehd-dkms](https://copr.fedorainfracloud.org/coprs/frgt10/facetimehd-dkms/) |
| 📷 Camera kmod Copr | [mulderje/facetimehd-kmod](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/) |
| 📷 Wiki camera | [facetimehd wiki — Fedora](https://github.com/patjak/facetimehd/wiki/Installation#get-started-on-fedora) |
| 📶 NVRAM WiFi | [gist de MikeRatcliffe](https://gist.github.com/MikeRatcliffe/9614c16a8ea09731a9d5e91685bd8c80) |

---

## 🩹 Details du patch SPI

Le patch `patches/0001-fix-kernel-6.x-api-changes.patch` corrige les changements d'API kernel suivants :

| Fichier | Changement | Version kernel |
|---|---|---|
| `applespi.c` | `delay_usecs` -> `delay.value` + `delay.unit` | 5.13+ |
| `applespi.c` | `asm/unaligned.h` -> `linux/unaligned.h` | 6.12+ |
| `applespi.c` | `efivar_entry_{get,set_safe}` -> `efi.{get,set}_variable` | 6.6+ |
| `applespi.c` | `no_llseek` -> `noop_llseek` | 6.8+ |
| `applespi.c` | `spi_driver.remove` retourne `void` | 6.1+ |
| `apple-ibridge.c` | `hid_driver.report_fixup` retourne `const __u8 *` | 6.12+ |
| `apple-ibridge.c` | `acpi_driver.ops.remove` retourne `void` | 6.2+ |
| `apple-ibridge.c` | Suppression de `.owner` dans `acpi_driver` | 6.4+ |
| `apple-ib-als.c` | `iio_device_alloc(size)` -> `iio_device_alloc(dev, size)` | 5.19+ |
| `apple-ib-als.c` | `iio_trigger_alloc(fmt)` -> `iio_trigger_alloc(dev, fmt)` | 5.19+ |
| `apple-ib-als.c` | `iio_dev->id` -> `iio_device_id(iio_dev)` | 5.19+ |
| `apple-ib-{als,tb}.c` | `platform_driver.remove` retourne `void` | 6.1+ |

Teste sur : Fedora 43, kernel 6.19.9-200.fc43.x86_64, MacBook Pro 14,2.

Pour appliquer manuellement :

```bash
cd macbook12-spi-driver
git apply /path/to/patches/0001-fix-kernel-6.x-api-changes.patch
```

---

## 📜 Licence

Ce depot est fourni tel quel a des fins educatives. Les drivers et firmwares individuels ont leurs propres licences (GPL-2.0, firmware proprietaire Apple).
