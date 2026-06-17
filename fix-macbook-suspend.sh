#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

function section() {
  echo
  echo "===== $1 ====="
}

function grub_has_s3_setting() {
  grep -q 'mem_sleep_default=s3' /etc/default/grub
}

section "MacBook 12\" Suspend Fix (Option 1: Force S3 Sleep Mode)"

if [[ "${1:-install}" == "revert" ]]; then
  section "Reverting suspend fix"

  if [[ ! -f /etc/default/grub ]]; then
    echo "ERROR: /etc/default/grub not found."
    exit 1
  fi

  if ! grub_has_s3_setting; then
    echo "S3 sleep setting not found in GRUB. Nothing to revert."
    exit 0
  fi

  echo "Removing mem_sleep_default=s3 from GRUB configuration."
  sed -i 's/ mem_sleep_default=s3//' /etc/default/grub

  echo "Updating GRUB boot configuration."
  update-grub

  section "Summary"
  echo "Suspend fix has been reverted."
  echo
  echo "IMPORTANT: You must reboot for the changes to take effect."
  echo "  sudo reboot"

  exit 0
fi

section "Checking current sleep states"
if [[ ! -f /sys/power/mem_sleep ]]; then
  echo "ERROR: mem_sleep file not found. Your system may not support configurable sleep modes."
  exit 1
fi

echo "Available sleep modes:"
cat /sys/power/mem_sleep

section "Checking GRUB configuration"
if [[ ! -f /etc/default/grub ]]; then
  echo "ERROR: /etc/default/grub not found. This system may not use GRUB."
  exit 1
fi

echo "Current GRUB_CMDLINE_LINUX setting:"
grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub || echo "No GRUB_CMDLINE_LINUX setting found (will be added)."

section "Applying S3 sleep mode fix"

if grub_has_s3_setting; then
  echo "S3 sleep mode is already configured in GRUB."
else
  echo "Adding mem_sleep_default=s3 to GRUB configuration."

  if grep -q '^GRUB_CMDLINE_LINUX="' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 mem_sleep_default=s3"/' /etc/default/grub
  else
    echo 'GRUB_CMDLINE_LINUX="mem_sleep_default=s3"' >> /etc/default/grub
  fi

  echo "Updating GRUB boot configuration."
  update-grub
fi

section "Summary"
echo "S3 sleep mode configuration has been applied."
echo
echo "IMPORTANT: You must reboot for the changes to take effect."
echo
echo "After rebooting, you can test suspend with:"
echo "  systemctl suspend"
echo
echo "To verify the fix is working:"
echo "  cat /sys/power/mem_sleep"
echo "  (should show [s3] or similar as the active mode)"
echo
echo "To revert this fix later, run:"
echo "  sudo ./fix-macbook-suspend.sh revert"
echo "  sudo reboot"
