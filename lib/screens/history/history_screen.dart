import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../providers/feeder_provider.dart';
import '../../models/feeding_log.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeding History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<FeederProvider>(context, listen: false).refreshData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing data...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: Consumer<FeederProvider>(
        builder: (context, feederProvider, child) {
          if (feederProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          final logs = feederProvider.feedingHistory;
          
          if (logs.isEmpty) {
            return _buildEmptyState(context, feederProvider.historyFilter != null);
          }
          
          return RefreshIndicator(
            onRefresh: () => feederProvider.refreshData(),
            child: Column(
              children: [
                // Stats Summary
                _buildStatsSummary(context, feederProvider),
                
                // Active Filter Indicator
                if (feederProvider.historyFilter != null)
                  _buildActiveFilterChip(context, feederProvider),
                
                // History List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final showDate = index == 0 || 
                          !_isSameDay(log.timestamp, logs[index - 1].timestamp);
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDate) ...[
                            Padding(
                              padding: EdgeInsets.only(bottom: 12, top: index == 0 ? 0 : 20),
                              child: Text(
                                _formatDateHeader(log.timestamp),
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          _buildHistoryCard(context, log),
                          const SizedBox(height: 12),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsSummary(BuildContext context, FeederProvider provider) {
    final todayCount = provider.getTodayFeedingCount();
    final weekCount = provider.getWeekFeedingCount();
    final totalAmount = provider.getTotalAmountDispensed();
    
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Feeding Statistics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(context, 'Today', '$todayCount'),
              Container(width: 1, height: 40, color: Colors.white30),
              _buildStatItem(context, 'This Week', '$weekCount'),
              Container(width: 1, height: 40, color: Colors.white30),
              _buildStatItem(context, 'Total', '${totalAmount.toInt()}g'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }
  
  Widget _buildActiveFilterChip(BuildContext context, FeederProvider provider) {
    final filterName = provider.historyFilter == FeedingType.manual 
        ? 'Manual' 
        : 'Scheduled';
    final filterColor = provider.historyFilter == FeedingType.manual
        ? AppTheme.secondaryColor
        : AppTheme.primaryColor;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: filterColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: filterColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  provider.historyFilter == FeedingType.manual 
                      ? Icons.touch_app 
                      : Icons.schedule,
                  size: 16,
                  color: filterColor,
                ),
                const SizedBox(width: 6),
                Text(
                  '$filterName Only',
                  style: TextStyle(
                    color: filterColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => provider.setHistoryFilter(null),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: filterColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, FeedingLog log) {
    final isManual = log.type == FeedingType.manual;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isManual ? AppTheme.secondaryColor : AppTheme.primaryColor)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isManual ? Icons.touch_app : Icons.schedule,
              color: isManual ? AppTheme.secondaryColor : AppTheme.primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.typeDisplayName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (log.success)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Success',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.successColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Failed',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      DateFormat('hh:mm a').format(log.timestamp),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (log.scheduleName != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.scheduleName!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.primaryColor,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${log.amount.toInt()}g',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.successColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Dispensed',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isFiltered) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFiltered ? Icons.filter_list_off : Icons.history,
                size: 80,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 30),
            Text(
              isFiltered ? 'No Matching Feedings' : 'No Feeding History',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              isFiltered 
                  ? 'Try changing or clearing the filter'
                  : 'Start feeding your cat to see the history here',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (isFiltered) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () {
                  Provider.of<FeederProvider>(context, listen: false)
                      .setHistoryFilter(null);
                },
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear Filter'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    
    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMMM dd, yyyy').format(date);
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year && 
           date1.month == date2.month && 
           date1.day == date2.day;
  }

  void _showFilterDialog(BuildContext context) {
    final feederProvider = Provider.of<FeederProvider>(context, listen: false);
    final currentFilter = feederProvider.historyFilter;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Filter History'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('All Feedings'),
              trailing: currentFilter == null 
                  ? const Icon(Icons.check, color: AppTheme.successColor)
                  : null,
              onTap: () {
                feederProvider.setHistoryFilter(null);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Showing all feedings'),
                    backgroundColor: AppTheme.successColor,
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.touch_app),
              title: const Text('Manual Only'),
              trailing: currentFilter == FeedingType.manual 
                  ? const Icon(Icons.check, color: AppTheme.successColor)
                  : null,
              onTap: () {
                feederProvider.setHistoryFilter(FeedingType.manual);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Showing manual feedings only'),
                    backgroundColor: AppTheme.secondaryColor,
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Scheduled Only'),
              trailing: currentFilter == FeedingType.scheduled 
                  ? const Icon(Icons.check, color: AppTheme.successColor)
                  : null,
              onTap: () {
                feederProvider.setHistoryFilter(FeedingType.scheduled);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Showing scheduled feedings only'),
                    backgroundColor: AppTheme.primaryColor,
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
