import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/shelter_provider.dart';
import '../../widgets/node_card.dart';
import '../../models/shelter_node.dart';

/// Main dashboard screen for shelter monitoring
/// Shows overview of all 4 nodes (W, X, Y, Z)
class ShelterDashboardScreen extends StatelessWidget {
  const ShelterDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelter Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<ShelterProvider>(context, listen: false).refreshData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing data...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<ShelterProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return RefreshIndicator(
            onRefresh: () => provider.refreshData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Demo mode banner
                  if (provider.isDemoMode) _buildDemoBanner(context),
                  
                  // Overview stats card
                  _buildOverviewCard(context, provider),
                  const SizedBox(height: 20),
                  
                  // Alert summary (if any)
                  if (provider.unacknowledgedAlerts.isNotEmpty)
                    _buildAlertSummary(context, provider),
                  
                  // Section title
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Monitoring Stations',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  
                  // Node grid (2x2)
                  _buildNodeGrid(context, provider),
                  const SizedBox(height: 20),
                  
                  // Routing info section
                  if (provider.routingLogs.isNotEmpty)
                    _buildRoutingSection(context, provider),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildDemoBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.science, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Demo Mode - Showing simulated data',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOverviewCard(BuildContext context, ShelterProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.home_work,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shelter Overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${provider.onlineNodeCount}/4 stations online',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                context,
                icon: Icons.restaurant,
                value: '${4 - provider.emptyPlateCount}',
                label: 'Filled',
                color: Colors.white,
              ),
              _buildStatItem(
                context,
                icon: Icons.warning_amber,
                value: '${provider.emptyPlateCount}',
                label: 'Empty',
                color: provider.emptyPlateCount > 0 
                    ? Colors.amber.shade300 
                    : Colors.white,
              ),
              _buildStatItem(
                context,
                icon: Icons.pets,
                value: '${provider.catsPresent}',
                label: 'Cats',
                color: Colors.white,
              ),
              _buildStatItem(
                context,
                icon: Icons.battery_std,
                value: '${provider.averageBattery.toStringAsFixed(0)}%',
                label: 'Avg Batt',
                color: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
  
  Widget _buildAlertSummary(BuildContext context, ShelterProvider provider) {
    final alerts = provider.unacknowledgedAlerts;
    final emptyPlates = provider.emptyPlateAlerts;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active,
              color: AppTheme.warningColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alerts.length} Active Alert${alerts.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.warningColor,
                    fontSize: 16,
                  ),
                ),
                if (emptyPlates.isNotEmpty)
                  Text(
                    '${emptyPlates.length} empty plate${emptyPlates.length > 1 ? 's' : ''} need refill',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // Navigate to alerts tab
              DefaultTabController.of(context).animateTo(1);
            },
            child: const Text('View All'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNodeGrid(BuildContext context, ShelterProvider provider) {
    final nodes = provider.nodeList;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,  // Taller cards to fit content
      ),
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        final node = nodes[index];
        return NodeCard(
          node: node,
          onTap: () => _showNodeDetails(context, node),
        );
      },
    );
  }
  
  Widget _buildRoutingSection(BuildContext context, ShelterProvider provider) {
    final logs = provider.routingLogs.take(3).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Routing Changes',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () => _showAllRoutingLogs(context, provider),
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...logs.map((log) => _buildRoutingLogItem(context, log)),
      ],
    );
  }
  
  Widget _buildRoutingLogItem(BuildContext context, RoutingDecision log) {
    final timeStr = _formatTime(log.timestamp);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              log.nodeId,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.previousNextHop} → ${log.newNextHop}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  log.reason,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showNodeDetails(BuildContext context, ShelterNode node) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NodeDetailSheet(node: node),
    );
  }
  
  void _showAllRoutingLogs(BuildContext context, ShelterProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Routing Decisions Log',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.routingLogs.length,
                  itemBuilder: (context, index) {
                    return _buildRoutingLogItem(context, provider.routingLogs[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

/// Bottom sheet showing detailed node information
class _NodeDetailSheet extends StatelessWidget {
  final ShelterNode node;
  
  const _NodeDetailSheet({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    node.nodeId,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.displayName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: node.isOnline ? AppTheme.successColor : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            node.isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: node.isOnline ? AppTheme.successColor : Colors.grey,
                              fontWeight: FontWeight.w500,
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
            
            // Details
            _buildDetailRow(Icons.restaurant, 'Plate Status', 
              node.plateStatus.displayName,
              node.plateStatus == PlateStatus.empty ? AppTheme.warningColor : null),
            _buildDetailRow(Icons.pets, 'Cat Presence', 
              node.catPresent ? 'Present 🐱' : 'Not Present',
              node.catPresent ? AppTheme.primaryColor : null),
            _buildDetailRow(Icons.battery_std, 'Battery', 
              '${node.batteryPercent.toStringAsFixed(1)}%'),
            if (node.batteryVoltage != null)
              _buildDetailRow(Icons.electrical_services, 'Voltage', 
                '${node.batteryVoltage!.toStringAsFixed(2)}V'),
            _buildDetailRow(Icons.signal_wifi_4_bar, 'Signal', 
              '${node.rssi ?? '?'} dBm'),
            _buildDetailRow(Icons.route, 'Route', 
              node.route.isNotEmpty ? node.route.join(' → ') : '${node.nodeId} → SINK'),
            _buildDetailRow(Icons.alt_route, 'Hops', 
              '${node.hopCount}'),
            
            if (node.lastColorReading != null) ...[
              const Divider(height: 24),
              Text(
                'Last Color Reading',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildColorChip('R', node.lastColorReading!.red, Colors.red),
                  const SizedBox(width: 8),
                  _buildColorChip('G', node.lastColorReading!.green, Colors.green),
                  const SizedBox(width: 8),
                  _buildColorChip('B', node.lastColorReading!.blue, Colors.blue),
                  const Spacer(),
                  Chip(
                    label: Text(
                      node.lastColorReading!.isBrown ? 'Brown (Food)' : 'Not Brown',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: node.lastColorReading!.isBrown 
                        ? Colors.brown.shade100 
                        : Colors.grey.shade200,
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(IconData icon, String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildColorChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }
}
