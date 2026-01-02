import 'package:flutter/material.dart';
import '../../models/shelter_node.dart';
import '../../config/theme.dart';
import '../../screens/shelter/calibration_screen.dart';

/// Card widget displaying status for a single shelter node/bowl
class NodeCard extends StatelessWidget {
  final ShelterNode node;
  final VoidCallback? onTap;
  
  const NodeCard({
    super.key,
    required this.node,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _getBorderColor(),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Node ID + Online Status
            _buildHeader(context),
            const SizedBox(height: 8),
            
            // Plate Status
            _buildPlateStatus(context),
            const SizedBox(height: 6),
            
            // Cat Presence
            _buildCatPresence(context),
            const SizedBox(height: 6),
            
            // Battery
            _buildBattery(context),
            const SizedBox(height: 6),
            
            // Network Info
            _buildNetworkInfo(context),
            
            // Last Update
            const Spacer(),
            _buildLastUpdate(context),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        // Node ID
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            node.nodeId,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Display name
        Expanded(
          child: Text(
            node.displayName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Calibration button
        IconButton(
          icon: Icon(
            Icons.tune,
            color: node.currentCalibration != null 
                ? AppTheme.primaryColor 
                : Colors.grey.shade400,
            size: 14,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          tooltip: node.currentCalibration != null 
              ? 'Calibrated: ${node.currentCalibration!.colorName}'
              : 'Calibrate',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => CalibrationScreen(node: node),
              ),
            );
          },
        ),
        const SizedBox(width: 2),
        // Online indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: node.isOnline 
                ? AppTheme.successColor.withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: node.isOnline ? AppTheme.successColor : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                node.isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  color: node.isOnline ? AppTheme.successColor : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildPlateStatus(BuildContext context) {
    IconData icon;
    Color color;
    String label;
    String? warningText;
    
    switch (node.plateStatus) {
      case PlateStatus.filled:
        icon = Icons.check_circle;
        color = AppTheme.successColor;
        label = 'Filled';
        // Add warning based on detection type
        if (node.lastColorReading != null) {
          final foodType = node.lastColorReading!.foodType;
          final calibrationName = node.currentCalibration?.colorName ?? 'brown';
          if (foodType == FoodDetectionType.other) {
            warningText = '⚠️ Warning: Non-$calibrationName food detected';
            color = AppTheme.warningColor; // Orange for non-match
          } else if (foodType == FoodDetectionType.brown) {
            warningText = '✓ $calibrationName food confirmed';
          }
        }
        break;
      case PlateStatus.empty:
        icon = Icons.warning_rounded;
        color = AppTheme.warningColor;
        label = 'Empty!';
        final calibrationName = node.currentCalibration?.colorName ?? 'brown';
        warningText = 'No $calibrationName food detected';
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
        label = 'Unknown';
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.restaurant, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Plate: ',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        if (warningText != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              warningText,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildCatPresence(BuildContext context) {
    return Row(
      children: [
        Icon(
          node.catPresent ? Icons.pets : Icons.pets_outlined,
          size: 16,
          color: node.catPresent ? AppTheme.primaryColor : AppTheme.textSecondary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            node.catPresent ? 'Cat: Present 🐱' : 'Cat: None',
            style: TextStyle(
              color: node.catPresent ? AppTheme.primaryColor : AppTheme.textSecondary,
              fontWeight: node.catPresent ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  Widget _buildBattery(BuildContext context) {
    Color batteryColor;
    IconData batteryIcon;
    
    if (node.batteryPercent > 60) {
      batteryColor = AppTheme.successColor;
      batteryIcon = Icons.battery_full;
    } else if (node.batteryPercent > 30) {
      batteryColor = AppTheme.warningColor;
      batteryIcon = Icons.battery_4_bar;
    } else if (node.batteryPercent > 10) {
      batteryColor = Colors.orange;
      batteryIcon = Icons.battery_2_bar;
    } else {
      batteryColor = AppTheme.errorColor;
      batteryIcon = Icons.battery_alert;
    }
    
    return Row(
      children: [
        Icon(batteryIcon, size: 16, color: batteryColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${node.batteryPercent.toStringAsFixed(0)}%',
            style: TextStyle(
              color: batteryColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        if (node.batteryVoltage != null) ...[
          Text(
            ' (${node.batteryVoltage!.toStringAsFixed(1)}V)',
            style: TextStyle(
              color: AppTheme.textLight,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildNetworkInfo(BuildContext context) {
    String routeStr = node.route.isNotEmpty 
        ? node.route.join(' → ')
        : '${node.nodeId} → SINK';
    
    return Row(
      children: [
        Icon(Icons.route, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            routeStr,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (node.rssi != null) ...[
          Icon(Icons.signal_wifi_4_bar, size: 14, color: _getSignalColor()),
          const SizedBox(width: 2),
          Text(
            '${node.rssi}dBm',
            style: TextStyle(
              color: AppTheme.textLight,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildLastUpdate(BuildContext context) {
    String timeStr = 'Never';
    if (node.lastUpdate != null) {
      final diff = DateTime.now().difference(node.lastUpdate!);
      if (diff.inSeconds < 60) {
        timeStr = '${diff.inSeconds}s ago';
      } else if (diff.inMinutes < 60) {
        timeStr = '${diff.inMinutes}m ago';
      } else {
        timeStr = '${diff.inHours}h ago';
      }
    }
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(Icons.update, size: 12, color: AppTheme.textLight),
        const SizedBox(width: 4),
        Text(
          timeStr,
          style: TextStyle(
            color: AppTheme.textLight,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
  
  Color _getBorderColor() {
    if (!node.isOnline) return Colors.grey.shade300;
    if (node.plateStatus == PlateStatus.empty && !node.catPresent) {
      return AppTheme.warningColor;
    }
    if (node.catPresent) return AppTheme.primaryColor;
    return Colors.grey.shade200;
  }
  
  Color _getSignalColor() {
    switch (node.signalStrength) {
      case SignalStrength.excellent:
        return AppTheme.successColor;
      case SignalStrength.good:
        return Colors.lightGreen;
      case SignalStrength.fair:
        return AppTheme.warningColor;
      case SignalStrength.poor:
        return AppTheme.errorColor;
      default:
        return Colors.grey;
    }
  }
}

/// Compact node card for list view
class NodeCardCompact extends StatelessWidget {
  final ShelterNode node;
  final VoidCallback? onTap;
  
  const NodeCardCompact({
    super.key,
    required this.node,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _getStatusColor().withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            node.nodeId,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _getStatusColor(),
            ),
          ),
        ),
      ),
      title: Text(
        node.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          Icon(
            node.plateStatus == PlateStatus.filled
                ? Icons.check_circle
                : node.plateStatus == PlateStatus.empty
                    ? Icons.warning
                    : Icons.help_outline,
            size: 14,
            color: node.plateStatus == PlateStatus.filled
                ? AppTheme.successColor
                : node.plateStatus == PlateStatus.empty
                    ? AppTheme.warningColor
                    : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(node.plateStatus.displayName),
          const SizedBox(width: 12),
          if (node.catPresent) ...[
            const Text('🐱', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
          ],
          Text('${node.batteryPercent.toStringAsFixed(0)}%'),
        ],
      ),
      trailing: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: node.isOnline ? AppTheme.successColor : Colors.grey,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
  
  Color _getStatusColor() {
    if (!node.isOnline) return Colors.grey;
    if (node.plateStatus == PlateStatus.empty) return AppTheme.warningColor;
    if (node.catPresent) return AppTheme.primaryColor;
    return AppTheme.successColor;
  }
}
