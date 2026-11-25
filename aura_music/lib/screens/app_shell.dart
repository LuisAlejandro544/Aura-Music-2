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
    return Scaffold(
      backgroundColor: AuraColors.background,
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
                Container(
                  decoration: const BoxDecoration(
                    color: AuraColors.surface,
                    border: Border(
                      top: BorderSide(color: AuraColors.border, width: 1),
                    ),
                  ),
                  child: NavigationBar(
                    height: 66,
                    backgroundColor: AuraColors.surface,
                    elevation: 0,
                    indicatorColor: AuraColors.accentSoft,
                    selectedIndex: _currentTab,
                    onDestinationSelected: (idx) {
                      setState(() => _currentTab = idx);
                    },
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(
                          Icons.home_rounded,
                          color: AuraColors.accent,
                        ),
                        label: 'Inicio',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search_rounded),
                        selectedIcon: Icon(
                          Icons.search_rounded,
                          color: AuraColors.accent,
                        ),
                        label: 'Buscar',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.library_music_outlined),
                        selectedIcon: Icon(
                          Icons.library_music_rounded,
                          color: AuraColors.accent,
                        ),
                        label: 'Biblioteca',
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
}
