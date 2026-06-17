#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

SUDO_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
AUDIO_CONFIG_PATH="/etc/wireplumber/wireplumber.conf.d/51-macbook-cs4208-softvol.conf"

function section() {
  echo
  echo "===== $1 ====="
}

function write_config() {
  if [[ -f "$AUDIO_CONFIG_PATH" ]]; then
    echo "WirePlumber soft volume config already exists at $AUDIO_CONFIG_PATH."
    return
  fi

  echo "Writing WirePlumber soft volume config."
  mkdir -p "$(dirname "$AUDIO_CONFIG_PATH")"
  cat > "$AUDIO_CONFIG_PATH" <<'EOFCONF'
# MacBook9,1 / MacBook10,1 CS4208 - force software volume (WirePlumber 0.5+)
# The internal speaker has no usable hardware volume control, so PipeWire must
# apply volume in software for the card.
monitor.alsa.rules = [
  {
    matches = [ { device.name = "alsa_card.pci-0000_00_1f.3" } ]
    actions = { update-props = { api.alsa.soft-mixer = true } }
  }
]
EOFCONF
}

function restart_wireplumber() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not found; cannot restart WirePlumber."
    return
  fi

  USER_UID="$(id -u "$SUDO_USER")"
  if [[ ! -d "/run/user/$USER_UID" ]]; then
    echo "User runtime directory /run/user/$USER_UID not available; cannot restart WirePlumber."
    return
  fi

  if ! command -v dbus-launch >/dev/null 2>&1; then
    echo "dbus-launch not installed; skipping WirePlumber restart."
    return
  fi

  echo "Restarting WirePlumber."
  sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" dbus-launch systemctl --user restart wireplumber || true
}

function set_max_volume() {
  if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    echo "Setting default sink volume to 150%."
    pactl set-sink-volume @DEFAULT_SINK@ 150% || true
  else
    echo "Skipping pactl volume adjust; PipeWire/PulseAudio unavailable."
  fi

  if command -v wpctl >/dev/null 2>&1 && wpctl status >/dev/null 2>&1; then
    wpctl set-volume @DEFAULT_SINK@ 150% || true
  else
    echo "Skipping wpctl volume adjust; PipeWire unavailable."
  fi
}

function reset_volume() {
  if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    echo "Resetting volume to 100%."
    pactl set-sink-volume @DEFAULT_SINK@ 100% || true
  fi

  if command -v wpctl >/dev/null 2>&1 && wpctl status >/dev/null 2>&1; then
    wpctl set-volume @DEFAULT_SINK@ 100% || true
  fi
}

section "MacBook volume fix"

if [[ "${1:-install}" == "revert" ]]; then
  section "Reverting MacBook volume fix"

  if [[ ! -f "$AUDIO_CONFIG_PATH" ]]; then
    echo "WirePlumber config not found. Nothing to revert."
    exit 0
  fi

  echo "Removing WirePlumber soft volume config."
  rm -f "$AUDIO_CONFIG_PATH"

  reset_volume
  restart_wireplumber

  section "Summary"
  echo "MacBook volume fix has been reverted."
  exit 0
fi

section "Applying MacBook volume fix"
write_config
restart_wireplumber
set_max_volume

echo "Volume fix applied. If audio still seems low, reboot and verify the WirePlumber config file exists at $AUDIO_CONFIG_PATH."
echo
echo "To revert this fix later, run:"
echo "  sudo ./fix-macbook-volume.sh revert"
