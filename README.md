# macbook12-ubuntu-setup

Setup scripts for my MacBook Retina (2017).

## Test environment

- Ubuntu version: 26.04 LTS
- Hardware: MacBook10,1, 12-inch Retina, Intel Core i5, 8GB RAM
- Apple specs: https://support.apple.com/kb/SP750?locale=en_US

## What this script does

`setup-macbook-ubuntu.sh` performs the following actions:

- Updates `apt` package metadata and installs required package tooling
- Installs `mpv` using `apt`
- Installs Flatpak and configures the Flathub repository
- Installs Wattage from Flathub
- Downloads and installs the latest Visual Studio Code `.deb`
- Downloads and installs the Synaptics DisplayLink repository keyring package
- Installs the DisplayLink driver from the Synaptics repository
- Installs Brave Origin browser using Brave's install script
- Attempts to install the Bitwarden browser extension into Brave
- Installs GNOME Tweaks and GNOME Shell Extension Manager
- Installs the Multi Monitor Bar GNOME extension
- Enables seconds display in the system clock
- Removes Firefox if it is installed (both `snap` and `apt` versions)
- Updates GNOME favorites to pin Brave Origin, VS Code, and Terminal to the left dock

## Hardware compatibility

### Works out of the box

- Keyboard: yes
- Trackpad: yes

### Works with patches

- Sound: yes, after installing the driver from `https://github.com/leifliddy/macbook12-audio-driver`
- Suspend: yes, with patches; the suspend patch script is still WIP

### Does not work well

- Bluetooth audio: sound is often choppy and unreliable

### Does not work

- Webcam: hardware not detected by default; a MacBook10,1-specific patch is available that requires `patjak/facetimehd` driver and Boot Camp firmware extraction

## Known bugs

- Speaker volume slider is not linear. Volume above 20% sounds almost the same, while 10% is already near half of full volume.
- The `fix-macbook-volume.sh` helper script improves this by enabling WirePlumber soft volume and pushing the sink volume higher.
- Webcam (FaceTimeHD) requires firmware extraction from Boot Camp and a kernel driver patch to work on MacBook10,1.

## Notes and workarounds

- This setup is intended for a usable Ubuntu experience on the 2017 12-inch MacBook. After installing Ubuntu, the machine is good for light web browsing and coding.
- Audio requires the third-party MacBook 12" audio driver repository and may still need fine-tuning for volume control. Use `sudo ./fix-macbook-volume.sh` after audio setup to improve speaker volume.
- Suspend works after applying the available patches, but the suspend/restore flow is still under active refinement.
- Bluetooth audio may be acceptable for casual use, but it is not reliable for media playback or long listening sessions.
- If you run into additional hardware quirks, the Ubuntu and MacBook Linux communities are the best sources for recent patches and driver workarounds.

## Prerequisites

- Ubuntu-based system
- Network access to download packages and installer files
- Must run the script as `root` or via `sudo`

## Usage

1. Make the scripts executable:

```bash
chmod +x setup-macbook-ubuntu.sh fix-macbook-*.sh
```

2. Run the main setup script as root:

```bash
sudo ./setup-macbook-ubuntu.sh
```

3. If DisplayLink requires it, reboot after the script finishes.

## Helper scripts

All helper scripts support both `install` (default) and `revert` operations. They automatically detect the current state and will skip installation if already applied.

### Volume fix helper

To install the MacBook CS4208 volume fix:

```bash
sudo ./fix-macbook-volume.sh
```

To revert:

```bash
sudo ./fix-macbook-volume.sh revert
```

This script:
- writes the WirePlumber `soft-mixer` config for the CS4208 card
- restarts WirePlumber if possible
- increases the default sink volume to `150%`

### Suspend fix helper

To enable suspend/sleep on the MacBook 12":

```bash
sudo ./fix-macbook-suspend.sh
```

To revert:

```bash
sudo ./fix-macbook-suspend.sh revert
sudo reboot
```

This script:
- checks available sleep modes on your system
- configures GRUB to force S3 sleep mode (disables deep sleep)
- updates the boot configuration
- **requires a reboot to take effect**

After reboot, test suspend with `systemctl suspend`.

### Webcam fix helper

To enable the FaceTimeHD webcam on MacBook10,1:

```bash
sudo ./fix-macbook-webcam.sh
```

To revert:

```bash
sudo ./fix-macbook-webcam.sh revert
sudo reboot
```

**Prerequisites** (must be completed first):
- Install `patjak/facetimehd` driver via DKMS
- Extract Boot Camp firmware files to `/lib/firmware/facetimehd/`

See the [firmware extraction guide](https://github.com/neron82/macbook10-1-facetimehd-linux/blob/main/docs/firmware-extraction-bootcamp-155.md) for firmware setup.

This script:
- clones the patch repository from GitHub
- applies the MacBook10,1-specific kernel driver patch
- rebuilds and reinstalls the FaceTimeHD DKMS module
- **requires a reboot to take effect**

After reboot, verify with:
```bash
strings /lib/firmware/facetimehd/firmware.bin | grep S2ISP
v4l2-ctl --device=/dev/video0 --all
```
