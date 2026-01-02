#!/usr/bin/env python3
"""
Smart Cat Feeder - RTSP Video Server (Demo Mode)
================================================
Streams a looping video file on rtsp://<IP>:8554/live

For demo purposes - simulates live camera feed.
The CSI camera module has hardware compatibility issues,
so we use a pre-recorded video for the demonstration.

Usage:
    1. Place a demo video at /opt/smart-cat-feeder/videos/demo.mp4
    2. Run: python3 rtsp_server.py
    3. Connect from app: rtsp://<ORANGE_PI_IP>:8554/live

See PHASE3_SETUP.md for USB camera setup instructions.
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import sys
import os
import socket

# Initialize GStreamer
Gst.init(None)

# ============================================================================
# Configuration
# ============================================================================

VIDEO_FILE = "/opt/smart-cat-feeder/videos/demo.mp4"
RTSP_PORT = 8554
MOUNT_POINT = "/live"

# ============================================================================
# RTSP Server Class
# ============================================================================

class VideoRTSPServer:
    """RTSP server that streams a video file."""
    
    def __init__(self, video_file, port=8554, mount_point="/live"):
        # Verify video file exists
        if not os.path.exists(video_file):
            print(f"❌ ERROR: Video file not found: {video_file}")
            print("\nTo fix this, create the video directory and add a demo video:")
            print("  sudo mkdir -p /opt/smart-cat-feeder/videos")
            print("  # Then either download a sample or copy your own video:")
            print("  wget -O /opt/smart-cat-feeder/videos/demo.mp4 \\")
            print("    'https://sample-videos.com/video321/mp4/720/big-buck-bunny_trailer_720p.mp4'")
            sys.exit(1)
        
        self.video_file = video_file
        self.server = GstRtspServer.RTSPServer()
        self.server.set_service(str(port))
        
        # Create media factory
        factory = GstRtspServer.RTSPMediaFactory()
        
        # Try direct H264 passthrough first (faster, lower CPU)
        # Falls back to transcoding if the source isn't H264
        pipeline = self._create_pipeline(video_file)
        
        factory.set_launch(pipeline)
        factory.set_shared(True)  # Allow multiple clients
        
        # Add mount point
        mount_points = self.server.get_mount_points()
        mount_points.add_factory(mount_point, factory)
        
        # Attach server to main context
        self.server.attach(None)
        
        # Get network IP
        ip_addr = self._get_ip()
        
        self._print_banner(video_file, ip_addr, port, mount_point)
    
    def _create_pipeline(self, video_file):
        """Create GStreamer pipeline for video streaming."""
        
        # Check if video is H264 (can passthrough without re-encoding)
        # For simplicity, we always transcode to ensure compatibility
        pipeline = (
            f"( filesrc location={video_file} ! "
            "decodebin ! videoconvert ! videoscale ! "
            "video/x-raw,width=640,height=480 ! "
            "x264enc tune=zerolatency bitrate=1500 speed-preset=superfast ! "
            "rtph264pay name=pay0 pt=96 config-interval=1 )"
        )
        
        return pipeline
    
    def _get_ip(self):
        """Get the local network IP address."""
        try:
            # Connect to external IP to determine our local IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return "192.168.1.100"
    
    def _print_banner(self, video_file, ip_addr, port, mount_point):
        """Print server information banner."""
        print("")
        print("=" * 60)
        print("  Smart Cat Feeder - RTSP Video Server (Demo Mode)")
        print("=" * 60)
        print(f"  Video file:  {video_file}")
        print(f"  Stream URL:  rtsp://{ip_addr}:{port}{mount_point}")
        print(f"  Local URL:   rtsp://localhost:{port}{mount_point}")
        print("")
        print("  Test with:")
        print(f"    ffplay rtsp://{ip_addr}:{port}{mount_point}")
        print(f"    vlc rtsp://{ip_addr}:{port}{mount_point}")
        print("")
        print("  For Flutter app, enter URL in Camera screen settings")
        print("=" * 60)
        print("")


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    print("🎬 Starting RTSP Video Server...")
    
    # Check if video file exists
    if not os.path.exists(VIDEO_FILE):
        print(f"\n❌ ERROR: Demo video not found!")
        print(f"   Expected location: {VIDEO_FILE}")
        print("\n📥 To download a sample video, run:")
        print("   sudo mkdir -p /opt/smart-cat-feeder/videos")
        print("   wget -O /opt/smart-cat-feeder/videos/demo.mp4 \\")
        print("     'https://sample-videos.com/video321/mp4/720/big-buck-bunny_trailer_720p.mp4'")
        print("\n📁 Or copy your own video:")
        print("   scp your_video.mp4 orangepi@IP:/opt/smart-cat-feeder/videos/demo.mp4")
        sys.exit(1)
    
    # Check file size
    file_size = os.path.getsize(VIDEO_FILE)
    print(f"📁 Video file: {VIDEO_FILE} ({file_size / 1024 / 1024:.1f} MB)")
    
    # Create and start server
    try:
        server = VideoRTSPServer(VIDEO_FILE, RTSP_PORT, MOUNT_POINT)
        print("✅ Server started successfully!")
        print("   Press Ctrl+C to stop.\n")
        
        # Run main loop
        loop = GLib.MainLoop()
        loop.run()
        
    except Exception as e:
        print(f"❌ Error starting server: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n👋 Shutting down server...")
        sys.exit(0)


if __name__ == "__main__":
    main()


