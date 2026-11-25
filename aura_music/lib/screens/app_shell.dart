// =============================================================================
// app_shell.dart — Estructura de navegación principal y MiniPlayer persistente
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Conecta las pantallas independientes (Inicio, Buscar, Biblioteca) usando
//   un IndexedStack para conservar la posición de scroll sin reconstruir vistas,
//   coloca el MiniPlayer flotante sobre la barra inferior y abre FullPlayerScreen
//   con una transición deslizante fluida desde abajo.
// =============================================================================

import 'package:flutter/material.dart';
import '../core/theme/aura_theme.dart';
import '../widgets/mini_player.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'player/full_player_screen.dart';
import 'search/search_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentTab = 0;
  int _librarySubTab = 0;

  void _openFullPlayer() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => const FullPlayerScreen(),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  void _jumpToLibrarySubTab(int subTab) {
    setState(() {
      _librarySubTab = subTab;
      _currentTab = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentTab,
            children: [
              HomeScreen(onNavigateToLibraryTab: _jumpToLibrarySubTab),
              const SearchScreen(),
              LibraryScreen(initialSubTab: _librarySubTab),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiniPlayer(onExpand: _openFullPlayer),
                _AuraBottomBar(
                  selectedIndex: _currentTab,
                  onDestinationSelected: (idx) {
                    setState(() => _currentTab = idx);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra inferior personalizada que conserva exactamente la estética de Aura
/// Music (fondo avena cálido, borde superior sutil y píldora coral suave) sin
/// el espacio vacío superior que añadía NavigationBar en algunas densidades.
class _AuraBottomBar extends StatelessWidget {
  const _AuraBottomBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _AuraNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Inicio',
                selected: selectedIndex == 0,
                onTap: () => onDestinationSelected(0),
              ),
              _AuraNavItem(
                icon: Icons.search_rounded,
                selectedIcon: Icons.search_rounded,
                label: 'Buscar',
                selected: selectedIndex == 1,
                onTap: () => onDestinationSelected(1),
              ),
              _AuraNavItem(
                icon: Icons.library_music_outlined,
                selectedIcon: Icons.library_music_rounded,
                label: 'Biblioteca',
                selected: selectedIndex == 2,
                onTap: () => onDestinationSelected(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuraNavItem extends StatelessWidget {
  const _AuraNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: c.accent.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 60,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? c.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                selected ? selectedIcon : icon,
                size: 22,
                color: selected ? c.accent : c.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
