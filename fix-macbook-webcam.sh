#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

WEBCAM_PATCH_REPO="https://github.com/neron82/macbook10-1-facetimehd-linux.git"
WEBCAM_PATCH_DIR="/usr/local/src/macbook10-1-facetimehd-linux"
FACETIMEHD_DKMS_DIR="/usr/src/facetimehd-0.7.0.1"
PATCH_FILE="$WEBCAM_PATCH_DIR/patches/0001-macbook10-1-facetimehd-480p-fw155-support.patch"
FIRMWARE_DIR="/lib/firmware/facetimehd"

function section() {
  echo
  echo "===== $1 ====="
}

function patch_is_applied() {
  if [[ ! -d "$FACETIMEHD_DKMS_DIR" ]]; then
    return 1
  fi

  if patch -p1 --dry-run -d "$FACETIMEHD_DKMS_DIR" < "$PATCH_FILE" >/dev/null 2>&1; then
    return 1
  else
    return 0
  fi
}

function install_facetimehd_driver() {
  section "Installing patjak/facetimehd driver"

  if [[ -d "$FACETIMEHD_DKMS_DIR" ]]; then
    echo "FaceTimeHD driver already installed at $FACETIMEHD_DKMS_DIR"
    return 0
  fi

  echo "Installing build dependencies for FaceTimeHD driver."
  apt install -y git dkms gcc make libusb-1.0-0-dev

  echo "Cloning patjak/facetimehd repository (tag 0.7.0.1)."
  git clone --branch 0.7.0.1 https://github.com/patjak/facetimehd.git /usr/src/facetimehd-0.7.0.1

  echo "Building and installing FaceTimeHD DKMS module."
  cd "$FACETIMEHD_DKMS_DIR"
  dkms add -m facetimehd -v 0.7.0.1
  dkms build -m facetimehd -v 0.7.0.1 || {
    echo "ERROR: DKMS build failed."
    return 1
  }

  dkms install -m facetimehd -v 0.7.0.1 || {
    echo "ERROR: DKMS install failed."
    return 1
  }

  echo "FaceTimeHD driver installed successfully."
  return 0
}

function check_prerequisites() {
  local missing_firmware=false

  if [[ ! -d "$FACETIMEHD_DKMS_DIR" ]]; then
    echo "FaceTimeHD DKMS source not found. Will attempt to install."
    if ! install_facetimehd_driver; then
      echo "ERROR: Failed to install FaceTimeHD driver."
      return 1
    fi
  fi

  if [[ ! -d "$FIRMWARE_DIR" ]] || ! ls "$FIRMWARE_DIR"/*.bin >/dev/null 2>&1; then
    missing_firmware=true
  fi

  if $missing_firmware; then
    echo
    echo "============================================================"
    echo "ERROR: FaceTimeHD firmware files not found at $FIRMWARE_DIR"
    echo "============================================================"
    echo
    echo "You must manually extract Boot Camp firmware files."
    echo
    echo "Steps:"
    echo "1. Download Boot Camp 6.1.12 or later from Apple for Windows 10/11"
    echo "2. Run the BootCamp installation .exe inside a Windows VM"
    echo "3. Extract S2ISP firmware from BootCamp drivers:"
    echo "   Usually at: \\BroadcomFirmware\\ or \\Drivers\\BroadcomFirmware\\"
    echo "4. Copy .bin and .dat firmware files to $FIRMWARE_DIR/"
    echo
    echo "See detailed guide:"
    echo "https://github.com/neron82/macbook10-1-facetimehd-linux/blob/main/docs/firmware-extraction-bootcamp-155.md"
    echo
    return 1
  fi

  return 0
}

section "MacBook10,1 FaceTimeHD Webcam Fix"

if [[ "${1:-install}" == "revert" ]]; then
  section "Reverting FaceTimeHD patch"

  if ! patch_is_applied; then
    echo "Patch is not currently applied. Nothing to revert."
    exit 0
  fi

  if [[ ! -d "$FACETIMEHD_DKMS_DIR" ]]; then
    echo "ERROR: FaceTimeHD DKMS source not found at $FACETIMEHD_DKMS_DIR"
    exit 1
  fi

  echo "Removing patch from FaceTimeHD source tree."
  patch -p1 -R -d "$FACETIMEHD_DKMS_DIR" < "$PATCH_FILE" || {
    echo "ERROR: Failed to revert patch. You may need to manually restore the DKMS source."
    exit 1
  }

  echo "Rebuilding FaceTimeHD DKMS module."
  cd "$FACETIMEHD_DKMS_DIR"
  dkms build -m facetimehd -v 0.7.0.1 || {
    echo "ERROR: DKMS rebuild failed."
    exit 1
  }

  dkms install -m facetimehd -v 0.7.0.1 || {
    echo "ERROR: DKMS install failed."
    exit 1
  }

  section "Summary"
  echo "FaceTimeHD patch has been reverted."
  echo "Reboot to apply: sudo reboot"

  exit 0
fi

section "Checking prerequisites"
if ! check_prerequisites; then
  exit 1
fi

section "Checking patch status"
if patch_is_applied; then
  echo "FaceTimeHD patch is already applied. Skipping installation."
  exit 0
fi

echo "Patch is not applied. Proceeding with installation."

section "Cloning FaceTimeHD patch repository"
if [[ -d "$WEBCAM_PATCH_DIR" ]]; then
  echo "Repository already exists at $WEBCAM_PATCH_DIR. Updating."
  git -C "$WEBCAM_PATCH_DIR" pull --ff-only || true
else
  echo "Cloning patch repository."
  git clone "$WEBCAM_PATCH_REPO" "$WEBCAM_PATCH_DIR"
fi

section "Applying patch to FaceTimeHD DKMS source"
echo "Applying patch from $PATCH_FILE"
patch -p1 -d "$FACETIMEHD_DKMS_DIR" < "$PATCH_FILE" || {
  echo "ERROR: Failed to apply patch."
  exit 1
}

section "Rebuilding FaceTimeHD DKMS module"
cd "$FACETIMEHD_DKMS_DIR"
dkms build -m facetimehd -v 0.7.0.1 || {
  echo "ERROR: DKMS build failed."
  exit 1
}

echo "Installing DKMS module."
dkms install -m facetimehd -v 0.7.0.1 || {
  echo "ERROR: DKMS install failed."
  exit 1
}

section "Summary"
echo "FaceTimeHD MacBook10,1 fix has been applied."
echo
echo "IMPORTANT: You must reboot for the changes to take effect."
echo
echo "After reboot, verify the fix with:"
echo "  strings /lib/firmware/facetimehd/firmware.bin | grep S2ISP"
echo "  v4l2-ctl --device=/dev/video0 --all"
echo
echo "To revert this patch later, run:"
echo "  sudo ./fix-macbook-webcam.sh revert"
echo "  sudo reboot"
