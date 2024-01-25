#!/bin/bash

# Check if xrdp is already installed
XRDP_SERVICE=$(sudo systemctl list-unit-files --type=service | grep "xrdp.service")
if [ -n "$XRDP_SERVICE" ]; then
  echo "xrdp already installed. checking if it is running..."
  STATE=$(sudo systemctl is-active xrdp.service)
  if [ "$STATE" = "active" ]; then
    echo "xrdp is already running."
    exit 0
  else
    echo "xrdp is not running."
    if sudo systemctl start xrdp.service; then
      echo "xrdp started successfully."
      exit 0
    else
      echo "xrdp failed to start."
    fi
  fi
fi

echo "Installing xrdp..."
sudo apt update
sudo apt install -y xrdp dbus-x11 nmap
sudo adduser xrdp ssl-cert
echo "Restarting xrdp..."
sudo systemctl restart xrdp
echo "Setting firewall rules..."
sudo ufw allow 3389/tcp

if ! grep -q "export \$(dbus-launch)" /etc/xrdp/startwm.sh; then
  echo "Updating the xrdp startwm.sh file..."
  echo "export \$(dbus-launch)" | sudo tee -a /etc/xrdp/startwm.sh >/dev/null
fi

sleep 2

PORT_TEST=$(nmap localhost -p3389 | grep "3389/tcp" | grep "open")
echo "Testing xrdp port..."
if [ -z "$PORT_TEST" ]; then
  echo "$PORT_TEST"
  echo "xrdp installation failed."
  exit 1
else
  echo "xrdp installation completed successfully."
  exit 0
fi
