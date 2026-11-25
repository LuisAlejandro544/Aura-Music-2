// =============================================================================
// lib.rs — Motor nativo Rust (JNI) de apoyo para yt-dlp en Aura Music
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Provee funciones nativas de alto rendimiento en Rust (compilado como
//   libaura_yt_rust.so para armeabi-v7a y arm64-v8a) invocadas desde Kotlin:
//   1. `parse_and_canonicalize_media_url`: valida y limpia URLs de YouTube
//      (youtu.be, watch, shorts, music.youtube.com), elimina parámetros de
//      rastreo (`si`, `pp`, `feature`) y extrae el videoId antes de pasar la
//      solicitud a yt-dlp.
//   2. `verify_and_tag_audio`: inspecciona los bytes mágicos del archivo
//      descargado (rechazando respuestas HTML corruptas o vacías), extrae
//      propiedades reales de audio (sampleRateHz, bitrateKbps, canales,
//      duración) usando `lofty` en todas las versiones de Android (incluyendo
//      Android 9-11) e incrusta etiquetas ID3/MP4/Vorbis + carátula directamente
//      sin necesitar FFmpeg GPL.
// =============================================================================

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;
use lofty::config::WriteOptions;
use lofty::file::{AudioFile, FileType, TaggedFileExt};
use lofty::picture::{MimeType, Picture, PictureType};
use lofty::probe::Probe;
use lofty::tag::{Accessor, Tag};
use serde::Serialize;
use std::fs::File;
use std::io::Read;
use std::path::Path;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct UrlParseResult {
    valid: bool,
    canonical_url: String,
    video_id: Option<String>,
    host: String,
    is_youtube: bool,
    error: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AudioInspectAndTagResult {
    valid: bool,
    container: String,
    mime_type: String,
    duration_ms: u64,
    bitrate_kbps: u32,
    sample_rate_hz: u32,
    channels: u8,
    tags_embedded: bool,
    artwork_embedded: bool,
    file_size_bytes: u64,
    error: Option<String>,
}

fn is_valid_yt_id(id: &str) -> bool {
    id.len() == 11
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

pub fn parse_and_canonicalize_media_url(raw: &str) -> UrlParseResult {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return UrlParseResult {
            valid: false,
            canonical_url: String::new(),
            video_id: None,
            host: String::new(),
            is_youtube: false,
            error: Some("La URL está vacía".to_string()),
        };
    }

    let without_scheme = if let Some(rest) = trimmed.strip_prefix("https://") {
        rest
    } else if let Some(rest) = trimmed.strip_prefix("http://") {
        rest
    } else {
        return UrlParseResult {
            valid: false,
            canonical_url: String::new(),
            video_id: None,
            host: String::new(),
            is_youtube: false,
            error: Some("La URL debe empezar con http:// o https://".to_string()),
        };
    };

    let (authority_and_path, query_part) = match without_scheme.split_once('?') {
        Some((left, right)) => (left, Some(right)),
        None => (without_scheme, None),
    };

    let authority_and_path = authority_and_path
        .split('#')
        .next()
        .unwrap_or(authority_and_path);
    let (host_raw, path_raw) = match authority_and_path.split_once('/') {
        Some((h, p)) => (h, p),
        None => (authority_and_path, ""),
    };

    let host = host_raw.to_ascii_lowercase();
    if host.is_empty() || !host.contains('.') {
        return UrlParseResult {
            valid: false,
            canonical_url: String::new(),
            video_id: None,
            host,
            is_youtube: false,
            error: Some("Dominio inválido en la URL".to_string()),
        };
    }

    let is_youtube = host == "youtu.be"
        || host == "youtube.com"
        || host.ends_with(".youtube.com")
        || host == "youtube-nocookie.com"
        || host.ends_with(".youtube-nocookie.com");

    let mut video_id: Option<String> = None;

    if is_youtube {
        if host == "youtu.be" {
            let candidate = path_raw.split('/').next().unwrap_or("").trim();
            if is_valid_yt_id(candidate) {
                video_id = Some(candidate.to_string());
            }
        } else if let Some(rest) = path_raw.strip_prefix("shorts/") {
            let candidate = rest.split('/').next().unwrap_or("").trim();
            if is_valid_yt_id(candidate) {
                video_id = Some(candidate.to_string());
            }
        } else if let Some(rest) = path_raw.strip_prefix("embed/") {
            let candidate = rest.split('/').next().unwrap_or("").trim();
            if is_valid_yt_id(candidate) {
                video_id = Some(candidate.to_string());
            }
        } else if let Some(rest) = path_raw.strip_prefix("live/") {
            let candidate = rest.split('/').next().unwrap_or("").trim();
            if is_valid_yt_id(candidate) {
                video_id = Some(candidate.to_string());
            }
        }

        if video_id.is_none() {
            if let Some(q) = query_part {
                for pair in q.split('&') {
                    if let Some((k, v)) = pair.split_once('=') {
                        if k == "v" && is_valid_yt_id(v) {
                            video_id = Some(v.to_string());
                            break;
                        }
                    }
                }
            }
        }

        if let Some(ref vid) = video_id {
            return UrlParseResult {
                valid: true,
                canonical_url: format!("https://www.youtube.com/watch?v={vid}"),
                video_id: Some(vid.clone()),
                host,
                is_youtube: true,
                error: None,
            };
        }
    }

    UrlParseResult {
        valid: true,
        canonical_url: trimmed.to_string(),
        video_id,
        host,
        is_youtube,
        error: None,
    }
}

pub fn verify_container_magic(head: &[u8]) -> Result<(&'static str, &'static str), String> {
    if head.len() < 12 {
        return Err("Archivo demasiado pequeño o truncado".to_string());
    }

    // Detectar páginas HTML o JSON de error devueltas por servidores bloqueados
    let lower_ascii = String::from_utf8_lossy(&head[..head.len().min(64)]).to_ascii_lowercase();
    let trimmed_ascii = lower_ascii.trim_start();
    if trimmed_ascii.starts_with("<!doctype")
        || trimmed_ascii.starts_with("<html")
        || trimmed_ascii.starts_with("{\"error")
    {
        return Err("El servidor devolvió datos HTML/JSON corruptos en lugar de audio".to_string());
    }

    // MP4 / M4A: bytes 4..8 == "ftyp"
    if &head[4..8] == b"ftyp" {
        return Ok(("M4A", "audio/mp4"));
    }
    // WebM / Matroska EBML header: 1A 45 DF A3
    if head[0] == 0x1A && head[1] == 0x45 && head[2] == 0xDF && head[3] == 0xA3 {
        return Ok(("WEBM", "audio/webm"));
    }
    // Ogg / Opus: "OggS"
    if &head[0..4] == b"OggS" {
        return Ok(("OGG", "audio/ogg"));
    }
    // FLAC: "fLaC"
    if &head[0..4] == b"fLaC" {
        return Ok(("FLAC", "audio/flac"));
    }
    // WAV: "RIFF....WAVE"
    if &head[0..4] == b"RIFF" && &head[8..12] == b"WAVE" {
        return Ok(("WAV", "audio/wav"));
    }
    // MP3: "ID3" o frame sync 0xFF 0xE0..0xFF
    if &head[0..3] == b"ID3" || (head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
        return Ok(("MP3", "audio/mpeg"));
    }

    Err("Cabecera de contenedor de audio no reconocida o corrupta".to_string())
}

fn detect_image_mime(bytes: &[u8]) -> Option<MimeType> {
    if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        // Lofty 0.22 MimeType::Unknown("image/webp") or fallback if supported
        return Some(MimeType::Unknown("image/webp".to_string()));
    }
    if bytes.len() >= 8 && &bytes[0..8] == b"\x89PNG\r\n\x1a\n" {
        return Some(MimeType::Png);
    }
    if bytes.len() >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
        return Some(MimeType::Jpeg);
    }
    None
}

fn mime_for_filetype(ft: FileType, fallback_mime: &str) -> String {
    match ft {
        FileType::Mp4 => "audio/mp4".to_string(),
        FileType::Mpeg => "audio/mpeg".to_string(),
        FileType::Flac => "audio/flac".to_string(),
        FileType::Opus => "audio/opus".to_string(),
        FileType::Vorbis => "audio/ogg".to_string(),
        FileType::Wav => "audio/wav".to_string(),
        _ => fallback_mime.to_string(),
    }
}

pub fn verify_and_tag_audio_file(
    audio_path: &str,
    title: &str,
    artist: &str,
    album: &str,
    artwork_path: Option<&str>,
) -> AudioInspectAndTagResult {
    let path = Path::new(audio_path);
    let metadata = match std::fs::metadata(path) {
        Ok(m) => m,
        Err(e) => {
            return AudioInspectAndTagResult {
                valid: false,
                container: String::new(),
                mime_type: String::new(),
                duration_ms: 0,
                bitrate_kbps: 0,
                sample_rate_hz: 0,
                channels: 0,
                tags_embedded: false,
                artwork_embedded: false,
                file_size_bytes: 0,
                error: Some(format!("No existe el archivo descargado: {e}")),
            };
        }
    };

    let file_size = metadata.len();
    let mut head = [0u8; 64];
    let read_len = match File::open(path).and_then(|mut f| f.read(&mut head)) {
        Ok(n) => n,
        Err(e) => {
            return AudioInspectAndTagResult {
                valid: false,
                container: String::new(),
                mime_type: String::new(),
                duration_ms: 0,
                bitrate_kbps: 0,
                sample_rate_hz: 0,
                channels: 0,
                tags_embedded: false,
                artwork_embedded: false,
                file_size_bytes: file_size,
                error: Some(format!("Error leyendo archivo descargado: {e}")),
            };
        }
    };

    let (container_label, fallback_mime) = match verify_container_magic(&head[..read_len]) {
        Ok(v) => v,
        Err(err_msg) => {
            return AudioInspectAndTagResult {
                valid: false,
                container: String::new(),
                mime_type: String::new(),
                duration_ms: 0,
                bitrate_kbps: 0,
                sample_rate_hz: 0,
                channels: 0,
                tags_embedded: false,
                artwork_embedded: false,
                file_size_bytes: file_size,
                error: Some(err_msg),
            };
        }
    };

    let mut duration_ms = 0u64;
    let mut bitrate_kbps = 0u32;
    let mut sample_rate_hz = 0u32;
    let mut channels = 0u8;
    let mut final_mime = fallback_mime.to_string();
    let mut tags_embedded = false;
    let mut artwork_embedded = false;

    if let Ok(probe) = Probe::open(path).and_then(|p| p.guess_file_type()) {
        if let Ok(mut tagged_file) = probe.read() {
            let ft = tagged_file.file_type();
            final_mime = mime_for_filetype(ft, fallback_mime);
            let props = tagged_file.properties();
            duration_ms = props.duration().as_millis() as u64;
            bitrate_kbps = props.audio_bitrate().or_else(|| props.overall_bitrate()).unwrap_or(0);
            sample_rate_hz = props.sample_rate().unwrap_or(0);
            channels = props.channels().unwrap_or(0);

            let tag_type = tagged_file.primary_tag_type();
            if tagged_file.primary_tag_mut().is_none() {
                tagged_file.insert_tag(Tag::new(tag_type));
            }
            if let Some(tag) = tagged_file.primary_tag_mut() {
                if !title.trim().is_empty() {
                    tag.set_title(title.trim().to_string());
                }
                if !artist.trim().is_empty() {
                    tag.set_artist(artist.trim().to_string());
                }
                if !album.trim().is_empty() {
                    tag.set_album(album.trim().to_string());
                }

                if let Some(art_p) = artwork_path.filter(|s| !s.trim().is_empty()) {
                    if let Ok(art_bytes) = std::fs::read(art_p) {
                        if let Some(img_mime) = detect_image_mime(&art_bytes) {
                            let pic = Picture::new_unchecked(
                                PictureType::CoverFront,
                                Some(img_mime),
                                None,
                                art_bytes,
                            );
                            tag.push_picture(pic);
                            artwork_embedded = true;
                        }
                    }
                }

                if tagged_file
                    .save_to_path(path, WriteOptions::default())
                    .is_ok()
                {
                    tags_embedded = true;
                } else {
                    artwork_embedded = false;
                }
            }
        }
    }

    AudioInspectAndTagResult {
        valid: true,
        container: container_label.to_string(),
        mime_type: final_mime,
        duration_ms,
        bitrate_kbps,
        sample_rate_hz,
        channels,
        tags_embedded,
        artwork_embedded,
        file_size_bytes: file_size,
        error: None,
    }
}

fn jstring_to_rust(env: &mut JNIEnv, input: &JString) -> String {
    env.get_string(input)
        .map(String::from)
        .unwrap_or_default()
}

fn rust_to_jstring(env: &mut JNIEnv, value: &str) -> jstring {
    env.new_string(value)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_com_auramusic_player_AuraRustYtBridge_nativeEngineInfo(
    mut env: JNIEnv,
    _class: JClass,
) -> jstring {
    let payload = serde_json::json!({
        "rustCrate": "aura_yt_engine",
        "jsRuntime": "rquickjs (QuickJS-ng 0.12.0, MIT)",
        "audioProcessor": "lofty 0.22 (MIT/Apache-2.0)",
        "arch": std::env::consts::ARCH,
    });
    rust_to_jstring(&mut env, &payload.to_string())
}

#[no_mangle]
pub extern "system" fn Java_com_auramusic_player_AuraRustYtBridge_nativeParseMediaUrl(
    mut env: JNIEnv,
    _class: JClass,
    raw_url: JString,
) -> jstring {
    let url = jstring_to_rust(&mut env, &raw_url);
    let parsed = parse_and_canonicalize_media_url(&url);
    let json = serde_json::to_string(&parsed).unwrap_or_else(|_| "{}".to_string());
    rust_to_jstring(&mut env, &json)
}

#[no_mangle]
pub extern "system" fn Java_com_auramusic_player_AuraRustYtBridge_nativeVerifyAndTagAudio(
    mut env: JNIEnv,
    _class: JClass,
    audio_path: JString,
    title: JString,
    artist: JString,
    album: JString,
    artwork_path: JString,
) -> jstring {
    let audio_p = jstring_to_rust(&mut env, &audio_path);
    let title_s = jstring_to_rust(&mut env, &title);
    let artist_s = jstring_to_rust(&mut env, &artist);
    let album_s = jstring_to_rust(&mut env, &album);
    let art_s = jstring_to_rust(&mut env, &artwork_path);

    let result = verify_and_tag_audio_file(
        &audio_p,
        &title_s,
        &artist_s,
        &album_s,
        if art_s.is_empty() { None } else { Some(art_s.as_str()) },
    );
    let json = serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string());
    rust_to_jstring(&mut env, &json)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonicalizes_youtu_be_share_links() {
        let res = parse_and_canonicalize_media_url(
            "https://youtu.be/zzWKwvBie7E?si=jaCYp8ZHgQa1k__6",
        );
        assert!(res.valid);
        assert!(res.is_youtube);
        assert_eq!(res.video_id.as_deref(), Some("zzWKwvBie7E"));
        assert_eq!(
            res.canonical_url,
            "https://www.youtube.com/watch?v=zzWKwvBie7E"
        );
    }

    #[test]
    fn rejects_html_payload_magic() {
        let html = b"<!DOCTYPE html><html><body>403 Forbidden</body></html>";
        assert!(verify_container_magic(html).is_err());
    }

    #[test]
    fn accepts_m4a_and_webm_magic() {
        let m4a = b"\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00";
        assert_eq!(verify_container_magic(m4a).unwrap().0, "M4A");

        let webm = [0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x00, 0x00, 0x00];
        assert_eq!(verify_container_magic(&webm).unwrap().0, "WEBM");
    }
}
