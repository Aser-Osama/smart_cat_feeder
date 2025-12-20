import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../config/theme.dart';
import '../../services/preferences_service.dart';
import '../../widgets/custom_button.dart';

/// Demo streams for testing - includes RTSP examples
class DemoStream {
  final String name;
  final String url;
  final String description;
  final String protocol;

  const DemoStream({
    required this.name,
    required this.url,
    required this.description,
    required this.protocol,
  });
}

/// Demo streams - HTTP for testing, RTSP format shown for reference
const List<DemoStream> demoStreams = [
  DemoStream(
    name: 'Big Buck Bunny',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    description: 'Google sample video - works immediately',
    protocol: 'HTTPS',
  ),
  DemoStream(
    name: 'Sintel Trailer',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    description: 'Blender movie trailer',
    protocol: 'HTTPS',
  ),
  DemoStream(
    name: 'Tears of Steel',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
    description: 'Sci-fi short film',
    protocol: 'HTTPS',
  ),
  DemoStream(
    name: 'RTSP Test Stream',
    url: 'rtsp://rtsp.stream/pattern',
    description: 'Public RTSP test stream (if available)',
    protocol: 'RTSP',
  ),
];

/// Camera screen using media_kit for RTSP/HTTP streaming.
/// Based on libmpv - supports RTSP, RTMP, HLS, HTTP, and more.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  // Media Kit player and controller
  Player? _player;
  VideoController? _videoController;
  
  bool _isStreamActive = false;
  bool _isLoading = false;
  bool _hasError = false;
  bool _isPlaying = false;
  bool _isEmulator = false;
  bool _playerInitialized = false;
  int _streamSeconds = 0;
  String _currentStreamName = '';
  String _currentStreamUrl = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    await _checkEmulator();
    _initializePlayer();
  }

  Future<void> _checkEmulator() async {
    // Check if running on emulator using device_info_plus
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final isPhysical = androidInfo.isPhysicalDevice;
        debugPrint('Android device - isPhysicalDevice: $isPhysical');
        debugPrint('Android device - brand: ${androidInfo.brand}, model: ${androidInfo.model}');
        if (mounted) {
          setState(() {
            _isEmulator = !isPhysical;
          });
        }
      } catch (e) {
        debugPrint('Failed to check emulator status: $e');
        // Assume physical device if check fails
        if (mounted) {
          setState(() => _isEmulator = false);
        }
      }
    }
  }

  void _initializePlayer() {
    try {
      // Create player with configuration optimized for streaming
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024, // 32MB buffer
        ),
      );
      
      // Create video controller
      // Disable hardware acceleration on emulators - they don't support GPU video decoding properly
      // which causes black screen issues. Software rendering works reliably.
      
      final bool enableHw = !_isEmulator && !Platform.isLinux; // force SW video on Linux (Wayland/GNOME issue)

      _videoController = VideoController(
        _player!,
        configuration: VideoControllerConfiguration(
          // Disable HW acceleration on emulators for software rendering fallback
          enableHardwareAcceleration: enableHw,
          // Use software-based Android Surface Type for emulators
          androidAttachSurfaceAfterVideoParameters: _isEmulator,
        ),
      );
      
      debugPrint('VideoController initialized - HW accel: ${enableHw}, isEmulator: $_isEmulator');
      
      // Listen to player state
      _player!.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
        }
      });
      
      _player!.stream.buffering.listen((buffering) {
        if (mounted && _isStreamActive) {
          setState(() => _isLoading = buffering);
        }
      });
      
      _player!.stream.error.listen((error) {
        if (mounted && error.isNotEmpty) {
          debugPrint('Player error: $error');
          setState(() {
            _hasError = true;
            _errorMessage = error;
            _isStreamActive = false;
          });
        }
      });

      if (mounted) {
        setState(() => _playerInitialized = true);
      }
    } catch (e) {
      debugPrint('Failed to initialize player: $e');
      if (mounted) {
        setState(() {
          _playerInitialized = false;
          _errorMessage = 'Video player initialization failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _startStream([String? customUrl, String? streamName]) async {
    if (!_playerInitialized || _player == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Video player not available';
      });
      return;
    }

    final streamUrl = customUrl ?? PreferencesService.cameraStreamUrl;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
      _currentStreamName = streamName ?? 'Custom Stream';
      _currentStreamUrl = streamUrl;
      _isStreamActive = true;
      _streamSeconds = 0;
    });

    try {
      // Open the media - media_kit handles RTSP, HTTP, HLS, etc.
      await _player!.open(Media(streamUrl));
      
      _startTimer();
    } catch (e) {
      debugPrint('Stream error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _isStreamActive = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _stopStream() async {
    await _player?.stop();
    
    if (mounted) {
      setState(() {
        _isStreamActive = false;
        _isLoading = false;
        _isPlaying = false;
        _streamSeconds = 0;
        _currentStreamName = '';
        _currentStreamUrl = '';
      });
    }
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_isStreamActive && _isPlaying && mounted) {
        setState(() => _streamSeconds++);
        return true;
      }
      return _isStreamActive && mounted;
    });
  }

  String get _formattedTime {
    final minutes = (_streamSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_streamSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getProtocolFromUrl(String url) {
    if (url.startsWith('rtsp://')) return 'RTSP';
    if (url.startsWith('rtmp://')) return 'RTMP';
    if (url.contains('.m3u8')) return 'HLS';
    if (url.startsWith('https://')) return 'HTTPS';
    if (url.startsWith('http://')) return 'HTTP';
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Camera'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: () => _showQuickUrlDialog(),
            tooltip: 'Enter URL',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCameraView(),
            const SizedBox(height: 20),
            _buildControlButtons(),
            const SizedBox(height: 25),
            _buildDemoStreams(),
            const SizedBox(height: 25),
            _buildCameraStats(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    return Container(
      height: MediaQuery.of(context).size.width * 0.65,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _buildCameraContent(),
      ),
    );
  }

  Widget _buildCameraContent() {
    // Player not initialized
    if (!_playerInitialized) {
      return _buildEmulatorFallback();
    }

    // Error state
    if (_hasError) {
      return Container(
        color: Colors.black87,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 48),
                const SizedBox(height: 15),
                Text(
                  'Stream Failed',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  _isEmulator 
                      ? 'Video playback may not work on emulators.\nTry on a real device.'
                      : 'Check the URL and try again',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                if (_errorMessage.isNotEmpty && !_isEmulator) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage.length > 80 
                        ? '${_errorMessage.substring(0, 80)}...' 
                        : _errorMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white30),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Active stream with video player
    if (_isStreamActive && _videoController != null) {
      return Stack(
        children: [
          // Video player from media_kit
          // On emulators, use software rendering with lower quality for performance
          Video(
            controller: _videoController!,
            controls: NoVideoControls,
            fill: Colors.black,
            wakelock: false,
            // Lower filter quality on emulators for better software rendering performance
            filterQuality: _isEmulator ? FilterQuality.none : FilterQuality.low,
          ),
          
          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Buffering...',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentStreamName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white38,
                      ),
                    ),
                    if (_isEmulator) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(50),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '⚠️ Emulator detected - video may not display',
                          style: TextStyle(color: Colors.orange, fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          
          // Overlays when playing
          if (_isPlaying && !_isLoading) ...[
            // Live indicator
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            
            // Protocol badge
            Positioned(
              top: 12,
              left: 70,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getProtocolFromUrl(_currentStreamUrl) == 'RTSP' 
                      ? AppTheme.successColor 
                      : Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _getProtocolFromUrl(_currentStreamUrl),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            
            // Timer
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(_formattedTime, style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
            
            // Play/pause button
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      _player?.playOrPause();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }

    // Inactive state (no stream)
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, color: Colors.white.withAlpha(100), size: 50),
            const SizedBox(height: 12),
            Text(
              'No Active Stream',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withAlpha(150),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Select a demo stream or enter RTSP URL',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withAlpha(100),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmulatorFallback() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.phone_android,
                size: 48,
                color: Colors.orange.withAlpha(200),
              ),
              const SizedBox(height: 16),
              Text(
                'Video Player Unavailable',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Video streaming requires:\n'
                '• Real Android/iOS device, or\n'
                '• Linux with libmpv installed:\n'
                '  sudo dnf install mpv-libs mpv-devel',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white60,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withAlpha(100)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'RTSP Support Ready',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'rtsp://192.168.1.100:8554/live',
                      style: TextStyle(
                        color: Colors.white.withAlpha(150),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: CustomButton(
            text: _isStreamActive ? 'Stop' : 'Start Stream',
            icon: _isStreamActive ? Icons.stop : Icons.play_arrow,
            onPressed: (!_playerInitialized || _isLoading) ? null : () async {
              if (_isStreamActive) {
                await _stopStream();
              } else {
                await _startStream();
              }
            },
            isLoading: _isLoading,
            backgroundColor: _isStreamActive ? AppTheme.errorColor : AppTheme.successColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: CustomButton(
            text: 'URL',
            icon: Icons.link,
            onPressed: () => _showQuickUrlDialog(),
            isOutlined: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDemoStreams() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Demo Streams', style: Theme.of(context).textTheme.headlineMedium),
            TextButton.icon(
              onPressed: () => _showStreamSourcesInfo(),
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('RTSP setup'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        ...demoStreams.map((stream) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildStreamTile(stream),
        )),
      ],
    );
  }

  Widget _buildStreamTile(DemoStream stream) {
    final isCurrentStream = _currentStreamUrl == stream.url && _isStreamActive;
    final isRtsp = stream.protocol == 'RTSP';
    
    return InkWell(
      onTap: _playerInitialized ? () async {
        if (isCurrentStream) {
          await _stopStream();
        } else {
          await _startStream(stream.url, stream.name);
        }
      } : null,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: _playerInitialized ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCurrentStream ? AppTheme.primaryColor.withAlpha(20) : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrentStream 
                  ? AppTheme.primaryColor 
                  : (isRtsp ? AppTheme.successColor.withAlpha(100) : AppTheme.textLight.withAlpha(50)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isRtsp 
                      ? AppTheme.successColor.withAlpha(26) 
                      : AppTheme.primaryColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCurrentStream 
                      ? Icons.stop_circle_outlined 
                      : (isRtsp ? Icons.router : Icons.play_circle_outline),
                  color: isRtsp ? AppTheme.successColor : AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(stream.name, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isRtsp 
                                ? AppTheme.successColor.withAlpha(30) 
                                : AppTheme.textLight.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            stream.protocol,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: isRtsp ? AppTheme.successColor : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isCurrentStream ? 'Now playing' : stream.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isCurrentStream ? AppTheme.primaryColor : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isCurrentStream ? Icons.stop : Icons.chevron_right,
                color: isCurrentStream ? AppTheme.primaryColor : AppTheme.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraStats() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stream Info', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          _buildStatRow(
            Icons.stream, 
            'Protocol', 
            _isStreamActive ? _getProtocolFromUrl(_currentStreamUrl) : 'RTSP/HTTP/HLS',
            valueColor: _isStreamActive && _getProtocolFromUrl(_currentStreamUrl) == 'RTSP' 
                ? AppTheme.successColor 
                : null,
          ),
          const Divider(height: 20),
          _buildStatRow(
            Icons.memory, 
            'Engine', 
            _isEmulator ? 'libmpv (SW render)' : 'libmpv (media_kit)',
            valueColor: _isEmulator ? Colors.orange : null,
          ),
          const Divider(height: 20),
          _buildStatRow(
            Icons.signal_cellular_alt,
            'Status',
            !_playerInitialized 
                ? 'Unavailable' 
                : (_isPlaying ? 'Playing' : (_isLoading ? 'Buffering...' : (_hasError ? 'Error' : 'Ready'))),
            valueColor: !_playerInitialized 
                ? Colors.orange 
                : (_isPlaying ? AppTheme.successColor : (_hasError ? AppTheme.errorColor : AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: valueColor ?? AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _showQuickUrlDialog() {
    final controller = TextEditingController(text: PreferencesService.cameraStreamUrl);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textLight.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Enter Stream URL', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Supports RTSP, RTMP, HTTP, HLS streams',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'rtsp://192.168.1.100:8554/live',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      controller.text = data!.text!;
                    }
                  },
                ),
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _buildProtocolChip('rtsp://', controller),
                _buildProtocolChip('http://', controller),
                _buildProtocolChip('rtmp://', controller),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _playerInitialized ? () {
                      final url = controller.text.trim();
                      if (url.isNotEmpty) {
                        PreferencesService.cameraStreamUrl = url;
                        Navigator.pop(context);
                        _startStream(url, 'Custom Stream');
                      }
                    } : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play Stream'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProtocolChip(String protocol, TextEditingController controller) {
    return ActionChip(
      label: Text(protocol, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        if (!controller.text.startsWith(protocol)) {
          controller.text = protocol;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        }
      },
    );
  }

  void _showStreamSourcesInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RTSP Stream Setup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSourceSection(
                'Orange Pi RTSP Server',
                '1. Install GStreamer on Orange Pi\n'
                '2. Run RTSP server:\n'
                '   gst-launch-1.0 v4l2src ! \\\n'
                '   videoconvert ! x264enc ! \\\n'
                '   rtspclientsink location=\\\n'
                '   rtsp://localhost:8554/live\n'
                '3. Enter: rtsp://[ORANGE_PI_IP]:8554/live',
              ),
              const SizedBox(height: 16),
              _buildSourceSection(
                'IP Camera Format',
                'Most IP cameras use:\n'
                '• rtsp://user:pass@ip:554/stream1\n'
                '• rtsp://ip:554/live/ch00_0\n'
                '• Check camera manual for exact path',
              ),
              const SizedBox(height: 16),
              _buildSourceSection(
                'Emulator Limitations',
                '⚠️ Android emulators have GPU\n'
                'virtualization issues with video.\n\n'
                'For testing, use:\n'
                '• Real Android/iOS device\n'
                '• Linux desktop with libmpv',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
        const SizedBox(height: 4),
        Text(content, style: const TextStyle(fontSize: 12, height: 1.5)),
      ],
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Media Kit Player'),
        content: const Text(
          'This screen uses media_kit (libmpv) for video playback.\n\n'
          'Supported protocols:\n'
          '• RTSP - Real-time streaming (low latency)\n'
          '• RTMP - Flash streaming servers\n'
          '• HTTP/HTTPS - Video files & CDNs\n'
          '• HLS - Adaptive streaming (.m3u8)\n\n'
          'Requirements:\n'
          '• Android/iOS: Works out of the box\n'
          '• Linux: Install libmpv\n'
          '• Emulator: Limited support',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
