import 'package:flutter/material.dart';
import 'home/home_screen.dart';
import 'camera/camera_screen.dart';
import 'history/history_screen.dart';
import 'schedule/schedule_screen.dart';
import 'profile/profile_screen.dart';

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
    const HomeScreen(),
    const CameraScreen(),
    const HistoryScreen(),
    const ScheduleScreen(),
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
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.videocam_outlined),
              activeIcon: Icon(Icons.videocam),
              label: 'Camera',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              activeIcon: Icon(Icons.history),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.schedule_outlined),
              activeIcon: Icon(Icons.schedule),
              label: 'Schedule',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

