#!/bin/bash
# Deploy shelter_gateway.py to Orange Pi and restart service

GATEWAY_IP="172.29.32.150"
USER="orangepi"
REMOTE_TMP="/home/orangepi/shelter_gateway.py"
REMOTE_DEST="/opt/smart-cat-feeder/shelter_gateway.py"

echo "🚀 Deploying shelter_gateway.py to $GATEWAY_IP..."

# Copy file to home directory (no sudo needed)
scp shelter_gateway.py $USER@$GATEWAY_IP:$REMOTE_TMP

echo ""
echo "📋 To complete deployment, SSH to the gateway and run:"
echo "   ssh $USER@$GATEWAY_IP"
echo ""
echo "Then execute these commands:"
echo "   sudo cp $REMOTE_TMP $REMOTE_DEST"
echo "   sudo systemctl restart shelter-gateway"
echo "   sudo systemctl status shelter-gateway"
echo "   sudo journalctl -u shelter-gateway -f"
