#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Variables
NQPTP_VERSION="1.2.4"
SHAIRPORT_SYNC_VERSION="4.3.2"
TMP_DIR=""

# Cleanup function to remove temporary directory
cleanup() {
    if [ -d "${TMP_DIR}" ]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT

# Verify OS
verify_os() {
    MSG="Unsupported OS: Raspberry Pi OS 12 (bookworm) is required."
    if [ ! -f /etc/os-release ]; then
        echo $MSG
        exit 1
    fi
    . /etc/os-release
    if [ "$ID" != "debian" ] && [ "$ID" != "raspbian" ] || [ "$VERSION_ID" != "12" ]; then
        echo $MSG
        exit 1
    fi
}

# Set hostname
set_hostname() {
    sudo raspi-config nonint do_hostname "${1:-$(hostname)}"
    sudo hostnamectl set-hostname --pretty "${2:-Raspberry Pi}"
}

# Install software
install_software() {
    echo "Updating package lists..."
    sudo apt update
    echo "Installing necessary packages..."
    sudo apt install -y samba samba-common qbittorrent qbittorrent-nox \
                        wget unzip autoconf automake build-essential libtool git \
                        libpopt-dev libconfig-dev libasound2-dev avahi-daemon \
                        libavahi-client-dev libssl-dev libsoxr-dev libplist-dev \
                        libsodium-dev libavutil-dev libavcodec-dev libavformat-dev \
                        uuid-dev libgcrypt20-dev xxd bluez-tools bluez-alsa-utils
    echo "All software installed successfully."

    echo "Configuring Samba..."
    sudo tee -a /etc/samba/smb.conf >/dev/null <<EOF

[Movies]
path = /media/pi/HDD/samba
writeable = Yes
create mask = 0777
directory mask = 0777
public = yes
valid users = pi
browseable = yes

[nobody]
path = /media/pi/HDD
writeable = Yes
create mask = 0777
directory mask = 0777
public = yes
valid users = pi
browseable = no



EOF
    sudo systemctl restart smbd
    echo "Samba configured successfully."
}

# Install Shairport Sync
install_shairport() {
    TMP_DIR=$(mktemp -d)
    cd $TMP_DIR

    # Install ALAC
    wget -O alac-master.zip https://github.com/mikebrady/alac/archive/refs/heads/master.zip
    unzip alac-master.zip
    cd alac-master
    autoreconf -fi
    ./configure
    make -j $(nproc)
    sudo make install
    sudo ldconfig
    cd ..

    # Install NQPTP
    wget -O nqptp-${NQPTP_VERSION}.zip https://github.com/mikebrady/nqptp/archive/refs/tags/${NQPTP_VERSION}.zip
    unzip nqptp-${NQPTP_VERSION}.zip
    cd nqptp-${NQPTP_VERSION}
    autoreconf -fi
    ./configure --with-systemd-startup
    make -j $(nproc)
    sudo make install
    cd ..

    # Install Shairport Sync
    wget -O shairport-sync-${SHAIRPORT_SYNC_VERSION}.zip https://github.com/mikebrady/shairport-sync/archive/refs/tags/${SHAIRPORT_SYNC_VERSION}.zip
    unzip shairport-sync-${SHAIRPORT_SYNC_VERSION}.zip
    cd shairport-sync-${SHAIRPORT_SYNC_VERSION}
    autoreconf -fi
    ./configure --sysconfdir=/etc --with-alsa --with-soxr --with-avahi --with-ssl=openssl --with-systemd --with-airplay-2 --with-apple-alac
    make -j $(nproc)
    sudo make install

    # Configure and enable Shairport Sync
    sudo tee /etc/shairport-sync.conf >/dev/null <<EOF
general = {
  name = "${PRETTY_HOSTNAME:-$(hostname)}";
  output_backend = "alsa";
}
sessioncontrol = {
  session_timeout = 20;
};
EOF
    sudo usermod -a -G gpio shairport-sync
    sudo systemctl enable --now nqptp shairport-sync

    echo "Shairport Sync installed successfully."
}

# Install Raspotify
install_raspotify() {
    curl -sL https://dtcooper.github.io/raspotify/install.sh | sh
    sudo tee /etc/raspotify/conf >/dev/null <<EOF
LIBRESPOT_NAME="${PRETTY_HOSTNAME// /-}"
LIBRESPOT_DEVICE_TYPE="avr"
LIBRESPOT_BITRATE="320"
LIBRESPOT_INITIAL_VOLUME="100"
EOF
    sudo systemctl enable raspotify
    echo "Raspotify installed successfully."
}

# Install and configure ZeroTier
install_zerotier() {
    echo "Installing ZeroTier..."
    curl -s https://install.zerotier.com | sudo bash
    sudo systemctl enable zerotier-one
    sudo zerotier-cli status
    sudo zerotier-cli join af415e486ff308cf
    sudo touch /var/lib/zerotier-one/networks.d/af415e486ff308cf.conf
    echo "ZeroTier installed and configured successfully."
}

install_Tailscale() {
	echo "Install Tailscale..."
	curl -fsSL https://tailscale.com/install.sh | sh
	echo "Use tailscale up"

}
install_qbittorrent()
{
sudo tee -a /etc/systemd/system/qbittorrent.service >/dev/null <<EOF
[Unit]
Description=qBittorrent
After=network.target

[Service]
Type=forking
User=pi
Group=pi
UMask=002
ExecStart=/usr/bin/qbittorrent-nox -d --webui-port=8113
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl start qbittorrent
sudo systemctl enable qbittorrent
}

# Main script execution
echo "Raspberry pi Essential Script"
verify_os
set_hostname
install_software
install_shairport
install_raspotify
install_zerotier
install_Tailscale
install_qbittorrent
