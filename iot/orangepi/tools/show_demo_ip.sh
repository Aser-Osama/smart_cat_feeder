#!/usr/bin/env bash
set -euo pipefail

# Pick interface from default route (works for ethernet or wifi)
IFACE="$(ip route | awk '/default/ {print $5; exit}')"

if [[ -z "${IFACE}" ]]; then
  echo "No default route found. Are you connected to WiFi/Ethernet?"
  exit 1
fi

IP="$(ip -4 addr show "$IFACE" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"

if [[ -z "${IP}" ]]; then
  echo "Interface '$IFACE' has no IPv4 address yet."
  echo "Try: nmcli dev status   (and connect WiFi if needed)"
  exit 1
fi

echo "==== DEMO INFO ===="
echo "Interface: $IFACE"
echo "MQTT:      $IP:1883"
echo "RTSP:      rtsp://$IP:8554/live"


