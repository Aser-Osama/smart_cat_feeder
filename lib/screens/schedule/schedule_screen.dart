import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/schedule.dart';
import '../../providers/feeder_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeding Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: Consumer<FeederProvider>(
        builder: (context, provider, child) {
          final schedules = provider.schedules;
          
          if (schedules.isEmpty) {
            return _buildEmptyState(context);
          }
          
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: schedules.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    _buildHeaderCard(context, provider),
                    const SizedBox(height: 25),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: _buildScheduleCard(context, schedules[index - 1], provider),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddScheduleDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Schedule'),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, FeederProvider provider) {
    final activeCount = provider.activeSchedulesCount;
    
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.schedule,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automated Feeding',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$activeCount active schedule${activeCount != 1 ? 's' : ''}',
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Schedules run automatically. Make sure your feeder is connected.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(BuildContext context, FeedingSchedule schedule, FeederProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      schedule.formattedTime,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: schedule.isActive,
                onChanged: (value) => provider.toggleScheduleActive(schedule.id),
                activeTrackColor: AppTheme.successColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Amount
          Row(
            children: [
              const Icon(
                Icons.restaurant_menu,
                color: AppTheme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Amount: ${schedule.amount.toInt()}g',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Weekdays
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                color: AppTheme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  schedule.formattedWeekdays,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showEditScheduleDialog(context, schedule),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(color: AppTheme.primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _deleteSchedule(context, schedule.id, provider),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    side: const BorderSide(color: AppTheme.errorColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
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
              child: const Icon(
                Icons.schedule,
                size: 80,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 30),
            Text(
              'No Schedules Yet',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Create your first feeding schedule to automate your pet care',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            CustomButton(
              text: 'Add Schedule',
              icon: Icons.add,
              onPressed: () => _showAddScheduleDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddScheduleDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ScheduleFormDialog(),
    );
  }

  void _showEditScheduleDialog(BuildContext context, FeedingSchedule schedule) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduleFormDialog(schedule: schedule),
    );
  }

  void _deleteSchedule(BuildContext context, String id, FeederProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: const Text('Are you sure you want to delete this feeding schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await provider.deleteSchedule(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Schedule deleted' : 'Failed to delete schedule'),
                    backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Schedules'),
        content: const Text(
          'Automated feeding schedules will run automatically at the set times. '
          'The feeder will dispense the specified amount of food on the selected days.\n\n'
          'Make sure your feeder is connected and has enough food!',
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
}

/// Form dialog for creating/editing feeding schedules
class ScheduleFormDialog extends StatefulWidget {
  final FeedingSchedule? schedule;

  const ScheduleFormDialog({super.key, this.schedule});

  @override
  State<ScheduleFormDialog> createState() => _ScheduleFormDialogState();
}

class _ScheduleFormDialogState extends State<ScheduleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  List<int> _selectedWeekdays = [1, 2, 3, 4, 5, 6, 7];
  bool _isLoading = false;
  
  bool get isEditing => widget.schedule != null;
  
  @override
  void initState() {
    super.initState();
    if (widget.schedule != null) {
      _nameController.text = widget.schedule!.name;
      _amountController.text = widget.schedule!.amount.toInt().toString();
      _selectedTime = widget.schedule!.time;
      _selectedWeekdays = List.from(widget.schedule!.weekdays);
    } else {
      _amountController.text = '50';
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 80),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textLight.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Title
                Text(
                  isEditing ? 'Edit Schedule' : 'New Feeding Schedule',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isEditing 
                      ? 'Update the schedule details below'
                      : 'Set up an automated feeding time for your cat',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                
                // Schedule Name
                CustomTextField(
                  controller: _nameController,
                  label: 'Schedule Name',
                  hint: 'e.g., Morning Feeding',
                  prefixIcon: Icons.label_outline,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name for this schedule';
                    }
                    if (value.length > 30) {
                      return 'Name must be 30 characters or less';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                
                // Time Picker
                _buildTimePicker(context),
                const SizedBox(height: 20),
                
                // Amount
                CustomTextField(
                  controller: _amountController,
                  label: 'Portion Size (grams)',
                  hint: 'e.g., 50',
                  prefixIcon: Icons.restaurant_menu,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter an amount';
                    }
                    final amount = double.tryParse(value);
                    if (amount == null) {
                      return 'Please enter a valid number';
                    }
                    if (amount < 10 || amount > 200) {
                      return 'Amount must be between 10 and 200 grams';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                
                // Weekday Selector
                _buildWeekdaySelector(context),
                const SizedBox(height: 30),
                
                // Submit Button
                CustomButton(
                  text: isEditing ? 'Save Changes' : 'Create Schedule',
                  icon: isEditing ? Icons.save : Icons.add,
                  onPressed: _isLoading ? null : _submitForm,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 10),
                
                // Cancel Button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimePicker(BuildContext context) {
    final formattedTime = _formatTime(_selectedTime);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Feeding Time',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final time = await showTimePicker(
              context: context,
              initialTime: _selectedTime,
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppTheme.primaryColor,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (time != null) {
              setState(() => _selectedTime = time);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.textLight.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: AppTheme.textLight),
                const SizedBox(width: 12),
                Text(
                  formattedTime,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdaySelector(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final dayNumbers = [1, 2, 3, 4, 5, 6, 7];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Repeat on Days',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedWeekdays.length == 7) {
                    _selectedWeekdays = [];
                  } else {
                    _selectedWeekdays = [1, 2, 3, 4, 5, 6, 7];
                  }
                });
              },
              child: Text(
                _selectedWeekdays.length == 7 ? 'Clear All' : 'Select All',
                style: const TextStyle(color: AppTheme.primaryColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            final dayNumber = dayNumbers[index];
            final isSelected = _selectedWeekdays.contains(dayNumber);
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedWeekdays.remove(dayNumber);
                  } else {
                    _selectedWeekdays.add(dayNumber);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isSelected 
                      ? AppTheme.primaryColor 
                      : AppTheme.surfaceColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected 
                        ? AppTheme.primaryColor 
                        : AppTheme.textLight.withOpacity(0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    days[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        if (_selectedWeekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Please select at least one day',
              style: TextStyle(
                color: AppTheme.errorColor,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  String _formatTime(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one day'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    final provider = Provider.of<FeederProvider>(context, listen: false);
    
    final schedule = FeedingSchedule(
      id: widget.schedule?.id ?? '',
      name: _nameController.text.trim(),
      time: _selectedTime,
      amount: double.parse(_amountController.text),
      isActive: widget.schedule?.isActive ?? true,
      weekdays: _selectedWeekdays..sort(),
      createdAt: widget.schedule?.createdAt,
    );
    
    bool success;
    if (isEditing) {
      success = await provider.updateSchedule(schedule);
    } else {
      success = await provider.addSchedule(schedule);
    }
    
    if (!mounted) return;
    
    setState(() => _isLoading = false);
    
    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? 'Schedule updated!' : 'Schedule created!'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Operation failed'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }
}
