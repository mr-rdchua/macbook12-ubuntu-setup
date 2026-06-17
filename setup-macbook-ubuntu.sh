#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

SUDO_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
AUDIO_REPO_DIR="/usr/local/src/macbook12-audio-driver"
AUDIO_CONFIG_PATH="/etc/wireplumber/wireplumber.conf.d/51-macbook-cs4208-softvol.conf"

function section() {
  echo
  echo "===== $1 ====="
}

function package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

function flatpak_installed() {
  flatpak info "$1" >/dev/null 2>&1
}

function brave_cli_supports_extensions() {
  command -v brave-browser >/dev/null 2>&1 && brave-browser --help 2>&1 | grep -q -- '--install-extension'
}

function audio_driver_installed() {
  if dkms status | grep -E '^(macbook12-audio|macbook12-audio-driver)/' >/dev/null 2>&1; then
    return 0
  fi

  if ls /lib/modules/$(uname -r)/updates/dkms/snd-hda-codec-cs420x.ko* >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

section "Preparing the system"
apt update
apt install -y \
  curl gnupg apt-transport-https ca-certificates software-properties-common wget git make gcc dkms linux-headers-$(uname -r) dbus-x11

section "Installing MacBook audio driver patch"
if audio_driver_installed; then
  echo "Audio driver is already installed via DKMS. Skipping audio install."
else
  if [[ -d "$AUDIO_REPO_DIR" ]]; then
    echo "Audio driver repo already exists at $AUDIO_REPO_DIR. Updating repository."
    git -C "$AUDIO_REPO_DIR" pull --ff-only || true
  else
    echo "Cloning audio driver repository to $AUDIO_REPO_DIR."
    git clone https://github.com/breitburg/macbook12-audio-driver.git "$AUDIO_REPO_DIR"
  fi

  echo "Building and installing the audio driver with DKMS."
  cd "$AUDIO_REPO_DIR"
  ./install.cirrus.driver.sh -i
fi

if [[ ! -f "$AUDIO_CONFIG_PATH" ]]; then
  echo "Writing WirePlumber soft volume configuration."
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
else
  echo "WirePlumber soft volume configuration already exists."
fi

section "Installing base software"
apt install -y mpv flatpak
if ! flatpak remote-list | grep -q '^flathub'; then
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

if flatpak_installed io.github.v81d.Wattage; then
  echo "Wattage is already installed via Flatpak."
else
  flatpak install -y flathub io.github.v81d.Wattage
fi

section "Installing Visual Studio Code"
if package_installed code; then
  echo "VS Code is already installed."
else
  VSCODE_DEB="/tmp/vscode_latest_amd64.deb"
  curl -fsSL -o "$VSCODE_DEB" "https://update.code.visualstudio.com/latest/linux-deb-x64/stable"
  dpkg -i "$VSCODE_DEB" || apt install -fy
  rm -f "$VSCODE_DEB"
fi

section "Installing DisplayLink"
if ! package_installed synaptics-repository-keyring; then
  DISPLAYLINK_DEB="/tmp/synaptics-repository-keyring.deb"
  curl -fsSL -o "$DISPLAYLINK_DEB" "https://www.synaptics.com/sites/default/files/Ubuntu/pool/stable/main/all/synaptics-repository-keyring.deb"
  dpkg -i "$DISPLAYLINK_DEB" || apt install -fy
  rm -f "$DISPLAYLINK_DEB"
else
  echo "DisplayLink repository keyring already installed."
fi
apt update
if package_installed displaylink-driver; then
  echo "DisplayLink driver package already installed."
else
  apt install -y displaylink-driver || true
fi

section "Installing Brave Origin browser"
if package_installed brave-origin-browser || package_installed brave-browser; then
  echo "Brave browser is already installed."
else
  curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh
fi

if brave_cli_supports_extensions; then
  echo "Attempting to install Bitwarden extension into Brave."
  brave-browser --install-extension nngceckbapebfimnlniiiahkandclblb || echo "Bitwarden extension install failed or is not supported by this Brave build."
else
  echo "Brave CLI does not support extension installation; please install Bitwarden manually if needed."
fi

section "Installing GNOME tweaks and extensions"
apt install -y gnome-tweaks gnome-shell-extension-manager

echo "Enabling clock to show seconds."
sudo -u "$SUDO_USER" dbus-launch gsettings set org.gnome.desktop.interface clock-show-seconds true || true

echo "Attempting to install Multi Monitor Bar GNOME extension."
if command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions install --from-zip <(curl -fsSL "https://extensions.gnome.org/download-extension/multmonitorbar@mzur.github.com.shell-extension.zip") 2>/dev/null || echo "Multi Monitor Bar install via gnome-extensions failed."
else
  echo "gnome-extensions command not found; Multi Monitor Bar must be installed manually via GNOME Extensions app."
fi

section "Removing Firefox and configuring favorites"
if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
  snap remove firefox || true
fi
apt purge -y firefox || true
apt autoremove -y

FAVORITES=("brave-origin-browser.desktop" "code.desktop" "org.gnome.Terminal.desktop")
if ! ls /usr/share/applications/brave-origin-browser.desktop >/dev/null 2>&1; then
  FAVORITES=("brave-browser.desktop" "code.desktop" "org.gnome.Terminal.desktop")
fi
if ! ls /usr/share/applications/org.gnome.Terminal.desktop >/dev/null 2>&1; then
  FAVORITES=("brave-browser.desktop" "code.desktop" "gnome-terminal.desktop")
fi

FAVORITES_STRING="["
for desktop in "${FAVORITES[@]}"; do
  FAVORITES_STRING+="'${desktop}', "
done
FAVORITES_STRING=${FAVORITES_STRING%, }
FAVORITES_STRING+="]"

sudo -u "$SUDO_USER" dbus-launch gsettings set org.gnome.shell favorite-apps "$FAVORITES_STRING" || true

section "Finalizing"
if command -v amixer >/dev/null 2>&1; then
  if amixer -D default info >/dev/null 2>&1; then
    amixer -D default sset Master 100% unmute || true
  else
    echo "Skipping amixer; audio host is down."
  fi
fi
if command -v alsactl >/dev/null 2>&1; then
  alsactl store || true
fi
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
if command -v systemctl >/dev/null 2>&1; then
  USER_UID="$(id -u "$SUDO_USER")"
  if [[ -d "/run/user/$USER_UID" ]]; then
    if command -v dbus-launch >/dev/null 2>&1; then
      sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" dbus-launch systemctl --user restart wireplumber || true
    else
      echo "Skipping wireplumber restart; dbus-launch is not installed."
    fi
  else
    echo "Skipping wireplumber restart because user runtime directory is not available."
  fi
fi

echo "Setup complete."
echo "If DisplayLink or the audio driver requires it, reboot after the script finishes."

