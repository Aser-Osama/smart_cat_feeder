#!/bin/bash

# =============================================================================
# RTSP Stream Demo Script for Smart Cat Feeder
# =============================================================================
# This script starts an RTSP server and streams a demo video.
# Use the displayed URL in your Smart Cat Feeder app to test RTSP playback.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/rtsp_demo"
MEDIAMTX_VERSION="v1.9.3"
RTSP_PORT="8554"
STREAM_PATH="live"

# Print banner
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          🎥 Smart Cat Feeder - RTSP Stream Demo 🐱            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Function to get local IP
get_local_ip() {
    ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' || \
    hostname -I | awk '{print $1}' || \
    echo "localhost"
}

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}🛑 Stopping RTSP stream...${NC}"
    pkill -f "mediamtx" 2>/dev/null || true
    pkill -f "ffmpeg.*rtsp://localhost:$RTSP_PORT" 2>/dev/null || true
    echo -e "${GREEN}✅ Cleanup complete${NC}"
}
trap cleanup EXIT

# Kill any existing instances
echo -e "${YELLOW}🧹 Cleaning up existing processes...${NC}"
pkill -f "mediamtx" 2>/dev/null || true
pkill -f "ffmpeg.*rtsp://localhost:$RTSP_PORT" 2>/dev/null || true
sleep 1

# Download MediaMTX if needed
if [ ! -f "$WORK_DIR/mediamtx" ]; then
    echo -e "${BLUE}📥 Downloading MediaMTX RTSP server...${NC}"
    wget -q --show-progress "https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/mediamtx_${MEDIAMTX_VERSION}_linux_amd64.tar.gz" -O mediamtx.tar.gz
    tar xzf mediamtx.tar.gz
    rm mediamtx.tar.gz
    echo -e "${GREEN}✅ MediaMTX ready${NC}"
else
    echo -e "${GREEN}✅ MediaMTX already downloaded${NC}"
fi

# Download test video if needed
if [ ! -f "$WORK_DIR/demo_video.mp4" ]; then
    echo -e "${BLUE}📥 Downloading demo video (Big Buck Bunny)...${NC}"
    wget -q --show-progress "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4" -O demo_video.mp4
    echo -e "${GREEN}✅ Demo video ready${NC}"
else
    echo -e "${GREEN}✅ Demo video already downloaded${NC}"
fi

# Start MediaMTX server
echo -e "${BLUE}🚀 Starting RTSP server...${NC}"
./mediamtx > /dev/null 2>&1 &
MEDIAMTX_PID=$!
sleep 2

# Check if MediaMTX started
if ! kill -0 $MEDIAMTX_PID 2>/dev/null; then
    echo -e "${RED}❌ Failed to start MediaMTX${NC}"
    exit 1
fi
echo -e "${GREEN}✅ RTSP server running (PID: $MEDIAMTX_PID)${NC}"

# Start streaming
echo -e "${BLUE}🎬 Starting video stream...${NC}"
ffmpeg -re -stream_loop -1 -i demo_video.mp4 -c copy -f rtsp -rtsp_transport tcp "rtsp://localhost:$RTSP_PORT/$STREAM_PATH" > /dev/null 2>&1 &
FFMPEG_PID=$!
sleep 2

# Check if ffmpeg started
if ! kill -0 $FFMPEG_PID 2>/dev/null; then
    echo -e "${RED}❌ Failed to start stream${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Video stream active (PID: $FFMPEG_PID)${NC}"

# Get local IP
LOCAL_IP=$(get_local_ip)

# Print connection info
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                    ${GREEN}🎉 RTSP STREAM READY! 🎉${NC}                   ${CYAN}║${NC}"
echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}                                                               ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${YELLOW}RTSP URL for your app:${NC}                                      ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                               ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}     ${GREEN}rtsp://${LOCAL_IP}:${RTSP_PORT}/${STREAM_PATH}${NC}"
echo -e "${CYAN}║${NC}                                                               ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${YELLOW}Test locally with:${NC}                                           ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}     ffplay rtsp://localhost:${RTSP_PORT}/${STREAM_PATH}                       ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                               ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${YELLOW}Video:${NC} Big Buck Bunny (1280x720, H.264, looping)              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                               ${CYAN}║${NC}"
echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}              Press ${RED}Ctrl+C${NC} to stop the stream                   ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Keep script running
echo -e "${BLUE}📡 Streaming... (Press Ctrl+C to stop)${NC}"
echo ""

# Wait and show status every 30 seconds
while true; do
    sleep 30
    if kill -0 $MEDIAMTX_PID 2>/dev/null && kill -0 $FFMPEG_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Stream healthy - rtsp://${LOCAL_IP}:${RTSP_PORT}/${STREAM_PATH}${NC}"
    else
        echo -e "${RED}❌ Stream stopped unexpectedly${NC}"
        exit 1
    fi
done

