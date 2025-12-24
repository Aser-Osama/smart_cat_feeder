#!/bin/bash
# ============================================================================
# Smart Cat Feeder - Orange Pi 3B Setup Script
# ============================================================================
# For use with: Orangepi3b_1.0.8_ubuntu_jammy_server_linux5.10.160
# DO NOT use with Armbian - camera module not supported on newer kernels
#
# This script sets up:
# 1. MQTT Broker (Mosquitto) for local WSN communication
# 2. GStreamer RTSP server for camera streaming
# 3. Python gateway service for Firebase ↔ MQTT bridge
# ============================================================================

set -e  # Exit on error

echo "============================================"
echo "Smart Cat Feeder - Orange Pi 3B Setup"
echo "============================================"
echo "For: Official Orange Pi Ubuntu Jammy (kernel 5.10.160)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (sudo ./setup.sh)${NC}"
    exit 1
fi

# Verify kernel version
KERNEL_VERSION=$(uname -r)
echo -e "${YELLOW}Detected kernel: ${KERNEL_VERSION}${NC}"
if [[ "$KERNEL_VERSION" == 6.* ]]; then
    echo -e "${RED}WARNING: Kernel 6.x detected. Camera may not work!${NC}"
    echo -e "${RED}Recommended: Use Orangepi3b_1.0.8_ubuntu_jammy_server_linux5.10.160${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get the actual user (not root)
ACTUAL_USER=${SUDO_USER:-$USER}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}Step 1: Updating system packages...${NC}"
apt-get update
apt-get upgrade -y

echo ""
echo -e "${YELLOW}Step 2: Installing MQTT Broker (Mosquitto)...${NC}"
apt-get install -y mosquitto mosquitto-clients

# Configure Mosquitto to allow anonymous connections on local network
cat > /etc/mosquitto/conf.d/smart_cat_feeder.conf << EOF
# Smart Cat Feeder MQTT Configuration
listener 1883
allow_anonymous true
# For security in production, uncomment these and set password:
# password_file /etc/mosquitto/passwd
# allow_anonymous false
EOF

# Restart Mosquitto
systemctl enable mosquitto
systemctl restart mosquitto
echo -e "${GREEN}✓ Mosquitto installed and running on port 1883${NC}"

echo ""
echo -e "${YELLOW}Step 3: Installing GStreamer for RTSP streaming...${NC}"
apt-get install -y \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-rtsp \
    libgstrtspserver-1.0-0 \
    gstreamer1.0-libav \
    v4l-utils

# Install Rockchip-specific GStreamer plugins (for hardware acceleration)
# This package may not exist on all systems - ignore if not found
apt-get install -y gstreamer1.0-rockchip1 2>/dev/null || \
    echo -e "${YELLOW}Note: gstreamer1.0-rockchip1 not available (optional)${NC}"

# Install ffmpeg for video handling
apt-get install -y ffmpeg

echo -e "${GREEN}✓ GStreamer and video tools installed${NC}"

echo ""
echo -e "${YELLOW}Step 3b: Setting up demo video directory...${NC}"
mkdir -p "$GATEWAY_DIR/videos"

# Download a demo video if none exists
if [ ! -f "$GATEWAY_DIR/videos/demo.mp4" ]; then
    echo "Downloading sample demo video..."
    wget -q --show-progress -O "$GATEWAY_DIR/videos/demo.mp4" \
        "https://sample-videos.com/video321/mp4/720/big-buck-bunny_trailer_720p.mp4" 2>/dev/null || \
        echo -e "${YELLOW}Note: Could not download demo video. Please add one manually.${NC}"
fi

if [ -f "$GATEWAY_DIR/videos/demo.mp4" ]; then
    echo -e "${GREEN}✓ Demo video ready at $GATEWAY_DIR/videos/demo.mp4${NC}"
else
    echo -e "${YELLOW}⚠ No demo video found. Please add one:${NC}"
    echo "  scp your_video.mp4 orangepi@IP:$GATEWAY_DIR/videos/demo.mp4"
fi

echo ""
echo -e "${YELLOW}Step 4: Installing Python dependencies...${NC}"
apt-get install -y python3-pip python3-venv

# Create virtual environment for gateway
GATEWAY_DIR="/opt/smart-cat-feeder"
mkdir -p "$GATEWAY_DIR"
python3 -m venv "$GATEWAY_DIR/venv"
source "$GATEWAY_DIR/venv/bin/activate"

# Install Python packages
pip install --upgrade pip
pip install -r "$SCRIPT_DIR/requirements.txt"

# Copy gateway script
cp "$SCRIPT_DIR/gateway.py" "$GATEWAY_DIR/"
cp "$SCRIPT_DIR/requirements.txt" "$GATEWAY_DIR/"

echo -e "${GREEN}✓ Python gateway installed to $GATEWAY_DIR${NC}"

echo ""
echo -e "${YELLOW}Step 5: Setting up Firebase credentials...${NC}"
CREDS_PATH="$GATEWAY_DIR/firebase-credentials.json"
if [ ! -f "$CREDS_PATH" ]; then
    echo -e "${YELLOW}Firebase service account credentials not found.${NC}"
    echo ""
    echo "To complete setup, you need to:"
    echo "1. Go to Firebase Console → Project Settings → Service Accounts"
    echo "2. Click 'Generate new private key'"
    echo "3. Copy the JSON file to: $CREDS_PATH"
    echo ""
    echo "After copying, run: sudo systemctl restart smart-cat-feeder-gateway"
else
    echo -e "${GREEN}✓ Firebase credentials found${NC}"
fi

echo ""
echo -e "${YELLOW}Step 6: Creating systemd services...${NC}"

# Gateway service
cat > /etc/systemd/system/smart-cat-feeder-gateway.service << EOF
[Unit]
Description=Smart Cat Feeder Gateway (Firebase ↔ MQTT)
After=network.target mosquitto.service
Wants=mosquitto.service

[Service]
Type=simple
User=root
WorkingDirectory=$GATEWAY_DIR
Environment="GOOGLE_APPLICATION_CREDENTIALS=$GATEWAY_DIR/firebase-credentials.json"
ExecStart=$GATEWAY_DIR/venv/bin/python $GATEWAY_DIR/gateway.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create RTSP video server script (Demo Mode - streams video file, not live camera)
# Note: CSI camera module has hardware compatibility issues
# See PHASE3_SETUP.md "Future: USB Camera Setup" for live camera options
cat > "$GATEWAY_DIR/rtsp_server.py" << 'RTSP_EOF'
#!/usr/bin/env python3
"""
Smart Cat Feeder - RTSP Video Server (Demo Mode)
Streams a looping video file on rtsp://<IP>:8554/live

For demo purposes - simulates live camera feed.
The CSI camera module has hardware compatibility issues.
"""
import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import sys
import os
import socket

Gst.init(None)

VIDEO_FILE = "/opt/smart-cat-feeder/videos/demo.mp4"
RTSP_PORT = 8554

class VideoRTSPServer:
    def __init__(self):
        if not os.path.exists(VIDEO_FILE):
            print(f"ERROR: Demo video not found at {VIDEO_FILE}")
            print("Please add a demo video file first.")
            sys.exit(1)
        
        self.server = GstRtspServer.RTSPServer()
        self.server.set_service(str(RTSP_PORT))
        
        factory = GstRtspServer.RTSPMediaFactory()
        
        # Pipeline for video file streaming
        pipeline = (
            f"( filesrc location={VIDEO_FILE} ! "
            "decodebin ! videoconvert ! videoscale ! "
            "video/x-raw,width=640,height=480 ! "
            "x264enc tune=zerolatency bitrate=1500 speed-preset=superfast ! "
            "rtph264pay name=pay0 pt=96 config-interval=1 )"
        )
        
        factory.set_launch(pipeline)
        factory.set_shared(True)
        
        self.server.get_mount_points().add_factory("/live", factory)
        self.server.attach(None)
        
        # Get IP address
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
        except:
            ip = "localhost"
        
        print("=" * 55)
        print("Smart Cat Feeder - RTSP Video Server (Demo Mode)")
        print("=" * 55)
        print(f"Video: {VIDEO_FILE}")
        print(f"Stream: rtsp://{ip}:{RTSP_PORT}/live")
        print("=" * 55)

if __name__ == "__main__":
    if not os.path.exists(VIDEO_FILE):
        print(f"ERROR: Video not found at {VIDEO_FILE}")
        print("Run: wget -O /opt/smart-cat-feeder/videos/demo.mp4 URL")
        sys.exit(1)
    
    server = VideoRTSPServer()
    print("Server running. Press Ctrl+C to stop.")
    
    try:
        GLib.MainLoop().run()
    except KeyboardInterrupt:
        print("Shutting down...")
RTSP_EOF
chmod +x "$GATEWAY_DIR/rtsp_server.py"

# RTSP Video Server service (Demo Mode)
cat > /etc/systemd/system/smart-cat-feeder-camera.service << EOF
[Unit]
Description=Smart Cat Feeder RTSP Video Server (Demo Mode)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$GATEWAY_DIR
ExecStart=$GATEWAY_DIR/venv/bin/python $GATEWAY_DIR/rtsp_server.py
Restart=always
RestartSec=5
StandardOutput=append:/var/log/smart-cat-feeder-camera.log
StandardError=append:/var/log/smart-cat-feeder-camera.log

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Enable services (but don't start gateway until credentials are in place)
systemctl enable smart-cat-feeder-gateway
systemctl enable smart-cat-feeder-camera

echo -e "${GREEN}✓ Systemd services created${NC}"

echo ""
echo -e "${YELLOW}Step 7: Checking video setup (Demo Mode)...${NC}"
echo -e "${YELLOW}Note: Using video file streaming instead of live camera${NC}"
echo "      (CSI camera module has hardware compatibility issues)"
echo ""

if [ -f "$GATEWAY_DIR/videos/demo.mp4" ]; then
    VIDEO_SIZE=$(du -h "$GATEWAY_DIR/videos/demo.mp4" | cut -f1)
    echo -e "${GREEN}✓ Demo video found: $GATEWAY_DIR/videos/demo.mp4 ($VIDEO_SIZE)${NC}"
    
    # Verify video is playable
    if command -v ffprobe &> /dev/null; then
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$GATEWAY_DIR/videos/demo.mp4" 2>/dev/null | cut -d. -f1)
        if [ -n "$DURATION" ]; then
            echo "  Duration: ${DURATION} seconds"
        fi
    fi
else
    echo -e "${YELLOW}⚠ No demo video found${NC}"
    echo "  Please add a video file:"
    echo "  scp your_video.mp4 orangepi@IP:$GATEWAY_DIR/videos/demo.mp4"
    echo ""
    echo "  Or download a sample:"
    echo "  wget -O $GATEWAY_DIR/videos/demo.mp4 \\"
    echo "    'https://sample-videos.com/video321/mp4/720/big-buck-bunny_trailer_720p.mp4'"
fi

# Note about future USB camera support
echo ""
echo -e "${YELLOW}Future: For live camera streaming, see PHASE3_SETUP.md${NC}"
echo "        section 'Future: USB Camera Setup'"

echo ""
echo -e "${YELLOW}Step 8: Testing MQTT broker...${NC}"
# Test MQTT
timeout 2 mosquitto_sub -h localhost -t "test" &
sleep 0.5
mosquitto_pub -h localhost -t "test" -m "Smart Cat Feeder test"
echo -e "${GREEN}✓ MQTT broker working${NC}"

echo ""
echo "============================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Add Firebase credentials:"
echo "   - Copy your firebase-credentials.json to: $GATEWAY_DIR/"
echo ""
echo "2. Get your Orange Pi IP address:"
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "   Current IP: $IP_ADDR"
echo ""
echo "3. Add a demo video (if not already downloaded):"
echo "   ls $GATEWAY_DIR/videos/demo.mp4"
echo "   # If missing, download or copy a video file"
echo ""
echo "4. Start the services:"
echo "   sudo systemctl start smart-cat-feeder-camera"
echo "   sudo systemctl start smart-cat-feeder-gateway"
echo ""
echo "5. Test video stream (Demo Mode):"
echo "   ffplay rtsp://$IP_ADDR:8554/live"
echo "   # or: vlc rtsp://$IP_ADDR:8554/live"
echo ""
echo "6. Update ESP8266 with MQTT broker IP:"
echo "   MQTT Broker: $IP_ADDR:1883"
echo ""
echo "7. Update Flutter app camera URL:"
echo "   rtsp://$IP_ADDR:8554/live"
echo ""
echo "Note: This setup uses demo video streaming."
echo "      For USB camera setup, see PHASE3_SETUP.md"
echo ""
echo "View logs:"
echo "   sudo journalctl -u smart-cat-feeder-gateway -f"
echo "   sudo tail -f /var/log/smart-cat-feeder-camera.log"
echo ""

