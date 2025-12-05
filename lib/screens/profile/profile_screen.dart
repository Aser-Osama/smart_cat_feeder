import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                
                // Profile Header
                _buildProfileHeader(context, authProvider),
                const SizedBox(height: 30),
                
                // Settings Sections
                _buildSettingsSection(
                  context,
                  title: 'Account Settings',
                  items: [
                    _SettingItem(
                      icon: Icons.person_outline,
                      title: 'Edit Profile',
                      subtitle: 'Update your personal information',
                      onTap: () => _showComingSoon(context, 'Edit Profile'),
                    ),
                    _SettingItem(
                      icon: Icons.email_outlined,
                      title: 'Email',
                      subtitle: authProvider.userEmail ?? 'Not set',
                      onTap: () => _showComingSoon(context, 'Change Email'),
                    ),
                    _SettingItem(
                      icon: Icons.lock_outline,
                      title: 'Change Password',
                      subtitle: 'Update your password',
                      onTap: () => _showComingSoon(context, 'Change Password'),
                    ),
                  ],
                ),
                
                _buildSettingsSection(
                  context,
                  title: 'Feeder Settings',
                  items: [
                    _SettingItem(
                      icon: Icons.devices,
                      title: 'Device Management',
                      subtitle: 'Manage connected feeders',
                      onTap: () => _showComingSoon(context, 'Device Management'),
                    ),
                    _SettingItem(
                      icon: Icons.wifi,
                      title: 'Connection Settings',
                      subtitle: 'Configure WiFi and network',
                      onTap: () => _showComingSoon(context, 'Connection Settings'),
                    ),
                    _SettingItem(
                      icon: Icons.tune,
                      title: 'Portion Settings',
                      subtitle: 'Adjust default portion size',
                      onTap: () => _showComingSoon(context, 'Portion Settings'),
                    ),
                  ],
                ),
                
                _buildSettingsSection(
                  context,
                  title: 'Notifications',
                  items: [
                    _SettingItem(
                      icon: Icons.notifications_outlined,
                      title: 'Push Notifications',
                      subtitle: 'Manage notification preferences',
                      onTap: () => _showComingSoon(context, 'Notifications'),
                    ),
                    _SettingItem(
                      icon: Icons.volume_up_outlined,
                      title: 'Sound & Alerts',
                      subtitle: 'Configure alert sounds',
                      onTap: () => _showComingSoon(context, 'Sound & Alerts'),
                    ),
                  ],
                ),
                
                _buildSettingsSection(
                  context,
                  title: 'App Settings',
                  items: [
                    _SettingItem(
                      icon: Icons.palette_outlined,
                      title: 'Theme',
                      subtitle: 'Light mode',
                      onTap: () => _showComingSoon(context, 'Theme Settings'),
                    ),
                    _SettingItem(
                      icon: Icons.language_outlined,
                      title: 'Language',
                      subtitle: 'English',
                      onTap: () => _showComingSoon(context, 'Language Settings'),
                    ),
                  ],
                ),
                
                _buildSettingsSection(
                  context,
                  title: 'Support',
                  items: [
                    _SettingItem(
                      icon: Icons.help_outline,
                      title: 'Help & FAQ',
                      subtitle: 'Get help and support',
                      onTap: () => _showComingSoon(context, 'Help & FAQ'),
                    ),
                    _SettingItem(
                      icon: Icons.info_outline,
                      title: 'About',
                      subtitle: 'App version and information',
                      onTap: () => _showAboutDialog(context),
                    ),
                    _SettingItem(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      subtitle: 'Read our privacy policy',
                      onTap: () => _showComingSoon(context, 'Privacy Policy'),
                    ),
                  ],
                ),
                
                // Logout Button
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _handleLogout(context, authProvider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout, color: Colors.white),
                          const SizedBox(width: 10),
                          Text(
                            'Logout',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, AuthProvider authProvider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
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
      child: Row(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _getInitial(authProvider.userName),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authProvider.userName ?? 'User',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  authProvider.userEmail ?? 'user@example.com',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_user,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Verified',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context, {
    required String title,
    required List<_SettingItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
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
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1, indent: 60),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: AppTheme.primaryColor),
                ),
                title: Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  item.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textLight),
                onTap: item.onTap,
              );
            },
          ),
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature will be available in future updates'),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Smart Cat Feeder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Version: 1.0.0+1'),
            const SizedBox(height: 10),
            const Text('Phase 1: Core Functionality'),
            const SizedBox(height: 10),
            Text(
              'A Flutter mobile application for remotely controlling and monitoring your smart cat feeder.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 15),
            const Text('Developer: Aser Osama'),
            const Text('Course: SWAPD 402'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getInitial(String? name) {
    if (name == null || name.isEmpty) return 'U';
    return name.substring(0, 1).toUpperCase();
  }

  void _handleLogout(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await authProvider.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Logout', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

