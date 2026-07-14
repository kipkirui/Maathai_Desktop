import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/model_controller.dart';
import '../state/translation_controller.dart';
import 'chat_screen.dart';
import 'knowledge_screen.dart';
import 'models_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _navItems = [
    _NavItem(icon: Icons.chat_outlined, activeIcon: Icons.chat, labelKey: 'nav_chat'),
    _NavItem(icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, labelKey: 'nav_knowledge'),
    _NavItem(icon: Icons.memory_outlined, activeIcon: Icons.memory, labelKey: 'nav_models'),
    _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, labelKey: 'nav_settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TranslationController>();
    final modelController = context.watch<ModelController>();

    return Scaffold(
      body: Row(
        children: [
          // Left navigation rail
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 36,
                    height: 36,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.eco,
                      size: 36,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Maathai',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2E7D32),
                        ),
                  ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ModelStatusDot(status: modelController.status),
                ),
              ),
            ),
            destinations: _navItems.map((item) {
              return NavigationRailDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: Text(t.t(item.labelKey)),
              );
            }).toList(),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // Main content area
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                ChatScreen(),
                KnowledgeScreen(),
                ModelsScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.labelKey,
  });
}

class _ModelStatusDot extends StatelessWidget {
  final ModelStatus status;

  const _ModelStatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String tooltip;

    switch (status) {
      case ModelStatus.ready:
        color = Colors.green;
        tooltip = 'Model ready';
      case ModelStatus.loading:
        color = Colors.orange;
        tooltip = 'Model loading...';
      case ModelStatus.generating:
        color = Colors.blue;
        tooltip = 'Generating...';
      case ModelStatus.error:
        color = Colors.red;
        tooltip = 'Model error';
      case ModelStatus.notLoaded:
        color = Colors.grey;
        tooltip = 'No model loaded';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
