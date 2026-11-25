// =============================================================================
// settings_screen.dart — Pantalla de Configuración y Versiones del Motor
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Centraliza las preferencias de Aura Music en una pantalla dedicada:
//   - Selector visual de apariencia (Modo Claro, Modo Oscuro o Sistema).
//   - Panel completo de versiones vivas del motor (yt-dlp, yt-dlp-ejs, Python
//     Chaquopy, Rust QuickJS-ng, Rust Lofty y Rust DSP aura_dsp + arquitectura ABI).
//   - Controles del auto-actualizador PyPI (activar chequeo cada 24 h, buscar
//     actualizaciones, instalarlas con progreso en tiempo real o restaurar las
//     versiones incluidas originalmente en el APK).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SettingsProvider>().loadEngineDetails(includePython: true);
    });
  }

  Future<void> _confirmRestoreBundled(BuildContext context) async {
    final c = AuraTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Restaurar motor del APK',
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Se eliminarán las actualizaciones descargadas desde PyPI en almacenamiento privado y se volverá a usar yt-dlp y yt-dlp-ejs incluidos dentro del APK.',
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<SettingsProvider>().restoreBundled();
    }
  }

  String _formatTimestamp(int ms) {
    if (ms <= 0) return 'Nunca comprobado';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Hoy, $hh:$mm';
    }
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd/$mo/${dt.year} · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final settings = context.watch<SettingsProvider>();
    final ytStatus = settings.engineStatus;
    final eqState = settings.equalizerState;
    final s8dState = settings.spatial8dState;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: c.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Configuración'),
        actions: [
          IconButton(
            tooltip: 'Recargar estado del motor',
            onPressed: settings.isBusy
                ? null
                : () => settings.loadEngineDetails(includePython: true),
            icon: settings.isLoadingStatus
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.accent,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: c.textPrimary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          // -----------------------------------------------------------------
          // Sección 1: Apariencia (Modo Claro / Oscuro / Sistema)
          // -----------------------------------------------------------------
          _SectionTitle(
            icon: Icons.palette_outlined,
            title: 'Apariencia',
          ),
          const SizedBox(height: 10),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tema de la interfaz',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Alterna entre la paleta cálida clara, modo oscuro espresso o el ajuste del teléfono.',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ThemeOptionButton(
                        icon: Icons.light_mode_rounded,
                        label: 'Claro',
                        selected: settings.themeMode == ThemeMode.light,
                        onTap: () => settings.setThemeMode(ThemeMode.light),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ThemeOptionButton(
                        icon: Icons.dark_mode_rounded,
                        label: 'Oscuro',
                        selected: settings.themeMode == ThemeMode.dark,
                        onTap: () => settings.setThemeMode(ThemeMode.dark),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ThemeOptionButton(
                        icon: Icons.brightness_auto_rounded,
                        label: 'Sistema',
                        selected: settings.themeMode == ThemeMode.system,
                        onTap: () => settings.setThemeMode(ThemeMode.system),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // -----------------------------------------------------------------
          // Sección 2: Motor yt-dlp y Auto-actualizador PyPI
          // -----------------------------------------------------------------
          _SectionTitle(
            icon: Icons.system_update_alt_rounded,
            title: 'Motor yt-dlp y actualizaciones',
          ),
          const SizedBox(height: 10),
          _SettingsCard(
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
                            'Auto-actualizar desde PyPI',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Comprueba cada 24 h si hay versiones nuevas de yt-dlp y yt-dlp-ejs antes de descargar por URL.',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 12.2,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value: ytStatus?.autoUpdateEnabled ?? true,
                      activeTrackColor: c.accent,
                      activeThumbColor: Colors.white,
                      onChanged: settings.isBusy
                          ? null
                          : (value) => settings.toggleAutoUpdate(value),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 14),

                // Tabla de versiones del extractor
                _VersionRow(
                  label: 'yt-dlp',
                  value: (ytStatus?.ytDlpVersion ?? '').isNotEmpty
                      ? ytStatus!.ytDlpVersion
                      : (settings.isLoadingStatus ? 'Cargando...' : 'No iniciado'),
                  badgeText: ytStatus?.usingUpdatedYtDlp == true
                      ? 'PyPI'
                      : 'APK base',
                  badgeHighlight: ytStatus?.usingUpdatedYtDlp == true,
                ),
                const SizedBox(height: 10),
                _VersionRow(
                  label: 'yt-dlp-ejs',
                  value: (ytStatus?.ejsVersion ?? '').isNotEmpty
                      ? ytStatus!.ejsVersion
                      : (settings.isLoadingStatus ? 'Cargando...' : 'No iniciado'),
                  badgeText: ytStatus?.usingUpdatedEjs == true
                      ? 'PyPI'
                      : 'APK base',
                  badgeHighlight: ytStatus?.usingUpdatedEjs == true,
                ),
                const SizedBox(height: 10),
                _VersionRow(
                  label: 'Python (Chaquopy)',
                  value: (ytStatus?.pythonVersion ?? '').isNotEmpty
                      ? ytStatus!.pythonVersion
                      : 'Diferido',
                  badgeText: ytStatus?.pythonStarted == true ? 'Activo' : 'Listo',
                  badgeHighlight: ytStatus?.pythonStarted == true,
                ),
                const SizedBox(height: 10),
                _VersionRow(
                  label: 'Rust QuickJS-ng',
                  value: ytStatus?.quickjsReady == true
                      ? 'Binario nativo listo'
                      : 'Verificando ABI',
                  badgeText: (ytStatus?.arch ?? '').isNotEmpty
                      ? ytStatus!.arch
                      : 'Nativo',
                  badgeHighlight: ytStatus?.quickjsReady == true,
                ),
                const SizedBox(height: 10),
                _VersionRow(
                  label: 'Rust Tagging',
                  value: (ytStatus?.audioProcessor ?? '').isNotEmpty
                      ? ytStatus!.audioProcessor
                      : 'lofty',
                  badgeText: (ytStatus?.rustCrate ?? '').isNotEmpty
                      ? ytStatus!.rustCrate
                      : 'aura_yt_engine',
                  badgeHighlight: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Última comprobación: ${_formatTimestamp(ytStatus?.lastUpdateCheckMs ?? 0)}',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),

                // Resultado de chequeo si hay versiones más recientes en PyPI
                if (settings.lastCheckResult != null &&
                    settings.lastCheckResult!.ok &&
                    settings.lastCheckResult!.hasUpdates) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.amberSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.amber.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.new_releases_rounded,
                              size: 16,
                              color: c.amber,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Actualizaciones disponibles en PyPI',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (settings.lastCheckResult!.ytDlp.updateAvailable)
                          Text(
                            '• yt-dlp: ${settings.lastCheckResult!.ytDlp.installed} → ${settings.lastCheckResult!.ytDlp.latest}',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (settings.lastCheckResult!.ytDlpEjs.updateAvailable)
                          Text(
                            '• yt-dlp-ejs: ${settings.lastCheckResult!.ytDlpEjs.installed} → ${settings.lastCheckResult!.ytDlpEjs.latest}',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                // Progreso vivo durante descarga e instalación de wheels
                if (settings.isUpdatingEngine) ...[
                  const SizedBox(height: 14),
                  _UpdateProgressBox(progress: settings.updateProgress),
                ],

                // Mensajes de estado o error
                if (settings.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: c.errorBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.errorBorder),
                    ),
                    child: Text(
                      settings.errorMessage!,
                      style: TextStyle(
                        color: c.errorText,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else if (settings.statusMessage != null &&
                    !settings.isUpdatingEngine) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: c.sageSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.sage.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      settings.statusMessage!,
                      style: TextStyle(
                        color: c.sage,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Botones de acción (seguros en 360dp)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            settings.isBusy ? null : settings.checkForUpdates,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.textPrimary,
                          side: BorderSide(color: c.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: settings.isCheckingUpdates
                            ? SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.accent,
                                ),
                              )
                            : const Icon(Icons.search_rounded, size: 18),
                        label: const Text(
                          'Comprobar',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: settings.isBusy
                            ? null
                            : () => settings.updateNow(force: false),
                        style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: settings.isUpdatingEngine
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 18),
                        label: const Text(
                          'Actualizar',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),

                if (ytStatus?.hasAnyPyPiOverride == true) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: settings.isBusy
                          ? null
                          : () => _confirmRestoreBundled(context),
                      style: TextButton.styleFrom(
                        foregroundColor: c.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text(
                        'Restaurar versión incluida en el APK',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // -----------------------------------------------------------------
          // Sección 3: Motor de audio y DSP nativo
          // -----------------------------------------------------------------
          _SectionTitle(
            icon: Icons.graphic_eq_rounded,
            title: 'Motor de audio y DSP',
          ),
          const SizedBox(height: 10),
          _SettingsCard(
            child: Column(
              children: [
                _VersionRow(
                  label: 'Reproducción',
                  value: 'Media3 ExoPlayer',
                  badgeText: 'Nativo',
                  badgeHighlight: false,
                ),
                const SizedBox(height: 10),
                _VersionRow(
                  label: 'Procesador DSP',
                  value: eqState?.engine ?? 'Biquad IIR 5-band + Soft Limiter',
                  badgeText: eqState?.rustCrate ?? 'aura_dsp',
                  badgeHighlight: eqState?.enabled ?? false,
                ),
                const SizedBox(height: 10),
                _VersionRow(
                  label: 'Estado EQ',
                  value: eqState?.enabled == true
                      ? 'Activo (Limitador ${eqState?.limiterEnabled == true ? "ON" : "OFF"})'
                      : 'Bypass directo',
                  badgeText: (eqState?.arch.isNotEmpty == true)
                      ? eqState!.arch
                      : ((ytStatus?.arch.isNotEmpty == true)
                          ? ytStatus!.arch
                          : 'ABI'),
                  badgeHighlight: eqState?.enabled ?? false,
                ),
                const SizedBox(height: 10),
                _VersionRow(
                  label: 'Audio 8D',
                  value: s8dState?.enabled == true
                      ? 'Activo (${s8dState?.isHeadphonesActive == true ? "Auriculares" : "Altavoz"})'
                      : 'Desactivado',
                  badgeText: s8dState?.modeWireValue == 'auto'
                      ? 'Auto'
                      : (s8dState?.isHeadphonesActive == true
                          ? 'Binaural'
                          : 'Altavoz'),
                  badgeHighlight: s8dState?.enabled ?? false,
                ),
                const SizedBox(height: 10),
                _VersionRow(
                  label: 'Caché streaming (Explorar)',
                  value:
                      '${settings.streamCacheStats.formattedUsed} · ${settings.streamCacheStats.cachedTracks} pistas',
                  badgeText: '512 MB máx',
                  badgeHighlight: settings.streamCacheStats.usedBytes > 0,
                ),
                if (settings.streamCacheStats.usedBytes > 0) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: settings.isBusy
                          ? null
                          : () => settings.clearStreamCache(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: settings.isClearingStreamCache
                          ? SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.accent,
                              ),
                            )
                          : const Icon(Icons.cleaning_services_rounded,
                              size: 17),
                      label: const Text('Vaciar caché de streaming'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // -----------------------------------------------------------------
          // Sección 4: Privacidad y aplicación
          // -----------------------------------------------------------------
          _SectionTitle(
            icon: Icons.info_outline_rounded,
            title: 'Acerca de Aura Music',
          ),
          const SizedBox(height: 10),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: c.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aura Music · v1.0.0',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Arquitectura 32 y 64 bits (armeabi-v7a / arm64-v8a)',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Reproductor local enfocado en privacidad: solo lee las carpetas y pistas que importas manualmente con Storage Access Framework (SAF) o descargas dentro de su almacenamiento privado.',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: c.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

class _ThemeOptionButton extends StatelessWidget {
  const _ThemeOptionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Material(
      color: selected ? c.accentSoft : c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? c.accent : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? c.accent : c.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? c.accent : c.textPrimary,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.value,
    required this.badgeText,
    required this.badgeHighlight,
  });

  final String label;
  final String value;
  final String badgeText;
  final bool badgeHighlight;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: badgeHighlight ? c.sageSoft : c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: badgeHighlight ? c.sage.withValues(alpha: 0.35) : c.border,
            ),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              color: badgeHighlight ? c.sage : c.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _UpdateProgressBox extends StatelessWidget {
  const _UpdateProgressBox({required this.progress});

  final YtUpdateProgressEvent? progress;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final pct = (progress?.percent ?? 0).clamp(0.0, 100.0);
    final msg = (progress?.message ?? '').isNotEmpty
        ? progress!.message
        : 'Actualizando componentes...';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  msg,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${pct.round()}%',
                style: TextStyle(
                  color: c.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct > 0 ? pct / 100.0 : null,
              minHeight: 6,
              backgroundColor: c.border,
              valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            ),
          ),
        ],
      ),
    );
  }
}
