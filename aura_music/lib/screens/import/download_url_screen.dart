// =============================================================================
// download_url_screen.dart — Pantalla dedicada de descarga con yt-dlp + Rust
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Proporciona una pantalla separada siguiendo la estética Acoustic Warmth
//   para descargar audio directamente desde enlaces (YouTube / URLs) usando:
//   - Intérprete Python minimalista (Chaquopy + yt-dlp --no-deps + yt-dlp-ejs).
//   - Runtime JavaScript QuickJS-ng compilado en Rust (`libaura_qjs.so`).
//   - Verificación e incrustación nativa de etiquetas en Rust (`lofty`).
//   Una vez completada la descarga, importa la pista a SQLite y comienza a
//   reproducirla de inmediato en ExoPlayer abriendo FullPlayerScreen.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../player/full_player_screen.dart';
import '../settings/settings_screen.dart';

class DownloadUrlScreen extends StatefulWidget {
  const DownloadUrlScreen({super.key});

  @override
  State<DownloadUrlScreen> createState() => _DownloadUrlScreenState();
}

class _DownloadUrlScreenState extends State<DownloadUrlScreen> {
  final _urlCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  YtDownloadFormat _selectedFormat = YtDownloadFormat.best;
  YtEngineStatus? _engineStatus;
  bool _loadingStatus = true;
  bool _showRawError = false;

  @override
  void initState() {
    super.initState();
    _loadEngineStatus();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEngineStatus() async {
    try {
      final status = await context.read<LibraryProvider>().fetchYtEngineStatus();
      if (!mounted) return;
      setState(() {
        _engineStatus = status;
        _loadingStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStatus = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      setState(() {
        _urlCtrl.text = text;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _startDownload() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _showRawError = false);

    final library = context.read<LibraryProvider>();
    final player = context.read<PlayerProvider>();
    final track = await library.downloadTrackFromUrl(
      _urlCtrl.text.trim(),
      format: _selectedFormat,
    );

    if (!mounted) return;
    if (track == null) {
      // Si la descarga falló tras arrancar Python, actualiza el diagnóstico
      _loadEngineStatus();
      return;
    }

    await player.playQueue([track], startIndex: 0);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const FullPlayerScreen(),
      ),
    );
  }

  Future<void> _copyRawError(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Error técnico en crudo copiado al portapapeles'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final library = context.watch<LibraryProvider>();
    final isDownloading = library.isDownloadingUrl;
    final progress = library.downloadProgress;
    final errorMsg = library.downloadError;
    final rawError = library.downloadRawError;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Descargar desde URL'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
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
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: c.accentSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.link_rounded,
                              color: c.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Motor directo yt-dlp + Rust',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Sin instancias públicas ni escaneo global',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _urlCtrl,
                        enabled: !isDownloading,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                        validator: (value) {
                          final trimmed = (value ?? '').trim();
                          if (trimmed.isEmpty) {
                            return 'Pega un enlace de YouTube o audio válido';
                          }
                          if (!trimmed.startsWith('http://') &&
                              !trimmed.startsWith('https://')) {
                            return 'El enlace debe iniciar con https:// o http://';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'https://youtu.be/...',
                          hintStyle: TextStyle(color: c.textMuted),
                          prefixIcon: Icon(
                            Icons.play_circle_outline_rounded,
                            color: c.textSecondary,
                          ),
                          suffixIcon: IconButton(
                            onPressed: isDownloading ? null : _pasteFromClipboard,
                            icon: Icon(
                              Icons.content_paste_rounded,
                              color: c.textSecondary,
                            ),
                            tooltip: 'Pegar enlace',
                          ),
                          filled: true,
                          fillColor: c.surface,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: c.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: c.accent,
                              width: 1.6,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: c.errorText,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: c.errorText,
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Formato de audio preferido',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _FormatOption(
                            label: 'Auto (Mejor)',
                            selected: _selectedFormat == YtDownloadFormat.best,
                            enabled: !isDownloading,
                            onTap: () => setState(
                              () => _selectedFormat = YtDownloadFormat.best,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FormatOption(
                            label: 'M4A / AAC',
                            selected: _selectedFormat == YtDownloadFormat.m4a,
                            enabled: !isDownloading,
                            onTap: () => setState(
                              () => _selectedFormat = YtDownloadFormat.m4a,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FormatOption(
                            label: 'WebM / Opus',
                            selected: _selectedFormat == YtDownloadFormat.opus,
                            enabled: !isDownloading,
                            onTap: () => setState(
                              () => _selectedFormat = YtDownloadFormat.opus,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isDownloading && progress != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
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
                                strokeWidth: 2.4,
                                color: c.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                progress.message.isNotEmpty
                                    ? progress.message
                                    : 'Procesando enlace...',
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
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: progress.percent > 0
                                ? (progress.percent / 100.0).clamp(0.0, 1.0)
                                : null,
                            minHeight: 7,
                            backgroundColor: c.surface,
                            valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                          ),
                        ),
                        if (progress.totalBytes > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${progress.percent.toStringAsFixed(1)}% · ${_formatBytes(progress.downloadedBytes)} / ${_formatBytes(progress.totalBytes)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (!isDownloading && errorMsg != null && errorMsg.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.errorBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.errorBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.error_outline_rounded,
                                size: 20,
                                color: c.errorText,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                errorMsg,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.4,
                                  color: c.errorText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (rawError != null && rawError.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => setState(
                                  () => _showRawError = !_showRawError,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.errorText,
                                  side: BorderSide(color: c.errorBorder),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: Icon(
                                  _showRawError
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.terminal_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  _showRawError
                                      ? 'Ocultar error en crudo'
                                      : 'Ver error técnico en crudo',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _copyRawError(rawError),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.errorText,
                                  side: BorderSide(color: c.errorBorder),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.copy_rounded, size: 15),
                                label: const Text(
                                  'Copiar log',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_showRawError) ...[
                            const SizedBox(height: 10),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 240),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: c.terminalBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Scrollbar(
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    rawError,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: c.terminalText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: isDownloading ? null : _startDownload,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: Icon(
                    isDownloading
                        ? Icons.downloading_rounded
                        : Icons.download_for_offline_rounded,
                  ),
                  label: Text(
                    isDownloading
                        ? 'Descargando y verificando...'
                        : 'Descargar y reproducir',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Arquitectura nativa activa',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                              if (mounted) {
                                _loadEngineStatus();
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: c.accent,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            icon: const Icon(Icons.system_update_alt_rounded,
                                size: 15),
                            label: const Text(
                              'Actualizar',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (_loadingStatus)
                        Text(
                          'Consultando runtime Python + Rust...',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        )
                      else if (_engineStatus != null)
                        Text(
                          _engineStatus!.pythonStarted ||
                                  _engineStatus!.ytDlpVersion.isNotEmpty
                              ? 'yt-dlp ${_engineStatus!.ytDlpVersion} · ejs ${_engineStatus!.ejsVersion}'
                                  '${_engineStatus!.pythonVersion.isNotEmpty ? " · Python ${_engineStatus!.pythonVersion}" : ""}\n'
                                  'JS Runtime: Rust QuickJS-ng (${_engineStatus!.quickjsReady ? "listo" : "pendiente"})\n'
                                  'Audio/Tags: ${_engineStatus!.audioProcessor} (${_engineStatus!.arch}) · Auto-actualizador ${_engineStatus!.autoUpdateEnabled ? "ON" : "OFF"}'
                              : 'Python 3.11 + yt-dlp + ejs (inicio diferido al descargar)\n'
                                  'JS Runtime: Rust QuickJS-ng (${_engineStatus!.quickjsReady ? "listo" : "pendiente"})\n'
                                  'Audio/Tags: ${_engineStatus!.audioProcessor} (${_engineStatus!.arch}) · Auto-actualizador ${_engineStatus!.autoUpdateEnabled ? "ON" : "OFF"}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: c.textSecondary,
                          ),
                        )
                      else
                        Text(
                          'yt-dlp + yt-dlp-ejs + Rust QuickJS-ng + Rust Lofty (32/64 bits)',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? c.chipSelectedBg : c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? c.chipSelectedBg : c.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? c.chipSelectedFg : c.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
