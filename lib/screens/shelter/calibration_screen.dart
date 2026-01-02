import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/shelter_node.dart';
import '../../models/color_calibration.dart';
import '../../providers/shelter_provider.dart';

/// Screen for calibrating food color detection on a specific node
class CalibrationScreen extends StatefulWidget {
  final ShelterNode node;

  const CalibrationScreen({
    super.key,
    required this.node,
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final _colorNameController = TextEditingController();
  bool _isCalibrating = false;
  ColorCalibration? _pendingCalibration;
  
  @override
  void dispose() {
    _colorNameController.dispose();
    super.dispose();
  }

  void _captureCalibration() {
    if (_colorNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a color name first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final latestReading = widget.node.lastColorReading;
    if (latestReading == null || latestReading.red == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid color reading available. Please wait for sensor data.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _pendingCalibration = ColorCalibration.fromRgbValues(
        colorName: _colorNameController.text.trim(),
        red: latestReading.red,
        green: latestReading.green,
        blue: latestReading.blue,
        tolerance: 0.25, // ±25%
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Captured "${_pendingCalibration!.colorName}" calibration'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _applyCalibration() async {
    if (_pendingCalibration == null) return;

    setState(() => _isCalibrating = true);

    try {
      final provider = Provider.of<ShelterProvider>(context, listen: false);
      await provider.calibrateNodeColor(widget.node.nodeId, _pendingCalibration!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calibration applied to ${widget.node.nodeId}!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply calibration: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCalibrating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final latestReading = widget.node.lastColorReading;
    final hasReading = latestReading != null && latestReading.red > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Calibrate ${widget.node.nodeId}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instructions card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'How to Calibrate',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Enter a name for your food color (e.g., "brown kibble", "red food")\n'
                      '2. Place the food under the color sensor\n'
                      '3. Wait for stable RGB readings\n'
                      '4. Tap "Capture" to save the current color\n'
                      '5. Review the thresholds and tap "Apply" to update the node',
                      style: TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Color name input
            TextField(
              controller: _colorNameController,
              decoration: InputDecoration(
                labelText: 'Food Color Name',
                hintText: 'e.g., brown, red, beige',
                prefixIcon: const Icon(Icons.palette),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),

            // Live RGB display
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Color Sensor',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!hasReading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Waiting for sensor data...',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          _buildColorBar('Red', latestReading!.red, Colors.red),
                          const SizedBox(height: 12),
                          _buildColorBar('Green', latestReading.green, Colors.green),
                          const SizedBox(height: 12),
                          _buildColorBar('Blue', latestReading.blue, Colors.blue),
                          const SizedBox(height: 16),
                          Container(
                            height: 60,
                            decoration: BoxDecoration(
                              color: Color.fromRGBO(
                                latestReading.red.clamp(0, 255),
                                latestReading.green.clamp(0, 255),
                                latestReading.blue.clamp(0, 255),
                                1.0,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: const Center(
                              child: Text(
                                'Current Color',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Capture button
            ElevatedButton.icon(
              onPressed: hasReading ? _captureCalibration : null,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture Current Color'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 24),

            // Pending calibration preview
            if (_pendingCalibration != null) ...[
              Card(
                color: Colors.green.shade50,
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Calibration Ready',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Color Name: ${_pendingCalibration!.colorName}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildThresholdRow('Red', _pendingCalibration!.redMin, _pendingCalibration!.redMax),
                      _buildThresholdRow('Green', _pendingCalibration!.greenMin, _pendingCalibration!.greenMax),
                      _buildThresholdRow('Blue', _pendingCalibration!.blueMin, _pendingCalibration!.blueMax),
                      const SizedBox(height: 8),
                      Text(
                        'Dark Threshold: ${_pendingCalibration!.darkThreshold}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        'G/R Ratio: ${_pendingCalibration!.greenRedRatioMin.toStringAsFixed(2)} - ${_pendingCalibration!.greenRedRatioMax.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isCalibrating ? null : _applyCalibration,
                icon: _isCalibrating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_isCalibrating ? 'Applying...' : 'Apply to Node'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildColorBar(String label, int value, Color color) {
    final percentage = (value / 1500 * 100).clamp(0, 100);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage / 100,
          backgroundColor: Colors.grey.shade200,
          color: color,
          minHeight: 12,
        ),
      ],
    );
  }

  Widget _buildThresholdRow(String label, int min, int max) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '$label: $min - $max',
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}
