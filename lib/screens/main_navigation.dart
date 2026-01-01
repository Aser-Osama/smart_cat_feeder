import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shelter_provider.dart';
import 'shelter/dashboard_screen.dart';
import 'shelter/alerts_screen.dart';
import 'profile/profile_screen.dart';

/// Main navigation for the Shelter Monitoring System
/// 
/// This navigation structure focuses on:
/// - Dashboard: Overview of all 4 monitoring nodes (W, X, Y, Z)
/// - Alerts: Empty plate warnings and system alerts
/// - Settings: User profile and system configuration
class MainNavigation extends StatefulWidget {
  MainNavigation({super.key}) : super();
  
  /// Global key to access navigation state for programmatic navigation
  static final GlobalKey<_MainNavigationState> navigationKey = GlobalKey<_MainNavigationState>();

  @override
  State<MainNavigation> createState() => _MainNavigationState();
  
  /// Static method to navigate to a tab from anywhere
  static void navigateTo(int index) {
    navigationKey.currentState?.navigateToTab(index);
  }
  
  /// Navigate directly to alerts tab (index 1)
  static void navigateToAlerts() {
    navigationKey.currentState?.navigateToTab(1);
  }
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  
  /// Navigate to a specific tab by index
  void navigateToTab(int index) {
    if (index >= 0 && index < _screens.length) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  final List<Widget> _screens = [
    const ShelterDashboardScreen(),
    const AlertsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Consumer<ShelterProvider>(
          builder: (context, provider, child) {
            final unacknowledgedCount = provider.alertStats.unacknowledged;
            
            return BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: unacknowledgedCount > 0,
                    label: Text(
                      unacknowledgedCount > 9 ? '9+' : '$unacknowledgedCount',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  activeIcon: Badge(
                    isLabelVisible: unacknowledgedCount > 0,
                    label: Text(
                      unacknowledgedCount > 9 ? '9+' : '$unacknowledgedCount',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: const Icon(Icons.notifications),
                  ),
                  label: 'Alerts',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  activeIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

