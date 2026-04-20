import 'package:flutter/material.dart';

import '../themes/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: statusBarHeight,
            child: const ColoredBox(color: AppTheme.headerBackground),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: const [AppTheme.headerShadow],
      ),
      child: Row(
        children: [
          AppTheme.backButton(
            context,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Notifications',
              textAlign: TextAlign.center,
              style: AppTheme.headlineStyle,
            ),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Settings clicked')));
            },
            icon: const Icon(Icons.settings, size: 24, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _buildSectionTitle('Today'),
        _buildJoinRequestCard(context),
        _buildNewEventCard(context),
        _buildSectionTitle('Sep 2nd'),
        _buildModifiedEventCard(context),
        _buildTaskCompletedCard(context),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildJoinRequestCard(BuildContext context) {
    return _notificationCard(
      context,
      icon: Icons.person_add,
      iconBackground: Colors.yellow.shade700,
      title: 'New member request',
      subtitle: 'John Doe wants to join the family calendar',
      action: TextButton(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Accept clicked')));
        },
        child: const Text('Accept'),
      ),
    );
  }

  Widget _buildNewEventCard(BuildContext context) {
    return _notificationCard(
      context,
      icon: Icons.event,
      iconBackground: Colors.orange.shade600,
      title: 'Scheduled: Sunday Roast',
      subtitle: 'Your family event is set for tomorrow at 6:00 PM',
      action: TextButton(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('View clicked')));
        },
        child: const Text('View'),
      ),
    );
  }

  Widget _buildModifiedEventCard(BuildContext context) {
    return _notificationCard(
      context,
      icon: Icons.edit,
      iconBackground: Colors.blue.shade400,
      title: 'Event changed',
      subtitle: 'Sunday Roast moved to 7:00 PM',
      action: TextButton(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('View clicked')));
        },
        child: const Text('View'),
      ),
    );
  }

  Widget _buildTaskCompletedCard(BuildContext context) {
    return _notificationCard(
      context,
      icon: Icons.check_circle,
      iconBackground: Colors.grey.shade400,
      title: 'Task completed',
      subtitle: 'Dad finished grocery shopping',
      action: TextButton(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Got it clicked')));
        },
        child: const Text('Got it'),
      ),
    );
  }

  Widget _notificationCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBackground,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
          ],
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: Colors.white),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(subtitle),
          trailing: action,
        ),
      ),
    );
  }
}
