import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../providers/shelter_provider.dart';
import '../../models/alert.dart';

/// Screen showing all alerts from shelter nodes
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertType? _filterType;
  bool _showAcknowledged = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                if (value == 'all') {
                  _filterType = null;
                } else if (value == 'empty_plate') {
                  _filterType = AlertType.emptyPlate;
                } else if (value == 'low_battery') {
                  _filterType = AlertType.lowBattery;
                } else if (value == 'node_offline') {
                  _filterType = AlertType.nodeOffline;
                } else if (value == 'toggle_ack') {
                  _showAcknowledged = !_showAcknowledged;
                }
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Types')),
              const PopupMenuItem(value: 'empty_plate', child: Text('🍽️ Empty Plates')),
              const PopupMenuItem(value: 'low_battery', child: Text('🔋 Low Battery')),
              const PopupMenuItem(value: 'node_offline', child: Text('📡 Node Offline')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'toggle_ack',
                child: Row(
                  children: [
                    Icon(
                      _showAcknowledged ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Show Acknowledged'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<ShelterProvider>(
        builder: (context, provider, child) {
          // Filter alerts
          var alerts = provider.alerts.where((a) {
            if (_filterType != null && a.type != _filterType) return false;
            if (!_showAcknowledged && a.acknowledged) return false;
            return true;
          }).toList();

          if (alerts.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              // Stats bar
              _buildStatsBar(context, provider),
              
              // Alerts list
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => provider.refreshData(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: alerts.length,
                    itemBuilder: (context, index) {
                      return _buildAlertCard(context, provider, alerts[index]);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            _filterType != null 
                ? 'No ${_filterType!.displayName} alerts'
                : 'No alerts',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All stations are operating normally',
            style: TextStyle(
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(BuildContext context, ShelterProvider provider) {
    final stats = provider.alertStats;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatChip(
            Icons.warning_amber_rounded,
            '${stats.unacknowledged}',
            'Active',
            AppTheme.warningColor,
          ),
          _buildStatChip(
            Icons.restaurant,
            '${stats.emptyPlates}',
            'Empty',
            Colors.orange,
          ),
          _buildStatChip(
            Icons.battery_alert,
            '${stats.lowBatteryNodes}',
            'Low Batt',
            Colors.red.shade400,
          ),
          _buildStatChip(
            Icons.wifi_off,
            '${stats.offlineNodes}',
            'Offline',
            Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAlertCard(BuildContext context, ShelterProvider provider, ShelterAlert alert) {
    final timeFormat = DateFormat('MMM d, h:mm a');
    
    return Dismissible(
      key: Key(alert.id),
      direction: alert.acknowledged 
          ? DismissDirection.none 
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.successColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      onDismissed: (_) {
        provider.acknowledgeAlert(alert.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert acknowledged'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: alert.acknowledged 
                ? Colors.grey.shade200 
                : _getSeverityColor(alert.severity).withOpacity(0.3),
            width: alert.acknowledged ? 1 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showAlertDetails(context, alert, provider),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Alert icon
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getTypeColor(alert.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      alert.type.icon,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Node ${alert.nodeId}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getSeverityColor(alert.severity).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                alert.severity.name.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _getSeverityColor(alert.severity),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          alert.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: alert.acknowledged 
                                ? AppTheme.textSecondary 
                                : AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeFormat.format(alert.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Status indicator
                  if (alert.acknowledged)
                    Icon(
                      Icons.check_circle,
                      color: AppTheme.successColor,
                      size: 24,
                    )
                  else
                    Icon(
                      Icons.chevron_right,
                      color: AppTheme.textLight,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAlertDetails(BuildContext context, ShelterAlert alert, ShelterProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getTypeColor(alert.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      alert.type.icon,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.title,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('MMM d, yyyy h:mm a').format(alert.timestamp),
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              
              // Message
              Text(
                alert.message ?? alert.defaultMessage,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
              
              // Details
              if (alert.details != null && alert.details!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: alert.details!.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDetailKey(e.key),
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                            Text(
                              e.value.toString(),
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Actions
              if (!alert.acknowledged)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      provider.acknowledgeAlert(alert.id);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Alert acknowledged')),
                      );
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Acknowledge Alert'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: AppTheme.successColor),
                      const SizedBox(width: 8),
                      Text(
                        'Acknowledged ${alert.acknowledgedAt != null ? DateFormat('MMM d, h:mm a').format(alert.acknowledgedAt!) : ''}',
                        style: TextStyle(
                          color: AppTheme.successColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 12),
              
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDetailKey(String key) {
    // Convert camelCase to Title Case
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .replaceFirst(key[0], key[0].toUpperCase())
        .trim();
  }

  Color _getTypeColor(AlertType type) {
    switch (type) {
      case AlertType.emptyPlate:
        return Colors.orange;
      case AlertType.lowBattery:
        return Colors.red;
      case AlertType.nodeOffline:
        return Colors.grey;
      case AlertType.routeChange:
        return AppTheme.primaryColor;
      case AlertType.catPresent:
        return Colors.blue;
    }
  }

  Color _getSeverityColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.info:
        return Colors.blue;
      case AlertSeverity.warning:
        return AppTheme.warningColor;
      case AlertSeverity.critical:
        return AppTheme.errorColor;
    }
  }
}
