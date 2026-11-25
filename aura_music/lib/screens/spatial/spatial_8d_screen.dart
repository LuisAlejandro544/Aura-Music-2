// =============================================================================
// spatial_8d_screen.dart — Pantalla dedicada para Audio 8D en Rust (`aura_dsp`)
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Proporciona una pantalla separada siguiendo la estética Acoustic Warmth
//   para configurar el efecto de Audio 8D orbital en tiempo real:
//   - Interruptor principal de activación (independiente del ecualizador).
//   - Modo dual de salida: Automático (detecta auriculares vs altavoz vía
//     AudioManager), Auriculares (binaural completo con ITD y sombra craneal)
//     o Altavoz (mono-safe sin cancelación de fase ni reverb).
//   - Velocidad de giro orbital e intensidad del efecto.
//   - Sin íconos 3D ni íconos animados, y sin efectos de reverb.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/player_provider.dart';

class Spatial8dScreen extends StatefulWidget {
  const Spatial8dScreen({super.key});

  @override
  State<Spatial8dScreen> createState() => _Spatial8dScreenState();
}

class _Spatial8dScreenState extends State<Spatial8dScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PlayerProvider>().refreshSpatial8dState();
      }
    });
  }

  String _modeDescription(Spatial8dState s8d) {
    if (!s8d.enabled) {
      return 'Desactivado: escuchas la mezcla estéreo original sin giro orbital.';
    }
    return s8d.isHeadphonesActive
        ? 'Perfil Auriculares activo: órbita 360°, micro-retardo binaural y sombra craneal.'
        : 'Perfil Altavoz activo: órbita segura para altavoces y salida mono sin cancelación.';
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final player = context.watch<PlayerProvider>();
    final s8d = player.spatial8d;
    final intensityPct = (s8d.intensity * 100).round();
    final orbitSecLabel = '${s8d.orbitSeconds.toStringAsFixed(1)} s/vuelta';

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Audio 8D'),
        actions: [
          TextButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              player.resetSpatial8d();
            },
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text(
              'Reiniciar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(
              foregroundColor: c.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tarjeta principal de activación (estática, sin íconos 3D en movimiento)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: s8d.enabled
                      ? c.accentSoft.withValues(alpha: 0.72)
                      : c.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: s8d.enabled
                        ? c.accent.withValues(alpha: 0.35)
                        : c.border,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: s8d.enabled ? c.accent : c.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.surround_sound_rounded,
                        color: s8d.enabled ? Colors.white : c.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s8d.enabled
                                ? 'Audio 8D activo'
                                : 'Audio 8D desactivado',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _modeDescription(s8d),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: s8d.enabled,
                      activeTrackColor: c.accent,
                      onChanged: (val) {
                        HapticFeedback.selectionClick();
                        player.setSpatial8dEnabled(val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Selector de salida (Auriculares vs Altavoz vs Automático)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Adaptación de salida',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: s8d.isHeadphonesActive
                                ? c.sageSoft
                                : c.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                s8d.isHeadphonesActive
                                    ? Icons.headphones_rounded
                                    : Icons.speaker_rounded,
                                size: 14,
                                color: s8d.isHeadphonesActive
                                    ? c.sage
                                    : c.textSecondary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                s8d.isHeadphonesActive
                                    ? 'Auriculares'
                                    : 'Altavoz',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: s8d.isHeadphonesActive
                                      ? c.sage
                                      : c.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'En Automático cambia solo entre perfil binaural (auriculares) y perfil seguro para altavoces del teléfono.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OutputModeOption(
                      icon: Icons.autorenew_rounded,
                      title: 'Automático',
                      subtitle:
                          'Detecta si conectas auriculares por cable, USB o Bluetooth.',
                      selected: s8d.mode == Spatial8dOutputMode.auto,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        player.setSpatial8dMode(Spatial8dOutputMode.auto);
                      },
                    ),
                    const SizedBox(height: 8),
                    _OutputModeOption(
                      icon: Icons.headphones_rounded,
                      title: 'Forzar auriculares',
                      subtitle:
                          'Paneo orbital 360°, micro-retardo binaural y sombra craneal.',
                      selected: s8d.mode == Spatial8dOutputMode.headphones,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        player.setSpatial8dMode(Spatial8dOutputMode.headphones);
                      },
                    ),
                    const SizedBox(height: 8),
                    _OutputModeOption(
                      icon: Icons.speaker_rounded,
                      title: 'Forzar altavoz',
                      subtitle:
                          'Espacializado compatible con altavoces y mezcla mono sin fase hueca.',
                      selected: s8d.mode == Spatial8dOutputMode.speaker,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        player.setSpatial8dMode(Spatial8dOutputMode.speaker);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Controles de velocidad e intensidad (sin reverb)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Velocidad de giro',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            orbitSecLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Controla qué tan rápido rodea el sonido. Valores bajos dan una sensación más relajada.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: c.textSecondary,
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7.5,
                        ),
                        activeTrackColor: s8d.enabled ? c.accent : c.textMuted,
                        inactiveTrackColor: c.border,
                        thumbColor: s8d.enabled ? c.accent : c.textSecondary,
                      ),
                      child: Slider(
                        min: 0.05,
                        max: 0.45,
                        divisions: 40,
                        value: s8d.speedHz.clamp(0.05, 0.45),
                        onChanged: (val) => player.setSpatial8dSpeedHz(val),
                      ),
                    ),
                    Divider(color: c.border, height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Intensidad del efecto',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$intensityPct%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ajusta la amplitud del movimiento lateral y la profundidad sin alterar el timbre base.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: c.textSecondary,
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7.5,
                        ),
                        activeTrackColor: s8d.enabled ? c.amber : c.textMuted,
                        inactiveTrackColor: c.border,
                        thumbColor: s8d.enabled ? c.amber : c.textSecondary,
                      ),
                      child: Slider(
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        value: s8d.intensity.clamp(0.0, 1.0),
                        onChanged: (val) => player.setSpatial8dIntensity(val),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Ficha del motor Rust DSP
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.memory_rounded,
                      size: 20,
                      color: c.sage,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Motor nativo: Rust ${s8d.rustCrate} · 8D Orbital puro (sin reverb)'
                        '${s8d.arch.isNotEmpty ? " (${s8d.arch})" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutputModeOption extends StatelessWidget {
  const _OutputModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? c.accent.withValues(alpha: 0.45) : c.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? c.accent : c.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? c.accent : c.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
