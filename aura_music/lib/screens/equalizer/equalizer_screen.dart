// =============================================================================
// equalizer_screen.dart — Pantalla dedicada y comprensible del Ecualizador Rust
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Presenta el motor DSP nativo (`aura_dsp` en Rust) en lenguaje claro y
//   accesible bajo la estética Acoustic Warmth:
//   - Interruptor principal para comparar "Ecualizador activo" vs "Original".
//   - Perfiles rápidos (Natural, Más Graves, Voces Claras, Acústico Cálido,
//     Más Brillo, Noche) con explicación en una línea de lo que modifican.
//   - Curva visual en tiempo real de las 5 bandas.
//   - 5 bandas explicadas por su efecto real (Subgraves, Graves, Voces,
//     Presencia, Brillo) además de su frecuencia en Hz.
//   - Volumen previo (Preamp) y limitador suave anti-distorsión en Rust.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/player_provider.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PlayerProvider>().refreshEqualizerState();
      }
    });
  }

  String _formatDb(double val) {
    final rounded = (val * 2).round() / 2;
    if (rounded.abs() < 0.05) return '0.0 dB';
    final sign = rounded > 0 ? '+' : '';
    return '$sign${rounded.toStringAsFixed(1)} dB';
  }

  String _presetSummary(EqualizerState eq) {
    if (!eq.enabled) {
      return 'Desactivado: escuchas el audio original sin filtros.';
    }
    if (eq.presetId == 'custom') {
      return 'Ajuste personalizado según tus bandas actuales.';
    }
    for (final p in EqualizerState.presets) {
      if (p.id == eq.presetId) return p.description;
    }
    return 'Ecualización activa en tiempo real.';
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final player = context.watch<PlayerProvider>();
    final eq = player.equalizer;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Ecualizador'),
        actions: [
          TextButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              player.resetEqualizer();
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
              // Tarjeta de activación principal
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: eq.enabled
                      ? c.accentSoft.withValues(alpha: 0.72)
                      : c.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: eq.enabled
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
                        color: eq.enabled ? c.accent : c.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: eq.enabled ? Colors.white : c.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eq.enabled
                                ? 'Ecualizador activo'
                                : 'Sonido original',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _presetSummary(eq),
                            maxLines: 2,
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
                      value: eq.enabled,
                      activeTrackColor: c.accent,
                      onChanged: (val) {
                        HapticFeedback.selectionClick();
                        player.setEqualizerEnabled(val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Curva visual en vivo
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                            'Forma del sonido',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          eq.enabled ? 'En vivo' : 'En pausa',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: eq.enabled ? c.accent : c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 92,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _EqCurvePainter(
                          gains: eq.bandGainsDb,
                          enabled: eq.enabled,
                          palette: c,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: EqualizerState.bands
                          .map(
                            (b) => Expanded(
                              child: Text(
                                b.humanName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Perfiles rápidos entendibles
              Text(
                'Estilos rápidos',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Elige un estilo o mueve cualquier barra abajo para crear el tuyo.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: EqualizerState.presets.map((preset) {
                  final selected = eq.enabled && eq.presetId == preset.id;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      player.applyEqualizerPreset(preset);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color:
                            selected ? c.chipSelectedBg : c.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? c.chipSelectedBg : c.border,
                        ),
                      ),
                      child: Text(
                        preset.name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? c.chipSelectedFg : c.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              // 5 bandas explicadas
              Text(
                'Ajuste por zonas del sonido',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ...EqualizerState.bands.map((band) {
                final gain = band.index < eq.bandGainsDb.length
                    ? eq.bandGainsDb[band.index]
                    : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BandControlCard(
                    band: band,
                    gainDb: gain,
                    enabled: eq.enabled,
                    formattedDb: _formatDb(gain),
                    onChanged: (val) => player.setBandGain(band.index, val),
                  ),
                );
              }),

              const SizedBox(height: 10),

              // Preamp y Limitador anti-distorsión
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
                            'Volumen previo (Preamp)',
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
                            _formatDb(eq.preampDb),
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
                      'Sube o baja la fuerza general antes de aplicar los filtros. Bájalo un poco si subes varias bandas al máximo.',
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
                        activeTrackColor: eq.enabled ? c.amber : c.textMuted,
                        inactiveTrackColor: c.border,
                        thumbColor: eq.enabled ? c.amber : c.textSecondary,
                      ),
                      child: Slider(
                        min: -6.0,
                        max: 6.0,
                        divisions: 24,
                        value: eq.preampDb.clamp(-6.0, 6.0),
                        onChanged: (val) => player.setPreampDb(val),
                      ),
                    ),
                    Divider(color: c.border, height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Protección anti-distorsión',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Limitador suave en Rust que evita chasquidos cuando subes mucho los graves.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch.adaptive(
                          value: eq.limiterEnabled,
                          activeTrackColor: c.sage,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            player.setLimiterEnabled(val);
                          },
                        ),
                      ],
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
                        'Motor nativo: Rust ${eq.rustCrate} · ${eq.engine}'
                        '${eq.arch.isNotEmpty ? " (${eq.arch})" : ""}',
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

class _BandControlCard extends StatelessWidget {
  const _BandControlCard({
    required this.band,
    required this.gainDb,
    required this.enabled,
    required this.formattedDb,
    required this.onChanged,
  });

  final EqualizerBandInfo band;
  final double gainDb;
  final bool enabled;
  final String formattedDb;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final active = gainDb.abs() >= 0.1;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: enabled && active
              ? c.accent.withValues(alpha: 0.4)
              : c.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        band.humanName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        band.freqLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: enabled && active ? c.accentSoft : c.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  formattedDb,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: enabled && active ? c.accent : c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            band.effectHint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: c.textSecondary,
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
              activeTrackColor: enabled ? c.accent : c.textMuted,
              inactiveTrackColor: c.border,
              thumbColor: enabled ? c.accent : c.textSecondary,
              overlayColor: c.accent.withValues(alpha: 0.14),
            ),
            child: Slider(
              min: -12.0,
              max: 12.0,
              divisions: 48,
              value: gainDb.clamp(-12.0, 12.0),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  const _EqCurvePainter({
    required this.gains,
    required this.enabled,
    required this.palette,
  });

  final List<double> gains;
  final bool enabled;
  final AuraPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    // Línea base 0 dB
    final zeroPaint = Paint()
      ..color = palette.border
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      zeroPaint,
    );

    if (gains.length < 5) return;

    final points = <Offset>[];
    final stepX = size.width / (gains.length - 1);
    for (var i = 0; i < gains.length; i++) {
      final norm = (gains[i].clamp(-12.0, 12.0) / 12.0);
      final y = centerY - norm * (size.height * 0.4);
      points.add(Offset(i * stepX, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final accentColor = enabled ? palette.accent : palette.textSecondary;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withValues(alpha: enabled ? 0.24 : 0.10),
          accentColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, strokePaint);

    final dotFill = Paint()..color = palette.surfaceElevated;
    final dotStroke = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    for (final pt in points) {
      canvas.drawCircle(pt, 4.5, dotFill);
      canvas.drawCircle(pt, 4.5, dotStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    return oldDelegate.enabled != enabled ||
        oldDelegate.palette != palette ||
        !listEquals(oldDelegate.gains, gains);
  }
}
