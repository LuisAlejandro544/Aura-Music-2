// =============================================================================
// import_source_sheet.dart — Popup para importar música local manualmente
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Permite a la usuaria elegir qué canciones o carpetas importar desde su
//   dispositivo mediante Storage Access Framework (SAF), mostrando progreso en
//   tiempo real mientras Kotlin Coroutines extrae metadatos y carátulas.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/aura_theme.dart';
import '../../screens/import/download_url_screen.dart';
import '../../state/library_provider.dart';

Future<void> showImportSourceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ImportSourceSheet(),
  );
}

class _ImportSourceSheet extends StatelessWidget {
  const _ImportSourceSheet();

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final library = context.watch<LibraryProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Importar tu música',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Aura Music nunca escanea todo tu teléfono. Elige exactamente las canciones o carpetas que quieres traer.',
              style: TextStyle(
                fontSize: 13.5,
                color: c.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            if (library.isImporting) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: c.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            library.importTotal > 0
                                ? 'Leyendo metadatos (${library.importProcessed}/${library.importTotal})...'
                                : 'Abriendo selector del sistema...',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (library.importTotal > 0) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (library.importProcessed / library.importTotal)
                              .clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: c.border,
                          valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              _ImportOptionCard(
                icon: Icons.audio_file_rounded,
                iconBg: c.accentSoft,
                iconColor: c.accent,
                title: 'Seleccionar archivos de audio',
                subtitle: 'Elige una o varias canciones (MP3, FLAC, M4A, WAV, OGG)',
                onTap: () async {
                  final count = await library.importFiles();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    if (count > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$count canciones añadidas a Aura Music'),
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              _ImportOptionCard(
                icon: Icons.folder_open_rounded,
                iconBg: c.amberSoft,
                iconColor: c.amber,
                title: 'Importar carpeta completa',
                subtitle: 'Conserva acceso directo a toda una carpeta de música',
                onTap: () async {
                  final count = await library.importFolder();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    if (count > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$count canciones importadas desde la carpeta'),
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              _ImportOptionCard(
                icon: Icons.cloud_download_rounded,
                iconBg: c.sageSoft,
                iconColor: c.sage,
                title: 'Descargar desde URL (yt-dlp)',
                subtitle: 'Extrae audio directo con yt-dlp-ejs y Rust QuickJS-ng',
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DownloadUrlScreen(),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportOptionCard extends StatelessWidget {
  const _ImportOptionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Material(
      color: c.surfaceElevated,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
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
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: c.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
