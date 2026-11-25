// =============================================================================
// permissions_screen.dart — Pantalla previa de permisos antes de entrar
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Se muestra antes de ingresar a AppShell cuando la app necesita solicitar
//   permisos en tiempo de ejecución (como notificaciones multimedia en Android
//   13+) o confirmar por primera vez el modelo privado de permisos de Aura
//   Music (SAF + selector de galería del sistema sin escaneo global).
//   Escucha el ciclo de vida de la app (WidgetsBindingObserver) para detectar
//   al instante si el usuario concede el permiso desde Ajustes del sistema.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/aura_theme.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({
    super.key,
    required this.onEnterApp,
    required this.onContinueWithoutNotifications,
  });

  final Future<void> Function() onEnterApp;
  final Future<void> Function() onContinueWithoutNotifications;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  PermissionStatus _notificationStatus = PermissionStatus.denied;
  bool _checking = true;
  bool _requesting = false;
  bool _hasAttemptedRequest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatuses();
    }
  }

  Future<void> _refreshStatuses() async {
    try {
      final notif = await Permission.notification.status;
      if (!mounted) return;
      setState(() {
        _notificationStatus = notif;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationStatus = PermissionStatus.granted;
        _checking = false;
      });
    }
  }

  Future<void> _handlePrimaryAction() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    try {
      var status = await Permission.notification.status;
      if (!status.isGranted) {
        status = await Permission.notification.request();
      }
      if (!mounted) return;
      setState(() {
        _notificationStatus = status;
        _hasAttemptedRequest = true;
      });

      if (status.isGranted) {
        await widget.onEnterApp();
      }
    } catch (_) {
      if (mounted) {
        await widget.onEnterApp();
      }
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final notifGranted = _notificationStatus.isGranted;
    final permanentlyDenied = _notificationStatus.isPermanentlyDenied;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(0.0, 2000.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: c.accent,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Permisos necesarios',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Antes de entrar a Aura Music, confirma los permisos necesarios para reproducir en segundo plano y proteger tu privacidad.',
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.45,
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _PermissionCard(
                          icon: Icons.notifications_active_rounded,
                          iconBg: c.accentSoft,
                          iconColor: c.accent,
                          title: 'Notificaciones y controles',
                          description:
                              'Permite mostrar el reproductor en la barra de notificaciones y en la pantalla bloqueada (Android 13+).',
                          badgeText: _checking
                              ? 'Verificando...'
                              : (notifGranted
                                  ? 'Concedido'
                                  : (permanentlyDenied
                                      ? 'Bloqueado'
                                      : 'Requerido')),
                          badgeColor: notifGranted
                              ? c.sage
                              : (permanentlyDenied ? c.errorText : c.amber),
                          badgeBg: notifGranted
                              ? c.sageSoft
                              : (permanentlyDenied ? c.errorBg : c.amberSoft),
                        ),
                        const SizedBox(height: 12),
                        _PermissionCard(
                          icon: Icons.folder_open_rounded,
                          iconBg: c.sageSoft,
                          iconColor: c.sage,
                          title: 'Música y galería bajo demanda',
                          description:
                              'Usamos los selectores seguros de Android (SAF y Photo Picker). Nunca escaneamos todo tu teléfono sin tu permiso.',
                          badgeText: 'Privado',
                          badgeColor: c.sage,
                          badgeBg: c.sageSoft,
                        ),
                        if (!notifGranted && _hasAttemptedRequest) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: c.amberSoft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: c.border),
                            ),
                            child: Text(
                              permanentlyDenied
                                  ? 'El permiso de notificaciones fue bloqueado en el sistema. Ábrelo en Ajustes para habilitar los controles en pantalla bloqueada.'
                                  : 'Sin este permiso, Android 13+ puede ocultar el reproductor en las notificaciones mientras la música suena en segundo plano.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 28),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _checking || _requesting
                              ? null
                              : (permanentlyDenied
                                  ? openAppSettings
                                  : _handlePrimaryAction),
                          style: FilledButton.styleFrom(
                            backgroundColor: c.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: _requesting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  notifGranted
                                      ? Icons.arrow_forward_rounded
                                      : (permanentlyDenied
                                          ? Icons.settings_rounded
                                          : Icons.verified_user_rounded),
                                ),
                          label: Text(
                            notifGranted
                                ? 'Continuar a Aura Music'
                                : (permanentlyDenied
                                    ? 'Abrir ajustes del sistema'
                                    : 'Conceder permisos y entrar'),
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!notifGranted && _hasAttemptedRequest) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _requesting
                                ? null
                                : widget.onContinueWithoutNotifications,
                            style: TextButton.styleFrom(
                              foregroundColor: c.textSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'Entrar sin notificaciones por ahora',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.badgeText,
    required this.badgeColor,
    required this.badgeBg,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;
  final String badgeText;
  final Color badgeColor;
  final Color badgeBg;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: c.textSecondary,
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
