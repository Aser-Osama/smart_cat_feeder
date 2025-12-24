#!/usr/bin/env python3
import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib

Gst.init(None)

VIDEO = "/srv/smart-cat-feeder/media/demo.mp4"

server = GstRtspServer.RTSPServer()
server.set_service("8554")

factory = GstRtspServer.RTSPMediaFactory()

# Decode + re-encode (most reliable across random mp4s)
factory.set_launch(
    f'( filesrc location={VIDEO} ! '
    'decodebin ! videoconvert ! '
    'x264enc tune=zerolatency speed-preset=superfast bitrate=1500 key-int-max=60 ! '
    'rtph264pay name=pay0 pt=96 config-interval=1 )'
)

factory.set_shared(True)
server.get_mount_points().add_factory("/live", factory)
server.attach(None)

print("RTSP ready:")
print("  rtsp://192.168.100.135:8554/live")

GLib.MainLoop().run()

