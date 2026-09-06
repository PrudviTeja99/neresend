import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../state/navigation_provider.dart';
import '../widgets/docked_transfer_bar.dart';
import 'history_modal.dart';
import 'nearby_tab_screen.dart';
import 'remote_tab_screen.dart';
import 'settings_modal.dart';

/// Root shell with 2-Tab Navigation (Nearby | Remote), persistent header, and docked transfer bar
class MainScaffoldScreen extends ConsumerWidget {
  const MainScaffoldScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeTabProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.swap_calls_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('DropFlow'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: AppColors.textSecondary),
            tooltip: 'Transfer History',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const HistoryModal(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
            tooltip: 'Settings & Identity',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const SettingsModal(),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceHighlight),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: 'Nearby',
                    icon: Icons.radar_rounded,
                    isSelected: activeTab == 0,
                    onTap: () => ref.read(activeTabProvider.notifier).state = 0,
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    label: 'Remote',
                    icon: Icons.public_rounded,
                    isSelected: activeTab == 1,
                    onTap: () => ref.read(activeTabProvider.notifier).state = 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: activeTab,
                children: const [
                  NearbyTabScreen(),
                  RemoteTabScreen(),
                ],
              ),
            ),

            // Persistent Docked Transfer Bar Slot (Visible when transfer is active)
            const DockedTransferBar(),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

