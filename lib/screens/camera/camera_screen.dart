import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../config/theme.dart';
import '../../services/preferences_service.dart';
import '../../widgets/custom_button.dart';

/// Demo streams for testing
class DemoStream {
  final String name;
  final String url;
  final String description;

  const DemoStream({
    required this.name,
    required this.url,
    required this.description,
  });
}

/// Public demo streams that work for testing
const List<DemoStream> demoStreams = [
  DemoStream(
    name: 'Big Buck Bunny',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    description: 'Google sample video - animated short',
  ),
  DemoStream(
    name: 'Sintel Trailer',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    description: 'Blender movie trailer',
  ),
  DemoStream(
    name: 'Tears of Steel',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
    description: 'Sci-fi short film',
  ),
  DemoStream(
    name: 'Elephant Dream',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    description: 'Animated short',
  ),
];

/// Camera screen using video_player for streaming.
/// Supports demo mode with public streams for testing.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  VideoPlayerController? _controller;
  bool _isStreamActive = false;
  bool _isLoading = false;
  bool _hasError = false;
  bool _isInitialized = false;
  int _streamSeconds = 0;
  String _currentStreamName = '';
  String _currentStreamUrl = '';
  String _errorMessage = '';

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _disposeController() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
  }

  Future<void> _startStream([String? customUrl, String? streamName]) async {
    // Stop existing stream first
    await _stopStream();
    
    final streamUrl = customUrl ?? PreferencesService.cameraStreamUrl;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
      _isInitialized = false;
      _errorMessage = '';
      _currentStreamName = streamName ?? 'Custom Stream';
      _currentStreamUrl = streamUrl;
      _isStreamActive = true;
      _streamSeconds = 0;
    });

    try {
      // Create video player controller
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      // Initialize and start playback
      await _controller!.initialize();
      await _controller!.play();
      await _controller!.setLooping(true);
      
      _controller!.addListener(_onPlayerStateChanged);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
        });
      }
      
      _startTimer();
    } catch (e) {
      debugPrint('Video player error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _isStreamActive = false;
          _errorMessage = e.toString();
        });
      }
      await _disposeController();
    }
  }

  void _onPlayerStateChanged() {
    if (_controller == null || !mounted) return;
    
    if (_controller!.value.hasError) {
      setState(() {
        _hasError = true;
        _isStreamActive = false;
        _errorMessage = _controller!.value.errorDescription ?? 'Playback error';
      });
    }
  }

  Future<void> _stopStream() async {
    await _disposeController();
    
    if (mounted) {
      setState(() {
        _isStreamActive = false;
        _isLoading = false;
        _isInitialized = false;
        _streamSeconds = 0;
        _currentStreamName = '';
        _currentStreamUrl = '';
      });
    }
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_isStreamActive && _isInitialized && mounted) {
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
    // Loading state
    if (_isLoading) {
      return Container(
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
                'Connecting...',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              if (_currentStreamName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _currentStreamName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white38,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
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
                  'Try a demo stream below',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage.length > 100 
                        ? '${_errorMessage.substring(0, 100)}...' 
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

    // Playing state
    if (_isInitialized && _controller != null && _controller!.value.isInitialized) {
      return Stack(
        children: [
          // Video player
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          
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
          
          // Stream name
          if (_currentStreamName.isNotEmpty)
            Positioned(
              top: 12,
              left: 70,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _currentStreamName,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
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
                    setState(() {
                      if (_controller!.value.isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Icon(
                      _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
              'Select a demo stream or enter URL',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withAlpha(100),
              ),
            ),
          ],
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
            onPressed: _isLoading ? null : () async {
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
              label: const Text('Find streams'),
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
    
    return InkWell(
      onTap: () async {
        if (isCurrentStream) {
          await _stopStream();
        } else {
          await _startStream(stream.url, stream.name);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrentStream ? AppTheme.primaryColor.withAlpha(20) : AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrentStream ? AppTheme.primaryColor : AppTheme.textLight.withAlpha(50),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isCurrentStream ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                color: AppTheme.primaryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stream.name, style: Theme.of(context).textTheme.titleMedium),
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
          _buildStatRow(Icons.stream, 'Protocol', 'HTTP/HTTPS'),
          const Divider(height: 20),
          _buildStatRow(Icons.high_quality, 'Quality', 'Auto'),
          const Divider(height: 20),
          _buildStatRow(
            Icons.signal_cellular_alt,
            'Status',
            _isInitialized ? 'Playing' : (_isLoading ? 'Connecting...' : (_hasError ? 'Error' : 'Ready')),
            valueColor: _isInitialized ? AppTheme.successColor : (_hasError ? AppTheme.errorColor : AppTheme.textSecondary),
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
              'Paste any HTTP/HTTPS video URL (.mp4, .m3u8)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'https://example.com/video.mp4',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    onPressed: () {
                      final url = controller.text.trim();
                      if (url.isNotEmpty) {
                        PreferencesService.cameraStreamUrl = url;
                        Navigator.pop(context);
                        _startStream(url, 'Custom URL');
                      }
                    },
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

  void _showStreamSourcesInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Where to Find Streams'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSourceSection(
                'Demo Streams',
                '• The demo streams above work immediately\n'
                '• Sample videos from Google Cloud Storage',
              ),
              const SizedBox(height: 16),
              _buildSourceSection(
                'HTTP Video URLs',
                '• Any direct .mp4 or .m3u8 URL\n'
                '• HLS streams from CDNs\n'
                '• Must be HTTPS for Android',
              ),
              const SizedBox(height: 16),
              _buildSourceSection(
                'For RTSP Streams',
                '• RTSP requires native app or VLC\n'
                '• Convert RTSP to HLS using FFmpeg\n'
                '• Use nginx-rtmp for restreaming',
              ),
              const SizedBox(height: 16),
              _buildSourceSection(
                'Orange Pi Setup',
                '• Stream camera via HLS\n'
                '• ffmpeg -i /dev/video0 \\\n'
                '  -f hls stream.m3u8',
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
        Text(content, style: const TextStyle(fontSize: 13, height: 1.4)),
      ],
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Video Player'),
        content: const Text(
          'This screen uses Flutter\'s official video_player plugin.\n\n'
          'Supported formats:\n'
          '• MP4 video files\n'
          '• HLS streams (.m3u8)\n'
          '• HTTPS video URLs\n\n'
          'For IoT cameras, set up HLS streaming on your Orange Pi.',
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
