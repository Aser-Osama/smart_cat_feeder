class ColorCalibration {
  final String colorName;
  final int redMin;
  final int redMax;
  final int greenMin;
  final int greenMax;
  final int blueMin;
  final int blueMax;
  final int darkThreshold;
  final double greenRedRatioMin;
  final double greenRedRatioMax;

  ColorCalibration({
    required this.colorName,
    required this.redMin,
    required this.redMax,
    required this.greenMin,
    required this.greenMax,
    required this.blueMin,
    required this.blueMax,
    required this.darkThreshold,
    required this.greenRedRatioMin,
    required this.greenRedRatioMax,
  });

  /// Create calibration from captured RGB values with tolerance
  factory ColorCalibration.fromRgbValues({
    required String colorName,
    required int red,
    required int green,
    required int blue,
    double tolerance = 0.25, // ±25% by default
  }) {
    final redMin = (red * (1 - tolerance)).round().clamp(0, 65535);
    final redMax = (red * (1 + tolerance)).round().clamp(0, 65535);
    final greenMin = (green * (1 - tolerance)).round().clamp(0, 65535);
    final greenMax = (green * (1 + tolerance)).round().clamp(0, 65535);
    final blueMin = (blue * (1 - tolerance)).round().clamp(0, 65535);
    final blueMax = (blue * (1 + tolerance)).round().clamp(0, 65535);

    // Calculate G/R ratio range
    final avgRatio = green / red;
    final greenRedRatioMin = (avgRatio * (1 - tolerance)).clamp(0.0, 2.0);
    final greenRedRatioMax = (avgRatio * (1 + tolerance)).clamp(0.0, 2.0);

    // Dark threshold is 75% of the minimum RGB value
    final darkThreshold = ([red, green, blue].reduce((a, b) => a < b ? a : b) * 0.75).round();

    return ColorCalibration(
      colorName: colorName,
      redMin: redMin,
      redMax: redMax,
      greenMin: greenMin,
      greenMax: greenMax,
      blueMin: blueMin,
      blueMax: blueMax,
      darkThreshold: darkThreshold,
      greenRedRatioMin: greenRedRatioMin,
      greenRedRatioMax: greenRedRatioMax,
    );
  }

  Map<String, dynamic> toJson() => {
        'colorName': colorName,
        'redMin': redMin,
        'redMax': redMax,
        'greenMin': greenMin,
        'greenMax': greenMax,
        'blueMin': blueMin,
        'blueMax': blueMax,
        'darkThreshold': darkThreshold,
        'greenRedRatioMin': greenRedRatioMin,
        'greenRedRatioMax': greenRedRatioMax,
      };

  factory ColorCalibration.fromJson(Map<String, dynamic> json) {
    return ColorCalibration(
      colorName: json['colorName'] as String,
      redMin: json['redMin'] as int,
      redMax: json['redMax'] as int,
      greenMin: json['greenMin'] as int,
      greenMax: json['greenMax'] as int,
      blueMin: json['blueMin'] as int,
      blueMax: json['blueMax'] as int,
      darkThreshold: json['darkThreshold'] as int,
      greenRedRatioMin: (json['greenRedRatioMin'] as num).toDouble(),
      greenRedRatioMax: (json['greenRedRatioMax'] as num).toDouble(),
    );
  }

  @override
  String toString() {
    return 'ColorCalibration($colorName: R[$redMin-$redMax] G[$greenMin-$greenMax] B[$blueMin-$blueMax])';
  }
}
