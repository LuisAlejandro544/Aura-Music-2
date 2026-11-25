// =============================================================================
// edit_track_metadata_screen.dart — Editor de metadatos y carátula WebP
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Pantalla dedicada para editar título, artista, álbum y carpeta/colección
//   de cualquier canción importada, además de elegir una carátula personalizada
//   desde la galería del teléfono (vía image_picker).
//   Cada imagen seleccionada se convierte en segundo plano en Kotlin nativo a
//   formato WebP con compresión máxima sin pérdida de calidad, guardándose de
//   forma persistente al confirmar los cambios y actualizando en vivo SQLite,
//   la biblioteca, el reproductor y la notificación de MediaSession.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/artwork_view.dart';

class EditTrackMetadataScreen extends StatefulWidget {
  const EditTrackMetadataScreen({
    super.key,
    required this.track,
  });

  final AudioTrack track;

  @override
  State<EditTrackMetadataScreen> createState() =>
      _EditTrackMetadataScreenState();
}

class _EditTrackMetadataScreenState extends State<EditTrackMetadataScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  late final TextEditingController _albumCtrl;
  late final TextEditingController _folderCtrl;

  LosslessWebpResult? _pendingWebp;
  bool _restoreOriginalArtwork = false;
  bool _isConvertingImage = false;
  bool _isSaving = false;
  String? _conversionError;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.track.title);
    _artistCtrl = TextEditingController(text: widget.track.artist);
    _albumCtrl = TextEditingController(text: widget.track.album);
    _folderCtrl = TextEditingController(text: widget.track.folderName);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  String? get _effectivePreviewArtwork {
    if (_restoreOriginalArtwork) {
      return widget.track.originalArtworkPath;
    }
    return _pendingWebp?.webpPath ?? widget.track.artworkPath;
  }

  bool get _canRestoreOriginal {
    if (_pendingWebp != null) return true;
    if (_restoreOriginalArtwork) return false;
    return widget.track.hasCustomWebpArtwork ||
        (widget.track.artworkPath != widget.track.originalArtworkPath);
  }

  Future<void> _pickGalleryArtwork() async {
    if (_isConvertingImage || _isSaving) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (picked == null || !mounted) return;

      setState(() {
        _isConvertingImage = true;
        _conversionError = null;
      });

      final library = context.read<LibraryProvider>();
      final webpResult = await library.convertGalleryImageToLosslessWebp(
        sourcePath: picked.path,
        trackId: widget.track.id,
      );

      if (!mounted) return;
      setState(() {
        _pendingWebp = webpResult;
        _restoreOriginalArtwork = false;
        _isConvertingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConvertingImage = false;
        _conversionError = 'No se pudo procesar la imagen a WebP: $e';
      });
    }
  }

  void _restoreOriginal() {
    setState(() {
      _pendingWebp = null;
      _restoreOriginalArtwork = true;
      _conversionError = null;
    });
  }

  Future<void> _saveChanges() async {
    if (_isSaving || _isConvertingImage) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      final library = context.read<LibraryProvider>();
      final player = context.read<PlayerProvider>();

      final updated = await library.updateTrackMetadata(
        track: widget.track,
        title: _titleCtrl.text,
        artist: _artistCtrl.text,
        album: _albumCtrl.text,
        folderName: _folderCtrl.text,
        pendingWebpPath: _pendingWebp?.webpPath,
        restoreOriginalArtwork: _restoreOriginalArtwork,
      );

      await player.syncUpdatedTrack(updated);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Metadatos actualizados correctamente'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar metadatos: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final previewPath = _effectivePreviewArtwork;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Editar metadatos'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _isSaving || _isConvertingImage ? null : _saveChanges,
              style: TextButton.styleFrom(
                foregroundColor: c.accent,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sección de carátula personalizada WebP sin pérdida
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: c.surfaceElevated,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _pickGalleryArtwork,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ArtworkView(
                              artworkPath: previewPath,
                              seed:
                                  '${_albumCtrl.text}_${_titleCtrl.text}',
                              size: 164,
                              borderRadius: 24,
                              showShadow: true,
                            ),
                            if (_isConvertingImage)
                              Container(
                                width: 164,
                                height: 164,
                                decoration: BoxDecoration(
                                  color: c.scrim,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.8,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'Convirtiendo a WebP...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_pendingWebp != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: c.sageSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_pendingWebp!.isLossless ? 'WebP sin pérdida' : 'WebP máxima calidad'} · ${_pendingWebp!.formattedSize} · ${_pendingWebp!.width}×${_pendingWebp!.height}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c.sage,
                            ),
                          ),
                        )
                      else if (!_restoreOriginalArtwork &&
                          widget.track.hasCustomWebpArtwork)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: c.sageSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Carátula personalizada WebP activa',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c.sage,
                            ),
                          ),
                        ),
                      if (_conversionError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _conversionError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.errorText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isConvertingImage || _isSaving
                                  ? null
                                  : _pickGalleryArtwork,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: c.textPrimary,
                                backgroundColor: c.surface,
                                side: BorderSide(color: c.border),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(
                                Icons.photo_library_rounded,
                                size: 19,
                              ),
                              label: const Text(
                                'Elegir de galería',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          if (_canRestoreOriginal) ...[
                            const SizedBox(width: 10),
                            IconButton.filledTonal(
                              onPressed: _isConvertingImage || _isSaving
                                  ? null
                                  : _restoreOriginal,
                              style: IconButton.styleFrom(
                                backgroundColor: c.surface,
                                foregroundColor: c.textPrimary,
                              ),
                              icon: const Icon(Icons.restore_rounded),
                              tooltip: 'Restaurar carátula original',
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Se convierte automáticamente a WebP a máxima compresión sin pérdida para ahorrar espacio sin bajar la calidad.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                _MetadataField(
                  controller: _titleCtrl,
                  label: 'Título de la canción',
                  hint: 'Nombre de la pista',
                  icon: Icons.music_note_rounded,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'El título no puede estar vacío';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _MetadataField(
                  controller: _artistCtrl,
                  label: 'Artista',
                  hint: 'Artista desconocido',
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 14),
                _MetadataField(
                  controller: _albumCtrl,
                  label: 'Álbum',
                  hint: 'Sin álbum',
                  icon: Icons.album_rounded,
                ),
                const SizedBox(height: 14),
                _MetadataField(
                  controller: _folderCtrl,
                  label: 'Carpeta / Colección',
                  hint: 'Música Importada',
                  icon: Icons.folder_rounded,
                  textInputAction: TextInputAction.done,
                ),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed:
                      _isSaving || _isConvertingImage ? null : _saveChanges,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _isSaving ? 'Guardando...' : 'Guardar cambios',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
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

class _MetadataField extends StatelessWidget {
  const _MetadataField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.validator,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          validator: validator,
          textInputAction: textInputAction,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: c.textMuted),
            prefixIcon: Icon(icon, color: c.textSecondary, size: 20),
            filled: true,
            fillColor: c.surfaceElevated,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: c.accent, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: c.errorText),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: c.errorText, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
